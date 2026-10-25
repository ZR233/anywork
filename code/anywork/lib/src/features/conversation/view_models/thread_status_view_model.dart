import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../presentation/model_route_presentation.dart';
import '../state/read_material.dart';
import '../state/thread_status_state.dart';
import 'activity_wait_reader.dart';
import 'read_scope_borrow.dart';
import 'detail_demand.dart';
import 'read_validation.dart';
import 'scoped_read_presenter.dart';
import 'session_facet_observer.dart';
import 'status_read_fields.dart';

part 'thread_status_view_model.g.dart';

@riverpod
class ThreadStatusViewModel extends _$ThreadStatusViewModel {
  late SessionFacetObserver<ThreadExecutionState> _execution;
  late SessionFacetObserver<ThreadConfigurationState> _configuration;
  late SessionFacetObserver<ThreadAuthoringState> _authoring;
  ScopedReadPresenter<
    ActivityReadScope,
    ActivityReadHeader,
    IndexedActivityToolReadItem
  >?
  _activity;
  ScopedReadPresenter<StorageReadScope, StorageReadHeader, Never>? _storage;
  ScopedReadPresenter<
    ThreadConfigurationReadScope,
    ThreadConfigurationReadHeader,
    SkillNameReadItem
  >?
  _config;
  ScopedReadPresenter<WorkflowReadScope, WorkflowReadHeader, Never>? _workflow;
  ScopedReadPresenter<TurnReadScope, TurnReadHeader, Never>? _turn;
  final Map<int?, ActivityWaitReader> _waitReaders = {};
  int _activityEpoch = 0,
      _storageEpoch = 0,
      _configEpoch = 0,
      _workflowEpoch = 0,
      _turnEpoch = 0;
  int _executionBinding = 0, _configurationBinding = 0, _authoringBinding = 0;
  ThreadFacetStamp? _workflowOrigin;
  late DetailDemand _detailDemand;
  int _modelRouteDemands = 0;
  ({int epoch, Future<void> work})? _modelRouteRead;
  void Function() beginDetailsDemand() => _detailDemand.begin();

  void Function() beginModelRouteDemand() {
    _modelRouteDemands++;
    loadModelRoute().ignore();
    var ended = false;
    return () {
      if (ended) return;
      ended = true;
      _modelRouteDemands--;
    };
  }

  @override
  FutureOr<ThreadStatusViewState> build(String threadId) {
    final repository = ref.read(conversationRepositoryProvider);
    _detailDemand = DetailDemand(setDetailsVisible);
    _execution = SessionFacetObserver<ThreadExecutionState>(
      repository: repository,
      threadId: threadId,
      source: (s) => s.execution,
      onValue: _executionChanged,
    );
    _configuration = SessionFacetObserver<ThreadConfigurationState>(
      repository: repository,
      threadId: threadId,
      source: (s) => s.configuration,
      onValue: _configurationChanged,
    );
    _authoring = SessionFacetObserver<ThreadAuthoringState>(
      repository: repository,
      threadId: threadId,
      source: (s) => s.authoring,
      onValue: _authoringChanged,
    );
    _workflowOrigin = _authoring.value?.stamp;
    _executionBinding = _execution.generation;
    _configurationBinding = _configuration.generation;
    _authoringBinding = _authoring.generation;
    ref.onDispose(() {
      _detailDemand.seal();
      _execution.cancel();
      _configuration.cancel();
      _authoring.cancel();
      _activity?.retire();
      _storage?.retire();
      _config?.retire();
      _workflow?.retire();
      _turn?.retire();
      _retireWaitReaders();
    });
    scheduleMicrotask(() {
      if (ref.mounted) {
        loadActivity();
        loadWorkflow();
      }
    });
    return ThreadStatusViewState(
      threadId: threadId,
      execution: _execution.value,
      configuration: _configuration.value,
      workflow: _authoring.value?.value?.workflow,
    );
  }

  void _executionChanged(ThreadExecutionState next) {
    if (!ref.mounted || !state.hasValue) return;
    final before = state.requireValue;
    final replaced =
        _executionBinding != _execution.generation ||
        before.execution?.stamp?.incarnation != next.stamp?.incarnation ||
        before.execution?.stamp?.runtimeEpoch != next.stamp?.runtimeEpoch;
    _executionBinding = _execution.generation;
    final activityChanged =
        replaced ||
        before.execution?.value?.activity?.reference !=
            next.value?.activity?.reference;
    final storageChanged =
        replaced ||
        before.execution?.value?.storage?.reference !=
            next.value?.storage?.reference;
    final turnChanged =
        replaced || _turnRef(before.execution) != _turnRef(next);
    if (activityChanged) {
      _retireWaitReaders();
      _activity?.retire();
      _activity = null;
      _activityEpoch++;
    }
    if (storageChanged) {
      _storage?.retire();
      _storage = null;
      _storageEpoch++;
    }
    if (turnChanged) {
      _turn?.retire();
      _turn = null;
      _turnEpoch++;
    }
    state = AsyncData(
      before.copyWith(
        execution: next,
        activityRead: activityChanged
            ? const ReadMaterial()
            : before.activityRead,
        latestWaitTargets: activityChanged ? null : before.latestWaitTargets,
        waitTargetsByTool: activityChanged
            ? const {}
            : before.waitTargetsByTool,
        storageRead: storageChanged ? const ReadMaterial() : before.storageRead,
        turnRead: turnChanged ? const ReadMaterial() : before.turnRead,
      ),
    );
    if (activityChanged) loadActivity();
    if (before.detailsVisible) {
      if (storageChanged) loadStorage();
      if (turnChanged) loadTurn();
    }
  }

  TurnReadRef? _turnRef(ThreadExecutionState? source) =>
      (source?.value?.activeTurn ?? source?.value?.recentTerminalTurn)
          ?.reference;

  void _configurationChanged(ThreadConfigurationState next) {
    if (!ref.mounted || !state.hasValue) return;
    final before = state.requireValue;
    final changed =
        _configurationBinding != _configuration.generation ||
        before.configuration?.value?.details != next.value?.details ||
        before.configuration?.stamp?.incarnation != next.stamp?.incarnation ||
        before.configuration?.stamp?.runtimeEpoch != next.stamp?.runtimeEpoch;
    _configurationBinding = _configuration.generation;
    if (changed) {
      _config?.retire();
      _config = null;
      _configEpoch++;
    }
    state = AsyncData(
      before.copyWith(
        configuration: next,
        configurationRead: changed
            ? const ReadMaterial()
            : before.configurationRead,
      ),
    );
    if (changed && _modelRouteDemands > 0) {
      loadModelRoute().ignore();
    } else if (changed && before.detailsVisible) {
      loadConfiguration();
    }
  }

  void _authoringChanged(ThreadAuthoringState next) {
    if (!ref.mounted || !state.hasValue) return;
    final workflow = next.value?.workflow;
    final before = state.requireValue;
    final changed =
        _authoringBinding != _authoring.generation ||
        before.workflow != workflow ||
        _workflowOrigin?.incarnation != next.stamp?.incarnation ||
        _workflowOrigin?.runtimeEpoch != next.stamp?.runtimeEpoch;
    _authoringBinding = _authoring.generation;
    _workflowOrigin = next.stamp;
    if (!changed) {
      return; // Plan/Todo updates do not materialize their contents here.
    }
    _workflow?.retire();
    _workflow = null;
    _workflowEpoch++;
    state = AsyncData(
      before.copyWith(workflow: workflow, workflowRead: const ReadMaterial()),
    );
    loadWorkflow();
  }

  void setDetailsVisible(bool visible) {
    if (!ref.mounted || !state.hasValue) return;
    state = AsyncData(state.requireValue.copyWith(detailsVisible: visible));
    if (visible) {
      if (state.requireValue.configurationRead.header == null) {
        loadConfiguration();
      }
      if (state.requireValue.storageRead.header == null) loadStorage();
      if (state.requireValue.turnRead.header == null) loadTurn();
    }
  }

  Future<void> loadActivity() {
    final value = state.requireValue;
    final session = _execution.session;
    final origin = value.execution?.stamp;
    final reference = value.execution?.value?.activity?.reference;
    if (session == null || origin == null || reference == null) {
      return Future<void>.value();
    }
    final epoch = _activityEpoch;
    final reader = _activity ??=
        ScopedReadPresenter<
          ActivityReadScope,
          ActivityReadHeader,
          IndexedActivityToolReadItem
        >(
          borrow: ReadScopeBorrow(
            open: () => session.openActivity(reference, origin: origin),
            requestClose: (s) => s.requestClose(),
            close: (s) => s.close(),
            retryCleanup: (s) => s.retryCleanup(),
          ),
          read: () => state.requireValue.activityRead,
          publish: (material) => state = AsyncData(
            state.requireValue.copyWith(activityRead: material),
          ),
          current: () =>
              ref.mounted &&
              _activityEpoch == epoch &&
              identical(_execution.session, session),
          header: (s) async {
            final h = await s.header();
            checkScopeOrigin(h.scope, origin.runtimeEpoch, origin.incarnation);
            if (h.revision != reference.revision) {
              throw readProtocol('activity-revision');
            }
            return h;
          },
          scopeOf: (h) => h.scope,
          headerTexts: activityHeaderTexts,
          total: (h) => h.activeCount,
          page: (s, offset) async {
            final p = await s.tools(offset: offset, limit: 32);
            return (
              scope: p.scope,
              offset: p.offset,
              total: p.total,
              items: p.items,
              nextOffset: p.nextOffset,
            );
          },
          itemTexts: activityToolTexts,
          indexOf: (i) => i.index,
          text: (s, field, offset) =>
              s.text(field, offset: offset, maxBytes: 65536),
        );
    return reader.load();
  }

  Future<void> loadStorage() {
    final value = state.requireValue;
    final session = _execution.session;
    final origin = value.execution?.stamp;
    final reference = value.execution?.value?.storage?.reference;
    if (!value.detailsVisible ||
        session == null ||
        origin == null ||
        reference == null) {
      return Future<void>.value();
    }
    final epoch = _storageEpoch;
    final reader = _storage ??=
        ScopedReadPresenter<StorageReadScope, StorageReadHeader, Never>(
          borrow: ReadScopeBorrow(
            open: () => session.openStorage(reference, origin: origin),
            requestClose: (s) => s.requestClose(),
            close: (s) => s.close(),
            retryCleanup: (s) => s.retryCleanup(),
          ),
          read: () => state.requireValue.storageRead,
          publish: (m) =>
              state = AsyncData(state.requireValue.copyWith(storageRead: m)),
          current: () =>
              ref.mounted &&
              epoch == _storageEpoch &&
              identical(_execution.session, session),
          header: (s) async {
            final h = await s.header();
            checkScopeOrigin(h.scope, origin.runtimeEpoch, origin.incarnation);
            return h;
          },
          scopeOf: (h) => h.scope,
          headerTexts: (h) => [?h.lastError],
          text: (s, field, offset) =>
              s.text(field, offset: offset, maxBytes: 65536),
        );
    return reader.load();
  }

  Future<void> loadConfiguration() {
    // A rebuild may dispose this notifier while an earlier configuration load is
    // still pending; that load must stop instead of reading a dead Ref.
    if (!ref.mounted || !state.hasValue) return Future<void>.value();
    final value = state.requireValue;
    final session = _configuration.session;
    final origin = value.configuration?.stamp;
    final reference = value.configuration?.value?.details;
    if ((!value.detailsVisible && _modelRouteDemands == 0) ||
        session == null ||
        origin == null ||
        reference == null) {
      return Future<void>.value();
    }
    final epoch = _configEpoch;
    final reader = _config ??=
        ScopedReadPresenter<
          ThreadConfigurationReadScope,
          ThreadConfigurationReadHeader,
          SkillNameReadItem
        >(
          borrow: ReadScopeBorrow(
            open: () => session.openConfiguration(reference, origin: origin),
            requestClose: (s) => s.requestClose(),
            close: (s) => s.close(),
            retryCleanup: (s) => s.retryCleanup(),
          ),
          read: () => state.requireValue.configurationRead,
          publish: (m) => state = AsyncData(
            state.requireValue.copyWith(configurationRead: m),
          ),
          current: () =>
              ref.mounted &&
              epoch == _configEpoch &&
              identical(_configuration.session, session),
          header: (s) async {
            final h = await s.header();
            checkScopeOrigin(h.scope, origin.runtimeEpoch, origin.incarnation);
            if (h.route?.revision !=
                value.configuration?.value?.modelRoute?.revision) {
              throw readProtocol('model-route-revision');
            }
            return h;
          },
          scopeOf: (h) => h.scope,
          headerTexts: configurationHeaderTexts,
          total: (h) => h.activeSkillCount,
          page: (s, offset) async {
            final p = await s.activeSkills(offset: offset, limit: 32);
            return (
              scope: p.scope,
              offset: p.offset,
              total: p.total,
              items: p.items,
              nextOffset: p.nextOffset,
            );
          },
          itemTexts: (i) => [i.name],
          indexOf: (i) => i.index,
          text: (s, field, offset) =>
              s.text(field, offset: offset, maxBytes: 65536),
        );
    return reader.load();
  }

  /// Visible input demand materializes just the original route's named texts.
  /// It borrows the status reader, not a second config scope or a latest query.
  Future<void> loadModelRoute() {
    if (!ref.mounted || !state.hasValue || _modelRouteDemands == 0) {
      return Future<void>.value();
    }
    final epoch = _configEpoch;
    final running = _modelRouteRead;
    if (running?.epoch == epoch) return running!.work;
    final done = Completer<void>();
    _modelRouteRead = (epoch: epoch, work: done.future);
    bool current() =>
        ref.mounted &&
        state.hasValue &&
        _configEpoch == epoch &&
        _modelRouteDemands > 0;
    Future<void>(() async {
      try {
        await loadConfiguration();
        if (!current()) return;
        final header = state.requireValue.configurationRead.header;
        if (header == null) return;
        for (final text in configurationHeaderTexts(
          header,
        ).whereType<DeferredReadText>()) {
          while (current()) {
            final before = state.requireValue.configurationRead;
            final progress = before.texts[text.fieldId];
            if (before.error != null || progress == null || progress.complete) {
              break;
            }
            await loadConfigurationText(text.fieldId);
            if (!current()) return;
            final after =
                state.requireValue.configurationRead.texts[text.fieldId];
            if (after == null ||
                after.loadedUtf8Bytes == progress.loadedUtf8Bytes) {
              break;
            }
          }
        }
      } on StudioFailure catch (error) {
        if (current()) {
          state = AsyncData(
            state.requireValue.copyWith(
              configurationRead: state.requireValue.configurationRead.copyWith(
                error: error,
              ),
            ),
          );
        }
      } finally {
        if (identical(_modelRouteRead?.work, done.future)) {
          _modelRouteRead = null;
        }
        done.complete();
      }
    });
    return done.future;
  }

  ConversationModelRouteProps modelRouteProps(ThreadMetadataState? metadata) {
    final view = state.requireValue;
    final thread = currentRouteThread(metadata, threadId);
    final route = currentModelRoute(view);
    final blocked = modelRouteEditBlock(view, thread, route);
    return (
      source: (
        runtimeEpoch: view.configuration?.stamp?.runtimeEpoch,
        incarnation: view.configuration?.stamp?.incarnation,
        generation: _configuration.generation,
      ),
      thread: thread,
      route: route,
      blocked: blocked,
      reading: view.configurationRead.loading,
      error:
          metadata?.readError ??
          metadata?.projection.sync.error ??
          view.configuration?.sync.error ??
          view.execution?.sync.error ??
          view.configurationRead.error,
    );
  }

  /// Capture the concrete sources rendered by this control, never look up a
  /// replacement Session by ID when a menu callback eventually runs.
  ThreadModelRouteWriter? captureModelRouteWriter(
    ThreadMetadataState? metadata,
  ) {
    final props = modelRouteProps(metadata);
    final configuration = _configuration.capture();
    final execution = _execution.capture();
    if (props.blocked != null ||
        configuration == null ||
        execution == null ||
        !identical(configuration.session, execution.session) ||
        !_configuration.matches(configuration, requireActive: true) ||
        !_execution.matches(execution, requireActive: true)) {
      return null;
    }
    final shown = configuration.source.value;
    final shownOrigin = shown.stamp;
    final shownReference = shown.value?.details;
    return (selection) {
      if (!ref.mounted ||
          !state.hasValue ||
          !_configuration.matches(configuration, requireActive: true) ||
          !_execution.matches(execution, requireActive: true)) {
        throw _routeSourceChanged;
      }
      final current = configuration.source.value;
      final origin = current.stamp;
      final route = currentModelRoute(state.requireValue);
      if (current != state.requireValue.configuration ||
          execution.source.value != state.requireValue.execution ||
          origin == null ||
          origin.runtimeEpoch != shownOrigin?.runtimeEpoch ||
          origin.incarnation != shownOrigin?.incarnation ||
          current.value?.details != shownReference ||
          route == null ||
          modelRouteEditBlock(state.requireValue, props.thread, route) !=
              null) {
        throw _routeSourceChanged;
      }
      final settings = ref.read(configurationRepositoryProvider).state.value;
      final settingsRevision =
          settings.projection.header?.configurationRevision;
      if (settings.projection.sync.phase != ResourceSyncPhase.ready ||
          settingsRevision == null ||
          settings.projection.stamp?.origin.ownerEpoch != origin.runtimeEpoch) {
        throw const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'The canonical settings revision is not available.',
          retryable: true,
          correlationId: 'model-route-settings-unavailable',
        );
      }
      // Native registration freezes OperationId too, before this stack yields.
      return configuration.session.setThreadModelRoute(
        origin: origin,
        accountId: selection.model.accountId,
        modelId: selection.model.modelId,
        effort: selection.effort,
        expectedModelRouteRevision: route.revision,
        expectedSettingsRevision: settingsRevision,
      );
    };
  }

  static const _routeSourceChanged = StudioFailure(
    code: StudioFailureCode.conflict,
    message: 'The original model route source is no longer editable. Retry explicitly from the current source.',
    retryable: true,
    correlationId: 'model-route-source-changed',
  );

  Future<void> retryModelRouteRead() async {
    final binding = _configuration.capture();
    if (binding == null) return;
    try {
      if (binding.source.value.sync.phase != FacetSyncPhase.ready) {
        await binding.session.retry(ThreadFacet.configuration);
      }
      if (ref.mounted && _configuration.matches(binding)) {
        await loadModelRoute();
      }
    } on StudioFailure catch (error) {
      if (ref.mounted && state.hasValue && _configuration.matches(binding)) {
        state = AsyncData(
          state.requireValue.copyWith(
            configurationRead: state.requireValue.configurationRead.copyWith(
              error: error,
            ),
          ),
        );
      }
    }
  }

  Future<void> loadWorkflow() {
    final value = state.requireValue;
    final session = _authoring.session;
    final origin = _workflowOrigin;
    final reference = value.workflow?.reference;
    if (session == null || origin == null || reference == null) {
      return Future<void>.value();
    }
    final epoch = _workflowEpoch;
    final reader = _workflow ??=
        ScopedReadPresenter<WorkflowReadScope, WorkflowReadHeader, Never>(
          borrow: ReadScopeBorrow(
            open: () => session.openWorkflow(reference, origin: origin),
            requestClose: (s) => s.requestClose(),
            close: (s) => s.close(),
            retryCleanup: (s) => s.retryCleanup(),
          ),
          read: () => state.requireValue.workflowRead,
          publish: (m) =>
              state = AsyncData(state.requireValue.copyWith(workflowRead: m)),
          current: () =>
              ref.mounted &&
              epoch == _workflowEpoch &&
              identical(_authoring.session, session),
          header: (s) async {
            final h = await s.header();
            checkScopeOrigin(h.scope, origin.runtimeEpoch, origin.incarnation);
            return h;
          },
          scopeOf: (h) => h.scope,
          headerTexts: workflowHeaderTexts,
          text: (s, field, offset) =>
              s.text(field, offset: offset, maxBytes: 65536),
        );
    return reader.load();
  }

  Future<void> loadTurn() {
    final value = state.requireValue;
    final session = _execution.session;
    final origin = value.execution?.stamp;
    final reference = _turnRef(value.execution);
    if (!value.detailsVisible ||
        session == null ||
        origin == null ||
        reference == null) {
      return Future<void>.value();
    }
    final epoch = _turnEpoch;
    final reader = _turn ??=
        ScopedReadPresenter<TurnReadScope, TurnReadHeader, Never>(
          borrow: ReadScopeBorrow(
            open: () => session.openTurn(reference, origin: origin),
            requestClose: (s) => s.requestClose(),
            close: (s) => s.close(),
            retryCleanup: (s) => s.retryCleanup(),
          ),
          read: () => state.requireValue.turnRead,
          publish: (m) =>
              state = AsyncData(state.requireValue.copyWith(turnRead: m)),
          current: () =>
              ref.mounted &&
              epoch == _turnEpoch &&
              identical(_execution.session, session),
          header: (s) async {
            final h = await s.header();
            checkScopeOrigin(h.scope, origin.runtimeEpoch, origin.incarnation);
            return h;
          },
          scopeOf: (h) => h.scope,
          headerTexts: turnHeaderTexts,
          text: (s, field, offset) =>
              s.text(field, offset: offset, maxBytes: 65536),
        );
    return reader.load();
  }

  Future<void> loadActivityText(int field) =>
      _activity?.loadText(field) ?? Future<void>.value();

  void _retireWaitReaders() {
    for (final reader in _waitReaders.values) {
      reader.retire();
    }
    _waitReaders.clear();
  }

  /// null denotes latestStarted's dedicated page. It is deliberately not
  /// translated to any active-tool index, even if their labels happen to match.
  Future<void> loadWaitTargets(int? toolIndex) {
    final value = state.requireValue;
    final activity = _activity;
    final header = value.activityRead.header;
    if (!value.detailsVisible ||
        activity == null ||
        !activity.active ||
        header == null) {
      return Future<void>.value();
    }
    WaitReadValue? wait;
    if (toolIndex == null) {
      wait = header.latestStarted?.wait;
    } else {
      for (final tool in value.activityRead.items) {
        if (tool.index == toolIndex) {
          wait = tool.wait;
          break;
        }
      }
    }
    if (wait?.intent case EventsWaitReadIntent(:final targetCount)) {
      if (targetCount < 0) {
        state = AsyncData(
          value.copyWith(
            activityRead: value.activityRead.copyWith(
              error: readProtocol('wait-target-count'),
            ),
          ),
        );
        return Future<void>.value();
      }
      final epoch = _activityEpoch;
      final reader = _waitReaders[toolIndex] ??= ActivityWaitReader(
        scope: header.scope,
        total: targetCount,
        read: () => toolIndex == null
            ? state.requireValue.latestWaitTargets!
            : state.requireValue.waitTargetsByTool[toolIndex]!,
        publish: (material) => _publishWaitTargets(toolIndex, material),
        current: () =>
            ref.mounted &&
            epoch == _activityEpoch &&
            identical(_activity, activity) &&
            activity.active,
        page: (offset) => activity.query(
          (scope) => toolIndex == null
              ? scope.latestWaitTargets(offset: offset, limit: 32)
              : scope.waitTargets(toolIndex, offset: offset, limit: 32),
        ),
        text: (field, offset) => activity.query(
          (scope) => scope.text(field, offset: offset, maxBytes: 65536),
        ),
      );
      final material = toolIndex == null
          ? value.latestWaitTargets
          : value.waitTargetsByTool[toolIndex];
      if (material == null) {
        _publishWaitTargets(
          toolIndex,
          ReadMaterial(header: wait, nextOffset: targetCount == 0 ? null : 0),
        );
      }
      return reader.load();
    }
    return Future<void>.value();
  }

  void _publishWaitTargets(
    int? toolIndex,
    ReadMaterial<WaitReadValue, WaitTargetReadItem> material,
  ) {
    final before = state.requireValue;
    state = AsyncData(
      toolIndex == null
          ? before.copyWith(latestWaitTargets: material)
          : before.copyWith(
              waitTargetsByTool: {
                ...before.waitTargetsByTool,
                toolIndex: material,
              },
            ),
    );
  }

  Future<void> loadWaitTargetText(int? toolIndex, int field) =>
      _waitReaders[toolIndex]?.loadText(field) ?? Future<void>.value();
  Future<void> loadStorageText(int field) =>
      _storage?.loadText(field) ?? Future<void>.value();
  Future<void> loadConfigurationText(int field) =>
      _config?.loadText(field) ?? Future<void>.value();
  Future<void> loadWorkflowText(int field) =>
      _workflow?.loadText(field) ?? Future<void>.value();
  Future<void> loadTurnText(int field) =>
      _turn?.loadText(field) ?? Future<void>.value();
}
