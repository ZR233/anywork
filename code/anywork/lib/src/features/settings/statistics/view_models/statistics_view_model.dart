import 'package:anywork_client/statistics.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../state/statistics_view_state.dart';
import 'statistics_repository_provider.dart';

part 'statistics_view_model.g.dart';

/// Owns statistics filters and their immutable presentation projection.
@riverpod
class StatisticsViewModel extends _$StatisticsViewModel {
  late StatisticsRepository _repository;
  StatisticsVisibilityLease? _visibleDemand;
  String? _modelFilter;
  String? _effortFilter;
  String? _serviceTierFilter;
  bool _mismatchesOnly = false;
  StatisticsSection _section = StatisticsSection.summaries;
  int _summaryPageIndex = 0;
  int _historyPageIndex = 0;
  StatisticsSnapshot? _reconciledSnapshot;
  StatisticsSnapshot? _filteredSnapshot;
  String? _filteredModel;
  String? _filteredEffort;
  String? _filteredServiceTier;
  bool _filteredMismatches = false;
  List<StatisticsSample> _filteredHistory = StatisticsMaterial.freeze(
    const <StatisticsSample>[],
  );

  @override
  StatisticsViewState build() {
    _repository = ref.watch(statisticsRepositoryProvider);
    final observation = _repository.observe(_repositoryChanged);
    ref.onDispose(() {
      _visibleDemand?.release();
      _visibleDemand = null;
      observation.cancel();
    });
    _reconcileFilters(observation.initialState);
    return _derive(observation.initialState);
  }

  void setVisible(bool visible) {
    if (visible) {
      _visibleDemand ??= _repository.acquireVisibleDemand();
      return;
    }
    _visibleDemand?.release();
    _visibleDemand = null;
  }

  void selectModel(String? filter) {
    if (_modelFilter == filter) return;
    _modelFilter = filter;
    _historyPageIndex = 0;
    _reconciledSnapshot = null;
    state = _derive(_repository.state);
  }

  void selectEffort(String? filter) {
    if (_effortFilter == filter) return;
    _effortFilter = filter;
    _historyPageIndex = 0;
    _reconciledSnapshot = null;
    state = _derive(_repository.state);
  }

  void setMismatchesOnly(bool value) {
    if (_mismatchesOnly == value) return;
    _mismatchesOnly = value;
    _historyPageIndex = 0;
    state = _derive(_repository.state);
  }

  void selectServiceTier(String? filter) {
    if (_serviceTierFilter == filter) return;
    _serviceTierFilter = filter;
    _historyPageIndex = 0;
    _reconciledSnapshot = null;
    state = _derive(_repository.state);
  }

  void refresh() => _repository.refresh();

  void selectSection(StatisticsSection section) {
    if (_section == section) return;
    _section = section;
    state = _derive(_repository.state);
  }

  void selectPage(int pageIndex) {
    final next = pageIndex.clamp(0, state.pageCount - 1);
    if (next == state.pageIndex) return;
    if (_section == StatisticsSection.summaries) {
      _summaryPageIndex = next;
    } else {
      _historyPageIndex = next;
    }
    state = _derive(_repository.state);
  }

  void _repositoryChanged(StatisticsRepositoryState next) {
    if (!ref.mounted) return;
    _reconcileFilters(next);
    state = _derive(next);
  }

  void _reconcileFilters(StatisticsRepositoryState source) {
    final snapshot = source.snapshot;
    // A filter is removed only after the current owner has published a complete authoritative
    // materialization. Last-good data during opening/partial failure is not proof of deletion.
    if (snapshot == null ||
        source.connection.phase != StatisticsConnectionPhase.ready) {
      return;
    }
    final previous = _reconciledSnapshot;
    if (previous != null &&
        previous.ownerEpoch == snapshot.ownerEpoch &&
        previous.feedId == snapshot.feedId &&
        previous.historyRevision == snapshot.historyRevision &&
        previous.summariesRevision == snapshot.summariesRevision &&
        identical(previous.history, snapshot.history) &&
        identical(previous.summaries, snapshot.summaries)) {
      return;
    }
    _reconciledSnapshot = snapshot;
    final modelFilter = _modelFilter;
    if (modelFilter != null &&
        !snapshot.history.any((item) => item.filterKey == modelFilter) &&
        !snapshot.summaries.any((item) => item.filterKey == modelFilter)) {
      _modelFilter = null;
    }
    final effortFilter = _effortFilter;
    if (effortFilter != null &&
        !snapshot.history.any((item) => item.effortKey == effortFilter)) {
      _effortFilter = null;
    }
    final serviceTierFilter = _serviceTierFilter;
    if (serviceTierFilter != null &&
        !snapshot.history.any(
          (item) => item.serviceTierKey == serviceTierFilter,
        )) {
      _serviceTierFilter = null;
    }
  }

  StatisticsViewState _derive(StatisticsRepositoryState repository) {
    final snapshot = repository.snapshot;
    final previous = _filteredSnapshot;
    final reuse =
        previous?.ownerEpoch == snapshot?.ownerEpoch &&
        previous?.feedId == snapshot?.feedId &&
        previous?.historyRevision == snapshot?.historyRevision &&
        identical(previous?.history, snapshot?.history) &&
        _filteredModel == _modelFilter &&
        _filteredEffort == _effortFilter &&
        _filteredServiceTier == _serviceTierFilter &&
        _filteredMismatches == _mismatchesOnly;
    if (!reuse) {
      final history = snapshot?.history ?? const <StatisticsSample>[];
      _filteredHistory =
          _modelFilter == null &&
              _effortFilter == null &&
              _serviceTierFilter == null &&
              !_mismatchesOnly
          ? StatisticsMaterial.freeze(history)
          : StatisticsMaterial.freeze(
              history.where(
                (item) =>
                    (_modelFilter == null || item.filterKey == _modelFilter) &&
                    (_effortFilter == null ||
                        item.effortKey == _effortFilter) &&
                    (_serviceTierFilter == null ||
                        item.serviceTierKey == _serviceTierFilter) &&
                    (!_mismatchesOnly ||
                        item.modelMatchState ==
                            StatisticsModelMatchState.mismatched),
              ),
            );
      _filteredSnapshot = snapshot;
      _filteredModel = _modelFilter;
      _filteredEffort = _effortFilter;
      _filteredServiceTier = _serviceTierFilter;
      _filteredMismatches = _mismatchesOnly;
    }
    _summaryPageIndex = _summaryPageIndex.clamp(
      0,
      StatisticsViewState.pagesFor(snapshot?.summaries.length ?? 0) - 1,
    );
    _historyPageIndex = _historyPageIndex.clamp(
      0,
      StatisticsViewState.pagesFor(_filteredHistory.length) - 1,
    );
    return StatisticsViewState(
      repository: repository,
      modelFilter: _modelFilter,
      effortFilter: _effortFilter,
      serviceTierFilter: _serviceTierFilter,
      mismatchesOnly: _mismatchesOnly,
      filteredHistory: _filteredHistory,
      section: _section,
      summaryPageIndex: _summaryPageIndex,
      historyPageIndex: _historyPageIndex,
    );
  }
}
