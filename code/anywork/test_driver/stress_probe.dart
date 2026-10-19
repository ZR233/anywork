import 'dart:convert';
import 'dart:io';

import 'flutter_driver_session.dart';
import 'timeline_observation.dart';

/// Upper bound on the `load-older` pages the probe drives.
///
/// 分页深度只用于证明真实页请求确实向更早方向前进；不再有 96 条窗口容量，也不再
/// 要求“窗口被裁回容量”来证明内存正确——前端已加载数据随访问页增长是明示取舍。
const _maxOlderPages = 8;

/// Milliseconds the probe waits for one `load-older` page to reach the display.
const _pageMoveTimeoutMillis = 20000;

/// 当前展示代次的身份与分页事实。
///
/// 严格读取新顶层 `timeline`：缺失字段是观测失败，不是“空窗口”。
TimelineObservation? _timeline(Map<String, dynamic> snapshot) =>
    TimelineObservation.optional(snapshot);

bool _sameIds(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// The probe's paging evidence file, a sibling of the sample report
/// (`probe-report.json` -> `probe-report.paging.json`).
File _pagingEvidenceFile(String reportPath) {
  final separator = reportPath.lastIndexOf(Platform.pathSeparator);
  final dot = reportPath.lastIndexOf('.');
  if (dot > separator) {
    return File(
      '${reportPath.substring(0, dot)}.paging${reportPath.substring(dot)}',
    );
  }
  return File('$reportPath.paging.json');
}

/// Polls the live display (read-only, bounded, no screenshots) until
/// `load-older` moved it. Stops early when the display reports no older content,
/// so a genuinely exhausted history fails fast instead of waiting out the
/// timeout.
Future<Map<String, dynamic>> _awaitPageMove(
  FlutterDriverSession driver,
  TimelineObservation before,
) async {
  final deadline = DateTime.now().add(
    const Duration(milliseconds: _pageMoveTimeoutMillis),
  );
  var snapshot = await driver.readSnapshot();
  while (DateTime.now().isBefore(deadline)) {
    final current = _timeline(snapshot);
    if (current != null &&
        (!_sameIds(current.itemIds, before.itemIds) ||
            current.loadingOlder != before.loadingOlder)) {
      return snapshot;
    }
    if (current != null && !current.hasOlder && !current.loadingOlder) {
      return snapshot;
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    snapshot = await driver.readSnapshot();
  }
  return snapshot;
}

/// Drives the real `load-older` command one page at a time, recording one
/// evidence step per page.
///
/// Each step proves the display really moved toward older content (identities
/// were prepended in canonical order while nothing already displayed was
/// trimmed) instead of inferring a move from a counter. The loop is bounded by
/// [_maxOlderPages] and never polls forever.
Future<Map<String, Object?>> _pageOlder(
  FlutterDriverSession driver,
  Map<String, dynamic> snapshot,
  List<Map<String, Object?>> pages,
) async {
  var current = snapshot;
  var previous = _timeline(snapshot);
  var cursorAdvanced = false;
  var generationStable = true;
  var modeStable = true;
  var retryVisible = false;
  for (var page = 1; page <= _maxOlderPages; page += 1) {
    if (previous == null || !previous.hasOlder) break;
    final before = previous;
    await driver.requestData('load-older');
    final next = await _awaitPageMove(driver, before);
    final after = _timeline(next);
    if (after == null) {
      pages.add(<String, Object?>{'page': page, 'observed': false});
      break;
    }
    final retained = before.itemIds.every(after.itemIds.contains);
    final grew = after.itemCount > before.itemCount;
    final movedOlder =
        grew &&
        retained &&
        before.itemIds.isNotEmpty &&
        after.itemIds.isNotEmpty &&
        after.itemIds.first != before.itemIds.first &&
        after.itemIds.last == before.itemIds.last;
    final cursorMoved =
        after.olderCursor != before.olderCursor || after.hasOlder == false;
    if (cursorMoved) cursorAdvanced = true;
    if (after.generation != before.generation) generationStable = false;
    if (after.mode != before.mode) modeStable = false;
    if (after.olderError != null) retryVisible = true;
    pages.add(<String, Object?>{
      'page': page,
      'beforeItems': before.itemCount,
      'beforeFirst': before.itemIds.isEmpty ? null : before.itemIds.first,
      'afterItems': after.itemCount,
      'afterFirst': after.itemIds.isEmpty ? null : after.itemIds.first,
      'afterLast': after.itemIds.isEmpty ? null : after.itemIds.last,
      'delivered': after.itemCount - before.itemCount,
      'unique': after.itemIds.toSet().length == after.itemIds.length,
      'orderAscending': after.ordinalAscending,
      'grewTowardOlder': movedOlder,
      'identityRetained': retained,
      'olderCursorBefore': before.olderCursor,
      'olderCursorAfter': after.olderCursor,
      'cursorAdvanced': cursorMoved,
      'hasOlder': after.hasOlder,
      'loadingOlder': after.loadingOlder,
      'olderError': after.olderError,
      'mode': after.mode,
      'generation': after.generation,
    });
    current = next;
    previous = after;
    if (!grew) break;
  }
  final finalTimeline = _timeline(current);
  return <String, Object?>{
    'paged': pages.isNotEmpty,
    'pageCount': pages.length,
    'movedOlder': pages.any((page) => page['grewTowardOlder'] == true),
    'identityRetained':
        pages.isNotEmpty &&
        pages.every((page) => page['identityRetained'] == true),
    'orderMonotonic':
        pages.isNotEmpty &&
        pages.every((page) => page['orderAscending'] == true),
    'uniqueIds':
        pages.isNotEmpty && pages.every((page) => page['unique'] == true),
    'cursorAdvanced': cursorAdvanced,
    'generationStable': generationStable,
    'modeStable': modeStable,
    'retryVisibleOnError': retryVisible,
    'finalItems': finalTimeline?.itemCount,
    'finalHasOlder': finalTimeline?.hasOlder,
    'finalOlderCursor': finalTimeline?.olderCursor,
    'finalMode': finalTimeline?.mode,
    'finalGeneration': finalTimeline?.generation,
  };
}

Future<void> main(List<String> args) async {
  if (args.length != 6) {
    stderr.writeln(
      'usage: stress_probe.dart VM_URL STOP_FILE REPORT_FILE READY_FILE FRAMES_FILE FINISHED_FILE',
    );
    exitCode = 64;
    return;
  }
  final stop = File(args[1]);
  final finished = File(args[5]);
  final pagingFile = _pagingEvidenceFile(args[2]);
  final pagingPages = <Map<String, Object?>>[];
  Map<String, Object?>? pagingSummary;
  final samples = <Map<String, Object?>>[];
  var lastReport = 0;
  Map<String, Object?>? authoritative;
  Map<String, Object?>? persistenceDiagnostics;
  var paginationStarted = false;
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);

  Future<void> writePagingEvidence({String? error}) async {
    final evidence = <String, Object?>{
      'maxPages': _maxOlderPages,
      'pages': pagingPages,
      ...?pagingSummary,
    };
    if (error != null) evidence['error'] = error;
    await pagingFile.writeAsString('${jsonEncode(evidence)}\n');
  }

  try {
    await driver.requestData('frame-start');
    await File(args[3]).writeAsString('ready\n');
    while (!await stop.exists()) {
      final started = DateTime.now().millisecondsSinceEpoch;
      try {
        final snapshot = await driver.readSnapshot();
        final workspace = snapshot['workspace'];
        final persistence = snapshot['persistence'];
        final usage = workspace is Map ? workspace['usage'] : null;
        final timeline = _timeline(snapshot);
        final scroll = TimelineScrollObservation.optional(snapshot);
        final kinds = timeline == null
            ? <String>{}
            : {for (final item in timeline.items) item.kind};
        final truncated = timeline == null
            ? 0
            : timeline.items.where((item) => item.textTruncated).length;
        final previewBytes = timeline == null
            ? 0
            : timeline.items.fold<int>(
                0,
                (total, item) => total + item.textBytes,
              );
        final streamCompleted =
            workspace is Map &&
            persistence is Map &&
            usage is Map &&
            (usage['outputTokens'] as num? ?? 0) >= 20000 &&
            workspace['isBusy'] == false &&
            workspace['syncState'] == 'ready' &&
            timeline != null &&
            persistence['kind'] == 'ready' &&
            persistence['pendingCommits'] == 0;
        if (!paginationStarted && streamCompleted && timeline.hasOlder) {
          // 流已可靠收束且仍有更早内容：驱动真实分页动作并记录每页边界。
          paginationStarted = true;
          try {
            pagingSummary = await _pageOlder(driver, snapshot, pagingPages);
            await writePagingEvidence();
          } catch (error) {
            await writePagingEvidence(error: error.toString());
            rethrow;
          }
          continue;
        }
        if (!await finished.exists() &&
            paginationStarted &&
            streamCompleted &&
            timeline.itemCount > 0 &&
            kinds.contains('agentMessage') &&
            // gui_stress_script emits messages and reasoning; tool execution is
            // covered by tool-scroll. Requiring a nonexistent tool never settles.
            kinds.contains('reasoning')) {
          await finished.writeAsString(
            '${DateTime.now().millisecondsSinceEpoch}\n',
          );
        }
        if (workspace is Map &&
            workspace['isBusy'] == false &&
            (usage is Map ? (usage['outputTokens'] as num? ?? 0) : 0) < 20000 &&
            started - lastReport >= 1000) {
          try {
            authoritative = (jsonDecode(
              await driver.requestData('thread-current'),
            ) as Map).cast<String, Object?>();
          } catch (_) {
            authoritative = {'error': 'unavailable'};
          }
        }
        if (persistence is Map &&
            persistence['kind'] == 'blocked' &&
            started - lastReport >= 1000) {
          try {
            persistenceDiagnostics = (jsonDecode(
              await driver.requestData('persistence-queue'),
            ) as Map).cast<String, Object?>();
          } catch (_) {
            persistenceDiagnostics = {'error': 'unavailable'};
          }
        }
        samples.add({
          'startedUnixMillis': started,
          'elapsedMillis': DateTime.now().millisecondsSinceEpoch - started,
          'ok': timeline != null,
          'itemCount': timeline?.itemCount,
          'itemIdsSample': timeline == null
              ? null
              : timeline.itemIds.length > 8
              ? timeline.itemIds.sublist(timeline.itemIds.length - 8)
              : timeline.itemIds,
          'mode': timeline?.mode,
          'generation': timeline?.generation,
          'connection': timeline?.connection,
          'appliedVersion': timeline?.appliedVersion,
          'hasOlder': timeline?.hasOlder,
          'olderCursor': timeline?.olderCursor,
          'loadingOlder': timeline?.loadingOlder,
          'olderError': timeline?.olderError,
          'hasNewOutput': timeline?.hasNewOutput,
          'preparingLive': timeline?.preparingLive,
          'truncatedItems': truncated,
          'previewTextBytes': previewBytes,
          'kinds': kinds.toList(),
          'scroll': scroll?.toJson(),
          'outputTokens': usage is Map ? usage['outputTokens'] : null,
          'authoritative': authoritative,
          'isBusy': workspace is Map ? workspace['isBusy'] : null,
          'syncState': workspace is Map ? workspace['syncState'] : null,
          'syncError': workspace is Map ? workspace['loadError'] : null,
          'persistenceKind': persistence is Map ? persistence['kind'] : null,
          'persistenceDiagnostics': persistenceDiagnostics,
          'persistenceErrorCode': persistence is Map
              ? persistence['errorCode']
              : null,
          'pendingCommits': persistence is Map
              ? persistence['pendingCommits']
              : null,
        });
      } catch (error) {
        samples.add({
          'startedUnixMillis': started,
          'elapsedMillis': DateTime.now().millisecondsSinceEpoch - started,
          'ok': false,
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
        });
      }
      // Keep only recent measurements when a manual session stays open for hours.
      if (samples.length > 20000) samples.removeRange(0, 1000);
      if (started - lastReport >= 1000) {
        await File(args[2]).writeAsString('${jsonEncode(samples)}\n');
        lastReport = started;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } finally {
    try {
      final frames = await driver.requestData('frame-stop');
      await File(args[4]).writeAsString('$frames\n');
    } catch (error) {
      await File(args[4])
          .writeAsString('${jsonEncode({'error': error.toString()})}\n');
    }
    try {
      // The paging evidence must survive a Driver failure as well, so a review
      // can still see whether the display ever moved.
      await writePagingEvidence();
    } catch (_) {
      // A failed evidence write must not mask the journey's own result or leak
      // the VM connection; the coordinator fails on the missing artifact.
    }
    await File(args[2]).writeAsString('${jsonEncode(samples)}\n');
    await driver.close();
  }
}
