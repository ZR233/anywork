import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../status/session_selectors.dart';
import '../../../shell/thread_preparation_card.dart';
import '../../interactions/connectors/child_interaction_connector.dart';
import '../../interactions/connectors/plan_confirmation_connector.dart';
import '../../interactions/connectors/tool_approval_connector.dart';
import '../../interactions/connectors/user_input_connector.dart';
import '../../interactions/state/interaction_payload.dart';
import '../composer.dart' show ComposerSubmissionControls;
import '../state/composer_input_state.dart';
import '../state/composer_view_state.dart';
import '../view_models/composer_view_model.dart';
import 'composer_dock_view.dart';
import 'composer_route_selectors.dart';
import 'composer_support_views.dart';
import 'composer_submission_body.dart';
import 'composer_submission_status.dart';
import 'prompt_composer_view.dart';
import 'start_environment_bar.dart';
import 'start_page_composer_view.dart';

/// Layout and selectors only. No Client lookup, observation or business awaits.
class ComposerContentView extends StatefulWidget {
  const ComposerContentView({
    required this.target,
    required this.state,
    required this.actions,
    this.compact = false,
    this.onAddProject,
    this.startBackendSelector,
    super.key,
  });

  final ComposerTarget target;
  final ComposerViewState state;
  final ComposerViewModel actions;
  final bool compact;
  final VoidCallback? onAddProject;
  final Widget? startBackendSelector;

  @override
  State<ComposerContentView> createState() => _ComposerContentViewState();
}

class _ComposerContentViewState extends State<ComposerContentView> {
  String? _notice;

  @override
  void didUpdateWidget(covariant ComposerContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target ||
        oldWidget.state.thread?.row?.backend !=
            widget.state.thread?.row?.backend ||
        oldWidget.state.thread?.displayRoute !=
            widget.state.thread?.displayRoute) {
      _notice = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final actions = widget.actions;
    final thread = state.thread;
    final start = state.start;
    final error = switch (state.actionFailure) {
      ComposerClipboardFailure.unsupportedImage =>
        context.l10n.composerClipboardImageUnsupported,
      ComposerClipboardFailure.readFailed =>
        context.l10n.composerClipboardReadFailed,
      final failure? => '$failure',
      null => null,
    };
    final input = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_notice case final notice?)
          Row(
            children: [
              Expanded(child: Text(notice)),
              IconButton(
                key: const ValueKey('model-notice-dismiss'),
                tooltip: context.l10n.statusModelNoticeDismiss,
                onPressed: () => setState(() => _notice = null),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        if (error != null) Text(error, key: StudioDriverKeys.composerError),
        PromptComposerView(
          state: state.input,
          actions: actions,
          targetKey: widget.target,
          creationCard: start != null,
          compact: widget.compact,
          selectorBar: _selectors(context),
        ),
      ],
    );
    if (start != null) {
      final project = start.project;
      final preparation = start.preparation;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (project != null && preparation != null)
            ThreadPreparationCard(
              key: ValueKey(preparation.inputId),
              project: project,
              preparation: preparation,
            ),
          for (final submission in state.submissions)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ComposerSubmissionBody(
                    submission: submission,
                    isSafeLink: actions.isSafeExternalLink,
                    onLink: actions.openExternalLink,
                  ),
                  for (final attachment in submission.attachments)
                    Text(attachment.filename),
                  ComposerSubmissionStatus(phase: submission.phase),
                  if (submission.error case final failure?) Text('$failure'),
                  ComposerSubmissionControls(
                    target: widget.target,
                    submission: submission,
                  ),
                ],
              ),
            ),
          StartPageComposerView(
            environmentBar: StartEnvironmentBar(
              state: state,
              actions: actions,
              onAddProject: widget.onAddProject,
              backendSelector: widget.startBackendSelector,
            ),
            composer: input,
          ),
        ],
      );
    }
    final row = thread?.row;
    if (thread == null || row == null || thread.executionClosed) {
      return const SizedBox.shrink();
    }
    final interaction = thread.activeInteraction;
    return ComposerDockView(
      compact: widget.compact,
      additionalDiagnostics: [
        for (final diagnostic in thread.additionalDiagnostics)
          if (diagnostic != thread.targetDiagnostic)
            ComposerTargetDiagnosticView(diagnostic: diagnostic),
      ],
      childInteractions: row.isChildRow
          ? null
          : ChildInteractionConnector(
              key: ValueKey(row.threadId),
              hostThreadId: row.threadId,
              items: thread.childInteractions,
              sync: thread.childInteractionSync,
              sources: thread.childInteractionSources,
            ),
      content: row.isChildRow && isRetiredAgentRole(row.role)
          ? Text(
              context.l10n.agentRoleRetired,
              key: const ValueKey('retired-agent-notice'),
            )
          : row.isChildRow
          ? AgentReadOnlyDockView(view: thread)
          : interaction != null
          ? _interaction(row.threadId, interaction, thread.interactionStop)
          : !state.input.enabled
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (thread.composer.error case final error?) Text(error),
                TextButton(
                  onPressed: actions.refresh,
                  child: Text(context.l10n.runtimeFatalRetry),
                ),
              ],
            )
          : input,
    );
  }

  Widget _selectors(BuildContext context) {
    final actions = widget.actions;
    final start = widget.state.start;
    if (start != null) {
      final mode = start.mode;
      final route = start.displayRoute(mode);
      final enabled = start.settingsLoaded && !start.submitting;
      return Wrap(
        key: StudioDriverKeys.startPageSelectors,
        spacing: 6,
        runSpacing: 4,
        children: [
          SessionModeSelector(
            catalog: widget.state.modeCatalog,
            mode: mode,
            enabled: enabled && start.project != null,
            lockedHint: start.project == null
                ? context.l10n.statusModeNeedsProject
                : context.l10n.statusSelectorsNotReady,
            onSelected: actions.setMode,
          ),
          ...modelRouteSelectorChildren(
            accounts: start.accounts,
            accountId: route?.accountId,
            modelId: route?.modelId,
            effort: route?.effort,
            pending: start.routePending(mode),
            enabled: enabled,
            unavailableReason:
                start.routeFailure(mode) ??
                context.l10n.statusModelRouteUnavailableFallback,
            onModelSelected: actions.setModel,
            onEffortSelected: actions.setEffort,
          ),
        ],
      );
    }
    final view = widget.state.thread!;
    final row = view.row;
    if (row == null || !row.isRootRow) return const SizedBox.shrink();
    final backend = row.backend;
    if (backend is! NativeAgentBackendView) {
      throw StateError('Native prompt composer cannot consume an ACP session');
    }
    final route = view.displayRoute;
    final blockedReason = switch (backend.status) {
      ThreadStatusView.idle => null,
      ThreadStatusView.closing ||
      ThreadStatusView.closed ||
      ThreadStatusView.faulted => context.l10n.statusModelSwitchWhileInactive,
      _ => context.l10n.statusModelSwitchWhileRunning,
    };
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 4,
      children: [
        if (row.mode case final mode?)
          SessionModeSelector(
            catalog: widget.state.modeCatalog,
            mode: mode,
            usesSnapshot: true,
            snapshotDisplayName: view.workflow?.currentRun?.modeDisplayName,
            enabled:
                !view.hasActiveWorkflow &&
                backend.status == ThreadStatusView.idle &&
                view.activeInteraction == null,
            onExplain: (message) => setState(() => _notice = message),
            onSelected: actions.setMode,
          ),
        if (view.modelRoute?.botId case final botId?)
          TextButton.icon(
            key: const ValueKey('bot-model-settings'),
            icon: const Icon(Icons.smart_toy_outlined, size: 16),
            label: Text(
              '${route?.modelId ?? ''} · ${context.l10n.botsManagedModel}',
            ),
            onPressed: () =>
                unawaited(BotDetailsRoute(botId: botId).push(context)),
          )
        else
          ...modelRouteSelectorChildren(
            accounts: view.accounts,
            accountId: route?.accountId,
            modelId: route?.modelId,
            effort: route?.effort,
            enabled: view.settingsLoaded,
            pending: view.routePending,
            available: route?.available ?? false,
            routeUnavailableReason: route?.unavailableReason,
            unavailableReason:
                view.routeFailure ??
                context.l10n.statusModelRouteUnavailableFallback,
            blockedReason: blockedReason,
            onExplain: (message) => setState(() => _notice = message),
            onModelSelected: actions.setModel,
            onEffortSelected: actions.setEffort,
          ),
      ],
    );
  }

  Widget _interaction(
    String threadId,
    PendingInteraction interaction,
    InteractionStopViewState stop,
  ) {
    final plan = interaction.planConfirmation;
    final payload = InteractionPayloadSnapshot.from(interaction);
    final content = plan != null
        ? PlanConfirmationConnector(
            threadId: threadId,
            plan: plan,
            enabled: true,
          )
        : switch (interaction.kind) {
            InteractionKind.toolApproval => ToolApprovalConnector(
              threadId: threadId,
              interactionId: interaction.id,
              expectedRevision: interaction.revision,
              payload: payload,
              enabled: true,
            ),
            InteractionKind.userInput => UserInputConnector(
              threadId: threadId,
              interactionId: interaction.id,
              expectedRevision: interaction.revision,
              payload: payload,
              enabled: true,
            ),
          };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        InteractionStopView(
          state: stop,
          onStop: stop.executionId == null
              ? null
              : () => widget.actions.stop(stop.executionId!),
        ),
      ],
    );
  }
}
