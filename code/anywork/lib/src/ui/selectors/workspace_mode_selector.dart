import 'package:anywork_client/workspace.dart' show ThreadWorkspaceMode;
import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';
import '../menus/quiet_selector_menu.dart';
import '../menus/studio_menu_label.dart';

/// New-conversation draft choice only; does not infer Git or remote readiness.
class WorkspaceModeSelector extends StatelessWidget {
  const WorkspaceModeSelector({
    required this.mode,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final ThreadWorkspaceMode mode;
  final ValueChanged<ThreadWorkspaceMode> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return QuietSelectorMenu<ThreadWorkspaceMode>(
      key: const ValueKey<String>('session-workspace-mode-selector'),
      tooltip: l10n.composerWorkspaceModeLabel,
      enabled: enabled,
      onSelected: onSelected,
      items: [
        QuietSelectorMenuItem<ThreadWorkspaceMode>(
          value: ThreadWorkspaceMode.local,
          selected: mode == ThreadWorkspaceMode.local,
          itemKey: const ValueKey<String>('session-workspace-mode-local'),
          child: _WorkspaceModeItem(
            icon: Icons.folder_outlined,
            label: l10n.composerWorkspaceModeLocal,
          ),
        ),
        QuietSelectorMenuItem<ThreadWorkspaceMode>(
          value: ThreadWorkspaceMode.worktree,
          selected: mode == ThreadWorkspaceMode.worktree,
          itemKey: const ValueKey<String>('session-workspace-mode-worktree'),
          child: _WorkspaceModeItem(
            icon: Icons.account_tree_outlined,
            label: l10n.composerWorkspaceModeWorktree,
          ),
        ),
      ],
      child: StudioMenuLabel(
        label: mode == ThreadWorkspaceMode.worktree
            ? l10n.composerWorkspaceModeWorktree
            : l10n.composerWorkspaceModeLocal,
        enabled: enabled,
        maxWidth: 96,
      ),
    );
  }
}

class _WorkspaceModeItem extends StatelessWidget {
  const _WorkspaceModeItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
