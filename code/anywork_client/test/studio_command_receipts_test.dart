import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

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
  _StopCall(this.operationId, this.threadId, this.executionId);
  final OperationId operationId;
  final String threadId;
  final String executionId;
  final reply = Completer<StopThreadCommandReply>();
}

final class _ContinueCall {
  _ContinueCall(
    this.operationId,
    this.threadId,
    this.continuationId,
    this.expectedModelRouteRevision,
  );
  final OperationId operationId;
  final String threadId;
  final String continuationId;
  final int expectedModelRouteRevision;
  final reply = Completer<ContinueThreadCommandReply>();
}

final class _InteractionCall {
  _InteractionCall(
    this.operationId,
    this.hostThreadId,
    this.interactionId,
    this.expectedRevision,
    this.resolution,
  );
  final OperationId operationId;
  final String hostThreadId;
  final String interactionId;
  final int expectedRevision;
  final InteractionResolutionCommand resolution;
  final reply = Completer<InteractionCommandReply>();
}

final class _ArchiveCall {
  _ArchiveCall(this.operationId, this.threadId);
  final OperationId operationId;
  final String threadId;
  final reply = Completer<ArchiveThreadCommandReply>();
}

/// Only the external owner response is controlled. Operation allocation,
/// command lanes, reducers, observation barriers and overlays are production.
final class _Transport implements StudioTransport {
  _Transport() {
    addTearDown(() => modes.close());
    addTearDown(() => routes.close());
    addTearDown(() => stops.close());
    addTearDown(() => continues.close());
    addTearDown(() => interactions.close());
    addTearDown(() => archives.close());
    addTearDown(() async {
      for (final binding in threadBindings) {
        await binding.close();
      }
      for (final sink in topicSinks) {
        await sink.close();
      }
    });
  }

  final modes = StreamController<_ModeCall>.broadcast();
  final routes = StreamController<_RouteCall>.broadcast();
  final stops = StreamController<_StopCall>.broadcast();
  final continues = StreamController<_ContinueCall>.broadcast();
  final interactions = StreamController<_InteractionCall>.broadcast();
  final archives = StreamController<_ArchiveCall>.broadcast();
  final archiveCalls = <_ArchiveCall>[];
  final compactions = <Completer<void>>[];
  final List<StreamController<ProductTopicFrame>> topicSinks = [];
  final List<StreamController<ThreadStreamFrame>> threadBindings = [];
  final List<ContinuationOperationView> continuationReads = [];
  ContinuationOperationView? continuationReadReply;
  List<ChildInteractionSummary> childInteractions = const [];
  int childInteractionReads = 0;
  int stopCalls = 0;
  int continueCalls = 0;
  int interactionCalls = 0;

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) {
    final binding = StreamController<ThreadStreamFrame>.broadcast(sync: true);
    threadBindings.add(binding);
    return binding.stream;
  }

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) async =>
      TestTimelineConnection(initial: baseline(1));

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
  Future<StopThreadCommandReply> stopThread(
    String threadId,
    String executionId, {
    required OperationId operationId,
  }) {
    stopCalls++;
    final call = _StopCall(operationId, threadId, executionId);
    stops.add(call);
    return call.reply.future;
  }

  @override
  Future<ContinueThreadCommandReply> continueThread(
    String threadId,
    String continuationId, {
    required int expectedModelRouteRevision,
    required OperationId operationId,
  }) {
    continueCalls++;
    final call = _ContinueCall(
      operationId,
      threadId,
      continuationId,
      expectedModelRouteRevision,
    );
    continues.add(call);
    return call.reply.future;
  }

  @override
  Future<ContinuationOperationView> readContinuationOperation(
    String threadId,
    String operationId,
  ) async {
    final reply = continuationReadReply;
    if (reply == null) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'no accepted continuation carries this identity',
        retryable: false,
        correlationId: 'stale-continuation-read',
      );
    }
    continuationReads.add(reply);
    return reply;
  }

  @override
  Future<List<ChildInteractionSummary>> readChildInteractions(
    String threadId,
  ) async {
    childInteractionReads++;
    return childInteractions;
  }

  @override
  Future<InteractionCommandReply> respondInteraction(
    String hostThreadId,
    String interactionId,
    int expectedRevision,
    InteractionResolutionCommand resolution, {
    required OperationId operationId,
  }) {
    final call = _InteractionCall(
      operationId,
      hostThreadId,
      interactionId,
      expectedRevision,
      resolution,
    );
    interactionCalls++;
    interactions.add(call);
    return call.reply.future;
  }

  @override
  Future<ArchiveThreadCommandReply> archiveThread(
    String threadId, {
    required OperationId operationId,
  }) {
    final call = _ArchiveCall(operationId, threadId);
    archiveCalls.add(call);
    archives.add(call);
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

/// A direct child of the main session: the same directory identity the agent
/// list publishes, with no separate page or content view.
StudioThread _childThread() => StudioThread(
  id: 'child',
  projectId: 'project',
  title: 'Child',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  parentThreadId: 'thread',
  rootThreadId: 'thread',
  agentPath: 'root/child',
  role: 'executor',
  updatedAt: DateTime.utc(2026),
  workspacePath: '/project',
);

AgentExecutionView? _execution({
  String id = 'execution-1',
  String turnId = 'turn',
  AgentExecutionPhase phase = AgentExecutionPhase.running,
}) => AgentExecutionView(id: id, phase: phase, turnId: turnId);

ThreadRuntimeView _runtime({
  String modelId = 'alpha',
  int routeRevision = 1,
  AgentExecutionView? execution,
  ContinuationView? continuation,
}) => ThreadRuntimeView(
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
  execution: execution,
  continuation: continuation,
);

ThreadWorkspace _workspace({
  int revision = 1,
  String modelId = 'alpha',
  int routeRevision = 1,
  StudioTurnView? activeTurn,
  AgentExecutionView? execution,
  ContinuationView? continuation,
  List<PendingInteraction> interactions = const [],
}) => ThreadWorkspace(
  thread: _thread(),
  revision: revision,
  interactions: interactions,
  runtime: _runtime(
    modelId: modelId,
    routeRevision: routeRevision,
    execution: execution,
    continuation: continuation,
  ),
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

StudioAgentView _agent({
  required String threadId,
  required String path,
  String? parentPath,
  AgentExecutionView? execution,
  bool canStop = true,
}) => StudioAgentView(
  id: threadId,
  threadId: threadId,
  path: path,
  parentPath: parentPath,
  rootThreadId: 'thread',
  depth: parentPath == null ? 0 : 1,
  role: 'executor',
  task: threadId,
  state: const IdleStudioAgent(),
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  execution: execution,
  canStop: canStop,
);

ChildInteractionSummary _childSummary({
  required int revision,
  String childThreadId = 'child',
}) => ChildInteractionSummary(
  childThreadId: childThreadId,
  interactionId: 'child-interaction',
  kind: InteractionKind.userInput,
  revision: revision,
  interaction: PendingInteraction(
    id: 'child-interaction',
    threadId: childThreadId,
    turnId: 'child-turn',
    kind: InteractionKind.userInput,
    title: 'Child question',
    body: 'Answer from the main session',
    revision: revision,
  ),
);

/// The canonical continuation projection the UI freezes before continuing.
ContinuationView _continuation({
  String id = 'continuation-1',
  String? sourceTurnId = 'turn',
  ContinuationReason? reason = ContinuationReason.userStop,
  bool claimed = false,
}) => ContinuationView(
  id: id,
  sourceTurnId: sourceTurnId,
  reason: reason,
  createdAt: DateTime.utc(2026),
  claimed: claimed,
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
  test('archive accepts a blocked repository-recovery root and releases its session', () async {
    final transport = _Transport();
    final client = AnyworkClient(transport: transport, clientId: 'client');
    client.applyBootstrap(
      StudioBootstrap(
        ownerEpoch: _epoch,
        projectDirectory: ProjectDirectoryState(
          values: [_project],
          revision: 1,
        ),
        threadDirectory: ThreadDirectoryWindow(
          threads: [_thread()],
          revision: 1,
        ),
        agentDirectory: AgentDirectoryState(revision: 1),
        settingsState: _settings(1),
        recoveryState: RecoveryStateSnapshot(
          revision: 1,
          values: const [
            StudioRecoveryIssue(
              id: 'missing-worktree',
              scope: RecoveryIssueScope.thread,
              category: RecoveryIssueCategory.repository,
              availableActions: [RecoveryIssueAction.retry],
              threadId: 'thread',
              detail: 'worktree is missing',
              worktree: WorktreeRecoveryPreview(
                inspection: WorktreeInspection.missing,
                ownerKind: WorktreeOwnerKind.session,
                ownerThreadId: 'thread',
                leaseRevision: 1,
                state: 'active',
                repositoryRoot: '/project',
                path: '/project/.anywork/worktrees/thread/session',
                branch: 'pure-session-thread',
                baseCommit: 'base',
                headCommit: null,
                dirty: null,
                changedFiles: null,
              ),
            ),
          ],
        ),
        mcpState: McpStateSnapshot(revision: 1),
        lspState: LspStateSnapshot(revision: 1),
        skillsByProject: const {},
        threadModeCatalog: const ThreadModeCatalogView(),
        accountUsageState: AccountUsageStateSnapshot(revision: 1),
        updaterState: DisabledUpdaterStateSnapshot(
          revision: 1,
          updatedAt: DateTime.utc(2026),
        ),
        persistenceState: const PersistenceStateSnapshot.ready(),
      ),
    );
    client.selection.restoreStartup(
      projectId: 'project',
      threadId: 'thread',
      needsOpen: true,
    );
    final session = client.session('thread')..applySnapshot(_workspace());
    session.start();
    expect(session.isActive, isTrue);
    addTearDown(client.close);

    final archive = client.threadCommands.archiveThread('thread');
    final callObserved = transport.archives.stream.first;
    await Future.any<void>([archive, callObserved.then<void>((_) {})]);
    expect(transport.archiveCalls, hasLength(1));
    final call = transport.archiveCalls.single;
    expect(call.threadId, 'thread');
    call.reply.complete(
      ArchiveThreadCommandReply(
        result: const ArchiveThreadResult(
          archivedRootId: 'thread',
          removedThreadIds: ['thread'],
        ),
        receipt: _receipt(call.operationId, const [
          ResourceStamp(
            resourceKey: 'catalog',
            ownerEpoch: _epoch,
            revision: 2,
          ),
        ]),
      ),
    );
    await archive;

    expect(
      client.mutations.lookup(call.operationId)?.state.value.receipt,
      isNotNull,
    );
    expect(session.isActive, isFalse);
  });

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
    for (final stopped in [false, true]) {
      test(
        'actual stop targets the captured execution identity (framesFirst=$framesFirst, stopped=$stopped)',
        () async {
          final transport = _Transport();
          final client = _client(transport);
          client
              .session('thread')
              .applySnapshot(
                _workspace(activeTurn: _turn(), execution: _execution()),
              );
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
          expect(
            call.executionId,
            'execution-1',
            reason: 'The stop target is the canonical execution identity',
          );
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
            client
                .session('thread')
                .applySnapshot(_workspace(revision: 2, activeTurn: null));
          }
          call.reply.complete(
            StopThreadCommandReply(
              threadId: call.threadId,
              executionId: call.executionId,
              stopped: stopped,
              receipt: _identityReceipt(
                call.operationId,
                disposition: stopped
                    ? CommitDisposition.applied
                    : CommitDisposition.noChange,
              ),
            ),
          );
          final outcome = await stopping;
          expect(
            outcome,
            isA<StopRequested>()
                .having((value) => value.threadId, 'threadId', 'thread')
                .having(
                  (value) => value.executionId,
                  'executionId',
                  'execution-1',
                )
                .having(
                  (value) => value.operationId,
                  'operationId',
                  operation.id,
                )
                .having((value) => value.requested, 'requested', isTrue),
            reason: 'The caller learns that a stop request really went out, and with which identity',
          );
          expect(
            operation.state.value.receipt!.disposition,
            stopped ? CommitDisposition.applied : CommitDisposition.noChange,
          );
          if (!framesFirst) {
            expect(
              operation.state.value.phase,
              OperationPhase.awaitingObservation,
            );
            expect(
              operation.state.value.effective,
              isFalse,
              reason: 'A stop ACK does not prove the execution ended',
            );
            expect(
              client.threadCommands.state.commands['stop:thread']?.phase,
              CommandPhase.pending,
            );
            _applyOwnerUpdate(
              client,
              ThreadRuntimeUpdate(
                runtime: _runtime(execution: _execution()),
                todo: null,
              ),
            );
            expect(
              operation.state.value.observed,
              isFalse,
              reason: 'Unrelated owner facts do not confirm the execution end',
            );
            client
                .session('thread')
                .applySnapshot(_workspace(revision: 2, activeTurn: null));
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
        expect(call.hostThreadId, 'thread');
        expect(call.interactionId, interaction.id);
        expect(call.expectedRevision, 0);
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

  test('a replaced execution makes the frozen stop target obsolete, not successful', () async {
    final transport = _Transport();
    final client = _client(transport);
    client
        .session('thread')
        .applySnapshot(
          _workspace(activeTurn: _turn(), execution: _execution()),
        );
    final stopping = client.threadCommands.stop('thread');
    // The canonical owner publishes a successor execution before the queued stop
    // reaches it: the captured identity is stale and must never stop its successor.
    client
        .session('thread')
        .applySnapshot(
          _workspace(
            revision: 2,
            activeTurn: _turn(turnId: 'turn-2'),
            execution: _execution(id: 'execution-2', turnId: 'turn-2'),
          ),
        );
    await expectLater(
      stopping,
      throwsA(
        isA<StudioFailure>()
            .having(
              (error) => error.reason,
              'reason',
              StudioFailureReason.staleExecution,
            )
            .having((error) => error.code, 'code', StudioFailureCode.conflict),
      ),
    );
    final status = client.threadCommands.state.commands['stop:thread'];
    expect(status?.phase, CommandPhase.failed);
    expect(status?.error?.reason, StudioFailureReason.staleExecution);
  });

  test(
    'child row stop uses the directory execution without selecting the member',
    () async {
      final transport = _Transport();
      final client = _client(transport);
      client.threadDirectory.applyDelta(
        revision: 2,
        upserted: [_childThread()],
        removed: const [],
      );
      client.project.applyAgentDirectory(
        AgentDirectoryState(
          revision: 2,
          values: [
            _agent(
              threadId: 'child',
              path: 'root/child',
              parentPath: 'root',
              execution: _execution(id: 'child-execution', turnId: 'c-turn'),
            ),
          ],
        ),
      );
      final selection = client.selection.state;
      final entered = transport.stops.stream.first;
      final stopping = client.threadCommands.stopAgent('child');
      final call = await entered;
      expect(call.threadId, 'child');
      expect(call.executionId, 'child-execution');
      expect(
        client.selection.state,
        same(selection),
        reason: 'Stopping a row never selects or opens the member',
      );
      expect(
        client.sessionStates.map((state) => state.threadId),
        isNot(contains('child')),
        reason: 'A row stop opens no session and no content subscription',
      );
      expect(
        client.mutations.latest('stop:child')?.state.value.receipt,
        isNull,
      );
      call.reply.complete(
        StopThreadCommandReply(
          threadId: 'child',
          executionId: 'child-execution',
          stopped: true,
          receipt: _identityReceipt(call.operationId),
        ),
      );
      final outcome = await stopping;
      expect(
        outcome,
        isA<StopRequested>()
            .having((value) => value.threadId, 'threadId', 'child')
            .having(
              (value) => value.executionId,
              'executionId',
              'child-execution',
            ),
        reason: 'The row stop reports the execution identity it sent',
      );
      expect(
        client.threadCommands.state.commands['stop:child']?.phase,
        CommandPhase.pending,
        reason: 'An ACK is not an observed execution end',
      );
      client.project.applyAgentDirectory(
        AgentDirectoryState(
          revision: 3,
          values: [
            _agent(
              threadId: 'child',
              path: 'root/child',
              parentPath: 'root',
              execution: null,
              canStop: false,
            ),
          ],
        ),
      );
      expect(
        client.threadCommands.state.commands,
        isNot(contains('stop:child')),
        reason: 'The same row confirming no execution settles the stop',
      );
      expect(
        client.sessionStates.map((state) => state.threadId),
        isNot(contains('child')),
      );
    },
  );

  test('a child row without a stop qualification is not sent and an unloaded page is not an end', () async {
    final transport = _Transport();
    final client = _client(transport);
    client.project.applyAgentDirectory(
      AgentDirectoryState(
        revision: 2,
        values: [
          _agent(
            threadId: 'child',
            path: 'root/child',
            parentPath: 'root',
            execution: _execution(id: 'child-execution'),
            canStop: false,
          ),
        ],
      ),
    );
    expect(
      await client.threadCommands.stopAgent('child'),
      isA<StopNotQualified>()
          .having((value) => value.threadId, 'threadId', 'child')
          .having((value) => value.requested, 'requested', isFalse),
      reason: 'A row without the stop qualification gets no execution intent',
    );
    expect(transport.stops.hasListener, isFalse);
    expect(client.mutations.latest('stop:child'), isNull);
    // A member that is not loaded publishes no execution at all.
    expect(
      await client.threadCommands.stopAgent('unknown-child'),
      isA<StopNotQualified>(),
    );
    expect(transport.stopCalls, 0);
    expect(client.mutations.latest('stop:unknown-child'), isNull);
  });

  test('a stop without a canonical execution reports that nothing was sent', () async {
    final transport = _Transport();
    final client = _client(transport);
    // The interface may still hold a stale "busy" view; the canonical owner has
    // no execution, so no request may be fabricated for it.
    client.session('thread').applySnapshot(_workspace(activeTurn: _turn()));
    expect(
      await client.threadCommands.stop('thread'),
      isA<StopNoExecution>()
          .having((value) => value.threadId, 'threadId', 'thread')
          .having((value) => value.requested, 'requested', isFalse),
      reason: 'A synchronous view is not a stop target',
    );
    expect(transport.stopCalls, 0);
    expect(client.mutations.latest('stop:thread'), isNull);
    expect(client.threadCommands.state.commands, isEmpty);
  });

  test('the command board distinguishes "in flight" from "accepted, waiting for canonical"', () async {
    final transport = _Transport();
    final client = _client(transport);
    client
        .session('thread')
        .applySnapshot(
          _workspace(activeTurn: _turn(), execution: _execution()),
        );
    final entered = transport.stops.stream.first;
    final stopping = client.threadCommands.stop('thread');
    final call = await entered;
    expect(
      client.threadCommands.state.commands['stop:thread']?.accepted,
      isFalse,
      reason: 'An in-flight request has no acceptance receipt yet',
    );
    call.reply.complete(
      StopThreadCommandReply(
        threadId: 'thread',
        executionId: 'execution-1',
        stopped: true,
        receipt: _identityReceipt(call.operationId),
      ),
    );
    expect(await stopping, isA<StopRequested>());
    final accepted = client.threadCommands.state.commands['stop:thread'];
    expect(
      accepted?.phase,
      CommandPhase.pending,
      reason: 'The execution has not left the canonical state yet',
    );
    expect(
      accepted?.accepted,
      isTrue,
      reason: 'The acceptance receipt is readable after an interface rebuild',
    );
    // Canonical convergence settles the command: the entry disappears.
    client
        .session('thread')
        .applySnapshot(_workspace(revision: 2, activeTurn: null));
    expect(
      client.threadCommands.state.commands,
      isNot(contains('stop:thread')),
    );
  });

  test(
    'a stop rejected before acceptance never claims an accepted receipt',
    () async {
      final transport = _Transport();
      final client = _client(transport);
      client
          .session('thread')
          .applySnapshot(
            _workspace(activeTurn: _turn(), execution: _execution()),
          );
      final entered = transport.stops.stream.first;
      final stopping = client.threadCommands.stop('thread');
      final call = await entered;
      call.reply.completeError(
        const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'The observed execution is no longer current',
          retryable: false,
          correlationId: 'server-stale-execution',
          reason: StudioFailureReason.staleExecution,
        ),
      );
      await expectLater(stopping, throwsA(isA<StudioFailure>()));
      final status = client.threadCommands.state.commands['stop:thread'];
      expect(status?.phase, CommandPhase.failed);
      expect(
        status?.accepted,
        isFalse,
        reason: 'A rejection is not an acceptance receipt',
      );
    },
  );

  test(
    'a repeated stop keeps one in-flight request plus one queued retry',
    () async {
      final transport = _Transport();
      final client = _client(transport);
      client
          .session('thread')
          .applySnapshot(
            _workspace(activeTurn: _turn(), execution: _execution()),
          );
      final entered = transport.stops.stream.first;
      final first = client.threadCommands.stop('thread');
      // One explicit retry is registered; further clicks merge into it.
      final firstRetry = client.threadCommands.stop('thread');
      final secondRetry = client.threadCommands.stop(
        'thread',
        expectedExecutionId: 'execution-1',
      );
      expect(identical(firstRetry, secondRetry), isTrue);
      expect(
        await firstRetry,
        isA<StopQueued>()
            .having((value) => value.executionId, 'executionId', 'execution-1')
            .having((value) => value.requested, 'requested', isFalse),
        reason: 'The retry is queued, not sent, and says so',
      );
      final call = await entered;
      expect(
        transport.stopCalls,
        1,
        reason: 'A queued retry never dispatches beside the in-flight attempt',
      );
      expect(
        client.mutations.operations.where(
          (value) => value.target == 'stop:thread',
        ),
        hasLength(1),
        reason: 'Queueing creates no operation and no pending permit',
      );
      call.reply.complete(
        StopThreadCommandReply(
          threadId: 'thread',
          executionId: 'execution-1',
          stopped: true,
          receipt: _identityReceipt(call.operationId),
        ),
      );
      expect(await first, isA<StopRequested>());
      // The queued retry takes its turn as soon as the first attempt settles.
      final queuedCall = await transport.stops.stream.first;
      expect(transport.stopCalls, 2);
      expect(queuedCall.executionId, 'execution-1');
      expect(
        client.mutations.operations.where(
          (value) => value.target == 'stop:thread',
        ),
        hasLength(2),
        reason: 'Exactly one queued attempt became a real request',
      );
      queuedCall.reply.complete(
        StopThreadCommandReply(
          threadId: 'thread',
          executionId: 'execution-1',
          stopped: true,
          receipt: _identityReceipt(queuedCall.operationId),
        ),
      );
      // Fully settled: a later explicit click is a fresh attempt again.
      await Future<void>.delayed(Duration.zero);
      expect(
        client.mutations.lookup(queuedCall.operationId)!.state.value.receipt,
        isNotNull,
      );
      final enteredAgain = transport.stops.stream.first;
      final retry = client.threadCommands.stop(
        'thread',
        expectedExecutionId: 'execution-1',
      );
      final retryCall = await enteredAgain;
      expect(transport.stopCalls, 3);
      retryCall.reply.complete(
        StopThreadCommandReply(
          threadId: 'thread',
          executionId: 'execution-1',
          stopped: true,
          receipt: _identityReceipt(retryCall.operationId),
        ),
      );
      await retry;
      expect(
        client.mutations.operations.where(
          (value) => value.target == 'stop:thread',
        ),
        hasLength(3),
      );
    },
  );

  test('stop flights are per execution and per thread, never merged across targets', () async {
    final transport = _Transport();
    final client = _client(transport);
    client
        .session('thread')
        .applySnapshot(
          _workspace(activeTurn: _turn(), execution: _execution()),
        );
    final received = <String>[];
    final entered = transport.stops.stream.first;
    final first = client.threadCommands.stop('thread');
    final other = client.threadCommands.stop(
      'thread',
      expectedExecutionId: 'execution-other',
    );
    final firstCall = await entered;
    received.add(firstCall.executionId);
    // The lane is serial: the second target only dispatches after the first
    // request settles, so its reply is completed here rather than awaited.
    final enteredOther = transport.stops.stream.first;
    firstCall.reply.complete(
      StopThreadCommandReply(
        threadId: 'thread',
        executionId: firstCall.executionId,
        stopped: true,
        receipt: _identityReceipt(firstCall.operationId),
      ),
    );
    final otherCall = await enteredOther;
    received.add(otherCall.executionId);
    expect(received, unorderedEquals(['execution-1', 'execution-other']));
    expect(transport.stopCalls, 2);
    expect(identical(first, other), isFalse);
    otherCall.reply.complete(
      StopThreadCommandReply(
        threadId: 'thread',
        executionId: otherCall.executionId,
        stopped: true,
        receipt: _identityReceipt(otherCall.operationId),
      ),
    );
    await Future.wait([first, other]);
  });

  test('a command records its start once and keeps it across accepted/failed states', () async {
    var clock = 1700000000000;
    final transport = _Transport();
    final client = AnyworkClient(
      transport: transport,
      clientId: 'client',
      threadCommandsClock: () => clock,
    );
    addTearDown(client.close);
    client.project.applyProjectDirectory(
      ProjectDirectoryState(values: [_project], revision: 1),
    );
    client.selection.restoreStartup(
      projectId: 'project',
      threadId: 'thread',
      needsOpen: true,
    );
    client
        .session('thread')
        .applySnapshot(
          _workspace(activeTurn: _turn(), execution: _execution()),
        );
    final entered = transport.stops.stream.first;
    final stopping = client.threadCommands.stop('thread');
    expect(
      client.threadCommands.state.commands['stop:thread']?.startedAtMs,
      clock,
      reason: 'The start fact is written when the command is registered',
    );
    final call = await entered;
    clock += 5000;
    call.reply.complete(
      StopThreadCommandReply(
        threadId: 'thread',
        executionId: 'execution-1',
        stopped: true,
        receipt: _identityReceipt(call.operationId),
      ),
    );
    expect(await stopping, isA<StopRequested>());
    final accepted = client.threadCommands.state.commands['stop:thread']!;
    expect(
      accepted.startedAtMs,
      1700000000000,
      reason: 'Acceptance never restamps the start fact',
    );
    expect(accepted.accepted, isTrue);
    // Equality includes the start fact, so an unchanged time never churns.
    expect(
      accepted,
      CommandStatus(
        key: 'stop:thread',
        phase: CommandPhase.pending,
        target: accepted.target,
        accepted: true,
        startedAtMs: 1700000000000,
      ),
    );
    clock += 5000;
    final failed = client.threadCommands.state.commands['stop:thread']!
        .withAccepted();
    expect(failed.startedAtMs, accepted.startedAtMs);
  });

  test('a frozen expected execution is sent as-is and the server owns the staleness verdict', () async {
    final transport = _Transport();
    final client = _client(transport);
    // The interface rendered execution-1; canonical already moved to execution-2.
    client
        .session('thread')
        .applySnapshot(
          _workspace(
            activeTurn: _turn(turnId: 'turn-2'),
            execution: _execution(id: 'execution-2', turnId: 'turn-2'),
          ),
        );
    final entered = transport.stops.stream.first;
    final stopping = client.threadCommands.stop(
      'thread',
      expectedExecutionId: 'execution-1',
    );
    final call = await entered;
    expect(
      call.executionId,
      'execution-1',
      reason: 'The frozen identity is the only target, never the latest one',
    );
    call.reply.completeError(
      const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The observed execution is no longer current',
        retryable: false,
        correlationId: 'server-stale-execution',
        reason: StudioFailureReason.staleExecution,
      ),
    );
    await expectLater(
      stopping,
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.reason,
          'reason',
          StudioFailureReason.staleExecution,
        ),
      ),
      reason: 'A stale frozen identity surfaces as a typed failure',
    );
    expect(
      client.mutations.latest('stop:thread')!.state.value.failurePhase,
      OperationPhase.rejected,
    );
    expect(
      client.threadCommands.state.commands['stop:thread']?.error?.reason,
      StudioFailureReason.staleExecution,
    );
  });

  test(
    'a frozen expected execution is still sent when canonical publishes none',
    () async {
      final transport = _Transport();
      final client = _client(transport);
      client.session('thread').applySnapshot(_workspace(activeTurn: _turn()));
      final entered = transport.stops.stream.first;
      final stopping = client.threadCommands.stop(
        'thread',
        expectedExecutionId: 'execution-1',
      );
      final call = await entered;
      expect(call.executionId, 'execution-1');
      call.reply.complete(
        StopThreadCommandReply(
          threadId: 'thread',
          executionId: 'execution-1',
          stopped: false,
          receipt: _identityReceipt(
            call.operationId,
            disposition: CommitDisposition.noChange,
          ),
        ),
      );
      final outcome = await stopping;
      expect(
        outcome,
        isA<StopRequested>()
            .having((value) => value.executionId, 'executionId', 'execution-1')
            .having(
              (value) => value.receipt.disposition,
              'disposition',
              CommitDisposition.noChange,
            ),
        reason:
            'The caller asked about a specific execution; the request goes out',
      );
    },
  );

  test('a frozen expected execution on a qualified row skips the directory target recheck', () async {
    final transport = _Transport();
    final client = _client(transport);
    client.project.applyAgentDirectory(
      AgentDirectoryState(
        revision: 2,
        values: [
          _agent(
            threadId: 'child',
            path: 'root/child',
            parentPath: 'root',
            execution: null,
            canStop: true,
          ),
        ],
      ),
    );
    final entered = transport.stops.stream.first;
    final stopping = client.threadCommands.stopAgent(
      'child',
      expectedExecutionId: 'child-execution',
    );
    final call = await entered;
    expect(call.executionId, 'child-execution');
    call.reply.complete(
      StopThreadCommandReply(
        threadId: 'child',
        executionId: 'child-execution',
        stopped: true,
        receipt: _identityReceipt(call.operationId),
      ),
    );
    expect(
      await stopping,
      isA<StopRequested>().having(
        (value) => value.executionId,
        'executionId',
        'child-execution',
      ),
    );
    // Without a frozen identity the same row reports that nothing was sent.
    expect(
      await client.threadCommands.stopAgent('child'),
      isA<StopNotQualified>(),
    );
    expect(transport.stopCalls, 1);
  });

  test('continue is admitted once, observed as a new Turn and re-read by identity instead of resent', () async {
    final transport = _Transport();
    final client = _client(transport);
    client.session('thread').applySnapshot(_workspace());
    final entered = transport.continues.stream.first;
    final continuing = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    // A second click on the same intent while the first is in flight joins it.
    final repeated = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    expect(identical(repeated, continuing), isTrue);
    final operation = client.mutations.latest('continue:thread')!;
    final call = await entered;
    expect(call.operationId, operation.id);
    expect(call.threadId, 'thread');
    expect(call.continuationId, 'continuation-1');
    expect(call.expectedModelRouteRevision, 1);
    expect(transport.continueCalls, 1);
    call.reply.complete(
      ContinueThreadCommandReply(
        threadId: 'thread',
        inputId: operation.id.value,
        continuationId: 'continuation-1',
        cursor: 4,
        receipt: _identityReceipt(operation.id),
      ),
    );
    await continuing;
    expect(
      operation.state.value.phase,
      OperationPhase.awaitingObservation,
      reason: 'Admission does not prove a Turn started',
    );
    expect(
      operation.state.value.effective,
      isFalse,
      reason: 'Continue acceptance alone is not effective',
    );
    expect(
      client.threadCommands.state.commands['continue:thread']?.phase,
      CommandPhase.pending,
    );
    // The canonical new Turn is what proves the continuation became effective.
    client
        .session('thread')
        .applySnapshot(
          _workspace(
            revision: 2,
            activeTurn: _turn(turnId: 'turn-continued'),
            execution: _execution(
              id: 'execution-continued',
              turnId: 'turn-continued',
            ),
          ),
        );
    expect(operation.state.value.observed, isTrue);
    expect(operation.state.value.effective, isTrue);
    expect(
      client.threadCommands.state.commands,
      isNot(contains('continue:thread')),
    );
    expect(
      transport.continueCalls,
      1,
      reason: 'Exactly one continue request was dispatched',
    );

    // A lost receipt is reconciled by the original identity, never resent.
    transport.continuationReadReply = ContinuationOperationView(
      threadId: 'thread',
      operationId: operation.id.value,
      inputId: operation.id.value,
      continuationId: 'continuation-1',
      acceptedSequence: 4,
      state: ConsumedContinuation('turn-continued'),
      durable: true,
      receipt: _identityReceipt(operation.id),
    );
    final reread = await client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    expect(reread.inputId, operation.id.value);
    expect(transport.continuationReads, hasLength(1));
    final view = await client.threadCommands.readContinuationOperation(
      'thread',
      operation.id.value,
    );
    expect(view.state, const ConsumedContinuation('turn-continued'));
    expect(view.durable, isTrue);
    expect(
      client.mutations.operations.where(
        (value) => value.target == 'continue:thread',
      ),
      hasLength(1),
      reason: 'Re-reading never allocates a second operation',
    );
  });

  test('the canonical continuation projection feeds continue and a claimed point sends nothing', () async {
    final transport = _Transport();
    final client = _client(transport);
    final published = _continuation();
    client.session('thread').applySnapshot(_workspace(continuation: published));
    expect(
      client.threadCommands.continuation('thread'),
      published,
      reason: 'The continue target is read from the canonical projection',
    );
    final entered = transport.continues.stream.first;
    final continuing = client.threadCommands.continueThread(
      'thread',
      published,
      expectedModelRouteRevision: 1,
    );
    final call = await entered;
    expect(call.continuationId, published.id);
    call.reply.complete(
      ContinueThreadCommandReply(
        threadId: 'thread',
        inputId: call.operationId.value,
        continuationId: published.id,
        cursor: 4,
        receipt: _identityReceipt(call.operationId),
      ),
    );
    await continuing;
    // The canonical new Turn proves the accepted continuation took effect.
    client
        .session('thread')
        .applySnapshot(
          _workspace(
            revision: 2,
            activeTurn: _turn(turnId: 'turn-continued'),
            execution: _execution(
              id: 'execution-continued',
              turnId: 'turn-continued',
            ),
            continuation: _continuation(claimed: true),
          ),
        );
    expect(
      client.mutations.lookup(call.operationId)!.state.value.observed,
      isTrue,
    );
    // A point another acceptance already claimed never dispatches a request.
    final claimed = _continuation(id: 'continuation-2', claimed: true);
    client
        .session('thread')
        .applySnapshot(
          _workspace(
            revision: 3,
            activeTurn: _turn(turnId: 'turn-continued'),
            execution: _execution(
              id: 'execution-continued',
              turnId: 'turn-continued',
            ),
            continuation: claimed,
          ),
        );
    await expectLater(
      client.threadCommands.continueThread(
        'thread',
        claimed,
        expectedModelRouteRevision: 1,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.reason,
          'reason',
          StudioFailureReason.continuationClaimed,
        ),
      ),
    );
    expect(
      transport.continueCalls,
      1,
      reason: 'A claimed continuation sends nothing',
    );
    // An older increment cannot replace the newer continuation projection.
    final session = client.session('thread');
    session.applyNotification(
      ThreadNotificationFrame(
        threadId: 'thread',
        revision: session.state.revision,
        baseRevision: session.state.revision,
        update: ThreadRuntimeUpdate(
          runtime: _runtime(continuation: _continuation(id: 'obsolete')),
          todo: null,
        ),
      ),
    );
    expect(
      client.threadCommands.continuation('thread')!.id,
      claimed.id,
      reason: 'A lowered frame revision never rewrites the projection',
    );
    // The consumed Turn clears the point: nothing local is offered afterwards.
    client
        .session('thread')
        .applySnapshot(
          _workspace(
            revision: 4,
            activeTurn: _turn(turnId: 'turn-continued'),
            execution: _execution(
              id: 'execution-continued',
              turnId: 'turn-continued',
            ),
            continuation: null,
          ),
        );
    expect(client.threadCommands.continuation('thread'), isNull);
    // Nothing derived locally: the point only comes from the canonical snapshot.
    expect(client.threadCommands.continuation('thread'), isNull);
    expect(transport.continuationReads, isEmpty);
  });

  test('continue is rejected for a child Thread before any request', () async {
    final transport = _Transport();
    final client = _client(transport);

    expect(
      client.threadDirectory.mergeOverlayThreads([_childThread()]),
      isTrue,
    );
    await expectLater(
      client.threadCommands.continueThread(
        'child',
        _continuation(),
        expectedModelRouteRevision: 1,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.reason,
          'reason',
          StudioFailureReason.childThreadRequiresParentScheduling,
        ),
      ),
    );
    expect(transport.continueCalls, 0);
  });

  test('a child decision is routed through the hosting main session with its revision', () async {
    final transport = _Transport();
    final client = _client(transport);
    final summary = _childSummary(revision: 3);
    transport.childInteractions = [summary];
    await client.threadCommands.readChildInteractions('thread');
    expect(transport.childInteractionReads, 1);
    expect(
      client.childInteractions.state.items.single.interactionId,
      'child-interaction',
    );
    final entered = transport.interactions.stream.first;
    final resolving = client.threadCommands.resolveChildInteraction(
      'thread',
      summary,
      _resolution,
    );
    final call = await entered;
    expect(call.hostThreadId, 'thread');
    expect(call.interactionId, 'child-interaction');
    expect(call.expectedRevision, 3);
    expect(call.resolution, same(_resolution));
    call.reply.complete(
      InteractionCommandReply(
        interaction: summary.interaction,
        receipt: _identityReceipt(call.operationId),
      ),
    );
    await resolving;
    expect(
      client.mutations.latest('interaction:thread')!.state.value.observed,
      isFalse,
      reason:
          'The original child interaction is still pending in the projection',
    );
    // The projection stops offering the interaction: the decision took effect.
    transport.childInteractions = const [];
    await client.threadCommands.readChildInteractions('thread');
    expect(
      client.mutations.latest('interaction:thread')!.state.value.observed,
      isTrue,
    );
    expect(
      client.threadCommands.state.commands,
      isNot(contains('interaction:thread')),
    );
  });

  test('a child session cannot host its own decision', () async {
    final transport = _Transport();
    final client = _client(transport);
    expect(
      client.threadDirectory.mergeOverlayThreads([_childThread()]),
      isTrue,
    );
    final summary = _childSummary(revision: 1);
    await expectLater(
      client.threadCommands.resolveChildInteraction(
        'child',
        summary,
        _resolution,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.reason,
          'reason',
          StudioFailureReason.interactionNotHosted,
        ),
      ),
    );
    await expectLater(
      client.threadCommands.resolveChildInteraction(
        'thread',
        _childSummary(revision: 1, childThreadId: 'thread'),
        _resolution,
      ),
      throwsA(isA<StudioFailure>()),
    );
    expect(
      transport.interactionCalls,
      0,
      reason: 'A child session has no entry to decide its own interaction',
    );
  });
}
