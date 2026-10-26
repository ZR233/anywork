import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../state/settings_navigation_state.dart';
import 'settings_tab_lifecycle.dart';

part 'settings_navigation_view_model.g.dart';

@Riverpod(keepAlive: true)
class SettingsNavigationViewModel extends _$SettingsNavigationViewModel {
  final _tabs = <SettingsTab, Map<int, SettingsTabLifecycle>>{};
  final _retiring = <SettingsTab>{};
  int _registration = 0;
  bool _alive = true;

  @override
  Future<SettingsNavigationState> build() async {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      // Do not start auto-save or business cancellation during disposal.
      _tabs.clear();
      _retiring.clear();
    });
    return const SettingsNavigationState();
  }

  SettingsTabRegistration register(
    SettingsTab tab,
    SettingsTabLifecycle lifecycle,
  ) {
    final id = ++_registration;
    _tabs.putIfAbsent(tab, () => {})[id] = lifecycle;
    return SettingsTabRegistration(
      tab: tab,
      visible: () =>
          _alive &&
          state.asData?.value.visible == true &&
          state.requireValue.tab == tab &&
          !_retiring.contains(tab),
      unregister: () {
        final entries = _tabs[tab];
        entries?.remove(id);
        if (entries?.isEmpty ?? false) _tabs.remove(tab);
      },
    );
  }

  void enter(SettingsTab? initialTab) {
    if (!_alive || state.asData == null) return;
    final current = state.requireValue;
    final tab = initialTab ?? current.tab;
    state = AsyncData(
      current.copyWith(
        tab: tab,
        visible: true,
        visited: {...current.visited, tab},
        generation: current.generation + 1,
        leaving: false,
        request: null,
        error: null,
      ),
    );
    _visibility(tab, true);
  }

  SettingsNavigationRequest? begin(SettingsTab? destination) {
    if (!_alive || state.asData == null || !state.requireValue.visible) {
      return null;
    }
    final current = state.requireValue;
    if (destination == current.tab && current.request == null) return null;
    final request = SettingsNavigationRequest(
      generation: current.generation + 1,
      from: current.tab,
      destination: destination,
    );
    state = AsyncData(
      current.copyWith(
        generation: request.generation,
        leaving: true,
        request: request,
        error: null,
      ),
    );
    return request;
  }

  bool owns(SettingsNavigationRequest request) =>
      _alive &&
      state.asData?.value.request == request &&
      state.requireValue.generation == request.generation &&
      state.requireValue.tab == request.from;

  void reject(SettingsNavigationRequest request) {
    if (owns(request)) {
      state = AsyncData(
        state.requireValue.copyWith(leaving: false, request: null),
      );
    }
  }

  bool complete(SettingsNavigationRequest request) {
    if (!owns(request)) return false;
    _retiring.add(request.from);
    try {
      final participants = List<SettingsTabLifecycle>.of(
        _tabs[request.from]?.values ?? const [],
      );
      for (final participant in participants) {
        participant.handoff?.call();
      }
      if (!owns(request)) return false;
      _visibility(request.from, false);
      if (!owns(request)) return false;
      final current = state.requireValue;
      final next = request.destination;
      state = AsyncData(
        current.copyWith(
          tab: next ?? current.tab,
          visible: next != null,
          visited: {...current.visited, ?next},
          leaving: false,
          request: null,
        ),
      );
      if (next != null) _visibility(next, true);
      return true;
    } finally {
      _retiring.remove(request.from);
    }
  }

  void _visibility(SettingsTab tab, bool visible) {
    for (final participant in List<SettingsTabLifecycle>.of(
      _tabs[tab]?.values ?? const [],
    )) {
      participant.visibility(visible);
    }
  }
}
