import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories/studio_controller.dart';

/// 把路由可见性转成会话阅读面的资源合同。
///
/// 导航只表达"用户在看哪一页"，不承担"数据是否新鲜"：设置、目录与线程事实都由
/// app 级 topic 租约与线程状态流持续交付，离开或返回设置页不触发任何 canonical
/// 读取。观察者因此只维护一件事——设置路由是否仍在栈上——并把结果交给控制器，
/// 由 `setConversationVisible` 按电平收敛（可重复、幂等）。
///
/// 路由栈按需记账：菜单、对话框等嵌套路由压栈时栈上仍存在设置路由，阅读面保持
/// 不可见；只有设置路由真正出栈才恢复。
final class StudioNavigationCoordinator extends NavigatorObserver {
  StudioNavigationCoordinator(this._controller);

  final StudioController _controller;
  final List<Route<dynamic>> _routes = [];
  bool? _conversationVisible;

  bool _isSettings(Route<dynamic> route) {
    final name = route.settings.name;
    return name == 'settings' || name?.endsWith('/settings') == true;
  }

  void _sync() {
    final visible = !_routes.any(_isSettings);
    if (_conversationVisible == visible) return;
    _conversationVisible = visible;
    // 路由回调不得阻塞：可见性立即提交，资源收敛在控制器内按顺序完成。
    unawaited(_setConversationVisible(visible));
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
    _routes.remove(route);
    if (previousRoute != null && !_routes.contains(previousRoute)) {
      _routes.add(previousRoute);
    }
    _sync();
  }

  void _recordReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
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
    _sync();
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
