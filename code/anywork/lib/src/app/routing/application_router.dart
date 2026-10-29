import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/modes/modes.dart' show confirmLeaveModeEditor;
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

  // Only the Settings root's own query-only section change is decided here.
  // Removing a mode workspace or detail match is a real route removal: it is
  // decided by ModeWorkspaceRoute.onExit (same-modeId source) with the
  // Settings parent re-checking the still-unsettled source afterwards. This
  // onEnter must not pre-decide that workspace draft first.
  if (!isSettingsRootMatch(currentState)) return const Allow();

  final currentSection = settingsSectionForMatchedRoute(currentState);
  if (currentSection != SettingsSection.workModes) return const Allow();

  final nextSection = settingsSectionForMatchedRoute(nextState);
  if (nextSection == null || nextSection == SettingsSection.workModes) {
    // Leaving the Settings match is handled by SettingsRoute.onExit.
    return const Allow();
  }

  final navigatorKey = router.routerDelegate.navigatorKey;
  final navigatorContext = navigatorKey.currentContext;
  if (navigatorContext == null ||
      !navigatorContext.mounted ||
      !identical(GoRouter.maybeOf(navigatorContext), router) ||
      !identical(
        Navigator.maybeOf(navigatorContext),
        navigatorKey.currentState,
      )) {
    return const Block.stop();
  }

  return await confirmLeaveModeEditor(navigatorContext)
      ? const Allow()
      : const Block.stop();
}
