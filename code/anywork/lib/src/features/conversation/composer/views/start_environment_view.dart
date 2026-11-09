import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/delegation_labels.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../../shared/studio_menu_label.dart';

/// 创建期环境控制的呈现；草稿和导航仍由各自的 Client owner 持有。
class StartEnvironmentView extends StatelessWidget {
  const StartEnvironmentView({
    required this.projectSelector,
    required this.defaultMode,
    required this.defaultPreference,
    required this.modeOverride,
    required this.preferenceOverride,
    required this.workspaceMode,
    required this.isStandalone,
    required this.enabled,
    required this.onModeChanged,
    required this.onPreferenceChanged,
    required this.onWorkspaceModeChanged,
    super.key,
  });

  final Widget projectSelector;
  final DelegationMode defaultMode;
  final DelegationPreference defaultPreference;
  final DelegationMode? modeOverride;
  final DelegationPreference? preferenceOverride;
  final ThreadWorkspaceMode workspaceMode;
  final bool isStandalone;
  final bool enabled;
  final ValueChanged<DelegationMode?> onModeChanged;
  final ValueChanged<DelegationPreference?> onPreferenceChanged;
  final ValueChanged<ThreadWorkspaceMode> onWorkspaceModeChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveMode = modeOverride ?? defaultMode;
    final effectivePreference = preferenceOverride ?? defaultPreference;
    final summary = effectiveMode == DelegationMode.profile
        ? context.delegationModeLabel(effectiveMode)
        : '${context.delegationModeLabel(effectiveMode)} · ${context.delegationPreferenceLabel(effectivePreference)}';
    final menuWidth = (MediaQuery.sizeOf(context).width - 40).clamp(
      180.0,
      360.0,
    );
    Widget label(String text, [String? hint]) => SizedBox(
      width: menuWidth - 64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (hint != null)
            Text(hint, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
    final workspaceSelector = isStandalone
        ? Tooltip(
            message: context.l10n.composerWorkspaceModeLocal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                context.l10n.composerFixedLocalDirectory,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          )
        : MenuAnchor(
            menuChildren: [
              for (final mode in ThreadWorkspaceMode.values)
                MenuItemButton(
                  key: StudioDriverKeys.sessionWorkspaceModeOption(mode.id),
                  leadingIcon: Icon(workspaceMode == mode ? Icons.check : null),
                  onPressed: enabled
                      ? () => onWorkspaceModeChanged(mode)
                      : null,
                  child: label(
                    mode == ThreadWorkspaceMode.worktree
                        ? context.l10n.composerWorkspaceModeWorktree
                        : context.l10n.composerWorkspaceModeLocal,
                    mode == ThreadWorkspaceMode.worktree
                        ? context.l10n.composerWorktreeHint
                        : context.l10n.composerLocalDirectoryHint,
                  ),
                ),
            ],
            builder: (context, controller, child) => _EnvironmentTrigger(
              key: StudioDriverKeys.sessionWorkspaceMode,
              enabled: enabled,
              label: workspaceMode == ThreadWorkspaceMode.worktree
                  ? context.l10n.composerWorkspaceModeWorktree
                  : context.l10n.composerWorkspaceModeLocal,
              onPressed: controller.isOpen ? controller.close : controller.open,
            ),
          );
    final delegationSelector = MenuAnchor(
      crossAxisUnconstrained: false,
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(
          Size(
            menuWidth,
            (MediaQuery.sizeOf(context).height - 48).clamp(160.0, 600.0),
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          key: StudioDriverKeys.draftDelegationMode,
          child: label(context.l10n.delegationModeLabel),
        ),
        for (final mode in <DelegationMode?>[null, ...DelegationMode.values])
          MenuItemButton(
            key: StudioDriverKeys.delegationModeOption('draft', mode),
            leadingIcon: Icon(modeOverride == mode ? Icons.check : null),
            onPressed: enabled ? () => onModeChanged(mode) : null,
            child: label(
              mode == null
                  ? '${context.l10n.delegationFollowDefault} · ${context.delegationModeLabel(defaultMode)}'
                  : context.delegationModeLabel(mode),
            ),
          ),
        const Divider(),
        MenuItemButton(
          key: StudioDriverKeys.draftDelegationPreference,
          child: label(
            context.l10n.delegationPreferenceLabel,
            effectiveMode == DelegationMode.profile
                ? context.l10n.delegationOnlyAutomatic
                : null,
          ),
        ),
        for (final preference in <DelegationPreference?>[
          null,
          ...DelegationPreference.values,
        ])
          MenuItemButton(
            key: StudioDriverKeys.delegationPreferenceOption(
              'draft',
              preference,
            ),
            leadingIcon: Icon(
              preferenceOverride == preference ? Icons.check : null,
            ),
            onPressed: enabled && effectiveMode == DelegationMode.automatic
                ? () => onPreferenceChanged(preference)
                : null,
            child: label(
              preference == null
                  ? '${context.l10n.delegationFollowDefault} · ${context.delegationPreferenceLabel(defaultPreference)}'
                  : context.delegationPreferenceLabel(preference),
              preference == null
                  ? null
                  : context.delegationPreferenceHint(preference),
            ),
          ),
      ],
      builder: (context, controller, child) => _EnvironmentTrigger(
        key: StudioDriverKeys.sessionSettings,
        enabled: enabled,
        label: summary,
        onPressed: controller.isOpen ? controller.close : controller.open,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final left = Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [projectSelector, workspaceSelector],
          );
          if (constraints.maxWidth < 600 ||
              MediaQuery.textScalerOf(context).scale(14) > 18) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                Align(
                  alignment: Alignment.centerRight,
                  child: delegationSelector,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: left),
              delegationSelector,
            ],
          );
        },
      ),
    );
  }
}

class _EnvironmentTrigger extends StatelessWidget {
  const _EnvironmentTrigger({
    required this.label,
    required this.enabled,
    required this.onPressed,
    super.key,
  });
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: enabled ? label : context.l10n.composerEnvironmentLocked,
    child: TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: StudioMenuLabel(label: label, enabled: enabled, maxWidth: 160),
    ),
  );
}
