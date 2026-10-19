import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'driver_read_commands.dart';
import 'flutter_driver_session.dart';
import 'timeline_observation.dart';

Future<Map<String, dynamic>> waitForSnapshot(
  FlutterDriverSession driver,
  bool Function(Map<String, dynamic>) condition,
  String stage,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await driver.readSnapshot();
    if (condition(last)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  final navigation = last?['navigation'] as Map?;
  final workspace = last?['workspace'] as Map?;
  final composer = navigation?['newThreadComposer'] as Map?;
  final persistence = last?['persistence'] as Map?;
  throw StateError(
    'timed out at $stage: draftLength=${(composer?['draft'] as String?)?.length}, '
    'phase=${composer?['phase']}, busy=${workspace?['isBusy']}, '
    'sync=${workspace?['syncState']}, saving=${persistence?['kind']}',
  );
}

String selectedThread(Map<String, dynamic> snapshot) =>
    (snapshot['navigation'] as Map)['selectedThreadId'] as String;

/// 当前展示代次的已加载身份，并核对内部一致性。
///
/// 没有旧 96 条窗口容量：已加载消息随访问页增长是明示取舍，这里只要求身份唯一、
/// `itemCount`/`itemIds`/`items` 一致，缺失字段是观测失败而不是“空窗口”。
TimelineObservation loadedWindow(Map<String, dynamic> snapshot) {
  final timeline = TimelineObservation.parse(snapshot);
  timeline.requireConsistentIds();
  if (timeline.itemIds.toSet().length != timeline.itemCount) {
    throw StateError('timeline exposes duplicate identities');
  }
  return timeline;
}

/// Fixture session 1 replies with `Long body 1: ` + `content ` repeated 16_384
/// times (see `gui_stress_script`), so the complete assistant body is
/// 13 + 16_384 * 8 = 131_085 UTF-8 bytes (ASCII markers).
///
/// 产品展示正文预算只有 32 KiB，所以行内必须是有界预览；真实总长由详情引用给出，
/// 完整正文只能由用户显式打开详情查看器逐块读取并复制。
const _largeSessionPrefix = 'Long body 1: ';
const _largeRepeats = 16384;

/// 产品动态正文展示预算（`pl-studio-runtime` 的 `PRODUCT_PREVIEW_BYTES`）。
const _productPreviewBudgetBytes = 32 * 1024;
const _largeSessionCharacters = 131085;

/// The longest canonical item preview, or null when none is available.
///
/// The multi-item stress fixture delivers its large reply as one message, so the
/// longest item is that assistant body.
TimelineItemObservation? _largestAssistantBody(TimelineObservation timeline) {
  TimelineItemObservation? best;
  for (final item in timeline.items) {
    if (best == null || item.text.length > best.text.length) best = item;
  }
  return best;
}

bool settled(Map<String, dynamic> snapshot, String threadId) {
  final workspace = snapshot['workspace'];
  final persistence = snapshot['persistence'];
  final timeline = TimelineObservation.optional(snapshot);
  return snapshot['navigation'] is Map &&
      (snapshot['navigation'] as Map)['selectedThreadId'] == threadId &&
      workspace is Map &&
      workspace['threadId'] == threadId &&
      workspace['syncState'] == 'ready' &&
      workspace['isBusy'] == false &&
      (workspace['usage'] as Map)['outputTokens'] is num &&
      (workspace['usage'] as Map)['outputTokens'] >= 5 &&
      persistence is Map &&
      persistence['kind'] == 'ready' &&
      persistence['pendingCommits'] == 0 &&
      timeline != null &&
      timeline.ready &&
      timeline.itemCount >= 2;
}

Future<void> main(List<String> args) async {
  if (args.length != 5) {
    stderr.writeln(
      'usage: stress_sessions.dart VM_URL COUNT PROMPT_PREFIX REPORT_FILE STAGE_FILE',
    );
    exitCode = 64;
    return;
  }
  final count = int.parse(args[1]);
  final report = File(args[3]);
  final stage = File(args[4]);
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  try {
    await stage.writeAsString('initial');
    final first = await waitForSnapshot(
      driver,
      (snapshot) =>
          snapshot['navigation'] is Map &&
          (snapshot['navigation'] as Map)['selectedThreadId'] is String &&
          (snapshot['workspace'] as Map?)?['isBusy'] == false,
      'first session',
    );
    final originalId = selectedThread(first);
    if (!settled(first, originalId)) {
      throw StateError('original stress session did not settle');
    }
    loadedWindow(first);
    final ids = <String>{originalId};
    final sessions = <Map<String, Object?>>[];
    for (var ordinal = 1; ordinal <= count; ordinal++) {
      await stage.writeAsString('session_$ordinal');
      await driver.tap(find.byValueKey('sidebar-new-session'));
      await stage.writeAsString('session_${ordinal}_new_tapped');
      await waitForSnapshot(
        driver,
        (snapshot) =>
            snapshot['navigation'] is Map &&
            (snapshot['navigation'] as Map)['selectedThreadId'] == null,
        'new session $ordinal',
      );
      await stage.writeAsString('session_${ordinal}_composer');
      // `FlutterDriver.waitFor` defaults to no timeout, so every finder wait here
      // carries an explicit deadline instead of hanging the host.
      await driver.waitFor(
        find.byValueKey('start-page-selectors'),
        timeout: const Duration(seconds: 30),
      );
      await driver.waitFor(
        find.byValueKey('composer-input'),
        timeout: const Duration(seconds: 30),
      );
      await driver.tap(find.byValueKey('composer-input'));
      final prompt = '${args[2]} $ordinal';
      await driver.enterText(prompt);
      await stage.writeAsString('session_${ordinal}_typed');
      await waitForSnapshot(
        driver,
        (snapshot) =>
            (snapshot['navigation'] as Map?)?['newThreadComposer'] is Map &&
            ((snapshot['navigation'] as Map)['newThreadComposer']
                    as Map)['draft'] ==
                prompt,
        'new session $ordinal draft',
      );
      await driver.waitFor(
        find.byValueKey('composer-submit'),
        timeout: const Duration(seconds: 15),
      );
      await driver.tap(find.byValueKey('composer-submit'));
      await stage.writeAsString('session_${ordinal}_submitted');
      final opened = await waitForSnapshot(
        driver,
        (snapshot) =>
            snapshot['navigation'] is Map &&
            (snapshot['navigation'] as Map)['selectedThreadId'] is String &&
            !ids.contains((snapshot['navigation'] as Map)['selectedThreadId']),
        'submit session $ordinal',
      );
      final id = selectedThread(opened);
      if (!ids.add(id)) throw StateError('duplicate session identity: $id');
      final finished = await waitForSnapshot(
        driver,
        (snapshot) =>
            settled(snapshot, id) &&
            (snapshot['sidebarDirectory'] as Map)['titles'] is Map &&
            ((snapshot['sidebarDirectory'] as Map)['titles'] as Map)[id] ==
                'Fixture Session $ordinal',
        'complete session $ordinal',
      );
      final timeline = loadedWindow(finished);
      if ((finished['sidebarDirectory'] as Map)['count'] < ids.length) {
        throw StateError('session directory omitted $id');
      }
      final body = _largestAssistantBody(timeline);
      final truncated = timeline.items
          .where((item) => item.textTruncated)
          .length;
      final detail = body?.detail('text');
      final record = <String, Object?>{
        'ordinal': ordinal,
        'threadId': id,
        'loadedItems': timeline.itemCount,
        'itemIds': timeline.itemIds,
        'mode': timeline.mode,
        'generation': timeline.generation,
        'hasOlder': timeline.hasOlder,
        'savedItems': timeline.items.where((item) => item.saved).length,
        'terminalItems': timeline.items.where((item) => item.terminal).length,
        'typedDetailRefs': timeline.items.fold<int>(
          0,
          (total, item) => total + item.details.length,
        ),
        'truncatedBodies': truncated,
        'previewTextBytes': timeline.items.fold<int>(
          0,
          (total, item) => total + item.textBytes,
        ),
        'assistantCharacters': body?.text.length,
        'assistantTextBytes': body?.textBytes,
        'assistantPreviewBytes': detail?.previewBytes,
        'assistantTextTotalBytes': detail?.totalBytes,
      };
      sessions.add(record);
      if (ordinal == 1) {
        // 32 KiB 产品预算：行内是有界预览，真实总长由详情引用给出；完整正文只能
        // 通过用户显式打开的查看器逐块读取并复制。
        final text = body?.text;
        if (body == null || text == null) {
          throw StateError('large response item was not observed');
        }
        if (!text.startsWith(_largeSessionPrefix)) {
          throw StateError('large response preview lost its fixture prefix');
        }
        if (truncated < 1 || !body.textTruncated) {
          throw StateError(
            'large response preview was not declared truncated: $truncated',
          );
        }
        if (detail == null || detail.totalBytes != _largeSessionCharacters) {
          throw StateError(
            'large response detail reference is wrong: '
            '${detail?.totalBytes} of $_largeSessionCharacters bytes',
          );
        }
        if (detail.previewBytes > _productPreviewBudgetBytes ||
            body.textBytes != detail.previewBytes) {
          throw StateError(
            'large response preview exceeded its budget: '
            '${detail.previewBytes} bytes / ${body.textBytes} delivered',
          );
        }
        final copy = await _copyDetailBody(
          driver,
          body.id,
          _largeSessionPrefix + 'content ' * _largeRepeats,
        );
        record['detailCopy'] = copy;
        if (copy['pass'] != true) {
          throw StateError('large response detail copy failed: $copy');
        }
      }
    }
    await stage.writeAsString('revisit_original');
    await driver.scrollUntilVisible(
      find.byValueKey('sidebar-project-tree'),
      find.byValueKey('thread-row-$originalId'),
      dyScroll: -200,
      timeout: const Duration(seconds: 45),
    );
    await driver.tap(find.byValueKey('thread-row-$originalId'));
    final revisited = await waitForSnapshot(
      driver,
      (snapshot) =>
          settled(snapshot, originalId) &&
          (snapshot['workspace'] as Map)['usage']['outputTokens'] >= 20000,
      'reopen original',
    );
    final revisitedTimeline = loadedWindow(revisited);
    await report.writeAsString(
      '${jsonEncode({'originalThreadId': originalId, 'originalReopened': true, 'originalLoadedItems': revisitedTimeline.itemCount, 'originalMode': revisitedTimeline.mode, 'originalHasOlder': revisitedTimeline.hasOlder, 'sessionCount': sessions.length, 'directoryCount': (revisited['sidebarDirectory'] as Map)['count'], 'sessions': sessions})}\n',
    );
    await stage.writeAsString('complete');
  } finally {
    await driver.close();
  }
}

/// 通过用户显式打开的真实详情查看器读取完整正文并复制，再与 canonical fixture 比对。
///
/// 只读 Driver 观察（`timeline-detail-text` / `clipboard-text`），不写剪贴板、不等固定
/// sleep；关闭后必须观察到查看器消失。
Future<Map<String, Object?>> _copyDetailBody(
  FlutterDriverSession driver,
  String itemId,
  String canonicalBody,
) async {
  final expectedHash = _fnv1a64(canonicalBody).toRadixString(16);
  final openKey = 'timeline-detail-open-$itemId-text';
  await driver.waitFor(
    find.byValueKey(openKey),
    timeout: const Duration(seconds: 30),
  );
  await driver.rawTap(
    find.byValueKey(openKey),
    timeout: const Duration(seconds: 30),
  );
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  DetailViewerRead? progress;
  var sawPartial = false;
  var viewerOpened = false;
  while (DateTime.now().isBefore(deadline)) {
    progress = await DetailViewerRead.read(driver.requestData);
    if (progress.open) viewerOpened = true;
    final characters = progress.characters;
    if (characters > 0 && characters < canonicalBody.length) sawPartial = true;
    if (characters >= canonicalBody.length) break;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final loadedCharacters = progress?.characters ?? 0;
  final loadedHash = progress?.hash;
  await driver.waitFor(
    find.byValueKey('timeline-detail-copy'),
    timeout: const Duration(seconds: 15),
  );
  await driver.rawTap(
    find.byValueKey('timeline-detail-copy'),
    timeout: const Duration(seconds: 30),
  );
  final clipboard = await ClipboardRead.read(driver.requestData);
  await driver.rawTap(
    find.byValueKey('timeline-detail-close'),
    timeout: const Duration(seconds: 30),
  );
  final closeDeadline = DateTime.now().add(const Duration(seconds: 15));
  var closed = false;
  while (DateTime.now().isBefore(closeDeadline)) {
    final decoded = await DetailViewerRead.read(driver.requestData);
    if (!decoded.open) {
      closed = true;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return <String, Object?>{
    'itemId': itemId,
    'expectedCharacters': canonicalBody.length,
    'expectedHash': expectedHash,
    // 理论块数（ceil(bytes/64KiB)），不是实际读了几块。
    'theoreticalChunks': (canonicalBody.length / (64 * 1024)).ceil(),
    'loadedCharacters': loadedCharacters,
    'loadedHash': loadedHash,
    'sawPartialChunk': sawPartial,
    'viewerOpened': viewerOpened,
    'clipboardCharacters': clipboard.characters,
    'clipboardHash': clipboard.hash,
    'viewerClosed': closed,
    'pass':
        viewerOpened &&
        loadedCharacters == canonicalBody.length &&
        loadedHash == expectedHash &&
        clipboard.characters == canonicalBody.length &&
        clipboard.hash == expectedHash &&
        closed,
  };
}

/// FNV-1a over the code units. Must stay identical to the Driver-side helper.
int _fnv1a64(String text) {
  var hash = 0xcbf29ce484222325;
  for (var index = 0; index < text.length; index += 1) {
    hash ^= text.codeUnitAt(index);
    hash = hash * 0x100000001b3;
  }
  return hash;
}
