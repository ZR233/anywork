import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'pointer_scroll.dart';
import 'timeline_observation.dart';
import 'tool_probe.dart';

/// Real paced output, explicit page boundaries, frozen coverage and UI recovery.
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
    Map<String, Object?>? lastObservation;
    while (DateTime.now().isBefore(deadline)) {
      final state = await driver.readSnapshot();
      if (ready(state)) return state;
      final timeline = state['timeline'] as Map?;
      lastObservation = <String, Object?>{
        'olderErrorCode': timeline?['olderErrorCode'],
        'olderErrorCorrelationId': timeline?['olderErrorCorrelationId'],
        'olderError': timeline?['olderError'],
        'mode': timeline?['mode'],
        'connection': timeline?['connection'],
        'generation': timeline?['generation'],
        'appliedVersion': timeline?['appliedVersion'],
        'itemCount': timeline?['itemCount'],
        'loadingOlder': timeline?['loadingOlder'],
        'busy': busy(state),
      };
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError(
      'Streaming history did not settle: $stage; '
      'lastObservation=${jsonEncode(lastObservation)}',
    );
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
    throw StateError('Streaming history did not expose its page boundary');
  }
  final start = TimelineObservation.parse(frozen);
  final failureCode = (frozen['timeline'] as Map)['olderErrorCode'];
  final failureCorrelation =
      (frozen['timeline'] as Map)['olderErrorCorrelationId'];
  final continuityExpired =
      failureCode == 'protocol' &&
      failureCorrelation == 'timeline-page-continuity';
  if (failureCode != 'busy' && !continuityExpired) {
    throw StateError(
      'Unexpected page failure $failureCode/$failureCorrelation: '
      '${start.olderError}',
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
  await File('${output.path}/streaming-history-boundary.png')
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
  final retryAdmission = await driver.sendCommand(
    ToolProbe(find.byValueKey('timeline-retry-older'), 'retryOlder'),
  );
  final retrySamples = retryAdmission['samples'] as List;
  if (!retrySamples.any(
        (value) =>
            value['threadId'] == start.threadId &&
            value['generation'] == start.generation &&
            value['loadingOlder'] == true &&
            value['olderErrorCode'] == null,
      ) ||
      retrySamples.last['loadingOlder'] != false) {
    throw StateError('Retry UI did not publish admission and completion');
  }
  final retried = await until('retry after admission', (state) {
    if (!settled(state)) return false;
    final content = TimelineObservation.parse(state);
    final timeline = state['timeline'] as Map;
    return (content.olderError == null &&
            content.itemCount > start.itemCount) ||
        (timeline['olderErrorCode'] == 'protocol' &&
            timeline['olderErrorCorrelationId'] == 'timeline-page-continuity');
  });
  final retry = TimelineObservation.parse(retried);
  retry.requireConsistentIds();
  if (retry.generation != start.generation ||
      !retry.isHistory ||
      retry.appliedVersion != start.appliedVersion ||
      !start.itemIds.every(retry.itemIds.contains) ||
      retry.itemCount - start.itemCount > 32) {
    throw StateError('Retry lost or replaced the frozen display');
  }
  final coverageExpired = retry.olderError != null;
  if (coverageExpired &&
      (body(frozen) != body(retried) ||
          retry.itemCount != start.itemCount ||
          retry.olderCursor != start.olderCursor ||
          !retry.hasOlder ||
          !retry.hasNewOutput)) {
    throw StateError('Expired coverage changed the frozen History');
  }
  await File('${output.path}/streaming-history-retry.png')
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
    'failureCorrelationId': failureCorrelation,
    'boundary': continuityExpired ? 'coverageExpired' : 'storageBusy',
    'retryAdmission': retryAdmission,
    'before': start.summary(),
    'frozenAfterCompletion': end.summary(),
    'bodyUnchanged': body(frozen) == body(completed),
    'retryOutcome': coverageExpired ? 'coverageExpired' : 'pageAppended',
    'retryErrorCode': (retried['timeline'] as Map)['olderErrorCode'],
    'retryErrorCorrelationId':
        (retried['timeline'] as Map)['olderErrorCorrelationId'],
    'retried': retry.summary(),
    'returnedLive': live.summary(),
    'pass': true,
  };
  await File('${output.path}/streaming-history.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  return report;
}
