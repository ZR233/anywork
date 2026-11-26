import 'runtime_models.dart';
import 'agent_models.dart';
import 'current_state_field.dart';
import 'timeline_models.dart';
import 'turn_models.dart';
import 'thread_activity_models.dart';
import 'thread_directory_models.dart';
import 'interaction_models.dart';
import 'studio_enums.dart';
import 'usage_diagnostics.dart';
import 'collection_equality.dart';

/// Mechanical immutable values owned by the Rust ConversationFeed domain.
typedef TimelineItemId = String;

final class BodyRef {
  const BodyRef({
    required this.databaseId,
    required this.bodyId,
    required this.ownerEventId,
    required this.bodyKey,
    required this.role,
    required this.byteLength,
    this.mediaType,
    this.inlineText,
  });
  final String databaseId;
  final String bodyId;
  final String ownerEventId;
  final String bodyKey;
  final String role;
  final int byteLength;
  final String? mediaType;
  final String? inlineText;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BodyRef &&
          databaseId == other.databaseId &&
          bodyId == other.bodyId &&
          ownerEventId == other.ownerEventId &&
          bodyKey == other.bodyKey &&
          role == other.role &&
          byteLength == other.byteLength &&
          mediaType == other.mediaType &&
          inlineText == other.inlineText;
  @override
  int get hashCode => Object.hashAll([
    BodyRef,
    databaseId,
    bodyId,
    ownerEventId,
    bodyKey,
    role,
    byteLength,
    mediaType,
    inlineText,
  ]);
}

final class BodyWindow {
  const BodyWindow({
    required this.offset,
    this.text,
    this.bytesBase64,
    required this.totalBytes,
    required this.eof,
  });
  final int offset;
  final String? text;
  final String? bytesBase64;
  final int totalBytes;
  final bool eof;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BodyWindow &&
          offset == other.offset &&
          text == other.text &&
          bytesBase64 == other.bytesBase64 &&
          totalBytes == other.totalBytes &&
          eof == other.eof;
  @override
  int get hashCode =>
      Object.hashAll([BodyWindow, offset, text, bytesBase64, totalBytes, eof]);
}

final class LiveWorkItem {
  const LiveWorkItem({
    required this.id,
    this.callId,
    required this.kind,
    required this.toolName,
    required this.status,
    required this.summary,
    this.startedAtMs,
    this.finishedAtMs,
  });
  final String id;
  final String? callId;
  final String kind;
  final String toolName;
  final String status;
  final String summary;
  final int? startedAtMs;
  final int? finishedAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveWorkItem &&
          id == other.id &&
          callId == other.callId &&
          kind == other.kind &&
          toolName == other.toolName &&
          status == other.status &&
          summary == other.summary &&
          startedAtMs == other.startedAtMs &&
          finishedAtMs == other.finishedAtMs;
  @override
  int get hashCode => Object.hashAll([
    LiveWorkItem,
    id,
    callId,
    kind,
    toolName,
    status,
    summary,
    startedAtMs,
    finishedAtMs,
  ]);
}

final class LiveAttention {
  const LiveAttention({
    required this.id,
    required this.kind,
    required this.summary,
    this.callId,
  });
  final String id;
  final String kind;
  final String summary;
  final String? callId;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveAttention &&
          id == other.id &&
          kind == other.kind &&
          summary == other.summary &&
          callId == other.callId;
  @override
  int get hashCode =>
      Object.hashAll([LiveAttention, id, kind, summary, callId]);
}

final class LiveStatusSnapshot {
  LiveStatusSnapshot({
    required this.revision,
    required this.phase,
    required Iterable<LiveAttention> attentions,
    required this.suppressedByInteraction,
  }) : attentions = List.unmodifiable(attentions);
  final int revision;
  final LiveStatusPhase phase;
  final List<LiveAttention> attentions;
  final bool suppressedByInteraction;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusSnapshot &&
          revision == other.revision &&
          phase == other.phase &&
          listEquals(attentions, other.attentions) &&
          suppressedByInteraction == other.suppressedByInteraction;
  @override
  int get hashCode => Object.hashAll([
    LiveStatusSnapshot,
    revision,
    phase,
    Object.hashAll(attentions),
    suppressedByInteraction,
  ]);
}

final class SessionMetaSnapshot {
  SessionMetaSnapshot({
    required this.threadId,
    required this.status,
    this.title,
    this.parentThreadId,
    required this.rootThreadId,
    required this.ownerEpoch,
    required this.revision,
    this.activeTurn,
    this.lastTurn,
    this.activity,
    required this.usage,
    this.contextMetrics,
    this.modelRoute,
    this.runtime,
    this.storageState,
    required Iterable<PendingInteraction> interactions,
    required this.pendingInteractionCount,
    this.plan,
    this.mode,
    required this.executionPresent,
  }) : interactions = List.unmodifiable(interactions);
  final String threadId;
  final ThreadStatusView status;
  final String? title;
  final String? parentThreadId;
  final String rootThreadId;
  final String ownerEpoch;
  final int revision;
  final StudioTurnView? activeTurn;
  final StudioTurnView? lastTurn;
  final ThreadActivityView? activity;
  final SessionUsageSummary usage;
  final ConversationRuntimeUsage? contextMetrics;
  final ThreadModelRouteView? modelRoute;
  final ConversationRuntimeSnapshot? runtime;
  final ThreadStorageStateView? storageState;
  final List<PendingInteraction> interactions;
  final int pendingInteractionCount;
  final PlanRuntimeView? plan;
  final ThreadModeId? mode;
  final bool executionPresent;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionMetaSnapshot &&
          threadId == other.threadId &&
          status == other.status &&
          title == other.title &&
          parentThreadId == other.parentThreadId &&
          rootThreadId == other.rootThreadId &&
          ownerEpoch == other.ownerEpoch &&
          revision == other.revision &&
          activeTurn == other.activeTurn &&
          lastTurn == other.lastTurn &&
          activity == other.activity &&
          usage == other.usage &&
          contextMetrics == other.contextMetrics &&
          modelRoute == other.modelRoute &&
          runtime == other.runtime &&
          storageState == other.storageState &&
          listEquals(interactions, other.interactions) &&
          pendingInteractionCount == other.pendingInteractionCount &&
          plan == other.plan &&
          mode == other.mode &&
          executionPresent == other.executionPresent;
  @override
  int get hashCode => Object.hashAll([
    SessionMetaSnapshot,
    threadId,
    status,
    title,
    parentThreadId,
    rootThreadId,
    ownerEpoch,
    revision,
    activeTurn,
    lastTurn,
    activity,
    usage,
    contextMetrics,
    modelRoute,
    runtime,
    storageState,
    Object.hashAll(interactions),
    pendingInteractionCount,
    plan,
    mode,
    executionPresent,
  ]);
}

enum WorkGroupStatus { active, completed, failed, cancelled }

sealed class TimelineItem {
  const TimelineItem({required this.id});
  final String id;
  int get seq;
}

final class TimelineUserMessage extends TimelineItem {
  TimelineUserMessage({
    required super.id,
    required this.seq,
    this.turnId,
    this.inputId,
    required this.channel,
    required this.text,
    required Iterable<Object?> attachments,
    this.occurredAtMs,
  }) : attachments = _freezeJsonList(attachments);
  final int seq;
  final String? turnId;
  final String? inputId;
  final String channel;
  final String text;
  final List<Object?> attachments;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineUserMessage &&
          id == other.id &&
          seq == other.seq &&
          turnId == other.turnId &&
          inputId == other.inputId &&
          channel == other.channel &&
          text == other.text &&
          _jsonEquals(attachments, other.attachments) &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    TimelineUserMessage,
    id,
    seq,
    turnId,
    inputId,
    channel,
    text,
    _jsonHash(attachments),
    occurredAtMs,
  ]);
}

final class TimelineAssistantText extends TimelineItem {
  const TimelineAssistantText({
    required super.id,
    required this.seq,
    this.turnId,
    this.attemptId,
    required this.channel,
    required this.text,
    this.bodyRef,
    required this.isFinalTurnDelivery,
    required this.outcome,
    this.modelRecovery,
    this.occurredAtMs,
  });
  final int seq;
  final String? turnId;
  final String? attemptId;
  final String channel;
  final String text;
  final BodyRef? bodyRef;
  final bool isFinalTurnDelivery;
  final String outcome;
  final StudioModelRecoveryNotice? modelRecovery;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineAssistantText &&
          id == other.id &&
          seq == other.seq &&
          turnId == other.turnId &&
          attemptId == other.attemptId &&
          channel == other.channel &&
          text == other.text &&
          bodyRef == other.bodyRef &&
          isFinalTurnDelivery == other.isFinalTurnDelivery &&
          outcome == other.outcome &&
          modelRecovery == other.modelRecovery &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    TimelineAssistantText,
    id,
    seq,
    turnId,
    attemptId,
    channel,
    text,
    bodyRef,
    isFinalTurnDelivery,
    outcome,
    modelRecovery,
    occurredAtMs,
  ]);
}

final class TimelineWorkGroup extends TimelineItem {
  const TimelineWorkGroup({
    required super.id,
    required this.firstSeq,
    required this.lastSeq,
    this.afterBoundarySeq,
    this.beforeBoundarySeq,
    required this.memberCount,
    required this.summary,
    required this.status,
    this.startedAtMs,
    this.finishedAtMs,
  });
  final int firstSeq;
  final int lastSeq;
  final int? afterBoundarySeq;
  final int? beforeBoundarySeq;
  final int memberCount;
  final String summary;
  final WorkGroupStatus status;
  final int? startedAtMs;
  final int? finishedAtMs;
  @override
  int get seq => lastSeq;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineWorkGroup &&
          id == other.id &&
          firstSeq == other.firstSeq &&
          lastSeq == other.lastSeq &&
          afterBoundarySeq == other.afterBoundarySeq &&
          beforeBoundarySeq == other.beforeBoundarySeq &&
          memberCount == other.memberCount &&
          summary == other.summary &&
          status == other.status &&
          startedAtMs == other.startedAtMs &&
          finishedAtMs == other.finishedAtMs;
  @override
  int get hashCode => Object.hashAll([
    TimelineWorkGroup,
    id,
    firstSeq,
    lastSeq,
    afterBoundarySeq,
    beforeBoundarySeq,
    memberCount,
    summary,
    status,
    startedAtMs,
    finishedAtMs,
  ]);
}

final class TimelineCompaction extends TimelineItem {
  const TimelineCompaction({
    required super.id,
    required this.seq,
    this.turnId,
    required this.summary,
    required this.outcome,
    this.tokensBefore,
    this.tokensAfter,
    this.occurredAtMs,
  });
  final int seq;
  final String? turnId;
  final String summary;
  final String outcome;
  final int? tokensBefore;
  final int? tokensAfter;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineCompaction &&
          id == other.id &&
          seq == other.seq &&
          turnId == other.turnId &&
          summary == other.summary &&
          outcome == other.outcome &&
          tokensBefore == other.tokensBefore &&
          tokensAfter == other.tokensAfter &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    TimelineCompaction,
    id,
    seq,
    turnId,
    summary,
    outcome,
    tokensBefore,
    tokensAfter,
    occurredAtMs,
  ]);
}

final class TimelinePlanResolution extends TimelineItem {
  const TimelinePlanResolution({
    required super.id,
    required this.seq,
    this.turnId,
    required this.decision,
    this.document,
    this.documentRef,
    this.feedback,
    this.occurredAtMs,
  });
  final int seq;
  final String? turnId;
  final String decision;
  final String? document;
  final BodyRef? documentRef;
  final String? feedback;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelinePlanResolution &&
          id == other.id &&
          seq == other.seq &&
          turnId == other.turnId &&
          decision == other.decision &&
          document == other.document &&
          documentRef == other.documentRef &&
          feedback == other.feedback &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    TimelinePlanResolution,
    id,
    seq,
    turnId,
    decision,
    document,
    documentRef,
    feedback,
    occurredAtMs,
  ]);
}

final class TimelineConnectionNotice extends TimelineItem {
  const TimelineConnectionNotice({
    required super.id,
    required this.seq,
    this.turnId,
    required this.scope,
    required this.state,
    required this.transport,
    this.fallbackTransport,
    required this.attempt,
    required this.maxAttempts,
    required this.recoverable,
    this.reason,
    this.durationMs,
    this.occurredAtMs,
  });
  final int seq;
  final String? turnId;
  final String scope;
  final String state;
  final String transport;
  final String? fallbackTransport;
  final int attempt;
  final int maxAttempts;
  final bool recoverable;
  final String? reason;
  final int? durationMs;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineConnectionNotice &&
          id == other.id &&
          seq == other.seq &&
          turnId == other.turnId &&
          scope == other.scope &&
          state == other.state &&
          transport == other.transport &&
          fallbackTransport == other.fallbackTransport &&
          attempt == other.attempt &&
          maxAttempts == other.maxAttempts &&
          recoverable == other.recoverable &&
          reason == other.reason &&
          durationMs == other.durationMs &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    TimelineConnectionNotice,
    id,
    seq,
    turnId,
    scope,
    state,
    transport,
    fallbackTransport,
    attempt,
    maxAttempts,
    recoverable,
    reason,
    durationMs,
    occurredAtMs,
  ]);
}

final class TimelineTurnOutcome extends TimelineItem {
  const TimelineTurnOutcome({
    required super.id,
    required this.seq,
    this.turnId,
    this.inputId,
    required this.outcome,
    this.message,
    this.turnFailure,
    this.occurredAtMs,
  });
  final int seq;
  final String? turnId;
  final String? inputId;
  final String outcome;
  final String? message;
  final StudioTurnFailureView? turnFailure;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineTurnOutcome &&
          id == other.id &&
          seq == other.seq &&
          turnId == other.turnId &&
          inputId == other.inputId &&
          outcome == other.outcome &&
          message == other.message &&
          turnFailure == other.turnFailure &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    TimelineTurnOutcome,
    id,
    seq,
    turnId,
    inputId,
    outcome,
    message,
    turnFailure,
    occurredAtMs,
  ]);
}

final class TimelineStandaloneTool extends TimelineItem {
  TimelineStandaloneTool({
    required super.id,
    required this.seq,
    this.turnId,
    required this.callId,
    required this.toolName,
    this.presentationContract,
    required this.state,
    required this.summary,
    required this.payloadJson,
    required Iterable<BodyRef> bodies,
    this.occurredAtMs,
  }) : bodies = List.unmodifiable(bodies);
  final int seq;
  final String? turnId;
  final String callId;
  final String toolName;
  final String? presentationContract;
  final String state;
  final String summary;
  final String payloadJson;
  final List<BodyRef> bodies;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineStandaloneTool &&
          id == other.id &&
          seq == other.seq &&
          turnId == other.turnId &&
          callId == other.callId &&
          toolName == other.toolName &&
          presentationContract == other.presentationContract &&
          state == other.state &&
          summary == other.summary &&
          payloadJson == other.payloadJson &&
          listEquals(bodies, other.bodies) &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    TimelineStandaloneTool,
    id,
    seq,
    turnId,
    callId,
    toolName,
    presentationContract,
    state,
    summary,
    payloadJson,
    Object.hashAll(bodies),
    occurredAtMs,
  ]);
}

final class TimelineFallback extends TimelineItem {
  const TimelineFallback({
    required super.id,
    required this.seq,
    required this.eventId,
    required this.eventKind,
    required this.reason,
    this.rawPreview,
    this.occurredAtMs,
  });
  final int seq;
  final String eventId;
  final String eventKind;
  final String reason;
  final String? rawPreview;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineFallback &&
          id == other.id &&
          seq == other.seq &&
          eventId == other.eventId &&
          eventKind == other.eventKind &&
          reason == other.reason &&
          rawPreview == other.rawPreview &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    TimelineFallback,
    id,
    seq,
    eventId,
    eventKind,
    reason,
    rawPreview,
    occurredAtMs,
  ]);
}

sealed class WorkGroupMember {
  const WorkGroupMember({required this.id, required this.seq});
  final String id;
  final int seq;
}

final class WorkGroupReasoning extends WorkGroupMember {
  const WorkGroupReasoning({
    required super.id,
    required super.seq,
    required this.text,
    required this.summary,
    this.bodyRef,
    required this.outcome,
    this.startedAtMs,
    this.finishedAtMs,
  });
  final String text;
  final String summary;
  final BodyRef? bodyRef;
  final String outcome;
  final int? startedAtMs;
  final int? finishedAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkGroupReasoning &&
          id == other.id &&
          seq == other.seq &&
          text == other.text &&
          summary == other.summary &&
          bodyRef == other.bodyRef &&
          outcome == other.outcome &&
          startedAtMs == other.startedAtMs &&
          finishedAtMs == other.finishedAtMs;
  @override
  int get hashCode => Object.hashAll([
    WorkGroupReasoning,
    id,
    seq,
    text,
    summary,
    bodyRef,
    outcome,
    startedAtMs,
    finishedAtMs,
  ]);
}

final class WorkGroupToolCall extends WorkGroupMember {
  WorkGroupToolCall({
    required super.id,
    required super.seq,
    required this.callId,
    this.turnId,
    required this.toolName,
    this.presentationContract,
    required this.status,
    required this.summary,
    this.arguments,
    this.resultPreview,
    required this.payloadJson,
    required Iterable<BodyRef> bodies,
    this.waitJson,
    this.startedAtMs,
    this.finishedAtMs,
  }) : bodies = List.unmodifiable(bodies);
  final String callId;
  final String? turnId;
  final String toolName;
  final String? presentationContract;
  final String status;
  final String summary;
  final String? arguments;
  final String? resultPreview;
  final String payloadJson;
  final List<BodyRef> bodies;
  final String? waitJson;
  final int? startedAtMs;
  final int? finishedAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkGroupToolCall &&
          id == other.id &&
          seq == other.seq &&
          callId == other.callId &&
          turnId == other.turnId &&
          toolName == other.toolName &&
          presentationContract == other.presentationContract &&
          status == other.status &&
          summary == other.summary &&
          arguments == other.arguments &&
          resultPreview == other.resultPreview &&
          payloadJson == other.payloadJson &&
          listEquals(bodies, other.bodies) &&
          waitJson == other.waitJson &&
          startedAtMs == other.startedAtMs &&
          finishedAtMs == other.finishedAtMs;
  @override
  int get hashCode => Object.hashAll([
    WorkGroupToolCall,
    id,
    seq,
    callId,
    turnId,
    toolName,
    presentationContract,
    status,
    summary,
    arguments,
    resultPreview,
    payloadJson,
    Object.hashAll(bodies),
    waitJson,
    startedAtMs,
    finishedAtMs,
  ]);
}

final class WorkGroupAgent extends WorkGroupMember {
  const WorkGroupAgent({
    required super.id,
    required super.seq,
    required this.agentId,
    required this.name,
    required this.status,
    required this.summary,
    required this.payloadJson,
    this.startedAtMs,
    this.finishedAtMs,
  });
  final String agentId;
  final String name;
  final String status;
  final String summary;
  final String payloadJson;
  final int? startedAtMs;
  final int? finishedAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkGroupAgent &&
          id == other.id &&
          seq == other.seq &&
          agentId == other.agentId &&
          name == other.name &&
          status == other.status &&
          summary == other.summary &&
          payloadJson == other.payloadJson &&
          startedAtMs == other.startedAtMs &&
          finishedAtMs == other.finishedAtMs;
  @override
  int get hashCode => Object.hashAll([
    WorkGroupAgent,
    id,
    seq,
    agentId,
    name,
    status,
    summary,
    payloadJson,
    startedAtMs,
    finishedAtMs,
  ]);
}

final class WorkGroupFileChange extends WorkGroupMember {
  WorkGroupFileChange({
    required super.id,
    required super.seq,
    required this.summary,
    required this.payloadJson,
    required Iterable<BodyRef> bodies,
    this.occurredAtMs,
  }) : bodies = List.unmodifiable(bodies);
  final String summary;
  final String payloadJson;
  final List<BodyRef> bodies;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkGroupFileChange &&
          id == other.id &&
          seq == other.seq &&
          summary == other.summary &&
          payloadJson == other.payloadJson &&
          listEquals(bodies, other.bodies) &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    WorkGroupFileChange,
    id,
    seq,
    summary,
    payloadJson,
    Object.hashAll(bodies),
    occurredAtMs,
  ]);
}

final class WorkGroupSkill extends WorkGroupMember {
  const WorkGroupSkill({
    required super.id,
    required super.seq,
    required this.name,
    required this.summary,
    required this.payloadJson,
    this.occurredAtMs,
  });
  final String name;
  final String summary;
  final String payloadJson;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkGroupSkill &&
          id == other.id &&
          seq == other.seq &&
          name == other.name &&
          summary == other.summary &&
          payloadJson == other.payloadJson &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    WorkGroupSkill,
    id,
    seq,
    name,
    summary,
    payloadJson,
    occurredAtMs,
  ]);
}

final class WorkGroupFallback extends WorkGroupMember {
  const WorkGroupFallback({
    required super.id,
    required super.seq,
    required this.eventId,
    required this.eventKind,
    required this.reason,
    this.occurredAtMs,
  });
  final String eventId;
  final String eventKind;
  final String reason;
  final int? occurredAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkGroupFallback &&
          id == other.id &&
          seq == other.seq &&
          eventId == other.eventId &&
          eventKind == other.eventKind &&
          reason == other.reason &&
          occurredAtMs == other.occurredAtMs;
  @override
  int get hashCode => Object.hashAll([
    WorkGroupFallback,
    id,
    seq,
    eventId,
    eventKind,
    reason,
    occurredAtMs,
  ]);
}

sealed class TimelinePatch {
  const TimelinePatch();
}

final class TimelineReset extends TimelinePatch {
  TimelineReset({
    required Iterable<TimelineItem> items,
    required this.hasMoreOlder,
    this.olderCursor,
    required this.revision,
  }) : items = List.unmodifiable(items);
  final List<TimelineItem> items;
  final bool hasMoreOlder;
  final String? olderCursor;
  final int revision;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineReset &&
          listEquals(items, other.items) &&
          hasMoreOlder == other.hasMoreOlder &&
          olderCursor == other.olderCursor &&
          revision == other.revision;
  @override
  int get hashCode => Object.hashAll([
    TimelineReset,
    Object.hashAll(items),
    hasMoreOlder,
    olderCursor,
    revision,
  ]);
}

final class TimelinePrependOlder extends TimelinePatch {
  TimelinePrependOlder({
    required Iterable<TimelineItem> items,
    required this.hasMoreOlder,
    this.olderCursor,
  }) : items = List.unmodifiable(items);
  final List<TimelineItem> items;
  final bool hasMoreOlder;
  final String? olderCursor;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelinePrependOlder &&
          listEquals(items, other.items) &&
          hasMoreOlder == other.hasMoreOlder &&
          olderCursor == other.olderCursor;
  @override
  int get hashCode => Object.hashAll([
    TimelinePrependOlder,
    Object.hashAll(items),
    hasMoreOlder,
    olderCursor,
  ]);
}

final class TimelineAppend extends TimelinePatch {
  TimelineAppend({required Iterable<TimelineItem> items})
    : items = List.unmodifiable(items);
  final List<TimelineItem> items;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineAppend && listEquals(items, other.items);
  @override
  int get hashCode => Object.hashAll([TimelineAppend, Object.hashAll(items)]);
}

final class TimelineUpdate extends TimelinePatch {
  const TimelineUpdate({required this.item});
  final TimelineItem item;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TimelineUpdate && item == other.item;
  @override
  int get hashCode => Object.hashAll([TimelineUpdate, item]);
}

final class TimelineRemove extends TimelinePatch {
  const TimelineRemove({required this.itemId});
  final String itemId;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineRemove && itemId == other.itemId;
  @override
  int get hashCode => Object.hashAll([TimelineRemove, itemId]);
}

sealed class LiveStatusPhase {
  const LiveStatusPhase();
}

final class LiveStatusIdle extends LiveStatusPhase {
  const LiveStatusIdle();
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LiveStatusIdle && true;
  @override
  int get hashCode => Object.hashAll([LiveStatusIdle]);
}

final class LiveStatusWorking extends LiveStatusPhase {
  LiveStatusWorking({
    required Iterable<LiveWorkItem> items,
    this.reasoningPreview,
    this.startedAtMs,
  }) : items = List.unmodifiable(items);
  final List<LiveWorkItem> items;
  final String? reasoningPreview;
  final int? startedAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusWorking &&
          listEquals(items, other.items) &&
          reasoningPreview == other.reasoningPreview &&
          startedAtMs == other.startedAtMs;
  @override
  int get hashCode => Object.hashAll([
    LiveStatusWorking,
    Object.hashAll(items),
    reasoningPreview,
    startedAtMs,
  ]);
}

final class LiveStatusStreamingText extends LiveStatusPhase {
  const LiveStatusStreamingText({
    required this.attemptId,
    required this.itemId,
    required this.text,
    this.startedAtMs,
  });
  final String attemptId;
  final String itemId;
  final String text;
  final int? startedAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusStreamingText &&
          attemptId == other.attemptId &&
          itemId == other.itemId &&
          text == other.text &&
          startedAtMs == other.startedAtMs;
  @override
  int get hashCode => Object.hashAll([
    LiveStatusStreamingText,
    attemptId,
    itemId,
    text,
    startedAtMs,
  ]);
}

final class LiveStatusCompacting extends LiveStatusPhase {
  const LiveStatusCompacting({required this.manual, this.startedAtMs});
  final bool manual;
  final int? startedAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusCompacting &&
          manual == other.manual &&
          startedAtMs == other.startedAtMs;
  @override
  int get hashCode =>
      Object.hashAll([LiveStatusCompacting, manual, startedAtMs]);
}

final class LiveStatusReconnecting extends LiveStatusPhase {
  const LiveStatusReconnecting({
    required this.attemptId,
    required this.message,
    this.retryAfterMs,
    required this.attempt,
    this.maxAttempts = 0,
  });
  final String attemptId;
  final String message;
  final int? retryAfterMs;
  final int attempt;
  final int maxAttempts;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusReconnecting &&
          attemptId == other.attemptId &&
          message == other.message &&
          retryAfterMs == other.retryAfterMs &&
          attempt == other.attempt &&
          maxAttempts == other.maxAttempts;
  @override
  int get hashCode => Object.hashAll([
    LiveStatusReconnecting,
    attemptId,
    message,
    retryAfterMs,
    attempt,
    maxAttempts,
  ]);
}

final class LiveStatusStopping extends LiveStatusPhase {
  const LiveStatusStopping({this.startedAtMs});
  final int? startedAtMs;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusStopping && startedAtMs == other.startedAtMs;
  @override
  int get hashCode => Object.hashAll([LiveStatusStopping, startedAtMs]);
}

sealed class ConversationFeedEvent {
  const ConversationFeedEvent();
}

final class ConversationTimeline extends ConversationFeedEvent {
  const ConversationTimeline({required this.patch});
  final TimelinePatch patch;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationTimeline && patch == other.patch;
  @override
  int get hashCode => Object.hashAll([ConversationTimeline, patch]);
}

final class ConversationLiveStatus extends ConversationFeedEvent {
  const ConversationLiveStatus({required this.snapshot});
  final LiveStatusSnapshot snapshot;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationLiveStatus && snapshot == other.snapshot;
  @override
  int get hashCode => Object.hashAll([ConversationLiveStatus, snapshot]);
}

final class ConversationSessionMeta extends ConversationFeedEvent {
  const ConversationSessionMeta({required this.snapshot});
  final SessionMetaSnapshot snapshot;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationSessionMeta && snapshot == other.snapshot;
  @override
  int get hashCode => Object.hashAll([ConversationSessionMeta, snapshot]);
}

final class ConversationInputPresented extends ConversationFeedEvent {
  const ConversationInputPresented({
    required this.inputId,
    required this.itemId,
  });
  final String inputId;
  final String itemId;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationInputPresented &&
          inputId == other.inputId &&
          itemId == other.itemId;
  @override
  int get hashCode =>
      Object.hashAll([ConversationInputPresented, inputId, itemId]);
}

final class ConversationResyncRequired extends ConversationFeedEvent {
  const ConversationResyncRequired({required this.reason});
  final String reason;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationResyncRequired && reason == other.reason;
  @override
  int get hashCode => Object.hashAll([ConversationResyncRequired, reason]);
}

final class SessionUsageSummary {
  const SessionUsageSummary({
    required this.appliedSequence,
    this.binding,
    required this.totals,
    required this.cache,
    required this.context,
    required this.throughput,
    required this.diagnostics,
    required this.pricing,
  });
  final int appliedSequence;
  final SessionModelUsageBinding? binding;
  final SessionUsageTotals totals;
  final SessionUsageCache cache;
  final SessionUsageContext context;
  final SessionUsageThroughput throughput;
  final SessionUsageDiagnostics diagnostics;
  final SessionUsagePricing pricing;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionUsageSummary &&
          appliedSequence == other.appliedSequence &&
          binding == other.binding &&
          totals == other.totals &&
          cache == other.cache &&
          context == other.context &&
          throughput == other.throughput &&
          diagnostics == other.diagnostics &&
          pricing == other.pricing;
  @override
  int get hashCode => Object.hashAll([
    SessionUsageSummary,
    appliedSequence,
    binding,
    totals,
    cache,
    context,
    throughput,
    diagnostics,
    pricing,
  ]);
}

final class SessionUsageTotals {
  const SessionUsageTotals({
    required this.inferenceCount,
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedPromptTokens,
    required this.cacheWriteTokens,
    required this.reasoningTokens,
    required this.totalTokens,
  });
  final int inferenceCount;
  final int promptTokens;
  final int completionTokens;
  final int cachedPromptTokens;
  final int cacheWriteTokens;
  final int reasoningTokens;
  final int totalTokens;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionUsageTotals &&
          inferenceCount == other.inferenceCount &&
          promptTokens == other.promptTokens &&
          completionTokens == other.completionTokens &&
          cachedPromptTokens == other.cachedPromptTokens &&
          cacheWriteTokens == other.cacheWriteTokens &&
          reasoningTokens == other.reasoningTokens &&
          totalTokens == other.totalTokens;
  @override
  int get hashCode => Object.hashAll([
    SessionUsageTotals,
    inferenceCount,
    promptTokens,
    completionTokens,
    cachedPromptTokens,
    cacheWriteTokens,
    reasoningTokens,
    totalTokens,
  ]);
}

final class SessionUsageCache {
  const SessionUsageCache({
    required this.inputTokens,
    required this.readTokens,
    required this.sampleCount,
    required this.incomplete,
  });
  final int inputTokens;
  final int readTokens;
  final int sampleCount;
  final bool incomplete;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionUsageCache &&
          inputTokens == other.inputTokens &&
          readTokens == other.readTokens &&
          sampleCount == other.sampleCount &&
          incomplete == other.incomplete;
  @override
  int get hashCode => Object.hashAll([
    SessionUsageCache,
    inputTokens,
    readTokens,
    sampleCount,
    incomplete,
  ]);
}

final class SessionUsageContext {
  const SessionUsageContext({required this.tokens, this.latestCall});
  final int tokens;
  final UsageCallSnapshot? latestCall;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionUsageContext &&
          tokens == other.tokens &&
          latestCall == other.latestCall;
  @override
  int get hashCode => Object.hashAll([SessionUsageContext, tokens, latestCall]);
}

final class SessionUsageThroughput {
  const SessionUsageThroughput({
    required this.turnId,
    required this.completionTokens,
    required this.responseMillis,
  });
  final String turnId;
  final int completionTokens;
  final int responseMillis;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionUsageThroughput &&
          turnId == other.turnId &&
          completionTokens == other.completionTokens &&
          responseMillis == other.responseMillis;
  @override
  int get hashCode => Object.hashAll([
    SessionUsageThroughput,
    turnId,
    completionTokens,
    responseMillis,
  ]);
}

final class SessionModelUsageBinding {
  const SessionModelUsageBinding({
    this.routeIdentity,
    required this.model,
    this.contextWindow,
    this.maxContextWindow,
    this.autoCompactLimit,
  });
  final String? routeIdentity;
  final String model;
  final int? contextWindow;
  final int? maxContextWindow;
  final int? autoCompactLimit;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionModelUsageBinding &&
          routeIdentity == other.routeIdentity &&
          model == other.model &&
          contextWindow == other.contextWindow &&
          maxContextWindow == other.maxContextWindow &&
          autoCompactLimit == other.autoCompactLimit;
  @override
  int get hashCode => Object.hashAll([
    SessionModelUsageBinding,
    routeIdentity,
    model,
    contextWindow,
    maxContextWindow,
    autoCompactLimit,
  ]);
}

final class SessionUsagePricing {
  SessionUsagePricing({
    required this.incomplete,
    required Iterable<RuntimeCostView> estimatedCosts,
    required Iterable<RuntimeCostView> estimatedCacheSavings,
  }) : estimatedCosts = List.unmodifiable(estimatedCosts),
       estimatedCacheSavings = List.unmodifiable(estimatedCacheSavings);
  final bool incomplete;
  final List<RuntimeCostView> estimatedCosts;
  final List<RuntimeCostView> estimatedCacheSavings;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionUsagePricing &&
          incomplete == other.incomplete &&
          listEquals(estimatedCosts, other.estimatedCosts) &&
          listEquals(estimatedCacheSavings, other.estimatedCacheSavings);
  @override
  int get hashCode => Object.hashAll([
    SessionUsagePricing,
    incomplete,
    Object.hashAll(estimatedCosts),
    Object.hashAll(estimatedCacheSavings),
  ]);
}

final class SessionUsageDiagnostics {
  SessionUsageDiagnostics({
    required this.incompleteCalls,
    required this.missingCalls,
    required this.partialCalls,
    required this.invalidCalls,
    required this.overflowCalls,
    required Iterable<UsageOutcomeCountSnapshot> byOutcome,
    required Iterable<UsagePurposeCountSnapshot> byPurpose,
    required this.otherPurposeCalls,
    required Iterable<UsageIssueCountSnapshot> byIssue,
    required Iterable<UsageCallSnapshot> recentGaps,
    required this.legacyUnknown,
    required this.legacyIncomplete,
    required this.countsOverflowed,
  }) : byOutcome = List.unmodifiable(byOutcome),
       byPurpose = List.unmodifiable(byPurpose),
       byIssue = List.unmodifiable(byIssue),
       recentGaps = List.unmodifiable(recentGaps);
  final int incompleteCalls;
  final int missingCalls;
  final int partialCalls;
  final int invalidCalls;
  final int overflowCalls;
  final List<UsageOutcomeCountSnapshot> byOutcome;
  final List<UsagePurposeCountSnapshot> byPurpose;
  final int otherPurposeCalls;
  final List<UsageIssueCountSnapshot> byIssue;
  final List<UsageCallSnapshot> recentGaps;
  final bool legacyUnknown;
  final bool legacyIncomplete;
  final bool countsOverflowed;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionUsageDiagnostics &&
          incompleteCalls == other.incompleteCalls &&
          missingCalls == other.missingCalls &&
          partialCalls == other.partialCalls &&
          invalidCalls == other.invalidCalls &&
          overflowCalls == other.overflowCalls &&
          listEquals(byOutcome, other.byOutcome) &&
          listEquals(byPurpose, other.byPurpose) &&
          otherPurposeCalls == other.otherPurposeCalls &&
          listEquals(byIssue, other.byIssue) &&
          listEquals(recentGaps, other.recentGaps) &&
          legacyUnknown == other.legacyUnknown &&
          legacyIncomplete == other.legacyIncomplete &&
          countsOverflowed == other.countsOverflowed;
  @override
  int get hashCode => Object.hashAll([
    SessionUsageDiagnostics,
    incompleteCalls,
    missingCalls,
    partialCalls,
    invalidCalls,
    overflowCalls,
    Object.hashAll(byOutcome),
    Object.hashAll(byPurpose),
    otherPurposeCalls,
    Object.hashAll(byIssue),
    Object.hashAll(recentGaps),
    legacyUnknown,
    legacyIncomplete,
    countsOverflowed,
  ]);
}

List<Object?> _freezeJsonList(Iterable<Object?> values) =>
    List.unmodifiable(values.map(_freezeJson));
Object? _freezeJson(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry(key, _freezeJson(value))),
  ),
  List<Object?>() => _freezeJsonList(value),
  _ => value,
};

bool _jsonEquals(Object? left, Object? right) {
  if (left is List<Object?> && right is List<Object?>) {
    return left.length == right.length &&
        [for (var i = 0; i < left.length; i++) _jsonEquals(left[i], right[i])]
            .every((equal) => equal);
  }
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _jsonEquals(left[key], right[key]),
        );
  }
  return left == right;
}

int _jsonHash(Object? value) => switch (value) {
  List<Object?>() => Object.hashAll(value.map(_jsonHash)),
  Map<String, Object?>() => Object.hashAllUnordered(
    value.entries.map(
      (entry) => Object.hash(entry.key, _jsonHash(entry.value)),
    ),
  ),
  _ => value.hashCode,
};

final class ConversationRuntimeUsage {
  ConversationRuntimeUsage({
    required this.diagnostics,
    required this.hasIncompleteUsage,
    required this.modelId,
    this.contextWindow,
    this.maxContextWindow,
    this.autoCompactLimit,
    required this.latestContextTokens,
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedPromptTokens,
    required this.cacheWriteTokens,
    required this.reasoningTokens,
    required this.inferenceCount,
    required this.totalTokens,
    required this.cacheUsage,
    required Iterable<RuntimeCostView> estimatedCosts,
    required Iterable<RuntimeCostView> estimatedCacheSavings,
    required this.hasUnpricedUsage,
    this.promptGeneration,
    this.promptCachePolicy,
    this.prefixChangedReason,
    required this.updatedAt,
  }) : estimatedCosts = List.unmodifiable(estimatedCosts),
       estimatedCacheSavings = List.unmodifiable(estimatedCacheSavings);
  final ThreadUsageDiagnostics diagnostics;
  final bool hasIncompleteUsage;
  final String modelId;
  final int? contextWindow;
  final int? maxContextWindow;
  final int? autoCompactLimit;
  final int latestContextTokens;
  final int promptTokens;
  final int completionTokens;
  final int cachedPromptTokens;
  final int cacheWriteTokens;
  final int reasoningTokens;
  final int inferenceCount;
  final int totalTokens;
  final CacheUsageView cacheUsage;
  final List<RuntimeCostView> estimatedCosts;
  final List<RuntimeCostView> estimatedCacheSavings;
  final bool hasUnpricedUsage;
  final int? promptGeneration;
  final String? promptCachePolicy;
  final ConversationPromptPrefixChangedReason? prefixChangedReason;
  final int updatedAt;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationRuntimeUsage &&
          diagnostics == other.diagnostics &&
          hasIncompleteUsage == other.hasIncompleteUsage &&
          modelId == other.modelId &&
          contextWindow == other.contextWindow &&
          maxContextWindow == other.maxContextWindow &&
          autoCompactLimit == other.autoCompactLimit &&
          latestContextTokens == other.latestContextTokens &&
          promptTokens == other.promptTokens &&
          completionTokens == other.completionTokens &&
          cachedPromptTokens == other.cachedPromptTokens &&
          cacheWriteTokens == other.cacheWriteTokens &&
          reasoningTokens == other.reasoningTokens &&
          inferenceCount == other.inferenceCount &&
          totalTokens == other.totalTokens &&
          cacheUsage == other.cacheUsage &&
          listEquals(estimatedCosts, other.estimatedCosts) &&
          listEquals(estimatedCacheSavings, other.estimatedCacheSavings) &&
          hasUnpricedUsage == other.hasUnpricedUsage &&
          promptGeneration == other.promptGeneration &&
          promptCachePolicy == other.promptCachePolicy &&
          prefixChangedReason == other.prefixChangedReason &&
          updatedAt == other.updatedAt;
  @override
  int get hashCode => Object.hashAll([
    ConversationRuntimeUsage,
    diagnostics,
    hasIncompleteUsage,
    modelId,
    contextWindow,
    maxContextWindow,
    autoCompactLimit,
    latestContextTokens,
    promptTokens,
    completionTokens,
    cachedPromptTokens,
    cacheWriteTokens,
    reasoningTokens,
    inferenceCount,
    totalTokens,
    cacheUsage,
    Object.hashAll(estimatedCosts),
    Object.hashAll(estimatedCacheSavings),
    hasUnpricedUsage,
    promptGeneration,
    promptCachePolicy,
    prefixChangedReason,
    updatedAt,
  ]);
}

final class ConversationRuntimeSnapshot {
  ConversationRuntimeSnapshot({
    required this.threadId,
    required Iterable<CurrentStateField> deferred,
    required this.usage,
    this.liveUsage,
    required this.turnCompletionTokens,
    required this.turnResponseMillis,
    TimelineTodoListUpdate? todo,
    required Iterable<String> activeSkills,
    required Iterable<String> activeMcpServers,
    required Iterable<String> activeLspServers,
    this.progress,
    this.mcpHealth,
    this.workflow,
    this.plan,
    this.execution,
    this.continuation,
    required this.updatedAt,
  }) : deferred = List.unmodifiable(deferred),
       activeSkills = List.unmodifiable(activeSkills),
       activeMcpServers = List.unmodifiable(activeMcpServers),
       activeLspServers = List.unmodifiable(activeLspServers),
       todo = _copyTodo(todo);
  final String threadId;
  final List<CurrentStateField> deferred;
  final ConversationRuntimeUsage usage;
  final ThreadRuntimeLiveUsageView? liveUsage;
  final int turnCompletionTokens;
  final int turnResponseMillis;
  final TimelineTodoListUpdate? todo;
  final List<String> activeSkills;
  final List<String> activeMcpServers;
  final List<String> activeLspServers;
  final String? progress;
  final ConversationMcpHealthSnapshot? mcpHealth;
  final WorkflowRuntimeView? workflow;
  final PlanRuntimeView? plan;
  final AgentExecutionView? execution;
  final ContinuationView? continuation;
  final int updatedAt;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationRuntimeSnapshot &&
          threadId == other.threadId &&
          listEquals(deferred, other.deferred) &&
          usage == other.usage &&
          liveUsage == other.liveUsage &&
          turnCompletionTokens == other.turnCompletionTokens &&
          turnResponseMillis == other.turnResponseMillis &&
          _todoEquals(todo, other.todo) &&
          listEquals(activeSkills, other.activeSkills) &&
          listEquals(activeMcpServers, other.activeMcpServers) &&
          listEquals(activeLspServers, other.activeLspServers) &&
          progress == other.progress &&
          mcpHealth == other.mcpHealth &&
          workflow == other.workflow &&
          plan == other.plan &&
          execution == other.execution &&
          continuation == other.continuation &&
          updatedAt == other.updatedAt;
  @override
  int get hashCode => Object.hashAll([
    ConversationRuntimeSnapshot,
    threadId,
    Object.hashAll(deferred),
    usage,
    liveUsage,
    turnCompletionTokens,
    turnResponseMillis,
    _todoHash(todo),
    Object.hashAll(activeSkills),
    Object.hashAll(activeMcpServers),
    Object.hashAll(activeLspServers),
    progress,
    mcpHealth,
    workflow,
    plan,
    execution,
    continuation,
    updatedAt,
  ]);
}

final class ConversationMcpHealthSnapshot {
  ConversationMcpHealthSnapshot({
    required this.generation,
    required Iterable<ConversationMcpAvailabilityDescriptor> servers,
  }) : servers = List.unmodifiable(servers);
  final int generation;
  final List<ConversationMcpAvailabilityDescriptor> servers;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationMcpHealthSnapshot &&
          generation == other.generation &&
          listEquals(servers, other.servers);
  @override
  int get hashCode => Object.hashAll([
    ConversationMcpHealthSnapshot,
    generation,
    Object.hashAll(servers),
  ]);
}

final class ConversationMcpAvailabilityDescriptor {
  const ConversationMcpAvailabilityDescriptor({
    required this.server,
    required this.availability,
    this.message,
    this.lastCheckedAt,
    this.toolCount,
  });
  final ConversationMcpServerDescriptor server;
  final String availability;
  final String? message;
  final int? lastCheckedAt;
  final int? toolCount;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationMcpAvailabilityDescriptor &&
          server == other.server &&
          availability == other.availability &&
          message == other.message &&
          lastCheckedAt == other.lastCheckedAt &&
          toolCount == other.toolCount;
  @override
  int get hashCode => Object.hashAll([
    ConversationMcpAvailabilityDescriptor,
    server,
    availability,
    message,
    lastCheckedAt,
    toolCount,
  ]);
}

final class ConversationMcpServerDescriptor {
  const ConversationMcpServerDescriptor({
    required this.id,
    required this.source,
    required this.transport,
    required this.endpoint,
    required this.builtIn,
  });
  final String id;
  final String source;
  final String transport;
  final String endpoint;
  final bool builtIn;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationMcpServerDescriptor &&
          id == other.id &&
          source == other.source &&
          transport == other.transport &&
          endpoint == other.endpoint &&
          builtIn == other.builtIn;
  @override
  int get hashCode => Object.hashAll([
    ConversationMcpServerDescriptor,
    id,
    source,
    transport,
    endpoint,
    builtIn,
  ]);
}

enum ConversationPromptPrefixChangedReason {
  initial,
  promptScopeChanged,
  accountChanged,
  modelChanged,
  baseInstructionsChanged,
  globalInstructionsChanged,
  modeRoleChanged,
  skillCatalogChanged,
  workspaceInstructionsChanged,
  requestPropertiesChanged,
  fixedPrefixChanged,
  toolSchemaChanged,
  contextCompacted,
  contextAppended,
  contextRecovered,
}

TimelineTodoListUpdate? _copyTodo(TimelineTodoListUpdate? todo) => todo == null
    ? null
    : TimelineTodoListUpdate(
        callId: todo.callId,
        items: List.unmodifiable(todo.items),
        agentId: todo.agentId,
        path: todo.path,
        parentPath: todo.parentPath,
        explanation: todo.explanation,
      );

bool _todoEquals(TimelineTodoListUpdate? left, TimelineTodoListUpdate? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null) return false;
  return left.callId == right.callId &&
      left.agentId == right.agentId &&
      left.path == right.path &&
      left.parentPath == right.parentPath &&
      left.explanation == right.explanation &&
      listEquals(
        [for (final item in left.items) (item.step, item.status)],
        [for (final item in right.items) (item.step, item.status)],
      );
}

int _todoHash(TimelineTodoListUpdate? todo) => todo == null
    ? 0
    : Object.hash(
        todo.callId,
        todo.agentId,
        todo.path,
        todo.parentPath,
        todo.explanation,
        Object.hashAll(todo.items.map((item) => (item.step, item.status))),
      );
