import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/recovery.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/feedback/studio_messages.dart';
import '../../../../ui/selectors/effort_selector.dart';
import '../../../../ui/selectors/model_route_selector.dart';
import '../../widgets/settings_feedback.dart';
import '../../accounts/widgets/auto_page_loader.dart';
import '../../widgets/settings_form_layout.dart';
import '../../widgets/settings_resource_row.dart';
import '../../widgets/settings_layout.dart';
import '../state/agent_profiles_state.dart';
import '../widgets/agent_workspace_label.dart';
import '../widgets/worktree_recovery_view.dart';

class AgentProfilesView extends StatelessWidget {
  const AgentProfilesView({
    required this.state,
    required this.profiles,
    required this.roleOptions,
    required this.routeLabels,
    required this.roleReadErrors,
    required this.errors,
    required this.profileErrors,
    required this.worktrees,
    required this.worktreeErrors,
    required this.checkingRecovery,
    required this.recoveryError,
    required this.hasMore,
    required this.onQuery,
    required this.onAdd,
    required this.onEdit,
    required this.onEnabled,
    required this.onModel,
    required this.onEffort,
    required this.onMore,
    required this.onRetry,
    required this.onCleanup,
    required this.onRetryRecovery,
    super.key,
  });
  final AgentProfilesViewState state;
  final List<AgentProfileSummary> profiles;
  final Map<String, List<ModelSelectionOption>> roleOptions;
  final Map<String, String> routeLabels;
  final Map<String, String> roleReadErrors;
  final List<String> errors;
  final Map<String, List<String>> profileErrors;
  final List<WorktreeRecoveryPreview> worktrees;
  final Map<(WorktreeOwner, String, int), List<String>> worktreeErrors;
  final bool checkingRecovery;
  final String? recoveryError;
  final bool hasMore;
  final ValueChanged<String> onQuery;
  final VoidCallback onAdd;
  final ValueChanged<String> onEdit;
  final void Function(String id, bool enabled) onEnabled;
  final void Function(String role, ModelSelectionOption option) onModel;
  final void Function(String role, String? effort) onEffort;
  final VoidCallback onMore;
  final VoidCallback onRetry;
  final ValueChanged<WorktreeRecoveryPreview> onCleanup;
  final VoidCallback? onRetryRecovery;

  @override
  Widget build(BuildContext context) => AutoPageLoader(
    hasMore: hasMore,
    loading: state.reading.contains(AgentProfilesReadField.profiles),
    blocked: state.readIssues.containsKey(AgentProfilesReadField.profiles),
    requestedCount: profiles.length,
    onLoadMore: onMore,
    child: SettingsPageLayout(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsHeader(
            title: context.l10n.settingsAgentsTitle,
            subtitle: context.l10n.settingsAgentsSubtitle,
            trailing: FilledButton.icon(
              key: const ValueKey('agent-profile-add'),
              onPressed: state.editor == null ? onAdd : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.l10n.settingsAgentsAddUserProfile),
            ),
          ),
          if (errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsInlineError(message: errors.join('\n')),
                  TextButton(
                    onPressed: onRetry,
                    child: Text(context.l10n.runtimeFatalRetry),
                  ),
                ],
              ),
            ),
        ],
      ),
      toolbar: SettingsSearchField(
        hintText: context.l10n.settingsFilterAgents,
        onChanged: onQuery,
      ),
      child: ListView(
        key: const ValueKey('settings-pane-scroll'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (checkingRecovery || recoveryError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  if (checkingRecovery) ...[
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(context.l10n.recoveryChecking)),
                  ] else ...[
                    Expanded(
                      child: StudioInlineMessage(
                        key: const ValueKey('recovery-check-status'),
                        icon: Icons.error_outline,
                        message:
                            '${context.l10n.recoveryCheckFailed}\n$recoveryError',
                        color: context.colors.error,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('recovery-check-retry'),
                      onPressed: onRetryRecovery,
                      child: Text(context.l10n.runtimeFatalRetry),
                    ),
                  ],
                ],
              ),
            ),
          if (state.editor != null) const SizedBox(height: 8),
          if (worktrees.isNotEmpty)
            SettingsSectionPanel(
              title: context.l10n.settingsAgentsRecoveryTitle,
              children: [
                for (final worktree in worktrees)
                  WorktreeRecoveryView(
                    worktree: worktree,
                    action:
                        state.cleanupActions[(
                          worktree.ownerKind,
                          worktree.ownerThreadId,
                          worktree.leaseRevision,
                        )],
                    errors:
                        worktreeErrors[(
                          worktree.ownerKind,
                          worktree.ownerThreadId,
                          worktree.leaseRevision,
                        )] ??
                        [],
                    onCleanup: () => onCleanup(worktree),
                  ),
              ],
            ),
          for (final system in [true, false])
            SettingsSectionPanel(
              title: system
                  ? context.l10n.settingsSystemAgentsGroup
                  : context.l10n.settingsUserAgentsGroup,
              children: [
                for (final profile in profiles.where(
                  (profile) => profile.system == system,
                ))
                  _AgentProfileRow(
                    key: ValueKey('agent-profile-card-${profile.profileId}'),
                    system: system,
                    profile: profile,
                    enabled: profile.enabled,
                    enabledPending:
                        state
                            .actions[(
                              profile.profileId,
                              AgentProfileAction.enabled,
                            )]
                            ?.preventsResubmission ==
                        true,
                    editEnabled: state.editor == null,
                    errors: profileErrors[profile.profileId] ?? const [],
                    onEnabled: (value) => onEnabled(profile.profileId, value),
                    onEdit: () => onEdit(profile.profileId),
                    route: system ? _role(context, profile.profileId) : null,
                  ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _role(BuildContext context, String role) {
    final route = state.routes[role];
    final pending = [AgentProfileAction.model, AgentProfileAction.effort].any(
      (action) => state.actions[(role, action)]?.preventsResubmission ?? false,
    );
    if (route == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.roleReads[role]?.pending == true)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 8),
                Text(context.l10n.resourceSourceLoading),
              ],
            )
          else
            Text(context.l10n.resourceSourceUninitialized),
          if (roleReadErrors[role] case final error?) ...[
            SelectableText(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (state.roleReads[role]?.target != null &&
                state.roleReads[role]?.pending == false)
              TextButton(
                onPressed: onRetry,
                child: Text(context.l10n.runtimeFatalRetry),
              ),
          ],
        ],
      );
    }
    final options = roleOptions[role] ?? const <ModelSelectionOption>[];
    final efforts = route.descriptor?.reasoning?.candidates ?? const <String>[];
    final modelSelector = ModelRouteSelector(
      selectorKey: StudioDriverKeys.settingsRoleModel(role),
      fieldLabel: context.l10n.settingsModelField,
      options: options,
      accountId: route.accountId,
      modelId: route.modelId,
      unresolvedLabel: routeLabels[role],
      enabled: options.isNotEmpty && !pending,
      onSelected: (option) => onModel(role, option),
      optionKeyBuilder: (option) => StudioDriverKeys.settingsRoleModelOption(
        role,
        option.accountId,
        option.modelId,
      ),
    );
    final effortSelector = KeyedSubtree(
      key: StudioDriverKeys.settingsRoleEffort(role),
      child: EffortSelector(
        efforts: efforts,
        selected: route.effort,
        enabled: efforts.isNotEmpty && !pending,
        allowDefault: false,
        pending: pending,
        onSelected: (value) => onEffort(role, value),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        if (constraints.maxWidth < textScaler.scale(760)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: modelSelector),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: effortSelector),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: modelSelector,
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: textScaler.scale(180)),
              child: effortSelector,
            ),
          ],
        );
      },
    );
  }
}

/// Agent row: identity, workspace-mode status and the switch/edit action, with
/// the role route panel (system profiles) and a 24-high divider underneath.
class _AgentProfileRow extends StatelessWidget {
  const _AgentProfileRow({
    required this.system,
    required this.profile,
    required this.enabled,
    required this.enabledPending,
    required this.editEnabled,
    required this.errors,
    required this.onEnabled,
    required this.onEdit,
    this.route,
    super.key,
  });
  final bool system;
  final AgentProfileSummary profile;
  final bool enabled;
  final bool enabledPending;
  final bool editEnabled;
  final List<String> errors;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onEdit;
  final Widget? route;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        '${profile.profileId} · '
        '${system ? context.roleDescription(profile.profileId) : profile.description}';
    return SettingsResourceRow(
      icon: system ? Icons.lock_outline : Icons.person_outline,
      title: system
          ? context.roleLabel(profile.profileId)
          : profile.displayName,
      subtitle: subtitle,
      status: Text(
        agentWorkspaceLabel(context, profile.workspaceMode),
        key: system
            ? ValueKey('system-agent-workspace-${profile.profileId}')
            : null,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      actions: [
        if (system)
          Switch(
            key: ValueKey('system-agent-enabled-${profile.profileId}'),
            value: enabled,
            onChanged: enabledPending ? null : onEnabled,
          )
        else
          TextButton.icon(
            key: ValueKey('agent-profile-edit-${profile.profileId}'),
            onPressed: editEnabled ? onEdit : null,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text(context.l10n.settingsAgentsEditTooltip),
          ),
      ],
      children: [
        if (errors.isNotEmpty) ...[
          for (final error in errors)
            SelectableText(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
        ],
        if (route != null) ...[route!, const SizedBox(height: 12)],
        const Divider(height: 24),
      ],
    );
  }
}
