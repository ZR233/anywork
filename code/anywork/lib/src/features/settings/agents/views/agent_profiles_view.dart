import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/recovery.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/selectors/effort_selector.dart';
import '../../../../ui/selectors/model_route_selector.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_pane.dart';
import '../../widgets/settings_source_status_view.dart';
import '../state/agent_profiles_state.dart';
import '../widgets/agent_workspace_label.dart';
import '../widgets/worktree_recovery_view.dart';

class AgentProfilesView extends StatelessWidget {
  const AgentProfilesView({required this.state, required this.profiles, required this.roleOptions,
    required this.routeLabels, required this.roleReadErrors, required this.errors, required this.profileErrors,
    required this.diagnostics, required this.worktrees, required this.worktreeErrors,
    required this.checkingRecovery, required this.recoveryError, required this.hasMore,
    required this.onQuery, required this.onAdd, required this.onEdit, required this.onEnabled,
    required this.onModel, required this.onEffort, required this.onMore, required this.onRetry,
    required this.onCleanup, required this.onRetryRecovery, super.key});
  final AgentProfilesViewState state;
  final List<AgentProfileSummary> profiles;
  final Map<String, List<ModelSelectionOption>> roleOptions;
  final Map<String, String> routeLabels;
  final Map<String, String> roleReadErrors;
  final List<String> errors;
  final Map<String, List<String>> profileErrors;
  final List<ProfileDiagnostic> diagnostics;
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
  Widget build(BuildContext context) => SettingsPane(title: context.l10n.settingsAgentsTitle,
    subtitle: context.l10n.settingsAgentsSubtitle,
    trailing: FilledButton.icon(key: const ValueKey('agent-profile-add'), onPressed: state.editor == null ? onAdd : null,
      icon: const Icon(Icons.add), label: Text(context.l10n.settingsAgentsAddUserProfile)),
    toolbar: SettingsFormField(value: state.query, label: context.l10n.settingsFilterAgents, onChanged: onQuery),
    child: ListView(key: const ValueKey('settings-pane-scroll'), children: [
      SettingsSourceStatusView(title: context.l10n.settingsAgentsTitle, brief: state.source.projection.header?.source.brief,
        read: state.source.sourceStatus, origin: state.source.projection.stamp?.origin,
        reference: state.source.projection.header?.source.status, onRetry: onRetry),
      SettingsSourceStatusView(title: context.l10n.settingsAccountTitle, brief: state.configurationSource.projection.header?.source.brief,
        read: state.configurationSource.sourceStatus, origin: state.configurationSource.projection.stamp?.origin,
        reference: state.configurationSource.projection.header?.source.status, onRetry: onRetry),
      SettingsSourceStatusView(title: context.l10n.settingsAccountModelsTitle, brief: state.modelSource.projection.header?.source.brief,
        read: state.modelSource.sourceStatus, origin: state.modelSource.projection.stamp?.origin,
        reference: state.modelSource.projection.header?.source.status, onRetry: onRetry),
      SettingsSourceStatusView(title: context.l10n.settingsAgentsRecoveryTitle, brief: state.recoverySource.projection.header?.source.brief,
        read: state.recoverySource.sourceStatus, origin: state.recoverySource.projection.stamp?.origin,
        reference: state.recoverySource.projection.header?.source.status, onRetry: onRetry),
      for (final error in errors) SelectableText(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (errors.isNotEmpty) TextButton(onPressed: onRetry, child: Text(context.l10n.runtimeFatalRetry)),
      if (checkingRecovery || recoveryError != null) Card.outlined(key: const ValueKey('recovery-check-status'),
        child: ListTile(leading: checkingRecovery ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.error_outline), title: Text(checkingRecovery ? context.l10n.recoveryChecking
            : '${context.l10n.recoveryCheckFailed}\n$recoveryError'),
          trailing: checkingRecovery ? null : TextButton(key: const ValueKey('recovery-check-retry'),
            onPressed: onRetryRecovery, child: Text(context.l10n.runtimeFatalRetry)))),
      if (worktrees.isNotEmpty) SettingsSection(title: context.l10n.settingsAgentsRecoveryTitle, children: [
        for (final worktree in worktrees) WorktreeRecoveryView(worktree: worktree,
          action: state.cleanupActions[(worktree.ownerKind, worktree.ownerThreadId, worktree.leaseRevision)],
          errors: worktreeErrors[(worktree.ownerKind, worktree.ownerThreadId, worktree.leaseRevision)] ?? [],
          onCleanup: () => onCleanup(worktree)),
      ]),
      for (final diagnostic in diagnostics) SelectableText('${diagnostic.path}: ${diagnostic.message}'),
      for (final system in [true, false]) SettingsSection(title: system ? context.l10n.settingsSystemAgentsGroup
        : context.l10n.settingsUserAgentsGroup, children: [
        for (final profile in profiles.where((profile) => profile.system == system)) Card.outlined(
          key: ValueKey('agent-profile-card-${profile.profileId}'), child: Padding(padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(contentPadding: EdgeInsets.zero, leading: Icon(system ? Icons.lock_outline : Icons.person_outline),
                title: Text(system ? context.roleLabel(profile.profileId) : profile.displayName),
                subtitle: Text('${profile.profileId} · ${system ? context.roleDescription(profile.profileId) : profile.description}'),
                trailing: system ? Switch(key: ValueKey('system-agent-enabled-${profile.profileId}'), value: profile.enabled,
                  onChanged: state.actions[(profile.profileId, AgentProfileAction.enabled)]?.preventsResubmission == true
                    ? null : (value) => onEnabled(profile.profileId, value))
                  : TextButton.icon(key: ValueKey('agent-profile-edit-${profile.profileId}'),
                    onPressed: state.editor == null ? () => onEdit(profile.profileId) : null,
                    icon: const Icon(Icons.edit_outlined), label: Text(context.l10n.settingsAgentsEditTooltip))),
              Text(agentWorkspaceLabel(context, profile.workspaceMode),
                key: system ? ValueKey('system-agent-workspace-${profile.profileId}') : null),
              if (system) _role(context, profile.profileId),
              for (final error in profileErrors[profile.profileId] ?? <String>[]) SelectableText(error,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]))),
      ]),
      if (hasMore) TextButton.icon(onPressed: state.reading.isNotEmpty ? null : onMore,
        icon: const Icon(Icons.expand_more), label: Text(context.l10n.settingsSshNextPage)),
    ]));

  Widget _role(BuildContext context, String role) {
    final route = state.routes[role];
    final pending = [AgentProfileAction.model, AgentProfileAction.effort].any((action) =>
      state.actions[(role, action)]?.preventsResubmission ?? false);
    if (route == null) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (state.roleReads[role]?.pending == true) Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
        const SizedBox(width: 8), Text(context.l10n.resourceSourceLoading),
      ]) else Text(context.l10n.resourceSourceUninitialized),
      if (roleReadErrors[role] case final error?) ...[
        SelectableText(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (state.roleReads[role]?.target != null && state.roleReads[role]?.pending == false)
        TextButton(onPressed: onRetry, child: Text(context.l10n.runtimeFatalRetry)),
      ],
    ]);
    return Wrap(spacing: 18, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      ModelRouteSelector(selectorKey: StudioDriverKeys.settingsRoleModel(role), fieldLabel: context.l10n.settingsModelField,
        options: roleOptions[role] ?? [], accountId: route.accountId, modelId: route.modelId, unresolvedLabel: routeLabels[role], enabled: !pending,
        onSelected: (option) => onModel(role, option),
        optionKeyBuilder: (option) => StudioDriverKeys.settingsRoleModelOption(role, option.accountId, option.modelId)),
      KeyedSubtree(key: StudioDriverKeys.settingsRoleEffort(role), child: EffortSelector(
        efforts: route.descriptor?.reasoning?.candidates ?? [], selected: route.effort,
        enabled: !pending, allowDefault: false, pending: pending,
        onSelected: (value) => onEffort(role, value))),
    ]);
  }
}
