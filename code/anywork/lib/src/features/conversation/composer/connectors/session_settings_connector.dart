import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/project_store.dart';
import '../../../../presentation/providers/settings_store.dart';
import '../../../../presentation/providers/start_session_controller.dart';
import '../../../../shared/delegation_labels.dart';
import '../views/session_settings_view.dart';

class SessionSettingsConnector extends ConsumerWidget {
  const SessionSettingsConnector({
    super.key,
    required this.workspaceId,
    required this.enabled,
  });

  final String workspaceId;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(startSessionControllerProvider);
    final project = draft.forProject(workspaceId);
    final workspace = ref
        .watch(projectStoreProvider)
        .projects
        ?.values
        .where((candidate) => candidate.id == workspaceId)
        .firstOrNull;
    final defaults = ref.watch(settingsStoreProvider).canonical?.delegation;
    if (defaults == null) return const SizedBox.shrink();
    final effective = project.resolveDelegation(defaults);
    final owner = ref.read(anyworkClientProvider).drafts.startDraft;
    return SessionSettingsView(
      summary: context.delegationSummary(effective),
      defaultMode: defaults.mode,
      defaultPreference: defaults.preference,
      modeOverride: project.delegationModeOverride,
      preferenceOverride: project.delegationPreferenceOverride,
      workspaceMode: project.workspaceMode,
      isStandalone: workspace?.isStandalone ?? false,
      enabled: enabled && !draft.submitting,
      onModeChanged: (mode) => owner.setDelegationModeOverride(workspaceId, mode),
      onPreferenceChanged: (preference) =>
          owner.setDelegationPreferenceOverride(workspaceId, preference),
      onWorkspaceModeChanged: (mode) => owner.setWorkspaceMode(workspaceId, mode),
    );
  }
}
