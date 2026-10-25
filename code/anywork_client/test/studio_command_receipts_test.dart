import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class _ModeCall {
  _ModeCall(this.operationId, this.threadId, this.mode);
  final OperationId operationId;
  final String threadId;
  final ThreadModeId mode;
  final reply = Completer<ThreadModeCommandReply>();
}

final class _RouteCall {
  _RouteCall(
    this.operationId,
    this.threadId,
    this.modelId,
    this.expectedRouteRevision,
    this.expectedSettingsRevision,
  );
  final OperationId operationId;
  final String threadId;
  final String modelId;
  final int expectedRouteRevision;
  final int expectedSettingsRevision;
  final reply = Completer<ThreadModelRouteCommandReply>();
}

final class _StopCall {
  _StopCall(this.operationId, this.threadId, this.turnId);
  final OperationId operationId;
  final String threadId;
  final String turnId;
  final reply = Completer<InterruptTurnCommandReply>();
}

final class _InteractionCall {
  _InteractionCall(this.operationId, this.interactionId, this.resolution);
  final OperationId operationId;
  final String interactionId;
  final InteractionResolutionCommand resolution;
  final reply = Completer<InteractionCommandReply>();
}

/// Only the external owner response is controlled. Operation allocation,
/// command lanes, reducers, observation barriers and overlays are production.
final class _Transport implements StudioTransport {
  _Transport() {
    addTearDown(() => modes.close());
    addTearDown(() => routes.close());
    addTearDown(() => stops.close());
    addTearDown(() => interactions.close());
    addTearDown(() async {
      for (final sink in topicSinks) {
        await sink.close();
      }
    });
  }

  final modes = StreamController<_ModeCall>.broadcast();
  final routes = StreamController<_RouteCall>.broadcast();
  final stops = StreamController<_StopCall>.broadcast();
  final interactions = StreamController<_InteractionCall>.broadcast();
  final compactions = <Completer<void>>[];
  final List<StreamController<ProductTopicFrame>> topicSinks = [];

  @override
  Future<void> compactThread(String threadId) {
    expect(threadId, 'thread');
    final reply = Completer<void>();
    compactions.add(reply);
    return reply.future;
  }

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    final sink = StreamController<ProductTopicFrame>();
    addTearDown(() => sink.close());
    topicSinks.add(sink);
    return sink.stream;
  }

  @override
  Future<ThreadModeCommandReply> setThreadMode({
    required OperationId operationId,
    required String threadId,
    required ThreadModeId mode,
  }) {
    final call = _ModeCall(operationId, threadId, mode);
    modes.add(call);
    return call.reply.future;
  }

  @override
  Future<ThreadModelRouteCommandReply> setThreadModelRoute({
    required OperationId operationId,
    required String threadId,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
    required String accountId,
    required String modelId,
    String? effort,
  }) {
    final call = _RouteCall(
      operationId,
      threadId,
      modelId,
      expectedModelRouteRevision,
      expectedSettingsRevision,
    );
    routes.add(call);
    return call.reply.future;
  }

  @override
  Future<InterruptTurnCommandReply> interruptTurn(
    String threadId,
    String turnId, {
    required OperationId operationId,
  }) {
    final call = _StopCall(operationId, threadId, turnId);
    stops.add(call);
    return call.reply.future;
  }

  @override
  Future<InteractionCommandReply> respondInteraction(
    String interactionId,
    InteractionResolutionCommand resolution, {
    required OperationId operationId,
  }) {
    final call = _InteractionCall(operationId, interactionId, resolution);
    interactions.add(call);
    return call.reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}

final class _RouteConflictTransport extends _Transport {
  _RouteConflictTransport({this.onRuntimeCancel}) {
    addTearDown(() async {
      for (final binding in bindings) {
        await binding.close();
      }
    });
  }

  final List<StreamController<ThreadStreamFrame>> bindings = [];
  final Future<void> Function(int index)? onRuntimeCancel;
  final List<_RouteCall> attempts = [];
  final refreshEntered = Completer<void>();
  final window = _RouteConflictConnection();
  int windowOpens = 0;

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) {
    final index = bindings.length;
    final binding = StreamController<ThreadStreamFrame>(
      sync: true,
      onCancel: () => onRuntimeCancel?.call(index),
    );
    bindings.add(binding);
    if (bindings.length == 2 && !refreshEntered.isCompleted) {
      refreshEntered.complete();
    }
    return binding.stream;
  }

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) async {
    windowOpens++;
    return window;
  }

  @override
  Future<SettingsStateSnapshot> readSettingsState() async => _settings(2);

  @override
  Future<ThreadModelRouteCommandReply> setThreadModelRoute({
    required OperationId operationId,
    required String threadId,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
    required String accountId,
    required String modelId,
    String? effort,
  }) async {
    attempts.add(
      _RouteCall(
        operationId,
        threadId,
        modelId,
        expectedModelRouteRevision,
        expectedSettingsRevision,
      ),
    );
    if (attempts.length == 1) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'route changed at its owner',
        retryable: true,
        correlationId: 'route-conflict',
      );
    }
    return ThreadModelRouteCommandReply(
      runtime: _runtime(routeRevision: 4),
      settings: _settings(2),
      modeDefaultSaved: true,
      receipt: _receipt(operationId, [
        _stamp('thread-route:thread', 4),
        _stamp('settings', 2),
      ], disposition: CommitDisposition.noChange),
    );
  }
}

final class _RouteConflictConnection implements StudioTimelineConnection {
  Completer<StudioTimelineUpdate?>? _pending;
  bool _closed = false;
  int requestCloseCalls = 0;

  @override
  Future<StudioTimelineBaseline> initial() async =>
      const StudioTimelineBaseline(
        subscriptionId: 'route-conflict',
        version: 300,
        items: [],
        before: null,
        hasOlder: false,
      );

  @override
  Future<StudioTimelineUpdate?> next() {
    if (_closed) return Future.value(null);
    return (_pending ??= Completer<StudioTimelineUpdate?>()).future;
  }

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) => Future.value(
    const StudioTimelinePage(items: [], before: null, hasOlder: false),
  );

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) => Future.error(UnsupportedError('route test has no detail body'));

  @override
  void requestClose() {
    requestCloseCalls++;
    _closed = true;
    if (_pending case final pending? when !pending.isCompleted) {
      pending.complete(null);
    }
  }

  @override
  Future<void> close() async => requestClose();
}

const _epoch = 'native-runtime-one';
const _project = StudioProject(
  id: 'project',
  name: 'Project',
  path: '/project',
);

StudioThread _thread({ThreadModeId mode = ThreadModeId.simple}) => StudioThread(
  id: 'thread',
  projectId: 'project',
  title: 'Thread',
  mode: mode,
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/project',
);

ThreadRuntimeView _runtime({String modelId = 'alpha', int routeRevision = 1}) =>
    ThreadRuntimeView(
      modelId: modelId,
      contextTokens: 0,
      contextWindow: 100,
      totalTokens: 0,
      costLabel: '',
      activeSkills: const [],
      activeMcpServers: const [],
      activeLspServers: const [],
      modelRoute: ThreadModelRouteView(
        accountId: 'account',
        modelId: modelId,
        effort: 'medium',
        revision: routeRevision,
        available: true,
      ),
    );

ThreadWorkspace _workspace({
  int revision = 1,
  String modelId = 'alpha',
  int routeRevision = 1,
  StudioTurnView? activeTurn,
  List<PendingInteraction> interactions = const [],
}) => ThreadWorkspace(
  audience: const ThreadAudienceUnbound(),
  thread: _thread(),
  revision: revision,
  interactions: interactions,
  runtime: _runtime(modelId: modelId, routeRevision: routeRevision),
  activeTurn: activeTurn,
);

StudioTurnView _turn({bool completed = false, String turnId = 'turn'}) =>
    StudioTurnView(
      threadId: 'thread',
      turnId: turnId,
      revision: completed ? 2 : 1,
      state: completed
          ? const CompletedStudioTurnState(
              startedAt: 1,
              completedAt: 2,
              completion: StudioTurnCompletion.normal,
            )
          : const RunningStudioTurnState(
              startedAt: 1,
              activity: StudioTurnActivity.thinking,
            ),
      updatedAt: DateTime.utc(2026),
    );

PendingInteraction _interaction([String id = 'interaction']) =>
    PendingInteraction(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      kind: InteractionKind.userInput,
      title: 'Input',
      body: 'Choose an answer',
    );

const _resolution = UserInputResolutionCommand(
  answers: [
    UserInputAnswerCommand(questionId: 'question', answers: ['Continue']),
  ],
);

void _applyOwnerUpdate(AnyworkClient client, ThreadWorkspaceUpdate update) {
  final session = client.session('thread');
  session.applyNotification(
    ThreadNotificationFrame(
      threadId: 'thread',
      revision: session.state.revision + 1,
      baseRevision: session.state.revision,
      update: update,
    ),
  );
}

StudioCommandReceipt _identityReceipt(
  OperationId operationId, {
  CommitDisposition disposition = CommitDisposition.applied,
  bool effective = false,
}) => StudioCommandReceipt(
  operationId: operationId,
  disposition: disposition,
  targets: const [],
  effect: EffectPoint.immediate,
  effective: effective,
  durable: false,
  requiresIdentityObservation: true,
);

SettingsStateSnapshot _settings(int revision) => SettingsStateSnapshot(
  revision: revision,
  modelCatalogRevision: 1,
  accounts: const [
    AccountSettingsView(
      id: 'account',
      name: 'Provider',
      baseUrl: 'http://local.invalid',
      defaultModelId: 'alpha',
      status: 'configured',
      usageLabel: '',
      models: [
        AccountModelView(
          modelId: 'alpha',
          displayName: 'Alpha',
          reasoningEfforts: ['medium'],
        ),
        AccountModelView(
          modelId: 'beta',
          displayName: 'Beta',
          reasoningEfforts: ['medium'],
        ),
      ],
    ),
  ],
  modeModelRoutes: const [
    ModeModelRouteView(
      modeId: ThreadModeId.simple,
      accountId: 'account',
      modelId: 'alpha',
      effort: 'medium',
    ),
  ],
);

AnyworkClient _client(_Transport transport) {
  final client = AnyworkClient(transport: transport, clientId: 'client');
  client.applyBootstrap(
    StudioBootstrap(
      ownerEpoch: _epoch,
      projectDirectory: ProjectDirectoryState(values: [_project], revision: 1),
      threadDirectory: ThreadDirectoryWindow(threads: [_thread()], revision: 1),
      agentDirectory: AgentDirectoryState(revision: 1),
      settingsState: _settings(1),
      recoveryState: RecoveryStateSnapshot(revision: 1),
      mcpState: McpStateSnapshot(revision: 1),
      lspState: LspStateSnapshot(revision: 1),
      skillsByProject: const {},
      threadModeCatalog: const ThreadModeCatalogView(),
      accountUsageState: AccountUsageStateSnapshot(revision: 1),
      modelPerformance: const ModelPerformanceSnapshotView(),
      updaterState: DisabledUpdaterStateSnapshot(
        revision: 1,
        updatedAt: DateTime.utc(2026),
      ),
      persistenceState: const PersistenceStateSnapshot.ready(),
    ),
  );
  // The command has a stable selected identity; this test does not open a native
  // ChatView. State frames enter through the production read-model reducers.
  client.selection.restoreStartup(
    projectId: 'project',
    threadId: 'thread',
    needsOpen: true,
  );
  client.session('thread').applySnapshot(_workspace());
  addTearDown(client.close);
  return client;
}

ResourceStamp _stamp(String key, int revision) =>
    ResourceStamp(resourceKey: key, ownerEpoch: _epoch, revision: revision);

StudioCommandReceipt _receipt(
  OperationId id,
  List<ResourceStamp> targets, {
  CommitDisposition disposition = CommitDisposition.applied,
  EffectPoint effect = EffectPoint.immediate,
}) => StudioCommandReceipt(
  operationId: id,
  disposition: disposition,
  targets: targets,
  effect: effect,
  effective: effect == EffectPoint.immediate,
  durable: false,
);

void main() {
  test('manual compaction waits for its owner, rejects duplicate dispatch and exposes failure', () async {
    final transport = _Transport();
    final client = _client(transport);
    final pending = client.threadCommands.compactThread('thread');
    await Future<void>.delayed(Duration.zero);
    expect(
      client.threadCommands.state.commands['compact:thread']?.phase,
      CommandPhase.pending,
    );
    await expectLater(
      client.threadCommands.compactThread('thread'),
      throwsStateError,
    );
    expect(transport.compactions, hasLength(1));
    final failed = expectLater(pending, throwsStateError);
    transport.compactions.single.completeError(
      StateError('compression failed'),
    );
    await failed;
    expect(
      client.threadCommands.state.commands['compact:thread']?.phase,
      CommandPhase.failed,
    );
    final retry = client.threadCommands.compactThread('thread');
    await Future<void>.delayed(Duration.zero);
    expect(transport.compactions, hasLength(2));
    transport.compactions.last.complete();
    await retry;
    expect(
      client.threadCommands.state.commands,
      isNot(contains('compact:thread')),
    );
  });

  test('route conflict resync replaces only its runtime binding and preserves ChatView', () async {
    final transport = _RouteConflictTransport();
    final client = _client(transport);
    client.selection.markOpened();
    final session = client.existingSession('thread')!;
    transport.bindings.first.add(
      ThreadSnapshotFrame(
        workspace: _workspace(revision: 40, routeRevision: 2),
      ),
    );
    await session.timeline.ready;
    transport.bindings.first.add(
      ThreadNotificationFrame(
        threadId: 'thread',
        epoch: 1,
        baseRevision: 40,
        revision: 41,
        update: ThreadRuntimeUpdate(
          runtime: _runtime(routeRevision: 3),
          todo: null,
        ),
      ),
    );
    final changing = client.threadCommands.setThreadModelRoute(
      threadId: 'thread',
      accountId: 'account',
      modelId: 'alpha',
    );
    await transport.refreshEntered.future;
    expect(transport.bindings, hasLength(2));
    expect(session.state.revision, 41);
    expect(
      transport.attempts,
      hasLength(1),
      reason: 'await the replacement baseline',
    );
    transport.bindings.last.add(
      ThreadSnapshotFrame(workspace: _workspace(revision: 7, routeRevision: 4)),
    );
    await changing;
    expect(transport.attempts, hasLength(2));
    expect(
      transport.attempts.last.operationId,
      transport.attempts.first.operationId,
    );
    expect(transport.attempts.last.expectedRouteRevision, 4);
    expect(transport.attempts.last.expectedSettingsRevision, 2);
    transport.bindings.first.add(
      ThreadNotificationFrame(
        threadId: 'thread',
        epoch: 1,
        baseRevision: 41,
        revision: 42,
        update: ThreadRuntimeUpdate(
          runtime: _runtime(modelId: 'obsolete'),
          todo: null,
        ),
      ),
    );
    transport.bindings.last.add(
      ThreadNotificationFrame(
        threadId: 'thread',
        epoch: 1,
        baseRevision: 7,
        revision: 8,
        update: ThreadRuntimeUpdate(
          runtime: _runtime(routeRevision: 4),
          todo: null,
        ),
      ),
    );
    expect(session.state.revision, 8);
    expect(session.state.runtime!.modelId, 'alpha');
    expect(session.state.sync.phase, DomainSyncPhase.ready);
    final delivered = session.timeline.lastDeliveredFrame;
    expect((delivered! as StudioTimelineBaselineFrame).baseline.version, 300);
    expect(transport.windowOpens, 1);
    expect(transport.window.requestCloseCalls, 0);
  });

  for (final closeClient in [false, true]) {
    test(
      'route resync baseline wait ends on ${closeClient ? 'Client close' : 'Session retire'} while cleanup stays owned',
      () async {
        final cancelEntered = Completer<void>();
        final cleanup = Completer<void>();
        final transport = _RouteConflictTransport(
          onRuntimeCancel: (index) {
            if (index != 1) return Future.value();
            cancelEntered.complete();
            return cleanup.future;
          },
        );
        final client = _client(transport);
        addTearDown(() {
          if (!cleanup.isCompleted) cleanup.complete();
        });
        client.selection.markOpened();
        final session = client.existingSession('thread')!;
        transport.bindings.single.add(
          ThreadSnapshotFrame(
            workspace: _workspace(revision: 40, routeRevision: 3),
          ),
        );
        await session.timeline.ready;
        final changing = client.threadCommands.setThreadModelRoute(
          threadId: 'thread',
          accountId: 'account',
          modelId: 'alpha',
        );
        final rejected = expectLater(
          changing,
          throwsA(
            isA<StudioFailure>().having(
              (error) => error.code,
              'original conflict',
              StudioFailureCode.conflict,
            ),
          ),
        );
        await transport.refreshEntered.future;
        expect(transport.bindings, hasLength(2));
        expect(transport.attempts, hasLength(1));
        final closing = closeClient
            ? client.close()
            : session.retire(deadline: DateTime.utc(2000));
        await cancelEntered.future;
        await rejected;
        expect(
          transport.attempts,
          hasLength(1),
          reason: 'Retired observation cannot replay even a known conflict',
        );
        expect(
          client.budget.usage
              .where((resource) => resource.owner.startsWith('runtime:thread:'))
              .single
              .phase,
          ResourcePhase.retiring,
        );
        if (!closeClient) {
          final report = await closing;
          expect(report.complete, isFalse);
          expect(
            report.unresolved.map((resource) => resource.owner),
            contains('runtime:thread'),
          );
        }
        cleanup.complete();
        if (closeClient) {
          expect((await closing).complete, isTrue);
        } else {
          expect((await session.retryCleanup()).complete, isTrue);
        }
        expect(
          client.budget.usage.where(
            (resource) => resource.owner.startsWith('runtime:thread:'),
          ),
          isEmpty,
        );
      },
    );
  }

  test(
    'Client close owns a resync still joining its previous runtime binding',
    () async {
      final cancelEntered = Completer<void>();
      final cleanup = Completer<void>();
      final transport = _RouteConflictTransport(
        onRuntimeCancel: (index) {
          if (index != 0) return Future.value();
          cancelEntered.complete();
          return cleanup.future;
        },
      );
      final client = _client(transport);
      addTearDown(() {
        if (!cleanup.isCompleted) cleanup.complete();
      });
      client.selection.markOpened();
      final session = client.existingSession('thread')!;
      transport.bindings.single.add(
        ThreadSnapshotFrame(
          workspace: _workspace(revision: 40, routeRevision: 3),
        ),
      );
      await session.timeline.ready;
      final changing = client.threadCommands.setThreadModelRoute(
        threadId: 'thread',
        accountId: 'account',
        modelId: 'alpha',
      );
      final rejected = expectLater(changing, throwsA(isA<StudioFailure>()));
      await cancelEntered.future;
      expect(transport.bindings, hasLength(1));
      expect(transport.refreshEntered.isCompleted, isFalse);
      final closing = client.close();
      await rejected;
      expect(transport.attempts, hasLength(1));
      expect(
        client.budget.usage
            .where((resource) => resource.owner.startsWith('runtime:thread:'))
            .single
            .phase,
        ResourcePhase.retiring,
      );
      cleanup.complete();
      expect((await closing).complete, isTrue);
      expect(
        transport.bindings,
        hasLength(1),
        reason: 'close prevents replacement',
      );
      expect(
        client.budget.usage.where(
          (resource) => resource.owner.startsWith('runtime:thread:'),
        ),
        isEmpty,
      );
    },
  );

  for (final framesFirst in [false, true]) {
    for (final interrupted in [false, true]) {
      test(
        'actual stop waits for its captured Turn (framesFirst=$framesFirst, interrupted=$interrupted)',
        () async {
          final transport = _Transport();
          final client = _client(transport);
          client
              .session('thread')
              .applySnapshot(_workspace(activeTurn: _turn()));
          final baselineObservers = client.budget.used(ResourceKind.observer);
          final entered = transport.stops.stream.first;
          final stopping = client.threadCommands.stop('thread');
          final operation = client.mutations.latest('stop:thread')!;
          expect(
            operation.state.value.receipt,
            isNull,
            reason: 'The operation exists before the command first awaits',
          );
          final call = await entered;
          expect(call.operationId, operation.id);
          expect(call.threadId, 'thread');
          expect(call.turnId, 'turn');
          expect(
            client.budget.used(ResourceKind.observer),
            baselineObservers + 1,
          );
          client.selection.restoreStartup(
            projectId: 'project',
            threadId: 'another-thread',
            needsOpen: true,
          );
          if (framesFirst) {
            _applyOwnerUpdate(client, ThreadTurnUpdate(_turn(completed: true)));
          }
          call.reply.complete(
            InterruptTurnCommandReply(
              threadId: call.threadId,
              turnId: call.turnId,
              interrupted: interrupted,
              receipt: _identityReceipt(
                call.operationId,
                disposition: interrupted
                    ? CommitDisposition.applied
                    : CommitDisposition.noChange,
              ),
            ),
          );
          await stopping;
          expect(
            operation.state.value.receipt!.disposition,
            interrupted
                ? CommitDisposition.applied
                : CommitDisposition.noChange,
          );
          if (!framesFirst) {
            expect(
              operation.state.value.phase,
              OperationPhase.awaitingObservation,
            );
            expect(
              operation.state.value.effective,
              isFalse,
              reason: 'An interrupt request ACK does not prove the Turn ended',
            );
            expect(
              client.threadCommands.state.commands['stop:thread']?.phase,
              CommandPhase.pending,
            );
            _applyOwnerUpdate(
              client,
              ThreadRuntimeUpdate(runtime: _runtime(), todo: null),
            );
            expect(
              operation.state.value.observed,
              isFalse,
              reason: 'Unrelated owner facts do not confirm the captured Turn',
            );
            _applyOwnerUpdate(client, ThreadTurnUpdate(_turn(completed: true)));
          }
          expect(operation.state.value.observed, isTrue);
          expect(operation.state.value.effective, isTrue);
          expect(operation.state.value.durable, isFalse);
          expect(
            client.threadCommands.state.commands,
            isNot(contains('stop:thread')),
          );
          expect(client.budget.used(ResourceKind.observer), baselineObservers);
        },
      );
    }

    test(
      'actual interaction waits for owner removal (framesFirst=$framesFirst)',
      () async {
        final transport = _Transport();
        final client = _client(transport);
        final interaction = _interaction();
        client
            .session('thread')
            .applySnapshot(_workspace(interactions: [interaction]));
        final entered = transport.interactions.stream.first;
        final resolving = client.threadCommands.resolveActiveInteraction(
          'thread',
          interaction.id,
          _resolution,
        );
        final operation = client.mutations.latest('interaction:thread')!;
        final call = await entered;
        expect(call.operationId, operation.id);
        expect(call.interactionId, interaction.id);
        expect(call.resolution, same(_resolution));
        if (framesFirst) {
          _applyOwnerUpdate(
            client,
            ThreadInteractionUpdate(interaction: interaction, pending: false),
          );
        }
        call.reply.complete(
          InteractionCommandReply(
            interaction: interaction,
            receipt: _identityReceipt(call.operationId, effective: true),
          ),
        );
        await resolving;
        if (!framesFirst) {
          expect(
            operation.state.value.phase,
            OperationPhase.awaitingObservation,
          );
          expect(
            operation.state.value.effective,
            isTrue,
            reason: 'Effect and canonical observation remain independent',
          );
          expect(
            client.session('thread').state.interactions.map((item) => item.id),
            contains(interaction.id),
            reason: 'The response never deletes canonical facts',
          );
          expect(
            client.threadCommands.state.commands['interaction:thread']?.phase,
            CommandPhase.pending,
          );
          _applyOwnerUpdate(
            client,
            ThreadInteractionUpdate(
              interaction: _interaction('unrelated'),
              pending: false,
            ),
          );
          expect(operation.state.value.observed, isFalse);
          _applyOwnerUpdate(
            client,
            ThreadInteractionUpdate(interaction: interaction, pending: false),
          );
        }
        expect(operation.state.value.observed, isTrue);
        expect(operation.state.value.durable, isFalse);
        expect(
          client.threadCommands.state.commands,
          isNot(contains('interaction:thread')),
        );
      },
    );
  }

  test('old interaction ACK cannot clear a newer interaction intent', () async {
    final transport = _Transport();
    final client = _client(transport);
    final x = _interaction('x');
    final y = _interaction('y');
    client.session('thread').applySnapshot(_workspace(interactions: [x]));
    final enteredX = transport.interactions.stream.first;
    final resolvingX = client.threadCommands.resolveActiveInteraction(
      'thread',
      x.id,
      _resolution,
    );
    final callX = await enteredX;
    _applyOwnerUpdate(
      client,
      ThreadInteractionUpdate(interaction: x, pending: false),
    );
    _applyOwnerUpdate(
      client,
      ThreadInteractionUpdate(interaction: y, pending: true),
    );
    final enteredY = transport.interactions.stream.first;
    final resolvingY = client.threadCommands.resolveActiveInteraction(
      'thread',
      y.id,
      _resolution,
    );
    expect(
      client.threadCommands.state.commands['interaction:thread']?.target.label,
      y.id,
    );
    callX.reply.complete(
      InteractionCommandReply(
        interaction: x,
        receipt: _identityReceipt(callX.operationId, effective: true),
      ),
    );
    await resolvingX;
    final callY = await enteredY;
    expect(
      client.mutations.lookup(callX.operationId)!.state.value.observed,
      isTrue,
    );
    expect(
      client.threadCommands.state.commands['interaction:thread']?.target.label,
      y.id,
    );
    callY.reply.complete(
      InteractionCommandReply(
        interaction: y,
        receipt: _identityReceipt(callY.operationId, effective: true),
      ),
    );
    await resolvingY;
    expect(
      client.threadCommands.state.commands['interaction:thread']?.target.label,
      y.id,
    );
    _applyOwnerUpdate(
      client,
      ThreadInteractionUpdate(interaction: y, pending: false),
    );
    expect(
      client.threadCommands.state.commands,
      isNot(contains('interaction:thread')),
    );
  });

  test('resource receipts cannot bypass their canonical version barrier', () {
    final board = MutationBoard(clientId: 'client');
    final operation = board.begin(target: 'settings');
    operation.accept(
      _receipt(operation.id, [_stamp('settings', 2)]).toCommitReceipt(),
    );
    expect(operation.state.value.effective, isTrue);
    expect(operation.state.value.phase, OperationPhase.awaitingObservation);
    expect(operation.markObserved, throwsStateError);
    board.observe(_stamp('settings', 2));
    expect(operation.state.value.observed, isTrue);
  });

  for (final framesFirst in [false, true]) {
    test(
      'actual mode command preserves overlay until all target frames (framesFirst=$framesFirst)',
      () async {
        final transport = _Transport();
        final client = _client(transport);
        final entered = transport.modes.stream.first;
        final changing = client.threadCommands.setThreadMode(ThreadModeId.task);
        final call = await entered;
        expect(call.operationId, client.mutations.latest('mode:thread')!.id);
        final receipt = _receipt(call.operationId, [
          _stamp('thread-state:thread', 2),
          _stamp('thread-directory', 2),
        ]);

        if (framesFirst) {
          client.session('thread').applySnapshot(_workspace(revision: 2));
          client.threadDirectory.applyDelta(
            revision: 2,
            upserted: [_thread(mode: ThreadModeId.task)],
            removed: const [],
          );
        }
        call.reply.complete(ThreadModeCommandReply(receipt: receipt));
        await changing;
        final operation = client.mutations.lookup(call.operationId)!;
        expect(
          operation.state.value.receipt!.disposition,
          CommitDisposition.applied,
          reason: 'An equal observation version never implies NoChange',
        );
        if (!framesFirst) {
          expect(
            operation.state.value.phase,
            OperationPhase.awaitingObservation,
          );
          expect(
            client.threadCommands.state.commands['mode:thread']?.phase,
            CommandPhase.pending,
          );
          client.mutations.observe(
            const ResourceStamp(
              resourceKey: 'thread-state:thread',
              ownerEpoch: 'another-runtime',
              revision: 200,
            ),
          );
          client.threadDirectory.applyDelta(
            revision: 2,
            upserted: [_thread(mode: ThreadModeId.task)],
            removed: const [],
          );
          expect(
            operation.state.value.observed,
            isFalse,
            reason: 'Every target and owner epoch must match',
          );
          expect(client.threadCommands.state.commands, contains('mode:thread'));
          client.session('thread').applySnapshot(_workspace(revision: 2));
        }
        expect(operation.state.value.observed, isTrue);
        expect(operation.state.value.durable, isFalse);
        expect(
          client.threadCommands.state.commands,
          isNot(contains('mode:thread')),
        );
      },
    );
  }

  test(
    'actual route X late acknowledgement cannot clear Y pending overlay',
    () async {
      final transport = _Transport();
      final client = _client(transport);
      final enteredX = transport.routes.stream.first;
      final changingX = client.threadCommands.setThreadModelRoute(
        threadId: 'thread',
        accountId: 'account',
        modelId: 'alpha',
      );
      final x = await enteredX;
      final enteredY = transport.routes.stream.first;
      final changingY = client.threadCommands.setThreadModelRoute(
        threadId: 'thread',
        accountId: 'account',
        modelId: 'beta',
      );
      expect(
        client.settings.state.commands['thread-route:thread']?.target.modelId,
        'beta',
      );

      client
          .session('thread')
          .applySnapshot(_workspace(revision: 2, routeRevision: 2));
      x.reply.complete(
        ThreadModelRouteCommandReply(
          runtime: _runtime(routeRevision: 2),
          settings: _settings(2),
          modeDefaultSaved: true,
          receipt: _receipt(x.operationId, [
            _stamp('thread-route:thread', 2),
            _stamp('settings', 2),
          ], effect: EffectPoint.nextTurn),
        ),
      );
      await changingX;
      final y = await enteredY;
      expect(y.operationId, isNot(x.operationId));
      expect(y.expectedRouteRevision, 2);
      expect(y.expectedSettingsRevision, 2);
      expect(
        client.mutations.lookup(x.operationId)!.state.value.observed,
        isTrue,
      );
      expect(
        client.settings.state.commands['thread-route:thread']?.target.modelId,
        'beta',
      );

      y.reply.complete(
        ThreadModelRouteCommandReply(
          runtime: _runtime(modelId: 'beta', routeRevision: 3),
          settings: _settings(3),
          modeDefaultSaved: true,
          receipt: _receipt(y.operationId, [
            _stamp('thread-route:thread', 3),
            _stamp('settings', 3),
          ], effect: EffectPoint.nextTurn),
        ),
      );
      await changingY;
      expect(
        client.mutations.lookup(y.operationId)!.state.value.phase,
        OperationPhase.awaitingObservation,
      );
      expect(
        client.settings.state.commands['thread-route:thread']?.target.modelId,
        'beta',
      );
      expect(
        client.session('thread').state.runtime?.modelRoute?.modelId,
        'alpha',
        reason: 'A control response does not write the Thread mirror',
      );
      client
          .session('thread')
          .applySnapshot(
            _workspace(revision: 3, modelId: 'beta', routeRevision: 3),
          );
      expect(
        client.mutations.lookup(y.operationId)!.state.value.observed,
        isTrue,
      );
      expect(
        client.settings.state.commands,
        isNot(contains('thread-route:thread')),
      );
    },
  );

  test('actual mode command preserves explicit NoChange with equal resource versions', () async {
    final transport = _Transport();
    final client = _client(transport);
    final entered = transport.modes.stream.first;
    final changing = client.threadCommands.setThreadMode(ThreadModeId.task);
    final call = await entered;
    call.reply.complete(
      ThreadModeCommandReply(
        receipt: _receipt(call.operationId, [
          _stamp('thread-state:thread', 1),
          _stamp('thread-directory', 1),
        ], disposition: CommitDisposition.noChange),
      ),
    );
    await changing;
    expect(
      client.mutations
          .lookup(call.operationId)!
          .state
          .value
          .receipt!
          .disposition,
      CommitDisposition.noChange,
    );
    expect(
      client.mutations.lookup(call.operationId)!.state.value.observed,
      isTrue,
    );
  });

  test(
    'actual command close seals admission and joins an in-flight response',
    () async {
      final transport = _Transport();
      final client = _client(transport);
      final entered = transport.modes.stream.first;
      final changing = client.threadCommands.setThreadMode(ThreadModeId.task);
      final call = await entered;
      var settled = false;
      final closing = client.threadCommands.close().then((_) {
        settled = true;
      });
      expect(settled, isFalse);
      expect(
        () => client.threadCommands.setThreadMode(ThreadModeId.task),
        throwsStateError,
      );
      call.reply.complete(
        ThreadModeCommandReply(
          receipt: _receipt(call.operationId, [
            _stamp('thread-state:thread', 1),
            _stamp('thread-directory', 1),
          ]),
        ),
      );
      await changing;
      await closing;
      expect(settled, isTrue);
    },
  );
}
