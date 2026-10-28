import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../../shared/studio_panel.dart';
import '../../interactions/widgets/interaction_widgets.dart';
import '../state/composer_view_state.dart';

/// The interaction dock owns one visible outlet for its SDK stop command.
class InteractionStopView extends StatelessWidget {
  const InteractionStopView({
    required this.state,
    required this.onStop,
    super.key,
  });

  final InteractionStopViewState state;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final failure = state.failure;
    if (state.executionId == null && failure == null) {
      return const SizedBox.shrink();
    }
    final failureText = failure == null
        ? null
        : failure.reason != null || failure.message.trim().isEmpty
        ? context.composerFailureReasonLabel(failure.reason)
        : failure.message;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.executionId != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (state.stopping)
                Text(
                  context.l10n.composerStopping,
                  key: StudioDriverKeys.composerStopping,
                ),
              IconButton.filledTonal(
                key: StudioDriverKeys.composerStop,
                tooltip: state.stopping
                    ? context.l10n.composerStopping
                    : context.l10n.composerStop,
                onPressed: state.canStop ? onStop : null,
                icon: state.pending
                    ? const SizedBox.square(
                        key: StudioDriverKeys.composerPending,
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.stop),
              ),
            ],
          ),
        if (failureText != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              failureText,
              key: const ValueKey('interaction-stop-failure'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
      ],
    );
  }
}

class ComposerTargetDiagnosticView extends StatelessWidget {
  const ComposerTargetDiagnosticView({required this.diagnostic, super.key});

  final ComposerTargetDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 17,
                color: colors.error,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    diagnostic.message,
                    key: ValueKey(
                      'composer-target-diagnostic-${diagnostic.targetKey}',
                    ),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.error),
                  ),
                  if (diagnostic.cleanupFailureDraftIds.isNotEmpty)
                    Text(
                      'Cleanup failed draft IDs: '
                      '${diagnostic.cleanupFailureDraftIds.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.error),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 子会话详情的只读说明。
///
/// 用户对子智能体的运行控制只有列表行内的停止；详情只展示历史、进展、模型、工作区与
/// 待决状态，等待主智能体调度（design/19 §19.6.1、design/25 §25.8）。
class AgentReadOnlyDockView extends StatelessWidget {
  const AgentReadOnlyDockView({required this.view, super.key});

  final ComposerDockViewState view;

  @override
  Widget build(BuildContext context) {
    final thread = view.thread;
    final secondaryStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: context.colors.onSurfaceVariant);
    final route = view.displayRoute;
    final execution = view.execution;
    final pending = view.activeInteraction;
    final continuation = view.continuation;
    // 只有在 canonical 确实等待调度（有未认领继续点且没有当前执行）时才说明；
    // 执行中的成员不能同时显示「正在运行」和「等待调度」。
    final waitingForScheduling =
        execution == null && continuation != null && !continuation.claimed;
    return StudioPanel(
      key: StudioDriverKeys.agentReadOnlyPanel,
      backgroundColor: context.colors.surfaceContainer,
      borderColor: context.colors.outlineVariant,
      radius: StudioRadii.lg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 18,
                color: context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  context.l10n.composerAgentReadOnlyTitle,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (waitingForScheduling)
            Text(
              context.l10n.composerAgentReadOnlyWaiting,
              key: const ValueKey('agent-readonly-waiting'),
              style: secondaryStyle,
            ),
          Text(
            context.l10n.composerAgentReadOnlyScope,
            key: const ValueKey('agent-readonly-scope'),
            style: secondaryStyle,
          ),
          if (pending != null)
            Text(
              context.l10n.composerAgentReadOnlyPending,
              key: const ValueKey('agent-readonly-pending'),
              style: secondaryStyle,
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              InfoChip(
                icon: Icons.timeline_outlined,
                label: context.threadStatusLabel(thread!.status),
              ),
              if (execution != null)
                InfoChip(
                  icon: Icons.bolt_outlined,
                  label: context.threadStatusLabel(
                    execution.phase == AgentExecutionPhase.stopping
                        ? ThreadStatusView.cancelling
                        : ThreadStatusView.running,
                  ),
                ),
              if (route != null)
                InfoChip(icon: Icons.memory_outlined, label: route.modelId),
              if (thread.workspacePath.trim().isNotEmpty)
                InfoChip(
                  icon: Icons.folder_outlined,
                  label: thread.workspacePath,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
