import 'dart:async';

import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class _TopicTransport implements StudioTransport {
  _TopicTransport() : root = ClientScope(owner: 'topic-test') {
    ownerScope = root.child('transport');
    addTearDown(() async {
      expect((await root.close(budget: _budget())).complete, isTrue);
    });
  }

  final ClientScope root;
  late final ClientScope ownerScope;
  final List<_TopicSource> sources = [];
  final List<Completer<_TopicSource>> _opened = [];
  Completer<void>? nextOpenGate;
  final threadLspResetRequests =
      <({String threadId, String bindingId, String serverId})>[];
  final threadLspResetStarted = Completer<void>();
  Completer<ThreadLspStateSnapshot>? threadLspResetResult;

  Future<_TopicSource> created(int index) {
    if (sources.length > index) return Future.value(sources[index]);
    while (_opened.length <= index) _opened.add(Completer());
    return _opened[index].future;
  }

  Future<_TopicSource> opened(int index) async {
    final source = await created(index);
    await source.listening.future;
    return source;
  }

  @override
  Future<ProductTopicObservation> openProductTopic(
    ProductTopic topic, {
    required ClientResourceId resourceId,
  }) async {
    final gate = nextOpenGate;
    nextOpenGate = null;
    final owner = ownerScope.open<_TopicSource>(
      'topic:${describeBridgeProductTopic(topic)}',
      (operation) async {
        final source = _TopicSource(topic, operation.resourceId);
        final index = sources.length;
        sources.add(source);
        if (_opened.length > index) _opened[index].complete(source);
        await gate?.future;
        return source;
      },
      identity: resourceId,
    );
    return _TopicPort(owner, await owner.ready);
  }

  @override
  Future<ThreadLspStateSnapshot> resetThreadLspServer({
    required String threadId,
    required String bindingId,
    required String serverId,
  }) {
    threadLspResetRequests.add((
      threadId: threadId,
      bindingId: bindingId,
      serverId: serverId,
    ));
    if (!threadLspResetStarted.isCompleted) {
      threadLspResetStarted.complete();
    }
    final result = threadLspResetResult;
    if (result == null) {
      throw StateError('Unexpected thread LSP reset without a result gate');
    }
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused fake topic capability: ${invocation.memberName}',
  );
}

/// The transport scope is the actual owner; the SDK sees only [_TopicPort].
final class _TopicSource implements ClientResource {
  _TopicSource(this.topic, this.resourceId) {
    _frames = StreamController(sync: true, onListen: listening.complete);
    frames = _frames.stream.transform(
      StreamTransformer<_Delivery, ProductTopicFrame>.fromHandlers(
        handleData: (delivery, sink) {
          sink.add(delivery.frame);
          delivery.dispatched.complete();
        },
        handleDone: (sink) {
          consumerStopping.complete();
          // Native ACK and SDK consumer completion are independent barriers.
          _consumerExit = Future<void>.sync(() async {
            await consumerExitGate?.future;
            sink.close();
            consumerExited.complete();
          });
        },
      ),
    );
  }

  final ProductTopic topic;
  @override
  final ClientResourceId resourceId;
  late final StreamController<_Delivery> _frames;
  late final Stream<ProductTopicFrame> frames;
  final Completer<void> listening = Completer();
  final Completer<void> consumerStopping = Completer();
  final Completer<void> consumerExited = Completer();
  final Completer<void> cancellationStarted = Completer();
  final Completer<void> nativeAcknowledged = Completer();
  Completer<void>? cancellationGate;
  Completer<void>? consumerExitGate;
  Future<void>? _frameClosing;
  Future<void>? _consumerExit;
  void Function()? onStop;
  Object? cancelFailure;
  int cancelCalls = 0;

  Future<void> emit(ProductTopicFrame frame) async {
    if (_frames.isClosed) return;
    final delivery = _Delivery(frame);
    _frames.add(delivery);
    // A dispatch is completed after the StreamIterator receives the frame, so
    // the real reducer runs before this method's caller resumes.
    await delivery.dispatched.future;
  }

  @override
  void requestClose() {
    final firstRequest = !_frames.isClosed;
    _frameClosing ??= _frames.close();
    if (firstRequest) onStop?.call();
  }

  @override
  Future<void> close() async {
    requestClose();
    if (!nativeAcknowledged.isCompleted) {
      cancelCalls++;
      if (!cancellationStarted.isCompleted) cancellationStarted.complete();
      await cancellationGate?.future;
      if (cancelFailure case final error?) throw error;
      nativeAcknowledged.complete();
    }
    // No SDK consumer is required for a late, never-delivered native handle.
    if (listening.isCompleted) await _frameClosing;
  }

  @override
  Future<void> retryClose() => close();
}

final class _Delivery {
  _Delivery(this.frame);
  final ProductTopicFrame frame;
  final Completer<void> dispatched = Completer();
}

final class _TopicPort implements ProductTopicObservation {
  _TopicPort(this.owner, this.source);
  final ClientAcquisition<_TopicSource> owner;
  final _TopicSource source;
  @override
  ClientResourceId get resourceId => owner.resourceId;
  @override
  Stream<ProductTopicFrame> get frames => source.frames;
  @override
  void requestClose() => owner.requestClose();
  @override
  Future<void> close() => owner.close();
  @override
  Future<void> retryClose() => owner.retryClose();
}

ClientCloseBudget _budget() => ClientCloseBudget(const Duration(seconds: 2));

AnyworkClient _client(_TopicTransport transport, String clientId) {
  final client = AnyworkClient(
    transport: transport,
    clientId: clientId,
    scope: transport.root.child('client'),
  );
  addTearDown(() async {
    expect((await client.close(budget: _budget())).complete, isTrue);
  });
  return client;
}

/// Minimal bootstrap facts so the real `bootstrap()` entry can run; every
/// resident topic subscription still goes through the real registry.
final class _BootstrapTopicTransport extends _TopicTransport {
  @override
  Future<StudioBootstrap> readBootstrap() async => StudioBootstrap(
    ownerEpoch: 'epoch-boot',
    projectDirectory: ProjectDirectoryState(),
    threadDirectory: const ThreadDirectoryPage(rows: []),
    agentDirectory: AgentDirectoryState(),
    settingsState: SettingsStateSnapshot(),
    recoveryState: RecoveryStateSnapshot(),
    mcpCatalog: const McpCatalogSnapshot(revision: 1),
    lspState: LspStateSnapshot(revision: 1),
    skillsByProject: const {},
    threadModeCatalog: const ThreadModeCatalogView(),
    updaterState: UpdaterStateSnapshot(
      activity: DisabledUpdaterActivity(
        revision: 1,
        updatedAt: DateTime.utc(2026),
      ),
    ),
    persistenceState: const PersistenceStateSnapshot.ready(),
  );
}

ProductTopicBaselineFrame _updater(int revision) => ProductTopicBaselineFrame(
  topic: const UpdaterTopic(),
  revision: revision,
  state: UpdaterBaseline(
    UpdaterStateSnapshot.idle(
      revision: revision,
      updatedAt: DateTime.utc(2026),
    ),
  ),
);

ChildInteractionSummary _hostedChildSummary(
  String hostThreadId,
  String childThreadId,
  int revision,
) => ChildInteractionSummary(
  childThreadId: childThreadId,
  interactionId: 'interaction-$childThreadId',
  kind: InteractionKind.userInput,
  revision: revision,
  interaction: PendingInteraction(
    id: 'interaction-$childThreadId',
    threadId: childThreadId,
    turnId: 'turn-$childThreadId',
    kind: InteractionKind.userInput,
    title: 'Question from $childThreadId',
    body: 'Hosted by $hostThreadId',
    revision: revision,
  ),
);

ProductTopicDataFrame _childEvent(
  String hostThreadId,
  int revision,
  List<ChildInteractionSummary> items,
) => ProductTopicDataFrame(
  topic: ChildInteractionsTopic(hostThreadId: hostThreadId),
  event: ProductTopicEventEnvelope(
    eventId: 'child-$hostThreadId-$revision',
    sequence: BigInt.from(revision),
    createdAt: DateTime.now(),
    payload: ChildInteractionsChangedPayload(
      ChildInteractionsStateView(
        hostThreadId: hostThreadId,
        state: ReadyObservedResource(
          revision: revision,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          lastCheckedAt: null,
          value: ChildInteractionsData(items: items),
        ),
      ),
    ),
  ),
);

LspServerStateView _threadLspServer(LspServerState state) => LspServerStateView(
  id: 'same-server',
  displayName: 'same-server',
  configurationPath: null,
  phase: 'ready',
  state: state,
);

ProductTopicBaselineFrame _threadLspBaseline(ThreadLspStateSnapshot snapshot) =>
    ProductTopicBaselineFrame(
      topic: ThreadLspTopic(threadId: snapshot.threadId),
      revision: snapshot.revision,
      state: ThreadLspBaseline(snapshot),
    );

ProductTopicDataFrame _threadLspEvent(ThreadLspStateSnapshot snapshot) =>
    ProductTopicDataFrame(
      topic: ThreadLspTopic(threadId: snapshot.threadId),
      event: ProductTopicEventEnvelope(
        eventId: 'thread-lsp-${snapshot.threadId}-${snapshot.revision}',
        sequence: BigInt.from(snapshot.revision),
        createdAt: DateTime.utc(2026),
        payload: ThreadLspStateChangedPayload(snapshot),
      ),
    );

void main() {
  test(
    'scoped topic demand installs mirrors before the first native callback',
    () async {
      final transport = _TopicTransport();
      final client = _client(transport, 'scoped');
      expect(client.existingSkills('project'), isNull);
      expect(client.existingSessionCosts('root'), isNull);
      final leases = client.channels.acquireTopics([
        const SkillsTopic(workspaceId: 'project'),
        const SessionCostsTopic(rootThreadId: 'root'),
      ]);
      final skills = client.existingSkills('project')!;
      final costs = client.existingSessionCosts('root')!;
      expect(skills.state.loaded, isFalse);
      expect(costs.state.loaded, isFalse);
      final skillSource = await transport.opened(0);
      final costSource = await transport.opened(1);
      await skillSource.emit(
        ProductTopicBaselineFrame(
          topic: const SkillsTopic(workspaceId: 'project'),
          revision: 1,
          state: SkillsBaseline(
            SkillsStateSnapshot(
              workspaceId: 'project',
              configFingerprint: 'configured',
              catalogRevision: 2,
              skills: const ['skill'],
              warnings: const [],
              revision: 1,
            ),
          ),
        ),
      );
      await costSource.emit(
        const ProductTopicBaselineFrame(
          topic: SessionCostsTopic(rootThreadId: 'root'),
          revision: 3,
          state: SessionCostsBaseline(
            SessionCostsStateView(rootThreadId: 'root', revision: 3),
          ),
        ),
      );
      expect(client.existingSkills('project'), same(skills));
      expect(client.existingSessionCosts('root'), same(costs));
      expect(skills.state.value?.skills, ['skill']);
      expect(costs.state.revision, 3);
      await leases.release();
      expect((await client.close(budget: _budget())).complete, isTrue);
    },
  );

  test('thread LSP late reset receipt cannot replace a newer empty binding snapshot', () async {
    final transport = _TopicTransport();
    final client = _client(transport, 'thread-lsp');
    final leaseA = client.channels.acquireThreadLsp('thread-a');
    final leaseB = client.channels.acquireThreadLsp('thread-b');
    final sourceA = await transport.opened(0);
    final sourceB = await transport.opened(1);
    final initialA = ThreadLspStateSnapshot(
      threadId: 'thread-a',
      revision: 10,
      bindingId: 'binding-a',
      servers: [
        _threadLspServer(const LspCheckingState(message: 'A initializing')),
      ],
    );
    final initialB = ThreadLspStateSnapshot(
      threadId: 'thread-b',
      revision: 4,
      bindingId: 'binding-b',
      servers: [
        _threadLspServer(
          const LspUnavailableState(
            checkedAt: 1,
            code: 'B',
            message: 'B unavailable',
            retryable: true,
          ),
        ),
      ],
    );
    await sourceA.emit(_threadLspBaseline(initialA));
    await sourceB.emit(_threadLspBaseline(initialB));
    final storeA = client.existingThreadLsp('thread-a')!;
    final storeB = client.existingThreadLsp('thread-b')!;
    expect(storeA.state.value, same(initialA));
    expect(storeB.state.value, same(initialB));
    expect(storeA.state.value!.servers.single.id, 'same-server');
    expect(storeB.state.value!.servers.single.id, 'same-server');

    final resetResult = Completer<ThreadLspStateSnapshot>();
    transport.threadLspResetResult = resetResult;
    final reset = client.directoryCommands.resetThreadLspServer(
      threadId: 'thread-a',
      bindingId: 'binding-a',
      serverId: 'same-server',
    );
    await transport.threadLspResetStarted.future;
    expect(transport.threadLspResetRequests, [
      (threadId: 'thread-a', bindingId: 'binding-a', serverId: 'same-server'),
    ]);

    final retiredA = const ThreadLspStateSnapshot(
      threadId: 'thread-a',
      revision: 12,
      bindingId: null,
      servers: [],
    );
    await sourceA.emit(_threadLspEvent(retiredA));
    expect(storeA.state.revision, 12);
    expect(storeA.state.value, same(retiredA));
    expect(storeB.state.value, same(initialB));

    final lateSuccess = ThreadLspStateSnapshot(
      threadId: 'thread-a',
      revision: 11,
      bindingId: 'binding-a',
      servers: [initialA.servers.single],
    );
    resetResult.complete(lateSuccess);
    expect(await reset, same(lateSuccess));
    expect(storeA.state.revision, 12);
    expect(storeA.state.value, same(retiredA));
    expect(storeA.state.value!.servers, isEmpty);
    expect(storeB.state.revision, 4);
    expect(storeB.state.value, same(initialB));

    await leaseA.release();
    await leaseB.release();
    expect(sourceA.cancelCalls, 1);
    expect(sourceB.cancelCalls, 1);
    expect((await client.close(budget: _budget())).complete, isTrue);
  });

  test(
    'child interactions topics are per-host mirrors with revision ordering',
    () async {
      final transport = _TopicTransport();
      final client = _client(transport, 'child-topics');
      expect(client.existingChildInteractions('host-a'), isNull);
      final leaseA = client.channels.acquireChildInteractions('host-a');
      final storeA = client.existingChildInteractions('host-a')!;
      expect(storeA.state.canonical.loaded, isFalse);
      final sourceA = await transport.opened(0);
      // 无值基线只建立资源观察，不代表完整集合，也不能确认决议消失。
      await sourceA.emit(
        ProductTopicBaselineFrame(
          topic: const ChildInteractionsTopic(hostThreadId: 'host-a'),
          revision: 2,
          state: ChildInteractionsBaseline(
            ChildInteractionsStateView(
              hostThreadId: 'host-a',
              state: const UninitializedObservedResource(
                revision: 2,
                updatedAt: 123,
              ),
            ),
          ),
        ),
      );
      expect(storeA.state.canonical.loaded, isTrue);
      expect(storeA.state.hasCurrentBaseline, isFalse);
      expect(storeA.state.canonical.value?.state.value, isNull);
      expect(
        storeA.state.canonical.value!.confirmsDecision(
          childThreadId: 'child-1',
          interactionId: 'interaction-child-1',
          revision: 5,
        ),
        isFalse,
      );
      final decisionSummary = _hostedChildSummary('host-a', 'child-1', 5);
      await sourceA.emit(
        ProductTopicBaselineFrame(
          topic: const ChildInteractionsTopic(hostThreadId: 'host-a'),
          revision: 2,
          state: ChildInteractionsBaseline(
            ChildInteractionsStateView(
              hostThreadId: 'host-a',
              state: ReadyObservedResource(
                revision: 2,
                updatedAt: 456,
                lastCheckedAt: null,
                value: ChildInteractionsData(items: [decisionSummary]),
              ),
            ),
          ),
        ),
      );
      expect(storeA.state.hasCurrentBaseline, isTrue);
      expect(storeA.state.canonical.revision, 2);
      expect(
        storeA.state.canonical.value?.state.value?.items.single.interactionId,
        'interaction-child-1',
      );

      // 另一个宿主有独立镜像；互不覆盖。
      final leaseB = client.channels.acquireChildInteractions('host-b');
      final storeB = client.existingChildInteractions('host-b')!;
      final sourceB = await transport.opened(1);
      await sourceB.emit(
        ProductTopicBaselineFrame(
          topic: const ChildInteractionsTopic(hostThreadId: 'host-b'),
          revision: 7,
          state: ChildInteractionsBaseline(
            ChildInteractionsStateView(
              hostThreadId: 'host-b',
              state: ReadyObservedResource(
                revision: 7,
                updatedAt: 789,
                lastCheckedAt: null,
                value: ChildInteractionsData(items: []),
              ),
            ),
          ),
        ),
      );
      expect(storeB.state.canonical.revision, 7);
      expect(storeB.state.hasCurrentBaseline, isTrue);
      expect(storeB.state.canonical.value?.state.value?.items, isEmpty);
      expect(
        storeB.state.canonical.value!.confirmsDecision(
          childThreadId: 'child-1',
          interactionId: 'interaction-child-1',
          revision: 5,
        ),
        isTrue,
        reason: '只有已知 Ready 空集合可以确认交互消失',
      );
      expect(storeA.state.canonical.revision, 2);

      // 旧 revision 事件被拒；新 revision 事件替换集合。
      await sourceA.emit(
        _childEvent('host-a', 2, [_hostedChildSummary('host-a', 'child-1', 9)]),
      );
      expect(
        storeA.state.canonical.value?.state.value?.items.single.revision,
        5,
      );
      await sourceA.emit(_childEvent('host-a', 3, const []));
      expect(storeA.state.canonical.value?.state.value?.items, isEmpty);
      expect(storeA.state.canonical.revision, 3);

      // 同租约内的短暂滞后/重连只更新 sync：资格与集合身份保持不变。
      final canonicalBeforeLag = storeA.state.canonical;
      await sourceA.emit(
        const ProductTopicLaggedFrame(
          topic: ChildInteractionsTopic(hostThreadId: 'host-a'),
          dropped: 2,
        ),
      );
      expect(storeA.state.hasCurrentBaseline, isTrue);
      expect(
        identical(storeA.state.canonical.value, canonicalBeforeLag.value),
        isTrue,
        reason: '重连窗口保留同一集合对象',
      );
      expect(storeA.state.canonical.sync.phase, DomainSyncPhase.reconnecting);

      // 全部租约释放到 idle：撤销资格并推进观察代次，lastKnown 集合保留。
      final canonicalBeforeIdle = storeA.state.canonical;
      await leaseA.release();
      await leaseB.release();
      expect(sourceA.cancelCalls, 1);
      expect(sourceB.cancelCalls, 1);
      expect(client.channels.activeTopicRefCountViews(), isEmpty);
      expect(storeA.state.hasCurrentBaseline, isFalse);
      expect(storeA.state.observationGeneration, 1);
      expect(storeA.state.canonical.sync.phase, DomainSyncPhase.idle);
      expect(
        identical(storeA.state.canonical.value, canonicalBeforeIdle.value),
        isTrue,
        reason: 'idle 只撤资格，不清 lastKnown 集合',
      );
      // 一个新的页面需求重订本域：更旧帧不得恢复资格或改变内容；同 revision
      // 的完整新基线恢复本代资格，且不重写 canonical 对象。
      final canonicalAtIdle = storeA.state.canonical;
      final thirdLease = client.channels.acquireChildInteractions('host-a');
      // 滞后触发的自动重订在租约释放后不再建立；本次新需求即第二个真实源。
      final thirdSourceA = await transport.opened(2);
      await thirdSourceA.emit(
        ProductTopicBaselineFrame(
          topic: const ChildInteractionsTopic(hostThreadId: 'host-a'),
          revision: 1,
          state: ChildInteractionsBaseline(
            ChildInteractionsStateView(
              hostThreadId: 'host-a',
              state: ReadyObservedResource(
                revision: 1,
                updatedAt: 1001,
                lastCheckedAt: null,
                value: ChildInteractionsData(
                  items: [_hostedChildSummary('host-a', 'child-9', 1)],
                ),
              ),
            ),
          ),
        ),
      );
      expect(storeA.state.hasCurrentBaseline, isFalse);
      expect(storeA.state.canonical.revision, 3);
      expect(storeA.state.canonical.value?.state.value?.items, isEmpty);
      await thirdSourceA.emit(
        ProductTopicBaselineFrame(
          topic: const ChildInteractionsTopic(hostThreadId: 'host-a'),
          revision: 3,
          state: ChildInteractionsBaseline(
            ChildInteractionsStateView(
              hostThreadId: 'host-a',
              state: ReadyObservedResource(
                revision: 3,
                updatedAt: 1002,
                lastCheckedAt: null,
                value: ChildInteractionsData(items: []),
              ),
            ),
          ),
        ),
      );
      expect(storeA.state.hasCurrentBaseline, isTrue);
      expect(
        identical(storeA.state.canonical.value, canonicalAtIdle.value),
        isTrue,
        reason: '等 revision 首帧只确认资格，不重写 canonical 集合值',
      );
      expect(storeA.state.canonical.revision, 3);
      await thirdLease.release();
      expect((await client.close(budget: _budget())).complete, isTrue);
    },
  );

  test('child interactions data freezes its items', () {
    final input = <ChildInteractionSummary>[
      _hostedChildSummary('host-a', 'child-1', 5),
    ];
    final view = ChildInteractionsStateView(
      hostThreadId: 'host-a',
      state: ReadyObservedResource(
        revision: 1,
        updatedAt: 123,
        lastCheckedAt: null,
        value: ChildInteractionsData(items: input),
      ),
    );
    input.clear();
    expect(view.state.value!.items, hasLength(1), reason: '数据构造边界复制输入列表');
    expect(
      () => view.state.value!.items.clear(),
      throwsUnsupportedError,
      reason: '读取到的列表不可变异',
    );
    expect(view.hostThreadId, 'host-a');
    expect(view.state.revision, 1);
  });

  test('child observation released before baseline advances once', () {
    final store = ChildInteractionStore('host-a');
    store.applyTransport(
      const DomainSyncStatus(phase: DomainSyncPhase.connecting),
    );
    store.applyTransport(const DomainSyncStatus());
    expect(store.state.hasCurrentBaseline, isFalse);
    expect(store.state.observationGeneration, 1);
    expect(store.state.canonical.sync.phase, DomainSyncPhase.idle);
    final released = store.state;
    store.applyTransport(const DomainSyncStatus());
    expect(identical(store.state, released), isTrue);
  });

  test(
    'shared topic reopens only after the original real cancel ACK',
    () async {
      final transport = _TopicTransport();
      final client = _client(transport, 'app');
      final firstLease = client.channels.acquireTopic(const UpdaterTopic());
      final secondLease = client.channels.acquireTopic(const UpdaterTopic());
      final old = await transport.opened(0);
      await old.emit(_updater(1));
      expect(client.updater.state.value?.revision, 1);
      await firstLease.release();
      expect(firstLease.retirementResourceIds, isEmpty);
      expect(old.cancelCalls, 0);
      old.cancellationGate = Completer();
      final releasing = secondLease.release();
      expect(secondLease.retirementResourceIds, [old.resourceId]);
      expect(secondLease.release(), same(releasing));
      expect(client.channels.activeTopicRefCountViews(), {'updater': 0});
      await old.cancellationStarted.future;
      final newLease = client.channels.acquireTopic(const UpdaterTopic());
      await old.emit(_updater(99));
      expect(client.updater.state.value?.revision, 1);
      expect(transport.sources, hasLength(1));
      old.cancellationGate!.complete();
      await releasing;
      final replacement = await transport.opened(1);
      await replacement.emit(_updater(2));
      await old.emit(_updater(100));
      expect(client.updater.state.value?.revision, 2);
      expect(secondLease.retirementResourceIds, [old.resourceId]);
      expect(replacement.resourceId, isNot(old.resourceId));
      await secondLease.release();
      expect(replacement.cancelCalls, 0);
      expect(client.channels.activeTopicRefCountViews(), {'updater': 1});
      await newLease.release();
      await client.close(budget: _budget());
    },
  );

  test(
    'cancel failure retains the same owner and blocks a second subscription',
    () async {
      final transport = _TopicTransport();
      final client = _client(transport, 'app');
      final lease = client.channels.acquireTopic(const UpdaterTopic());
      final old = await transport.opened(0);
      old.cancelFailure = StateError('native observer did not stop');
      await expectLater(
        lease.release(),
        throwsA(isA<BridgeTopicCleanupBlocked>()),
      );
      expect(client.channels.activeTopicRefCountViews(), {'updater': 0});
      final reacquired = client.channels.acquireTopic(const UpdaterTopic());
      expect(transport.sources, hasLength(1));
      expect(old.cancelCalls, 1);
      old.cancelFailure = null;
      expect(
        (await client.channels.retryCleanup(budget: _budget())).complete,
        isTrue,
      );
      expect(old.cancelCalls, 2);
      final replacement = await transport.opened(1);
      await replacement.emit(_updater(3));
      await old.emit(_updater(100));
      expect(client.updater.state.value?.revision, 3);
      expect(lease.retirementResourceIds, [old.resourceId]);
      await lease.release();
      expect(old.cancelCalls, 2);
      expect(replacement.cancelCalls, 0);
      await reacquired.release();
      expect(replacement.cancelCalls, 1);
      expect(client.channels.activeTopicRefCountViews(), isEmpty);

      await client.close(budget: _budget());
    },
  );

  test(
    'close reports unresolved native cleanup and retry retains its owner',
    () async {
      final transport = _TopicTransport();
      final client = _client(transport, 'app');
      final lease = client.channels.acquireTopic(const UpdaterTopic());
      final source = await transport.opened(0);
      source.cancelFailure = StateError('native sink cleanup failed');
      final report = await client.channels.dispose(budget: _budget());
      expect(report.complete, isFalse);
      expect(report.unresolved.single.owner, 'topic:updater');
      expect(report.unresolved.single.resourceId, source.resourceId);
      expect(source.cancelCalls, 1);
      expect(await client.channels.dispose(budget: _budget()), same(report));
      expect(source.cancelCalls, 1);
      expect(client.channels.activeTopicRefCountViews(), {'updater': 0});
      source.cancelFailure = null;
      expect(
        (await client.channels.retryCleanup(budget: _budget())).complete,
        isTrue,
      );
      await lease.release();
      await client.close(budget: _budget());
    },
  );

  test('business reconnect never retries a failed native close', () async {
    final transport = _TopicTransport();
    final client = _client(transport, 'reconnect');
    final lease = client.channels.acquireTopic(const UpdaterTopic());
    final source = await transport.opened(0);
    source.cancelFailure = StateError('native close refused');
    await expectLater(
      lease.release(),
      throwsA(isA<BridgeTopicCleanupBlocked>()),
    );
    final nextLease = client.channels.acquireTopic(const UpdaterTopic());
    client.channels.retryTopic(const UpdaterTopic());
    // Ordinary shutdown joins the same failed acquisition. It is not a cleanup
    // retry and also provides a managed barrier for the reconnect request.
    final report = await client.channels.dispose(budget: _budget());
    expect(report.unresolved.single.resourceId, source.resourceId);
    expect(source.cancelCalls, 1);
    expect(transport.sources, hasLength(1));
    source.cancelFailure = null;
    expect(
      (await client.channels.retryCleanup(budget: _budget())).complete,
      isTrue,
    );
    expect(source.cancelCalls, 2);
    await nextLease.release();
  });

  test('scoped topic release omits an already closed failed source', () async {
    final transport = _TopicTransport();
    final sdk = transport.root.child('topic-registry');
    final page = transport.root.child('page');
    final failed = Completer<void>();
    final registry = BridgeTopicRegistry(
      transport,
      scope: sdk,
      onFrame: (_) {},
      onTopicConnection: (_, state) {
        if (state?.phase == ProductTopicConnectionPhase.reconnecting &&
            !failed.isCompleted) {
          failed.complete();
        }
      },
    );
    final opening = transport.nextOpenGate = Completer<void>();
    final lease = page.acquireLease(
      'updater-page',
      () => registry.acquire(const UpdaterTopic()),
    );
    await transport.created(0);
    opening.completeError(StateError('topic open failed'));
    await failed.future;
    expect((await sdk.retryCleanup(budget: _budget())).complete, isTrue);

    final report = await page.close(budget: _budget());
    expect(lease.retirementResourceIds, isEmpty);
    expect(report.complete, isTrue);
    expect(registry.activeTopicRefCountViews(), isEmpty);
  });

  test('late open is owned and closed without starting a consumer', () async {
    final transport = _TopicTransport();
    final client = _client(transport, 'opening');
    final opening = transport.nextOpenGate = Completer<void>();
    final lease = client.channels.acquireTopic(const UpdaterTopic());
    final source = await transport.created(0);
    final releasing = lease.release();
    expect(lease.retirementResourceIds, [source.resourceId]);
    expect(lease.release(), same(releasing));
    expect(source.listening.isCompleted, isFalse);
    expect(source.cancelCalls, 0);
    opening.complete();
    await releasing;
    expect(source.cancelCalls, 1);
    expect(source.nativeAcknowledged.isCompleted, isTrue);
    expect(source.listening.isCompleted, isFalse);
    expect(client.updater.state.value, isNull);
    expect(client.channels.activeTopicRefCountViews(), isEmpty);
  });

  test('native ACK does not hide a still-running SDK consumer', () async {
    final transport = _TopicTransport();
    final client = _client(transport, 'consumer');
    final lease = client.channels.acquireTopic(const UpdaterTopic());
    final source = await transport.opened(0);
    source.consumerExitGate = Completer<void>();
    final releasing = lease.release();
    final nextLease = client.channels.acquireTopic(const UpdaterTopic());
    await source.nativeAcknowledged.future;
    await source.consumerStopping.future;
    final report = await client.channels.retryCleanup(
      budget: ClientCloseBudget(Duration.zero),
    );
    expect(report.complete, isFalse);
    expect(report.unresolved.single.resourceId, source.resourceId);
    expect(
      report.unresolved.single.stages,
      contains(
        isA<ClientResourceStage>()
            .having((stage) => stage.phase, 'phase', ClientClosePhase.consumer)
            .having((stage) => stage.pending, 'pending', isTrue),
      ),
    );
    expect(source.consumerExited.isCompleted, isFalse);
    expect(transport.sources, hasLength(1));
    source.consumerExitGate!.complete();
    await source._consumerExit;
    await releasing;
    final replacement = await transport.opened(1);
    expect(replacement.resourceId, isNot(source.resourceId));
    expect(source.cancelCalls, 1);
    await nextLease.release();
  });

  test(
    'A to B to A lease retry retires only the captured original identity',
    () async {
      final transport = _TopicTransport();
      final client = _client(transport, 'identity');
      final oldLease = client.channels.acquireTopic(const UpdaterTopic());
      final oldA = await transport.opened(0);
      oldA.cancelFailure = StateError('first A close failed');
      await expectLater(
        oldLease.release(),
        throwsA(isA<BridgeTopicCleanupBlocked>()),
      );
      final ids = oldLease.retirementResourceIds;
      expect(ids, [oldA.resourceId]);
      expect(() => ids.clear(), throwsUnsupportedError);
      final leaseB = client.channels.acquireTopic(const RecoveryTopic());
      final sourceB = await transport.opened(1);
      final newLease = client.channels.acquireTopic(const UpdaterTopic());
      expect(transport.sources, hasLength(2));
      oldA.cancelFailure = null;
      oldA.cancellationGate = Completer<void>();
      final retry = oldLease.release();
      expect(oldLease.release(), same(retry));
      expect(oldLease.retirementResourceIds, same(ids));
      oldA.cancellationGate!.complete();
      await retry;
      final newA = await transport.opened(2);
      expect(newA.topic, oldA.topic);
      expect(newA.resourceId, isNot(oldA.resourceId));
      await oldLease.release();
      expect(oldA.cancelCalls, 2);
      expect(newA.cancelCalls, 0);
      expect(sourceB.cancelCalls, 0);
      expect(client.channels.activeTopicRefCountViews(), {
        'updater': 1,
        'recovery': 1,
      });
      await newLease.release();
      await leaseB.release();
    },
  );

  test(
    'bundle retry keeps its first retirement set and shared demand',
    () async {
      final transport = _TopicTransport();
      final client = _client(transport, 'bundle');
      final shared = client.channels.acquireTopic(const UpdaterTopic());
      final page = transport.root.child('page');
      final bundle = page.acquireLease(
        'topics',
        () => client.channels.acquireTopics([
          const UpdaterTopic(),
          const RecoveryTopic(),
        ]),
      );
      final updater = await transport.opened(0);
      final recovery = await transport.opened(1);
      recovery.cancelFailure = StateError('recovery close failed');
      final closing = page.close(budget: _budget());
      // Lease metadata is captured synchronously even when cleanup later fails.
      expect(bundle.retirementResourceIds, [recovery.resourceId]);
      expect((await closing).unresolved.single.resourceId, recovery.resourceId);
      final ids = bundle.retirementResourceIds;
      final reacquired = client.channels.acquireTopic(const RecoveryTopic());
      recovery.cancelFailure = null;
      // The actual owner, SDK proxy and registered bundle all join one pass.
      expect(
        (await transport.root.retryCleanup(budget: _budget())).complete,
        isTrue,
      );
      final replacement = await transport.opened(2);
      expect(recovery.cancelCalls, 2);
      expect(updater.cancelCalls, 0);
      expect(bundle.retirementResourceIds, same(ids));
      await bundle.release();
      expect(replacement.cancelCalls, 0);
      expect(client.channels.activeTopicRefCountViews(), {
        'updater': 1,
        'recovery': 1,
      });
      await shared.release();
      await reacquired.release();
    },
  );

  test(
    'bundle freezes all retirement identities before stop reenters disposal',
    () async {
      final transport = _TopicTransport();
      final client = _client(transport, 'bundle-reentry');
      final page = transport.root.child('page');
      final bundle = page.acquireLease(
        'topics',
        () => client.channels.acquireTopics([
          const UpdaterTopic(),
          const RecoveryTopic(),
        ]),
      );
      final updater = await transport.opened(0);
      final recovery = await transport.opened(1);
      updater.cancellationGate = Completer<void>();
      recovery.cancellationGate = Completer<void>();
      List<ClientResourceId>? captured;
      Future<CloseReport>? reentered;
      updater.onStop = () {
        reentered = page.close(budget: ClientCloseBudget(Duration.zero));
        captured = bundle.retirementResourceIds;
      };
      final releasing = bundle.release();
      final report = await reentered!;
      // Release and reentrant scope disposal must both see the complete frozen
      // set, not just the first source that happened to receive requestClose.
      updater.cancellationGate!.complete();
      recovery.cancellationGate!.complete();
      await releasing;
      expect(captured, [updater.resourceId, recovery.resourceId]);
      expect(
        report.unresolved.map((item) => item.resourceId),
        unorderedEquals([updater.resourceId, recovery.resourceId]),
      );
      expect(client.channels.activeTopicRefCountViews(), isEmpty);
    },
  );

  test(
    'lagged rebuild joins only its source while another topic keeps reducing',
    () async {
      final transport = _TopicTransport();
      final client = _client(transport, 'app');
      final leases = client.channels.acquireTopics([
        const UpdaterTopic(),
        const RecoveryTopic(),
      ]);
      final updater = await transport.opened(0);
      final recovery = await transport.opened(1);
      await updater.emit(_updater(1));
      updater.cancellationGate = Completer();
      await updater.emit(
        const ProductTopicLaggedFrame(topic: UpdaterTopic(), dropped: 1),
      );
      await updater.cancellationStarted.future;
      await recovery.emit(
        ProductTopicBaselineFrame(
          topic: const RecoveryTopic(),
          revision: 4,
          state: RecoveryBaseline(RecoveryStateSnapshot(revision: 4)),
        ),
      );
      expect(client.recovery.state.value?.revision, 4);
      expect(recovery.cancelCalls, 0);
      expect(transport.sources, hasLength(2));
      updater.cancellationGate!.complete();
      final replacement = await transport.opened(2);
      await replacement.emit(_updater(2));
      await updater.emit(_updater(99));
      expect(client.updater.state.value?.revision, 2);
      expect(recovery.cancelCalls, 0);
      await leases.release();
      await client.close(budget: _budget());
    },
  );

  test('repeated topic exit shares the first deadline and keeps pending cancel owned', () async {
    final transport = _TopicTransport();
    final client = _client(transport, 'app');
    client.channels.acquireTopic(const UpdaterTopic());
    final source = await transport.opened(0);
    source.cancellationGate = Completer();
    final closing = client.channels.dispose(
      budget: ClientCloseBudget(Duration.zero),
    );
    expect(
      identical(closing, client.channels.dispose(budget: _budget())),
      isTrue,
    );
    expect((await closing).complete, isFalse);
    await source.cancellationStarted.future;
    await source.emit(_updater(99));
    expect(client.updater.state.value, isNull);
    source.cancellationGate!.complete();
    expect(
      (await client.channels.retryCleanup(budget: _budget())).complete,
      isTrue,
    );
    await client.close(budget: _budget());
  });

  test(
    'bootstrap owns the resident bots topic and releases it on close',
    () async {
      final transport = _BootstrapTopicTransport();
      final client = _client(transport, 'boot');
      await client.bootstrap();
      // The Client—not a visible page scope—is the resident bots owner, so a
      // GUI observer or settings round trip can never be its only demand.
      expect(client.applicationTopics, contains(const BotsTopic()));
      final residentIndex = client.applicationTopics.indexOf(const BotsTopic());
      final source = await transport.opened(residentIndex);
      expect(source.topic, const BotsTopic());
      await source.emit(
        ProductTopicBaselineFrame(
          topic: const BotsTopic(),
          revision: 2,
          state: BotsBaseline(
            BotsStateSnapshot(
              revision: 2,
              updatedAt: 1718000000,
              bots: [
                BotSnapshot(
                  id: 'bot-boot',
                  name: '启动机器人',
                  workspaceId: 'project',
                  appId: 'cli_boot',
                  platform: BotPlatform.feishuChina,
                  enabled: true,
                  toolsEnabled: false,
                  configRevision: 1,
                  trustedOpenIds: const [],
                  trustedChatIds: const [],
                  connection: const BotConnectionDisabled(),
                  credential: BotCredentialAvailability.missing,
                  pairing: const [],
                  canChangeProject: true,
                  canChangeAppId: true,
                  createdAt: 1718000000,
                  updatedAt: 1718000000,
                ),
              ],
            ),
          ),
        ),
      );
      expect(client.bots.state.loaded, isTrue);
      expect(client.bots.state.revision, 2);
      expect(client.bots.state.value?.bots.single.id, 'bot-boot');

      // A settings round trip adds and removes only its own scope demand; the
      // resident owner keeps the subscription alive afterwards.
      final scope = client.channels.acquireSettingsScope(
        BridgeSettingsScopeKind.bots,
        null,
      );
      expect(client.channels.activeTopicRefCountViews()['bots'], 2);
      await scope.release();
      expect(client.channels.activeTopicRefCountViews()['bots'], 1);

      // Typed increments keep flowing into the canonical store.
      await source.emit(
        ProductTopicDataFrame(
          topic: const BotsTopic(),
          event: ProductTopicEventEnvelope(
            eventId: 'evt-boot-1',
            sequence: BigInt.one,
            createdAt: DateTime.utc(2026),
            payload: BotsStateChangedPayload(
              BotsStateSnapshot(
                revision: 3,
                updatedAt: 1718000001,
                bots: const [],
              ),
            ),
          ),
        ),
      );
      expect(client.bots.state.revision, 3);
      expect(client.bots.state.value?.bots, isEmpty);

      // Real close cancels the resident subscription through the topic owner.
      expect((await client.close(budget: _budget())).complete, isTrue);
      expect(source.cancelCalls, 1);
    },
  );
}
