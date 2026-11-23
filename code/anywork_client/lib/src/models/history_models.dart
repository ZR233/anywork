import 'chat_models.dart';
import 'current_models.dart' show CurrentTurnPhase;
import 'runtime_models.dart';

const historyProtocolVersion = 2;

final class HistoryCut {
  const HistoryCut(this.token);
  final String token;
  @override
  bool operator ==(Object other) => other is HistoryCut && token == other.token;
  @override
  int get hashCode => token.hashCode;
}

final class HistoryDemand {
  const HistoryDemand({required this.maxRows, required this.maxBytes});
  final int maxRows;
  final int maxBytes;
}

enum HistoryTimelineRole { divider, work, hidden }

enum HistoryBusinessRowScope { turn, source, cost, accounting }

enum HistoryTurnState {
  unknown,
  queued,
  running,
  completed,
  cancelled,
  failed,
  budgetLimited,
}

enum HistoryContextDisposition { active, rolledBack }

enum HistorySourceLifecycleKind { unknown, active, ended }

enum HistoryBodyRoleKind {
  canonicalPayload,
  canonicalMetadata,
  body,
  reasoningSummary,
  toolArguments,
  toolOutput,
  attachment,
  waitPresentation,
  other,
}

sealed class HistoryEventsQuery {
  const HistoryEventsQuery();
}

final class AllHistoryEvents extends HistoryEventsQuery {
  const AllHistoryEvents();
}

final class EntityHistoryEvents extends HistoryEventsQuery {
  const EntityHistoryEvents(this.entityId);
  final String entityId;
}

final class TurnHistoryEvents extends HistoryEventsQuery {
  const TurnHistoryEvents(this.turnId);
  final String turnId;
}

final class SourceHistoryEvents extends HistoryEventsQuery {
  const SourceHistoryEvents(this.source);
  final ChatSourceId source;
}

final class CallHistoryEvents extends HistoryEventsQuery {
  const CallHistoryEvents(this.callId);
  final String callId;
}

final class MessageHistoryEvents extends HistoryEventsQuery {
  const MessageHistoryEvents(this.messageId);
  final String messageId;
}

final class AttemptHistoryEvents extends HistoryEventsQuery {
  const AttemptHistoryEvents({required this.runId, required this.attemptId});
  final String runId;
  final String attemptId;
}

final class OriginalsHistoryEvents extends HistoryEventsQuery {
  const OriginalsHistoryEvents({required this.queryClass, this.parentId});
  final String queryClass;
  final String? parentId;
}

final class TextOriginalHistoryEvents extends HistoryEventsQuery {
  const TextOriginalHistoryEvents();
}

final class HistoryTurnHead {
  const HistoryTurnHead({
    required this.turnId,
    this.inputId,
    this.runId,
    required this.state,
    this.phase,
    required this.contextDisposition,
    this.queuedAt,
    this.startedAt,
    this.finishedAt,
    required this.updatedAt,
    this.detailEventId,
  });
  final String turnId;
  final String? inputId;
  final String? runId;
  final HistoryTurnState state;
  final CurrentTurnPhase? phase;
  final HistoryContextDisposition contextDisposition;
  final int? queuedAt;
  final int? startedAt;
  final int? finishedAt;
  final int updatedAt;
  final String? detailEventId;
}

final class HistorySourceHead {
  const HistorySourceHead({
    required this.source,
    required this.lifecycle,
    this.startedAt,
    this.endedAt,
    this.observedAt,
    this.detailEventId,
  });
  final ChatSourceId source;
  final HistorySourceLifecycle lifecycle;
  final int? startedAt;
  final int? endedAt;
  final int? observedAt;
  final String? detailEventId;
}

final class HistorySourceLifecycle {
  const HistorySourceLifecycle({required this.kind, this.outcome});
  final HistorySourceLifecycleKind kind;
  final ChatTerminalOutcome? outcome;
}

final class HistoryCostHead {
  const HistoryCostHead({
    this.purpose,
    required this.currency,
    this.costDelta,
    required this.costTotal,
    this.cacheSavingsDelta,
    this.cacheSavingsTotal,
    required this.updatedAt,
    this.detailEventId,
  });
  final String? purpose;
  final String currency;
  final double? costDelta;
  final double costTotal;
  final double? cacheSavingsDelta;
  final double? cacheSavingsTotal;
  final int updatedAt;
  final String? detailEventId;
}

final class HistoryAccountingHead {
  const HistoryAccountingHead({
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedPromptTokens,
    required this.cacheWriteTokens,
    required this.reasoningTokens,
    required this.inferenceCount,
    required this.totalTokens,
    required this.cacheUsage,
    required this.hasIncompleteUsage,
    required this.hasUnpricedUsage,
    required this.updatedAt,
    this.detailEventId,
  });
  final int promptTokens;
  final int completionTokens;
  final int cachedPromptTokens;
  final int cacheWriteTokens;
  final int reasoningTokens;
  final int inferenceCount;
  final int totalTokens;
  final CacheUsageView cacheUsage;
  final bool hasIncompleteUsage;
  final bool hasUnpricedUsage;
  final int updatedAt;
  final String? detailEventId;
}

enum HistorySingleVisibility { content, finalEmptyAfterContent }

final class HistoryEventRecord {
  const HistoryEventRecord({
    required this.seq,
    required this.eventId,
    required this.kind,
    required this.timelineRole,
    this.occurredAt,
    required this.recordedAt,
    this.runId,
    this.turnId,
    this.attemptId,
    this.callId,
    this.entityId,
    this.messageId,
    this.toolName,
    this.source,
    this.original,
    this.rowScope,
    this.rowKey,
    required this.payloadSchema,
    required this.payloadJson,
  });
  final int seq;
  final String eventId;
  final String kind;
  final HistoryTimelineRole timelineRole;
  final int? occurredAt;
  final int recordedAt;
  final String? runId;
  final String? turnId;
  final String? attemptId;
  final String? callId;
  final String? entityId;
  final String? messageId;
  final String? toolName;
  final ChatSourceId? source;
  final HistoryOriginalInfo? original;
  final HistoryBusinessRowScope? rowScope;
  final String? rowKey;
  final String payloadSchema;
  final String payloadJson;
}

final class HistoryWorkRange {
  const HistoryWorkRange({
    required this.rangeId,
    this.afterSeq,
    this.beforeSeq,
    required this.firstSeq,
    required this.lastSeq,
    this.startedAt,
    this.endedAt,
    this.runId,
    required this.eventCount,
  });
  final String rangeId;
  final int? afterSeq;
  final int? beforeSeq;
  final int firstSeq;
  final int lastSeq;
  final int? startedAt;
  final int? endedAt;
  final String? runId;
  final int eventCount;
}

sealed class HistoryTimelineItem {
  const HistoryTimelineItem();
}

final class DividerTimelineItem extends HistoryTimelineItem {
  const DividerTimelineItem(this.event);
  final HistoryEventRecord event;
}

final class WorkRangeTimelineItem extends HistoryTimelineItem {
  const WorkRangeTimelineItem(this.range);
  final HistoryWorkRange range;
}

final class HistoryTimelinePage {
  HistoryTimelinePage({
    required this.cut,
    required List<HistoryTimelineItem> items,
    this.next,
  }) : items = List.unmodifiable(items);
  final HistoryCut cut;
  final List<HistoryTimelineItem> items;
  final String? next;
}

final class HistoryWorkRangePage {
  HistoryWorkRangePage({
    required this.cut,
    this.afterSeq,
    this.beforeSeq,
    required List<HistoryEventRecord> events,
    this.next,
  }) : events = List.unmodifiable(events);
  final HistoryCut cut;
  final int? afterSeq;
  final int? beforeSeq;
  final List<HistoryEventRecord> events;
  final String? next;
}

sealed class HistoryBusinessRowHead {
  const HistoryBusinessRowHead();
}

final class TurnHistoryBusinessRow extends HistoryBusinessRowHead {
  const TurnHistoryBusinessRow(this.head);
  final HistoryTurnHead head;
}

final class SourceHistoryBusinessRow extends HistoryBusinessRowHead {
  const SourceHistoryBusinessRow(this.head);
  final HistorySourceHead head;
}

final class CostHistoryBusinessRow extends HistoryBusinessRowHead {
  const CostHistoryBusinessRow(this.head);
  final HistoryCostHead head;
}

final class AccountingHistoryBusinessRow extends HistoryBusinessRowHead {
  const AccountingHistoryBusinessRow(this.head);
  final HistoryAccountingHead head;
}

final class HistoryBusinessRowEntry {
  const HistoryBusinessRowEntry({
    required this.rowKey,
    required this.anchorSeq,
    required this.headSeq,
    required this.head,
  });
  final String rowKey;
  final int anchorSeq;
  final int headSeq;
  final HistoryBusinessRowHead head;
}

final class HistoryBusinessPage {
  HistoryBusinessPage({
    required this.cut,
    required List<HistoryBusinessRowEntry> entries,
    this.next,
  }) : entries = List.unmodifiable(entries);
  final HistoryCut cut;
  final List<HistoryBusinessRowEntry> entries;
  final String? next;
}

final class HistoryOriginalInfo {
  const HistoryOriginalInfo({
    required this.queryClass,
    this.parentId,
    required this.originalKind,
    this.toolName,
  });
  final String queryClass;
  final String? parentId;
  final ChatAtomKind originalKind;
  final String? toolName;
}

final class HistoryEventBodyRef {
  const HistoryEventBodyRef({
    required this.databaseId,
    required this.ownerEventId,
    required this.bodyKey,
    required this.bodyId,
    required this.byteStart,
    required this.byteLength,
  });
  final String databaseId;
  final String ownerEventId;
  final String bodyKey;
  final String bodyId;
  final int byteStart;
  final int byteLength;

  @override
  bool operator ==(Object other) =>
      other is HistoryEventBodyRef &&
      databaseId == other.databaseId &&
      ownerEventId == other.ownerEventId &&
      bodyKey == other.bodyKey &&
      bodyId == other.bodyId &&
      byteStart == other.byteStart &&
      byteLength == other.byteLength;

  @override
  int get hashCode => Object.hash(
    databaseId,
    ownerEventId,
    bodyKey,
    bodyId,
    byteStart,
    byteLength,
  );
}

final class HistoryEventsPage {
  HistoryEventsPage({
    required this.cut,
    required List<HistoryEventRecord> entries,
    this.next,
  }) : entries = List.unmodifiable(entries);
  final HistoryCut cut;
  final List<HistoryEventRecord> entries;
  final String? next;
}

final class HistoryBodyWindow {
  HistoryBodyWindow({
    required this.offset,
    required List<int> bytes,
    required this.totalLength,
    this.mediaType,
  }) : bytes = List.unmodifiable(bytes);
  final int offset;
  final List<int> bytes;
  final int totalLength;
  final String? mediaType;
}

final class HistoryBodyEntry {
  const HistoryBodyEntry({
    required this.ordinal,
    required this.bodyKey,
    required this.role,
    required this.reference,
    this.mediaType,
  });
  final int ordinal;
  final String bodyKey;
  final HistoryBodyRole role;
  final HistoryEventBodyRef reference;
  final String? mediaType;
}

final class HistoryBodyRole {
  const HistoryBodyRole(this.kind, {this.name});
  final HistoryBodyRoleKind kind;
  final String? name;
}

final class HistoryBodyPage {
  HistoryBodyPage({
    required this.ownerEventId,
    required List<HistoryBodyEntry> entries,
    this.next,
  }) : entries = List.unmodifiable(entries);
  final String ownerEventId;
  final List<HistoryBodyEntry> entries;
  final String? next;
}

final class HistoryAccounting {
  const HistoryAccounting(this.head);
  final HistoryAccountingHead head;
}
