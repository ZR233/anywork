import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_key_values.dart';
import '../../shared/studio_driver_keys.dart';

/// Presents the Client's frozen submission; expansion is the only local state.
class ThreadPreparationCard extends StatelessWidget {
  const ThreadPreparationCard({
    required this.project,
    required this.preparation,
    super.key,
  });

  final StudioProject project;
  final NewThreadPreparation preparation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final phase = preparation.phase;
    final running = phase == NewThreadPreparationPhase.preparing;
    final unknown = phase == NewThreadPreparationPhase.unknownOutcome;
    final stage = preparation.progress?.stage;
    final currentStep = stage?.step ?? 0;
    final terminalColor = unknown
        ? context.statusColors.warning
        : context.colors.error;
    final failure = preparation.failure;
    final workspacePath = preparation.progress?.workspacePath;
    final branch = preparation.progress?.branch;
    final stages = [
      l10n.preparationCheckProject,
      l10n.preparationWorkspace,
      l10n.preparationInitializeSession,
      l10n.preparationSubmitPrompt,
    ];
    final title = running
        ? l10n.preparationTitle
        : unknown
        ? l10n.preparationUnknownTitle
        : l10n.preparationFailedTitle;

    return Container(
      key: StudioDriverKeys.threadPreparation,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(StudioRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (running)
            TickerMode(
              enabled: !MediaQuery.disableAnimationsOf(context),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: context.statusColors.activeIndicator,
                backgroundColor: context.colors.surfaceContainerLow,
                semanticsLabel: title,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(StudioRadii.sm),
                      ),
                      child: Icon(
                        running
                            ? Icons.folder_open_outlined
                            : unknown
                            ? Icons.help_outline
                            : Icons.error_outline,
                        color: running ? context.colors.primary : terminalColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              title,
                              style: context.text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            running
                                ? l10n.preparationSubtitle
                                : unknown
                                ? l10n.preparationUnknownBody
                                : l10n.preparationRetainedBody,
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                for (var index = 0; index < stages.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == stages.length - 1 ? 0 : 14,
                    ),
                    child: _PreparationStep(
                      title: stages[index],
                      complete: index < currentStep,
                      current: index == currentStep,
                      phase: phase,
                      detail: index == currentStep
                          ? stage == null
                                ? l10n.preparationWaiting
                                : _stageLabel(context, stage)
                          : null,
                      stage: index == currentStep ? stage : null,
                    ),
                  ),
                if (failure != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: unknown
                          ? context.statusColors.warningContainer
                          : context.colors.errorContainer,
                      borderRadius: BorderRadius.circular(StudioRadii.sm),
                    ),
                    child: SelectableText(
                      failure is StudioFailure
                          ? failure.message
                          : failure.toString(),
                      style: context.text.bodySmall?.copyWith(
                        color: terminalColor,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.outlineVariant),
          ExpansionTile(
            key: StudioDriverKeys.threadPreparationDetails,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 2,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              l10n.preparationMoreDetails,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            children: [
              _PreparationDetail(
                label: l10n.preparationProjectLabel,
                value: project.name,
              ),
              _PreparationDetail(
                label: l10n.composerWorkspaceModeLabel,
                value: preparation.workspaceMode == ThreadWorkspaceMode.worktree
                    ? l10n.composerWorkspaceModeWorktree
                    : l10n.composerWorkspaceModeLocal,
              ),
              if (project.sshAlias case final alias?)
                _PreparationDetail(
                  label: l10n.preparationRemoteLabel,
                  value: alias,
                ),
              if (workspacePath != null)
                _PreparationDetail(
                  label: l10n.preparationPathLabel,
                  value: workspacePath,
                  technicalValue: true,
                ),
              if (branch != null)
                _PreparationDetail(
                  label: l10n.preparationBranchLabel,
                  value: branch,
                  technicalValue: true,
                ),
              if (failure is StudioFailure)
                _PreparationDetail(
                  label: l10n.preparationDiagnosticLabel,
                  value: failure.correlationId,
                  technicalValue: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _stageLabel(BuildContext context, ThreadPreparationStage stage) =>
      switch (stage) {
        ThreadPreparationStage.checkingProject =>
          context.l10n.preparationCheckingProject,
        ThreadPreparationStage.preparingWorkspace =>
          context.l10n.preparationPreparingWorkspace,
        ThreadPreparationStage.resolvingRepository =>
          context.l10n.preparationResolvingRepository,
        ThreadPreparationStage.creatingWorktree =>
          context.l10n.preparationCreatingWorktree,
        ThreadPreparationStage.initializingSession =>
          context.l10n.preparationInitializingSession,
        ThreadPreparationStage.submittingPrompt =>
          context.l10n.preparationSubmittingPrompt,
      };
}

class _PreparationStep extends StatelessWidget {
  const _PreparationStep({
    required this.title,
    required this.complete,
    required this.current,
    required this.phase,
    this.detail,
    this.stage,
  });
  final String title;
  final bool complete;
  final bool current;
  final NewThreadPreparationPhase phase;
  final String? detail;
  final ThreadPreparationStage? stage;

  @override
  Widget build(BuildContext context) {
    final running = phase == NewThreadPreparationPhase.preparing;
    final unknown = phase == NewThreadPreparationPhase.unknownOutcome;
    final color = complete
        ? context.statusColors.success
        : current
        ? running
              ? context.statusColors.activeIndicator
              : unknown
              ? context.statusColors.warning
              : context.colors.error
        : context.colors.outline;
    final status = complete
        ? context.l10n.preparationStepComplete
        : !current
        ? context.l10n.preparationStepPending
        : running
        ? context.l10n.preparationStepRunning
        : unknown
        ? context.l10n.preparationUnknownTitle
        : context.l10n.preparationStepFailed;
    return Semantics(
      label: '$title, $status',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: current && running
                ? TickerMode(
                    enabled: !MediaQuery.disableAnimationsOf(context),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: color,
                        semanticsLabel: status,
                      ),
                    ),
                  )
                : Icon(
                    complete
                        ? Icons.check_circle_outline
                        : current
                        ? Icons.error_outline
                        : Icons.radio_button_unchecked,
                    size: 19,
                    color: color,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.text.bodyMedium?.copyWith(
                    color: current || complete
                        ? context.colors.onSurface
                        : context.colors.onSurfaceVariant,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (current && detail != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    detail!,
                    key: stage == null
                        ? null
                        : ValueKey(
                            StudioDriverKeyValues.threadPreparationStage(
                              stage!,
                            ),
                          ),
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreparationDetail extends StatelessWidget {
  const _PreparationDetail({
    required this.label,
    required this.value,
    this.technicalValue = false,
  });
  final String label;
  final String value;
  final bool technicalValue;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: context.text.bodySmall?.copyWith(
              height: 1.5,
              fontFamily: technicalValue ? studioCodeFontFamily : null,
            ),
          ),
        ],
      ),
    ),
  );
}
