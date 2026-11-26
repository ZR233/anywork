import 'dart:convert' show utf8;

import '../../models/studio_enums.dart';
import '../../models/delegation_models.dart';
import '../../models/interaction_models.dart' show UserQuestionView;
import '../../models/runtime_models.dart'
    show PlanRuntimeView, WorkflowRunView, WorkflowRuntimeGraphSnapshotView;

import '../../models/acp_models.dart' show AcpAuthMethodKindView;
import 'acp_content.dart';
import 'acp_session_payloads.dart';
import 'acp_updates.dart';
import 'acp_values.dart';

sealed class AcpOpenIntentView {
  const AcpOpenIntentView();
}

final class AcpNewIntentView extends AcpOpenIntentView {
  const AcpNewIntentView();
}

final class AcpDraftIntentView extends AcpOpenIntentView {
  const AcpDraftIntentView({
    required this.workspaceMode,
    this.delegationMode,
    this.delegationPreference,
    this.mode,
  });
  final ThreadWorkspaceMode workspaceMode;
  final DelegationMode? delegationMode;
  final DelegationPreference? delegationPreference;
  final String? mode;
}

final class AcpLoadIntentView extends AcpOpenIntentView {
  const AcpLoadIntentView(this.sessionId);
  final AcpRemoteSessionId sessionId;
}

final class AcpResumeIntentView extends AcpOpenIntentView {
  const AcpResumeIntentView(this.sessionId);
  final AcpRemoteSessionId sessionId;
}

final class OpenAcpSessionRequestView {
  const OpenAcpSessionRequestView({
    required this.accountId,
    required this.expectedConnectionRevision,
    required this.workspaceId,
    required this.intent,
    this.threadId,
  });
  final String accountId;
  final BigInt expectedConnectionRevision;
  final String workspaceId;
  final String? threadId;
  final AcpOpenIntentView intent;
}

/// Product membership and Studio materialization generation.
///
/// The three product IDs are independent, and [instance] is not an SDK run or
/// permission generation. Commands must carry the original target unchanged.
final class AcpSessionTargetView {
  const AcpSessionTargetView({
    required this.sessionId,
    required this.agentId,
    required this.threadId,
    required this.instance,
  });
  final String sessionId;
  final String agentId;
  final String threadId;
  final BigInt instance;
  @override
  bool operator ==(Object other) =>
      other is AcpSessionTargetView &&
      sessionId == other.sessionId &&
      agentId == other.agentId &&
      threadId == other.threadId &&
      instance == other.instance;
  @override
  int get hashCode => Object.hash(sessionId, agentId, threadId, instance);
}

/// Original SDK run qualification, independent of the product target instance.
final class AcpRunIdView {
  const AcpRunIdView({required this.instance, required this.sequence});
  final BigInt instance;
  final BigInt sequence;
  @override
  bool operator ==(Object other) =>
      other is AcpRunIdView &&
      instance == other.instance &&
      sequence == other.sequence;
  @override
  int get hashCode => Object.hash(instance, sequence);
}

/// Original SDK permission qualification, independent of the target instance.
final class AcpPermissionIdView {
  const AcpPermissionIdView({required this.instance, required this.sequence});
  final BigInt instance;
  final BigInt sequence;
  @override
  bool operator ==(Object other) =>
      other is AcpPermissionIdView &&
      instance == other.instance &&
      sequence == other.sequence;
  @override
  int get hashCode => Object.hash(instance, sequence);
}

enum AcpBusinessFailureKindView {
  busy,
  stale,
  notReady,
  closed,
  unsupported,
  unsupportedVersion,
  serverVersionMismatch,
  invalidOption,
  rpc,
  installRequired,
  installationInvalid,
  unsupportedPlatform,
  missingExecutable,
  invalidWorkingDirectory,
  invalidDefinition,
  io,
  cancelled,
  preparation,
  publication,
}

final class AcpBusinessAuthMethodView {
  const AcpBusinessAuthMethodView({
    required this.id,
    required this.name,
    required this.kind,
    this.description,
  });
  final String id;
  final String name;
  final AcpAuthMethodKindView kind;
  final String? description;
}

final class AcpBusinessFailureView implements Exception {
  AcpBusinessFailureView({
    required this.kind,
    required this.message,
    this.rpcCode,
    this.rpcData,
    Iterable<AcpBusinessAuthMethodView> authMethods = const [],
  }) : authMethods = List.unmodifiable(authMethods);
  final AcpBusinessFailureKindView kind;
  final int? rpcCode;
  final String message;
  final AcpJsonValue? rpcData;
  final List<AcpBusinessAuthMethodView> authMethods;
  @override
  String toString() =>
      'AcpBusinessFailureView(${kind.name}, rpcCode: $rpcCode)';
}

final class AcpCommandOutcomeUnknown implements Exception {
  const AcpCommandOutcomeUnknown({required this.command, required this.cause});
  final String command;
  final Object cause;
  @override
  String toString() =>
      'ACP $command outcome unknown; the command was not resent';
}

final class AcpObservationDisposed implements Exception {
  const AcpObservationDisposed();
  @override
  String toString() =>
      'ACP observation was released; the business operation may continue';
}

/// An official non-exhaustive payload variant unsupported by this SDK version.
///
/// Adapters must fail explicitly rather than dropping the value, coercing it to
/// a known variant, or inventing Native state. [typeName] identifies the variant.
final class AcpUnsupportedPayload implements Exception {
  const AcpUnsupportedPayload(this.typeName);
  final String typeName;
  @override
  String toString() => 'Unsupported ACP payload: $typeName';
}

sealed class AcpResultView<T> {
  const AcpResultView();
}

final class AcpSuccessView<T> extends AcpResultView<T> {
  const AcpSuccessView(this.value);
  final T value;
}

final class AcpFailureView<T> extends AcpResultView<T> {
  const AcpFailureView(this.error);
  final AcpBusinessFailureView error;
}

enum AcpObservationGapView { windowExceeded, disconnected, encoding }

typedef AcpTextPerformanceView = ({
  int estimatedOutputTokens,
  int responseMillis,
});

final class AcpUsageSnapshotView {
  const AcpUsageSnapshotView({
    required this.used,
    required this.size,
    required this.updatedAt,
  });

  final BigInt used;
  final BigInt size;
  final int updatedAt;

  @override
  bool operator ==(Object other) =>
      other is AcpUsageSnapshotView &&
      used == other.used &&
      size == other.size &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(used, size, updatedAt);
}

final class AcpCostSnapshotView {
  const AcpCostSnapshotView({
    required this.amount,
    required this.currency,
    required this.updatedAt,
  });

  final double amount;
  final String currency;
  final int updatedAt;

  @override
  bool operator ==(Object other) =>
      other is AcpCostSnapshotView &&
      amount == other.amount &&
      currency == other.currency &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(amount, currency, updatedAt);
}

final class AcpTextPerformanceSnapshotView {
  const AcpTextPerformanceSnapshotView({
    required this.estimatedOutputTokens,
    required this.responseMillis,
    required this.updatedAt,
  });

  final int estimatedOutputTokens;
  final int responseMillis;
  final int updatedAt;

  @override
  bool operator ==(Object other) =>
      other is AcpTextPerformanceSnapshotView &&
      estimatedOutputTokens == other.estimatedOutputTokens &&
      responseMillis == other.responseMillis &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      Object.hash(estimatedOutputTokens, responseMillis, updatedAt);
}

final class AcpServerInfoView {
  const AcpServerInfoView({
    required this.name,
    required this.version,
    this.title,
  });

  final String name;
  final String version;
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is AcpServerInfoView &&
      name == other.name &&
      version == other.version &&
      title == other.title;

  @override
  int get hashCode => Object.hash(name, version, title);
}

final class AcpConfigItemSnapshotView {
  const AcpConfigItemSnapshotView({
    required this.id,
    required this.name,
    this.category,
    required this.valueId,
    required this.valueLabel,
  });

  final String id;
  final String name;
  final String? category;
  final String valueId;
  final String valueLabel;

  @override
  bool operator ==(Object other) =>
      other is AcpConfigItemSnapshotView &&
      id == other.id &&
      name == other.name &&
      category == other.category &&
      valueId == other.valueId &&
      valueLabel == other.valueLabel;

  @override
  int get hashCode => Object.hash(id, name, category, valueId, valueLabel);
}

final class AcpSessionInfoSnapshotView {
  AcpSessionInfoSnapshotView({
    this.usage,
    this.cost,
    this.textPerformance,
    this.lastStopReason,
    this.serverInfo,
    Iterable<AcpConfigItemSnapshotView> activeConfig = const [],
    this.completedTurns,
    required this.updatedAt,
  }) : activeConfig = List.unmodifiable(activeConfig);

  final AcpUsageSnapshotView? usage;
  final AcpCostSnapshotView? cost;
  final AcpTextPerformanceSnapshotView? textPerformance;
  final String? lastStopReason;
  final AcpServerInfoView? serverInfo;
  final List<AcpConfigItemSnapshotView> activeConfig;
  final int? completedTurns;
  final int updatedAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AcpSessionInfoSnapshotView) return false;
    if (usage != other.usage ||
        cost != other.cost ||
        textPerformance != other.textPerformance ||
        lastStopReason != other.lastStopReason ||
        serverInfo != other.serverInfo ||
        completedTurns != other.completedTurns ||
        updatedAt != other.updatedAt ||
        activeConfig.length != other.activeConfig.length) {
      return false;
    }
    for (var i = 0; i < activeConfig.length; i++) {
      if (activeConfig[i] != other.activeConfig[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    usage,
    cost,
    textPerformance,
    lastStopReason,
    serverInfo,
    Object.hashAll(activeConfig),
    completedTurns,
    updatedAt,
  );
}

final class AcpCompletedRunView {
  AcpCompletedRunView({
    required this.run,
    required this.completionSequence,
    required this.result,
    required this.summary,
    required this.truncated,
    this.textPerformance,
  }) {
    if (utf8.encode(summary).length > 16 * 1024) {
      throw ArgumentError('ACP completion summary exceeds the 16 KiB boundary');
    }
  }
  final AcpRunIdView run;
  final BigInt completionSequence;
  final AcpResultView<AcpPromptResponseView> result;
  final String summary;
  final bool truncated;
  final AcpTextPerformanceView? textPerformance;
}

sealed class AcpSessionEventView {
  const AcpSessionEventView();
}

final class AcpAgentCapabilitiesView {
  const AcpAgentCapabilitiesView({
    required this.image,
    required this.audio,
    required this.embeddedContext,
    required this.loadSession,
    required this.listSessions,
    required this.resumeSession,
  });

  final bool image;
  final bool audio;
  final bool embeddedContext;
  final bool loadSession;
  final bool listSessions;
  final bool resumeSession;
}

final class AcpInitializedEventView extends AcpSessionEventView {
  const AcpInitializedEventView(this.capabilities, {this.serverInfo});
  final AcpAgentCapabilitiesView capabilities;
  final AcpServerInfoView? serverInfo;
}

final class AcpUpdateEventView extends AcpSessionEventView {
  const AcpUpdateEventView(this.update, {this.textPerformance});
  final AcpTextPerformanceView? textPerformance;
  final AcpSessionNotificationView update;
}

final class AcpReadyEventView extends AcpSessionEventView {
  const AcpReadyEventView(this.response);
  final AcpNewSessionResponseView response;
}

final class AcpFailedEventView extends AcpSessionEventView {
  const AcpFailedEventView(this.error);
  final AcpBusinessFailureView error;
}

final class AcpPermissionEventView extends AcpSessionEventView {
  const AcpPermissionEventView({required this.id, required this.request});
  final AcpPermissionIdView id;
  final AcpPermissionRequestView request;
}

final class AcpConfiguredEventView extends AcpSessionEventView {
  const AcpConfiguredEventView(this.response);
  final AcpConfiguredResponseView response;
}

final class AcpModeSetEventView extends AcpSessionEventView {
  const AcpModeSetEventView(this.modeId);
  final AcpModeId modeId;
}

final class AcpWorkflowStateView {
  const AcpWorkflowStateView({
    this.modeId,
    this.modeDisplayName,
    this.run,
    this.graph,
    this.plan,
    this.pendingInteraction,
  });

  final String? modeId;
  final String? modeDisplayName;
  final WorkflowRunView? run;
  final WorkflowRuntimeGraphSnapshotView? graph;
  final PlanRuntimeView? plan;
  final AcpPendingInteractionView? pendingInteraction;
}

sealed class AcpPendingInteractionView {
  const AcpPendingInteractionView(this.id);

  final String id;
}

final class AcpPendingQuestionView extends AcpPendingInteractionView {
  AcpPendingQuestionView(super.id, Iterable<UserQuestionView> questions)
    : questions = List.unmodifiable(questions);

  final List<UserQuestionView> questions;
}

final class AcpPendingPlanConfirmationView extends AcpPendingInteractionView {
  const AcpPendingPlanConfirmationView(super.id);
}

final class AcpCompletedEventView extends AcpSessionEventView {
  const AcpCompletedEventView(this.completed);
  final AcpCompletedRunView completed;
}

final class AcpWorkflowStateUpdatedEventView extends AcpSessionEventView {
  const AcpWorkflowStateUpdatedEventView(this.state);
  final AcpWorkflowStateView state;
}

final class AcpGapEventView extends AcpSessionEventView {
  const AcpGapEventView(this.gap);
  final AcpObservationGapView gap;
}

sealed class AcpSessionFrameView {
  const AcpSessionFrameView();
}

final class AcpAcceptedFrameView extends AcpSessionFrameView {
  const AcpAcceptedFrameView({
    required this.target,
    required this.hasObservation,
    this.infoSnapshot,
    this.workflowState,
  });
  final AcpSessionTargetView target;
  final bool hasObservation;
  final AcpSessionInfoSnapshotView? infoSnapshot;
  final AcpWorkflowStateView? workflowState;
}

final class AcpSettledFrameView extends AcpSessionFrameView {
  const AcpSettledFrameView(this.result);
  final AcpResultView<void> result;
}

final class AcpEventFrameView extends AcpSessionFrameView {
  const AcpEventFrameView(this.event);
  final AcpSessionEventView event;
}

final class AcpBusinessSnapshotView {
  AcpBusinessSnapshotView({
    required this.target,
    required this.ready,
    required this.closing,
    required this.configPending,
    this.acpSessionId,
    Iterable<AcpSessionConfigOptionView>? configOptions,
    this.modes,
    this.activeRun,
    this.lastCompleted,
    this.observationGap,
    this.infoSnapshot,
    this.workflowState,
    Iterable<AcpBusinessAuthMethodView> authMethods = const [],
  }) : configOptions = configOptions == null
           ? null
           : List.unmodifiable(configOptions),
       authMethods = List.unmodifiable(authMethods);
  final AcpSessionTargetView target;
  final AcpRemoteSessionId? acpSessionId;
  final bool ready;
  final bool closing;
  final bool configPending;
  final List<AcpSessionConfigOptionView>? configOptions;
  final AcpSessionModeStateView? modes;
  final AcpRunIdView? activeRun;
  final AcpCompletedRunView? lastCompleted;
  final AcpObservationGapView? observationGap;
  final AcpSessionInfoSnapshotView? infoSnapshot;
  final AcpWorkflowStateView? workflowState;
  final List<AcpBusinessAuthMethodView> authMethods;
}

final class AcpMemberCloseFailureView {
  const AcpMemberCloseFailureView({
    required this.threadId,
    required this.message,
  });
  final String threadId;
  final String message;
}

final class AcpBusinessCloseView {
  AcpBusinessCloseView({
    required this.localComplete,
    required this.sdkFinished,
    required this.cleanupTimedOut,
    required this.unfinishedControls,
    this.remoteCloseError,
    this.sdkError,
    this.driverError,
    this.unfinishedPrompt,
    this.lastCompleted,
    Iterable<AcpMemberCloseFailureView> ownerFailures = const [],
  }) : ownerFailures = List.unmodifiable(ownerFailures);
  final bool localComplete;
  final bool sdkFinished;
  final bool cleanupTimedOut;
  final AcpBusinessFailureView? remoteCloseError;
  final AcpBusinessFailureView? sdkError;
  final String? driverError;
  final AcpRunIdView? unfinishedPrompt;
  final bool unfinishedControls;
  final AcpCompletedRunView? lastCompleted;
  final List<AcpMemberCloseFailureView> ownerFailures;
}

final class AcpPromptRequestView {
  AcpPromptRequestView({
    required this.target,
    required Iterable<AcpContentBlockView> content,
  }) : content = List.unmodifiable(content);
  final AcpSessionTargetView target;
  final List<AcpContentBlockView> content;
}

final class AcpReplaceRequestView {
  AcpReplaceRequestView({
    required this.target,
    required this.run,
    required Iterable<AcpContentBlockView> content,
  }) : content = List.unmodifiable(content);
  final AcpSessionTargetView target;
  final AcpRunIdView run;
  final List<AcpContentBlockView> content;
}

final class AcpInterruptRequestView {
  const AcpInterruptRequestView({required this.target, required this.run});
  final AcpSessionTargetView target;
  final AcpRunIdView run;
}

final class AcpConfigureRequestView {
  const AcpConfigureRequestView({
    required this.target,
    required this.configId,
    required this.value,
  });
  final AcpSessionTargetView target;
  final AcpConfigId configId;
  final AcpSessionConfigValueView value;
}

final class AcpSetModeRequestView {
  const AcpSetModeRequestView({required this.target, required this.modeId});
  final AcpSessionTargetView target;
  final AcpModeId modeId;
}

final class AcpSetThreadModeRequestView {
  const AcpSetThreadModeRequestView({
    required this.target,
    required this.modeId,
  });
  final AcpSessionTargetView target;
  final String modeId;
}

final class AcpPermissionAnswerRequestView {
  const AcpPermissionAnswerRequestView({
    required this.target,
    required this.permissionId,
    this.optionId,
  });
  final AcpSessionTargetView target;
  final AcpPermissionIdView permissionId;
  final AcpPermissionOptionId? optionId;
}

sealed class AcpHostInteractionAnswerView {
  const AcpHostInteractionAnswerView();
}

final class AcpHostQuestionAnswerView extends AcpHostInteractionAnswerView {
  AcpHostQuestionAnswerView(Map<String, List<String>> answers)
    : answers = Map.unmodifiable({
        for (final entry in answers.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      });

  final Map<String, List<String>> answers;
}

final class AcpHostApprovePlanView extends AcpHostInteractionAnswerView {
  const AcpHostApprovePlanView();
}

final class AcpHostRevisePlanView extends AcpHostInteractionAnswerView {
  const AcpHostRevisePlanView(this.feedback);

  final String feedback;
}

final class AcpHostCancelInteractionView extends AcpHostInteractionAnswerView {
  const AcpHostCancelInteractionView();
}

final class AcpHostInteractionAnswerRequestView {
  const AcpHostInteractionAnswerRequestView({
    required this.target,
    required this.interactionId,
    required this.answer,
  });

  final AcpSessionTargetView target;
  final String interactionId;
  final AcpHostInteractionAnswerView answer;
}

final class AcpListRequestView {
  const AcpListRequestView({required this.target, required this.request});
  final AcpSessionTargetView target;
  final AcpListSessionsRequestView request;
}
