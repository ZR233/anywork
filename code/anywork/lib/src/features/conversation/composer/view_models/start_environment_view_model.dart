import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/providers/project_store.dart';
import '../../../../presentation/providers/settings_store.dart';
import '../../../../presentation/providers/start_session_controller.dart';

final _standalonePreparingProvider = Provider.autoDispose<bool>((ref) {
  final state = observeClient(
    ref,
    ref.read(anyworkClientProvider).directoryCommands.source,
    (_) => ref.invalidateSelf(),
  );
  return state.standalonePreparationInProgress;
});

typedef StartEnvironmentState = ({
  List<StudioProject> projects,
  StudioProject? workspace,
  DelegationSettingsView? defaults,
  DelegationMode? modeOverride,
  DelegationPreference? preferenceOverride,
  ThreadWorkspaceMode workspaceMode,
  bool editable,
});

final startEnvironmentViewModelProvider = Provider.autoDispose
    .family<StartEnvironmentState, String?>((ref, workspaceId) {
      final projects =
          ref
              .watch(projectStoreProvider.select((state) => state.projects))
              ?.values
              .toList() ??
          <StudioProject>[];
      final draft = ref.watch(
        startSessionControllerProvider.select((state) {
          final project = state.forProject(workspaceId);
          return (
            state.submitting,
            project.delegationModeOverride,
            project.delegationPreferenceOverride,
            project.workspaceMode,
          );
        }),
      );
      return (
        projects: projects,
        workspace: projects.where((item) => item.id == workspaceId).firstOrNull,
        defaults: ref.watch(
          settingsStoreProvider.select((state) => state.canonical?.delegation),
        ),
        modeOverride: draft.$2,
        preferenceOverride: draft.$3,
        workspaceMode: draft.$4,
        editable: !draft.$1 && !ref.watch(_standalonePreparingProvider),
      );
    });

final startEnvironmentActionsProvider = NotifierProvider.autoDispose
    .family<StartEnvironmentActions, Object?, String?>(
      StartEnvironmentActions.new,
    );

final class StartEnvironmentActions extends Notifier<Object?> {
  StartEnvironmentActions(this._workspaceId);

  final String? _workspaceId;

  @override
  Object? build() => null;

  Future<void> selectProject(StudioProject? project) async {
    state = null;
    final commands = ref.read(anyworkClientProvider).directoryCommands;
    try {
      if (project == null || project.isStandalone) {
        await commands.beginStandaloneThread();
      } else {
        await commands.beginNewThread(workspaceId: project.id);
      }
    } catch (error) {
      if (ref.mounted) state = error;
    }
  }

  void setMode(DelegationMode? mode) => ref
      .read(anyworkClientProvider)
      .drafts
      .startDraft
      .setDelegationModeOverride(_workspaceId!, mode);

  void setPreference(DelegationPreference? preference) => ref
      .read(anyworkClientProvider)
      .drafts
      .startDraft
      .setDelegationPreferenceOverride(_workspaceId!, preference);

  void setWorkspaceMode(ThreadWorkspaceMode mode) => ref
      .read(anyworkClientProvider)
      .drafts
      .startDraft
      .setWorkspaceMode(_workspaceId!, mode);
}
