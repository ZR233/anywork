import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/settings_workspace_state.dart';

part 'settings_workspace_view_model.g.dart';

@riverpod
class SettingsWorkspaceViewModel extends _$SettingsWorkspaceViewModel {
  late WorkspaceRepository _repository;
  Observation? _observation;
  bool _alive = true;
  bool _connecting = false;
  int _lifetime = 0;
  @override
  Future<SettingsWorkspaceState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _repository = ref.watch(workspaceRepositoryProvider);
    ref.onDispose(() { _alive = false; _lifetime++; _observation?.cancel(); });
    final initial = _connect(lifetime);
    unawaited(Future<void>(() {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(source: _repository.state.value));
    }));
    return initial;
  }
  bool _owns(int lifetime) => _alive && lifetime == _lifetime && state.asData != null;
  SettingsWorkspaceState _connect(int lifetime) {
    StudioFailure? failure;
    try {
      final watch = _repository.state.watchLatest((source) {
        if (_owns(lifetime)) state = AsyncData(SettingsWorkspaceState(source: source, observing: true));
      });
      if (_alive && lifetime == _lifetime) { _observation = watch.observation; }
      else { watch.observation.cancel(); }
    } on StudioFailure catch (error) { failure = error; }
    return SettingsWorkspaceState(source: _repository.state.value,
      observing: failure == null && _observation != null, observationError: failure);
  }
  void retryObservation() {
    if (!_alive || _connecting || state.asData == null || _observation != null) return;
    _connecting = true;
    try {
      final lifetime = _lifetime;
      final current = _connect(lifetime);
      if (_owns(lifetime)) state = AsyncData(current);
    } finally { _connecting = false; }
  }
}
