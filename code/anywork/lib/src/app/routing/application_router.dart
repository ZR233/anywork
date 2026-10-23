import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/workspace/connectors/add_project_dialog.dart';
import '../../features/workspace/state/workspace_view_state.dart';
import '../../features/workspace/workspace_screen.dart';
import '../lifecycle/application_exit_coordinator.dart';

/// The one navigation owner. Feature public Screen/guard leaves are required
/// inputs, not default pages, facades or an alternative selected-ID store.
/// The application transfers this router to AnyworkApp for disposal.
GoRouter createApplicationRouter({
  required ApplicationExitCoordinator exitCoordinator,
  required WidgetBuilder settingsScreen,
  required Future<bool> Function(BuildContext context) confirmLeaveSettings,
}) {
  late final GoRouter router;
  void navigate(WorkspaceNavigationIntent intent) {
    if (exitCoordinator.state.value.exiting) return;
    router.goNamed(switch (intent.destination) {
      WorkspaceNavigationDestination.workspace => 'studio',
      WorkspaceNavigationDestination.settings => 'settings',
    });
  }
  router = GoRouter(
    restorationScopeId: 'anywork-router',
    routes: [
      GoRoute(path: '/', name: 'studio',
        builder: (context, state) => WorkspaceScreen(
          onNavigate: navigate,
          onAddProject: () {
            if (!exitCoordinator.state.value.exiting) unawaited(showAddProjectDialog(context));
          }),
        routes: [
          GoRoute(path: 'settings', name: 'settings',
            onExit: (context, state) => exitCoordinator.state.value.exiting
                ? true : confirmLeaveSettings(context),
            pageBuilder: (context, state) => MaterialPage<void>(
              key: state.pageKey, restorationId: 'settings-page',
              child: settingsScreen(context))),
        ]),
    ],
  );
  return router;
}
