import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/selector_catalog_state.dart';

part 'selector_catalog_view_model.g.dart';

@riverpod
class SelectorCatalogViewModel extends _$SelectorCatalogViewModel {
  final List<Observation> _observations = [];
  bool _initializing = true;
  SelectorCatalogState Function(SelectorCatalogState)? _pendingEdit;
  bool _publishScheduled = false;

  @override
  FutureOr<SelectorCatalogState> build() {
    _initializing = true;
    final configuration = ref.read(configurationRepositoryProvider);
    final models = ref.read(modelsRepositoryProvider);
    final modes = ref.read(modesRepositoryProvider);
    ref.onDispose(_disposeObservations);
    try {
      _observations.add(
        configuration.state.watchLatest((value) {
          _coalesce((current) => current.copyWith(configuration: value));
        }).observation,
      );
      _observations.add(
        models.state.watchLatest((value) {
          _coalesce((current) => current.copyWith(models: value));
        }).observation,
      );
      _observations.add(
        modes.state.watchLatest((value) {
          _coalesce((current) => current.copyWith(modes: value));
        }).observation,
      );
      final initial = SelectorCatalogState(
        configuration: configuration.state.value,
        models: models.state.value,
        modes: modes.state.value,
      );
      _initializing = false;
      scheduleMicrotask(() {
        if (ref.mounted) unawaited(loadMore());
      });
      return initial;
    } catch (error, stack) {
      _disposeObservations();
      Error.throwWithStackTrace(error, stack);
    }
  }

  bool get _canPublish => ref.mounted && !_initializing && state.hasValue;

  /// Shared sources publish synchronously from inside whichever provider read
  /// them, which may be another provider's build. Coalesce the edits and apply
  /// them in a microtask so this notifier never mutates itself while a sibling
  /// is initializing; one tick publishes only the last composed value and every
  /// edit is re-checked against the live owner before it is written.
  void _coalesce(SelectorCatalogState Function(SelectorCatalogState) edit) {
    final previous = _pendingEdit;
    _pendingEdit = previous == null
        ? edit
        : (current) => edit(previous(current));
    if (_publishScheduled) return;
    _publishScheduled = true;
    scheduleMicrotask(() {
      _publishScheduled = false;
      final pending = _pendingEdit;
      _pendingEdit = null;
      if (pending == null || !_canPublish) return;
      state = AsyncData(pending(state.requireValue));
    });
  }

  /// One bounded page per demand. Do not scan every account or derive defaults
  /// from a partly loaded catalog; explicit subsequent clicks load more.
  Future<void> loadMore() async {
    if (!_canPublish) return;
    final configuration = ref.read(configurationRepositoryProvider);
    await Future.wait([
      _read(SelectorRead.accounts, configuration.loadAccountsPage),
      _read(
        SelectorRead.models,
        ref.read(modelsRepositoryProvider).loadAccountsPage,
      ),
      _read(
        SelectorRead.modes,
        ref.read(modesRepositoryProvider).loadModesPage,
      ),
      _read(SelectorRead.delegation, () async {
        await configuration.loadDelegationSettings();
      }),
    ]);
  }

  Future<void> _read(SelectorRead field, Future<void> Function() read) async {
    if (!_canPublish || state.requireValue.reading.contains(field)) return;
    final before = state.requireValue;
    state = AsyncData(
      before.copyWith(
        reading: {...before.reading, field},
        errors: {...before.errors}..remove(field),
      ),
    );
    try {
      await read();
    } on StudioFailure catch (error) {
      if (_canPublish) {
        state = AsyncData(
          state.requireValue.copyWith(
            errors: {...state.requireValue.errors, field: error},
          ),
        );
      }
    } finally {
      if (_canPublish) {
        state = AsyncData(
          state.requireValue.copyWith(
            reading: {...state.requireValue.reading}..remove(field),
          ),
        );
      }
    }
  }

  void _disposeObservations() {
    _initializing = true;
    final observations = List<Observation>.of(_observations);
    _observations.clear();
    for (final observation in observations) {
      try {
        observation.cancel();
      } catch (error, stack) {
        Zone.current.handleUncaughtError(error, stack);
      }
    }
  }
}
