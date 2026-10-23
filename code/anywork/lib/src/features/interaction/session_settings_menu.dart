import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/settings_store.dart';
import '../../presentation/providers/start_session_controller.dart';
import '../../shared/delegation_labels.dart';
import '../../shared/studio_driver_keys.dart';

/// Project-scoped draft choices; workspace admission remains Runtime-owned for
/// both local and SSH projects, including non-Git and unavailable workspaces.
class SessionSettingsMenu extends ConsumerStatefulWidget {
  const SessionSettingsMenu({
    super.key,
    required this.projectId,
    required this.enabled,
  });
  final String projectId;
  final bool enabled;
  @override
  ConsumerState<SessionSettingsMenu> createState() =>
      _SessionSettingsMenuState();
}

class _SessionSettingsMenuState extends ConsumerState<SessionSettingsMenu> {
  final FocusNode _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(startSessionControllerProvider);
    final project = state.forProject(widget.projectId);
    final defaults = ref.watch(settingsStoreProvider).canonical?.delegation;
    if (defaults == null) return const SizedBox.shrink();
    final effective = project.resolveDelegation(defaults);
    final summary = context.delegationSummary(effective);
    final owner = ref.read(anyworkClientProvider).startDraft;
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 400.0);
    final height = (MediaQuery.sizeOf(context).height - 96).clamp(0.0, 520.0);
    final enabled = widget.enabled && !state.submitting;
    final submenuStyle = MenuStyle(
      minimumSize: WidgetStatePropertyAll(Size(width, 0)),
      maximumSize: WidgetStatePropertyAll(Size(width, height)),
    );
    // SubmenuButton uses its own natural-size panel. Bound each leaf's content
    // as well as the panel; maximumSize alone does not constrain intrinsic text.
    Widget label(String text) => SizedBox(
      width: (width - 88).clamp(0.0, width),
      child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
    );
    return MenuAnchor(
      childFocusNode: _focus,
      crossAxisUnconstrained: false,
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(width, 0)),
        maximumSize: WidgetStatePropertyAll(Size(width, height)),
      ),
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
                leadingIcon: Icon(
                  project.delegationModeOverride == mode ? Icons.check : null,
                ),
                onPressed: !enabled
                    ? null
                    : () => owner.setDelegationModeOverride(
                        widget.projectId,
                        mode,
                      ),
                child: label(
                  mode == null
                      ? '${context.l10n.delegationFollowDefault} · ${context.delegationModeLabel(defaults.mode)}'
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
                  project.delegationPreferenceOverride == preference
                      ? Icons.check
                      : null,
                ),
                onPressed:
                    !enabled || effective.mode != DelegationMode.automatic
                    ? null
                    : () => owner.setDelegationPreferenceOverride(
                        widget.projectId,
                        preference,
                      ),
                child: label(
                  preference == null
                      ? '${context.l10n.delegationFollowDefault} · ${context.delegationPreferenceLabel(defaults.preference)}'
                      : context.delegationPreferenceLabel(preference),
                ),
              ),
          ],
          child: Text(context.l10n.delegationPreferenceLabel),
        ),
        if (effective.mode == DelegationMode.profile)
          MenuItemButton(
            onPressed: null,
            child: label(context.l10n.delegationOnlyAutomatic),
          ),
        SubmenuButton(
          key: StudioDriverKeys.sessionWorkspaceMode,
          menuStyle: submenuStyle,
          menuChildren: [
            for (final mode in ThreadWorkspaceMode.values)
              MenuItemButton(
                key: StudioDriverKeys.sessionWorkspaceModeOption(mode.id),
                leadingIcon: Icon(
                  project.workspaceMode == mode ? Icons.check : null,
                ),
                onPressed: !enabled
                    ? null
                    : () => owner.setWorkspaceMode(widget.projectId, mode),
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
        focusNode: _focus,
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
