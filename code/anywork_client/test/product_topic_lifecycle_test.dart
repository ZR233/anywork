import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class _TopicTransport implements StudioTransport {
  final List<_TopicSource> sources = [];
  final List<Completer<_TopicSource>> _opened = [];

  Future<_TopicSource> opened(int index) {
    if (sources.length > index) return Future.value(sources[index]);
    while (_opened.length <= index) _opened.add(Completer());
    return _opened[index].future;
  }

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    final source = _TopicSource(topic);
    final index = sources.length;
    sources.add(source);
    if (_opened.length > index) _opened[index].complete(source);
    return source;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused fake topic capability: ${invocation.memberName}',
  );
}

/// The native source may still invoke a callback while its cancel ACK is pending.
final class _TopicSource extends Stream<ProductTopicFrame> {
  _TopicSource(this.topic);
  final ProductTopic topic;
  void Function(ProductTopicFrame)? _deliver;
  final Completer<void> cancellationStarted = Completer();
  Completer<void>? cancellationGate;
  Object? cancelFailure;
  int cancelCalls = 0;

  void emit(ProductTopicFrame frame) => _deliver?.call(frame);

  @override
  StreamSubscription<ProductTopicFrame> listen(
    void Function(ProductTopicFrame)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _deliver = onData;
    return _TopicSubscription(this);
  }

  Future<void> cancel() async {
    cancelCalls++;
    if (!cancellationStarted.isCompleted) cancellationStarted.complete();
    await cancellationGate?.future;
    if (cancelFailure case final error?) throw error;
  }
}

final class _TopicSubscription
    implements StreamSubscription<ProductTopicFrame> {
  _TopicSubscription(this.source);
  final _TopicSource source;
  @override
  Future<void> cancel() => source.cancel();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused fake subscription capability: ${invocation.memberName}',
  );
}

/// Minimal bootstrap facts so the real `bootstrap()` entry can run; every
/// resident topic subscription still goes through the real registry.
final class _BootstrapTopicTransport extends _TopicTransport {
  @override
  Future<StudioBootstrap> readBootstrap() async => StudioBootstrap(
    ownerEpoch: 'epoch-boot',
    projectDirectory: ProjectDirectoryState(),
    threadDirectory: ThreadDirectoryWindow(),
    agentDirectory: AgentDirectoryState(),
    settingsState: SettingsStateSnapshot(),
    recoveryState: RecoveryStateSnapshot(),
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
        revision: revision,
        items: items,
      ),
    ),
  ),
);

void main() {
  test(
    'scoped topic demand installs mirrors before the first native callback',
    () async {
      final transport = _TopicTransport();
      final budget = ResourceBudget(
        capacities: {ResourceKind.observer: 2, ResourceKind.readModel: 2},
      );
      final client = AnyworkClient(
        transport: transport,
        clientId: 'scoped',
        budget: budget,
      );
      expect(client.existingSkills('project'), isNull);
      expect(client.existingSessionCosts('root'), isNull);
      expect(budget.used(ResourceKind.readModel), 0);
      final leases = client.channels.acquireTopics([
        const SkillsTopic(workspaceId: 'project'),
        const SessionCostsTopic(rootThreadId: 'root'),
      ]);
      final skills = client.existingSkills('project')!;
      final costs = client.existingSessionCosts('root')!;
      expect(skills.state.loaded, isFalse);
      expect(costs.state.loaded, isFalse);
      expect(budget.used(ResourceKind.readModel), 2);
      final skillSource = await transport.opened(0);
      final costSource = await transport.opened(1);
      skillSource.emit(
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
      costSource.emit(
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
      expect(budget.used(ResourceKind.observer), 0);
      expect(budget.used(ResourceKind.readModel), 2);
      expect((await client.close()).complete, isTrue);
      expect(budget.usage, isEmpty);
    },
  );

  test(
    'child interactions topics are per-host mirrors with revision ordering',
    () async {
      final transport = _TopicTransport();
      final budget = ResourceBudget(
        capacities: {ResourceKind.observer: 2, ResourceKind.readModel: 2},
      );
      final client = AnyworkClient(
        transport: transport,
        clientId: 'child-topics',
        budget: budget,
      );
      expect(client.existingChildInteractions('host-a'), isNull);
      final leaseA = client.channels.acquireChildInteractions('host-a');
      final storeA = client.existingChildInteractions('host-a')!;
      expect(storeA.state.canonical.loaded, isFalse);
      final sourceA = await transport.opened(0);
      // 非空首帧基线在首个原生回调前已有自己的宿主镜像。
      sourceA.emit(
        ProductTopicBaselineFrame(
          topic: const ChildInteractionsTopic(hostThreadId: 'host-a'),
          revision: 2,
          state: ChildInteractionsBaseline(
            ChildInteractionsStateView(
              hostThreadId: 'host-a',
              revision: 2,
              items: [_hostedChildSummary('host-a', 'child-1', 5)],
            ),
          ),
        ),
      );
      expect(storeA.state.canonical.loaded, isTrue);
      expect(storeA.state.hasCurrentBaseline, isTrue);
      expect(storeA.state.canonical.revision, 2);
      expect(
        storeA.state.canonical.value?.items.single.interactionId,
        'interaction-child-1',
      );

      // 另一个宿主有独立镜像；互不覆盖。
      final leaseB = client.channels.acquireChildInteractions('host-b');
      final storeB = client.existingChildInteractions('host-b')!;
      final sourceB = await transport.opened(1);
      sourceB.emit(
        ProductTopicBaselineFrame(
          topic: const ChildInteractionsTopic(hostThreadId: 'host-b'),
          revision: 7,
          state: ChildInteractionsBaseline(
            ChildInteractionsStateView(hostThreadId: 'host-b', revision: 7),
          ),
        ),
      );
      expect(storeB.state.canonical.revision, 7);
      expect(storeB.state.hasCurrentBaseline, isTrue);
      expect(storeB.state.canonical.value?.items, isEmpty);
      expect(storeA.state.canonical.revision, 2);

      // 旧 revision 事件被拒；新 revision 事件替换集合。
      sourceA.emit(
        _childEvent('host-a', 2, [_hostedChildSummary('host-a', 'child-1', 9)]),
      );
      expect(storeA.state.canonical.value?.items.single.revision, 5);
      sourceA.emit(_childEvent('host-a', 3, const []));
      expect(storeA.state.canonical.value?.items, isEmpty);
      expect(storeA.state.canonical.revision, 3);

      // 同租约内的短暂滞后/重连只更新 sync：资格与集合身份保持不变。
      final canonicalBeforeLag = storeA.state.canonical;
      sourceA.emit(
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
      thirdSourceA.emit(
        ProductTopicBaselineFrame(
          topic: const ChildInteractionsTopic(hostThreadId: 'host-a'),
          revision: 1,
          state: ChildInteractionsBaseline(
            ChildInteractionsStateView(
              hostThreadId: 'host-a',
              revision: 1,
              items: [_hostedChildSummary('host-a', 'child-9', 1)],
            ),
          ),
        ),
      );
      expect(storeA.state.hasCurrentBaseline, isFalse);
      expect(storeA.state.canonical.revision, 3);
      expect(storeA.state.canonical.value?.items, isEmpty);
      thirdSourceA.emit(
        ProductTopicBaselineFrame(
          topic: const ChildInteractionsTopic(hostThreadId: 'host-a'),
          revision: 3,
          state: ChildInteractionsBaseline(
            ChildInteractionsStateView(hostThreadId: 'host-a', revision: 3),
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
      expect((await client.close()).complete, isTrue);
      expect(budget.usage, isEmpty);
    },
  );

  test('child interactions state view freezes its items', () {
    final input = <ChildInteractionSummary>[
      _hostedChildSummary('host-a', 'child-1', 5),
    ];
    final view = ChildInteractionsStateView(
      hostThreadId: 'host-a',
      revision: 1,
      items: input,
    );
    input.clear();
    expect(view.items, hasLength(1), reason: '构造边界复制输入列表');
    expect(
      () => view.items.clear(),
      throwsUnsupportedError,
      reason: '读取到的列表不可变异',
    );
    expect(view.hostThreadId, 'host-a');
    expect(view.revision, 1);
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
      final budget = ResourceBudget(capacities: {ResourceKind.observer: 1});
      final client = AnyworkClient(
        transport: transport,
        clientId: 'app',
        budget: budget,
      );
      final firstLease = client.channels.acquireTopic(const UpdaterTopic());
      final secondLease = client.channels.acquireTopic(const UpdaterTopic());
      expect(budget.used(ResourceKind.observer), 1);
      expect(budget.usage.single.phase, ResourcePhase.opening);
      final old = await transport.opened(0);
      old.emit(_updater(1));
      expect(client.updater.state.value?.revision, 1);
      await firstLease.release();
      expect(old.cancelCalls, 0);
      old.cancellationGate = Completer();
      final releasing = secondLease.release();
      await old.cancellationStarted.future;
      expect(budget.usage.single.phase, ResourcePhase.retiring);
      final newLease = client.channels.acquireTopic(const UpdaterTopic());
      old.emit(_updater(99));
      expect(client.updater.state.value?.revision, 1);
      expect(transport.sources, hasLength(1));
      expect(budget.used(ResourceKind.observer), 1);
      old.cancellationGate!.complete();
      await releasing;
      final replacement = await transport.opened(1);
      replacement.emit(_updater(2));
      old.emit(_updater(100));
      expect(client.updater.state.value?.revision, 2);
      expect(client.channels.activeTopicRefCountViews(), {'updater': 1});
      await newLease.release();
      expect(budget.used(ResourceKind.observer), 0);
      await client.close();
    },
  );

  test(
    'cancel failure retains the same owner and blocks a second subscription',
    () async {
      final transport = _TopicTransport();
      final budget = ResourceBudget(capacities: {ResourceKind.observer: 1});
      final client = AnyworkClient(
        transport: transport,
        clientId: 'app',
        budget: budget,
      );
      final lease = client.channels.acquireTopic(const UpdaterTopic());
      final old = await transport.opened(0);
      old.cancelFailure = StateError('native observer did not stop');
      await expectLater(
        lease.release(),
        throwsA(isA<BridgeTopicCleanupBlocked>()),
      );
      expect(budget.usage.single.phase, ResourcePhase.unresolved);
      expect(client.channels.activeTopicRefCountViews(), {'updater': 0});
      final reacquired = client.channels.acquireTopic(const UpdaterTopic());
      expect(transport.sources, hasLength(1));
      expect(client.channels.unresolvedResources, hasLength(1));
      old.cancelFailure = null;
      client.channels.retryTopic(const UpdaterTopic());
      final replacement = await transport.opened(1);
      replacement.emit(_updater(3));
      old.emit(_updater(100));
      expect(client.updater.state.value?.revision, 3);
      expect(client.channels.unresolvedResources, isEmpty);
      await reacquired.release();
      expect(replacement.cancelCalls, 1);
      expect(client.channels.activeTopicRefCountViews(), isEmpty);
      expect(budget.used(ResourceKind.observer), 0);
      await client.close();
    },
  );

  test(
    'topic budget exhaustion preserves the already active canonical source',
    () async {
      final transport = _TopicTransport();
      final budget = ResourceBudget(capacities: {ResourceKind.observer: 1});
      final client = AnyworkClient(
        transport: transport,
        clientId: 'app',
        budget: budget,
      );
      client.channels.acquireTopic(const UpdaterTopic());
      final source = await transport.opened(0);
      expect(
        () => client.channels.acquireTopic(const RecoveryTopic()),
        throwsA(isA<ResourceBudgetExceeded>()),
      );
      source.emit(_updater(4));
      expect(client.updater.state.value?.revision, 4);
      expect(transport.sources, hasLength(1));
      expect((await client.channels.dispose()).complete, isTrue);
      expect(budget.used(ResourceKind.observer), 0);
      await client.close();
    },
  );

  test(
    'close reports unresolved native cleanup and retry retains its permit',
    () async {
      final transport = _TopicTransport();
      final budget = ResourceBudget(capacities: {ResourceKind.observer: 1});
      final client = AnyworkClient(
        transport: transport,
        clientId: 'app',
        budget: budget,
      );
      final lease = client.channels.acquireTopic(const UpdaterTopic());
      final source = await transport.opened(0);
      source.cancelFailure = StateError('native sink cleanup failed');
      final report = await client.channels.dispose();
      expect(report.complete, isFalse);
      expect(report.unresolved.single.owner, 'topic:updater');
      expect(client.channels.activeTopicRefCountViews(), {'updater': 0});
      expect(budget.used(ResourceKind.observer), 1);
      source.cancelFailure = null;
      expect((await client.channels.retryCleanup()).complete, isTrue);
      expect(budget.used(ResourceKind.observer), 0);
      await lease.release();
      await client.close();
    },
  );

  test(
    'lagged rebuild joins only its source while another topic keeps reducing',
    () async {
      final transport = _TopicTransport();
      final client = AnyworkClient(transport: transport, clientId: 'app');
      final leases = client.channels.acquireTopics([
        const UpdaterTopic(),
        const RecoveryTopic(),
      ]);
      final updater = await transport.opened(0);
      final recovery = await transport.opened(1);
      updater.emit(_updater(1));
      updater.cancellationGate = Completer();
      updater.emit(
        const ProductTopicLaggedFrame(topic: UpdaterTopic(), dropped: 1),
      );
      await updater.cancellationStarted.future;
      recovery.emit(
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
      replacement.emit(_updater(2));
      updater.emit(_updater(99));
      expect(client.updater.state.value?.revision, 2);
      expect(recovery.cancelCalls, 0);
      await leases.release();
      await client.close();
    },
  );

  test('repeated topic exit shares the first deadline and keeps pending cancel owned', () async {
    final transport = _TopicTransport();
    final budget = ResourceBudget(capacities: {ResourceKind.observer: 1});
    final client = AnyworkClient(
      transport: transport,
      clientId: 'app',
      budget: budget,
    );
    client.channels.acquireTopic(const UpdaterTopic());
    final source = await transport.opened(0);
    source.cancellationGate = Completer();
    final closing = client.channels.dispose(deadline: DateTime.utc(2000));
    expect(
      identical(closing, client.channels.dispose(deadline: DateTime.utc(2099))),
      isTrue,
    );
    expect((await closing).complete, isFalse);
    await source.cancellationStarted.future;
    source.emit(_updater(99));
    expect(client.updater.state.value, isNull);
    expect(budget.used(ResourceKind.observer), 1);
    source.cancellationGate!.complete();
    expect((await client.channels.retryCleanup()).complete, isTrue);
    expect(budget.used(ResourceKind.observer), 0);
    await client.close();
  });

  test(
    'bootstrap owns the resident bots topic and releases it on close',
    () async {
      final transport = _BootstrapTopicTransport();
      final client = AnyworkClient(transport: transport, clientId: 'boot');
      await client.bootstrap();
      // The Client—not a visible page scope—is the resident bots owner, so a
      // GUI observer or settings round trip can never be its only demand.
      expect(client.applicationTopics, contains(const BotsTopic()));
      _TopicSource? resident;
      for (var attempt = 0; resident == null && attempt < 100; attempt++) {
        await Future<void>.delayed(Duration.zero);
        for (final candidate in transport.sources) {
          if (candidate.topic == const BotsTopic()) resident = candidate;
        }
      }
      expect(resident, isNotNull, reason: 'the bots subscription is created');
      final source = resident!;
      source.emit(
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
      source.emit(
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
      expect((await client.close()).complete, isTrue);
      expect(source.cancelCalls, 1);
    },
  );
}
