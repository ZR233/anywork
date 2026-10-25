import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../state/account_model_details_state.dart';
import 'account_model_details_target.dart';

part 'account_model_details_view_model.g.dart';

@riverpod
class AccountModelDetailsViewModel extends _$AccountModelDetailsViewModel {
  late ConfigurationRepository _configuration;
  late ModelsRepository _models;
  late ConfigurationState _configurationSource;
  late ModelsState _catalogSource;
  late AccountModelDetailsEntry _entry;
  final _observations = <Observation>[];
  int _lifetime = 0;
  int _intent = 0;
  bool _alive = false;
  bool _initialRequested = false;

  @override
  Future<AccountModelDetailsViewState> build(
    AccountModelDetailsEntry entry,
  ) async {
    _alive = true;
    _entry = entry;
    final lifetime = ++_lifetime;
    _configuration = ref.watch(configurationRepositoryProvider);
    _models = ref.watch(modelsRepositoryProvider);
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      for (final observation in _observations) {
        observation.cancel();
      }
      _observations.clear();
      // Exact-read scope cleanup and accepted reads belong to the Repository.
    });
    final observationErrors = _observeSources(lifetime);
    // Registration precedes current consumption. Build never opens a detail
    // scope: the Smart entry explicitly starts the one initial read below.
    return AccountModelDetailsViewState(
      entry: entry,
      target: entry.target,
      billingOverrideKnown: entry.billingOverrideKnown,
      billingOverride: entry.billingOverride,
      stale: entry.target != null && !_current(entry.target!),
      observationErrors: observationErrors,
      configurationError: _configurationSource.projection.sync.error,
      catalogError: _catalogSource.projection.sync.error,
    );
  }

  List<StudioFailure> _observeSources(int lifetime) {
    for (final observation in _observations) {
      observation.cancel();
    }
    _observations.clear();
    final errors = <StudioFailure>[];
    try {
      final watch = _configuration.state.watchLatest((source) {
        if (!_alive || _lifetime != lifetime) return;
        _configurationSource = source;
        _sourceChanged(lifetime);
      });
      _observations.add(watch.observation);
      _configurationSource = watch.value;
    } on StudioFailure catch (error) {
      errors.add(error);
      _configurationSource = _configuration.state.value;
    }
    try {
      final watch = _models.state.watchLatest((source) {
        if (!_alive || _lifetime != lifetime) return;
        _catalogSource = source;
        _sourceChanged(lifetime);
      });
      _observations.add(watch.observation);
      _catalogSource = watch.value;
    } on StudioFailure catch (error) {
      errors.add(error);
      _catalogSource = _models.state.value;
    }
    return errors;
  }

  bool _owns(int lifetime, AccountModelDetailsEntry entry, int intent) =>
      _alive &&
      lifetime == _lifetime &&
      identical(_entry, entry) &&
      state.asData != null &&
      identical(state.requireValue.entry, entry) &&
      state.requireValue.latestIntent == intent;

  bool _current(DelegationModelReadTarget target) {
    final pair = target.sources;
    return _observations.length == 2 &&
        _observations.every(
          (observation) => !observation.isCancelled && !observation.isPaused,
        ) &&
        _configurationSource.projection.header?.roleRead == pair &&
        _configurationSource.projection.stamp?.origin ==
            pair.configuration.origin &&
        _configurationSource.projection.header?.reference ==
            pair.configuration.reference &&
        _catalogSource.projection.stamp?.origin == pair.catalog.origin &&
        _catalogSource.projection.header?.reference == pair.catalog.reference &&
        _configurationSource.projection.sync.phase == ResourceSyncPhase.ready &&
        _catalogSource.projection.sync.phase == ResourceSyncPhase.ready;
  }

  void _sourceChanged(int lifetime) {
    if (!_alive || lifetime != _lifetime || state.asData == null) return;
    final value = state.requireValue;
    final target = value.target;
    state = AsyncData(
      value.copyWith(
        stale: value.stale || (target != null && !_current(target)),
        configurationError: _configurationSource.projection.sync.error,
        catalogError: _catalogSource.projection.sync.error,
      ),
    );
    // Source notifications mark last-known material; they never reload it.
  }

  Future<void> loadInitial(AccountModelDetailsEntry entry) async {
    if (!_alive ||
        !identical(_entry, entry) ||
        _initialRequested ||
        state.asData == null) {
      return;
    }
    _initialRequested = true;
    await _read(entry);
  }

  Future<void> reload() async {
    if (!_alive || state.asData == null || state.requireValue.reading) return;
    final errors = _observeSources(_lifetime);
    state = AsyncData(
      state.requireValue.copyWith(
        observationErrors: errors,
        configurationError: _configurationSource.projection.sync.error,
        catalogError: _catalogSource.projection.sync.error,
      ),
    );
    // An explicit action alone captures a new real pair. A missing/failed pair
    // is an unavailable read, never an empty successful detail or a latest shim.
    final capture = captureModelDetailsEntry(
      _entry.model,
      _configurationSource,
    );
    await _read(capture);
  }

  Future<void> _read(AccountModelDetailsEntry capture) async {
    if (!_alive || state.asData == null) return;
    final lifetime = _lifetime;
    final entry = _entry;
    final models = _models;
    final target = capture.target;
    final intent = ++_intent;
    final previous = state.requireValue;
    state = AsyncData(
      previous.copyWith(
        target: target,
        latestIntent: intent,
        reading: true,
        error: null,
        stale:
            (previous.detail != null && previous.detail!.target != target) ||
            (target != null && !_current(target)),
        // Keep the previous detail's matching billing readout while it is shown.
        billingOverrideKnown: previous.detail == null
            ? capture.billingOverrideKnown
            : previous.billingOverrideKnown,
        billingOverride: previous.detail == null
            ? capture.billingOverride
            : previous.billingOverride,
      ),
    );
    if (!_owns(lifetime, entry, intent)) return;
    try {
      if (target == null) {
        throw const StudioFailure(
          code: StudioFailureCode.notInitialized,
          message: 'The original configuration/catalog pairing credential is not ready.',
          retryable: true,
          correlationId: 'settings-model-details',
        );
      }
      if (target.model != entry.model) {
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'The model detail read changed its original account/model.',
          retryable: false,
          correlationId: 'settings-model-details',
        );
      }
      if (!_current(target)) {
        throw const StudioFailure(
          code: StudioFailureCode.staleRevision,
          message: 'The captured configuration/catalog pair is no longer current or ready. Reload its details.',
          retryable: true,
          correlationId: 'settings-model-details',
        );
      }
      final detail = await models.loadDelegationModel(target);
      if (!_owns(lifetime, entry, intent)) return;
      if (detail.target != target ||
          detail.target.model != entry.model ||
          detail.descriptor.modelId != entry.model.modelId) {
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message:
              'The model detail response belongs to another original target.',
          retryable: false,
          correlationId: 'settings-model-details',
        );
      }
      final current = state.requireValue;
      state = AsyncData(
        current.copyWith(
          detail: detail,
          reading: false,
          error: null,
          stale: !_current(target),
          billingOverrideKnown: capture.billingOverrideKnown,
          billingOverride: capture.billingOverride,
        ),
      );
    } on StudioFailure catch (error) {
      if (!_owns(lifetime, entry, intent)) return;
      state = AsyncData(
        state.requireValue.copyWith(
          reading: false,
          error: error,
          stale:
              state.requireValue.stale ||
              error.code == StudioFailureCode.staleRevision,
        ),
      );
    } catch (error, stack) {
      // Programming/non-domain failures remain failures, including after close.
      if (!_owns(lifetime, entry, intent)) {
        Error.throwWithStackTrace(error, stack);
      }
      state = AsyncError(error, stack);
    }
  }
}
