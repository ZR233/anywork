import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/settings/mode_editor/mode_editor_dialogs.dart';
import '../../features/settings/settings_section.dart';
import 'app_route.dart';

/// Creates the application's sole router from the generated typed route table.
GoRouter createApplicationRouter() => GoRouter(
  restorationScopeId: 'anywork-router',
  onEnter: _protectModeSectionChange,
  routes: $appRoutes,
);

Future<OnEnterResult> _protectModeSectionChange(
  BuildContext context,
  GoRouterState currentState,
  GoRouterState nextState,
  GoRouter router,
) async {
  final currentMatches = router.routerDelegate.currentConfiguration.matches;
  if (!currentMatchesSettings(currentMatches)) return const Allow();

  final currentSection = settingsSectionForMatchedRoute(currentState);
  if (currentSection != SettingsSection.workModes) return const Allow();

  final nextSection = settingsSectionForMatchedRoute(nextState);
  if (nextSection == null || nextSection == SettingsSection.workModes) {
    // Leaving the Settings match is handled by SettingsRoute.onExit.
    return const Allow();
  }

  return await confirmLeaveModeEditor(context)
      ? const Allow()
      : const Block.stop();
}
