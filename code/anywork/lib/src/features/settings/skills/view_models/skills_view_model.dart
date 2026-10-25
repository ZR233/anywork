import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/skills.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/skills_view_state.dart';
import 'active_skill_names_read.dart';

part 'skills_view_model.g.dart';

@riverpod
class SkillsViewModel extends _$SkillsViewModel {
  late SkillsRepository _repository;
  ActiveSkillNamesRead? _active;
  CloseReport? _activeCleanup;
  List<StudioFailure> _activeCleanupErrors = [];
  late String _projectId;
  ProjectSkillsQuery? _query;
  Observation? _sourceObservation;
  Observation? _operation;
  VisibleReadDemand<(ProductReadOrigin, SkillsReadRef)>? _catalog;
  VisibleReadDemand<(ProductReadOrigin, SkillsReadRef)>? _warnings;
  VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)>? _status;
  final _retired = <ProjectSkillsQuery, CloseReport?>{};
  final _cleanupErrors = <ProjectSkillsQuery, StudioFailure>{};
  Timer? _searchTimer;
  bool _alive = true;
  bool _visible = false;
  bool _refreshing = false;
  bool _bootstrapAttempted = false;
  int _lifetime = 0;
  int _queryGeneration = 0;
  int _searchGeneration = 0;
  int _intent = 0;

  @override
  Future<SkillsViewState> build(String projectId) async {
    _alive = true;
    _projectId = projectId;
    final lifetime = ++_lifetime;
    _repository = ref.watch(skillsRepositoryProvider);
    final tab = ref
        .read(settingsNavigationViewModelProvider.notifier)
        .register(
          SettingsTab.skills,
          SettingsTabLifecycle(visibility: setVisible),
        );
    _visible = tab.visible;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      _searchGeneration++;
      tab.unregister();
      _searchTimer?.cancel();
      _sourceObservation?.cancel();
      _operation?.cancel();
      _disposeDemands();
      _active?.dispose(); // No business cancellation or fake query join here.
    });
    if (!_visible) {
      // 无可见业务需求时不创建 native Skills feed，也不占用 read-model permit；
      // 以 typed failure 表达"尚不具备观察前提"，不伪造 Idle 或空集合。
      // 可见性变化后由 setVisible 重新构建本 VM。
      throw const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Skills 观察需要可见的设置分页需求',
        correlationId: '',
        retryable: false,
      );
    }
    _active = ActiveSkillNamesRead(
      projectId: projectId,
      conversations: ref.watch(conversationRepositoryProvider),
      workspace: ref.watch(workspaceRepositoryProvider),
      cleanupErrorsChanged: (errors) {
        if (_owns(lifetime)) {
          _activeCleanupErrors = errors;
          _publishCleanup();
        }
      },
      changed: (names, error, reading, cleanup) {
        if (!_owns(lifetime)) return;
        if (cleanup != null) {
          _activeCleanup = cleanup;
          _publishCleanup();
          return;
        }
        state = AsyncData(state.requireValue.copyWith(activeNames: names));
        _changed(SkillsReadField.activeNames, error, true, reading);
      },
    );
    final query = _openQuery(lifetime);
    Future<void>(() {
      if (!_owns(lifetime) || _query == null) return;
      state = AsyncData(
        state.requireValue.copyWith(source: _query!.state.value),
      );
      _refreshDemands();
      _active?.visible(_visible);
    });
    return SkillsViewState(projectId: projectId, source: query.state.value);
  }

  bool _owns(int lifetime) =>
      _alive && lifetime == _lifetime && state.asData != null;
  bool get isVisible => _visible;
  bool _ownsQuery(int lifetime, int generation, ProjectSkillsQuery query) =>
      _owns(lifetime) &&
      generation == _queryGeneration &&
      identical(_query, query);

  ProjectSkillsQuery _openQuery(int lifetime) {
    final query = _repository.project(_projectId);
    _query = query;
    final generation = ++_queryGeneration;
    _bootstrapAttempted = false;
    void changed(
      SkillsReadField field,
      StudioFailure? error,
      bool current,
      bool reading,
    ) {
      if (_ownsQuery(lifetime, generation, query)) {
        _changed(field, error, current, reading);
      }
    }

    _catalog = VisibleReadDemand(
      read: (target) async {
        final source = query.state.value.projection;
        if (source.stamp?.origin == target.$1 &&
            source.header?.reference == target.$2) {
          await query.loadSkillsPage();
        }
      },
      changed: (target, error, current) => changed(
        SkillsReadField.catalog,
        error,
        current,
        _catalog?.reading ?? false,
      ),
    );
    _warnings = VisibleReadDemand(
      read: (target) async {
        final source = query.state.value.projection;
        if (source.stamp?.origin == target.$1 &&
            source.header?.reference == target.$2) {
          await query.loadWarnings();
        }
      },
      changed: (target, error, current) => changed(
        SkillsReadField.warnings,
        error,
        current,
        _warnings?.reading ?? false,
      ),
    );
    _status = VisibleReadDemand(
      read: (target) async {
        final source = query.state.value.projection;
        if (source.stamp?.origin == target.$1 &&
            source.header?.source.status == target.$2) {
          await query.loadSourceStatus();
        }
      },
      changed: (target, error, current) => changed(
        SkillsReadField.sourceStatus,
        error,
        current,
        _status?.reading ?? false,
      ),
    );
    // A Skills source can publish while another provider is still building;
    // Riverpod forbids mutating this provider during that build, so the
    // publication is deferred to one microtask that writes the last value.
    SkillsState? pendingSource;
    var sourceScheduled = false;
    void publishSource(SkillsState source) {
      if (!_ownsQuery(lifetime, generation, query) || state.asData == null) {
        return;
      }
      pendingSource = source;
      if (sourceScheduled) return;
      sourceScheduled = true;
      scheduleMicrotask(() {
        sourceScheduled = false;
        final next = pendingSource;
        pendingSource = null;
        if (!_ownsQuery(lifetime, generation, query) || next == null) return;
        final current = state.asData?.value;
        if (current == null) return;
        final changedCatalog =
            next.projection.stamp?.origin !=
                current.source.projection.stamp?.origin ||
            next.projection.header?.catalogRevision !=
                current.source.projection.header?.catalogRevision;
        final changedOrigin =
            next.projection.stamp?.origin !=
            current.source.projection.stamp?.origin;
        state = AsyncData(
          current.copyWith(
            source: next,
            readIssues: changedOrigin ? {} : current.readIssues,
          ),
        );
        if (changedCatalog) _scheduleSearch();
        _refreshDemands();
      });
    }

    try {
      _sourceObservation = query.state.watchLatest(publishSource).observation;
    } on StudioFailure {
      query.requestClose();
      _query = null;
      _disposeDemands();
      unawaited(_closeQuery(query));
      rethrow;
    }
    final source = query.state.value;
    if (failedReadIdentity(source.warnings) case final target?) {
      _warnings?.remember(target);
    }
    if (failedReadIdentity(source.sourceStatus) case final target?) {
      _status?.remember(target);
    }
    if (displayCollection(source.skills)?.error != null &&
        source.projection.stamp != null &&
        source.projection.header?.reference != null) {
      _catalog?.remember((
        source.projection.stamp!.origin,
        source.projection.header!.reference!,
      ));
    }
    return query;
  }

  void _disposeDemands() {
    _catalog?.dispose();
    _warnings?.dispose();
    _status?.dispose();
  }

  void setVisible(bool visible) {
    if (!_alive || _visible == visible) return;
    _visible = visible;
    _active?.visible(visible);
    if (!visible) {
      _searchTimer?.cancel();
      _searchGeneration++;
      _sourceObservation?.cancel();
      _sourceObservation = null;
      _disposeDemands();
      final query = _query;
      _query = null;
      _queryGeneration++;
      if (query != null) {
        query.requestClose();
        unawaited(_closeQuery(query));
      }
      if (state.asData != null) {
        state = AsyncData(
          state.requireValue.copyWith(searching: false, reading: {}),
        );
      }
    } else if (state.asData != null) {
      final query = _openQuery(_lifetime);
      state = AsyncData(
        state.requireValue.copyWith(
          source: query.state.value,
          readIssues: {},
          reading: {},
        ),
      );
      _refreshDemands();
      _scheduleSearch();
    } else {
      // 之前因无可见需求而未建立观察（build 抛 typed failure）：可见后重新构建。
      ref.invalidateSelf();
    }
  }

  Future<void> _closeQuery(
    ProjectSkillsQuery query, {
    bool retry = false,
  }) async {
    final previous = _retired[query];
    final issues = previous?.unresolved
        .expand((resource) => resource.issues)
        .toList();
    if (retry &&
        issues != null &&
        issues.every((issue) => issue.recovery == CleanupRecovery.terminal)) {
      return;
    }
    final retryClose =
        retry &&
        issues != null &&
        issues.any((issue) => issue.recovery == CleanupRecovery.retryClose);
    _retired.putIfAbsent(query, () => null);
    try {
      final report = await (retryClose ? query.retryCleanup() : query.close());
      _cleanupErrors.remove(query);
      if (report.complete) {
        _retired.remove(query);
      } else {
        _retired[query] = report;
      }
    } on StudioFailure catch (error) {
      _cleanupErrors[query] = error;
    }
    _publishCleanup();
  }

  void _publishCleanup() {
    if (_alive && state.asData != null) {
      state = AsyncData(
        state.requireValue.copyWith(
          cleanupErrors: [..._cleanupErrors.values, ..._activeCleanupErrors],
          cleanupReports: [
            for (final value in _retired.values) ?value,
            if (_activeCleanup case final report?)
              if (!report.complete) report,
          ],
        ),
      );
    }
  }

  void _changed(
    SkillsReadField field,
    StudioFailure? error,
    bool current,
    bool reading,
  ) {
    if (!_alive || state.asData == null) return;
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
        readIssues: issues,
        reading: {...state.requireValue.reading}
          ..remove(field)
          ..addAll(reading ? [field] : []),
      ),
    );
  }

  void _refreshDemands() {
    if (!_alive || state.asData == null || _query == null) return;
    final source = state.requireValue.source;
    final origin = source.projection.stamp?.origin;
    final reference = source.projection.header?.reference;
    final status = source.projection.header?.source.status;
    final window = displayCollection(source.skills);
    final needsCatalog =
        source.skills is! CurrentCollectionMirror<SkillSummary> ||
        window == null ||
        window.origin != origin ||
        window.entries.isEmpty && !window.complete ||
        window.entries.any((reference) {
          final row = window.rows[reference.entry];
          return row is! ReadyReadValue<SkillSummary, ProductEntityRef> ||
              row.current.origin != origin ||
              row.current.reference != reference;
        });
    _catalog?.target(
      origin == null || reference == null ? null : (origin, reference),
      needed: !_refreshing && needsCatalog,
    );
    _warnings?.target(
      origin == null || reference == null ? null : (origin, reference),
      needed:
          !_refreshing && !isCurrentRead(source.warnings, reference, origin),
    );
    _status?.target(
      origin == null || status == null ? null : (origin, status),
      needed:
          !_refreshing && !isCurrentRead(source.sourceStatus, status, origin),
    );
    _catalog?.visible(_visible);
    _warnings?.visible(_visible);
    _status?.visible(_visible);
    if (_visible &&
        !_refreshing &&
        !_bootstrapAttempted &&
        (origin == null || reference == null)) {
      _bootstrapAttempted = true;
      unawaited(
        Future<void>(() async {
          if (_alive && _visible) {
            await refresh(retryActive: false, retryRetired: false);
          } else {
            _bootstrapAttempted = false;
          }
        }),
      );
    }
  }

  Future<void> refresh({
    bool retryActive = true,
    bool retryRetired = true,
  }) async {
    final query = _query;
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        query == null ||
        _refreshing ||
        (_catalog?.reading ?? false) ||
        (_warnings?.reading ?? false) ||
        (_status?.reading ?? false)) {
      return;
    }
    _refreshing = true;
    final lifetime = _lifetime;
    final generation = _queryGeneration;
    try {
      await Future.wait<void>([
        _read(
          SkillsReadField.catalog,
          query.loadSkillsPage,
          query,
          lifetime,
          generation,
        ),
        _read(
          SkillsReadField.warnings,
          query.loadWarnings,
          query,
          lifetime,
          generation,
        ),
        _read(
          SkillsReadField.sourceStatus,
          query.loadSourceStatus,
          query,
          lifetime,
          generation,
        ),
      ]);
      if (retryRetired) {
        for (final owner in List<ProjectSkillsQuery>.of(_retired.keys)) {
          await _closeQuery(owner, retry: true);
        }
      }
      if (retryActive && _ownsQuery(lifetime, generation, query) && _visible) {
        await _active?.retry();
      }
    } finally {
      _refreshing = false;
      if (_ownsQuery(lifetime, generation, query)) {
        final source = query.state.value;
        if (failedReadIdentity(source.warnings) case final target?) {
          _warnings?.remember(target);
        }
        if (failedReadIdentity(source.sourceStatus) case final target?) {
          _status?.remember(target);
        }
        if (displayCollection(source.skills)?.error != null &&
            source.projection.stamp != null &&
            source.projection.header?.reference != null) {
          _catalog?.remember((
            source.projection.stamp!.origin,
            source.projection.header!.reference!,
          ));
        }
      }
      if (_owns(lifetime)) _refreshDemands();
    }
  }

  Future<void> _read(
    SkillsReadField field,
    Future<void> Function() read,
    ProjectSkillsQuery query,
    int lifetime,
    int generation,
  ) async {
    if (!_visible || !_ownsQuery(lifetime, generation, query)) return;
    _changed(field, null, true, true);
    try {
      if (!_visible || !_ownsQuery(lifetime, generation, query)) return;
      await read();
      if (_ownsQuery(lifetime, generation, query)) {
        _changed(field, null, true, false);
      }
    } on StudioFailure catch (error) {
      if (_ownsQuery(lifetime, generation, query)) {
        _changed(field, error, true, false);
      }
    } finally {
      if (_ownsQuery(lifetime, generation, query)) {
        state = AsyncData(
          state.requireValue.copyWith(
            reading: {...state.requireValue.reading}..remove(field),
          ),
        );
      }
    }
  }

  Future<void> loadMore() async {
    final query = _query;
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        query == null ||
        _refreshing ||
        (_catalog?.reading ?? false) ||
        state.requireValue.reading.contains(SkillsReadField.catalog)) {
      return;
    }
    await _read(
      SkillsReadField.catalog,
      query.loadSkillsPage,
      query,
      _lifetime,
      _queryGeneration,
    );
  }

  void requestSearch(String raw) {
    final query = raw.trim();
    if (!_alive ||
        state.asData == null ||
        state.requireValue.searchQuery == query) {
      return;
    }
    state = AsyncData(state.requireValue.copyWith(searchQuery: query));
    _scheduleSearch();
  }

  void _scheduleSearch() {
    _searchTimer?.cancel();
    final generation = ++_searchGeneration;
    if (!_alive || state.asData == null) return;
    final query = state.requireValue.searchQuery;
    final revision =
        state.requireValue.source.projection.header?.catalogRevision;
    state = AsyncData(
      state.requireValue.copyWith(
        search: null,
        searchError: null,
        searchGeneration: generation,
        searching: _visible && query.isNotEmpty && revision != null,
      ),
    );
    if (!_visible || query.isEmpty || revision == null) return;
    final lifetime = _lifetime;
    final repository = _repository;
    final projectId = _projectId;
    _searchTimer = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(
        _search(repository, projectId, query, revision, lifetime, generation),
      ),
    );
  }

  Future<void> _search(
    SkillsRepository repository,
    String projectId,
    String query,
    int revision,
    int lifetime,
    int generation,
  ) async {
    bool owns() =>
        _owns(lifetime) &&
        _visible &&
        generation == _searchGeneration &&
        state.requireValue.source.projection.header?.catalogRevision ==
            revision;
    if (!owns()) return;
    try {
      final result = await repository.search(projectId, query);
      if (owns() &&
          result.projectId == projectId &&
          result.catalogRevision == revision) {
        state = AsyncData(
          state.requireValue.copyWith(search: result, searching: false),
        );
      }
    } on StudioFailure catch (error) {
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(searchError: error, searching: false),
        );
      }
    } finally {
      if (owns() && state.requireValue.searching) {
        state = AsyncData(state.requireValue.copyWith(searching: false));
      }
    }
  }

  Future<void> discover() async {
    if (!_alive ||
        !_visible ||
        state.asData == null ||
        (state.requireValue.discoverAction?.preventsResubmission ?? false)) {
      return;
    }
    final projectId = _projectId;
    final repository = _repository;
    final lifetime = _lifetime;
    final intent = ++_intent;
    state = AsyncData(
      state.requireValue.copyWith(
        discoverAction: SettingsAction(intent: intent, pending: true),
      ),
    );
    bool owns() =>
        _owns(lifetime) && state.requireValue.discoverAction?.intent == intent;
    if (!owns()) return;
    OperationTicket<SkillsReadTarget> ticket;
    try {
      ticket = repository.discover(projectId);
    } on StudioFailure catch (error) {
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(
            discoverAction: SettingsAction(
              intent: intent,
              outcome: SettingsActionOutcome.rejected,
              error: error,
            ),
          ),
        );
      }
      return;
    }
    StudioFailure? observationError;
    if (owns()) {
      _operation?.cancel();
      _operation = null;
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (owns()) {
            state = AsyncData(
              state.requireValue.copyWith(
                discoverAction: state.requireValue.discoverAction?.copyWith(
                  operation: operation,
                ),
              ),
            );
          }
        });
        if (owns()) {
          _operation = watch.observation;
        } else {
          watch.observation.cancel();
        }
      } on StudioFailure catch (error) {
        observationError = error;
      }
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(
            discoverAction: SettingsAction(
              intent: intent,
              pending: true,
              operation: ticket.state.value,
              observationError: observationError,
            ),
          ),
        );
      }
    }
    final result = await ticket.result;
    if (owns()) {
      state = AsyncData(
        state.requireValue.copyWith(
          discoverAction: settledSettingsAction(
            intent,
            result,
            operation: ticket.state.value,
          ).copyWith(observationError: observationError),
        ),
      );
    }
  }
}
