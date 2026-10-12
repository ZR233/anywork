import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories/studio_controller.dart';

/// Owns app-wide route effects that must outlive a Settings page.
///
/// Settings writes are owned by [StudioController]. When the Settings route is
/// removed, this observer enqueues one canonical read behind the same
/// operation lane. The page itself therefore has no page-lifetime barrier and
/// a dialog or nested route cannot make the observer mistake a temporary top
/// route for leaving Settings.
final class StudioNavigationCoordinator extends NavigatorObserver {
  StudioNavigationCoordinator(this._controller);

  final StudioController _controller;
  final List<Route<dynamic>> _routes = [];
  bool? _conversationVisible;
  bool _settingsRouteActive = false;

  bool _isSettings(Route<dynamic> route) {
    final name = route.settings.name;
    return name == 'settings' || name?.endsWith('/settings') == true;
  }

  void _sync({bool settingsRouteRemoved = false}) {
    final settingsRouteActive = _routes.any(_isSettings);
    final leavingSettings =
        !settingsRouteActive && (settingsRouteRemoved || _settingsRouteActive);
    _settingsRouteActive = settingsRouteActive;

    // Route callbacks must stay non-blocking. The operation is ordered by the
    // controller, while visibility is updated immediately so subscription
    // lifecycle never waits on a bridge read.
    if (leavingSettings) {
      unawaited(_reconcileSettingsAfterNavigation());
    }
    final visible = !settingsRouteActive;
    if (_conversationVisible == visible) return;
    _conversationVisible = visible;
    unawaited(_setConversationVisible(visible));
  }

  Future<void> _reconcileSettingsAfterNavigation() async {
    try {
      await _controller.reconcileSettingsAfterNavigation();
    } catch (error, stack) {
      debugPrint(
        'settings_navigation_reconcile_unhandled error=$error\n$stack',
      );
    }
  }

  Future<void> _setConversationVisible(bool visible) async {
    try {
      await _controller.setConversationVisible(visible);
    } catch (error, stack) {
      debugPrint(
        'route_visibility_failed visible=$visible error=$error\n$stack',
      );
    }
  }

  void _recordPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null && !_routes.contains(previousRoute)) {
      _routes.add(previousRoute);
    }
    _routes.remove(route);
    _routes.add(route);
    _sync();
  }

  void _recordPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final removedSettings = _isSettings(route);
    _routes.remove(route);
    if (previousRoute != null && !_routes.contains(previousRoute)) {
      _routes.add(previousRoute);
    }
    _sync(settingsRouteRemoved: removedSettings);
  }

  void _recordReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final removedSettings = oldRoute != null && _isSettings(oldRoute);
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    } else if (newRoute != null) {
      _routes.remove(newRoute);
      _routes.add(newRoute);
    }
    _sync(settingsRouteRemoved: removedSettings);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _recordPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _recordPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _recordPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _recordReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
