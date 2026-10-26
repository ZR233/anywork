import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/statistics.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../state/statistics_view_state.dart';

part 'statistics_view_model.g.dart';

/// Owns the statistics page's visibility demand, its observation and its
/// filters. Every collection, page and read identity stays inside the
/// Repository; this ViewModel never pages, merges or fabricates a snapshot.
@riverpod
class StatisticsViewModel extends _$StatisticsViewModel {
  late StatisticsRepository _repository;
  Observation? _observation;
  StatisticsVisibilityLease? _lease;
  Future<void>? _retrying;
  bool _alive = true;
  bool _visible = false;
  int _lifetime = 0;

  @override
  Future<StatisticsViewState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _repository = ref.watch(statisticsRepositoryProvider);
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
      _retrying = null;
      tab.unregister();
      _releaseDemand();
      _detach();
      // Statistics are read-only: this page never closes the Repository and
      // never cancels an accepted notification or transform.
    });
    // Registration is synchronous, so the first projection already shows the
    // mirror's current value. A hidden build creates no demand.
    _attach(lifetime);
    final repository = _repository;
    // Everything this build may still return exists before the first wait, so a
    // dispose/rebuild during it never reads ref, state or a newer repository.
    final initial = _derive(repository.state.value);
    if (!_visible) return initial;
    _acquireDemand(lifetime);
    if (!_current(lifetime) || _lease == null) return initial;
    try {
      await repository.synchronize();
    } on StudioFailure {
      // The attempt failure is already published as the mirror's `sync` value,
      // so the page shows the real error in its own light status area and
      // retries through the Repository's read-only recovery. Nothing is
      // fabricated here, and the original attempt/owner keeps its duty.
    }
    if (!_current(lifetime)) return initial;
    return _derive(repository.state.value);
  }

  bool _current(int lifetime) => _alive && lifetime == _lifetime;

  void _attach(int lifetime) {
    if (_observation != null || !_alive) return;
    _observation = _repository.state.watchLatest((source) {
      if (!_current(lifetime)) return;
      _publish(source);
    }).observation;
  }

  void _detach() {
    _observation?.cancel();
    _observation = null;
  }

  void _releaseDemand() {
    final lease = _lease;
    _lease = null;
    lease?.release();
  }

  /// Registers the visible demand before any notification can observe it, and
  /// releases the just-acquired lease when a reentrant dispose/hide invalidates
  /// this attempt. No timer, delay or deferred retry is involved.
  void _acquireDemand(int lifetime) {
    if (_lease != null || !_visible || !_current(lifetime)) return;
    final StatisticsVisibilityLease lease;
    try {
      lease = _repository.acquireVisibleDemand();
    } on StudioFailure {
      // A sealed Repository grants no new demand; the last known snapshot
      // stays published and no second attempt masks the original duty.
      return;
    }
    _lease = lease;
    if (_current(lifetime) && _visible) return;
    if (identical(_lease, lease)) _lease = null;
    lease.release();
  }

  /// Publishing is guarded: a page that is loading or already failed never
  /// resurrects itself from a late notification.
  void _publish(StatisticsState source) {
    if (!_alive || state.asData == null) return;
    state = AsyncData(_derive(source));
  }

  void setVisible(bool visible) {
    if (!_alive || _visible == visible) return;
    _visible = visible;
    final lifetime = _lifetime;
    if (!visible) {
      _releaseDemand();
      _detach();
    } else {
      _attach(lifetime);
      _acquireDemand(lifetime);
      if (_lease != null) unawaited(_synchronize(lifetime));
    }
    _publish(_repository.state.value);
  }

  /// Awaits one complete publication of the current attempt. A failure keeps
  /// the last complete snapshot; the failure itself stays in the mirror's
  /// `sync` value and is presented by the page's light status area.
  Future<void> _synchronize(int lifetime) async {
    final repository = _repository;
    try {
      await repository.synchronize();
    } on StudioFailure {
      // Keep last good content, scroll and filters; the published failure is
      // visible through the mirror and still offers the real retry.
    }
    if (!_current(lifetime) || !identical(repository, _repository)) return;
    _publish(repository.state.value);
  }

  /// The one explicit recovery of a failed attempt: a read-only re-sync of the
  /// original owner, never a business reload and never a provider rebuild. An
  /// in-flight retry is joined instead of opening a second one.
  void retrySync() {
    if (!_alive || !_visible || _lease == null || _retrying != null) return;
    final lifetime = _lifetime;
    late final Future<void> retrying;
    retrying = _retry(lifetime).whenComplete(() {
      if (identical(_retrying, retrying)) _retrying = null;
    });
    _retrying = retrying;
    unawaited(retrying);
  }

  Future<void> _retry(int lifetime) async {
    final repository = _repository;
    try {
      await repository.retrySync();
    } on StudioFailure {
      // The Repository republishes the real failure and keeps the unresolved
      // cleanup responsibility; the page shows that same error.
    }
    if (!_current(lifetime) || !identical(repository, _repository)) return;
    _publish(repository.state.value);
  }

  void selectModel(StatisticsModelKey? value) {
    final current = state.asData?.value;
    if (!_alive || current == null || current.modelFilter == value) return;
    state = AsyncData(_filtered(current.copyWith(modelFilter: value)));
  }

  void selectEffort(StatisticsEffortFilter? value) {
    final current = state.asData?.value;
    if (!_alive || current == null || current.effortFilter == value) return;
    state = AsyncData(_filtered(current.copyWith(effortFilter: value)));
  }

  void setMismatchesOnly(bool value) {
    final current = state.asData?.value;
    if (!_alive || current == null || current.mismatchesOnly == value) return;
    state = AsyncData(_filtered(current.copyWith(mismatchesOnly: value)));
  }

  StatisticsViewState _derive(StatisticsState source) {
    final current = state.asData?.value;
    final snapshot = source.snapshot;
    final summaries = snapshot?.summaries ?? const <PerformanceSummary>[];
    final history = snapshot?.history ?? const <PerformanceSample>[];
    final modelOptions = List<StatisticsModelOption>.unmodifiable(
      _modelOptions(summaries, history),
    );
    final effortOptions = List<StatisticsEffortFilter>.unmodifiable(
      _effortOptions(history),
    );
    var modelFilter = current?.modelFilter;
    var effortFilter = current?.effortFilter;
    // A bounded page or a last-good value never proves an identity is gone: only
    // a complete authoritative snapshot prunes a selected filter.
    if (snapshot != null) {
      if (modelFilter != null &&
          !modelOptions.any((option) => option.key == modelFilter)) {
        modelFilter = null;
      }
      if (effortFilter != null && !effortOptions.contains(effortFilter)) {
        effortFilter = null;
      }
    }
    return _filtered(
      StatisticsViewState(
        source: source,
        visible: _visible,
        modelFilter: modelFilter,
        effortFilter: effortFilter,
        mismatchesOnly: current?.mismatchesOnly ?? false,
        modelOptions: modelOptions,
        effortOptions: effortOptions,
      ),
    );
  }

  StatisticsViewState _filtered(StatisticsViewState value) {
    final history =
        value.source.snapshot?.history ?? const <PerformanceSample>[];
    final model = value.modelFilter;
    final effort = value.effortFilter;
    final mismatchesOnly = value.mismatchesOnly;
    return value.copyWith(
      filteredHistory: List<PerformanceSample>.unmodifiable([
        for (final sample in history)
          if ((model == null ||
                  model ==
                      _keyOf(
                        sample.identity.accountId,
                        sample.identity.modelId,
                      )) &&
              (effort == null || effort.value == sample.identity.effort) &&
              (!mismatchesOnly ||
                  sample.identity.modelMatchState ==
                      ModelMatchState.mismatched))
            sample,
      ]),
    );
  }

  /// History identities first (they are the frozen call facts), then the
  /// aggregates the owner published for the same account model.
  List<StatisticsModelOption> _modelOptions(
    List<PerformanceSummary> summaries,
    List<PerformanceSample> history,
  ) {
    final options = <StatisticsModelKey, StatisticsModelOption>{};
    for (final sample in history) {
      final identity = sample.identity;
      final key = _keyOf(identity.accountId, identity.modelId);
      options.putIfAbsent(
        key,
        () => StatisticsModelOption(
          key: key,
          accountDisplayName: identity.accountDisplayName,
          displayModel: identity.modelId ?? identity.sentModel ?? '',
        ),
      );
    }
    for (final summary in summaries) {
      final identity = summary.identity;
      final key = _keyOf(identity.accountId, identity.modelId);
      options.putIfAbsent(
        key,
        () => StatisticsModelOption(
          key: key,
          accountDisplayName: identity.accountDisplayName,
          displayModel: identity.modelId,
        ),
      );
    }
    return options.values.toList(growable: false);
  }

  static List<StatisticsEffortFilter> _effortOptions(
    List<PerformanceSample> history,
  ) => {
    for (final sample in history)
      StatisticsEffortFilter(value: sample.identity.effort),
  }.toList(growable: false);

  static StatisticsModelKey _keyOf(String accountId, String? modelId) =>
      StatisticsModelKey(accountId: accountId, modelId: modelId);
}
