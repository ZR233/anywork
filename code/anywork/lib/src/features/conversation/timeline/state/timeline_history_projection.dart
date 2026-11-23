import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart' show ThreadTextChannel;

import 'chat_item_presentation.dart';
import 'timeline_display_models.dart';

/// Projects index-derived Divider events and WorkRanges onto Timeline display
/// blocks, and converts atomic HistoryEventRecord values into DisplayRecords
/// without dropping single unknown/malformed entries.
abstract final class TimelineHistoryProjection {
  static List<DisplayBlock> blocks(
    Iterable<HistoryTimelineItem> items, {
    required HistoryCut cut,
  }) => [for (final item in items) block(item, cut: cut)];

  /// Builds an open, live-updating Work block for [LiveStatusBar] only while
  /// execution is active and the tail range has not been sealed into Timeline.
  static DisplayBlock liveOpenWorkBlock(
    HistoryWorkRange range, {
    required HistoryCut cut,
    int unfinishedCount = 1,
    String? summary,
  }) {
    if (range.rangeId.isEmpty) {
      throw const ConversationContinuityError(
        'History WorkRange has no stable range identity',
      );
    }
    return DisplayBlock(
      id: range.rangeId,
      blockOrder: range.firstSeq,
      body: WorkDisplayBlock(
        timing: WorkTiming(
          startedAtMillis: range.startedAt,
          finishedAtMillis: null,
        ),
        members: DisplayBlockRef(
          blockId: range.rangeId,
          cut: cut,
          anchorSeq: range.firstSeq,
          headSeq: range.lastSeq,
          afterSeq: range.afterSeq,
          beforeSeq: range.beforeSeq,
          runId: range.runId,
        ),
        executionPresent: true,
        memberCount: range.eventCount,
        unfinishedCount: unfinishedCount > 0 ? unfinishedCount : 1,
        groupClosed: false,
        summary: summary,
      ),
    );
  }

  static DisplayBlock block(
    HistoryTimelineItem item, {
    required HistoryCut cut,
  }) {
    switch (item) {
      case WorkRangeTimelineItem(:final range):
        if (range.rangeId.isEmpty) {
          throw const ConversationContinuityError(
            'History WorkRange has no stable range identity',
          );
        }
        return DisplayBlock(
          id: range.rangeId,
          blockOrder: range.firstSeq,
          body: WorkDisplayBlock(
            timing: WorkTiming(
              startedAtMillis: range.startedAt,
              finishedAtMillis: range.endedAt,
            ),
            members: DisplayBlockRef(
              blockId: range.rangeId,
              cut: cut,
              anchorSeq: range.firstSeq,
              headSeq: range.lastSeq,
              afterSeq: range.afterSeq,
              beforeSeq: range.beforeSeq,
              runId: range.runId,
            ),
            executionPresent: false,
            memberCount: range.eventCount,
            unfinishedCount: 0,
            groupClosed: true,
          ),
        );
      case DividerTimelineItem(:final event):
        if (event.eventId.isEmpty) {
          throw const ConversationContinuityError(
            'History Divider event has no stable event identity',
          );
        }
        final rowKey = (event.rowKey != null && event.rowKey!.isNotEmpty)
            ? event.rowKey!
            : 'divider:${event.eventId}';
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
    final predecoded = ChatItemPresentation.decodeEventRecord(
      event,
      id: displayId,
    );
    final envelope = _decodeEnvelopeObject(event.payloadJson);
    final meta = envelope?['meta'] is Map<String, dynamic>
        ? envelope!['meta'] as Map<String, dynamic>
        : null;
    final data = envelope?['data'] is Map<String, dynamic>
        ? envelope!['data'] as Map<String, dynamic>
        : null;
    final capturedAt = envelope?['capturedAt'] as int?;
    final isFrozen =
        capturedAt != null ||
        event.kind == 'legacy_observed' ||
        event.kind == 'boundary_observed';
    final isTerminal = _isTerminalEvent(event, meta: meta, data: data);
    final contentPresent = meta?['contentPresent'] as bool?;
    final startedMillis = (meta?['startedAt'] as int?) ?? event.occurredAt;
    final finishedMillis = isFrozen ? null : meta?['finishedAt'] as int?;
    final entityId =
        (meta?['entityId'] as String?) ??
        (event.entityId != null && event.entityId!.isNotEmpty
            ? event.entityId!
            : event.callId != null
            ? 'tool:${event.callId!.length}:${event.callId}'
            : event.eventId);
    final kind = _atomKind(meta?['entityKind'], event.kind, predecoded.type);
    final delivery = _deliveryKind(meta?['delivery']);
    final textChannel = _textChannel(meta?['textChannel'] ?? data?['channel']);
    final visibility = meta?['singleVisibility'] == 'finalEmptyAfterContent'
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
          (meta?['sourceOrder'] as int?) ?? (envelope?['sourceOrder'] as int?),
      kind: kind,
      delivery: delivery,
      lifecycle: lifecycle,
      turnId: event.turnId ?? (envelope?['turnId'] as String?),
      attemptId: event.attemptId,
      tool: tool,
      textChannel: textChannel,
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
