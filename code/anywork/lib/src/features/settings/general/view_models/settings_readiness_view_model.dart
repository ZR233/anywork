import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../view_models/read_values.dart';
import '../state/general_settings_state.dart';

part 'settings_readiness_view_model.g.dart';

/// The Settings shell only prepares public configuration. It does not mount a
/// hidden General/Updates connector or request another tab's business details.
@Riverpod(keepAlive: true)
class SettingsReadinessViewModel extends _$SettingsReadinessViewModel {
  late ConfigurationRepository _repository;
  Object? _lifetime;
  Object? _attempted;
  ({Object token, Future<void> result})? _reading;
  Object? _entry;
  bool _scheduled = false;
  ({Object source, StudioFailure error})? _error;

  @override
  FutureOr<SettingsReadinessState> build() {
    final lifetime = Object();
    _lifetime = lifetime;
    _repository = ref.watch(configurationRepositoryProvider);
    _attempted = null;
    _reading = null;
    _scheduled = false;
    _error = null;
    Observation? observation;
    ref.onDispose(() {
      if (identical(_lifetime, lifetime)) _lifetime = null;
      observation?.cancel();
    });
    // Registration and current read are synchronous; publications from sibling
    // provider builds are coalesced, rather than mutating a provider in build.
    observation = _repository.state
        .watchLatest((_) => _schedule(lifetime))
        .observation;
    final initial = _snapshot(null);
    _schedule(lifetime);
    return initial;
  }

  bool _owns(Object lifetime) => ref.mounted && identical(_lifetime, lifetime);

  Object get _source {
    final projection = _repository.state.value.projection;
    return (projection.stamp?.origin, projection.header?.reference);
  }

  SettingsReadinessState _snapshot(SettingsReadinessState? previous) {
    final source = _repository.state.value;
    final origin = source.projection.stamp?.origin;
    final reference = source.projection.header?.reference;
    final ready =
        origin != null &&
        (previous?.ready == true && previous?.readyOrigin == origin ||
            source.projection.sync.phase == ResourceSyncPhase.ready &&
                isCurrentRead(source.general, reference, origin) &&
                isCurrentRead(source.webSearch, reference, origin) &&
                isCurrentRead(source.deepSeekSearch, reference, origin));
    StudioFailure? failure<T>(ReadValue<T, ConfigurationReadRef>? read) =>
        read is FailedReadValue<T, ConfigurationReadRef> &&
            read.origin == origin &&
            read.reference == reference
        ? read.error
        : null;
    return SettingsReadinessState(
      ready: ready,
      readyOrigin: ready ? origin : null,
      error: ready
          ? null
          : failure(source.general) ??
                failure(source.webSearch) ??
                failure(source.deepSeekSearch) ??
                source.projection.sync.error ??
                (_error?.source == _source ? _error?.error : null),
    );
  }

  void _schedule(Object lifetime) {
    if (!_owns(lifetime) || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      if (!_owns(lifetime)) return;
      _scheduled = false;
      unawaited(_reconcile(lifetime));
    });
  }

  /// One route entry is one explicit read attempt. Rebuilds/tab prop changes do
  /// not create entries, and a reentry while the original read waits joins it.
  Future<void> enter(Object entry) {
    final lifetime = _lifetime;
    if (lifetime == null || !_owns(lifetime)) return Future<void>.value();
    if (!identical(_entry, entry) && _reading == null) {
      _attempted = null;
      _error = null;
    }
    _entry = entry;
    return _reconcile(lifetime, recoverSource: true);
  }

  void leave(Object entry) {
    if (identical(_entry, entry)) _entry = null;
    // Leaving only releases demand. The repository still owns pending reads.
  }

  Future<void> _reconcile(Object lifetime, {bool recoverSource = false}) {
    if (!_owns(lifetime) || !state.hasValue) return Future<void>.value();
    final next = _snapshot(state.requireValue);
    state = AsyncData(next);
    if (!_owns(lifetime)) return Future<void>.value();
    final reading = _reading;
    if (reading != null) return reading.result;
    final sourceRecovery =
        recoverSource &&
        _repository.state.value.projection.sync.phase !=
            ResourceSyncPhase.ready;
    if (_entry == null ||
        next.ready && !sourceRecovery ||
        _attempted == _source) {
      return Future<void>.value();
    }
    final source = _source;
    final work = Object();
    final done = Completer<void>();
    _attempted = source;
    _reading = (token: work, result: done.future);
    _error = null;
    unawaited(
      _prepare(
        _repository,
        lifetime,
        work,
      ).then(done.complete, onError: done.completeError),
    );
    return done.future;
  }

  Future<void> _prepare(
    ConfigurationRepository repository,
    Object lifetime,
    Object work,
  ) async {
    StudioFailure? error;
    Future<void> read<T>(Future<T> Function() query) async {
      try {
        await query();
      } on StudioFailure catch (failure) {
        error ??= failure;
      }
    }

    try {
      if (repository.state.value.projection.sync.phase !=
          ResourceSyncPhase.ready) {
        // Pure source recovery, never reload/save. It also joins the original
        // repository bootstrap before the three exact current field reads.
        final recoverySource = _source;
        await read(repository.loadSourceStatus);
        if (error != null) {
          if (_owns(lifetime) &&
              identical(_reading?.token, work) &&
              recoverySource == _source) {
            _error = (source: recoverySource, error: error!);
          }
          return;
        }
      }
      if (!_owns(lifetime) || !identical(_reading?.token, work)) return;
      final source = _source;
      _attempted = source;
      await Future.wait([
        read(repository.loadGeneralSettings),
        read(repository.loadWebSearchSettings),
        read(repository.loadDeepSeekSettings),
      ]);
      if (!_owns(lifetime) || !identical(_reading?.token, work)) return;
      if (source == _source) {
        _error = error == null ? null : (source: source, error: error!);
      }
    } finally {
      if (_owns(lifetime) && identical(_reading?.token, work)) {
        _reading = null;
        _schedule(lifetime);
      }
    }
  }
}
