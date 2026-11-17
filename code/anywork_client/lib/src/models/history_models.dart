import 'chat_models.dart';
import 'current_models.dart' show CurrentTurnPhase;
import 'runtime_models.dart';
import 'thread_models.dart' show ThreadTextChannel;
import 'thread_wait_models.dart';

const historyProtocolVersion = 1;

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

enum HistoryEntityStateKind { unknown, knownActive, knownTerminal }

enum HistoryObservationKind { original, boundary, unavailableLegacy }

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

enum HistoryWaitState {
  waiting,
  ready,
  timedOut,
  elapsed,
  cancelled,
  failed,
  interrupted,
}

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

final class HistoryWorkHead {
  const HistoryWorkHead({
    required this.groupId,
    this.runId,
    this.startedAt,
    this.boundaryAt,
    required this.closed,
    required this.memberCount,
    required this.unfinishedCount,
    required this.executionPresent,
    this.summary,
  });
  final String groupId;
  final String? runId;
  final int? startedAt;
  final int? boundaryAt;
  final bool closed;
  final int memberCount;
  final int unfinishedCount;
  final bool executionPresent;
  final String? summary;
}

final class HistoryEntityHead {
  const HistoryEntityHead({
    required this.entityId,
    this.runId,
    this.attemptId,
    required this.source,
    required this.kind,
    required this.delivery,
    required this.state,
    this.startedAt,
    this.finishedAt,
    this.textChannel,
    this.tool,
    this.wait,
    this.contentPresent,
    this.singleVisibility,
    required this.observation,
    this.presentationContract,
    this.detailEventId,
    this.inputManifestEventId,
    this.bodyManifestEventId,
  });
  final String entityId;
  final String? runId;
  final String? attemptId;
  final ChatSourceId source;
  final ChatAtomKind kind;
  final ChatDeliveryKind delivery;
  final HistoryEntityState state;
  final int? startedAt;
  final int? finishedAt;
  final ThreadTextChannel? textChannel;
  final ChatToolIdentity? tool;
  final HistoryWaitHead? wait;
  final bool? contentPresent;
  final HistorySingleVisibility? singleVisibility;
  final HistoryObservation observation;
  final String? presentationContract;
  final String? detailEventId;
  final String? inputManifestEventId;
  final String? bodyManifestEventId;
}

final class HistoryEntityState {
  const HistoryEntityState({
    required this.kind,
    this.activeStatus,
    this.outcome,
  }) : assert(
         (kind == HistoryEntityStateKind.knownActive) == (activeStatus != null),
       ),
       assert(
         (kind == HistoryEntityStateKind.knownTerminal) == (outcome != null),
       );
  final HistoryEntityStateKind kind;
  final ChatActiveStatus? activeStatus;
  final ChatTerminalOutcome? outcome;
}

final class HistoryObservation {
  const HistoryObservation({required this.kind, this.capturedAt});
  final HistoryObservationKind kind;
  final int? capturedAt;
}

enum HistorySingleVisibility { content, finalEmptyAfterContent }

sealed class HistoryWaitHead {
  const HistoryWaitHead();
}

final class InlineHistoryWait extends HistoryWaitHead {
  const InlineHistoryWait(this.presentation);
  final ThreadWaitPresentationView presentation;
}

final class DeferredHistoryWait extends HistoryWaitHead {
  const DeferredHistoryWait({
    required this.intent,
    required this.state,
    this.messagesReady,
    required this.presentation,
  });
  final HistoryWaitIntent intent;
  final HistoryWaitState state;
  final bool? messagesReady;
  final HistoryEventBodyRef presentation;
}

sealed class HistoryWaitIntent {
  const HistoryWaitIntent();
}

final class EventsHistoryWaitIntent extends HistoryWaitIntent {
  const EventsHistoryWaitIntent({
    required this.targetCount,
    required this.timeoutMs,
  });
  final int targetCount;
  final int timeoutMs;
}

final class TimerHistoryWaitIntent extends HistoryWaitIntent {
  const TimerHistoryWaitIntent(this.durationMs);
  final int durationMs;
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

sealed class HistoryRowHead {
  const HistoryRowHead();
}

final class WorkHistoryRow extends HistoryRowHead {
  const WorkHistoryRow(this.head);
  final HistoryWorkHead head;
}

final class SingleHistoryRow extends HistoryRowHead {
  const SingleHistoryRow(this.head);
  final HistoryEntityHead head;
}

final class MemberHistoryRow extends HistoryRowHead {
  const MemberHistoryRow(this.head);
  final HistoryEntityHead head;
}

final class TurnHistoryRow extends HistoryRowHead {
  const TurnHistoryRow(this.head);
  final HistoryTurnHead head;
}

final class SourceHistoryRow extends HistoryRowHead {
  const SourceHistoryRow(this.head);
  final HistorySourceHead head;
}

final class CostHistoryRow extends HistoryRowHead {
  const CostHistoryRow(this.head);
  final HistoryCostHead head;
}

final class AccountingHistoryRow extends HistoryRowHead {
  const AccountingHistoryRow(this.head);
  final HistoryAccountingHead head;
}

final class HistoryTimelineEntry {
  const HistoryTimelineEntry({
    required this.rowKey,
    required this.anchorSeq,
    required this.headSeq,
    required this.head,
  });
  final String rowKey;
  final int anchorSeq;
  final int headSeq;
  final HistoryRowHead head;
}

final class HistoryTimelinePage {
  HistoryTimelinePage({
    required this.cut,
    required List<HistoryTimelineEntry> entries,
    this.next,
  }) : entries = List.unmodifiable(entries);
  final HistoryCut cut;
  final List<HistoryTimelineEntry> entries;
  final String? next;
}

final class HistoryGroupPage {
  HistoryGroupPage({
    required this.cut,
    required this.groupId,
    required List<HistoryTimelineEntry> members,
    this.next,
  }) : members = List.unmodifiable(members);
  final HistoryCut cut;
  final String groupId;
  final List<HistoryTimelineEntry> members;
  final String? next;
}

final class HistoryEventHeader {
  const HistoryEventHeader({
    required this.seq,
    required this.eventId,
    required this.kind,
    this.runId,
    this.attemptId,
    this.entityId,
    this.turnId,
    this.source,
    this.callId,
    this.messageId,
    this.groupId,
    this.rowKey,
    this.original,
    this.occurredAt,
    required this.recordedAt,
  });
  final int seq;
  final String eventId;
  final String kind;
  final String? runId;
  final String? attemptId;
  final String? entityId;
  final String? turnId;
  final ChatSourceId? source;
  final String? callId;
  final String? messageId;
  final String? groupId;
  final String? rowKey;
  final HistoryOriginalInfo? original;
  final int? occurredAt;
  final int recordedAt;
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

final class HistoryEventDetail {
  const HistoryEventDetail({
    required this.header,
    this.head,
    this.payloadRef,
    this.ownedManifestEventId,
  });
  final HistoryEventHeader header;
  final HistoryRowHead? head;
  final HistoryEventBodyRef? payloadRef;
  final String? ownedManifestEventId;
}

final class HistoryEventsPage {
  HistoryEventsPage({
    required this.cut,
    required List<HistoryEventDetail> entries,
    this.next,
  }) : entries = List.unmodifiable(entries);
  final HistoryCut cut;
  final List<HistoryEventDetail> entries;
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
