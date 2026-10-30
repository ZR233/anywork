import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/delegation_labels.dart';
import '../../../../shared/studio_driver_keys.dart';

class SessionSettingsView extends StatelessWidget {
  const SessionSettingsView({
    required this.summary,
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

  final String summary;
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
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 400.0);
    final height = (MediaQuery.sizeOf(context).height - 96).clamp(0.0, 520.0);
    final submenuStyle = MenuStyle(
      minimumSize: WidgetStatePropertyAll(Size(width, 0)),
      maximumSize: WidgetStatePropertyAll(Size(width, height)),
    );
    Widget label(String text) => SizedBox(
      width: (width - 88).clamp(0.0, width),
      child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
    );
    final effectiveMode = modeOverride ?? defaultMode;
    return MenuAnchor(
      crossAxisUnconstrained: false,
      style: submenuStyle,
      menuChildren: [
        MenuItemButton(onPressed: null, child: label(summary)),
        SubmenuButton(
          key: StudioDriverKeys.draftDelegationMode,
          menuStyle: submenuStyle,
          menuChildren: [
            for (final mode in <DelegationMode?>[
              null,
              ...DelegationMode.values,
            ])
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
          ],
          child: Text(context.l10n.delegationModeLabel),
        ),
        SubmenuButton(
          key: StudioDriverKeys.draftDelegationPreference,
          menuStyle: submenuStyle,
          menuChildren: [
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
                onPressed: !enabled || effectiveMode != DelegationMode.automatic
                    ? null
                    : () => onPreferenceChanged(preference),
                child: label(
                  preference == null
                      ? '${context.l10n.delegationFollowDefault} · ${context.delegationPreferenceLabel(defaultPreference)}'
                      : context.delegationPreferenceLabel(preference),
                ),
              ),
          ],
          child: Text(context.l10n.delegationPreferenceLabel),
        ),
        if (effectiveMode == DelegationMode.profile)
          MenuItemButton(
            onPressed: null,
            child: label(context.l10n.delegationOnlyAutomatic),
          ),
        if (!isStandalone)
          SubmenuButton(
            key: StudioDriverKeys.sessionWorkspaceMode,
            menuStyle: submenuStyle,
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
                  ),
                ),
            ],
            child: Text(context.l10n.composerWorkspaceModeLabel),
          ),
      ],
      builder: (context, controller, child) => IconButton(
        key: StudioDriverKeys.sessionSettings,
        tooltip: '${context.l10n.delegationSessionSettings} · $summary',
        onPressed: !enabled
            ? null
            : controller.isOpen
            ? controller.close
            : controller.open,
        icon: const Icon(Icons.tune, size: 20),
      ),
    );
  }
}
