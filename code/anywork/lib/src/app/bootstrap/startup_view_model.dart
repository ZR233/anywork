import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app_bindings.dart';
import 'startup_view_state.dart';

part 'startup_view_model.g.dart';

/// build only registers an observation. App bootstrap, not a rebuild, calls
/// StartupRepository.start (initialize → prepare → open → listen → start).
@Riverpod(keepAlive: true)
class StartupViewModel extends _$StartupViewModel {
  bool _alive = true;
  int _recoveryIntent = 0;
  int _turnsIntent = 0;
  int _bindingGeneration = 0;
  bool _initializing = false;

  @override
  FutureOr<StartupViewState> build() {
    _alive = true;
    _initializing = true;
    final repository = ref.watch(startupRepositoryProvider);
    final watch = repository.state.watchLatest((startup) {
      final previous = state.asData?.value;
      if (!_alive || _initializing || previous == null) return;
      final sameReady = switch ((previous.startup, startup)) {
        (ReadyStartupState(result: final before), ReadyStartupState(result: final after)) =>
          before.details == after.details,
        _ => false,
      };
      state = AsyncData(previous.copyWith(
        startup: startup,
        recovery: sameReady ? previous.recovery : null,
        recoveryDismissed: sameReady && previous.recoveryDismissed,
        recoveryLoading: sameReady && previous.recoveryLoading,
        recoveryError: sameReady ? previous.recoveryError : null,
        activeTurns: sameReady ? previous.activeTurns : null,
        activeTurnsLoading: sameReady && previous.activeTurnsLoading,
        activeTurnsError: sameReady ? previous.activeTurnsError : null,
      ));
    });
    ref.onDispose(() {
      _alive = false;
      ++_bindingGeneration;
      _recoveryIntent++;
      _turnsIntent++;
      watch.observation.cancel();
    });
    final initial = StartupViewState(
      startup: repository.state.value,
      retryPending: false,
      bootstrapError: null,
      recovery: null,
      recoveryDismissed: false,
      recoveryLoading: false,
      recoveryError: null,
      activeTurns: null,
      activeTurnsLoading: false,
      activeTurnsError: null,
    );
    _initializing = false;
    return initial;
  }

  Future<void> retry() async {
    final previous = state.requireValue;
    if (previous.retryPending) return;
    final binding = _bindingGeneration;
    state = AsyncData(previous.copyWith(retryPending: true, bootstrapError: null));
    try {
      await ref.read(applicationBootstrapProvider).start();
    } on StudioFailure catch (error) {
      if (_alive && binding == _bindingGeneration) {
        state = AsyncData(state.requireValue.copyWith(bootstrapError: error));
      }
    } finally {
      if (_alive && binding == _bindingGeneration) {
        state = AsyncData(state.requireValue.copyWith(retryPending: false));
      }
    }
  }

  Future<void> loadRecovery() async {
    final previous = state.requireValue;
    final startup = previous.startup;
    if (startup is! ReadyStartupState || previous.recoveryLoading) return;
    final reference = startup.result.details;
    final intent = ++_recoveryIntent;
    final repository = ref.read(startupRepositoryProvider);
    state = AsyncData(previous.copyWith(recoveryLoading: true, recoveryError: null));
    try {
      final recovery = await repository.readRecovery(reference);
      if (!_currentReady(reference) || intent != _recoveryIntent) return;
      state = AsyncData(state.requireValue.copyWith(
        recovery: recovery,
        recoveryLoading: false,
      ));
    } on StudioFailure catch (error) {
      if (!_currentReady(reference) || intent != _recoveryIntent) return;
      state = AsyncData(state.requireValue.copyWith(
        recoveryLoading: false,
        recoveryError: error,
      ));
    }
  }

  Future<void> loadActiveTurns({int offset = 0}) async {
    final previous = state.requireValue;
    final startup = previous.startup;
    if (startup is! ReadyStartupState || previous.activeTurnsLoading) return;
    final reference = startup.result.details;
    final intent = ++_turnsIntent;
    final repository = ref.read(startupRepositoryProvider);
    state = AsyncData(previous.copyWith(activeTurnsLoading: true, activeTurnsError: null));
    try {
      final page = await repository.readActiveTurns(reference, offset: offset);
      if (!_currentReady(reference) || intent != _turnsIntent) return;
      state = AsyncData(state.requireValue.copyWith(
        activeTurns: page,
        activeTurnsLoading: false,
      ));
    } on StudioFailure catch (error) {
      if (!_currentReady(reference) || intent != _turnsIntent) return;
      state = AsyncData(state.requireValue.copyWith(
        activeTurnsLoading: false,
        activeTurnsError: error,
      ));
    }
  }

  void dismissRecovery() {
    state = AsyncData(state.requireValue.copyWith(recoveryDismissed: true));
  }

  bool _currentReady(RuntimeStartupReadRef reference) =>
      _alive && switch (state.asData?.value.startup) {
        ReadyStartupState(:final result) => result.details == reference,
        _ => false,
      };
}
