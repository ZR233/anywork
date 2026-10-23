import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modes/connectors/mode_editor_connector.dart';
import '../state/settings_navigation_state.dart';
import '../view_models/settings_navigation_view_model.dart';

/// The application router's one Settings onExit callback. No router, exit
/// coordinator or business operation is owned by this feature entrypoint.
Future<bool> confirmLeaveSettings(BuildContext context, WidgetRef ref) =>
  _requestNavigation(context, ref, null);

/// Local tab navigation follows the same request and handoff path as onExit.
Future<bool> selectSettingsTab(BuildContext context, WidgetRef ref, SettingsTab tab) =>
  _requestNavigation(context, ref, tab);

Future<bool> _requestNavigation(BuildContext context, WidgetRef ref, SettingsTab? destination) async {
  if (!context.mounted) return false;
  final owner = ref.read(settingsNavigationViewModelProvider.notifier);
  final snapshot = ref.read(settingsNavigationViewModelProvider);
  if (snapshot.isLoading || snapshot.hasError) return false;
  final current = snapshot.asData?.value;
  if (current == null) return false;
  if (!current.visible) return destination == null;
  final request = owner.begin(destination);
  if (request == null) return destination == current.tab;
  bool owns() {
    if (!context.mounted || !identical(ref.read(settingsNavigationViewModelProvider.notifier), owner)) return false;
    final snapshot = ref.read(settingsNavigationViewModelProvider);
    return !snapshot.isLoading && !snapshot.hasError && identical(snapshot.asData?.value.request, request) && owner.owns(request);
  }
  if (!owns()) return false;
  if (request.from == SettingsTab.modes) {
    final allowed = await confirmLeaveModeEditor(context, ref, isCurrent: owns);
    if (!owns()) return false;
    if (!allowed) { owner.reject(request); return false; }
  }
  if (!owns()) return false;
  // The original owner hands valid auto-save intentions to their Repositories
  // before hiding participants; it alone changes the active/visited tab state.
  return owner.complete(request);
}
