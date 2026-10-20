import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'pointer_scroll.dart';
import 'timeline_observation.dart';

/// Real paced provider output, native page Busy and recovery through the UI.
/// No product state, storage rows or loading flags are injected.
Future<Map<String, Object?>> observeStreamingHistory(
  FlutterDriverSession driver,
  Directory output,
) async {
  bool busy(Map<String, dynamic> state) =>
      (state['workspace'] as Map?)?['isBusy'] == true;
  bool settled(Map<String, dynamic> state) {
    final content = TimelineObservation.optional(state);
    final scroll = TimelineScrollObservation.optional(state);
    return content?.ready == true &&
        content?.connection == 'ready' &&
        content?.loadingOlder == false &&
        scroll?.laidOut == true &&
        scroll?.isScrolling == false &&
        scroll?.generation == content?.generation;
  }

  String body(Map<String, dynamic> state) =>
      jsonEncode((state['timeline'] as Map)['items']);
  Future<Map<String, dynamic>> until(
    String stage,
    bool Function(Map<String, dynamic>) ready,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      final state = await driver.readSnapshot();
      if (ready(state)) return state;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('Streaming history did not settle: $stage');
  }

  await until(
    'live content',
    (state) =>
        busy(state) &&
        settled(state) &&
        (TimelineScrollObservation.parse(state).maxScrollExtent ?? 0) > 400,
  );
  await driver.sendCommand(
    PointerScroll(find.byValueKey('timeline-scrollable'), -240),
  );
  await until(
    'History during output',
    (state) =>
        busy(state) &&
        settled(state) &&
        TimelineObservation.parse(state).isHistory,
  );
  // Rejoin Live during output to establish a fresh latest page before reading
  // back beyond the hot window. This is the normal UI action, not a new seed.
  final previous = TimelineObservation.parse(await driver.readSnapshot());
  await driver.rawTap(find.byValueKey('timeline-return-live'));
  await until(
    'fresh latest during output',
    (state) =>
        busy(state) &&
        settled(state) &&
        TimelineObservation.parse(state).isLive &&
        TimelineObservation.parse(state).generation > previous.generation,
  );
  await driver.sendCommand(
    PointerScroll(find.byValueKey('timeline-scrollable'), -240),
  );
  await until(
    'reading fresh history',
    (state) =>
        busy(state) &&
        settled(state) &&
        TimelineObservation.parse(state).isHistory,
  );
  Map<String, dynamic>? frozen;
  for (var read = 0; read < 8; read++) {
    await driver.requestData('load-older');
    final state = await until('page $read', settled);
    if (!busy(state)) throw StateError('No real streaming/page overlap');
    if (TimelineObservation.parse(state).olderError != null) {
      frozen = state;
      break;
    }
  }
  if (frozen == null) {
    throw StateError('Uncommitted gap did not report a retryable page failure');
  }
  final start = TimelineObservation.parse(frozen);
  final failureCode = (frozen['timeline'] as Map)['olderErrorCode'];
  if (failureCode != 'busy') {
    throw StateError(
      'Expected the real native gap Busy, received $failureCode: ${start.olderError}',
    );
  }
  start.requireConsistentIds();
  if (!start.hasOlder || start.olderCursor == null || !start.isHistory) {
    throw StateError('Uncommitted preview range was mistaken for EOF');
  }
  await driver.waitFor(
    find.byValueKey('timeline-retry-older'),
    timeout: const Duration(seconds: 10),
  );
  await File('${output.path}/streaming-history-busy.png')
      .writeAsBytes(await driver.screenshot());
  final completed = await until('background completion', (state) {
    final workspace = state['workspace'] as Map?;
    final persistence = state['persistence'] as Map?;
    return !busy(state) &&
        settled(state) &&
        (workspace?['lastTurn'] as Map?)?['status'] == 'completed' &&
        persistence?['kind'] == 'ready' &&
        persistence?['pendingCommits'] == 0;
  });
  final end = TimelineObservation.parse(completed);
  if (!end.isHistory ||
      end.generation != start.generation ||
      end.appliedVersion != start.appliedVersion ||
      body(frozen) != body(completed) ||
      !end.hasNewOutput) {
    throw StateError('Background output changed the frozen History');
  }
  await File('${output.path}/streaming-history-frozen.png')
      .writeAsBytes(await driver.screenshot());
  await driver.rawTap(find.byValueKey('timeline-retry-older'));
  final recovered = await until(
    'retry after admission',
    (state) =>
        settled(state) &&
        TimelineObservation.parse(state).olderError == null &&
        TimelineObservation.parse(state).itemCount > start.itemCount,
  );
  final recovery = TimelineObservation.parse(recovered);
  recovery.requireConsistentIds();
  if (recovery.generation != start.generation ||
      !recovery.isHistory ||
      !start.itemIds.every(recovery.itemIds.contains) ||
      recovery.itemCount - start.itemCount > 32) {
    throw StateError('Retry lost or replaced the frozen display');
  }
  await File('${output.path}/streaming-history-recovered.png')
      .writeAsBytes(await driver.screenshot());
  await driver.rawTap(find.byValueKey('timeline-return-live'));
  final stability = TimelineViewportStability();
  final latest = await until(
    'return Live',
    (state) =>
        stability.accept(state) &&
        TimelineObservation.parse(state).isLive &&
        TimelineScrollObservation.parse(state).atLiveEdge &&
        TimelineObservation.parse(state).generation > start.generation,
  );
  final live = TimelineObservation.parse(latest);
  if (!live.itemIds.last.contains('stress-item-19999') ||
      live.items.last.ordinal <= start.items.last.ordinal) {
    throw StateError('Return Live did not reveal genuinely newer output');
  }
  await File('${output.path}/streaming-history-live.png')
      .writeAsBytes(await driver.screenshot());
  final report = <String, Object?>{
    'busyDuringFailure': busy(frozen),
    'failure': '${start.olderError}',
    'failureCode': failureCode,
    'before': start.summary(),
    'frozenAfterCompletion': end.summary(),
    'bodyUnchanged': body(frozen) == body(completed),
    'recovered': recovery.summary(),
    'returnedLive': live.summary(),
    'pass': true,
  };
  await File('${output.path}/streaming-history.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  return report;
}
