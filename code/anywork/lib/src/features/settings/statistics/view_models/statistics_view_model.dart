import 'dart:async';

import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/statistics_view_state.dart';

part 'statistics_view_model.g.dart';

@riverpod
class StatisticsViewModel extends _$StatisticsViewModel {
  late StatisticsRepository _repository;
  late VisibleReadDemand<(ProductReadOrigin, PerformanceSummariesReadRef)>
  _summaries;
  late VisibleReadDemand<(ProductReadOrigin, PerformanceHistoryReadRef)>
  _history;
  Observation? _summaryObservation;
  Observation? _historyObservation;
  final _manualReading = <StatisticsReadField>{};
  final _bootstrapped = <StatisticsReadField>{};
  final _observerErrors = <StatisticsReadField, StudioFailure>{};
  bool _alive = true;
  bool _visible = false;
  int _lifetime = 0;
  @override
  Future<StatisticsViewState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _repository = ref.watch(statisticsRepositoryProvider);
    _summaries = VisibleReadDemand(
      read: (target) async {
        final source = _repository.summaries.value.projection;
        if (source.stamp?.origin == target.$1 &&
            source.header?.reference == target.$2) {
          await _repository.loadSummariesPage();
        }
      },
      changed: (target, error, current) => _changed(
        StatisticsReadField.summaries,
        error,
        current,
        _summaries.reading,
        lifetime,
      ),
    );
    _history = VisibleReadDemand(
      read: (target) async {
        final source = _repository.history.value.projection;
        if (source.stamp?.origin == target.$1 &&
            source.header?.reference == target.$2) {
          await _repository.loadHistoryPage();
        }
      },
      changed: (target, error, current) => _changed(
        StatisticsReadField.history,
        error,
        current,
        _history.reading,
        lifetime,
      ),
    );
    final tab = ref
        .read(settingsNavigationViewModelProvider.notifier)
        .register(
          SettingsTab.statistics,
          SettingsTabLifecycle(visibility: setVisible),
        );
    _visible = tab.visible;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      tab.unregister();
      _detach();
      _summaries.dispose();
      _history.dispose();
      // Statistics are read-only. No accepted read or Repository is cancelled.
    });
    if (_visible) _attach(lifetime);
    Future<void>(() {
      if (_owns(lifetime)) _refresh();
    });
    return StatisticsViewState(
      summaries: _repository.summaries.value,
      history: _repository.history.value,
      visible: _visible,
      observationIssues: {..._observerErrors},
    );
  }

  bool _owns(int lifetime) =>
      _alive && lifetime == _lifetime && state.asData != null;
  void _attach(int lifetime) {
    try {
      _summaryObservation ??= _repository.summaries.watchLatest((source) {
        if (!_owns(lifetime) || !_visible) return;
        state = AsyncData(state.requireValue.copyWith(summaries: source));
        _pruneFilters();
        _refresh();
      }).observation;
      _observerErrors.remove(StatisticsReadField.summaries);
    } on StudioFailure catch (error) {
      _observerErrors[StatisticsReadField.summaries] = error;
    }
    try {
      _historyObservation ??= _repository.history.watchLatest((source) {
        if (!_owns(lifetime) || !_visible) return;
        state = AsyncData(state.requireValue.copyWith(history: source));
        _pruneFilters();
        _refresh();
      }).observation;
      _observerErrors.remove(StatisticsReadField.history);
    } on StudioFailure catch (error) {
      _observerErrors[StatisticsReadField.history] = error;
    }
    if (_owns(lifetime)) {
      state = AsyncData(
        state.requireValue.copyWith(observationIssues: {..._observerErrors}),
      );
    }
  }

  void _detach() {
    _summaryObservation?.cancel();
    _summaryObservation = null;
    _historyObservation?.cancel();
    _historyObservation = null;
  }

  void setVisible(bool visible) {
    if (!_alive || _visible == visible) return;
    _visible = visible;
    if (!visible) {
      _detach();
      _summaries.visible(false);
      _history.visible(false);
    } else {
      _attach(_lifetime);
    }
    if (state.asData != null) {
      state = AsyncData(
        state.requireValue.copyWith(
          visible: visible,
          summaries: visible
              ? _repository.summaries.value
              : state.requireValue.summaries,
          history: visible
              ? _repository.history.value
              : state.requireValue.history,
        ),
      );
      _pruneFilters();
      _refresh();
    }
  }

  void _changed(
    StatisticsReadField field,
    StudioFailure? error,
    bool current,
    bool reading,
    int lifetime,
  ) {
    if (!_owns(lifetime)) return;
    final issues = {...state.requireValue.readIssues};
    if (current) {
      if (error == null) {
        issues.remove(field);
      } else {
        issues[field] = error;
      }
    }
    state = AsyncData(
      state.requireValue.copyWith(
        reading: {...state.requireValue.reading}
          ..remove(field)
          ..addAll(reading ? [field] : []),
        readIssues: issues,
      ),
    );
  }

  static bool _needsPage<T>(
    CollectionMirror<T> mirror,
    ProductReadOrigin origin,
  ) {
    if (mirror is! CurrentCollectionMirror<T> ||
        mirror.window.origin != origin) {
      return true;
    }
    final window = mirror.window;
    return window.entries.isEmpty && !window.complete ||
        window.entries.any((reference) {
          final row = window.rows[reference.entry];
          return row is! ReadyReadValue<T, ProductEntityRef> ||
              row.current.origin != origin ||
              row.current.reference != reference;
        });
  }

  void _refresh() {
    if (!_alive || state.asData == null) return;
    final summary = state.requireValue.summaries;
    final history = state.requireValue.history;
    final summaryOrigin = summary.projection.stamp?.origin;
    final summaryRef = summary.projection.header?.reference;
    final historyOrigin = history.projection.stamp?.origin;
    final historyRef = history.projection.header?.reference;
    _summaries.target(
      summaryOrigin == null || summaryRef == null
          ? null
          : (summaryOrigin, summaryRef),
      needed:
          !_manualReading.contains(StatisticsReadField.summaries) &&
          summaryOrigin != null &&
          _needsPage(summary.summaries, summaryOrigin),
    );
    _history.target(
      historyOrigin == null || historyRef == null
          ? null
          : (historyOrigin, historyRef),
      needed:
          !_manualReading.contains(StatisticsReadField.history) &&
          historyOrigin != null &&
          _needsPage(history.samples, historyOrigin),
    );
    _summaries.visible(_visible);
    _history.visible(_visible);
    if (_visible) {
      // Missing origin/ref requires the Repository's real bootstrap, not a fake
      // source identity. Reserve before publication so reentry cannot duplicate.
      final missing = [
        if ((summaryOrigin == null || summaryRef == null) &&
            !_bootstrapped.contains(StatisticsReadField.summaries))
          StatisticsReadField.summaries,
        if ((historyOrigin == null || historyRef == null) &&
            !_bootstrapped.contains(StatisticsReadField.history))
          StatisticsReadField.history,
      ];
      _bootstrapped.addAll(missing);
      for (final field in missing) {
        unawaited(
          Future<void>(() async {
            if (!_alive || !_visible) {
              _bootstrapped.remove(field);
              return;
            }
            await load(field);
          }),
        );
      }
    }
  }

  Future<void> load(StatisticsReadField field) async {
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        _manualReading.contains(field) ||
        (field == StatisticsReadField.summaries
            ? _summaries.reading
            : _history.reading)) {
      return;
    }
    final lifetime = _lifetime;
    final repository = _repository;
    _manualReading.add(field);
    _attach(
      lifetime,
    ); // Explicit read/retry can restore only missing UI observers.
    final beforeSummary = repository.summaries.value.projection;
    final beforeHistory = repository.history.value.projection;
    final summaryTarget =
        beforeSummary.stamp == null || beforeSummary.header == null
        ? null
        : (beforeSummary.stamp!.origin, beforeSummary.header!.reference);
    final historyTarget =
        beforeHistory.stamp == null || beforeHistory.header == null
        ? null
        : (beforeHistory.stamp!.origin, beforeHistory.header!.reference);
    StudioFailure? failure;
    var issued = false;
    _changed(field, null, true, true, lifetime);
    try {
      if (!_owns(lifetime) || !_visible) {
        _bootstrapped.remove(field);
        return;
      }
      issued = true;
      if (field == StatisticsReadField.summaries) {
        await repository.loadSummariesPage();
      } else {
        await repository.loadHistoryPage();
      }
      if (_owns(lifetime) && _visible) {
        state = AsyncData(
          state.requireValue.copyWith(
            summaries: repository.summaries.value,
            history: repository.history.value,
          ),
        );
      }
      if (_owns(lifetime)) _changed(field, null, true, false, lifetime);
    } on StudioFailure catch (error) {
      failure = error;
      if (_owns(lifetime) && _visible) {
        state = AsyncData(
          state.requireValue.copyWith(
            summaries: repository.summaries.value,
            history: repository.history.value,
          ),
        );
      }
      if (_owns(lifetime)) _changed(field, error, true, false, lifetime);
    } finally {
      _manualReading.remove(field);
      if (_owns(lifetime)) {
        final summary = repository.summaries.value.projection;
        final history = repository.history.value.projection;
        if (issued && field == StatisticsReadField.summaries) {
          if (summaryTarget != null) {
            _summaries.remember(summaryTarget);
          } else if (failure != null &&
              summary.stamp != null &&
              summary.header != null &&
              displayCollection(repository.summaries.value.summaries)?.error ==
                  failure) {
            _summaries.remember((
              summary.stamp!.origin,
              summary.header!.reference,
            ));
          }
        }
        if (issued && field == StatisticsReadField.history) {
          if (historyTarget != null) {
            _history.remember(historyTarget);
          } else if (failure != null &&
              history.stamp != null &&
              history.header != null &&
              displayCollection(repository.history.value.samples)?.error ==
                  failure) {
            _history.remember((
              history.stamp!.origin,
              history.header!.reference,
            ));
          }
        }
        state = AsyncData(
          state.requireValue.copyWith(
            reading: {...state.requireValue.reading}..remove(field),
          ),
        );
        _refresh();
      }
    }
  }

  List<PerformanceSummary> get summaryRows =>
      displayCollectionRows(state.requireValue.summaries.summaries);
  List<PerformanceSample> get allHistory =>
      displayCollectionRows(state.requireValue.history.samples);
  List<PerformanceSample> get filteredHistory {
    final value = state.requireValue;
    return [
      for (final sample in allHistory)
        if ((value.modelFilter == null ||
                value.modelFilter ==
                    StatisticsModelKey(
                      accountId: sample.identity.accountId,
                      modelId: sample.identity.modelId,
                    )) &&
            (value.effortFilter == null ||
                value.effortFilter!.value == sample.identity.effort) &&
            (!value.mismatchesOnly ||
                sample.identity.modelMatchState == ModelMatchState.mismatched))
          sample,
    ];
  }

  List<StatisticsModelOption> get modelOptions {
    final options = <StatisticsModelKey, StatisticsModelOption>{};
    for (final sample in allHistory) {
      final identity = sample.identity;
      final key = StatisticsModelKey(
        accountId: identity.accountId,
        modelId: identity.modelId,
      );
      options.putIfAbsent(
        key,
        () => StatisticsModelOption(
          key: key,
          accountDisplayName: identity.accountDisplayName,
          displayModel: identity.modelId ?? identity.sentModel ?? '',
        ),
      );
    }
    for (final summary in summaryRows) {
      final identity = summary.identity;
      final key = StatisticsModelKey(
        accountId: identity.accountId,
        modelId: identity.modelId,
      );
      options.putIfAbsent(
        key,
        () => StatisticsModelOption(
          key: key,
          accountDisplayName: identity.accountDisplayName,
          displayModel: identity.modelId,
        ),
      );
    }
    return options.values.toList();
  }

  List<StatisticsEffortFilter> get effortOptions => {
    for (final sample in allHistory)
      StatisticsEffortFilter(value: sample.identity.effort),
  }.toList();
  void setModel(StatisticsModelKey? value) {
    if (_alive && state.asData != null) {
      state = AsyncData(state.requireValue.copyWith(modelFilter: value));
    }
  }

  void setEffort(StatisticsEffortFilter? value) {
    if (_alive && state.asData != null) {
      state = AsyncData(state.requireValue.copyWith(effortFilter: value));
    }
  }

  void setMismatchesOnly(bool value) {
    if (_alive && state.asData != null) {
      state = AsyncData(state.requireValue.copyWith(mismatchesOnly: value));
    }
  }

  void _pruneFilters() {
    final value = state.requireValue;
    final summariesComplete = collectionComplete(
      value.summaries.summaries,
      value.summaries.projection.stamp?.origin,
    );
    final historyComplete = collectionComplete(
      value.history.samples,
      value.history.projection.stamp?.origin,
    );
    // A bounded page missing a selected identity does not prove its deletion.
    if (summariesComplete &&
        historyComplete &&
        value.modelFilter != null &&
        !modelOptions.any((option) => option.key == value.modelFilter)) {
      setModel(null);
    }
    if (historyComplete &&
        value.effortFilter != null &&
        !effortOptions.contains(value.effortFilter)) {
      setEffort(null);
    }
  }
}
