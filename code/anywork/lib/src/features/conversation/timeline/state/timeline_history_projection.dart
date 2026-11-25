import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart'
    show StudioModelRecoveryNotice, ThreadTextChannel;

import 'chat_item_presentation.dart';
import 'timeline_display_models.dart';

/// Projects direct History timeline entries and adjacent folded work intervals
/// onto Timeline display blocks, and converts atomic HistoryEventRecord values
/// into DisplayRecords without dropping single unknown/malformed entries.
abstract final class TimelineHistoryProjection {
  static List<DisplayBlock> blocksFromEntries(
    List<HistoryTimelineEntry> ascendingEntries, {
    required HistoryCut cut,
    ({int seq, int displayTimeMs})? nextDirect,
    bool hasFoldedBeforeOldest = false,
    bool suppressTailFold = false,
  }) {
    final blocks = <DisplayBlock>[];
    if (hasFoldedBeforeOldest) {
      final firstEntry = ascendingEntries.firstOrNull;
      final beforeSeq = firstEntry?.event.seq ?? nextDirect?.seq;
      final suppressedByLiveTail =
          suppressTailFold && ascendingEntries.isEmpty && nextDirect == null;
      if (!suppressedByLiveTail) {
        blocks.add(
          leadingFoldedWorkBlock(
            cut: cut,
            beforeSeq: beforeSeq,
            finishedAtMillis:
                firstEntry?.displayTimeMs ?? nextDirect?.displayTimeMs,
          ),
        );
      }
    }
    for (var i = 0; i < ascendingEntries.length; i++) {
      final entry = ascendingEntries[i];
      blocks.add(directBlock(entry.event));
      if (!entry.hasFoldedAfter) continue;
      final followingDirect = i + 1 < ascendingEntries.length
          ? (
              seq: ascendingEntries[i + 1].event.seq,
              displayTimeMs: ascendingEntries[i + 1].displayTimeMs,
            )
          : nextDirect;
      if (suppressTailFold &&
          i == ascendingEntries.length - 1 &&
          followingDirect == null) {
        continue;
      }
      blocks.add(
        closedFoldedWorkBlock(entry, cut: cut, nextDirect: followingDirect),
      );
    }
    return blocks;
  }

  static DisplayBlock directBlock(HistoryEventRecord event) {
    if (event.eventId.isEmpty) {
      throw const ConversationContinuityError(
        'History direct event has no stable event identity',
      );
    }
    final rowKey = (event.rowKey != null && event.rowKey!.isNotEmpty)
        ? event.rowKey!
        : 'boundary:${event.eventId}';
    final projected = _projectEvent(event, idOverride: rowKey);
    return DisplayBlock(
      id: rowKey,
      blockOrder: event.seq,
      body: SingleDisplayBlock(
        record: projected.record,
        visibility: projected.visibility,
      ),
    );
  }

  static DisplayBlock leadingFoldedWorkBlock({
    required HistoryCut cut,
    int? beforeSeq,
    int? finishedAtMillis,
  }) {
    final headSeq = beforeSeq == null ? 1 : (beforeSeq > 1 ? beforeSeq - 1 : 1);
    return DisplayBlock(
      id: 'work:0',
      blockOrder: 1,
      body: WorkDisplayBlock(
        timing: WorkTiming(
          startedAtMillis: null,
          finishedAtMillis: finishedAtMillis,
        ),
        members: DisplayBlockRef(
          blockId: 'work:0',
          cut: cut,
          anchorSeq: 1,
          headSeq: headSeq,
          afterSeq: null,
          beforeSeq: beforeSeq,
        ),
        executionPresent: false,
        memberCount: 1,
        unfinishedCount: 0,
        groupClosed: true,
      ),
    );
  }

  static DisplayBlock closedFoldedWorkBlock(
    HistoryTimelineEntry? entry, {
    required HistoryCut cut,
    ({int seq, int displayTimeMs})? nextDirect,
  }) {
    if (entry == null) {
      return leadingFoldedWorkBlock(
        cut: cut,
        beforeSeq: nextDirect?.seq,
        finishedAtMillis: nextDirect?.displayTimeMs,
      );
    }
    final startSeq = entry.event.seq;
    final workId = 'work:$startSeq';
    final finishedAtMillis =
        nextDirect?.displayTimeMs ?? entry.tailFoldedEndedAt;
    return DisplayBlock(
      id: workId,
      blockOrder: startSeq + 1,
      body: WorkDisplayBlock(
        timing: WorkTiming(
          startedAtMillis: entry.displayTimeMs,
          finishedAtMillis: finishedAtMillis,
        ),
        members: DisplayBlockRef(
          blockId: workId,
          cut: cut,
          anchorSeq: startSeq + 1,
          headSeq: nextDirect != null ? nextDirect.seq - 1 : startSeq + 1,
          afterSeq: startSeq,
          beforeSeq: nextDirect?.seq,
        ),
        executionPresent: false,
        memberCount: 1,
        unfinishedCount: 0,
        groupClosed: true,
      ),
    );
  }

  /// Builds an open, live-updating Work block for [LiveStatusBar] only while
  /// execution is active and the tail folded interval has not been sealed.
  static DisplayBlock liveOpenWorkBlockForTail(
    HistoryTimelineEntry? entry, {
    required HistoryCut cut,
    int unfinishedCount = 1,
    String? summary,
  }) {
    final startSeq = entry?.event.seq ?? 0;
    final workId = 'work:$startSeq';
    final anchorSeq = startSeq + 1;
    return DisplayBlock(
      id: workId,
      blockOrder: anchorSeq,
      body: WorkDisplayBlock(
        timing: WorkTiming(
          startedAtMillis: entry?.displayTimeMs,
          finishedAtMillis: null,
        ),
        members: DisplayBlockRef(
          blockId: workId,
          cut: cut,
          anchorSeq: anchorSeq,
          headSeq: anchorSeq,
          afterSeq: entry?.event.seq,
          beforeSeq: null,
        ),
        executionPresent: true,
        memberCount: 1,
        unfinishedCount: unfinishedCount > 0 ? unfinishedCount : 1,
        groupClosed: false,
        summary: summary,
      ),
    );
  }

  static DisplayBlock eventRecord(
    HistoryEventRecord record, {
    required HistoryCut cut,
  }) {
    if (record.eventId.isEmpty) {
      throw const ConversationContinuityError(
        'History event has no stable event identity',
      );
    }
    final rowKey = (record.rowKey != null && record.rowKey!.isNotEmpty)
        ? record.rowKey!
        : 'event:${record.eventId}';
    final projected = _projectEvent(record, idOverride: rowKey);
    return DisplayBlock(
      id: rowKey,
      blockOrder: record.seq,
      body: SingleDisplayBlock(
        record: projected.record,
        visibility: projected.visibility,
      ),
    );
  }

  static DisplayRecord recordFromEvent(
    HistoryEventRecord event, {
    String? idOverride,
  }) => _projectEvent(event, idOverride: idOverride).record;

  static ({DisplayRecord record, HistorySingleVisibility visibility})
  _projectEvent(HistoryEventRecord event, {String? idOverride}) {
    final displayId = idOverride ?? event.entityId ?? event.eventId;
    var predecoded = ChatItemPresentation.decodeEventRecord(
      event,
      id: displayId,
    );
    final envelope = _decodeEnvelopeObject(event.payloadJson);
    final invalidField = _invalidProjectionField(envelope);
    if (invalidField != null) {
      predecoded = ChatItemPresentation(
        id: displayId,
        compatibility: ChatItemCompatibility.malformed,
        type: 'malformed',
        data: const {},
        bodies: const [],
        raw: event.payloadJson,
        createdAt: predecoded.createdAt,
        diagnostic: 'Invalid $invalidField',
      );
      // Keep valid observation facts, including its captured cut. Typed reads
      // below ignore damaged fields without inventing original availability.
    }
    final meta = envelope?['meta'] is Map<String, dynamic>
        ? envelope!['meta'] as Map<String, dynamic>
        : null;
    final data = envelope?['data'] is Map<String, dynamic>
        ? envelope!['data'] as Map<String, dynamic>
        : null;
    final capturedAt = _metadataValue<int>(envelope?['capturedAt']);
    final isFrozen =
        capturedAt != null ||
        event.kind == 'legacy_observed' ||
        event.kind == 'boundary_observed';
    final isTerminal = _isTerminalEvent(event, meta: meta, data: data);
    final contentPresent = _metadataValue<bool>(meta?['contentPresent']);
    final startedMillis =
        _metadataValue<int>(meta?['startedAt']) ?? event.occurredAt;
    final finishedMillis = isFrozen
        ? null
        : _metadataValue<int>(meta?['finishedAt']);
    final entityId =
        _metadataValue<String>(meta?['entityId']) ??
        (event.entityId != null && event.entityId!.isNotEmpty
            ? event.entityId!
            : event.callId != null
            ? 'tool:${event.callId!.length}:${event.callId}'
            : event.eventId);
    final kind = _atomKind(meta?['entityKind'], event.kind, predecoded.type);
    final delivery = _deliveryKind(meta?['delivery']);
    final textChannel = _textChannel(meta?['textChannel'] ?? data?['channel']);
    final visibility =
        invalidField == null &&
            meta?['singleVisibility'] == 'finalEmptyAfterContent'
        ? HistorySingleVisibility.finalEmptyAfterContent
        : HistorySingleVisibility.content;
    final tool = _toolIdentity(meta?['tool'], event);
    final lifecycle = isTerminal
        ? TerminalChatAtom(
            started: null,
            ended: null,
            outcome: _terminalOutcome(meta?['state'], data?['state']),
          )
        : ActiveChatAtom(
            started: null,
            status: _activeStatus(event.kind, meta?['state'], data?['state']),
          );
    final legacyUnavailable = data?['legacyUnavailable'] == true;
    final availableObservation = legacyUnavailable
        ? false
        : (contentPresent ??
              (predecoded.compatibility == ChatItemCompatibility.current &&
                  (event.kind == 'boundary_observed' ||
                      predecoded.bodies.isNotEmpty ||
                      predecoded.type == 'tool')));
    final contentSource = isFrozen
        ? FrozenObservation(
            capturedAt: capturedAt ?? event.occurredAt,
            available: availableObservation,
          )
        : CompletedOriginal(completionId: event.eventId);

    final atom = ChatAtom(
      id: entityId,
      source: event.source ?? ReceiptChatSource(receiptId: event.eventId),
      sourceOrder:
          _metadataValue<int>(meta?['sourceOrder']) ??
          _metadataValue<int>(envelope?['sourceOrder']),
      kind: kind,
      delivery: delivery,
      lifecycle: lifecycle,
      turnId: event.turnId ?? _metadataValue<String>(envelope?['turnId']),
      attemptId: event.attemptId,
      tool: tool,
      textChannel: textChannel,
      modelRecovery: switch ((kind, meta?['modelRecovery'])) {
        (ChatAtomKind.text, null) => predecoded.modelRecovery,
        (ChatAtomKind.text, final recovery) =>
          StudioModelRecoveryNotice.fromJson(recovery),
        _ => null,
      },
      contentPresent: contentPresent,
      startedAt: _atomSeconds(startedMillis),
      finishedAt: _atomSeconds(finishedMillis),
      contents: const [],
    );

    final hasHistoryPayload =
        contentPresent != false ||
        predecoded.compatibility != ChatItemCompatibility.current;
    final record = DisplayRecord(
      atom: atom,
      contentSource: contentSource,
      historyEventId: hasHistoryPayload ? event.eventId : null,
      historyDetailEventId: event.eventId,
      runId: event.runId,
      isTerminalHistory: isTerminal,
      isFrozenHistory: isFrozen,
      callId: event.callId ?? tool?.callId,
      predecodedPresentation: predecoded,
    );
    return (record: record, visibility: visibility);
  }

  static T? _metadataValue<T>(Object? value) => value is T ? value : null;

  static String? _invalidProjectionField(Map<String, dynamic>? envelope) {
    final rawMeta = envelope?['meta'];
    final meta = rawMeta is Map<String, dynamic> ? rawMeta : null;
    for (final field in {
      'capturedAt': envelope?['capturedAt'],
      'sourceOrder': envelope?['sourceOrder'],
      'meta.startedAt': meta?['startedAt'],
      'meta.finishedAt': meta?['finishedAt'],
      'meta.sourceOrder': meta?['sourceOrder'],
    }.entries) {
      if (field.value != null && field.value is! int) return field.key;
    }
    for (final field in {
      'turnId': envelope?['turnId'],
      'meta.entityId': meta?['entityId'],
    }.entries) {
      if (field.value != null && field.value is! String) return field.key;
    }
    final contentPresent = meta?['contentPresent'];
    if (contentPresent != null && contentPresent is! bool) {
      return 'meta.contentPresent';
    }
    return null;
  }

  static Map<String, dynamic>? _decodeEnvelopeObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static bool _isTerminalEvent(
    HistoryEventRecord event, {
    Map<String, dynamic>? meta,
    Map<String, dynamic>? data,
  }) {
    final stateKind = meta?['state'] is Map<String, dynamic>
        ? (meta!['state'] as Map<String, dynamic>)['kind']
        : null;
    if (stateKind == 'knownTerminal') return true;
    if (stateKind == 'knownActive') return false;
    final dataStateKind = data?['state'] is Map<String, dynamic>
        ? (data!['state'] as Map<String, dynamic>)['kind']
        : null;
    if (const {
      'running',
      'waiting',
      'waitingApproval',
      'cancelling',
    }.contains(dataStateKind)) {
      return false;
    }
    if (const {
      'succeeded',
      'failed',
      'denied',
      'cancelled',
      'interrupted',
      'backgroundStarted',
    }.contains(dataStateKind)) {
      return true;
    }
    return event.kind != 'tool_called' &&
        event.kind != 'tool_waiting_approval' &&
        event.kind != 'tool_cancel_requested';
  }

  static ChatAtomKind _atomKind(
    Object? rawEntityKind,
    String eventKind,
    String itemType,
  ) {
    if (rawEntityKind is String) {
      for (final value in ChatAtomKind.values) {
        if (value.name == rawEntityKind) return value;
      }
    }
    return switch (itemType) {
      'text' =>
        eventKind.startsWith('input') ? ChatAtomKind.input : ChatAtomKind.text,
      'thinking' => ChatAtomKind.reasoning,
      'tool' => ChatAtomKind.toolCall,
      'plan' => ChatAtomKind.plan,
      'turn' => ChatAtomKind.turnReceipt,
      'skill' => ChatAtomKind.skill,
      'file' => ChatAtomKind.fileChange,
      'agent' => ChatAtomKind.agent,
      'inference' => ChatAtomKind.inference,
      'contextCompaction' => ChatAtomKind.compaction,
      _ =>
        eventKind.startsWith('tool_')
            ? ChatAtomKind.toolCall
            : ChatAtomKind.raw,
    };
  }

  static ChatDeliveryKind _deliveryKind(Object? rawDelivery) {
    if (rawDelivery is String) {
      for (final value in ChatDeliveryKind.values) {
        if (value.name == rawDelivery) return value;
      }
    }
    return ChatDeliveryKind.foreground;
  }

  static ThreadTextChannel? _textChannel(Object? rawChannel) {
    if (rawChannel == 'final') return ThreadTextChannel.finalAnswer;
    if (rawChannel is String) {
      for (final value in ThreadTextChannel.values) {
        if (value.name == rawChannel) return value;
      }
    }
    return null;
  }

  static ChatToolIdentity? _toolIdentity(
    Object? rawTool,
    HistoryEventRecord event,
  ) {
    if (rawTool is Map<String, dynamic>) {
      final callId = rawTool['callId'];
      final name = rawTool['name'];
      if (callId is String && name is String) {
        return ChatToolIdentity(callId: callId, name: name);
      }
    }
    if (event.callId != null) {
      return ChatToolIdentity(
        callId: event.callId!,
        name: event.toolName ?? 'Tool',
      );
    }
    return null;
  }

  static ChatActiveStatus _activeStatus(
    String eventKind,
    Object? metaState,
    Object? dataState,
  ) {
    final metaStatus = metaState is Map<String, dynamic>
        ? metaState['status']
        : null;
    if (metaStatus == 'waiting') return ChatActiveStatus.waiting;
    if (metaStatus == 'running') return ChatActiveStatus.running;
    final dataKind = dataState is Map<String, dynamic>
        ? dataState['kind']
        : null;
    if (dataKind == 'waiting' ||
        dataKind == 'waitingApproval' ||
        eventKind == 'tool_waiting_approval') {
      return ChatActiveStatus.waiting;
    }
    return ChatActiveStatus.running;
  }

  static ChatTerminalOutcome _terminalOutcome(
    Object? metaState,
    Object? dataState,
  ) {
    final metaOutcome = metaState is Map<String, dynamic>
        ? metaState['outcome']
        : null;
    if (metaOutcome is String) {
      for (final value in ChatTerminalOutcome.values) {
        if (value.name == metaOutcome) return value;
      }
    }
    final dataKind = dataState is Map<String, dynamic>
        ? dataState['kind']
        : null;
    return switch (dataKind) {
      'failed' || 'denied' => ChatTerminalOutcome.failed,
      'cancelled' || 'interrupted' => ChatTerminalOutcome.cancelled,
      'backgroundStarted' => ChatTerminalOutcome.transferred,
      _ => ChatTerminalOutcome.completed,
    };
  }

  // ChatAtom retains the native producer's Unix seconds.
  static int? _atomSeconds(int? millis) =>
      millis == null ? null : millis ~/ Duration.millisecondsPerSecond;
}
