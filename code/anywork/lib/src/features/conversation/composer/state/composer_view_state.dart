import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../domain/models/composer_primary_action.dart';

part 'composer_view_state.freezed.dart';

@freezed
abstract class StartPageComposerViewState with _$StartPageComposerViewState {
  const StartPageComposerViewState._();

  const factory StartPageComposerViewState({
    required StudioProject? project,
    required List<ModelSelectionAccount> accounts,
    required List<ModeModelRouteView> modeModelRoutes,
    required bool settingsLoaded,

    /// Recovery 已判为访问受阻时不允许编辑；执行阻塞只禁提交。
    required bool canEdit,
    required bool canSubmit,

    /// 同目标规则选出的最高优先级执行阻塞 issue；`null` 表示没有。
    required StudioRecoveryIssue? recoveryIssue,
    required Map<String, CommandStatus> commands,
    required List<ComposerTargetDiagnostic> diagnostics,
    required ThreadModeCatalogView? modeCatalog,
    required StartSessionDraft sessionDraft,
    required ComposerThreadState composer,
    required ComposerTargetDiagnostic? targetDiagnostic,
  }) = _StartPageComposerViewState;

  ThreadModeId get mode => sessionDraft.forProject(project?.id).mode;
  ThreadWorkspaceMode get workspaceMode =>
      sessionDraft.forProject(project?.id).workspaceMode;
  String get draftText => sessionDraft.forProject(project?.id).text;
  bool get submitting => sessionDraft.submitting;
  NewThreadPreparation? get preparation =>
      sessionDraft.preparations[project?.id];

  ModeModelRouteView? canonicalRoute(ThreadModeId mode) =>
      _route(mode).canonical;
  bool routePending(ThreadModeId mode) => _route(mode).pending;
  ModeModelRouteView? displayRoute(ThreadModeId mode) => _route(mode).display;
  ModeModelRouteView? laneRoute(ThreadModeId mode) => _route(mode).lane;
  String? routeFailure(ThreadModeId mode) => _route(mode).failure;

  StartRouteQuery _route(ThreadModeId mode) => ModelRouteQueries.startRoute(
    routes: modeModelRoutes,
    commands: commands,
    draft: sessionDraft,
    mode: mode,
  );
}

@freezed
abstract class ComposerDockViewState with _$ComposerDockViewState {
  const ComposerDockViewState._();

  const factory ComposerDockViewState({
    required StudioThread? thread,
    required bool hasSnapshot,
    required int revision,
    required ComposerThreadState composer,
    required PendingInteraction? activeInteraction,
    required StudioTurnView? turn,
    required AgentExecutionView? execution,
    required ContinuationView? continuation,
    required CommandStatus? stopCommand,
    required CommandStatus? continueCommand,
    int? queuedStopStartedAtMs,
    required bool saveBlocked,

    /// 同一 Client 目标规则选出的最高优先级执行恢复阻塞。
    required StudioRecoveryIssue? recoveryIssue,

    /// 目录 thread 或已加载 canonical workspace.thread 已 closing/closed：
    /// 不显示执行入口，历史仍展示、草稿不清。
    required bool executionClosed,
    required List<ChildInteractionSummary> childInteractions,
    required DomainSyncStatus? childInteractionSync,
    required Map<String, String> childInteractionSources,
    required ThreadModelRouteView? modelRoute,
    ModelRouteDisplay? routeDisplay,
    required bool routePending,
    required String? routeFailure,
    required WorkflowRuntimeView? workflow,
    required List<ModelSelectionAccount> accounts,
    required bool settingsLoaded,
    required ComposerTargetDiagnostic? targetDiagnostic,
    required List<ComposerTargetDiagnostic> additionalDiagnostics,
  }) = _ComposerDockViewState;

  bool get isBusy => turn?.state.isBusy ?? false;
  InteractionStopViewState get interactionStop {
    final executionId = execution?.id;
    final command = stopCommand;
    final matches = executionId != null && command?.target.label == executionId;
    return InteractionStopViewState(
      executionId: executionId,
      pending:
          matches &&
          (command?.isPending ?? false) &&
          !(command?.accepted ?? false),
      stopping:
          (execution?.phase.isStopping ?? false) ||
          (matches && (command?.accepted ?? false)),
      failure: command?.phase == CommandPhase.failed ? command?.error : null,
    );
  }

  bool get hasActiveWorkflow => workflow?.isActive ?? false;
  bool get modelUnavailable => displayRoute?.available == false;
  bool get continuationPending =>
      continuation != null &&
      continueCommand?.target.label == continuation!.id &&
      (continueCommand?.isPending ?? false) &&
      !(continueCommand?.accepted ?? false) &&
      !continuation!.claimed;
  bool get continuationAccepted =>
      continuation?.claimed == true ||
      (continuation != null &&
          continueCommand?.target.label == continuation!.id &&
          (continueCommand?.accepted ?? false));
  ComposerBlocker? get operationFailure {
    final command =
        continueCommand?.phase == CommandPhase.failed &&
            continuation != null &&
            continueCommand?.target.label == continuation!.id
        ? continueCommand
        : null;
    final error = command?.error;
    return command == null
        ? null
        : ComposerFailureBlocker(
            error?.reason,
            recoveryIssue: recoveryIssueFromFailure(error),
          );
  }

  ComposerBlocker? get canonicalBlocker {
    if (saveBlocked) return const ComposerStorageBlocker();
    if (recoveryIssue case final issue?) return ComposerRecoveryBlocker(issue);
    if (modelUnavailable) return const ComposerModelBlocker();
    return null;
  }

  ModelRouteDisplay? get displayRoute =>
      routeDisplay ??
      ModelRouteQueries.threadRoute(
        canonical: modelRoute,
        command: null,
        accounts: accounts,
      );
}

/// Pure projection of the current execution and the SDK stop command.
final class InteractionStopViewState {
  const InteractionStopViewState({
    required this.executionId,
    required this.pending,
    required this.stopping,
    required this.failure,
  });

  final String? executionId;
  final bool pending;
  final bool stopping;
  final StudioFailure? failure;

  bool get canStop => executionId != null && !pending && !stopping;
}
