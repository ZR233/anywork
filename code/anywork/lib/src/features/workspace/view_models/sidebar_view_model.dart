import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../../../app/lifecycle/exit_participant.dart';
import '../state/collection_presentation.dart';
import '../state/sidebar_view_state.dart';

part 'sidebar_view_model.g.dart';

/// Presentation/query owner, not a directory reducer. Each borrowed query has
/// its own canonical window/cursor; the VM never merges rows or guesses EOF.
@Riverpod(keepAlive: true)
class SidebarViewModel extends _$SidebarViewModel
    implements ApplicationEditProducer {
  final Map<String, _SidebarQuery> _queries = {};
  final Map<String, Observation> _writeObservations = {};
  final List<Observation> _observations = [];
  Timer? _debounce;
  bool _alive = true;
  int _writeIntent = 0;
  (int, Future<void>)? _widthSave;
  Future<void>? _projectsRead;
  Future<void>? _projectSourceRead;
  Object? _projectSourceTarget;
  bool _projectSourceAgain = false;
  bool _initializing = false;
  int _bindingGeneration = 0;
  ApplicationEditRegistration? _editRegistration;

  @override
  FutureOr<SidebarViewState> build() {
    _alive = true;
    _initializing = true;
    ref.onDispose(_disposeBindings);
    try {
      final initial = _initialize();
      _initializing = false;
      return initial;
    } catch (error, stack) {
      _disposeBindings();
      Error.throwWithStackTrace(error, stack);
    }
  }

  SidebarViewState _initialize() {
    final workspace = ref.watch(workspaceRepositoryProvider);
    final configuration = ref.watch(configurationRepositoryProvider);
    final updates = ref.watch(updatesRepositoryProvider);
    _editRegistration = ref
        .watch(applicationEditProducerRegistryProvider)
        .register(this);
    final selection = workspace.state.watchLatest((workspace) {
      if (!_alive || _initializing) return;
      final previous = state.requireValue;
      final projectId = workspace.selection.projectId;
      state = AsyncData(
        previous.copyWith(
          workspace: workspace,
          expandedProjectIds: {
            ...previous.expandedProjectIds,
            // A restored target must not create a new metadata query demand.
            // Existing/manual expansion and explicit search remain independent.
            if (!workspace.selection.needsOpen && projectId != null) projectId,
          },
        ),
      );
      _syncQueries();
    });
    _observations.add(selection.observation);
    final projects = workspace.projects.watchLatest((projects) {
      if (!_alive || _initializing) return;
      final previousReference =
          state.requireValue.projects.projection.header?.source.status;
      state = AsyncData(state.requireValue.copyWith(projects: projects));
      // A project search depends on canonical Project names/paths as well as
      // thread metadata. D3 owns that source dependency and window updates.
      _syncQueries();
      if (projects.projection.header?.source.status != previousReference) {
        unawaited(loadProjectSourceStatus());
      }
    });
    _observations.add(projects.observation);
    // One coalescing scheduler for every canonical source this VM projects. A
    // source can publish while another provider is still building (for example
    // Settings reading the same configuration source). Riverpod forbids writing
    // this provider's state during that build, so publications are collected
    // per source and applied once, in a fixed order, from a microtask: several
    // ticks of one source keep only its last value, and distinct sources that
    // changed in the same tick are all applied.
    final pendingPublications =
        <_SidebarPublication, SidebarViewState Function(SidebarViewState)>{};
    var publicationsScheduled = false;
    void publish(
      _SidebarPublication source,
      SidebarViewState Function(SidebarViewState current) apply,
    ) {
      if (!_alive || _initializing) return;
      pendingPublications[source] = apply;
      if (publicationsScheduled) return;
      publicationsScheduled = true;
      final generation = _bindingGeneration;
      scheduleMicrotask(() {
        publicationsScheduled = false;
        final pending = Map.of(pendingPublications);
        pendingPublications.clear();
        // Publication is dropped once this binding generation is gone, so a
        // disposed or re-initialized VM never writes a stale value.
        if (!_alive || _initializing || _bindingGeneration != generation) {
          return;
        }
        final initial = state.asData?.value;
        if (initial == null) return;
        var next = initial;
        for (final source in _SidebarPublication.values) {
          final apply = pending[source];
          if (apply != null) next = apply(next);
        }
        state = AsyncData(next);
      });
    }

    final config = configuration.state.watchLatest(
      (value) => publish(
        _SidebarPublication.configuration,
        (current) => current.copyWith(configuration: value),
      ),
    );
    _observations.add(config.observation);
    final update = updates.state.watchLatest((value) {
      final brief = value.projection.header?.brief;
      publish(
        _SidebarPublication.updates,
        (current) => current.copyWith(updatesBrief: brief),
      );
    });
    _observations.add(update.observation);
    final currentSelection = workspace.state.value;
    final initial = SidebarViewState(
      workspace: currentSelection,
      projects: workspace.projects.value,
      configuration: configuration.state.value,
      updatesBrief: updates.state.value.projection.header?.brief,
      rawQuery: '',
      normalizedQuery: '',
      filter: DirectoryFilter.all,
      archived: false,
      expandedProjectIds: {
        if (currentSelection.selection case WorkspaceSelection(
          needsOpen: false,
          projectId: final id?,
        ))
          id,
      },
      queryGeneration: 0,
      pages: const {},
      widthDraft: null,
      widthIntent: 0,
      writes: const {},
      preferencesReadError: null,
      projectsReadError: null,
      projectSourceReadError: null,
      sealed: false,
    );
    // Necessary reads are allowed; they are not activation or mutation. Defer
    // only until the synchronous AsyncNotifier build has installed its value.
    final bindingGeneration = _bindingGeneration;
    scheduleMicrotask(() {
      if (!_alive || _bindingGeneration != bindingGeneration) return;
      _syncQueries();
      unawaited(_readPreferences());
      unawaited(loadProjectsPage());
    });
    return initial;
  }

  void _disposeBindings() {
    _alive = false;
    ++_bindingGeneration;
    _projectsRead = null;
    _projectSourceRead = null;
    _projectSourceTarget = null;
    _projectSourceAgain = false;
    _widthSave = null;
    _editRegistration?.unregister();
    _editRegistration = null;
    _debounce?.cancel();
    for (final observation in [
      ..._observations,
      ..._writeObservations.values,
    ]) {
      observation.cancel();
    }
    _observations.clear();
    _writeObservations.clear();
    for (final query in _queries.values.toList()) {
      _retire(query);
    }
    _queries.clear();
  }

  Future<void> loadProjectsPage() {
    if (state.requireValue.sealed) return Future<void>.value();
    final existing = _projectsRead;
    if (existing != null) return existing;
    final completion = Completer<void>();
    final task = completion.future;
    _projectsRead = task;
    final generation = _bindingGeneration;
    unawaited(
      Future<void>.sync(() => _loadProjectsPage(generation))
          .then(completion.complete, onError: completion.completeError),
    );
    return task.whenComplete(() {
      if (identical(_projectsRead, task)) _projectsRead = null;
    });
  }

  Future<void> _loadProjectsPage(int generation) async {
    try {
      await ref.read(workspaceRepositoryProvider).loadProjectsPage();
      if (!_alive || generation != _bindingGeneration) return;
      state = AsyncData(state.requireValue.copyWith(projectsReadError: null));
      await loadProjectSourceStatus();
    } on StudioFailure catch (error) {
      if (_alive && generation == _bindingGeneration) {
        state = AsyncData(
          state.requireValue.copyWith(projectsReadError: error),
        );
      }
    }
  }

  Future<void> loadProjectSourceStatus() {
    if (!_alive || state.requireValue.sealed) return Future<void>.value();
    final projection = state.requireValue.projects.projection;
    final target = (projection.stamp?.origin, projection.header?.source.status);
    final existing = _projectSourceRead;
    if (existing != null) {
      _projectSourceAgain = _projectSourceTarget != target;
      return existing;
    }
    final completion = Completer<void>();
    final task = completion.future;
    _projectSourceRead = task;
    _projectSourceTarget = target;
    final generation = _bindingGeneration;
    unawaited(
      Future<void>.sync(() => _loadProjectSourceStatus(generation))
          .then(completion.complete, onError: completion.completeError),
    );
    return task.whenComplete(() {
      if (!identical(_projectSourceRead, task)) return;
      _projectSourceRead = null;
      _projectSourceTarget = null;
      final again = _projectSourceAgain;
      _projectSourceAgain = false;
      if (_alive && again && generation == _bindingGeneration) {
        scheduleMicrotask(() {
          if (_alive && generation == _bindingGeneration) {
            unawaited(loadProjectSourceStatus());
          }
        });
      }
    });
  }

  Future<void> _loadProjectSourceStatus(int generation) async {
    try {
      await ref.read(workspaceRepositoryProvider).loadProjectSourceStatus();
      if (_alive && generation == _bindingGeneration) {
        state = AsyncData(
          state.requireValue.copyWith(projectSourceReadError: null),
        );
      }
    } on StudioFailure catch (error) {
      if (_alive && generation == _bindingGeneration) {
        state = AsyncData(
          state.requireValue.copyWith(projectSourceReadError: error),
        );
      }
    }
  }

  Future<void> _readPreferences() async {
    final generation = _bindingGeneration;
    try {
      await ref.read(configurationRepositoryProvider).loadGeneralSettings();
      if (_alive && generation == _bindingGeneration) {
        state = AsyncData(
          state.requireValue.copyWith(preferencesReadError: null),
        );
      }
    } on StudioFailure catch (error) {
      if (_alive && generation == _bindingGeneration) {
        state = AsyncData(
          state.requireValue.copyWith(preferencesReadError: error),
        );
      }
    }
  }

  void changeQuery(String raw) {
    if (state.requireValue.sealed) return;
    final next = state.requireValue.copyWith(
      rawQuery: raw,
      normalizedQuery: raw.trim(),
    );
    _replaceQuery(next, debounce: true);
  }

  void changeFilter(DirectoryFilter filter) {
    if (state.requireValue.sealed) return;
    _replaceQuery(state.requireValue.copyWith(filter: filter), debounce: false);
  }

  void toggleArchived() {
    if (state.requireValue.sealed) return;
    final previous = state.requireValue;
    _replaceQuery(
      previous.copyWith(archived: !previous.archived),
      debounce: false,
    );
  }

  void _replaceQuery(SidebarViewState next, {required bool debounce}) {
    _debounce?.cancel();
    for (final query in _queries.values.toList()) {
      _retire(query);
    }
    _queries.clear();
    state = AsyncData(
      next.copyWith(
        queryGeneration: state.requireValue.queryGeneration + 1,
        pages: const {},
      ),
    );
    if (debounce) {
      _debounce = Timer(const Duration(milliseconds: 200), () {
        _debounce = null;
        _syncQueries();
      });
    } else {
      _syncQueries();
    }
  }

  void toggleExpanded(String projectId) {
    final previous = state.requireValue;
    if (previous.sealed) return;
    final expanded = {...previous.expandedProjectIds};
    if (!expanded.remove(projectId)) expanded.add(projectId);
    state = AsyncData(previous.copyWith(expandedProjectIds: expanded));
    _syncQueries();
  }

  void _syncQueries() {
    if (!_alive || state.requireValue.sealed) return;
    if (_debounce?.isActive == true) return;
    _debounce = null;
    final current = state.requireValue;
    final filtered =
        current.normalizedQuery.isNotEmpty ||
        current.filter != DirectoryFilter.all ||
        current.archived;
    final desired = {
      for (final project in presentRows(current.projects.projects))
        if (filtered || current.expandedProjectIds.contains(project.id))
          project.id,
    };
    for (final id in _queries.keys.toList()) {
      if (desired.contains(id)) continue;
      _retire(_queries.remove(id)!);
      final pages = {...state.requireValue.pages}..remove(id);
      state = AsyncData(state.requireValue.copyWith(pages: pages));
    }
    for (final id in desired) {
      if (_queries.containsKey(id)) continue;
      final query = DirectoryQuery(
        projectId: id,
        search: current.normalizedQuery.isEmpty
            ? null
            : current.normalizedQuery,
        filter: current.filter,
        archived: current.archived,
      );
      _SidebarQuery? created;
      try {
        final borrowed = ref
            .read(workspaceRepositoryProvider)
            .queryThreads(query);
        final binding = _SidebarQuery(borrowed, current.queryGeneration);
        created = binding;
        // Publish admission before subscribing: callbacks capture this exact
        // borrow, not merely projectId or a later A→B→A query string.
        _queries[id] = binding;
        final watched = borrowed.state.watchLatest((directory) {
          if (!_currentQuery(id, binding)) return;
          _setPage(
            id,
            SidebarProjectPage(
              generation: binding.generation,
              query: query,
              directory: directory,
              demandError: null,
            ),
          );
        });
        binding.observation = watched.observation;
        _setPage(
          id,
          SidebarProjectPage(
            generation: binding.generation,
            query: query,
            directory: watched.value,
            demandError: null,
          ),
        );
        // Opening the read-only demand does not imply its first index page is
        // already materialized. Ask for exactly that bounded page explicitly.
        unawaited(_queryAction(id, retry: false));
      } on StudioFailure catch (error) {
        if (created != null && identical(_queries[id], created)) {
          _queries.remove(id);
          _retire(created);
        }
        _setPage(
          id,
          SidebarProjectPage(
            generation: current.queryGeneration,
            query: query,
            directory: null,
            demandError: error,
          ),
        );
      }
    }
  }

  bool _currentQuery(String projectId, _SidebarQuery binding) =>
      _alive &&
      identical(_queries[projectId], binding) &&
      state.requireValue.queryGeneration == binding.generation;

  void _setPage(String projectId, SidebarProjectPage page) {
    state = AsyncData(
      state.requireValue.copyWith(
        pages: {...state.requireValue.pages, projectId: page},
      ),
    );
  }

  void _retire(_SidebarQuery binding) {
    binding.observation?.cancel();
    try {
      binding.query.requestClose();
    } catch (error, stack) {
      _closeError(error, stack);
    }
    // The Repository retains the original query and its permit until real
    // cleanup. Removing the presentation binding is not release evidence.
    unawaited(
      Future<CloseReport>.sync(binding.query.close)
          .then<void>((_) {}, onError: _closeError),
    );
  }

  void _closeError(Object error, StackTrace stack) {
    final zone = Zone.current;
    scheduleMicrotask(() => zone.handleUncaughtError(error, stack));
  }

  Future<void> loadMore(String projectId) =>
      _queryAction(projectId, retry: false);
  Future<void> retry(String projectId) async {
    if (!_queries.containsKey(projectId)) {
      _syncQueries();
      return;
    }
    await _queryAction(projectId, retry: true);
  }

  Future<void> _queryAction(String projectId, {required bool retry}) async {
    final binding = _queries[projectId];
    if (binding == null || state.requireValue.sealed) return;
    try {
      await (retry ? binding.query.retry() : binding.query.loadMore());
    } on StudioFailure catch (error) {
      if (!_currentQuery(projectId, binding)) return;
      final previous = state.requireValue.pages[projectId];
      if (previous != null) {
        _setPage(projectId, previous.copyWith(demandError: error));
      }
    }
  }

  Future<void> toggleProjectPin(String id) => _togglePin(id, project: true);
  Future<void> toggleThreadPin(String id) => _togglePin(id, project: false);

  Future<void> _togglePin(String id, {required bool project}) async {
    if (state.requireValue.sealed) return;
    var general = state.requireValue.configuration.general;
    // A displayed last-known value is not current write input.
    if (general is! ReadyReadValue<GeneralSettings, ConfigurationReadRef>) {
      await _readPreferences();
      if (!_alive || state.requireValue.sealed) return;
      general = state.requireValue.configuration.general;
    }
    if (general is! ReadyReadValue<GeneralSettings, ConfigurationReadRef>) {
      return;
    }
    final ids = [
      ...(project
          ? general.current.value.pinnedProjectIds
          : general.current.value.pinnedThreadIds),
    ];
    if (ids.contains(id)) {
      ids.remove(id);
    } else {
      ids.add(id);
    }
    await _writePreference(
      project ? 'project-pins' : 'thread-pins',
      project
          ? SettingsFieldUpdate.generalPinnedProjectIds(value: ids)
          : SettingsFieldUpdate.generalPinnedThreadIds(value: ids),
    );
  }

  void changeWidth(double width) {
    final previous = state.requireValue;
    if (previous.sealed || !width.isFinite) return;
    state = AsyncData(
      previous.copyWith(
        widthDraft: width.clamp(300.0, 440.0).toDouble(),
        widthIntent: previous.widthIntent + 1,
      ),
    );
  }

  void resizeWidth(double delta, double displayedWidth, double maximumWidth) {
    final current = state.requireValue.widthDraft ?? displayedWidth;
    changeWidth((current + delta).clamp(300.0, maximumWidth).toDouble());
  }

  void cancelWidth() {
    final previous = state.requireValue;
    state = AsyncData(
      previous.copyWith(
        widthDraft: null,
        widthIntent: previous.widthIntent + 1,
      ),
    );
  }

  Future<void> commitWidth() {
    final previous = state.requireValue;
    final width = previous.widthDraft;
    if (width == null) return Future<void>.value();
    final existing = _widthSave;
    if (existing?.$1 == previous.widthIntent) return existing!.$2;
    final intent = previous.widthIntent;
    final generation = _bindingGeneration;
    final completion = Completer<void>();
    final task = completion.future;
    _widthSave = (intent, task);
    // Install completion before applyField can synchronously re-enter the app
    // producer barrier. Re-entrant commitWidth then shares this exact work.
    unawaited(
      Future<void>.sync(() => _saveWidth(width, intent, generation)).then(
        (_) {
          if (identical(_widthSave?.$2, task)) _widthSave = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_widthSave?.$2, task)) _widthSave = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return task;
  }

  Future<void> _saveWidth(double width, int intent, int generation) async {
    final success = await _writePreference(
      'sidebar-width',
      SettingsFieldUpdate.generalSidebarWidth(value: width.round()),
      allowQueued: true,
    );
    if (_alive &&
        success &&
        generation == _bindingGeneration &&
        state.requireValue.widthIntent == intent) {
      state = AsyncData(state.requireValue.copyWith(widthDraft: null));
    }
  }

  Future<bool> _writePreference(
    String key,
    SettingsFieldUpdate update, {
    bool allowQueued = false,
  }) async {
    final previous = state.requireValue;
    if (previous.sealed ||
        (!allowQueued && previous.writes[key]?.pending == true)) {
      return false;
    }
    final intent = ++_writeIntent;
    _writeObservations.remove(key)?.cancel();
    void publish(SidebarPreferenceWrite write) {
      if (!_alive) return;
      state = AsyncData(
        state.requireValue.copyWith(
          writes: {...state.requireValue.writes, key: write},
        ),
      );
    }

    bool current() =>
        _alive && state.requireValue.writes[key]?.intent == intent;
    publish(
      SidebarPreferenceWrite(
        intent: intent,
        pending: true,
        operation: null,
        admissionError: null,
      ),
    );
    try {
      final ticket = ref
          .read(configurationRepositoryProvider)
          .applyField(update);
      try {
        final watched = ticket.state.watchLatest((operation) {
          if (current()) {
            publish(
              state.requireValue.writes[key]!.copyWith(operation: operation),
            );
          }
        });
        if (current()) {
          _writeObservations[key] = watched.observation;
          publish(
            state.requireValue.writes[key]!.copyWith(operation: watched.value),
          );
        } else {
          watched.observation.cancel();
        }
      } on StudioFailure catch (error) {
        if (current()) {
          publish(
            state.requireValue.writes[key]!.copyWith(
              observationError: error,
              operation: ticket.state.value,
            ),
          );
        }
      }
      final result = await ticket.result;
      if (current()) {
        publish(
          state.requireValue.writes[key]!.copyWith(
            pending: false,
            operation: ticket.state.value,
          ),
        );
      }
      return result is CommittedCommandResult<Unit> ||
          result is AcknowledgedCommandResult<Unit>;
    } on StudioFailure catch (error) {
      if (current()) {
        publish(
          state.requireValue.writes[key]!.copyWith(
            pending: false,
            admissionError: error,
          ),
        );
      }
      return false;
    }
  }

  /// Called explicitly by the app producer barrier, never from ref.onDispose.
  /// The synchronous prefix of commitWidth admits a valid pending intent before
  /// the composition root seals ConfigurationRepository/Operations.
  void sealEdits() {
    if (state.requireValue.sealed) return;
    _debounce?.cancel();
    unawaited(commitWidth());
    state = AsyncData(state.requireValue.copyWith(sealed: true));
  }

  @override
  void sealAndHandoff() => sealEdits();
}

final class _SidebarQuery {
  _SidebarQuery(this.query, this.generation);
  final ThreadDirectoryQuery query;
  final int generation;
  Observation? observation;
}

/// Canonical sources projected into [SidebarViewState]. The declaration order is
/// also the publication order when several of them change within one tick.
enum _SidebarPublication { configuration, updates }
