import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/layout/studio_panel.dart';
import 'interaction_dock_shell.dart';

/// Read-only child facts. Source validation, route reads and label formatting
/// belong to the connector; this surface has no business action or resource.
class AgentReadOnlyPanel extends StatelessWidget {
  const AgentReadOnlyPanel({
    required this.waitingForScheduling,
    required this.pendingInteraction,
    required this.statusLabel,
    required this.modelLabel,
    this.executionLabel,
    this.effortLabel,
    this.workspacePath,
    this.retiredPlanner = false,
    super.key,
  });

  final bool waitingForScheduling;
  final bool pendingInteraction;
  final String statusLabel;
  final String? executionLabel;
  final String modelLabel;
  final String? effortLabel;
  final String? workspacePath;
  final bool retiredPlanner;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final secondaryStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.onSurfaceVariant);
    final panel = StudioPanel(
      key: StudioDriverKeys.agentReadOnlyPanel,
      backgroundColor: colors.surfaceContainer,
      borderColor: colors.outlineVariant,
      radius: StudioRadii.lg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  context.l10n.composerAgentReadOnlyTitle,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
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
          if (pendingInteraction)
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
                key: const ValueKey('agent-readonly-status'),
                icon: Icons.timeline_outlined,
                label: statusLabel,
              ),
              if (executionLabel != null)
                InfoChip(
                  key: const ValueKey('agent-readonly-execution'),
                  icon: Icons.bolt_outlined,
                  label: executionLabel!,
                ),
              InfoChip(
                key: const ValueKey('agent-readonly-model'),
                icon: Icons.memory_outlined,
                label: modelLabel,
              ),
              if (effortLabel != null)
                InfoChip(
                  key: const ValueKey('agent-readonly-effort'),
                  icon: Icons.psychology_alt_outlined,
                  label: effortLabel!,
                ),
              if (workspacePath != null)
                InfoChip(
                  key: const ValueKey('agent-readonly-workspace'),
                  icon: Icons.folder_outlined,
                  label: workspacePath!,
                ),
            ],
          ),
        ],
      ),
    );
    if (!retiredPlanner) return panel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.agentRoleRetired,
          key: const ValueKey('retired-planner-input-notice')),
        panel,
      ],
    );
  }
}
