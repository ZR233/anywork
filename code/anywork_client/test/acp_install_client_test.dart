import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

/// 真实 `StreamController` 驱动的 topic 源（与既有 ACP 契约测试同构）。
final class _TopicSource {
  _TopicSource(this.topic) {
    _controller = StreamController<ProductTopicFrame>(
      onListen: () {
        _attached = true;
        if (!_listening.isCompleted) _listening.complete();
      },
      onCancel: () {
        _attached = false;
        cancelCalls += 1;
        if (!_cancelled.isCompleted) _cancelled.complete();
      },
    );
  }

  final ProductTopic topic;
  late final StreamController<ProductTopicFrame> _controller;
  final Completer<void> _listening = Completer<void>();
  final Completer<void> _cancelled = Completer<void>();
  bool _attached = false;
  int cancelCalls = 0;

  Stream<ProductTopicFrame> get stream => _controller.stream;
  bool get isAttached => _attached;
  Future<void> get listening => _listening.future;
  Future<void> get cancelled => _cancelled.future;

  void emit(ProductTopicFrame frame) {
    if (!_attached) throw StateError('the topic source is not subscribed');
    _controller.add(frame);
  }
}

const _release = AcpInstallReleaseView(
  version: '1.4.1',
  target: 'linux-x86_64',
  archiveUrl: 'https://dl.google.com/agy-extensions/releases/a.zip',
);

AcpInstallSnapshotView _snapshot(int revision, AcpInstallStateView state) =>
    AcpInstallSnapshotView(
      revision: revision,
      updatedAt: revision,
      installations: [
        AcpInstallEntryView(
          provider: AcpProviderView.antigravity,
          state: state,
        ),
      ],
    );

/// 只实现本契约需要的入口；其余 member 由 noSuchMethod 明确失败。
final class _InstallTransport implements StudioTransport {
  final Map<ProductTopic, _TopicSource> sources = {};
  final Map<ProductTopic, Completer<_TopicSource>> _attached = {};

  /// start 的返回方式由测试脚本决定：立即回执，或挂起到取消。
  Completer<AcpInstallCommandReply>? pendingStart;
  int startCalls = 0;
  int cancelCalls = 0;

  /// 取消命令实际收到的 target 身份：断言命中 canonical operation，而不是看回执。
  OperationId? lastCancelTarget;
  AcpProviderView? lastCancelProvider;
  AcpInstallSnapshotView replySnapshot = _snapshot(
    1,
    const AcpResolvingState(operationId: 'op-1'),
  );

  Future<_TopicSource> attached(ProductTopic topic) async {
    final source =
        sources[topic] ??
        await (_attached[topic] ??= Completer<_TopicSource>()).future;
    await source.listening;
    return source;
  }

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    final source = _TopicSource(topic);
    sources[topic] = source;
    final opening = _attached[topic];
    if (opening != null && !opening.isCompleted) opening.complete(source);
    return source.stream;
  }

  @override
  Future<StudioBootstrap> readBootstrap() async => StudioBootstrap(
    ownerEpoch: 'owner-1',
    projectDirectory: ProjectDirectoryState(values: const [], revision: 1),
    threadDirectory: ThreadDirectoryWindow(threads: const [], revision: 1),
    agentDirectory: AgentDirectoryState(revision: 1),
    settingsState: SettingsStateSnapshot(revision: 1),
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
  );

  @override
  Future<AccountCatalogView> loadAccountCatalog() async =>
      const AccountCatalogView.empty();

  @override
  Future<AcpAccountCatalogView> loadAcpAccountCatalog() async =>
      const AcpAccountCatalogView(
        templates: [
          AcpAccountTemplateView(
            provider: AcpProviderView.antigravity,
            displayName: 'Antigravity',
            automaticInstall: AcpInstallAvailableView(target: 'linux-x86_64'),
          ),
        ],
      );

  @override
  Future<AcpInstallSnapshotView> readAcpInstallState() async =>
      _snapshot(0, const AcpInstallIdleState());

  @override
  Future<AcpInstallCommandReply> startAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
  }) {
    startCalls += 1;
    final reply = AcpInstallCommandReply(
      // 回执资源是 `acp-install`，水位取**当前 canonical**（含 revision 0）。
      receipt: StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: [
          ResourceStamp(
            resourceKey: 'acp-install',
            ownerEpoch: 'owner-1',
            revision: replySnapshot.revision,
          ),
        ],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
      ),
      snapshot: replySnapshot,
    );
    final gate = pendingStart;
    if (gate == null) return Future.value(reply);
    return gate.future.then((_) => reply);
  }

  @override
  Future<AcpInstallCommandReply> cancelAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
    required OperationId targetOperationId,
  }) {
    cancelCalls += 1;
    lastCancelTarget = targetOperationId;
    lastCancelProvider = provider;
    final snapshot = _snapshot(
      2,
      AcpInstallCancellingState(operationId: targetOperationId.value),
    );
    pendingStart?.complete(
      AcpInstallCommandReply(
        receipt: StudioCommandReceipt(
          operationId: targetOperationId,
          disposition: CommitDisposition.applied,
          targets: [
            ResourceStamp(
              resourceKey: 'acp-install',
              ownerEpoch: 'owner-1',
              revision: 2,
            ),
          ],
          effect: EffectPoint.immediate,
          effective: true,
          durable: false,
        ),
        snapshot: snapshot,
      ),
    );
    pendingStart = null;
    return Future.value(
      AcpInstallCommandReply(
        receipt: StudioCommandReceipt(
          operationId: operationId,
          disposition: CommitDisposition.applied,
          targets: [
            ResourceStamp(
              resourceKey: 'acp-install',
              ownerEpoch: 'owner-1',
              revision: 2,
            ),
          ],
          effect: EffectPoint.immediate,
          effective: true,
          durable: false,
        ),
        snapshot: snapshot,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused install transport: ${invocation.memberName}',
  );
}

Future<AnyworkClient> _bootstrapped(_InstallTransport transport) async {
  final client = AnyworkClient(transport: transport, clientId: 'acp-install');
  await client.bootstrap();
  return client;
}

void main() {
  test('application owner subscribes acpInstall and revision 0 is a real observation', () async {
    final transport = _InstallTransport();
    final client = await _bootstrapped(transport);
    addTearDown(client.close);
    addTearDown(client.channels.dispose);
    expect(client.channels.activeTopicRefCountViews()['acpInstall'], 1);
    final source = await transport.attached(const AcpInstallTopic());

    // revision 0 也是已加载水位：MutationBoard 必须据此满足回执。
    source.emit(
      const ProductTopicBaselineFrame(
        topic: AcpInstallTopic(),
        revision: 0,
        state: AcpInstallBaseline(AcpInstallSnapshotView.empty()),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.acpInstall.state.loaded, isTrue);
    expect(client.acpInstall.state.revision, 0);

    final snapshot = await client.acpInstallCommands.start(
      AcpProviderView.antigravity,
    );
    expect(snapshot.revision, 1);
    final operation = client.mutations.operations.last;
    expect(operation.target, 'acp-install');
    // rev0 水位就足以满足回执：不留在 awaitingObservation，也不占 pending 预算。
    expect(operation.observed, isTrue);
    expect(operation.isPending, isFalse);
    expect(client.budget.used(ResourceKind.pendingOperation), 0);
  });

  test('an event before the reply still satisfies the same receipt', () async {
    final transport = _InstallTransport();
    final client = await _bootstrapped(transport);
    addTearDown(client.close);
    addTearDown(client.channels.dispose);
    final source = await transport.attached(const AcpInstallTopic());
    source.emit(
      const ProductTopicBaselineFrame(
        topic: AcpInstallTopic(),
        revision: 0,
        state: AcpInstallBaseline(AcpInstallSnapshotView.empty()),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // 先到的事件把水位推到 2，回执声明的 1 已被覆盖。
    source.emit(
      ProductTopicDataFrame(
        topic: const AcpInstallTopic(),
        event: ProductTopicEventEnvelope(
          eventId: 'evt-1',
          sequence: BigInt.one,
          createdAt: DateTime.utc(2026),
          payload: AcpInstallStateChangedPayload(
            _snapshot(
              2,
              const AcpDownloadingState(
                operationId: 'op-1',
                release: _release,
                progress: AcpInstallProgressView(
                  completedBytes: 2048,
                  totalBytes: 4096,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      client.acpInstall.stateOf(AcpProviderView.antigravity).operationId,
      'op-1',
    );

    final snapshot = await client.acpInstallCommands.start(
      AcpProviderView.antigravity,
    );
    expect(snapshot.revision, 1);
    // 事件先到、回执后到：命令仍被观察满足，不会永久停在 awaitingObservation。
    final operation = client.mutations.operations.last;
    expect(operation.observed, isTrue);
    expect(operation.isPending, isFalse);
    expect(
      client.acpInstall.stateOf(AcpProviderView.antigravity),
      isA<AcpDownloadingState>(),
    );
  });

  test('cancel runs on its own lane while start is still pending', () async {
    final transport = _InstallTransport();
    final client = await _bootstrapped(transport);
    addTearDown(client.close);
    addTearDown(client.channels.dispose);
    final source = await transport.attached(const AcpInstallTopic());
    source.emit(
      const ProductTopicBaselineFrame(
        topic: AcpInstallTopic(),
        revision: 0,
        state: AcpInstallBaseline(AcpInstallSnapshotView.empty()),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // start 挂起：canonical 先通过 topic 给出 operation 身份。
    transport.pendingStart = Completer<AcpInstallCommandReply>();
    final starting = client.acpInstallCommands.start(
      AcpProviderView.antigravity,
    );
    source.emit(
      ProductTopicDataFrame(
        topic: const AcpInstallTopic(),
        event: ProductTopicEventEnvelope(
          eventId: 'evt-2',
          sequence: BigInt.one,
          createdAt: DateTime.utc(2026),
          payload: AcpInstallStateChangedPayload(
            _snapshot(1, const AcpResolvingState(operationId: 'op-1')),
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // 取消不排在 start 之后：不需要先完成 start 就能提交。
    final cancelled = await client.acpInstallCommands.cancel(
      AcpProviderView.antigravity,
    );
    expect(transport.cancelCalls, 1);
    // 取消必须命中 canonical 给出的 operation 身份与 provider。
    expect(transport.lastCancelTarget, const OperationId('op-1'));
    expect(transport.lastCancelProvider, AcpProviderView.antigravity);
    expect(
      cancelled.stateOf(AcpProviderView.antigravity),
      isA<AcpInstallCancellingState>(),
    );
    await starting;

    // 同一 provider 只受理一个 start；结束后才允许新的意图。
    await expectLater(
      client.acpInstallCommands.start(AcpProviderView.antigravity),
      completes,
    );
  });

  test('a duplicate start is rejected before touching the transport', () async {
    final transport = _InstallTransport();
    final client = await _bootstrapped(transport);
    addTearDown(client.close);
    addTearDown(client.channels.dispose);
    await transport.attached(const AcpInstallTopic());
    transport.pendingStart = Completer<AcpInstallCommandReply>();
    final first = client.acpInstallCommands.start(AcpProviderView.antigravity);
    await expectLater(
      client.acpInstallCommands.start(AcpProviderView.antigravity),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.busy,
        ),
      ),
    );
    expect(transport.startCalls, 1);
    transport.pendingStart!.complete(
      AcpInstallCommandReply(
        receipt: StudioCommandReceipt(
          operationId: OperationId('op-1'),
          disposition: CommitDisposition.applied,
          targets: [
            ResourceStamp(
              resourceKey: 'acp-install',
              ownerEpoch: 'owner-1',
              revision: 1,
            ),
          ],
          effect: EffectPoint.immediate,
          effective: true,
          durable: false,
        ),
        snapshot: _snapshot(1, const AcpResolvingState(operationId: 'op-1')),
      ),
    );
    await first;
  });

  test('leaving the page only releases its own observation', () async {
    final transport = _InstallTransport();
    final client = await _bootstrapped(transport);
    addTearDown(client.close);
    addTearDown(client.channels.dispose);
    final source = await transport.attached(const AcpInstallTopic());
    source.emit(
      ProductTopicDataFrame(
        topic: const AcpInstallTopic(),
        event: ProductTopicEventEnvelope(
          eventId: 'evt-3',
          sequence: BigInt.one,
          createdAt: DateTime.utc(2026),
          payload: AcpInstallStateChangedPayload(
            _snapshot(
              3,
              const AcpDownloadingState(
                operationId: 'op-9',
                release: _release,
                progress: AcpInstallProgressView(
                  completedBytes: 10,
                  totalBytes: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final scope = client.channels.acquireSettingsScope(
      BridgeSettingsScopeKind.acp,
      null,
    );
    expect(client.channels.activeTopicRefCountViews()['acpInstall'], 2);
    await scope.release();
    // 离页只取消自己的观察：下载没有被取消，canonical 仍然在。
    expect(client.channels.activeTopicRefCountViews()['acpInstall'], 1);
    expect(source.isAttached, isTrue);
    expect(source.cancelCalls, 0);
    expect(
      client.acpInstall.stateOf(AcpProviderView.antigravity).operationId,
      'op-9',
    );
  });

  test('a draft intent only accepts its own provider and operation', () {
    final intent = const AcpPreparationIntent(
      provider: AcpProviderView.antigravity,
    );
    final ready = AcpInstallReadyState(
      operationId: 'op-a',
      server: AcpInstalledServerView(
        installationId: 'installation-a',
        release: _release,
        program: '/servers/a/program',
        readyAt: 10,
      ),
    );
    // 没有认领时不能凭“同品牌”自动填入。
    expect(
      intent.resolve(ready, provider: AcpProviderView.antigravity),
      isNull,
    );
    expect(
      intent.availableElsewhere(ready, provider: AcpProviderView.antigravity),
      isNotNull,
    );

    final claimed = intent.claim('op-a');
    expect(
      claimed.resolve(ready, provider: AcpProviderView.antigravity)?.program,
      '/servers/a/program',
    );
    // 其他操作的就绪结果不可回填。
    final other = AcpInstallReadyState(
      operationId: 'op-b',
      server: AcpInstalledServerView(
        installationId: 'installation-b',
        release: _release,
        program: '/servers/b/program',
      ),
    );
    expect(
      claimed.resolve(other, provider: AcpProviderView.antigravity),
      isNull,
    );

    // 换来源推进代次：绑定被清空，旧结果只能显式认领。
    final renewed = claimed.renewed();
    expect(renewed.generation, claimed.generation + 1);
    expect(renewed.operationId, isNull);
    expect(
      renewed.resolve(ready, provider: AcpProviderView.antigravity),
      isNull,
    );
  });
}
