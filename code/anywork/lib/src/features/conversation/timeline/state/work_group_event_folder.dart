import 'package:anywork_client/conversation.dart';

import 'chat_item_presentation.dart';
import 'timeline_display_models.dart';
import 'timeline_history_projection.dart';

final class WorkGroupFoldResult {
  const WorkGroupFoldResult({
    required this.entries,
    required this.missingCallIds,
  });

  final List<DisplayMemberHead> entries;
  final List<String> missingCallIds;
}

/// Folds atomic History events inside one WorkRange into collapsed display
/// member rows keyed by callId / entityId / eventId without mutating History.
abstract final class WorkGroupEventFolder {
  static WorkGroupFoldResult fold({
    required List<HistoryEventRecord> rangeEvents,
    Map<String, List<HistoryEventRecord>> backfilledCallEvents = const {},
    Set<String> attemptedCallBackfills = const {},
  }) {
    final buckets = <String, _FoldBucket>{};
    for (final event in rangeEvents) {
      final String key;
      final String? callId;
      if (event.callId case final id? when id.isNotEmpty) {
        key = 'call:$id';
        callId = id;
      } else if (event.entityId case final id? when id.isNotEmpty) {
        key = 'entity:$id';
        callId = null;
      } else {
        key = 'event:${event.eventId}';
        callId = null;
      }
      final bucket = buckets.putIfAbsent(
        key,
        () => _FoldBucket(key: key, firstSeqInRange: event.seq, callId: callId),
      );
      if (event.seq < bucket.firstSeqInRange) {
        bucket.firstSeqInRange = event.seq;
      }
      bucket.inRange.add(event);
    }

    final missingCallIds = <String>[];
    final entries = <DisplayMemberHead>[];
    for (final bucket in buckets.values) {
      final combined = <String, HistoryEventRecord>{
        if (bucket.callId != null)
          for (final prior in backfilledCallEvents[bucket.callId!] ?? const [])
            prior.eventId: prior,
        for (final event in bucket.inRange) event.eventId: event,
      }.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));

      if (bucket.callId case final callId?) {
        final hasCalled = combined.any((event) => event.kind == 'tool_called');
        if (!hasCalled && !attemptedCallBackfills.contains(callId)) {
          missingCallIds.add(callId);
        }
      }

      entries.add(
        DisplayMemberHead(
          memberKey: bucket.key,
          memberOrder: bucket.firstSeqInRange,
          record: _mergeEvents(combined, memberKey: bucket.key),
        ),
      );
    }

    entries.sort((a, b) => a.memberOrder.compareTo(b.memberOrder));
    return WorkGroupFoldResult(
      entries: List.unmodifiable(entries),
      missingCallIds: List.unmodifiable(missingCallIds),
    );
  }

  static DisplayRecord _mergeEvents(
    List<HistoryEventRecord> events, {
    required String memberKey,
  }) {
    if (events.length == 1) {
      return TimelineHistoryProjection.recordFromEvent(
        events.single,
        idOverride: memberKey,
      );
    }

    final records = [
      for (final event in events)
        TimelineHistoryProjection.recordFromEvent(event, idOverride: memberKey),
    ];
    final latest = records.last;
    final latestPre = latest.predecodedPresentation;
    if (latestPre != null &&
        latestPre.compatibility != ChatItemCompatibility.current) {
      return latest;
    }

    final mergedBodies = <String, ChatBodyPresentation>{};
    Map<String, Object?>? mergedInvocation;
    int? earliestStartedAt;
    String? fallbackContract;
    String? runId;
    String? callId;
    ChatToolIdentity? tool;
    DateTime? createdAt;
    String? historyEventId;
    String? historyDetailEventId;
    final mergedData = <String, Object?>{};
    String? mergedType;

    for (final current in records) {
      earliestStartedAt ??= current.atom.startedAt;
      runId ??= current.runId;
      callId ??= current.callId;
      if (current.atom.tool != null) tool = current.atom.tool;
      historyEventId = current.historyEventId ?? historyEventId;
      historyDetailEventId =
          current.historyDetailEventId ?? historyDetailEventId;

      final pre = current.predecodedPresentation;
      if (pre == null || pre.compatibility != ChatItemCompatibility.current) {
        continue;
      }
      mergedType = pre.type;
      fallbackContract = pre.presentationContract ?? fallbackContract;
      createdAt = pre.createdAt ?? createdAt;
      for (final body in pre.bodies) {
        mergedBodies[body.key] = body;
      }
      for (final entry in pre.data.entries) {
        if (entry.key == 'invocation' && entry.value is Map<String, Object?>) {
          final inv = Map<String, Object?>.of(
            entry.value as Map<String, Object?>,
          );
          mergedInvocation = {...?mergedInvocation, ...inv};
          mergedData['invocation'] = Map<String, Object?>.unmodifiable(
            mergedInvocation,
          );
        } else {
          mergedData[entry.key] = entry.value;
        }
      }
    }

    final latestPreCurrent =
        latestPre != null &&
            latestPre.compatibility == ChatItemCompatibility.current
        ? latestPre
        : null;
    final foldedPresentation = latestPreCurrent == null
        ? latestPre
        : ChatItemPresentation(
            id: memberKey,
            compatibility: latestPreCurrent.compatibility,
            type: mergedType ?? latestPreCurrent.type,
            data: Map<String, Object?>.unmodifiable(mergedData),
            bodies: List<ChatBodyPresentation>.unmodifiable(
              mergedBodies.values,
            ),
            raw: latestPreCurrent.raw,
            byteLength: latestPreCurrent.byteLength,
            createdAt: createdAt ?? latestPreCurrent.createdAt,
            authorId: latestPreCurrent.authorId,
            presentationContract:
                latestPreCurrent.presentationContract ?? fallbackContract,
            diagnostic: latestPreCurrent.diagnostic,
          );

    final latestAtom = latest.atom;
    final mergedAtom = ChatAtom(
      id: latestAtom.id,
      source: latestAtom.source,
      sourceState: latestAtom.sourceState,
      sourceOrder: latestAtom.sourceOrder,
      kind: latestAtom.kind,
      delivery: latestAtom.delivery,
      lifecycle: latestAtom.lifecycle,
      turnId: latestAtom.turnId,
      attemptId: latestAtom.attemptId,
      tool: tool ?? latestAtom.tool,
      wait: latestAtom.wait,
      textChannel: latestAtom.textChannel,
      contentPresent: latestAtom.contentPresent,
      startedAt: earliestStartedAt ?? latestAtom.startedAt,
      finishedAt: latestAtom.finishedAt,
      contents: latestAtom.contents,
      payload: latestAtom.payload,
    );

    return DisplayRecord(
      atom: mergedAtom,
      contentSource: latest.contentSource,
      startFact: latest.startFact,
      endFact: latest.endFact,
      historyEventId: historyEventId,
      historyDetailEventId: historyDetailEventId,
      runId: latest.runId ?? runId,
      isTerminalHistory: latest.isTerminalHistory,
      isFrozenHistory: latest.isFrozenHistory,
      callId: latest.callId ?? callId,
      predecodedPresentation: foldedPresentation,
      immutableRecord: latest.immutableRecord,
      currentContents: latest.currentContents,
    );
  }
}

final class _FoldBucket {
  _FoldBucket({required this.key, required this.firstSeqInRange, this.callId});

  final String key;
  int firstSeqInRange;
  final String? callId;
  final List<HistoryEventRecord> inRange = [];
}
