import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'pointer_scroll.dart';
import 'timeline_observation.dart';

/// Real paced output overlaps independent durable page reads in one generation.
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

  TimelineObservation? lastContent;
  void retainCompleted(TimelineObservation current) {
    current.requireConsistentIds();
    final previous = lastContent;
    if (current.timelineEpoch == null ||
        current.itemIds.toSet().length != current.itemCount ||
        !current.appendSeqAscending) {
      throw StateError(
        'Completed timeline lacks epoch or unique ordered atoms',
      );
    }
    if (previous != null) {
      final oldIds = previous.itemIds.toSet();
      final retainedOrder = current.itemIds.where(oldIds.contains).toList();
      if (current.threadId != previous.threadId ||
          current.generation != previous.generation ||
          current.timelineEpoch != previous.timelineEpoch ||
          jsonEncode(retainedOrder) != jsonEncode(previous.itemIds)) {
        throw StateError('Streaming/page update replaced frozen coverage');
      }
      for (final item in previous.items) {
        final retained = current.item(item.id);
        if (retained == null ||
            jsonEncode(item.frozenFields()) !=
                jsonEncode(retained.frozenFields())) {
          throw StateError(
            'Streaming/page update changed frozen atom ${item.id}',
          );
        }
      }
    }
    lastContent = current;
  }

  _ResponseProgress? activity;
  _ResponseProgress? readProgress(Map<String, dynamic> state) {
    final current = _ResponseProgress.optional(state);
    final previous = activity;
    if (current != null && previous != null) {
      current.requireContinuationOf(previous);
    }
    if (current != null) activity = current;
    return current;
  }

  Future<Map<String, dynamic>> until(
    String stage,
    bool Function(Map<String, dynamic>) ready,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    Map<String, Object?>? lastObservation;
    while (DateTime.now().isBefore(deadline)) {
      final state = await driver.readSnapshot();
      final timeline = state['timeline'] as Map?;
      lastObservation = <String, Object?>{
        'olderErrorCode': timeline?['olderErrorCode'],
        'olderErrorCorrelationId': timeline?['olderErrorCorrelationId'],
        'olderError': timeline?['olderError'],
        'mode': timeline?['mode'],
        'connection': timeline?['connection'],
        'generation': timeline?['generation'],
        'itemCount': timeline?['itemCount'],
        'loadingOlder': timeline?['loadingOlder'],
        'busy': busy(state),
      };
      if (timeline?['connection'] == 'failed') {
        // Read the product's existing error notice, not a second error source.
        // Keep the failed connection as the cause even if diagnostics fail.
        try {
          lastObservation['connectionNotice'] = await driver.getText(
            find.descendant(
              of: find.descendant(
                of: find.byValueKey('timeline-connection-notice'),
                matching: find.byType('Expanded'),
              ),
              matching: find.byType('Text'),
            ),
          );
          await File('${output.path}/timeline-streaming-connection-failed.png')
              .writeAsBytes(await driver.screenshot());
        } catch (error) {
          lastObservation['diagnosticError'] = '$error';
        }
        await File('${output.path}/timeline-streaming-connection-failed.json')
            .writeAsString(jsonEncode(lastObservation));
        throw StateError(
          'Streaming history connection failed: $stage; '
          'lastObservation=${jsonEncode(lastObservation)}',
        );
      }
      final content = TimelineObservation.optional(state);
      if (content?.ready == true) {
        retainCompleted(content!);
        if (content.olderError != null) {
          throw StateError(
            'Independent durable page failed: $stage; '
            'lastObservation=${jsonEncode(lastObservation)}',
          );
        }
      }
      readProgress(state);
      if (ready(state)) return state;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError(
      'Streaming history did not settle: $stage; '
      'lastObservation=${jsonEncode(lastObservation)}',
    );
  }

  final running = await until(
    'live content',
    (state) =>
        busy(state) &&
        settled(state) &&
        TimelineObservation.parse(state).isLive &&
        TimelineObservation.parse(state).hasOlder &&
        readProgress(state) != null,
  );
  final initial = TimelineObservation.parse(running);
  final initialActivity = readProgress(running)!;
  await driver.sendCommand(
    PointerScroll(find.byValueKey('timeline-scrollable'), -240),
  );
  final firstHistory = await until(
    'History during output',
    (state) =>
        busy(state) &&
        settled(state) &&
        TimelineObservation.parse(state).isHistory,
  );
  final beforeReturn = TimelineObservation.parse(firstHistory);
  await driver.rawTap(find.byValueKey('timeline-return-live'));
  final returned = await until(
    'return Live during output',
    (state) =>
        busy(state) &&
        settled(state) &&
        TimelineObservation.parse(state).isLive &&
        TimelineScrollObservation.parse(state).atLiveEdge,
  );
  final returnedLive = TimelineObservation.parse(returned);
  if (returnedLive.generation != beforeReturn.generation ||
      returnedLive.timelineEpoch != beforeReturn.timelineEpoch ||
      returnedLive.olderCursor != beforeReturn.olderCursor ||
      returnedLive.hasOlder != beforeReturn.hasOlder ||
      returnedLive.hasNewOutput) {
    throw StateError('Return Live replaced the page window or reading intent');
  }
  await driver.sendCommand(
    PointerScroll(find.byValueKey('timeline-scrollable'), -240),
  );
  await until(
    'reading History again',
    (state) =>
        busy(state) &&
        settled(state) &&
        TimelineObservation.parse(state).isHistory,
  );
  final pages = <Map<String, Object?>>[];
  // Durable inventory was produced by the preceding, completed 2000-item call.
  // Every read must succeed while this separate single response keeps growing.
  for (var read = 1; read <= 3; read++) {
    final beforeState = await until(
      'before page $read',
      (state) => busy(state) && settled(state) && readProgress(state) != null,
    );
    final before = TimelineObservation.parse(beforeState);
    final beforeActivity = readProgress(beforeState)!;
    if (!before.isHistory || !before.hasOlder || before.olderCursor == null) {
      throw StateError('Streaming page has no durable History boundary');
    }
    final pageResult = jsonDecode(await driver.requestData('load-older'));
    final afterState = await until('page $read with response growth', (state) {
      final current = TimelineObservation.parse(state);
      final progress = readProgress(state);
      return busy(state) &&
          settled(state) &&
          current.itemCount > before.itemCount &&
          progress != null &&
          progress.text.length > beforeActivity.text.length;
    });
    final after = TimelineObservation.parse(afterState);
    final afterActivity = readProgress(afterState)!;
    final delivered = after.itemCount - before.itemCount;
    if (!after.isHistory ||
        delivered < 1 ||
        delivered > 32 ||
        after.itemIds.first == before.itemIds.first ||
        after.itemIds.last != before.itemIds.last ||
        after.olderCursor == before.olderCursor ||
        !after.hasOlder ||
        after.olderCursor == null) {
      throw StateError('Streaming page did not prepend 1..32 durable atoms');
    }
    pages.add(<String, Object?>{
      'page': read,
      'requestResult': pageResult,
      'before': before.summary(),
      'after': after.summary(),
      'delivered': delivered,
      'itemIds': after.itemIds,
      'busyBeforeAndAfter': true,
      'activityBefore': beforeActivity.summary(),
      'activityAfter': afterActivity.summary(),
      'responseGrew': true,
      'frozenFieldsRetained': true,
    });
  }
  final start = lastContent!;
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
      !end.hasNewOutput ||
      end.itemCount <= start.itemCount ||
      end.items.last.appendSeq <= start.items.last.appendSeq) {
    throw StateError('History did not retain and append completed live output');
  }
  final responses = end.items
      .where(
        (item) =>
            item.appendSeq > start.items.last.appendSeq && item.isFinalAnswer,
      )
      .toList();
  if (responses.length != 1) {
    throw StateError('Single response did not become one completed final atom');
  }
  final response = responses.single;
  // Timeline atoms publish bounded previews; detail metadata declares the full
  // body length. Omitted preview bytes do not mean the stored body was lost.
  final responseBytes = response.textTotalBytes ?? response.textBytes;
  if (responseBytes != 128000 * 2) {
    throw StateError(
      'Completed reference body is incomplete: '
      'bytes=$responseBytes',
    );
  }
  await File('${output.path}/streaming-history-frozen.png')
      .writeAsBytes(await driver.screenshot());
  await driver.rawTap(find.byValueKey('timeline-return-live'));
  final stability = TimelineViewportStability();
  final latest = await until(
    'return Live',
    (state) =>
        stability.accept(state) &&
        TimelineObservation.parse(state).isLive &&
        TimelineScrollObservation.parse(state).atLiveEdge,
  );
  final live = TimelineObservation.parse(latest);
  if (live.generation != end.generation ||
      live.timelineEpoch != end.timelineEpoch ||
      jsonEncode(live.itemIds) != jsonEncode(end.itemIds) ||
      live.olderCursor != end.olderCursor ||
      live.hasOlder != end.hasOlder ||
      live.hasNewOutput) {
    throw StateError('Return Live replaced the completed loaded window');
  }
  await File('${output.path}/streaming-history-live.png')
      .writeAsBytes(await driver.screenshot());
  final report = <String, Object?>{
    'referenceTokens': 128000,
    'independentItems': 1,
    'initial': initial.summary(),
    'initialActivity': initialActivity.summary(),
    'firstReturnLive': returnedLive.summary(),
    'pages': pages,
    'beforeCompletion': start.summary(),
    'completedInHistory': end.summary(),
    'completedResponseId': response.id,
    'completedResponseBytes': responseBytes,
    'completedResponsePreviewBytes': response.textBytes,
    'completedResponseOmittedPreviewBytes': response.omittedBytes,
    'frozenFieldsRetained': true,
    'returnedLive': live.summary(),
    'pass': true,
  };
  await File('${output.path}/streaming-history.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  return report;
}

/// The existing typed currentActivity projection carries original model part
/// identity. Only growth of that same response proves output/page overlap.
final class _ResponseProgress {
  _ResponseProgress({
    required this.identity,
    required this.turnId,
    required this.executionId,
    required this.itemId,
    required this.text,
  });

  static _ResponseProgress? optional(Map<String, dynamic> state) {
    final observation = conversationActivityContentObservation(state);
    if (observation == null) return null;
    final activity = jsonDecode(observation) as Map;
    final parts = activity['responseParts'] as List;
    if (parts.isEmpty) return null;
    if (parts.length != 1) {
      throw StateError('Single-item stream published multiple response parts');
    }
    final part = parts.single as Map;
    final identity = activity['identity'];
    final turnId = activity['turnId'];
    final executionId = activity['executionId'];
    final itemId = part['itemId'];
    final text = part['text'];
    if (identity is! String ||
        identity.isEmpty ||
        turnId is! String ||
        turnId.isEmpty ||
        (executionId != null && executionId is! String) ||
        itemId is! String ||
        itemId.isEmpty ||
        text is! String) {
      throw StateError('Streaming response lacks typed activity/part identity');
    }
    return _ResponseProgress(
      identity: identity,
      turnId: turnId,
      executionId: executionId as String?,
      itemId: itemId,
      text: text,
    );
  }

  final String identity;
  final String turnId;
  final String? executionId;
  final String itemId;
  final String text;

  void requireContinuationOf(_ResponseProgress previous) {
    if (identity != previous.identity ||
        turnId != previous.turnId ||
        executionId != previous.executionId ||
        itemId != previous.itemId ||
        !text.startsWith(previous.text)) {
      throw StateError(
        'Streaming activity/response changed identity or regressed',
      );
    }
  }

  Map<String, Object?> summary() => <String, Object?>{
    'identity': identity,
    'turnId': turnId,
    'executionId': executionId,
    'itemId': itemId,
    'responseBytes': utf8.encode(text).length,
  };
}
