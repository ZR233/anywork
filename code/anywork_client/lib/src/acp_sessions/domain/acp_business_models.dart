import 'dart:convert' show utf8;

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

final class AcpCompletedRunView {
  AcpCompletedRunView({
    required this.run,
    required this.completionSequence,
    required this.result,
    required this.summary,
    required this.truncated,
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
  const AcpInitializedEventView(this.capabilities);
  final AcpAgentCapabilitiesView capabilities;
}

final class AcpUpdateEventView extends AcpSessionEventView {
  const AcpUpdateEventView(this.update);
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

final class AcpCompletedEventView extends AcpSessionEventView {
  const AcpCompletedEventView(this.completed);
  final AcpCompletedRunView completed;
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
  });
  final AcpSessionTargetView target;
  final bool hasObservation;
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
    this.workerError,
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
  final String? workerError;
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

final class AcpListRequestView {
  const AcpListRequestView({required this.target, required this.request});
  final AcpSessionTargetView target;
  final AcpListSessionsRequestView request;
}
