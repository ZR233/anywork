import '../state/settings_navigation_state.dart';

/// Settings-local presentation lifecycle, not a business operation registry.
/// Owners register their already existing VM; navigation never constructs an
/// unseen family merely to hand off an editor.
final class SettingsTabLifecycle {
  const SettingsTabLifecycle({required this.visibility, this.handoff});
  final void Function(bool visible) visibility;
  final void Function()? handoff;
}

final class SettingsTabRegistration {
  SettingsTabRegistration({required this.tab, required bool Function() visible,
    required void Function() unregister}) : _visible = visible, _unregister = unregister;
  final SettingsTab tab;
  final bool Function() _visible;
  final void Function() _unregister;
  bool _closed = false;
  bool get visible => !_closed && _visible();
  void unregister() {
    if (_closed) return;
    _closed = true;
    _unregister();
  }
}
