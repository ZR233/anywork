import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

/// 真实 `StreamController` 驱动的 topic 源。
///
/// 订阅、取消、`asFuture`、pause/resume 等生命周期全部来自 SDK 的
/// `StreamSubscription`，不再手写 fake subscription；挂载与取消 ACK 分别由
/// `onListen` / `onCancel` 明确同步。
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

  /// 真正的 `listen` 已发生。
  Future<void> get listening => _listening.future;

  /// 上游订阅已按 ACK 取消。
  Future<void> get cancelled => _cancelled.future;

  /// 只在真实订阅者存在时投递；不在断开后伪造缓冲或静默丢弃。
  void emit(ProductTopicFrame frame) {
    if (!_attached) {
      throw StateError('the topic source is not subscribed');
    }
    _controller.add(frame);
  }
}

/// 只实现本契约需要的入口；其余 member 由 noSuchMethod 明确失败。
final class _ContractTransport implements StudioTransport {
  final Map<ProductTopic, _TopicSource> sources = {};
  final Map<ProductTopic, Completer<_TopicSource>> _attached = {};
  int catalogReads = 0;

  /// 订阅由 registry 串行 start 异步挂载（真实产品行为）：等到真正的 `listen`。
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
  Future<AcpAccountCatalogView> loadAcpAccountCatalog() async {
    catalogReads += 1;
    return const AcpAccountCatalogView(
      templates: [
        AcpAccountTemplateView(
          provider: AcpProviderView.antigravity,
          displayName: 'Antigravity',
          installUrl: 'https://antigravity.google/docs/ide/extensions',
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused contract transport: ${invocation.memberName}',
  );
}

const _verifyServer = AcpServerInfoView(name: 'antigravity', version: '1.2.3');

AcpAuthSnapshotView _snapshot(
  int revision,
  AcpAuthStateView state, {
  int connectionRevision = 7,
}) => AcpAuthSnapshotView(
  revision: revision,
  updatedAt: revision,
  accounts: [
    AcpAuthAccountView(
      accountId: 'acp-1',
      connectionRevision: connectionRevision,
      state: state,
    ),
  ],
);

Future<AnyworkClient> _bootstrapped(_ContractTransport transport) async {
  final client = AnyworkClient(transport: transport, clientId: 'acp-topic');
  await client.bootstrap();
  return client;
}

void main() {
  test(
    'application owner subscribes the ACP topic and feeds the reducer',
    () async {
      final transport = _ContractTransport();
      final client = await _bootstrapped(transport);
      addTearDown(client.close);
      addTearDown(client.channels.dispose);

      // Client 自己持有 acpAuth 租约：页面观察不是订阅的唯一来源。
      expect(client.channels.activeTopicRefCountViews()['acpAuth'], 1);
      final source = await transport.attached(const AcpAuthTopic());
      expect(source.isAttached, isTrue);

      // 首帧 baseline 进入同一个 reducer。
      source.emit(
        ProductTopicBaselineFrame(
          topic: const AcpAuthTopic(),
          revision: 3,
          state: AcpAuthBaseline(
            _snapshot(
              3,
              const AcpVerifiedState(checkedAt: 30, server: _verifyServer),
            ),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        client.acpAuth.stateOf('acp-1', connectionRevision: 7),
        isA<AcpVerifiedState>(),
      );

      // owner 事件推进；旧 revision 不得回退。
      source.emit(
        ProductTopicDataFrame(
          topic: const AcpAuthTopic(),
          event: ProductTopicEventEnvelope(
            eventId: 'event-4',
            sequence: BigInt.from(4),
            createdAt: DateTime.utc(2026),
            payload: AcpAuthStateChangedPayload(
              _snapshot(4, const AcpCheckingState(operationId: 'op-4')),
            ),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        client.acpAuth.stateOf('acp-1', connectionRevision: 7),
        isA<AcpCheckingState>(),
      );

      source.emit(
        ProductTopicDataFrame(
          topic: const AcpAuthTopic(),
          event: ProductTopicEventEnvelope(
            eventId: 'event-3',
            sequence: BigInt.from(5),
            createdAt: DateTime.utc(2026),
            payload: AcpAuthStateChangedPayload(
              _snapshot(3, const AcpUncheckedState()),
            ),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.acpAuth.state.revision, 4);
      expect(
        client.acpAuth.stateOf('acp-1', connectionRevision: 7),
        isA<AcpCheckingState>(),
      );
      expect(client.acpAuth.state.sync.isReady, isTrue);
    },
  );

  test(
    'a page observation lease does not own the business subscription',
    () async {
      final transport = _ContractTransport();
      final client = await _bootstrapped(transport);
      addTearDown(client.close);
      addTearDown(client.channels.dispose);
      final source = await transport.attached(const AcpAuthTopic());

      // 模拟页面观察：只借用 store，随后释放自己的观察。
      final watched = client.acpAuth.source.watchLatest((_) {});
      watched.observation.cancel();
      expect(client.channels.activeTopicRefCountViews()['acpAuth'], 1);

      source.emit(
        ProductTopicDataFrame(
          topic: const AcpAuthTopic(),
          event: ProductTopicEventEnvelope(
            eventId: 'event-9',
            sequence: BigInt.from(9),
            createdAt: DateTime.utc(2026),
            payload: AcpAuthStateChangedPayload(
              _snapshot(9, const AcpVerifiedState(checkedAt: 90, server: null)),
            ),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.acpAuth.state.revision, 9);
      // 页面释放后 Client 仍持有租约；只有 Client 关闭才取消。
      expect(client.channels.activeTopicRefCountViews()['acpAuth'], 1);

      // 关闭时等待上游真实 cancel ACK，而不是本地抹掉订阅。
      await client.channels.dispose();
      await source.cancelled;
      expect(source.isAttached, isFalse);
      expect(source.cancelCalls, 1);
    },
  );
}
