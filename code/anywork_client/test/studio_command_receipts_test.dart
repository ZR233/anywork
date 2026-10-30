import 'support/conversation_delivery.dart';

import 'dart:async';

import 'package:anywork_client/accounts.dart' show NativeAccountIdentity;
import 'package:anywork_client/accounts_ports.dart'
    show SettingsWriteOwnerChanged;
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';
import 'support/timeline_transport.dart';

// The native fixture identity used before the SDK conversation migration.
const _epoch = 'native-runtime-one';

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

final class _SettingsCall {
  _SettingsCall(this.revision, this.command, this.operationId);
  final int revision;
  final SettingsFieldCommand command;
  final OperationId operationId;
  final reply = Completer<SettingsCommandReply>();
}

final class _ArchiveCall {
  _ArchiveCall(this.operationId, this.threadId);
  final OperationId operationId;
  final String threadId;
  final reply = Completer<ArchiveThreadCommandReply>();
}

/// Only the external owner response is controlled. Operation allocation,
/// command lanes, reducers, observation barriers and overlays are production.
final class _Transport extends AccountsTestTransport {
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
  final Completer<void> compactEntered = Completer<void>();
  final List<StreamController<ProductTopicFrame>> topicSinks = [];
  final List<StreamController<ThreadStreamFrame>> threadBindings = [];
  final List<ContinuationOperationView> continuationReads = [];
  ContinuationOperationView? continuationReadReply;
  int continuationReadCalls = 0;
  List<ChildInteractionSummary> childInteractions = const [];
  int childInteractionReads = 0;
  Future<List<ChildInteractionSummary>> Function(String)?
  childInteractionsReply;
  int stopCalls = 0;
  int continueCalls = 0;
  int interactionCalls = 0;
  final settingsCalls = <_SettingsCall>[];
  final routeCalls = <_RouteCall>[];
  final _settingsEntered = <int, Completer<_SettingsCall>>{};
  Future<SettingsCommandReply> Function(_SettingsCall)? settingsReply;
  Future<ThreadModelRouteCommandReply> Function(_RouteCall)? routeReply;
  Future<SettingsStateSnapshot> Function()? settingsRead;
  final settingsReadEntered = Completer<void>();

  Future<_SettingsCall> settingsCall(int index) => settingsCalls.length > index
      ? Future.value(settingsCalls[index])
      : (_settingsEntered[index] ??= Completer<_SettingsCall>()).future;

  @override
  Future<SettingsCommandReply> applySettingsField(
    int revision,
    SettingsFieldCommand command, {
    required OperationId operationId,
  }) {
    final call = _SettingsCall(revision, command, operationId);
    final index = settingsCalls.length;
    settingsCalls.add(call);
    _settingsEntered.remove(index)?.complete(call);
    return settingsReply?.call(call) ?? Future.error(_probeRejection);
  }

  @override
  Future<SettingsStateSnapshot> readSettingsState() {
    if (!settingsReadEntered.isCompleted) settingsReadEntered.complete();
    return settingsRead?.call() ?? Future.value(_settings(1));
  }

  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    ConversationCompletionCursor? resumeAfter,
  }) async {
    final states = StreamController<ThreadStreamFrame>.broadcast(sync: true);
    threadBindings.add(states);
    return ScriptedConversationFeed(
      threadId: threadId,
      states: states.stream,
      resumeAfter: resumeAfter,
    );
  }

  @override
  Future<void> compactThread(String threadId) {
    expect(threadId, 'thread');
    final reply = Completer<void>();
    compactions.add(reply);
    if (!compactEntered.isCompleted) compactEntered.complete();
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
    routeCalls.add(call);
    return routeReply?.call(call) ?? call.reply.future;
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
    continuationReadCalls += 1;
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
    final reply = childInteractionsReply;
    if (reply != null) return reply(threadId);
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

final class _RouteConflictFeed extends ScriptedConversationFeed {
  _RouteConflictFeed({
    required super.threadId,
    required super.initial,
    required super.states,
    super.resumeAfter,
    required this.onClose,
  });

  final Future<void> Function() onClose;
  Future<void>? _closing;

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    // A feed owns cleanup even if retired before its events getter is consumed.
    await onClose();
    await super.close();
  }
}

final class _RouteConflictTransport extends _Transport {
  _RouteConflictTransport({this.onFeedClose}) {
    addTearDown(() async {
      for (final binding in bindings) {
        await binding.close();
      }
    });
  }

  final List<StreamController<ThreadStreamFrame>> bindings = [];
  final Future<void> Function(int index)? onFeedClose;
  final List<_RouteCall> attempts = [];
  final refreshEntered = Completer<void>();
  int windowOpens = 0;

  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    ConversationCompletionCursor? resumeAfter,
  }) async {
    final index = bindings.length;
    // Frames may have no consumer when opening is retired immediately.
    final binding = StreamController<ThreadStreamFrame>.broadcast(sync: true);
    bindings.add(binding);
    windowOpens++;
    final feed = _RouteConflictFeed(
      threadId: threadId,
      initial: baseline(
        300,
        subscriptionId: 'route-conflict-$index',
        items: const [],
      ),
      states: binding.stream,
      resumeAfter: resumeAfter,
      onClose: () => onFeedClose?.call(index) ?? Future<void>.value(),
    );
    if (bindings.length == 2 && !refreshEntered.isCompleted)
      refreshEntered.complete();
    return feed;
  }

  @override
  Future<SettingsStateSnapshot> readSettingsState() => settingsRead == null
      ? Future.value(_settings(2))
      : super.readSettingsState();

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

const _project = StudioProject(
  id: 'project',
  name: 'Project',
  path: '/project',
);

StudioThread _thread({ThreadModeId mode = ThreadModeId.simple}) => StudioThread(
  id: 'thread',
  workspaceId: 'project',
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
  workspaceId: 'project',
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
  ThreadStorageStateView? storage,
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
  storage: storage,
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

Future<void> _applyOwnerUpdate(
  AnyworkClient client,
  ThreadWorkspaceUpdate update,
) async {
  final session = client.conversations.session('thread');
  await session.deliverNotification(
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

const _probeRejection = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'Scripted request rejection',
  retryable: false,
  correlationId: 'settings-owner-test',
);
const _threadAccessIssue = StudioRecoveryIssue(
  id: 'thread-access-unavailable',
  scope: RecoveryIssueScope.thread,
  category: RecoveryIssueCategory.storage,
  impact: RecoveryIssueImpact.accessBlocked,
  availableActions: [RecoveryIssueAction.retry],
  threadId: 'thread',
  detail: 'The target Thread storage is inaccessible',
);
StudioBootstrap _bootstrap(String epoch, SettingsStateSnapshot settings) =>
    StudioBootstrap(
      ownerEpoch: epoch,
      projectDirectory: ProjectDirectoryState(values: [_project], revision: 1),
      threadDirectory: ThreadDirectoryWindow(threads: [_thread()], revision: 1),
      agentDirectory: AgentDirectoryState(revision: 1),
      settingsState: settings,
      recoveryState: RecoveryStateSnapshot(revision: 1),
      mcpState: McpStateSnapshot(revision: 1),
      lspState: LspStateSnapshot(revision: 1),
      skillsByProject: const {},
      threadModeCatalog: const ThreadModeCatalogView(),
      updaterState: DisabledUpdaterStateSnapshot(
        revision: 1,
        updatedAt: DateTime.utc(2026),
      ),
      persistenceState: const PersistenceStateSnapshot.ready(),
    );

Future<AnyworkClient> _client(
  _Transport transport, {
  void Function(AccountsTestRuntime)? onRuntime,
}) async {
  transport.epoch = _epoch;
  final runtime = AccountsTestRuntime(transport, clientId: 'client');
  runtime.seed(_settings(1));
  onRuntime?.call(runtime);
  final client = runtime.client;
  client.applyBootstrap(_bootstrap(_epoch, _settings(1)));
  // The command has a stable selected identity; this test does not open a native
  // ChatView. State frames enter through the production read-model reducers.
  client.selection.restoreStartup(
    workspaceId: 'project',
    threadId: 'thread',
    needsOpen: true,
  );
  final consumer = TestCompletionConsumer();
  client.conversations.session('thread').content.attachConsumer(consumer);
  _completionConsumers[client] = consumer;
  client.conversations.setVisibleThread('thread');
  await client.conversations.session('thread').deliverWorkspace(_workspace());
  addTearDown(runtime.close);
  client.conversations.setVisibleThread('thread');
  return client;
}

final _completionConsumers = Expando<TestCompletionConsumer>();

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
  for (final replacement in ['third', 'next']) {
    for (final boundary in [
      'settings reset',
      'summaries',
      'first detail',
      if (replacement == 'next') 'settings reset direct',
    ]) {
      test(
        '${replacement == 'next' ? 'same-next' : 'reentrant'} bootstrap invalidation preserves the nested owner baseline after $boundary notification',
        () async {
          final transport = _Transport();
          final runtime = AccountsTestRuntime(
            transport,
            clientId: 'bootstrap-reentry',
          );
          addTearDown(runtime.close);
          final client = runtime.client;
          const first = NativeAccountIdentity('account');
          const second = NativeAccountIdentity('second');
          SettingsStateSnapshot baseline(int revision) => SettingsStateSnapshot(
            revision: revision,
            modelCatalogRevision: revision,
            accounts: [
              ..._settings(revision).accounts,
              const AccountSettingsView(
                id: 'second',
                name: 'Second',
                baseUrl: 'https://second.invalid',
                defaultModelId: '',
                status: 'ready',
                usageLabel: '',
                models: [],
              ),
            ],
          );
          client.applyBootstrap(_bootstrap('old', baseline(99)));
          transport.epoch = 'old';
          runtime.seed(baseline(99));
          var replaced = false;
          late List<Object> nestedDetails;
          late List<Object> nestedConfigurations;
          void replace() {
            if (replaced) return;
            replaced = true;
            if (boundary != 'settings reset direct') {
              client.applyBootstrap(_bootstrap(replacement, baseline(1)));
            }
            transport.epoch = replacement;
            runtime.seed(baseline(1));
            nestedDetails = [
              for (final id in [first, second])
                runtime.domains.accounts.details(id).value,
            ];
            nestedConfigurations = [
              for (final id in [first, second])
                runtime.domains.models.state.value.configurations[id]!,
            ];
          }

          final listener = switch (boundary) {
            'settings reset' ||
            'settings reset direct' => client.settings.source.watch((value) {
              if (!value.configLoaded) replace();
            }),
            'first detail' => runtime.domains.accounts.details(first).watch((
              value,
            ) {
              if (value.stale) replace();
            }),
            _ => runtime.domains.accounts.state.watch((value) {
              if (value.stale) replace();
            }),
          };
          addTearDown(listener.cancel);
          if (replacement == 'third') {
            expect(
              () => client.applyBootstrap(_bootstrap('next', baseline(1))),
              throwsA(isA<SettingsWriteOwnerChanged>()),
            );
          } else {
            client.applyBootstrap(_bootstrap('next', baseline(1)));
          }
          expect(replaced, isTrue);
          expect(client.settings.state.settingsRevision, 1);
          expect(
            runtime.coordinator.stamp,
            testStamp('settings', 1, epoch: replacement),
          );
          for (var index = 0; index < 2; index++) {
            final id = [first, second][index];
            final detail = runtime.domains.accounts.details(id).value;
            final configuration =
                runtime.domains.models.state.value.configurations[id]!;
            expect(
              (detail.loaded, detail.stale, detail.loading),
              (true, false, false),
            );
            expect(
              (
                configuration.loaded,
                configuration.stale,
                configuration.loading,
              ),
              (true, false, false),
            );
            expect(detail, same(nestedDetails[index]));
            expect(configuration, same(nestedConfigurations[index]));
          }
          // The nested baseline must already be ready: deduplicated replay is not
          // a recovery mechanism for an old invalidation tail.
          runtime.seed(baseline(1));
          expect(
            runtime.domains.accounts.details(second).value,
            same(nestedDetails[1]),
          );
          expect(
            runtime.domains.models.state.value.configurations[second],
            same(nestedConfigurations[1]),
          );
          listener.cancel();
          expect((await runtime.close()).complete, isTrue);
        },
      );
    }
  }

  test('reentrant settings reply routing retains its receipt but stops old target frames after reconnect', () async {
    final transport = _Transport()..settingsReply = (call) => call.reply.future;
    late AccountsTestRuntime runtime;
    final client = await _client(
      transport,
      onRuntime: (value) => runtime = value,
    );
    client.applyBootstrap(_bootstrap('old', _settings(99)));
    transport.epoch = 'old';
    runtime.seed(_settings(99));
    var replaced = false;
    final listener = client.settings.source.watch((state) {
      if (!replaced && state.settingsRevision == 100) {
        replaced = true;
        client.applyBootstrap(_bootstrap('next', _settings(1)));
        client.applyBootstrap(_bootstrap('old', _settings(1)));
        transport.epoch = 'old';
        runtime.seed(_settings(1));
      }
    });
    addTearDown(listener.cancel);
    final failure = expectLater(
      client.settingsCommands.applySettingsField(
        const InstructionUserCommand('old-input'),
      ),
      throwsStateError,
    );
    final call = await transport.settingsCall(0);
    call.reply.complete(
      accountReply(
        snapshot: SettingsStateSnapshot(
          revision: 100,
          modelCatalogRevision: 100,
          accounts: [
            ..._settings(1).accounts,
            const AccountSettingsView(
              id: 'late-b',
              name: 'Retired B',
              baseUrl: 'http://retired.invalid',
              defaultModelId: '',
              models: [],
              status: 'ready',
              usageLabel: '',
            ),
          ],
        ),
        receipt: StudioCommandReceipt(
          operationId: call.operationId,
          disposition: CommitDisposition.applied,
          targets: const [
            ResourceStamp(
              resourceKey: 'settings',
              ownerEpoch: 'old',
              revision: 100,
            ),
          ],
          effect: EffectPoint.futureSession,
          effective: true,
          durable: true,
        ),
      ),
    );
    await failure;
    expect(replaced, isTrue);
    expect(client.settings.state.settingsRevision, 1);
    expect(
      client.settingsWrites.stamp,
      const ResourceStamp(
        resourceKey: 'settings',
        ownerEpoch: 'old',
        revision: 1,
      ),
    );
    expect(client.modelCatalogLoaded, isFalse);
    expect(client.modelCatalogRevision, 0);
    expect(
      runtime.domains.models.state.value.accounts.keys.map(
        (identity) => identity.accountId,
      ),
      isNot(contains('late-b')),
    );
    final operation = client.mutations.lookup(call.operationId)!.state.value;
    expect(operation.receipt!.operationId, call.operationId);
    expect(operation.durable, isTrue);
    expect(operation.effective, isTrue);
    expect(operation.phase, OperationPhase.syncFailed);
    listener.cancel();
    await client.close();
  });

  for (final routeWrite in [false, true]) {
    test(
      'owner incarnation cannot observe a retired sent ${routeWrite ? 'route' : 'settings'} receipt when its epoch name returns',
      () async {
        for (final replacementFrameFirst in [false, true]) {
          final transport = _Transport()
            ..settingsReply = (call) => call.reply.future;
          late AccountsTestRuntime runtime;
          final client = await _client(
            transport,
            onRuntime: (value) => runtime = value,
          );
          client.applyBootstrap(_bootstrap('old', _settings(99)));
          transport.epoch = 'old';
          runtime.seed(_settings(99));
          late final Future<void> failure;
          late final OperationId id;
          late final void Function() complete;
          if (routeWrite) {
            final entered = transport.routes.stream.first;
            failure = expectLater(
              client.threadCommands.setThreadModelRoute(
                threadId: 'thread',
                accountId: 'account',
                modelId: 'beta',
              ),
              throwsStateError,
            );
            final call = await entered;
            id = call.operationId;
            complete = () => call.reply.complete(
              ThreadModelRouteCommandReply(
                runtime: _runtime(routeRevision: 4),
                settings: _settings(100),
                modeDefaultSaved: true,
                receipt: StudioCommandReceipt(
                  operationId: id,
                  disposition: CommitDisposition.applied,
                  targets: const [
                    ResourceStamp(
                      resourceKey: 'settings',
                      ownerEpoch: 'old',
                      revision: 100,
                    ),
                  ],
                  effect: EffectPoint.futureSession,
                  effective: true,
                  durable: true,
                ),
              ),
            );
          } else {
            failure = expectLater(
              client.settingsCommands.applySettingsField(
                const InstructionUserCommand('retired-input'),
              ),
              throwsStateError,
            );
            final call = await transport.settingsCall(0);
            id = call.operationId;
            complete = () => call.reply.complete(
              SettingsCommandReply(
                snapshot: _settings(100),
                receipt: StudioCommandReceipt(
                  operationId: id,
                  disposition: CommitDisposition.applied,
                  targets: const [
                    ResourceStamp(
                      resourceKey: 'settings',
                      ownerEpoch: 'old',
                      revision: 100,
                    ),
                  ],
                  effect: EffectPoint.futureSession,
                  effective: true,
                  durable: true,
                ),
              ),
            );
          }
          client.applyBootstrap(_bootstrap('next', _settings(1)));
          client.applyBootstrap(_bootstrap('old', _settings(1)));
          transport.epoch = 'old';
          runtime.seed(_settings(1));
          if (replacementFrameFirst)
            client.acceptSettingsSnapshot(_settings(101));
          complete();
          await failure;
          final operation = client.mutations.lookup(id)!;
          final before = operation.state.value;
          expect(
            before.observed,
            isFalse,
            reason: 'Acceptance cannot use a replacement incarnation watermark',
          );
          expect(before.phase, OperationPhase.syncFailed);
          final ownerFailure = before.error;
          client.acceptSettingsSnapshot(_settings(102));
          final after = operation.state.value;
          expect(
            after.observed,
            isFalse,
            reason: 'Every later automatic merge must retain the original observation qualification',
          );
          expect(after.phase, OperationPhase.syncFailed);
          expect(after.error, same(ownerFailure));
          expect(after.receipt!.operationId, id);
          expect(
            after.receipt!.targets.single,
            const ResourceStamp(
              resourceKey: 'settings',
              ownerEpoch: 'old',
              revision: 100,
            ),
          );
          expect(after.receipt!.disposition, CommitDisposition.applied);
          expect(after.effective, isTrue);
          expect(after.durable, isTrue);
          expect(
            client.budget.used(ResourceKind.pendingOperation),
            1,
            reason: 'A failed observation is not an early permit release',
          );
          final report = await client.close();
          expect(report.complete, isFalse);
          expect(
            report.unresolved.any(
              (resource) => resource.owner == 'operation:${id.value}',
            ),
            isTrue,
          );
        }
      },
    );
  }

  for (final withDomains in [false, true]) {
    test(
      'reentrant settings reduction cannot retag an old read or publish its catalog (domains=$withDomains)',
      () async {
        final transport = _Transport();
        final read = Completer<SettingsStateSnapshot>();
        transport.settingsRead = () => read.future;
        AccountsTestRuntime? runtime;
        final client = withDomains
            ? await _client(transport, onRuntime: (value) => runtime = value)
            : AnyworkClient(transport: transport, clientId: 'reentrant-read');
        if (!withDomains) addTearDown(client.close);
        client.applyBootstrap(_bootstrap('old', _settings(99)));
        var replaced = false;
        final listener = client.settings.source.watch((state) {
          if (!replaced && state.settingsRevision == 100) {
            replaced = true;
            client.applyBootstrap(_bootstrap('next', _settings(1)));
            transport.epoch = 'next';
            runtime?.seed(_settings(1));
          }
        });
        addTearDown(listener.cancel);
        final reading = client.settingsCommands.refreshCanonical();
        final rejected = expectLater(reading, throwsStateError);
        read.complete(
          SettingsStateSnapshot(
            revision: 100,
            modelCatalogRevision: 100,
            accounts: _settings(1).accounts,
            instructions: const InstructionsSettingsView(user: 'retired-read'),
          ),
        );
        await rejected;
        expect(replaced, isTrue);
        expect(client.settings.state.settingsRevision, 1);
        expect(client.settings.state.canonical!.instructions.user, isEmpty);
        expect(
          client.settingsWrites.stamp,
          const ResourceStamp(
            resourceKey: 'settings',
            ownerEpoch: 'next',
            revision: 1,
          ),
        );
        expect(client.modelCatalogLoaded, isFalse);
        expect(client.modelCatalogRevision, 0);
        if (withDomains) {
          final models = runtime!.domains.models.state.value.accounts.values;
          expect(models.single.stamp!.ownerEpoch, 'next');
          expect(models.single.stamp!.revision, 1);
        }
        listener.cancel();
        expect((await client.close()).complete, isTrue);
      },
    );
  }

  test('reentrant model reduction stops the remainder of a whole catalog even after the epoch name returns', () async {
    final transport = _Transport();
    final read = Completer<SettingsStateSnapshot>();
    transport.settingsRead = () => read.future;
    late AccountsTestRuntime runtime;
    final client = await _client(
      transport,
      onRuntime: (value) => runtime = value,
    );
    client.applyBootstrap(_bootstrap('old', _settings(99)));
    transport.epoch = 'old';
    runtime.seed(_settings(99));
    var replaced = false;
    final listener = runtime.domains.models.state.watch((state) {
      if (!replaced &&
          state.accounts.values.any((value) => value.stamp?.revision == 100)) {
        replaced = true;
        client.applyBootstrap(_bootstrap('next', _settings(1)));
        client.applyBootstrap(_bootstrap('old', _settings(1)));
        transport.epoch = 'old';
        runtime.seed(_settings(1));
      }
    });
    addTearDown(listener.cancel);
    final rejected = expectLater(
      client.settingsCommands.refreshCanonical(),
      throwsStateError,
    );
    read.complete(
      SettingsStateSnapshot(
        revision: 100,
        modelCatalogRevision: 100,
        accounts: [
          ..._settings(1).accounts,
          const AccountSettingsView(
            id: 'late-b',
            name: 'Retired B',
            baseUrl: 'http://retired.invalid',
            defaultModelId: '',
            models: [],
            status: 'ready',
            usageLabel: '',
          ),
        ],
      ),
    );
    await rejected;
    expect(replaced, isTrue);
    expect(client.settings.state.settingsRevision, 1);
    expect(
      client.settingsWrites.stamp,
      const ResourceStamp(
        resourceKey: 'settings',
        ownerEpoch: 'old',
        revision: 1,
      ),
    );
    expect(client.modelCatalogLoaded, isFalse);
    expect(client.modelCatalogRevision, 0);
    expect(
      runtime.domains.models.state.value.accounts.keys.map(
        (identity) => identity.accountId,
      ),
      isNot(contains('late-b')),
    );
    expect(
      runtime.domains.models.state.value.accounts.values.single.stamp!.revision,
      1,
    );
    listener.cancel();
    expect((await client.close()).complete, isTrue);
  });

  test('settings owner change back to the same epoch name cannot revive an old queued intent', () async {
    final transport = _Transport();
    final client = await _client(transport);
    client.applyBootstrap(_bootstrap('old', _settings(99)));
    final entered = Completer<void>();
    final release = Completer<void>();
    final blocking = client.settingsWrites.enqueue(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final rejected = expectLater(
      client.settingsCommands.applySettingsField(
        const InstructionUserCommand('retired-incarnation'),
      ),
      throwsStateError,
    );
    client.applyBootstrap(_bootstrap('next', _settings(1)));
    client.applyBootstrap(_bootstrap('old', _settings(1)));
    release.complete();
    await blocking;
    await rejected;
    expect(transport.settingsCalls, isEmpty);
    expect(
      client.mutations.latest('settings:instructions:user')!.state.value.phase,
      OperationPhase.rejected,
    );
    expect((await client.close()).complete, isTrue);
  });

  test('settings owner change rejects a queued intent before transport and admits the new low revision', () async {
    final transport = _Transport();
    final client = await _client(transport);
    client.applyBootstrap(_bootstrap('old', _settings(99)));
    final entered = Completer<void>();
    final release = Completer<void>();
    final blocking = client.settingsWrites.enqueue(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final old = client.settingsCommands.applySettingsField(
      const InstructionUserCommand('old-owner-input'),
    );
    final oldOperation = client.mutations.latest('settings:instructions:user')!;
    final rejected = expectLater(old, throwsStateError);
    client.applyBootstrap(_bootstrap('next', _settings(1)));
    release.complete();
    await blocking;
    await rejected;
    expect(transport.settingsCalls, isEmpty);
    expect(oldOperation.state.value.phase, OperationPhase.rejected);
    expect(client.settings.state.commands, isEmpty);
    await expectLater(
      client.settingsCommands.applySettingsField(
        const InstructionUserCommand('next-owner-input'),
      ),
      throwsA(same(_probeRejection)),
    );
    expect(transport.settingsCalls.map((call) => call.revision), [1]);
    expect(
      (transport.settingsCalls.single.command as InstructionUserCommand).value,
      'next-owner-input',
    );
    expect((await client.close()).complete, isTrue);
  });

  test('settings owner change while acquiring CAS rejects the old read before publication or dispatch', () async {
    final transport = _Transport();
    final read = Completer<SettingsStateSnapshot>();
    transport.settingsRead = () => read.future;
    final client = await _client(transport);
    client.applyBootstrap(
      _bootstrap(
        'loading-old',
        const SettingsStateSnapshot.fromState(
          state: UninitializedObservedResource<SettingsStateData>(updatedAt: 0),
        ),
      ),
    );
    final old = client.settingsCommands.applySettingsField(
      const InstructionUserCommand('old-owner-input'),
    );
    final rejected = expectLater(old, throwsStateError);
    await transport.settingsReadEntered.future;
    client.applyBootstrap(_bootstrap('next', _settings(1)));
    read.complete(
      SettingsStateSnapshot(
        revision: 999,
        instructions: const InstructionsSettingsView(user: 'late-old-read'),
      ),
    );
    await rejected;
    expect(transport.settingsCalls, isEmpty);
    expect(client.settings.state.settingsRevision, 1);
    expect(client.settings.state.canonical!.instructions.user, isEmpty);
    expect(
      client.settingsWrites.stamp,
      const ResourceStamp(
        resourceKey: 'settings',
        ownerEpoch: 'next',
        revision: 1,
      ),
    );
    expect(
      client.mutations.latest('settings:instructions:user')!.state.value.phase,
      OperationPhase.rejected,
    );
    expect((await client.close()).complete, isTrue);
  });

  test('settings owner change during conflict refresh does not retry or rebind the late canonical read', () async {
    final transport = _Transport();
    final read = Completer<SettingsStateSnapshot>();
    transport.settingsRead = () => read.future;
    const conflict = StudioFailure(
      code: StudioFailureCode.staleRevision,
      message: 'Old settings changed',
      retryable: true,
      correlationId: 'owner-conflict',
    );
    transport.settingsReply = (_) => Future.error(conflict);
    final client = await _client(transport);
    client.applyBootstrap(_bootstrap('old', _settings(99)));
    final old = client.settingsCommands.applySettingsField(
      const InstructionUserCommand('old-owner-input'),
    );
    final rejected = expectLater(old, throwsStateError);
    await transport.settingsReadEntered.future;
    client.applyBootstrap(_bootstrap('next', _settings(1)));
    read.complete(
      SettingsStateSnapshot(
        revision: 100,
        instructions: const InstructionsSettingsView(user: 'old-refresh'),
      ),
    );
    await rejected;
    expect(transport.settingsCalls.map((call) => call.revision), [99]);
    expect(client.settings.state.settingsRevision, 1);
    expect(client.settings.state.canonical!.instructions.user, isEmpty);
    final operation = client.mutations
        .latest('settings:instructions:user')!
        .state
        .value;
    expect(
      operation.phase,
      OperationPhase.rejected,
      reason: 'The old RPC was definitely rejected, even though its retry owner retired',
    );
    expect(operation.error, same(conflict));
    expect((await client.close()).complete, isTrue);
  });

  test('settings owner change joins a sent RPC but cannot apply its late response to the new owner', () async {
    final transport = _Transport()..settingsReply = (call) => call.reply.future;
    final client = await _client(transport);
    client.applyBootstrap(_bootstrap('old', _settings(99)));
    final old = client.settingsCommands.applySettingsField(
      const InstructionUserCommand('old-owner-input'),
    );
    final failure = expectLater(old, throwsStateError);
    final call = await transport.settingsCall(0);
    client.applyBootstrap(_bootstrap('next', _settings(1)));
    var closed = false;
    final closing = client.close().then((report) {
      closed = true;
      return report;
    });
    expect(closed, isFalse);
    call.reply.complete(
      SettingsCommandReply(
        snapshot: SettingsStateSnapshot(
          revision: 100,
          instructions: const InstructionsSettingsView(user: 'late-old-reply'),
        ),
        receipt: StudioCommandReceipt(
          operationId: call.operationId,
          disposition: CommitDisposition.applied,
          targets: const [
            ResourceStamp(
              resourceKey: 'settings',
              ownerEpoch: 'old',
              revision: 100,
            ),
          ],
          effect: EffectPoint.futureSession,
          effective: false,
          durable: true,
        ),
      ),
    );
    await failure;
    final report = await closing;
    expect(closed, isTrue);
    expect(transport.settingsCalls, hasLength(1));
    expect(client.settings.state.settingsRevision, 1);
    expect(client.settings.state.canonical!.instructions.user, isEmpty);
    final operation = client.mutations
        .latest('settings:instructions:user')!
        .state
        .value;
    expect(operation.receipt!.operationId, call.operationId);
    expect(operation.durable, isTrue);
    expect(operation.observed, isFalse);
    expect(operation.phase, OperationPhase.syncFailed);
    expect(
      report.unresolved.any(
        (resource) => resource.owner == 'settings-commands',
      ),
      isFalse,
      reason: 'The RPC was really joined, not detached by the owner switch',
    );
    expect(
      report.unresolved.any(
        (resource) => resource.owner == 'operation:${call.operationId.value}',
      ),
      isTrue,
      reason: 'A retired owner observation is honestly unresolved, not satisfied by the new baseline',
    );
  });

  test('thread route owner change rejects a queued intent on the same shared write lane', () async {
    final transport = _Transport()
      ..routeReply = (_) => Future.error(_probeRejection);
    late AccountsTestRuntime runtime;
    final client = await _client(
      transport,
      onRuntime: (value) => runtime = value,
    );
    client.applyBootstrap(_bootstrap('old', _settings(99)));
    transport.epoch = 'old';
    runtime.seed(_settings(99));
    final entered = Completer<void>();
    final release = Completer<void>();
    final blocking = client.settingsWrites.enqueue(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final old = client.threadCommands.setThreadModelRoute(
      threadId: 'thread',
      accountId: 'account',
      modelId: 'beta',
    );
    final rejected = expectLater(old, throwsStateError);
    client.applyBootstrap(_bootstrap('next', _settings(1)));
    transport.epoch = 'next';
    runtime.seed(_settings(1));
    release.complete();
    await blocking;
    await rejected;
    expect(transport.routeCalls, isEmpty);
    expect(
      client.mutations.latest('thread-route:thread')!.state.value.phase,
      OperationPhase.rejected,
    );
    expect(client.settings.state.commands, isEmpty);
    expect((await client.close()).complete, isTrue);
  });

  test('thread route owner change during settings refresh cannot publish or retry an old request', () async {
    const conflict = StudioFailure(
      code: StudioFailureCode.staleRevision,
      message: 'Old route settings changed',
      retryable: true,
      correlationId: 'route-owner-conflict',
    );
    final transport = _Transport()..routeReply = (_) => Future.error(conflict);
    final read = Completer<SettingsStateSnapshot>();
    transport.settingsRead = () => read.future;
    late AccountsTestRuntime runtime;
    final client = await _client(
      transport,
      onRuntime: (value) => runtime = value,
    );
    client.applyBootstrap(_bootstrap('old', _settings(99)));
    transport.epoch = 'old';
    runtime.seed(_settings(99));
    final old = client.threadCommands.setThreadModelRoute(
      threadId: 'thread',
      accountId: 'account',
      modelId: 'beta',
    );
    final rejected = expectLater(old, throwsStateError);
    await transport.settingsReadEntered.future;
    client.applyBootstrap(_bootstrap('next', _settings(1)));
    transport.epoch = 'next';
    runtime.seed(_settings(1));
    read.complete(_settings(100));
    await rejected;
    expect(transport.routeCalls.map((call) => call.expectedSettingsRevision), [
      99,
    ]);
    expect(client.settings.state.settingsRevision, 1);
    final operation = client.mutations
        .latest('thread-route:thread')!
        .state
        .value;
    expect(operation.phase, OperationPhase.rejected);
    expect(operation.error, same(conflict));
    expect((await client.close()).complete, isTrue);
  });

  test('thread route owner change joins the sent response without applying old settings or warnings', () async {
    final transport = _Transport();
    late AccountsTestRuntime runtime;
    final client = await _client(
      transport,
      onRuntime: (value) => runtime = value,
    );
    client.applyBootstrap(_bootstrap('old', _settings(99)));
    transport.epoch = 'old';
    runtime.seed(_settings(99));
    final entered = transport.routes.stream.first;
    final failure = expectLater(
      client.threadCommands.setThreadModelRoute(
        threadId: 'thread',
        accountId: 'account',
        modelId: 'beta',
      ),
      throwsStateError,
    );
    final call = await entered;
    client.applyBootstrap(_bootstrap('next', _settings(1)));
    transport.epoch = 'next';
    runtime.seed(_settings(1));
    var closed = false;
    final closing = client.close().then((report) {
      closed = true;
      return report;
    });
    expect(closed, isFalse);
    call.reply.complete(
      ThreadModelRouteCommandReply(
        runtime: _runtime(routeRevision: 4),
        settings: _settings(100),
        modeDefaultSaved: true,
        warning: 'old-owner-warning',
        receipt: StudioCommandReceipt(
          operationId: call.operationId,
          disposition: CommitDisposition.applied,
          targets: const [
            ResourceStamp(
              resourceKey: 'settings',
              ownerEpoch: 'old',
              revision: 100,
            ),
          ],
          effect: EffectPoint.futureSession,
          effective: false,
          durable: true,
        ),
      ),
    );
    await failure;
    final report = await closing;
    expect(closed, isTrue);
    expect(transport.routeCalls, hasLength(1));
    expect(client.settings.state.settingsRevision, 1);
    expect(client.threadCommands.state.warnings, isEmpty);
    final operation = client.mutations
        .latest('thread-route:thread')!
        .state
        .value;
    expect(operation.receipt!.operationId, call.operationId);
    expect(operation.phase, OperationPhase.syncFailed);
    expect(operation.observed, isFalse);
    expect(
      report.unresolved.any((resource) => resource.owner == 'thread-commands'),
      isFalse,
    );
    expect(
      report.unresolved.any(
        (resource) => resource.owner == 'operation:${call.operationId.value}',
      ),
      isTrue,
    );
  });

  test('thread route owner change while joining runtime resync prevents another CAS attempt', () async {
    final transport = _RouteConflictTransport();
    late AccountsTestRuntime runtime;
    final client = await _client(
      transport,
      onRuntime: (value) => runtime = value,
    );
    client.selection.markOpened();
    final session = client.conversations.existingSession('thread')!;
    await session.deliverWorkspace(_workspace(revision: 40, routeRevision: 2));
    await session.content.ready;
    final failure = expectLater(
      client.threadCommands.setThreadModelRoute(
        threadId: 'thread',
        accountId: 'account',
        modelId: 'beta',
      ),
      throwsStateError,
    );
    await transport.refreshEntered.future;
    client.applyBootstrap(_bootstrap('next', _settings(1)));
    transport.epoch = 'next';
    runtime.seed(_settings(1));
    await session.deliverWorkspace(_workspace(revision: 80, routeRevision: 3));
    await failure;
    expect(transport.attempts, hasLength(1));
    expect(client.settings.state.settingsRevision, 1);
    expect(
      client.mutations.latest('thread-route:thread')!.state.value.phase,
      OperationPhase.rejected,
    );
    expect((await client.close()).complete, isTrue);
  });

  test('thread route rechecks recovery after queueing and does not confuse execution or unrelated access with its own access gate', () async {
    final transport = _Transport()
      ..routeReply = (_) => Future.error(_probeRejection);
    final client = await _client(transport);
    final entered = Completer<void>();
    final release = Completer<void>();
    final blocking = client.settingsWrites.enqueue(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final blocked = expectLater(
      client.threadCommands.setThreadModelRoute(
        threadId: 'thread',
        accountId: 'account',
        modelId: 'beta',
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => recoveryIssueFromFailure(failure)?.id,
          'exact recovery owner',
          _threadAccessIssue.id,
        ),
      ),
    );
    client.recovery.apply(
      RecoveryStateSnapshot(revision: 2, values: const [_threadAccessIssue]),
    );
    release.complete();
    await blocking;
    await blocked;
    expect(transport.routeCalls, isEmpty);
    expect(
      client.mutations.latest('thread-route:thread')!.state.value.phase,
      OperationPhase.rejected,
    );

    client.recovery.apply(
      RecoveryStateSnapshot(
        revision: 3,
        values: const [
          StudioRecoveryIssue(
            id: 'project-access-unavailable',
            scope: RecoveryIssueScope.project,
            category: RecoveryIssueCategory.repository,
            impact: RecoveryIssueImpact.accessBlocked,
            availableActions: [],
            workspaceId: 'project',
            detail: 'Only Project operations are blocked',
          ),
          StudioRecoveryIssue(
            id: 'child-access-unavailable',
            scope: RecoveryIssueScope.thread,
            category: RecoveryIssueCategory.storage,
            impact: RecoveryIssueImpact.accessBlocked,
            availableActions: [],
            threadId: 'child',
            detail: 'Only the child history is inaccessible',
          ),
          StudioRecoveryIssue(
            id: 'thread-worktree-unavailable',
            scope: RecoveryIssueScope.thread,
            category: RecoveryIssueCategory.repository,
            impact: RecoveryIssueImpact.executionBlocked,
            availableActions: [],
            threadId: 'thread',
            detail: 'Execution is paused, not route settings access',
          ),
        ],
      ),
    );
    await expectLater(
      client.threadCommands.setThreadModelRoute(
        threadId: 'thread',
        accountId: 'account',
        modelId: 'beta',
      ),
      throwsA(same(_probeRejection)),
    );
    expect(transport.routeCalls, hasLength(1));
  });

  for (final checkpoint in ['settings refresh', 'runtime baseline']) {
    test(
      'thread route recovery during $checkpoint prevents CAS redispatch and preserves the issued conflict',
      () async {
        final transport = _RouteConflictTransport();
        final read = Completer<SettingsStateSnapshot>();
        if (checkpoint == 'settings refresh') {
          transport.settingsRead = () => read.future;
        }
        final client = await _client(transport);
        client.selection.markOpened();
        final session = client.conversations.existingSession('thread')!;
        await session.deliverWorkspace(
          _workspace(revision: 40, routeRevision: 3),
        );
        final rejected = expectLater(
          client.threadCommands.setThreadModelRoute(
            threadId: 'thread',
            accountId: 'account',
            modelId: 'beta',
          ),
          throwsA(
            isA<StudioFailure>().having(
              (failure) => recoveryIssueFromFailure(failure)?.id,
              'current recovery gate',
              _threadAccessIssue.id,
            ),
          ),
        );
        if (checkpoint == 'settings refresh') {
          await transport.settingsReadEntered.future;
        } else {
          await transport.refreshEntered.future;
        }
        client.recovery.apply(
          RecoveryStateSnapshot(
            revision: 2,
            values: const [_threadAccessIssue],
          ),
        );
        if (checkpoint == 'settings refresh') {
          read.complete(_settings(2));
        } else {
          await session.deliverWorkspace(
            _workspace(revision: 80, routeRevision: 4),
          );
        }
        await rejected;
        expect(transport.attempts, hasLength(1));
        final operation = client.mutations
            .latest('thread-route:thread')!
            .state
            .value;
        expect(operation.phase, OperationPhase.rejected);
        expect(
          operation.error,
          isA<StudioFailure>()
              .having(
                (failure) => failure.code,
                'issued outcome',
                StudioFailureCode.conflict,
              )
              .having(
                (failure) => failure.correlationId,
                'original request',
                'route-conflict',
              ),
        );
      },
    );
  }

  test('issued thread route transport failure remains unknown after access recovery changes', () async {
    final transport = _Transport();
    final client = await _client(transport);
    final lostReceipt = StateError('Route response was lost');
    final entered = transport.routes.stream.first;
    final failed = expectLater(
      client.threadCommands.setThreadModelRoute(
        threadId: 'thread',
        accountId: 'account',
        modelId: 'beta',
      ),
      throwsA(same(lostReceipt)),
    );
    final call = await entered;
    client.recovery.apply(
      RecoveryStateSnapshot(revision: 2, values: const [_threadAccessIssue]),
    );
    call.reply.completeError(lostReceipt);
    await failed;
    expect(transport.routeCalls, hasLength(1));
    final operation = client.mutations
        .latest('thread-route:thread')!
        .state
        .value;
    expect(operation.phase, OperationPhase.unknownOutcome);
    expect(operation.error, same(lostReceipt));
    expect(operation.receipt, isNull);
  });

  for (final scope in [
    RecoveryIssueScope.application,
    RecoveryIssueScope.thread,
  ]) {
    test(
      'archive preserves the real ${scope.name} access blocker and the live session',
      () async {
        final transport = _Transport();
        final client = await _client(transport);
        final session = client.conversations.existingSession('thread')!;
        final issue = StudioRecoveryIssue(
          id: 'archive-access-unavailable',
          scope: scope,
          category: RecoveryIssueCategory.storage,
          impact: RecoveryIssueImpact.accessBlocked,
          availableActions: const [RecoveryIssueAction.retry],
          threadId: scope == RecoveryIssueScope.thread ? 'thread' : null,
          detail: 'The archive target storage is inaccessible',
        );
        client.recovery.apply(
          RecoveryStateSnapshot(revision: 2, values: [issue]),
        );
        await expectLater(
          client.threadCommands.archiveThread('thread'),
          throwsA(
            isA<StudioFailure>().having(
              (failure) => recoveryIssueFromFailure(failure)?.scope,
              'original access scope',
              scope,
            ),
          ),
        );
        expect(transport.archiveCalls, isEmpty);
        expect(session.isActive, isTrue);
        final operation = client.mutations
            .latest('archive:thread')!
            .state
            .value;
        expect(operation.phase, OperationPhase.rejected);
        expect(operation.receipt, isNull);
      },
    );
  }

  test('archive accepts a blocked repository-recovery root and releases its session', () async {
    final transport = _Transport();
    final client = await _client(transport);
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
              impact: RecoveryIssueImpact.executionBlocked,
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
        updaterState: DisabledUpdaterStateSnapshot(
          revision: 1,
          updatedAt: DateTime.utc(2026),
        ),
        persistenceState: const PersistenceStateSnapshot.ready(),
      ),
    );
    client.selection.restoreStartup(
      workspaceId: 'project',
      threadId: 'thread',
      needsOpen: true,
    );
    final session = client.conversations.session('thread');
    expect(session.isActive, isTrue);

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
    final client = await _client(transport);
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

  test('route conflict resync replaces its combined feed and awaits the new baseline', () async {
    final transport = _RouteConflictTransport();
    final client = await _client(transport);
    client.selection.markOpened();
    final session = client.conversations.existingSession('thread')!;
    await session.deliverWorkspace(_workspace(revision: 40, routeRevision: 2));
    await session.content.ready;
    await session.deliverNotification(
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
    await session.deliverWorkspace(_workspace(revision: 7, routeRevision: 4));
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
    await session.source.waitFor((state) => state.revision == 8);
    expect(session.state.revision, 8);
    expect(session.state.runtime!.modelId, 'alpha');
    expect(session.state.sync.phase, DomainSyncPhase.ready);
    final delivered = _completionConsumers[client]!.frames.single;
    expect(
      (delivered as ConversationBaselineFrame)
          .baseline
          .completedCursor
          .appendSeq,
      300,
    );
    expect(transport.windowOpens, 2);
    expect(transport.bindings, hasLength(2));
  });

  for (final closeClient in [false, true]) {
    test(
      'route resync baseline wait ends on ${closeClient ? 'Client close' : 'Session retire'} while cleanup stays owned',
      () async {
        final cancelEntered = Completer<void>();
        final cleanup = Completer<void>();
        final transport = _RouteConflictTransport(
          onFeedClose: (index) {
            if (index != 1) return Future.value();
            cancelEntered.complete();
            return cleanup.future;
          },
        );
        final client = await _client(transport);
        addTearDown(() {
          if (!cleanup.isCompleted) cleanup.complete();
        });
        client.selection.markOpened();
        final session = client.conversations.existingSession('thread')!;
        await session.deliverWorkspace(
          _workspace(revision: 40, routeRevision: 3),
        );
        await session.content.ready;
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
            : client.conversations.close(deadline: DateTime.utc(2000));
        await cancelEntered.future;
        await rejected;
        expect(
          transport.attempts,
          hasLength(1),
          reason: 'Retired observation cannot replay even a known conflict',
        );
        final retiring = client.budget.usage
            .where((resource) => resource.owner.startsWith('thread:'))
            .toList();
        expect(retiring, isNotEmpty);
        expect(
          retiring.map((resource) => resource.phase),
          everyElement(ResourcePhase.retiring),
        );
        if (!closeClient) {
          final report = await closing;
          expect(report.complete, isFalse);
          expect(
            report.unresolved.map((resource) => resource.owner),
            contains('conversation:thread'),
          );
        }
        cleanup.complete();
        if (closeClient) {
          expect((await closing).complete, isTrue);
        } else {
          expect((await client.conversations.retryCleanup()).complete, isTrue);
        }
        expect(
          client.budget.usage.where(
            (resource) => resource.owner.startsWith('thread:'),
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
        onFeedClose: (index) {
          if (index != 0) return Future.value();
          cancelEntered.complete();
          return cleanup.future;
        },
      );
      final client = await _client(transport);
      addTearDown(() {
        if (!cleanup.isCompleted) cleanup.complete();
      });
      client.selection.markOpened();
      final session = client.conversations.existingSession('thread')!;
      await session.deliverWorkspace(
        _workspace(revision: 40, routeRevision: 3),
      );
      await session.content.ready;
      final changing = client.threadCommands.setThreadModelRoute(
        threadId: 'thread',
        accountId: 'account',
        modelId: 'alpha',
      );
      final rejected = expectLater(changing, throwsA(isA<StudioFailure>()));
      await cancelEntered.future;
      expect(transport.bindings, hasLength(2));
      expect(transport.refreshEntered.isCompleted, isTrue);
      final closing = client.close();
      await rejected;
      expect(transport.attempts, hasLength(1));
      final retiring = client.budget.usage
          .where((resource) => resource.owner.startsWith('thread:'))
          .toList();
      expect(retiring, isNotEmpty);
      expect(
        retiring.map((resource) => resource.phase),
        everyElement(ResourcePhase.retiring),
      );
      cleanup.complete();
      expect((await closing).complete, isTrue);
      expect(
        transport.bindings,
        hasLength(2),
        reason: 'close prevents any further replacement',
      );
      expect(
        client.budget.usage.where(
          (resource) => resource.owner.startsWith('thread:'),
        ),
        isEmpty,
      );
    },
  );

  test('execution recovery does not gate an explicit stop request', () async {
    final transport = _Transport();
    final client = await _client(transport);
    await client.conversations
        .session('thread')
        .deliverWorkspace(
          _workspace(activeTurn: _turn(), execution: _execution()),
        );
    client.recovery.apply(
      RecoveryStateSnapshot(
        revision: 2,
        values: const [
          StudioRecoveryIssue(
            id: 'execution-paused',
            scope: RecoveryIssueScope.thread,
            category: RecoveryIssueCategory.storage,
            impact: RecoveryIssueImpact.executionBlocked,
            availableActions: [],
            workspaceId: 'project',
            threadId: 'thread',
            detail: 'New work is paused while storage is repaired',
          ),
        ],
      ),
    );

    final entered = transport.stops.stream.first;
    final stopping = client.threadCommands.stop('thread');
    final call = await entered;
    expect(transport.stopCalls, 1);
    expect(call.threadId, 'thread');
    expect(call.executionId, 'execution-1');
    call.reply.complete(
      StopThreadCommandReply(
        threadId: call.threadId,
        executionId: call.executionId,
        stopped: true,
        receipt: _identityReceipt(call.operationId),
      ),
    );
    expect(await stopping, isA<StopRequested>());
    await client.close();
  });

  for (final framesFirst in [false, true]) {
    for (final stopped in [false, true]) {
      test(
        'actual stop targets the captured execution identity (framesFirst=$framesFirst, stopped=$stopped)',
        () async {
          final transport = _Transport();
          final client = await _client(transport);
          await client.conversations
              .session('thread')
              .deliverWorkspace(
                _workspace(activeTurn: _turn(), execution: _execution()),
              );
          final entered = transport.stops.stream.first;
          final stopping = client.threadCommands.stop('thread');
          final operation = client.mutations.latest('stop:thread')!;
          int commandObservers() => client.budget.usage
              .where(
                (resource) =>
                    resource.kind == ResourceKind.observer &&
                    resource.owner == 'command:${operation.id.value}',
              )
              .length;
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
          expect(commandObservers(), 1);
          client.selection.restoreStartup(
            workspaceId: 'project',
            threadId: 'another-thread',
            needsOpen: true,
          );
          if (framesFirst) {
            await client.conversations
                .session('thread')
                .deliverWorkspace(_workspace(revision: 2, activeTurn: null));
          }
          expect(
            commandObservers(),
            1,
            reason: 'Canonical facts alone cannot release the receipt barrier',
          );
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
            await _applyOwnerUpdate(
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
            expect(commandObservers(), 1);
            await client.conversations
                .session('thread')
                .deliverWorkspace(_workspace(revision: 2, activeTurn: null));
          }
          expect(operation.state.value.observed, isTrue);
          expect(operation.state.value.effective, isTrue);
          expect(operation.state.value.durable, isFalse);
          expect(
            client.threadCommands.state.commands,
            isNot(contains('stop:thread')),
          );
          expect(
            commandObservers(),
            0,
            reason: 'Only this operation owns its command observer permit; selection changes topic permits independently',
          );
        },
      );
    }

    test(
      'actual interaction waits for owner removal (framesFirst=$framesFirst)',
      () async {
        final transport = _Transport();
        final client = await _client(transport);
        final interaction = _interaction();
        await client.conversations
            .session('thread')
            .deliverWorkspace(_workspace(interactions: [interaction]));
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
          await _applyOwnerUpdate(
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
            client.conversations
                .session('thread')
                .state
                .interactions
                .map((item) => item.id),
            contains(interaction.id),
            reason: 'The response never deletes canonical facts',
          );
          expect(
            client.threadCommands.state.commands['interaction:thread']?.phase,
            CommandPhase.pending,
          );
          await _applyOwnerUpdate(
            client,
            ThreadInteractionUpdate(
              interaction: _interaction('unrelated'),
              pending: false,
            ),
          );
          expect(operation.state.value.observed, isFalse);
          await _applyOwnerUpdate(
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

  test(
    'queued interaction rechecks Recovery before transport invocation',
    () async {
      final transport = _Transport();
      final client = await _client(transport);
      const projectIssue = StudioRecoveryIssue(
        id: 'project-preparation-unavailable',
        scope: RecoveryIssueScope.project,
        category: RecoveryIssueCategory.repository,
        impact: RecoveryIssueImpact.executionBlocked,
        availableActions: [],
        workspaceId: 'project',
        detail:
            'Only Project preparation is blocked until a Thread issue arrives',
      );
      client.recovery.apply(
        RecoveryStateSnapshot(revision: 2, values: const [projectIssue]),
      );
      final compacting = client.threadCommands.compactThread('thread');
      await transport.compactEntered.future;

      final interaction = _interaction();
      await client.conversations
          .session('thread')
          .deliverWorkspace(_workspace(interactions: [interaction]));
      final resolving = client.threadCommands.resolveActiveInteraction(
        'thread',
        interaction.id,
        _resolution,
      );
      final operation = client.mutations.latest('interaction:thread')!;
      client.recovery.apply(
        RecoveryStateSnapshot(
          revision: 3,
          values: [
            projectIssue,
            StudioRecoveryIssue(
              id: 'queued-interaction-block',
              scope: RecoveryIssueScope.thread,
              category: RecoveryIssueCategory.repository,
              impact: RecoveryIssueImpact.executionBlocked,
              availableActions: const [RecoveryIssueAction.retry],
              threadId: 'thread',
              detail: 'Interaction execution must wait for recovery',
            ),
          ],
        ),
      );

      transport.compactions.single.complete();
      await compacting;
      await expectLater(
        resolving,
        throwsA(
          isA<StudioFailure>()
              .having(
                (failure) => failure.code,
                'code',
                StudioFailureCode.permissionDenied,
              )
              .having(
                (failure) => recoveryIssueFromFailure(failure)?.id,
                'issue id',
                'queued-interaction-block',
              ),
        ),
      );
      expect(transport.interactionCalls, 0);
      expect(operation.state.value.phase, OperationPhase.rejected);
      expect(operation.state.value.receipt, isNull);
    },
  );

  test('old interaction ACK cannot clear a newer interaction intent', () async {
    final transport = _Transport();
    final client = await _client(transport);
    final x = _interaction('x');
    final y = _interaction('y');
    await client.conversations
        .session('thread')
        .deliverWorkspace(_workspace(interactions: [x]));
    final enteredX = transport.interactions.stream.first;
    final resolvingX = client.threadCommands.resolveActiveInteraction(
      'thread',
      x.id,
      _resolution,
    );
    final callX = await enteredX;
    await _applyOwnerUpdate(
      client,
      ThreadInteractionUpdate(interaction: x, pending: false),
    );
    await _applyOwnerUpdate(
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
    await _applyOwnerUpdate(
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
        final client = await _client(transport);
        final entered = transport.modes.stream.first;
        final changing = client.threadCommands.setThreadMode(
          ThreadModeId.task,
          threadId: 'thread',
        );
        final call = await entered;
        expect(call.operationId, client.mutations.latest('mode:thread')!.id);
        final receipt = _receipt(call.operationId, [
          _stamp('thread-state:thread', 2),
          _stamp('thread-directory', 2),
        ]);

        if (framesFirst) {
          await client.conversations
              .session('thread')
              .deliverWorkspace(_workspace(revision: 2));
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
          await client.conversations
              .session('thread')
              .deliverWorkspace(_workspace(revision: 2));
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
      final client = await _client(transport);
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

      await client.conversations
          .session('thread')
          .deliverWorkspace(_workspace(revision: 2, routeRevision: 2));
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
        client.conversations
            .session('thread')
            .state
            .runtime
            ?.modelRoute
            ?.modelId,
        'alpha',
        reason: 'A control response does not write the Thread mirror',
      );
      await client.conversations
          .session('thread')
          .deliverWorkspace(
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

  test(
    'a captured mode action keeps its target after selection changes',
    () async {
      final transport = _Transport();
      final client = await _client(transport);
      final oldAction = () => client.threadCommands.setThreadMode(
        ThreadModeId.task,
        threadId: 'thread',
      );
      client.selection.selectThread(workspaceId: 'project', threadId: 'other');
      final entered = transport.modes.stream.first;
      final changing = oldAction();
      final call = await entered;
      expect(call.threadId, 'thread');
      expect(client.mutations.latest('mode:other'), isNull);
      call.reply.complete(
        ThreadModeCommandReply(
          receipt: _receipt(call.operationId, [
            _stamp('thread-state:thread', 1),
            _stamp('thread-directory', 1),
          ], disposition: CommitDisposition.noChange),
        ),
      );
      await changing;
    },
  );

  test('actual mode command preserves explicit NoChange with equal resource versions', () async {
    final transport = _Transport();
    final client = await _client(transport);
    final entered = transport.modes.stream.first;
    final changing = client.threadCommands.setThreadMode(
      ThreadModeId.task,
      threadId: 'thread',
    );
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
      final client = await _client(transport);
      final entered = transport.modes.stream.first;
      final changing = client.threadCommands.setThreadMode(
        ThreadModeId.task,
        threadId: 'thread',
      );
      final call = await entered;
      var settled = false;
      final closing = client.threadCommands.close().then((_) {
        settled = true;
      });
      expect(settled, isFalse);
      expect(
        () => client.threadCommands.setThreadMode(
          ThreadModeId.task,
          threadId: 'thread',
        ),
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
    final client = await _client(transport);
    await client.conversations
        .session('thread')
        .deliverWorkspace(
          _workspace(activeTurn: _turn(), execution: _execution()),
        );
    final feedCount = transport.threadBindings.length;
    final blockerEntered = transport.stops.stream.first;
    final blocking = client.threadCommands.stop(
      'blocker-thread',
      expectedExecutionId: 'blocker-execution',
    );
    final blocker = await blockerEntered;
    expect(blocker.threadId, 'blocker-thread');
    expect(blocker.executionId, 'blocker-execution');
    final stopping = client.threadCommands.stop('thread');
    final operation = client.mutations.latest('stop:thread')!;
    final rejected = expectLater(
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
    // The in-flight explicit target holds the real stop lane. Deliver the
    // successor through the visible feed before releasing that lane, rather
    // than depending on an async delivery winning a microtask race.
    await client.conversations
        .session('thread')
        .deliverWorkspace(
          _workspace(
            revision: 2,
            activeTurn: _turn(turnId: 'turn-2'),
            execution: _execution(id: 'execution-2', turnId: 'turn-2'),
          ),
        );
    expect(transport.stopCalls, 1);
    expect(operation.state.value.receipt, isNull);
    expect(operation.state.value.observed, isFalse);
    blocker.reply.complete(
      StopThreadCommandReply(
        threadId: blocker.threadId,
        executionId: blocker.executionId,
        stopped: true,
        receipt: _identityReceipt(blocker.operationId),
      ),
    );
    expect(await blocking, isA<StopRequested>());
    await rejected;
    expect(
      transport.stopCalls,
      1,
      reason: 'The obsolete target and its successor must never be dispatched',
    );
    expect(
      transport.threadBindings,
      hasLength(feedCount),
      reason: 'The explicit blocker target must not create a hidden feed',
    );
    expect(operation.state.value.receipt, isNull);
    expect(operation.state.value.observed, isFalse);
    expect(operation.state.value.effective, isFalse);
    final status = client.threadCommands.state.commands['stop:thread'];
    expect(status?.phase, CommandPhase.failed);
    expect(status?.error?.reason, StudioFailureReason.staleExecution);
    expect(status?.target.label, 'execution-1');
  });

  test(
    'child row stop uses the directory execution without selecting the member',
    () async {
      final transport = _Transport();
      final client = await _client(transport);
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
        client.conversations.sessionStates.map((state) => state.threadId),
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
        client.conversations.sessionStates.map((state) => state.threadId),
        isNot(contains('child')),
      );
    },
  );

  test('a child row without a stop qualification is not sent and an unloaded page is not an end', () async {
    final transport = _Transport();
    final client = await _client(transport);
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
    final client = await _client(transport);
    // The interface may still hold a stale "busy" view; the canonical owner has
    // no execution, so no request may be fabricated for it.
    await client.conversations
        .session('thread')
        .deliverWorkspace(_workspace(activeTurn: _turn()));
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
    final client = await _client(transport);
    await client.conversations
        .session('thread')
        .deliverWorkspace(
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
    await client.conversations
        .session('thread')
        .deliverWorkspace(_workspace(revision: 2, activeTurn: null));
    expect(
      client.threadCommands.state.commands,
      isNot(contains('stop:thread')),
    );
  });

  test(
    'a stop rejected before acceptance never claims an accepted receipt',
    () async {
      final transport = _Transport();
      final client = await _client(transport);
      await client.conversations
          .session('thread')
          .deliverWorkspace(
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
      final client = await _client(transport);
      await client.conversations
          .session('thread')
          .deliverWorkspace(
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
    final client = await _client(transport);
    await client.conversations
        .session('thread')
        .deliverWorkspace(
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
      workspaceId: 'project',
      threadId: 'thread',
      needsOpen: true,
    );
    client.conversations
        .session('thread')
        .content
        .attachConsumer(TestCompletionConsumer());
    client.conversations.setVisibleThread('thread');
    await client.conversations
        .session('thread')
        .deliverWorkspace(
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
    await client.conversations
        .session('thread')
        .deliverWorkspace(
          _workspace(
            revision: 2,
            activeTurn: _turn(turnId: 'turn-2'),
            execution: _execution(id: 'execution-2', turnId: 'turn-2'),
          ),
        );
    clock += 5000;
    final failedStartedAt = clock;
    final retryEntered = transport.stops.stream.first;
    final retrying = client.threadCommands.stop('thread');
    final rejected = expectLater(retrying, throwsA(same(_probeRejection)));
    expect(
      client.threadCommands.state.commands['stop:thread']?.startedAtMs,
      failedStartedAt,
    );
    final retry = await retryEntered;
    expect(retry.executionId, 'execution-2');
    clock += 5000;
    retry.reply.completeError(_probeRejection);
    await rejected;
    final failed = client.threadCommands.state.commands['stop:thread']!;
    expect(failed.phase, CommandPhase.failed);
    expect(failed.error, same(_probeRejection));
    expect(failed.accepted, isFalse);
    expect(
      failed.startedAtMs,
      failedStartedAt,
      reason: 'Failure preserves this attempt’s registration time, not the failure time or the previous attempt’s start',
    );
    expect(accepted.startedAtMs, 1700000000000);
  });

  test('a frozen expected execution is sent as-is and the server owns the staleness verdict', () async {
    final transport = _Transport();
    final client = await _client(transport);
    // The interface rendered execution-1; canonical already moved to execution-2.
    await client.conversations
        .session('thread')
        .deliverWorkspace(
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
      final client = await _client(transport);
      await client.conversations
          .session('thread')
          .deliverWorkspace(_workspace(activeTurn: _turn()));
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
    final client = await _client(transport);
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

  for (final ordering in [
    'receipt first',
    'observation first',
    'new intent during acceptance',
    'synchronous synchronization failure',
  ]) {
    test(
      'continue is admitted once, observed as a new Turn and re-read by identity instead of resent ($ordering)',
      () async {
        final framesFirst = ordering == 'observation first';
        final reenter = ordering == 'new intent during acceptance';
        final syncFailure = ordering == 'synchronous synchronization failure';
        final transport = _Transport();
        final client = await _client(transport);
        client.conversations.setVisibleThread('thread');
        await client.conversations
            .session('thread')
            .deliverWorkspace(_workspace());
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
        expect(
          client.threadCommands.state.commands['continue:thread']?.accepted,
          isFalse,
        );
        Future<_ContinueCall>? newerEntered;
        Future<ContinueThreadCommandReply>? newerContinuing;
        OperationHandle? newerOperation;
        final failure = StateError(
          'continuation acceptance synchronization failed',
        );
        var failedSync = false;
        final acceptance = operation.state.watch((next) {
          if (next.receipt == null) return;
          if (syncFailure && !failedSync) {
            failedSync = true;
            operation.syncFailed(failure);
            return;
          }
          if (!reenter || newerContinuing != null) return;
          newerEntered = transport.continues.stream.first;
          newerContinuing = client.threadCommands.continueThread(
            'thread',
            _continuation(id: 'continuation-2'),
            expectedModelRouteRevision: 1,
          );
          newerOperation = client.mutations.latest('continue:thread');
        });
        addTearDown(acceptance.cancel);
        final newTurn = _workspace(
          revision: 2,
          activeTurn: _turn(turnId: 'turn-continued'),
          execution: _execution(
            id: 'execution-continued',
            turnId: 'turn-continued',
          ),
        );
        if (framesFirst) {
          await client.conversations
              .session('thread')
              .deliverWorkspace(newTurn);
          expect(operation.state.value.observed, isFalse);
          expect(
            client.threadCommands.state.commands['continue:thread']?.accepted,
            isFalse,
            reason: 'Canonical facts cannot replace the acceptance receipt',
          );
        }
        final reply = ContinueThreadCommandReply(
          threadId: 'thread',
          inputId: operation.id.value,
          continuationId: 'continuation-1',
          cursor: 4,
          receipt: _identityReceipt(operation.id),
        );
        call.reply.complete(reply);
        expect(await continuing, same(reply));
        acceptance.cancel();
        expect(operation.state.value.receipt!.operationId, call.operationId);
        expect(
          operation.state.value.phase,
          syncFailure
              ? OperationPhase.syncFailed
              : framesFirst
              ? OperationPhase.effective
              : OperationPhase.awaitingObservation,
          reason: 'Admission does not prove a Turn started',
        );
        expect(
          operation.state.value.effective,
          framesFirst,
          reason: 'Continue acceptance alone is not effective',
        );
        final command = client.threadCommands.state.commands['continue:thread'];
        if (framesFirst) {
          expect(
            command,
            isNull,
            reason: 'Acceptance must not revive a cleared continuation command',
          );
        } else {
          expect(command?.phase, CommandPhase.pending);
          expect(command?.accepted, !reenter);
          expect(
            command?.target.label,
            reenter ? 'continuation-2' : 'continuation-1',
          );
        }
        if (syncFailure) {
          expect(operation.state.value.error, same(failure));
          expect(operation.state.value.observed, isFalse);
        }
        if (reenter) {
          expect(newerOperation, isNotNull);
          expect(newerOperation!.id, isNot(operation.id));
          expect(newerOperation!.state.value.receipt, isNull);
          expect(
            client.mutations.latest('continue:thread'),
            same(newerOperation),
          );
          final newerCall = await newerEntered!;
          expect(newerCall.operationId, newerOperation!.id);
          expect(newerCall.threadId, 'thread');
          expect(newerCall.continuationId, 'continuation-2');
          expect(newerCall.expectedModelRouteRevision, 1);
          final newerReply = ContinueThreadCommandReply(
            threadId: 'thread',
            inputId: newerCall.operationId.value,
            continuationId: 'continuation-2',
            cursor: 5,
            receipt: _identityReceipt(newerCall.operationId),
          );
          newerCall.reply.complete(newerReply);
          expect(await newerContinuing!, same(newerReply));
          expect(
            client.threadCommands.state.commands['continue:thread']?.accepted,
            isTrue,
            reason:
                'Only the newer continuation receipt accepts the newer intent',
          );
          expect(newerOperation!.state.value.observed, isFalse);
        }
        // The canonical new Turn is what proves the continuation became effective.
        if (!framesFirst) {
          await client.conversations
              .session('thread')
              .deliverWorkspace(newTurn);
        }
        // retainUntilSettled：带回执的 syncFailed 同样保留原 identity 观察，
        // canonical Turn 到达后观察完成并生效，无例外。
        expect(operation.state.value.observed, isTrue);
        expect(operation.state.value.effective, isTrue);
        if (syncFailure) {
          expect(operation.state.value.phase, OperationPhase.syncFailed);
          expect(
            operation.state.value.receipt,
            isNotNull,
            reason: 'Synchronization failure cannot erase a valid receipt',
          );
        }
        expect(
          client.threadCommands.state.commands,
          isNot(contains('continue:thread')),
        );
        if (reenter) expect(newerOperation!.state.value.observed, isTrue);
        expect(
          transport.continueCalls,
          reenter ? 2 : 1,
          reason: 'Exactly one request per distinct continuation intent',
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
          hasLength(reenter ? 2 : 1),
          reason: 'Re-reading never allocates a second operation',
        );
        expect(transport.continueCalls, reenter ? 2 : 1);
        expect(
          client.threadCommands.state.commands,
          isNot(contains('continue:thread')),
        );
      },
    );
  }

  test('execution-blocked continuation still reconciles the original identity without resending', () async {
    final transport = _Transport();
    final client = await _client(transport);
    client.conversations.setVisibleThread('thread');
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final entered = transport.continues.stream.first;
    final continuing = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    final call = await entered;
    call.reply.complete(
      ContinueThreadCommandReply(
        threadId: 'thread',
        inputId: call.operationId.value,
        continuationId: 'continuation-1',
        cursor: 4,
        receipt: _identityReceipt(call.operationId),
      ),
    );
    await continuing;
    final operation = client.mutations.latest('continue:thread')!;
    client.recovery.apply(
      RecoveryStateSnapshot(
        revision: 2,
        values: const [
          StudioRecoveryIssue(
            id: 'continue-execution-paused',
            scope: RecoveryIssueScope.thread,
            category: RecoveryIssueCategory.storage,
            impact: RecoveryIssueImpact.executionBlocked,
            availableActions: [],
            workspaceId: 'project',
            threadId: 'thread',
            detail: 'New execution is paused',
          ),
        ],
      ),
    );
    await client.conversations
        .session('thread')
        .deliverWorkspace(
          _workspace(
            revision: 3,
            activeTurn: _turn(turnId: 'turn-continued'),
            execution: _execution(
              id: 'execution-continued',
              turnId: 'turn-continued',
            ),
            storage: const ThreadStorageStateView(
              execution: ThreadStorageExecution.paused,
              resumeRequired: true,
              lastError: 'writer is waiting for explicit recovery',
            ),
          ),
        );

    // A lost receipt is reconciled by the original identity, never resent:
    // execution/storage 暂停不禁止这个只读回查。
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
    expect(transport.continueCalls, 1);
    expect(transport.continuationReadCalls, 1);
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

  test('a lost continue receipt resends the frozen input under the original identity', () async {
    final transport = _Transport();
    final client = await _client(transport);
    final entered = transport.continues.stream.first;
    final first = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    final call = await entered;
    final operation = client.mutations.latest('continue:thread')!;
    call.reply.completeError(StateError('continue response was lost'));
    await expectLater(first, throwsA(isA<StateError>()));
    expect(operation.state.value.phase, OperationPhase.unknownOutcome);

    // 后续点击传不同 route：仍按原身份回查；回查 NotFound 证明从未受理后，
    // 以冻结的原 route CAS 与同一 OperationId 再发。
    transport.continuationReadReply = null;
    final second = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 9,
    );
    final resent = await transport.continues.stream.first;
    expect(resent.operationId, call.operationId);
    expect(resent.expectedModelRouteRevision, 1);
    expect(resent.continuationId, call.continuationId);
    expect(transport.continuationReadCalls, 1);
    resent.reply.complete(
      ContinueThreadCommandReply(
        threadId: 'thread',
        inputId: resent.operationId.value,
        continuationId: resent.continuationId,
        cursor: 6,
        receipt: _identityReceipt(resent.operationId),
      ),
    );
    final reply = await second;
    expect(reply.inputId, resent.operationId.value);
    expect(transport.continueCalls, 2);
    expect(
      client.mutations.operations.where(
        (value) => value.target == 'continue:thread',
      ),
      hasLength(1),
      reason: '原身份再发不分配第二个操作',
    );
    expect(operation.state.value.receipt, isNotNull);
    expect(operation.state.value.failurePhase, isNull);
  });

  test(
    'a budget-exceeded continue begin fails closed without dangling joins',
    () async {
      final budget = ResourceBudget(
        capacities: {
          ...ResourceBudget().capacities,
          ResourceKind.pendingOperation: 0,
        },
      );
      final transport = _Transport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'budget-join',
        budget: budget,
      );
      addTearDown(client.close);
      // The first click gets the explicit typed rejection through its shared
      // join instead of a dangling future that later clicks await forever.
      final first = client.threadCommands.continueThread(
        'thread',
        _continuation(),
        expectedModelRouteRevision: 1,
      );
      await expectLater(first, throwsA(isA<ResourceBudgetExceeded>()));
      // The same intent re-clicks: the failed setup released the frozen
      // identity, so a retry walks the fresh path and fails equally closed.
      final second = client.threadCommands.continueThread(
        'thread',
        _continuation(),
        expectedModelRouteRevision: 1,
      );
      await expectLater(second, throwsA(isA<ResourceBudgetExceeded>()));
      expect(client.mutations.latest('continue:thread'), isNull);
      expect(budget.used(ResourceKind.pendingOperation), 0);
      expect(transport.continueCalls, 0);
    },
  );

  test('a determined rejection after NotFound resends nothing and keeps the identity', () async {
    final transport = _Transport();
    final client = await _client(transport);
    final entered = transport.continues.stream.first;
    final first = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    final call = await entered;
    final operation = client.mutations.latest('continue:thread')!;
    // A typed conflict from the transport is a determined rejection: the
    // intent keeps its frozen identity but never dispatches again.
    final conflict = StudioFailure(
      code: StudioFailureCode.conflict,
      message: 'The continuation point is already claimed',
      retryable: false,
      correlationId: 'client-test-conflict',
      reason: StudioFailureReason.continuationClaimed,
    );
    call.reply.completeError(conflict);
    await expectLater(first, throwsA(same(conflict)));
    expect(operation.state.value.failurePhase, OperationPhase.rejected);

    transport.continuationReadReply = null;
    final blocked = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    await expectLater(blocked, throwsA(same(conflict)));
    expect(transport.continuationReadCalls, 1);
    expect(transport.continueCalls, 1);
    expect(operation.state.value.failurePhase, OperationPhase.rejected);
    expect(
      client.mutations.operations.where(
        (value) => value.target == 'continue:thread',
      ),
      hasLength(1),
      reason: 'A determined rejection never re-begins or re-sends',
    );
  });

  for (final blocked in ['execution', 'closed', 'storage']) {
    test(
      'a resend blocked after NotFound keeps the unknown identity ($blocked)',
      () async {
        final transport = _Transport();
        final client = await _client(transport);
        final entered = transport.continues.stream.first;
        final first = client.threadCommands.continueThread(
          'thread',
          _continuation(),
          expectedModelRouteRevision: 1,
        );
        final call = await entered;
        final operation = client.mutations.latest('continue:thread')!;
        call.reply.completeError(StateError('response lost while blocked'));
        await expectLater(first, throwsA(isA<StateError>()));
        expect(operation.state.value.phase, OperationPhase.unknownOutcome);
        transport.continuationReadReply = null;

        if (blocked == 'execution') {
          client.recovery.apply(
            RecoveryStateSnapshot(
              revision: 2,
              values: const [
                StudioRecoveryIssue(
                  id: 'resend-execution-paused',
                  scope: RecoveryIssueScope.thread,
                  category: RecoveryIssueCategory.storage,
                  impact: RecoveryIssueImpact.executionBlocked,
                  availableActions: [],
                  workspaceId: 'project',
                  threadId: 'thread',
                  detail: 'Execution is paused before the resend',
                ),
              ],
            ),
          );
        } else if (blocked == 'closed') {
          client.threadDirectory.applyWindow(
            ThreadDirectoryWindow(
              threads: [_thread().copyWith(status: ThreadStatusView.closing)],
              revision: 2,
            ),
          );
        } else {
          await client.conversations
              .session('thread')
              .deliverWorkspace(
                _workspace(
                  revision: 2,
                  storage: const ThreadStorageStateView(
                    execution: ThreadStorageExecution.paused,
                    resumeRequired: true,
                    lastError: 'writer paused before the resend',
                  ),
                ),
              );
        }

        // 回查仍允许（只读），但再发被 guard 阻断：原 typed 错误返回调用方，
        // 意图、原 unknown 操作与观察责任保持不变，零新发送。
        final blockedClick = client.threadCommands.continueThread(
          'thread',
          _continuation(),
          expectedModelRouteRevision: 1,
        );
        Object? failure;
        try {
          await blockedClick;
        } on Object catch (error) {
          failure = error;
        }
        expect(failure, isA<StudioFailure>());
        expect(transport.continuationReadCalls, 1);
        expect(transport.continueCalls, 1);
        expect(operation.state.value.phase, OperationPhase.unknownOutcome);
        // The blocked resend leaves the original unknown disposition intact:
        // phase comes from failurePhase, so both must stay unknownOutcome.
        expect(
          operation.state.value.failurePhase,
          OperationPhase.unknownOutcome,
        );
        expect(
          client.mutations.operations.where(
            (value) => value.target == 'continue:thread',
          ),
          hasLength(1),
        );

        if (blocked == 'execution') {
          client.recovery.apply(
            RecoveryStateSnapshot(revision: 3, values: const []),
          );
        } else if (blocked == 'closed') {
          client.threadDirectory.applyWindow(
            ThreadDirectoryWindow(threads: [_thread()], revision: 3),
          );
        } else {
          await client.conversations
              .session('thread')
              .deliverWorkspace(_workspace(revision: 3));
        }
        // 解除后下一次点击仍先回查原身份；再次 NotFound 才以同 ID 再发。
        final retry = client.threadCommands.continueThread(
          'thread',
          _continuation(),
          expectedModelRouteRevision: 4,
        );
        final resent = await transport.continues.stream.first;
        expect(resent.operationId, call.operationId);
        expect(
          resent.expectedModelRouteRevision,
          1,
          reason: '冻结的原 route CAS 不被后续点击覆盖',
        );
        expect(
          transport.continuationReadCalls,
          2,
          reason: '不缓存 NotFound：每次点击都先回查',
        );
        resent.reply.complete(
          ContinueThreadCommandReply(
            threadId: 'thread',
            inputId: resent.operationId.value,
            continuationId: resent.continuationId,
            cursor: 7,
            receipt: _identityReceipt(resent.operationId),
          ),
        );
        await retry;
        expect(transport.continueCalls, 2);
      },
    );
  }

  test('continuation reentry shares one future and close releases the retained observer', () async {
    final transport = _Transport();
    final client = await _client(transport);
    var reentered = false;
    Future<ContinueThreadCommandReply>? reentrantJoin;
    final observation = client.threadCommands.source.watch((state) {
      if (state.commands.containsKey('continue:thread') && !reentered) {
        reentered = true;
        reentrantJoin = client.threadCommands.continueThread(
          'thread',
          _continuation(),
          expectedModelRouteRevision: 1,
        );
      }
    });
    final first = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    observation.cancel();
    expect(reentered, isTrue);
    expect(
      identical(reentrantJoin, first),
      isTrue,
      reason: '首次 begin 发布中的同步重入共享同一个 future',
    );
    final joined = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    expect(identical(joined, first), isTrue);
    final entered = transport.continues.stream.first;
    final call = await entered;
    final operation = client.mutations.latest('continue:thread')!;
    expect(transport.continueCalls, 1);
    call.reply.completeError(StateError('lost before observation'));
    await expectLater(first, throwsA(isA<StateError>()));
    expect(operation.state.value.phase, OperationPhase.unknownOutcome);
    int observers() => client.budget.usage
        .where(
          (resource) =>
              resource.kind == ResourceKind.observer &&
              resource.owner == 'command:${operation.id.value}',
        )
        .length;
    expect(observers(), 1, reason: 'unknown 期间保留原 identity 观察');
    await client.close();
    expect(
      observers(),
      0,
      reason: 'client.close 精确取消 retained binding，无第二个观察泄漏',
    );
  });

  test(
    'access recovery prevents re-reading an existing continuation identity',
    () async {
      final transport = _Transport();
      final client = await _client(transport);
      final entered = transport.continues.stream.first;
      final continuing = client.threadCommands.continueThread(
        'thread',
        _continuation(),
        expectedModelRouteRevision: 1,
      );
      final call = await entered;
      call.reply.complete(
        ContinueThreadCommandReply(
          threadId: 'thread',
          inputId: call.operationId.value,
          continuationId: call.continuationId,
          cursor: 4,
          receipt: _identityReceipt(call.operationId),
        ),
      );
      await continuing;
      expect(transport.continueCalls, 1);

      client.recovery.apply(
        RecoveryStateSnapshot(
          revision: 2,
          values: const [
            StudioRecoveryIssue(
              id: 'thread-history-inaccessible',
              scope: RecoveryIssueScope.thread,
              category: RecoveryIssueCategory.storage,
              impact: RecoveryIssueImpact.accessBlocked,
              availableActions: [RecoveryIssueAction.retry],
              workspaceId: 'project',
              threadId: 'thread',
              detail: 'Thread history cannot be read safely',
            ),
          ],
        ),
      );

      await expectLater(
        client.threadCommands.continueThread(
          'thread',
          _continuation(),
          expectedModelRouteRevision: 1,
        ),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => recoveryIssueFromFailure(failure)?.id,
            'issue id',
            'thread-history-inaccessible',
          ),
        ),
      );
      await expectLater(
        client.threadCommands.readContinuationOperation(
          'thread',
          call.operationId.value,
        ),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => recoveryIssueFromFailure(failure)?.id,
            'issue id',
            'thread-history-inaccessible',
          ),
        ),
      );
      expect(transport.continuationReadCalls, 0);
      expect(transport.continueCalls, 1);
    },
  );

  test('a not-found continue identity cannot send a new request through storage pause', () async {
    final transport = _Transport();
    final client = await _client(transport);
    final entered = transport.continues.stream.first;
    final continuing = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    final call = await entered;
    call.reply.complete(
      ContinueThreadCommandReply(
        threadId: 'thread',
        inputId: call.operationId.value,
        continuationId: call.continuationId,
        cursor: 4,
        receipt: _identityReceipt(call.operationId),
      ),
    );
    await continuing;
    expect(transport.continueCalls, 1);

    await client.conversations
        .session('thread')
        .deliverWorkspace(
          _workspace(
            revision: 2,
            storage: const ThreadStorageStateView(
              execution: ThreadStorageExecution.paused,
              resumeRequired: true,
              lastError: 'writer recovery still requires an explicit continue',
            ),
          ),
        );
    await expectLater(
      client.threadCommands.continueThread(
        'thread',
        _continuation(),
        expectedModelRouteRevision: 1,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.storage,
        ),
      ),
    );
    expect(transport.continuationReadCalls, 1);
    expect(transport.continueCalls, 1);
    expect(
      client.mutations.operations.where(
        (operation) => operation.target == 'continue:thread',
      ),
      hasLength(1),
      reason: 'A missing old operation does not allocate a new blocked request',
    );
  });

  test('a storage gate discovered while continue waits in the lane rejects the unsent identity', () async {
    final transport = _Transport();
    final client = await _client(transport);
    final compacting = client.threadCommands.compactThread('thread');
    await transport.compactEntered.future;

    final continuing = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    final unsentOperation = client.mutations.latest('continue:thread')!;
    await client.conversations
        .session('thread')
        .deliverWorkspace(
          _workspace(
            revision: 2,
            storage: const ThreadStorageStateView(
              execution: ThreadStorageExecution.paused,
              resumeRequired: true,
              lastError: 'storage paused while continue was queued',
            ),
          ),
        );
    transport.compactions.single.complete();
    await compacting;

    StudioFailure? rejection;
    try {
      await continuing;
    } on StudioFailure catch (error) {
      rejection = error;
    }
    expect(rejection, isA<StudioFailure>());
    final storageRejection = rejection as StudioFailure;
    expect(storageRejection.code, StudioFailureCode.storage);
    expect(unsentOperation.state.value.phase, OperationPhase.rejected);
    expect(
      identical(unsentOperation.state.value.error, storageRejection),
      isTrue,
    );
    expect(transport.continueCalls, 0);
    expect(transport.continuationReadCalls, 0);

    await client.conversations
        .session('thread')
        .deliverWorkspace(_workspace(revision: 3));
    final entered = transport.continues.stream.first;
    final retry = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    final retryCall = await entered;
    expect(retryCall.operationId, isNot(unsentOperation.id));
    retryCall.reply.complete(
      ContinueThreadCommandReply(
        threadId: 'thread',
        inputId: retryCall.operationId.value,
        continuationId: retryCall.continuationId,
        cursor: 5,
        receipt: _identityReceipt(retryCall.operationId),
      ),
    );
    await retry;
    expect(transport.continueCalls, 1);
    expect(transport.continuationReadCalls, 0);
  });

  test('a post-transport storage failure remains unknown and re-reads the original identity', () async {
    final transport = _Transport();
    final client = await _client(transport);
    final entered = transport.continues.stream.first;
    final continuing = client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );
    final call = await entered;
    final operation = client.mutations.latest('continue:thread')!;
    const storageFailure = StudioFailure(
      code: StudioFailureCode.storage,
      message: 'transport failed after continuation dispatch',
      retryable: false,
      correlationId: 'continue-transport-storage',
    );
    call.reply.completeError(storageFailure);
    await expectLater(continuing, throwsA(same(storageFailure)));
    expect(operation.state.value.phase, OperationPhase.unknownOutcome);
    expect(identical(operation.state.value.error, storageFailure), isTrue);
    expect(transport.continueCalls, 1);

    client.recovery.apply(
      RecoveryStateSnapshot(
        revision: 2,
        values: const [
          StudioRecoveryIssue(
            id: 'continue-execution-paused',
            scope: RecoveryIssueScope.thread,
            category: RecoveryIssueCategory.storage,
            impact: RecoveryIssueImpact.executionBlocked,
            availableActions: [],
            workspaceId: 'project',
            threadId: 'thread',
            detail: 'New execution is paused',
          ),
        ],
      ),
    );
    await client.conversations
        .session('thread')
        .deliverWorkspace(
          _workspace(
            revision: 2,
            storage: const ThreadStorageStateView(
              execution: ThreadStorageExecution.paused,
              resumeRequired: true,
              lastError: 'writer remains paused',
            ),
          ),
        );
    transport.continuationReadReply = ContinuationOperationView(
      threadId: 'thread',
      operationId: operation.id.value,
      inputId: operation.id.value,
      continuationId: call.continuationId,
      acceptedSequence: 5,
      state: const ConsumedContinuation('continued-turn'),
      durable: true,
      receipt: _identityReceipt(operation.id),
    );
    final reconciled = await client.threadCommands.continueThread(
      'thread',
      _continuation(),
      expectedModelRouteRevision: 1,
    );

    expect(reconciled.inputId, operation.id.value);
    expect(transport.continuationReadCalls, 1);
    expect(transport.continueCalls, 1);
    expect(
      client.mutations.operations.where(
        (item) => item.target == 'continue:thread',
      ),
      hasLength(1),
      reason: 'The storage failure is reconciled by its original operation ID',
    );
  });

  test('the canonical continuation projection feeds continue and a claimed point sends nothing', () async {
    final transport = _Transport();
    final client = await _client(transport);
    final published = _continuation();
    await client.conversations
        .session('thread')
        .deliverWorkspace(_workspace(continuation: published));
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
    await client.conversations
        .session('thread')
        .deliverWorkspace(
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
    await client.conversations
        .session('thread')
        .deliverWorkspace(
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
    final session = client.conversations.session('thread');
    await session.deliverNotification(
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
    await client.conversations
        .session('thread')
        .deliverWorkspace(
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
    final client = await _client(transport);

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

  test(
    'child cards require a successful read in the current display generation',
    () async {
      final transport = _Transport();
      final client = await _client(transport);
      final summary = _childSummary(revision: 3);
      final oldReply = Completer<List<ChildInteractionSummary>>();
      transport.childInteractionsReply = (_) => oldReply.future;
      final initialGeneration =
          client.childInteractions.state.displayGeneration;
      var notifications = 0;
      final observation = client.childInteractions.source.watch((_) {
        notifications++;
      });
      addTearDown(observation.cancel);
      client.conversations.setVisibleThread('thread');
      expect(notifications, 0, reason: 'The same visible target is a no-op');
      final oldRead = client.threadCommands.readChildInteractions('thread');
      client.conversations.setVisibleThread('other');
      client.conversations.setVisibleThread('thread');
      expect(notifications, 2);
      expect(
        client.childInteractions.state.displayGeneration,
        initialGeneration + 2,
      );
      oldReply.complete([summary]);
      expect(await oldRead, [summary]);
      expect(client.childInteractions.state.items, [summary]);
      expect(
        client.childInteractions.state.readDisplayGeneration,
        initialGeneration,
      );
      expect(client.childInteractions.state.visibleItems, isEmpty);

      final failure = StateError('current read failed');
      transport.childInteractionsReply = (_) => Future.error(failure);
      await expectLater(
        client.threadCommands.readChildInteractions('thread'),
        throwsA(same(failure)),
      );
      expect(client.childInteractions.state.items, [summary]);
      expect(client.childInteractions.state.visibleItems, isEmpty);

      final refreshed = _childSummary(revision: 4);
      transport.childInteractionsReply = null;
      transport.childInteractions = [refreshed];
      await client.threadCommands.readChildInteractions('thread');
      expect(client.childInteractions.state.visibleItems, [refreshed]);
      final generation = client.childInteractions.state.displayGeneration;
      client.selection.selectThread(workspaceId: 'project', threadId: 'other');
      expect(client.childInteractions.state.displayGeneration, generation);
      expect(client.childInteractions.state.visibleItems, [refreshed]);
      client.conversations.setVisibleThread(null);
      expect(client.childInteractions.state.visibleItems, isEmpty);
      expect(client.childInteractions.state.items, [refreshed]);
    },
  );

  test(
    'a newer child read intent blocks an older result before either publishes',
    () async {
      final transport = _Transport();
      final client = await _client(transport);
      final baseline = _childSummary(revision: 1);
      transport.childInteractions = [baseline];
      await client.threadCommands.readChildInteractions('thread');
      final sequence = client.childInteractions.state.sequence;
      final oldReply = Completer<List<ChildInteractionSummary>>();
      final newReply = Completer<List<ChildInteractionSummary>>();
      transport.childInteractionsReply = (_) => oldReply.future;
      final oldRead = client.threadCommands.readChildInteractions('thread');
      transport.childInteractionsReply = (_) => newReply.future;
      final newRead = client.threadCommands.readChildInteractions('thread');
      final stale = _childSummary(revision: 2);
      oldReply.complete([stale]);
      expect(await oldRead, [stale]);
      expect(client.childInteractions.state.sequence, sequence);
      expect(client.childInteractions.state.items, [baseline]);
      final current = _childSummary(revision: 3);
      newReply.complete([current]);
      expect(await newRead, [current]);
      expect(client.childInteractions.state.sequence, sequence + 2);
      expect(client.childInteractions.state.visibleItems, [current]);
    },
  );

  test(
    'client close revokes child cards synchronously but joins the old query',
    () async {
      final transport = _Transport();
      final client = await _client(transport);
      final summary = _childSummary(revision: 3);
      transport.childInteractions = [summary];
      await client.threadCommands.readChildInteractions('thread');
      expect(client.childInteractions.state.visibleItems, [summary]);
      final generation = client.childInteractions.state.displayGeneration;
      final reply = Completer<List<ChildInteractionSummary>>();
      transport.childInteractionsReply = (_) => reply.future;
      final reading = client.threadCommands.readChildInteractions('thread');
      var commandsClosed = false;
      final commandsClosing = client.threadCommands.close().then((_) {
        commandsClosed = true;
      });
      await Future<void>.value();
      expect(commandsClosed, isFalse, reason: 'The query still owns its gate');
      var closed = false;
      final closing = client.close().then((report) {
        closed = true;
        return report;
      });
      expect(client.childInteractions.state.visibleHostThreadId, isNull);
      expect(client.childInteractions.state.displayGeneration, generation + 1);
      expect(client.childInteractions.state.visibleItems, isEmpty);
      client.conversations.setVisibleThread(null);
      expect(client.childInteractions.state.displayGeneration, generation + 1);
      await Future<void>.value();
      expect(closed, isFalse);
      reply.complete([summary]);
      expect(await reading, [summary]);
      await commandsClosing;
      expect(commandsClosed, isTrue);
      await closing;
      expect(closed, isTrue);
      expect(client.childInteractions.state.visibleItems, isEmpty);
    },
  );

  for (final ordering in [
    'receipt first',
    'observation first',
    'new intent during acceptance',
  ]) {
    test(
      'a child decision is routed through the hosting main session with its revision ($ordering)',
      () async {
        final framesFirst = ordering == 'observation first';
        final reenter = ordering == 'new intent during acceptance';
        final transport = _Transport();
        final client = await _client(transport);
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
        final operation = client.mutations.latest('interaction:thread')!;
        expect(
          client.threadCommands.state.commands['interaction:thread']?.accepted,
          isFalse,
        );
        final call = await entered;
        expect(call.operationId, operation.id);
        expect(call.hostThreadId, 'thread');
        expect(call.interactionId, 'child-interaction');
        expect(call.expectedRevision, 3);
        expect(call.resolution, same(_resolution));
        Future<_InteractionCall>? newerEntered;
        Future<OperationHandle>? newerResolving;
        OperationHandle? newerOperation;
        final acceptance = operation.state.watch((next) {
          if (!reenter || next.receipt == null || newerResolving != null)
            return;
          newerEntered = transport.interactions.stream.first;
          newerResolving = client.threadCommands.resolveChildInteraction(
            'thread',
            _childSummary(revision: 4),
            _resolution,
          );
          newerOperation = client.mutations.latest('interaction:thread');
        });
        addTearDown(acceptance.cancel);
        if (framesFirst) {
          transport.childInteractions = const [];
          await client.threadCommands.readChildInteractions('thread');
          expect(operation.state.value.observed, isFalse);
          expect(
            client
                .threadCommands
                .state
                .commands['interaction:thread']
                ?.accepted,
            isFalse,
            reason: 'Canonical evidence alone is not an acceptance receipt',
          );
        }
        call.reply.complete(
          InteractionCommandReply(
            interaction: summary.interaction,
            receipt: _identityReceipt(call.operationId),
          ),
        );
        expect(await resolving, same(operation));
        acceptance.cancel();
        expect(operation.id, call.operationId);
        expect(operation, same(client.mutations.lookup(call.operationId)));
        expect(operation.state.value.receipt!.operationId, call.operationId);
        expect(operation.state.value.observed, framesFirst);
        expect(
          operation.state.value.phase,
          framesFirst
              ? OperationPhase.effective
              : OperationPhase.awaitingObservation,
        );
        final command =
            client.threadCommands.state.commands['interaction:thread'];
        if (framesFirst) {
          expect(
            command,
            isNull,
            reason: 'Acceptance must not revive a cleared command',
          );
        } else {
          expect(command?.phase, CommandPhase.pending);
          expect(command?.accepted, !reenter);
          expect(command?.target.label, summary.interactionId);
        }
        if (reenter) {
          expect(newerOperation, isNotNull);
          expect(newerOperation!.id, isNot(operation.id));
          expect(newerOperation!.state.value.receipt, isNull);
          expect(
            client.mutations.latest('interaction:thread'),
            same(newerOperation),
          );
          final newerCall = await newerEntered!;
          expect(newerCall.operationId, newerOperation!.id);
          expect(newerCall.hostThreadId, 'thread');
          expect(newerCall.interactionId, summary.interactionId);
          expect(newerCall.expectedRevision, 4);
          newerCall.reply.complete(
            InteractionCommandReply(
              interaction: _childSummary(revision: 4).interaction,
              receipt: _identityReceipt(newerCall.operationId),
            ),
          );
          expect(await newerResolving!, same(newerOperation));
          expect(
            client
                .threadCommands
                .state
                .commands['interaction:thread']
                ?.accepted,
            isTrue,
            reason: 'Only the newer operation’s own receipt marks its command accepted',
          );
          expect(newerOperation!.state.value.observed, isFalse);
        }
        expect(
          client.childInteractions.state.visibleItems,
          framesFirst ? isEmpty : [summary],
        );
        client.conversations.setVisibleThread('other');
        client.conversations.setVisibleThread('thread');
        expect(client.childInteractions.state.visibleItems, isEmpty);
        expect(
          client.childInteractions.state.items,
          framesFirst ? isEmpty : [summary],
        );
        expect(
          operation.state.value.observed,
          framesFirst,
          reason:
              'Navigation only revokes presentation, not the pending decision',
        );
        // The projection stops offering the interaction: the decision took effect.
        transport.childInteractions = const [];
        await client.threadCommands.readChildInteractions('thread');
        expect(operation.state.value.observed, isTrue);
        if (reenter) expect(newerOperation!.state.value.observed, isTrue);
        expect(
          client.threadCommands.state.commands,
          isNot(contains('interaction:thread')),
        );
      },
    );
  }

  test('a child session cannot host its own decision', () async {
    final transport = _Transport();
    final client = await _client(transport);
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
