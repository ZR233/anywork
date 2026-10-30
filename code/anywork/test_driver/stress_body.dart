import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'driver_read_commands.dart';
import 'flutter_driver_session.dart';
import 'scrolling_journey.dart';
import 'timeline_observation.dart';
// The multi-item stress journey already owns the session-switch flow helpers.
import 'stress_sessions.dart' show selectedThread, settled, waitForSnapshot;

/// Single-item long-body stress journey.
///
/// The fixture appends every increment to one stable item/part, so this journey
/// is recorded separately from the multi-item stress journey even though it
/// carries the same event count and nominal rate. It records only GUI-observed
/// timing and raw frame data: the synthetic account's own byte count lives in
/// the fixture report and is never treated as an FRB transfer measurement.
///
/// 断言只读当前展示事实：`timeline`（epoch/原子身份/append sequence/省略声明/详情引用）与
/// `timelineScroll`（当前标准 ScrollController 几何）。正文预览有界；超过单项预览
/// 预算的正文只在用户显式打开的详情查看器里逐块读取。
const _prompt = 'Stream the local GUI stress body fixture';
const _largePrompt = 'Stream the local GUI stress body large fixture';
const _expectedTokens = 20000;

/// Every fixture increment is `body-%05d ` (5 + 5 + 1 = 11 UTF-16 code units),
/// so the strict full reply is [_expectedBodyCharacters]. ASCII markers keep
/// characters and UTF-8 bytes equal.
const _bodyUnitCharacters = 11;
const _expectedBodyCharacters = _expectedTokens * _bodyUnitCharacters;

/// Large-body increments append [_largeBodyPad] `W` characters plus a trailing
/// space, so each increment is `_largeBodyUnitCharacters` (12 + pad) characters.
const _largeBodyPad = 20;
const _largeBodyUnitCharacters = 12 + _largeBodyPad;
const _expectedLargeBodyCharacters = _expectedTokens * _largeBodyUnitCharacters;

/// 产品动态正文的展示预算（`pl-studio-runtime` 的 `PRODUCT_PREVIEW_BYTES`）。
///
/// core 条目「结构 + 正文」共 256 KiB 是后端事实层预算，产品展示层再把它压到 32 KiB
/// 共享正文额度；工具参数/结果各自 4 KiB。这里断言的是**产品展示预算**。
const _productPreviewBudgetBytes = 32 * 1024;

/// Strict follow-up session prompt the body fixture script answers with a title.
const _secondSessionPrompt = 'Local GUI stress session 1';

/// Reading into the reply drags the pointer downward in fixed steps.
///
/// `FlutterDriver.scroll`/`scrollBy` take a *pointer* offset (`driver.dart`:
/// `[dx] and [dy] specify the total offset for the entire scrolling action`), so
/// a positive `dy` drags the finger down and reveals earlier content toward the
/// top of the history — the same convention `scrollUntilVisible` documents ("if
/// [item] is above, specify a positive value for [dyScroll]"). A negative `dy`
/// keeps pulling content from below and never leaves the pinned last line.
const _readScrollStep = 700.0;

/// Bounded read attempts: a view that refuses to leave the bottom becomes a
/// reported failure instead of an endless loop.
const _maxReadSteps = 24;

/// At least this many pixels of content must remain below the viewport for the
/// reading position to count as detached from the bottom.
const _minDetachedExtentAfter = 200.0;

Future<void> main(List<String> args) async {
  if (args.length != 4 && args.length != 5) {
    stderr.writeln(
      'usage: stress_body.dart VM_URL PROJECT_DIR OUTPUT_DIR COORD_DIR [SCENARIO]',
    );
    exitCode = 64;
    return;
  }
  // The same journey drives the default and the large-body scenario; the
  // scenario only selects the expected content and marker shape.
  final scenario = args.length == 5 ? args[4] : 'stress-body';
  final largeBody = scenario == 'stress-body-large';
  final expectedBodyCharacters = largeBody
      ? _expectedLargeBodyCharacters
      : _expectedBodyCharacters;
  final output = Directory(args[2]);
  final coord = Directory(args[3]);
  Future<void> mark(String value) =>
      File('${coord.path}/stress-body-stage').writeAsString(value);
  final FlutterDriverSession driver;
  try {
    driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  } catch (error, stackTrace) {
    // 连接失败是主错；这份报告写失败只作为次级事实报告，不能覆盖原始错误与栈。
    try {
      await _writeReport(output, <String, Object?>{
        'scenario': scenario,
        'verdict': 'pending',
        'status': 'failed',
        'stage': 'connect_failed',
        'error': error.toString(),
        'shutdownError': null,
      });
    } catch (reportError, reportStack) {
      stderr.writeln(
        'stress-body connect-failure report write failed: '
        '$reportError\n$reportStack',
      );
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
  var stage = 'connected';
  // Expose the GUI native process identity to the external resident-memory
  // sampler. The Driver's `pid` request is the only owner of that identity: the
  // launcher chain above the app (cargo/xtask/flutter) is not the GUI, so the
  // sampler consumes this file instead of guessing a process name. Missing this
  // file is missing evidence, never a journey failure, and the request happens
  // before `frame-start` so it cannot perturb the recorded frame window.
  try {
    final raw = await driver.requestData(
      'pid',
      timeout: const Duration(seconds: 15),
    );
    final decoded = jsonDecode(raw);
    final guiPid = decoded is Map ? decoded['pid'] : null;
    if (guiPid is int && guiPid > 0) {
      await File('${output.path}/gui-pid.txt').writeAsString('$guiPid\n');
    }
  } on Object {
    // Resident-memory sampling is optional evidence for the caller.
  }
  // Records both the coordinator marker and the stage reported in the summary, so
  // a failure never reports a coarser stage than the marker file.
  Future<void> markStage(String value) async {
    stage = value;
    await mark(value);
  }

  Object? failure;
  StackTrace? failureStack;
  String? shutdownError;
  Map<String, dynamic>? frames;
  final report = <String, Object?>{};
  final checks = <String, Object?>{};
  final findings = <String, Object?>{};
  final pendingEvidence = <String>[
    'the fixture account bytes come from the synthetic account stream and are '
        'never an FRB transfer measurement',
    'per-item and per-page preview budgets are backend limits: the text each '
        'displayed item carries grows with the pages this journey actually '
        'visited and is not a constant-memory claim',
  ];
  try {
    await mark(stage);
    await _openProject(driver, args[1]);
    stage = 'project_opened';
    await mark(stage);
    await driver.requestData(
      'frame-start',
      timeout: const Duration(seconds: 20),
    );
    final submittedAt = DateTime.now().millisecondsSinceEpoch;
    report['submittedAt'] = submittedAt;
    await _submit(driver, largeBody ? _largePrompt : _prompt);
    stage = 'prompt_submitted';
    await mark(stage);
    final streaming = await _waitFor(
      driver,
      (snapshot) => _streamingBodyObservation(snapshot) != null,
      'streaming',
      evidence: output,
    );
    final firstContentAt = DateTime.now().millisecondsSinceEpoch;
    report['firstContentAt'] = firstContentAt;
    report['timeToFirstContentMillis'] = firstContentAt - submittedAt;
    report['streamingOutputTokens'] = _outputTokens(streaming);
    final firstBody = _streamingBodyObservation(streaming)!;
    report['streamingAnswerLength'] = firstBody['characters'];
    report['streamingBodySource'] = firstBody;
    stage = 'streaming';
    await mark(stage);
    // Large body only: prove the body really keeps following the stream while it
    // is still generating *above* the per-item preview budget. Preview bytes stay
    // capped by contract. Streaming growth comes from actual ordered activity
    // response parts; completed detail is read only after the atom is sealed.
    //
    // 流中历史阅读/拖动/滚动条由 timeline-history 的完成种子旅程承载。
    // 本单项场景先采样 Live 正文增长，再截图，避免截图消耗生成窗口。
    if (largeBody) {
      final growing = await _sampleStreamingLargeBody(driver, output);
      report['streamingGrowth'] = growing;
      checks['largeBodyGrowingFullFollow'] =
          growing['windowPassed'] == true &&
          growing['identityStable'] == true &&
          (growing['growthFramesAboveWindow'] as int) >= 2 &&
          growing['stayedLiveAtEdge'] == true;
      if (checks['largeBodyGrowingFullFollow'] != true) {
        throw StateError(
          'Large body did not prove same-source text growth above the preview '
          'budget while following Live: ${jsonEncode(growing)}',
        );
      }
    }
    await File('${output.path}/stress-body-streaming.png')
        .writeAsBytes(await driver.screenshot());
    final terminal = await _waitFor(
      driver,
      (snapshot) =>
          _outputTokens(snapshot) >= _expectedTokens && !_isBusy(snapshot),
      'terminal',
      evidence: output,
    );
    final terminalAt = DateTime.now().millisecondsSinceEpoch;
    report['terminalAt'] = terminalAt;
    report['terminalOutputTokens'] = _outputTokens(terminal);
    stage = 'terminal';
    await mark(stage);
    // The local snapshot must not be named `settled`: that would shadow the
    // imported `settled(snapshot, threadId)` predicate used for the reopen wait.
    var settledSnapshot = await _waitFor(
      driver,
      _settled,
      'settled',
      evidence: output,
    );
    report['durableSettledAt'] = DateTime.now().millisecondsSinceEpoch;
    report['settledOutputTokens'] = _outputTokens(settledSnapshot);
    final settledTimeline = TimelineObservation.parse(settledSnapshot);
    settledTimeline.requireConsistentIds();
    report['answerItemCount'] = settledTimeline.ofKind('agentMessage').length;
    stage = 'settled';
    await mark(stage);
    // Hold (bounded) until the assistant item's true body length is known before
    // asserting, so a snapshot taken mid-render cannot falsely fail while a
    // genuinely truncated body still fails within the deadline.
    settledSnapshot = await _waitFor(
      driver,
      (snapshot) =>
          _longBodyItem(snapshot)?.textTotalBytes == expectedBodyCharacters,
      'body_rendered',
      evidence: output,
    );
    report['bodyRenderedAt'] = DateTime.now().millisecondsSinceEpoch;
    await File('${output.path}/stress-body-settled.png')
        .writeAsBytes(await driver.screenshot());

    final longBody = _longBodyItem(settledSnapshot);
    final longBodyId = longBody?.id;
    final bodyText = longBody?.text;
    final bodyCharacters = bodyText?.length;
    final bodyBytes = bodyText == null ? null : utf8.encode(bodyText).length;
    final detail = longBody?.detail('text');
    final prefixOk = bodyText != null && bodyText.startsWith('body-00000 ');
    final suffixOk =
        bodyText != null && bodyText.endsWith(_expectedBodySuffix(largeBody));
    final totalBytes = detail?.totalBytes;
    // Bounded boundary previews so a reviewer can re-check the content without
    // duplicating the whole reply.
    String? headPreview;
    String? tailPreview;
    if (bodyText != null) {
      headPreview = bodyText.substring(
        0,
        bodyText.length < 32 ? bodyText.length : 32,
      );
      tailPreview = bodyText.substring(
        bodyText.length < 32 ? 0 : bodyText.length - 32,
      );
    }
    report['longBody'] = <String, Object?>{
      'itemId': longBodyId,
      'expectedCharacters': expectedBodyCharacters,
      'deliveredCharacters': bodyCharacters,
      'deliveredBytes': bodyBytes,
      'detailTotalBytes': totalBytes,
      'previewBytes': detail?.previewBytes,
      'timelineEpoch': settledTimeline.timelineEpoch,
      'appendSeq': longBody?.appendSeq,
      'truncated': longBody?.textTruncated,
      'largeBody': largeBody,
      'prefixOk': prefixOk,
      'suffixOk': suffixOk,
      'headPreview': headPreview,
      'tailPreview': tailPreview,
      'manualLoadTapped': false,
      'viewerRequired': true,
    };
    // 两个场景的正文都超过产品 32 KiB 展示预算：行内只保留有界预览，真实总长由
    // 详情引用给出；完整正文只能由用户显式打开查看器逐块读取。
    final previewBytes = detail?.previewBytes;
    checks['bodyPreviewBounded'] =
        longBody?.textTruncated == true &&
        totalBytes == expectedBodyCharacters &&
        previewBytes != null &&
        previewBytes <= _productPreviewBudgetBytes &&
        bodyCharacters == previewBytes &&
        prefixOk;
    checks['bodyFullLengthDeclared'] = totalBytes == expectedBodyCharacters;
    if (largeBody) {
      checks['largeBodyAboveProductPreview'] =
          totalBytes == _expectedLargeBodyCharacters &&
          (totalBytes ?? 0) > _productPreviewBudgetBytes;
    }
    // suffix 只在预览确实覆盖正文尾部时才成立：有界预览不应包含尾部标记。
    checks['bodyPreviewExcludesTail'] = !suffixOk;
    // Evidence of the current epoch, completed identities, append positions and
    // preview bytes.
    findings['loadedItems'] = <String, Object?>{
      'itemCount': settledTimeline.itemCount,
      'mode': settledTimeline.mode,
      'generation': settledTimeline.generation,
      'hasOlder': settledTimeline.hasOlder,
      'olderCursor': settledTimeline.olderCursor,
      'textBytes': settledTimeline.items.fold<int>(
        0,
        (total, item) => total + item.textBytes,
      ),
      'truncatedItems': settledTimeline.items
          .where((item) => item.textTruncated)
          .length,
      'note': 'preview bytes of the currently loaded canonical items',
    };

    // 完整正文只经用户显式打开的详情查看器读取并复制；行内预览另有真实渲染/选择复制
    // 证据（有界，不当全文）。
    stage = 'detail_copy';
    await mark(stage);
    final detailCopy = await _copyThroughDetailViewer(
      driver,
      output,
      expectedBodyCharacters,
      largeBody,
      longBodyId,
    );
    report['detailCopy'] = detailCopy;
    checks['detailViewerFullBody'] = detailCopy['pass'] == true;
    stage = 'preview_selection_copy';
    await mark(stage);
    final previewCopy = await _selectAndCopyPreview(
      driver,
      output,
      detail?.previewBytes ?? 0,
      largeBody,
    );
    report['previewCopy'] = previewCopy;
    checks['renderedOriginalPreviewCopy'] = previewCopy['pass'] == true;

    await markStage('wheel_and_scrollbar');
    final scrolling = await observeTimelineScrolling(args[0], output);
    report['scrolling'] = scrolling;
    checks['wheelAndScrollbar'] = scrolling['pass'] == true;

    // Read into the interior of the long assistant body, then create a second
    // session and switch back. Reopening starts from the latest small page by
    // contract: no pixel anchor is saved or restored.
    final originalId = selectedThread(settledSnapshot);
    await markStage('reading');
    final reading = await _readIntoLongBody(driver, output, settledSnapshot);
    report['reading'] = reading;
    checks['readingInsideLongBody'] = reading['pass'] == true;
    await mark('second_session');
    final secondId = await _createSecondSession(
      driver,
      originalId,
      onStage: markStage,
      output: output,
    );
    report['secondSessionId'] = secondId;
    await File('${output.path}/stress-body-second-session.png')
        .writeAsBytes(await driver.screenshot());
    await mark('revisit_original');
    await driver.scrollUntilVisible(
      find.byValueKey('sidebar-project-tree'),
      find.byValueKey('thread-row-$originalId'),
      dyScroll: -200,
      timeout: const Duration(seconds: 45),
    );
    await driver.tap(find.byValueKey('thread-row-$originalId'));
    final reopened = await _waitFor(
      driver,
      (snapshot) {
        final timeline = TimelineObservation.optional(snapshot);
        final scroll = TimelineScrollObservation.optional(snapshot);
        return _selectedThreadOrNull(snapshot) == originalId &&
            timeline != null &&
            timeline.ready &&
            scroll != null &&
            scroll.laidOut &&
            !scroll.isScrolling &&
            settled(snapshot, originalId);
      },
      'reopen_original',
      evidence: output,
    );
    final reopenedTimeline = TimelineObservation.parse(reopened);
    final reopenedScroll = TimelineScrollObservation.parse(reopened);
    final reopenLayout = _decodeDriverMap(
      await driver.requestData('body-layout'),
    );
    await File('${output.path}/stress-body-reopened.png')
        .writeAsBytes(await driver.screenshot());
    await File('${output.path}/stress-body-timeline-scroll.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(reopenedScroll.toJson())}\n',
    );
    await File('${output.path}/stress-body-reopened-layout.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(reopenLayout)}\n',
    );
    final reopenedBody = _longBodyItem(reopened);
    final reopenedDetail = reopenedBody?.detail('text');
    final generationAdvanced =
        reopenedTimeline.generation != settledTimeline.generation;
    // 重开从最新端开始并按视口补齐：offset 0、Live 模式，不恢复像素。
    //
    // 标准反向列表的底端就是 offset 0：此时 `extentBefore` 为 0、`extentAfter` 是
    // 全部可滚动内容。用 `extentAfter ≈ 0` 判“贴底”属于非反向 ListView 的语义，
    // 在正确实现上必然失败；这里读真实几何（`atLiveEdge` + offset 0 + extentBefore 0）。
    final latestPageOnReopen =
        reopenedTimeline.isLive &&
        generationAdvanced &&
        reopenedScroll.atLiveEdge &&
        (reopenedScroll.pixels ?? 1).abs() <= 0.5 &&
        (reopenedScroll.extentBefore ?? 1).abs() <= 0.5 &&
        timelineViewportSettled(reopened);
    // 同身份正文仍在展示范围内：身份 + 真实总长一致，行内预览不因重开被替换成
    // 另一份正文。
    final stableBodyOnReopen =
        reopenedBody != null &&
        reopenedBody.id == reading['itemId'] &&
        reopenedDetail?.totalBytes == expectedBodyCharacters;
    report['sessionSwitch'] = <String, Object?>{
      'originalThreadId': originalId,
      'secondThreadId': secondId,
      'returnedToOriginal': _selectedThreadOrNull(reopened) == originalId,
      'generationBefore': settledTimeline.generation,
      'generationAfter': reopenedTimeline.generation,
      'readingItemId': reading['itemId'],
      'latestPageOnReopen': latestPageOnReopen,
      'stableBodyOnReopen': stableBodyOnReopen,
      'pixelsAfterReopen': reopenedScroll.pixels,
      'atLiveEdgeAfterReopen': reopenedScroll.atLiveEdge,
      'itemCountAfterReopen': reopenedTimeline.itemCount,
      'reopenedScroll': reopenedScroll.toJson(),
      'reopenedLayout': reopenLayout,
    };
    checks['reopenStartsAtLatestPage'] =
        latestPageOnReopen && stableBodyOnReopen;
    stage = 'session_switch_complete';
    await mark(stage);
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
    // Capture the failing observation before shutdown. The original error is
    // always preserved: a driver that already exited yields no extra evidence
    // instead of a second, misleading error.
    await _captureFailure(driver, output);
  }
  try {
    frames = jsonDecode(
      await driver.requestData(
        'frame-stop',
        timeout: const Duration(seconds: 20),
      ),
    ) as Map<String, dynamic>;
    await File(
      '${output.path}/stress-body-frames.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(frames)}\n');
  } catch (error) {
    shutdownError ??= 'frame recording stop failed: $error';
  }
  try {
    final shutdown = jsonDecode(
      await driver
          .requestData('shutdown', timeout: const Duration(seconds: 60))
          .timeout(const Duration(seconds: 65)),
    );
    if (shutdown is! Map || shutdown['shutdown'] != 'completed') {
      shutdownError ??= 'native GUI shutdown did not report completion';
    }
  } catch (error) {
    shutdownError ??= 'native GUI shutdown failed: $error';
  } finally {
    try {
      await driver.close().timeout(const Duration(seconds: 5));
    } catch (_) {
      // A completed shutdown must not keep the acceptance process open.
    }
  }
  final failedChecks = checks.entries
      .where((entry) => entry.value != true)
      .map((entry) => entry.key)
      .toList(growable: false);
  final primaryFailed =
      failure != null || shutdownError != null || failedChecks.isNotEmpty;
  final status = primaryFailed ? 'failed' : 'complete';
  // 主报告是判定的一部分：写失败必须让本旅程失败。已有业务主错时保留主错与原栈，
  // 只把报告写失败作为次级事实打到 stderr；没有主错时必须由报告写错失败收尾，
  // 绝不 mark complete。
  Object? reportError;
  StackTrace? reportStack;
  try {
    await _writeReport(output, <String, Object?>{
      'scenario': scenario,
      'verdict': 'pending',
      'status': status,
      'stage': stage,
      'error': failure?.toString(),
      'shutdownError': shutdownError,
      'failedChecks': failedChecks,
      'checks': checks,
      'findings': findings,
      'pendingEvidence': pendingEvidence,
      'observations': report,
      'frameSampleCount': frames?['samples'] is List
          ? (frames!['samples'] as List).length
          : null,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    });
  } catch (error, stackTrace) {
    reportError = error;
    reportStack = stackTrace;
    stderr.writeln('stress-body report write failed: $error\n$stackTrace');
  }
  await mark(primaryFailed || reportError != null ? stage : 'complete');
  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
  if (shutdownError != null) {
    throw StateError('native GUI shutdown failed: $shutdownError');
  }
  if (failedChecks.isNotEmpty) {
    throw StateError(
      'stress-body checks failed: ${failedChecks.join(', ')}; '
      'longBody=${report['longBody']}; sessionSwitch=${report['sessionSwitch']}',
    );
  }
  if (reportError != null) {
    // 没有业务主错时，报告写失败就是本次失败，必须非零退出。
    Error.throwWithStackTrace(reportError, reportStack!);
  }
}

Future<void> _writeReport(Directory output, Map<String, Object?> report) async {
  // 主报告不是可选旁证：直接 await 让写失败传播，由调用方按主错优先级处理。
  await File('${output.path}/stress-body-report.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
}

Future<void> _openProject(FlutterDriverSession driver, String project) async {
  await driver.waitFor(
    find.byValueKey('sidebar-open-project'),
    timeout: const Duration(seconds: 60),
  );
  await _tap(driver, 'sidebar-open-project');
  await _tap(driver, 'add-project-local');
  await driver.waitFor(
    find.byValueKey('add-project-continue-ready'),
    timeout: const Duration(seconds: 30),
  );
  await _tap(driver, 'add-project-continue-ready');
  await driver.waitFor(
    find.byValueKey('project-path-input'),
    timeout: const Duration(seconds: 30),
  );
  await _tap(driver, 'project-path-input');
  await driver.enterText(project);
  await driver.waitFor(
    find.byValueKey('project-path-submit'),
    timeout: const Duration(seconds: 30),
  );
  await _tap(driver, 'project-path-submit');
  await driver.waitFor(
    find.byValueKey('composer-input'),
    timeout: const Duration(seconds: 60),
  );
}

Future<void> _submit(FlutterDriverSession driver, String prompt) async {
  await driver.waitFor(
    find.byValueKey('composer-input'),
    timeout: const Duration(seconds: 30),
  );
  await _tap(driver, 'composer-input');
  await driver.enterText(prompt);
  await driver.waitFor(
    find.byValueKey('composer-submit'),
    timeout: const Duration(seconds: 30),
  );
  await _tap(driver, 'composer-submit');
}

Future<void> _tap(FlutterDriverSession driver, String key) =>
    driver.rawTap(find.byValueKey(key), timeout: const Duration(seconds: 30));

Future<Map<String, dynamic>> _waitFor(
  FlutterDriverSession driver,
  bool Function(Map<String, dynamic>) predicate,
  String label, {
  Duration timeout = const Duration(seconds: 120),
  Directory? evidence,
}) async {
  final deadline = DateTime.now().add(timeout);
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await driver.readSnapshot();
    if (predicate(last)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  // The timeout must carry the real observed state, and the snapshot must survive
  // after the coordinator reclaims its tempdir.
  if (evidence != null && last != null) {
    try {
      await File(
        '${evidence.path}/stress-body-wait-timeout-$label.json',
      ).writeAsString('${const JsonEncoder.withIndent('  ').convert(last)}\n');
    } catch (_) {
      // Capturing evidence must never replace the timeout it documents.
    }
  }
  throw StateError(
    'timed out waiting for stress-body $label after ${timeout.inSeconds}s: '
    '${_summarize(last)}',
  );
}

/// Saves the last snapshot and a screenshot for a failed journey.
///
/// The caller keeps the original failure: a driver that already exited simply
/// yields no extra evidence instead of a second, misleading error.
Future<void> _captureFailure(
  FlutterDriverSession driver,
  Directory output,
) async {
  try {
    final snapshot = await driver.readSnapshot().timeout(
      const Duration(seconds: 10),
    );
    await File('${output.path}/stress-body-failure-snapshot.json')
        .writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n',
        );
  } catch (_) {
    // Ignored: the report still carries the original error and stage.
  }
  try {
    final png = await driver.screenshot().timeout(const Duration(seconds: 20));
    await File('${output.path}/stress-body-failure.png').writeAsBytes(png);
  } catch (_) {
    // Ignored: see above.
  }
}

/// A compact description of the observed state for timeout diagnostics.
String _summarize(Map<String, dynamic>? snapshot) {
  if (snapshot == null) return 'no snapshot was observed';
  final workspace = _workspace(snapshot);
  final persistence = snapshot['persistence'];
  final directory = snapshot['sidebarDirectory'];
  final timeline = TimelineObservation.optional(snapshot);
  return 'threadStatus=${workspace?['threadStatus']}, '
      'busy=${workspace?['isBusy']}, '
      'sync=${workspace?['syncState']}, '
      'mode=${timeline?.mode}, '
      'items=${timeline?.itemCount}, '
      'turn=${_turnIdOrNull(snapshot)}, '
      'selected=${_selectedThreadOrNull(snapshot)}, '
      'saving=${persistence is Map ? persistence['kind'] : null}, '
      'sessions=${directory is Map ? directory['count'] : null}';
}

String? _turnIdOrNull(Map<String, dynamic> snapshot) {
  final workspace = _workspace(snapshot);
  final turn = workspace?['turn'];
  return turn is Map && turn['id'] is String ? turn['id'] as String : null;
}

Map<String, dynamic>? _workspace(Map<String, dynamic> snapshot) {
  final workspace = snapshot['workspace'];
  return workspace is Map<String, dynamic> ? workspace : null;
}

bool _isBusy(Map<String, dynamic> snapshot) =>
    _workspace(snapshot)?['isBusy'] == true;

int _outputTokens(Map<String, dynamic> snapshot) {
  final usage = _workspace(snapshot)?['usage'];
  return usage is Map ? (usage['outputTokens'] as num? ?? 0).toInt() : 0;
}

bool _settled(Map<String, dynamic> snapshot) {
  final workspace = _workspace(snapshot);
  final persistence = snapshot['persistence'];
  final timeline = TimelineObservation.optional(snapshot);
  return workspace != null &&
      workspace['isBusy'] == false &&
      workspace['threadStatus'] == 'idle' &&
      workspace['syncState'] == 'ready' &&
      persistence is Map &&
      persistence['kind'] == 'ready' &&
      persistence['pendingCommits'] == 0 &&
      timeline != null &&
      timeline.ready &&
      timeline.connection == 'ready';
}

/// 当前展示的助手正文条目：已加载 agentMessage 中正文预览最长的一条。
TimelineItemObservation? _longBodyItem(Map<String, dynamic> snapshot) {
  final timeline = TimelineObservation.optional(snapshot);
  if (timeline == null) return null;
  TimelineItemObservation? best;
  for (final item in timeline.items) {
    if (item.kind != 'agentMessage') continue;
    if (best == null || item.text.length > best.text.length) best = item;
  }
  return best;
}

/// 首正文只来自当前 busy Turn 的未完成活动段，不能用完成历史预览代替。
Map<String, Object?>? _streamingBodyObservation(Map<String, dynamic> snapshot) {
  if (!_isBusy(snapshot)) return null;
  if (!snapshot.containsKey('conversationActivity')) {
    throw StateError('Streaming snapshot lacks conversationActivity');
  }
  final rawActivity = snapshot['conversationActivity'];
  if (rawActivity == null) return null;
  if (rawActivity is! Map) {
    throw StateError('Streaming conversationActivity is not an object');
  }
  final identity = rawActivity['identity'];
  final turnId = rawActivity['turnId'];
  final executionId = rawActivity['executionId'];
  final rawParts = rawActivity['responseParts'];
  if (identity is! String ||
      identity.isEmpty ||
      turnId is! String ||
      turnId.isEmpty ||
      turnId != _turnIdOrNull(snapshot) ||
      !rawActivity.containsKey('executionId') ||
      (executionId != null &&
          (executionId is! String || executionId.isEmpty)) ||
      rawParts is! List) {
    throw StateError('Streaming body lacks current activity/source identity');
  }
  if (rawParts.isEmpty) return null;
  if (rawParts.length != 1) {
    throw StateError(
      'Single-item body stream published multiple response parts',
    );
  }
  final part = _responseActivityPart(rawParts.single, 0);
  final itemId = part['itemId']! as String;
  final text = part['text']! as String;
  if (itemId.isEmpty) {
    throw StateError('Streaming response part lacks item identity');
  }
  if (part['complete'] != false || text.isEmpty) return null;
  return <String, Object?>{
    'busy': _isBusy(snapshot),
    'currentTurnId': _turnIdOrNull(snapshot),
    'activityIdentity': identity,
    'turnId': turnId,
    'executionId': executionId,
    'itemId': itemId,
    'complete': part['complete'],
    'characters': text.length,
    'byteLength': part['byteLength'],
  };
}

/// Samples the in-flight large body while it is still generating.
///
/// Streaming progress is sampled from the real ordered response parts of the
/// current `conversationActivity`. No detail query is made until the completed
/// atom is explicitly opened below.
Future<Map<String, Object?>> _sampleStreamingLargeBody(
  FlutterDriverSession driver,
  Directory output,
) async {
  final frames = <Map<String, Object?>>[];
  var windowPassed = false;
  var identityStable = true;
  var stayedLiveAtEdge = true;
  var growthFrames = 0;
  final growthProofs = <Map<String, Object?>>[];
  Map<String, Object?>? previousFrame;
  Object? samplingError;
  StackTrace? samplingStack;
  // 有界 deadline 覆盖合成流窗口即可；终态在循环内单独 break，不靠 deadline 收尾。
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  try {
    while (DateTime.now().isBefore(deadline) && growthFrames < 2) {
      final snapshot = await driver.readSnapshot();
      final rawActivity = snapshot['conversationActivity'];
      final activity = rawActivity is Map ? rawActivity : null;
      final rawParts = activity?['responseParts'];
      final frame = <String, Object?>{
        'at': DateTime.now().millisecondsSinceEpoch,
        'busy': _isBusy(snapshot),
        'currentTurnId': _turnIdOrNull(snapshot),
        'activityIdentity': activity?['identity'],
        'turnId': activity?['turnId'],
        'executionId': activity?['executionId'],
        'responsePartCount': rawParts is List ? rawParts.length : null,
        'responseParts': rawParts,
        'countedGrowth': false,
      };
      frames.add(frame);
      if (!_isBusy(snapshot)) break;
      final body = _streamingBodyObservation(snapshot);
      if (body == null) {
        throw StateError('Large body has no current incomplete streaming text');
      }
      final part = _responseActivityPart((rawParts as List).single, 0);
      final itemId = part['itemId']! as String;
      final text = part['text']! as String;
      final byteLength = part['byteLength']! as int;
      final scroll = TimelineScrollObservation.parse(snapshot);
      final timeline = TimelineObservation.parse(snapshot);
      final liveAtEdge =
          timeline.isLive &&
          scroll.laidOut &&
          scroll.threadId == timeline.threadId &&
          scroll.generation == timeline.generation &&
          scroll.atLiveEdge;
      frame.addAll(<String, Object?>{
        ...body,
        'part': part,
        'mode': timeline.mode,
        'atLiveEdge': scroll.atLiveEdge,
        'pixels': scroll.pixels,
        'extentBefore': scroll.extentBefore,
        'extentAfter': scroll.extentAfter,
      });
      if (!liveAtEdge) {
        stayedLiveAtEdge = false;
        throw StateError('Large body growth left the Live edge');
      }
      if (byteLength > _productPreviewBudgetBytes) windowPassed = true;
      final previous = previousFrame;
      if (previous != null) {
        if (body['activityIdentity'] != previous['activityIdentity'] ||
            body['turnId'] != previous['turnId'] ||
            body['executionId'] != previous['executionId'] ||
            itemId != previous['itemId']) {
          identityStable = false;
          throw StateError('Large body changed activity/source/part identity');
        }
        final previousPart = previous['part']! as Map<String, Object?>;
        final previousText = previousPart['text']! as String;
        final previousByteLength = previousPart['byteLength']! as int;
        if (!text.startsWith(previousText) ||
            text.length < previousText.length ||
            byteLength < previousByteLength) {
          throw StateError('Large body text was replaced or regressed');
        }
        if (previousByteLength > _productPreviewBudgetBytes &&
            byteLength > _productPreviewBudgetBytes &&
            text.length > previousText.length &&
            byteLength > previousByteLength) {
          frame['countedGrowth'] = true;
          growthFrames += 1;
          growthProofs.add(<String, Object?>{
            'before': previous,
            'after': frame,
          });
        }
      }
      previousFrame = frame;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } catch (error, stackTrace) {
    samplingError = error;
    samplingStack = stackTrace;
  }
  if (samplingError == null && growthFrames < 2) {
    samplingError = StateError(
      'Large body ended or sampling window expired before two valid growths',
    );
    samplingStack = StackTrace.current;
  }
  final evidence = <String, Object?>{
    'windowPassed': windowPassed,
    'identityStable': identityStable,
    'stayedLiveAtEdge': stayedLiveAtEdge,
    'growthFramesAboveWindow': growthFrames,
    'growthProofs': growthProofs,
    'framesSampled': frames.length,
    'thresholdBytes': _productPreviewBudgetBytes,
    'manualLoadTapped': false,
    'error': samplingError?.toString(),
    // Bounded tail so a reviewer can re-check the growth without the whole list.
    'recentFrames': frames.length > 8
        ? frames.sublist(frames.length - 8)
        : frames,
  };
  // 这份证据是判定的一部分，不是可选旁证：写入失败必须原样传播到本旅程，由外层
  // 保留原始错误并完成 shutdown 收束，不能吞掉后当“已观测”。
  try {
    await File('${output.path}/stress-body-large-growth.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(evidence)}\n',
    );
  } catch (error) {
    if (samplingError == null) rethrow;
    stderr.writeln('Large body growth evidence write failed: $error');
  }
  if (samplingError != null) {
    Error.throwWithStackTrace(samplingError, samplingStack!);
  }
  return evidence;
}

Map<String, Object?> _responseActivityPart(Object? raw, int index) {
  if (raw is! Map || raw['complete'] is! bool) {
    throw StateError('conversationActivity.responseParts lacks complete state');
  }
  return <String, Object?>{
    ...parseConversationActivityPart(
      raw,
      index: index,
      identityField: 'itemId',
      context: 'conversationActivity.responseParts',
    ),
    'complete': raw['complete'],
  };
}

/// Scrolls into the *interior* of the assistant long body — the actual reply row,
/// never the user input row — until a point inside that row is visibly on screen
/// and the viewport has really left the pinned last line.
///
/// The scroll step is **positive** (see [_readScrollStep]); a negative step keeps
/// pulling content from below, so the reading position never leaves the bottom.
/// 可见位置来自请求时的真实行几何（按 canonical row key 现场扫描），不是生产状态。
Future<Map<String, Object?>> _readIntoLongBody(
  FlutterDriverSession driver,
  Directory output,
  Map<String, dynamic> settledSnapshot,
) async {
  final item = _longBodyItem(settledSnapshot);
  final target = item?.id;
  final probe = TimelineRowsProbe(driver.requestData);
  final geometry = <Map<String, Object?>>[];
  final evidence = <String, Object?>{
    'itemId': target,
    'kind': item?.kind,
    'geometry': geometry,
    'pass': false,
  };
  try {
    if (item == null ||
        target == null ||
        item.kind != 'agentMessage' ||
        !item.text.startsWith('body-00000 ')) {
      throw StateError(
        'No canonical assistant fixture body is available to read',
      );
    }
    final initial = TimelineObservation.parse(settledSnapshot);
    initial.requireConsistentIds();
    final presentationId = initial.presentationFor(target).id;
    evidence['presentationId'] = presentationId;
    var scrolled = false;
    var mode = initial.mode;
    var detached = false;
    for (var step = 0; step < _maxReadSteps && !detached; step++) {
      final beforeRows = await probe.read(rowIds: [presentationId]);
      final row = beforeRows.row(presentationId);
      geometry.add(<String, Object?>{
        'phase': 'before_scroll_${step + 1}',
        'row': row?.toJson(),
        'viewport': beforeRows.viewport.toJson(),
      });
      await driver.scrollBy(
        find.byValueKey('timeline-scrollable'),
        _readScrollStep,
        timeout: const Duration(seconds: 15),
      );
      scrolled = true;
      final state = await _waitFor(
        driver,
        (snapshot) {
          final timeline = TimelineObservation.optional(snapshot);
          final scroll = TimelineScrollObservation.optional(snapshot);
          return timeline != null &&
              scroll != null &&
              scroll.laidOut &&
              !scroll.isScrolling;
        },
        'reading_drag_${step + 1}_idle',
        evidence: output,
      );
      final timeline = TimelineObservation.parse(state);
      final scroll = TimelineScrollObservation.parse(state);
      timeline.requireConsistentIds();
      if (timeline.threadId != initial.threadId ||
          timeline.timelineEpoch != initial.timelineEpoch ||
          timeline.generation != initial.generation ||
          scroll.threadId != timeline.threadId ||
          scroll.generation != timeline.generation ||
          timeline.presentationFor(target).id != presentationId ||
          jsonEncode(timeline.item(target)?.frozenFields()) !=
              jsonEncode(item.frozenFields())) {
        throw StateError('Reading changed the canonical body or its owner');
      }
      mode = timeline.mode;
      final rows = await probe.read(rowIds: [presentationId]);
      final after = rows.row(presentationId);
      final viewport = rows.viewport;
      // 可见点在行内（顶部高于视口、底部低于视口），说明视口真的落在巨大正文内部。
      final insideRow =
          after != null &&
          after.intersects &&
          after.rect != null &&
          after.rect!.top < 1 &&
          after.rect!.bottom > viewport.height - 1;
      final threshold = _detachedExtentThreshold(scroll.viewportDimension);
      // 标准反向列表的底端是 offset 0：真正“离开底端”的量是 `extentBefore`
      // （已从 0 向上滚过的距离）。`extentAfter` 是剩余可向下滚动的内容，在底端
      // 恰为最大值，不能用来判离底。仍需视口落在巨大正文内部、且不在最早端点。
      detached =
          timeline.isHistory &&
          insideRow &&
          (scroll.extentBefore ?? 0) > threshold &&
          (scroll.pixels ?? 0) < (scroll.maxScrollExtent ?? 0) - 1.0;
      geometry.add(<String, Object?>{
        'phase': 'after_scroll_${step + 1}',
        'row': after?.toJson(),
        'viewport': viewport.toJson(),
        'timeline': timeline.summary(),
        'scroll': scroll.toJson(),
        'insideRow': insideRow,
        'detached': detached,
      });
    }
    await File('${output.path}/stress-body-reading.png')
        .writeAsBytes(await driver.screenshot());
    final layout = _decodeDriverMap(await driver.requestData('body-layout'));
    evidence['layout'] = layout;
    await File(
      '${output.path}/stress-body-reading-layout.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(layout)}\n');
    final visible = layout?['visible'];
    final characterOffset = visible is Map ? visible['characterOffset'] : null;
    final visibleText = visible is Map ? visible['text'] : null;
    final bodyLayoutMatchesPreview =
        layout?['ok'] == true &&
        layout?['characters'] == item.text.length &&
        characterOffset is int &&
        characterOffset > 0 &&
        characterOffset < item.text.length &&
        visibleText is String &&
        visibleText.isNotEmpty &&
        characterOffset + visibleText.length <= item.text.length &&
        item.text.substring(
              characterOffset,
              characterOffset + visibleText.length,
            ) ==
            visibleText;
    final finalState = await driver.readSnapshot();
    final finalTimeline = TimelineObservation.parse(finalState);
    final finalScroll = TimelineScrollObservation.parse(finalState);
    finalTimeline.requireConsistentIds();
    final insideLongBody = detached && bodyLayoutMatchesPreview;
    final pass =
        scrolled &&
        insideLongBody &&
        finalTimeline.isHistory &&
        finalTimeline.threadId == initial.threadId &&
        finalTimeline.timelineEpoch == initial.timelineEpoch &&
        finalTimeline.generation == initial.generation &&
        finalTimeline.presentationFor(target).id == presentationId &&
        jsonEncode(finalTimeline.item(target)?.frozenFields()) ==
            jsonEncode(item.frozenFields()) &&
        finalScroll.threadId == initial.threadId &&
        finalScroll.generation == initial.generation &&
        !finalScroll.atLiveEdge &&
        (finalScroll.extentBefore ?? 0) >
            _detachedExtentThreshold(finalScroll.viewportDimension) &&
        (finalScroll.pixels ?? 0) < (finalScroll.maxScrollExtent ?? 0) - 1.0;
    evidence.addAll(<String, Object?>{
      'scrolled': scrolled,
      'steps': geometry.length ~/ 2,
      'mode': mode,
      'finalMode': finalTimeline.mode,
      'generation': finalTimeline.generation,
      'insideLongBody': insideLongBody,
      'bodyLayoutMatchesPreview': bodyLayoutMatchesPreview,
      'detachedFromLiveEdge': !finalScroll.atLiveEdge,
      'extentBefore': finalScroll.extentBefore,
      'extentAfter': finalScroll.extentAfter,
      'pixels': finalScroll.pixels,
      'maxScrollExtent': finalScroll.maxScrollExtent,
      'detachedThreshold': _detachedExtentThreshold(
        finalScroll.viewportDimension,
      ),
      'final': finalScroll.toJson(),
      'pass': pass,
    });
    await File('${output.path}/stress-body-reading-scroll.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(evidence)}\n',
    );
    if (!pass) {
      throw StateError('Reading did not reach the canonical body interior');
    }
    return evidence;
  } catch (error, stackTrace) {
    evidence['error'] = '$error';
    evidence['pass'] = false;
    if (evidence['layout'] == null) {
      try {
        final layout = _decodeDriverMap(
          await driver.requestData('body-layout'),
        );
        evidence['layout'] = layout;
        await File('${output.path}/stress-body-reading-layout.json')
            .writeAsString(
              '${const JsonEncoder.withIndent('  ').convert(layout)}\n',
            );
      } catch (captureError) {
        stderr.writeln('Reading layout capture failed: $captureError');
      }
    }
    try {
      await File('${output.path}/stress-body-reading-scroll-error.txt')
          .writeAsString('$error\n$stackTrace\n');
      await File('${output.path}/stress-body-reading-scroll.json')
          .writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(evidence)}\n',
          );
    } catch (captureError) {
      stderr.writeln('Reading failure evidence write failed: $captureError');
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

/// A full viewport of content (never below [_minDetachedExtentAfter] px) must
/// remain below the viewport for the reading position to count as detached.
double _detachedExtentThreshold(Object? viewportDimension) {
  final viewport = _doubleOrNull(viewportDimension) ?? 0;
  return viewport > _minDetachedExtentAfter
      ? viewport
      : _minDetachedExtentAfter;
}

double? _doubleOrNull(Object? value) => value is num ? value.toDouble() : null;

/// Creates one strict follow-up session and waits for its title to settle.
///
/// Every wait is bounded and every step is staged: a stuck composer fails into
/// the report with the observed state instead of hanging the host until its own
/// timeout. `FlutterDriver.waitFor`/`waitForAbsent` default to *no* timeout, so
/// the finder waits below always pass an explicit deadline.
Future<String> _createSecondSession(
  FlutterDriverSession driver,
  String originalId, {
  required Future<void> Function(String stage) onStage,
  required Directory output,
}) async {
  await onStage('second_session_new_tapped');
  await driver.tap(find.byValueKey('sidebar-new-session'));
  await waitForSnapshot(
    driver,
    (snapshot) => _selectedThreadOrNull(snapshot) == null,
    'new session',
  );
  await onStage('second_session_composer');
  await driver.waitFor(
    find.byValueKey('start-page-selectors'),
    timeout: const Duration(seconds: 30),
  );
  await driver.waitFor(
    find.byValueKey('composer-input'),
    timeout: const Duration(seconds: 30),
  );
  await driver.tap(find.byValueKey('composer-input'));
  await driver.enterText(_secondSessionPrompt);
  await onStage('second_session_typed');
  // Keep the composer state the draft wait is about, so a stuck draft can be
  // re-checked after the coordinator reclaims its tempdir.
  await File(
    '${output.path}/stress-body-second-session-composer.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(await driver.readSnapshot())}\n',
  );
  // The submit button only becomes usable once the draft is canonical in the
  // bridge state, so wait for the draft itself (the multi-item stress journey
  // does the same) instead of tapping an indeterminate button.
  await waitForSnapshot(
    driver,
    (snapshot) => _newThreadDraft(snapshot) == _secondSessionPrompt,
    'second session draft',
  );
  await driver.waitFor(
    find.byValueKey('composer-submit'),
    timeout: const Duration(seconds: 15),
  );
  await onStage('second_session_submitted');
  await driver.tap(find.byValueKey('composer-submit'));
  final opened = await waitForSnapshot(driver, (snapshot) {
    final selected = _selectedThreadOrNull(snapshot);
    return selected != null && selected != originalId;
  }, 'second session open');
  final id = selectedThread(opened);
  await onStage('second_session_opened');
  await waitForSnapshot(driver, (snapshot) {
    final directory = snapshot['sidebarDirectory'];
    if (directory is! Map) return false;
    final titles = directory['titles'];
    return TimelineObservation.optional(snapshot) != null &&
        settled(snapshot, id) &&
        titles is Map &&
        titles[id] == 'Fixture Session 1';
  }, 'second session complete');
  await onStage('second_session_complete');
  return id;
}

/// The canonical new-thread composer draft, when the snapshot exposes it.
String? _newThreadDraft(Map<String, dynamic> snapshot) {
  final navigation = snapshot['navigation'];
  if (navigation is! Map) return null;
  final composer = navigation['newThreadComposer'];
  if (composer is! Map) return null;
  final draft = composer['draft'];
  return draft is String ? draft : null;
}

String? _selectedThreadOrNull(Map<String, dynamic> snapshot) {
  final navigation = snapshot['navigation'];
  if (navigation is! Map) return null;
  final selected = navigation['selectedThreadId'];
  return selected is String ? selected : null;
}

/// The tail marker the strict fixture body ends with, per scenario.
String _expectedBodySuffix(bool largeBody) =>
    largeBody ? 'body-19999 ${'W' * _largeBodyPad} ' : ' body-19999 ';

/// Drives a real `SelectionArea` select/copy of the **bounded inline preview**.
///
/// 产品正文预算是 32 KiB：行内只交付有界预览，完整正文由显式详情查看器提供
/// （[_copyThroughDetailViewer]）。这里验证实际生产 RenderParagraph 与产品复制回调
/// 对交付预览逐字节一致；标准 Text 可以只有一个段落，本纯文本样例不证明跨块选择。
Future<Map<String, Object?>> _selectAndCopyPreview(
  FlutterDriverSession driver,
  Directory output,
  int previewCharacters,
  bool largeBody,
) async {
  final canonical = _canonicalBody(largeBody);
  final expectedPreview = previewCharacters >= canonical.length
      ? canonical
      : canonical.substring(0, previewCharacters);
  final expectedHash = _fnv1a64(expectedPreview).toRadixString(16);
  final beforeTimeline = TimelineObservation.parse(await driver.readSnapshot());
  final scrollBefore = TimelineScrollObservation.optional(
    await driver.readSnapshot(),
  );
  Map<String, dynamic>? rendered;
  int? stableParagraphCount;
  var stablePolls = 0;
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (true) {
    rendered = _decodeDriverMap(
      await driver.requestData(
        'selection-body',
        timeout: const Duration(seconds: 20),
      ),
    );
    if (rendered?['ok'] != true) break;
    final paragraphs = (rendered?['paragraphCount'] as num? ?? 0).toInt();
    if (rendered?['characters'] == previewCharacters && paragraphs >= 1) {
      if (paragraphs == stableParagraphCount) {
        stablePolls += 1;
      } else {
        stablePolls = 0;
        stableParagraphCount = paragraphs;
      }
      if (stablePolls >= 2) break;
    } else {
      stablePolls = 0;
      stableParagraphCount = null;
    }
    if (!DateTime.now().isBefore(deadline)) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final renderedReady =
      rendered != null &&
      rendered['ok'] == true &&
      rendered['characters'] == previewCharacters &&
      (rendered['paragraphCount'] as num? ?? 0) >= 1 &&
      rendered['hash'] == expectedHash;
  final selected = _decodeDriverMap(
    await driver.requestData(
      'selection-select-all',
      timeout: const Duration(seconds: 30),
    ),
  );
  final copied = _decodeDriverMap(
    await driver.requestData(
      'selection-copy',
      timeout: const Duration(seconds: 60),
    ),
  );
  final copiedText = copied?['copied'] as String?;
  final copiedHash = copied?['copiedHash'];
  // 平台剪贴板回读必须与原文预览精确相等，不允许前后缀或插入换行。
  final copiedMatchesPreview =
      copiedText != null &&
      copiedText.length == previewCharacters &&
      copied?['copiedLength'] == previewCharacters &&
      copiedHash == expectedHash &&
      copiedText == expectedPreview;
  String? cancelClickError;
  var cancelClicked = false;
  try {
    await driver.rawTap(
      find.byValueKey('timeline-scrollable'),
      timeout: const Duration(seconds: 30),
    );
    cancelClicked = true;
  } catch (error) {
    cancelClickError = error.toString();
  }
  final selectionState = _decodeDriverMap(
    await driver.requestData(
      'selection-state',
      timeout: const Duration(seconds: 15),
    ),
  );
  final selectionCleared = selectionState?['copyable'] == false;
  final afterTimeline = TimelineObservation.parse(await driver.readSnapshot());
  final scrollAfter = TimelineScrollObservation.optional(
    await driver.readSnapshot(),
  );
  final scrollStable =
      scrollBefore != null &&
      scrollAfter != null &&
      scrollBefore.generation == scrollAfter.generation &&
      ((scrollBefore.pixels ?? 0) - (scrollAfter.pixels ?? 0)).abs() <= 1.0;
  final modeStable =
      afterTimeline.generation == beforeTimeline.generation &&
      afterTimeline.mode == beforeTimeline.mode;
  final pass =
      renderedReady &&
      copied?['ok'] == true &&
      copiedMatchesPreview &&
      selected?['copyable'] == true &&
      cancelClicked &&
      selectionCleared &&
      scrollStable &&
      modeStable;
  final evidence = <String, Object?>{
    'method':
        'SelectionArea selectAll + product context-menu copy callback + '
        'Clipboard.getData readback + real click cancel (inline preview only)',
    'previewCharacters': previewCharacters,
    'expectedHash': expectedHash,
    'expectedHead': _headOf(expectedPreview),
    'expectedTail': _tailOf(expectedPreview),
    'fullBodyCharacters': canonical.length,
    'note':
        'inline preview is bounded by the product 32 KiB budget; the complete '
        'body is read through the explicit detail viewer',
    'renderedParagraphCount': rendered?['paragraphCount'],
    'renderedCharacters': rendered?['characters'],
    'renderedHash': rendered?['hash'],
    'renderedMatchesPreview': renderedReady,
    'selectOk': selected?['ok'],
    'copyButtonPresent': selected?['copyable'],
    'copyOk': copied?['ok'],
    'copiedLength': copiedText?.length,
    'copiedHash': copiedHash,
    'copiedMatchesPreview': copiedMatchesPreview,
    'cancelClick': cancelClicked,
    'cancelClickError': cancelClickError,
    'copyableAfterCancelClick': selectionState?['copyable'],
    'selectionCleared': selectionCleared,
    'scrollStable': scrollStable,
    'modeStable': modeStable,
    'pass': pass,
  };
  await File(
    '${output.path}/stress-body-preview-copy.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(evidence)}\n');
  return evidence;
}

/// Copies the complete body through the explicit detail viewer.
///
/// 历史行本身不会因后台补齐而升级：完整正文只来自用户打开的查看器，逐块累计到真实
/// 总长后由产品自己的复制按钮写入剪贴板，再与 canonical fixture 正文比对。关闭后
/// 查看器消失，行内预览长度保持不变。
Future<Map<String, Object?>> _copyThroughDetailViewer(
  FlutterDriverSession driver,
  Directory output,
  int expectedBodyCharacters,
  bool largeBody,
  String? itemId,
) async {
  final expectedBody = _canonicalBody(largeBody);
  final expectedHash = _fnv1a64(expectedBody).toRadixString(16);
  final before = TimelineObservation.parse(await driver.readSnapshot());
  final rowBefore = itemId == null ? null : before.item(itemId);
  final evidence = <String, Object?>{};
  if (itemId == null) {
    evidence['reason'] = 'no assistant body identity for the detail viewer';
    evidence['pass'] = false;
    return evidence;
  }
  final openKey = 'timeline-detail-open-$itemId-text';
  await driver.waitFor(
    find.byValueKey(openKey),
    timeout: const Duration(seconds: 30),
  );
  await driver.rawTap(
    find.byValueKey(openKey),
    timeout: const Duration(seconds: 30),
  );
  // 逐块累计：等待查看器报告的真实字符数达到条目声明的总长。
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  DetailViewerRead? progress;
  var sawPartial = false;
  var viewerOpened = false;
  while (DateTime.now().isBefore(deadline)) {
    progress = await DetailViewerRead.read(driver.requestData);
    if (progress.open) viewerOpened = true;
    final characters = progress.characters;
    if (characters > 0 && characters < expectedBodyCharacters) {
      sawPartial = true;
    }
    if (characters >= expectedBodyCharacters) break;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final loadedCharacters = progress?.characters ?? 0;
  final loadedHash = progress?.hash;
  await File('${output.path}/stress-body-detail-viewer.png')
      .writeAsBytes(await driver.screenshot());
  await driver.waitFor(
    find.byValueKey('timeline-detail-copy'),
    timeout: const Duration(seconds: 15),
  );
  await driver.rawTap(
    find.byValueKey('timeline-detail-copy'),
    timeout: const Duration(seconds: 30),
  );
  final clipboard = await ClipboardRead.read(driver.requestData);
  final clipboardHash = clipboard.hash;
  final clipboardCharacters = clipboard.characters;
  await driver.rawTap(
    find.byValueKey('timeline-detail-close'),
    timeout: const Duration(seconds: 30),
  );
  // 关闭后查看器消失；等待显式的关闭事实，不用固定 sleep。
  final closeDeadline = DateTime.now().add(const Duration(seconds: 15));
  var closed = false;
  while (DateTime.now().isBefore(closeDeadline)) {
    final state = await DetailViewerRead.read(driver.requestData);
    if (!state.open) {
      closed = true;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final after = TimelineObservation.parse(await driver.readSnapshot());
  final rowAfter = after.item(itemId);
  final previewUnchanged =
      rowBefore != null &&
      rowAfter != null &&
      before.timelineEpoch == after.timelineEpoch &&
      rowBefore.id == rowAfter.id &&
      rowBefore.appendSeq == rowAfter.appendSeq &&
      jsonEncode(rowBefore.frozenFields()) ==
          jsonEncode(rowAfter.frozenFields());
  evidence.addAll(<String, Object?>{
    'itemId': itemId,
    'expectedCharacters': expectedBodyCharacters,
    'expectedHash': expectedHash,
    'loadedCharacters': loadedCharacters,
    'loadedHash': loadedHash,
    'clipboardCharacters': clipboardCharacters,
    'clipboardHash': clipboardHash,
    'viewerOpened': viewerOpened,
    'viewerClosed': closed,
    'rowPreviewUnchanged': previewUnchanged,
    // 理论块数只是结构推算（ceil(bytes/64KiB)）；实际读了几块不要求被帧采样到，
    // 快速多块读取允许在一次轮询前完成。`sawPartialChunk` 仅记录。
    'theoreticalChunks': (expectedBodyCharacters / (64 * 1024)).ceil(),
    'sawPartialChunk': sawPartial,
    // 完整字节 + fixture 原文 hash + 真实查看器/剪贴板一致 + 关闭即证明保真。
    'pass':
        viewerOpened &&
        loadedCharacters == expectedBodyCharacters &&
        loadedHash == expectedHash &&
        clipboardCharacters == expectedBodyCharacters &&
        clipboardHash == expectedHash &&
        closed &&
        previewUnchanged,
  });
  await File(
    '${output.path}/stress-body-detail-copy.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(evidence)}\n');
  return evidence;
}

/// The exact body the scripted account streams: every increment is
/// `body-%05d ` (plus the large-scenario `W` pad), reconstructed here so the
/// clipboard comparison never trusts the delivered domain text.
String _canonicalBody(bool largeBody) {
  final buffer = StringBuffer();
  for (var ordinal = 0; ordinal < _expectedTokens; ordinal += 1) {
    buffer.write('body-${ordinal.toString().padLeft(5, '0')} ');
    if (largeBody) {
      buffer.write('W' * _largeBodyPad);
      buffer.write(' ');
    }
  }
  return buffer.toString();
}

Map<String, dynamic>? _decodeDriverMap(String raw) {
  final decoded = jsonDecode(raw);
  return decoded is Map<String, dynamic> ? decoded : null;
}

String _headOf(String text) =>
    text.substring(0, text.length < 64 ? text.length : 64);

String _tailOf(String text) =>
    text.substring(text.length < 64 ? 0 : text.length - 64);

/// FNV-1a over the code units. Must stay identical to the Driver-side helper.
int _fnv1a64(String text) {
  var hash = 0xcbf29ce484222325;
  for (var index = 0; index < text.length; index += 1) {
    hash ^= text.codeUnitAt(index);
    hash = hash * 0x100000001b3;
  }
  return hash;
}
