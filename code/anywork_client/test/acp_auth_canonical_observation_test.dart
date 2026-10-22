import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

/// `acp-auth` 的 canonical 水位必须由生产观察链登记。
///
/// 命令回执的 targets 是 `acp-auth`，产品 topic 帧与命令响应进入同一 reducer；如果
/// Client 只登记 settings/thread-directory/mode-catalog 的水位，check/login/cancel
/// 受理后会永久停在 `awaitingObservation`（UI 正常，close 报告却挂着 pending
/// operation）。这些用例只驱动生产入口（真实 `AnyworkClient`、真实
/// MutationBoard/预算/命令 lane、真实 bootstrap ownerEpoch、真实命令方法），fake
/// 仅出现在 transport 边界，并且不调用 `observeResource` 之类内部动作替代被测行为。
const _epoch = 'epoch-acp';

final class _AcpTransport implements StudioTransport {
  /// 保存的接入连接身份；所有用例沿用同一身份（7）。
  final int connectionRevision = 7;
  final List<String> accountIds = const ['acp-1'];

  /// 每条命令回执携带的 `acp-auth` 目标 revision；测试据此模拟迟到或更旧的事实。
  int startRevision = 1;
  int cancelRevision = 2;

  int startCalls = 0;
  int cancelCalls = 0;
  AcpAuthActionView? lastAction;
  int? lastExpectedConnectionRevision;
  OperationId? lastCancelTarget;

  /// 让 start 停在 transport 上，用于构造“topic 帧先到、回执后到”的时序。
  bool holdStart = false;
  Completer<void>? pendingStart;

  /// start 命令已到达 transport 的信号（测试用它等待入口，不做无界轮询）。
  final Completer<void> startEntered = Completer<void>();

  StudioCommandReceipt _receipt(OperationId operationId, int revision) =>
      StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: [
          ResourceStamp(
            resourceKey: 'acp-auth',
            ownerEpoch: _epoch,
            revision: revision,
          ),
        ],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
      );

  AcpAuthSnapshotView _snapshot(int revision, AcpAuthStateView state) =>
      AcpAuthSnapshotView(
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

  @override
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  }) async {
    startCalls += 1;
    lastAction = action;
    lastExpectedConnectionRevision = expectedConnectionRevision;
    final reply = AcpAuthCommandReply(
      receipt: _receipt(operationId, startRevision),
      snapshot: _snapshot(
        startRevision,
        AcpCheckingState(operationId: operationId.value),
      ),
    );
    if (!startEntered.isCompleted) startEntered.complete();
    if (holdStart) {
      final gate = pendingStart = Completer<void>();
      await gate.future;
    }
    return reply;
  }

  @override
  Future<AcpAuthCommandReply> cancelAcpAuth({
    required OperationId operationId,
    required String accountId,
    required OperationId targetOperationId,
  }) async {
    cancelCalls += 1;
    lastCancelTarget = targetOperationId;
    return AcpAuthCommandReply(
      receipt: _receipt(operationId, cancelRevision),
      snapshot: _snapshot(cancelRevision, const AcpCancelledState()),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}

StudioBootstrap _bootstrap(_AcpTransport transport) => StudioBootstrap(
  ownerEpoch: _epoch,
  projectDirectory: ProjectDirectoryState(values: const [], revision: 1),
  threadDirectory: const ThreadDirectoryWindow(threads: [], revision: 1),
  agentDirectory: AgentDirectoryState(revision: 1),
  settingsState: SettingsStateSnapshot(
    revision: 1,
    acpAccounts: [
      for (final accountId in transport.accountIds)
        AcpAccountSettingsView(
          accountId: accountId,
          name: accountId,
          provider: AcpProviderView.antigravity,
          program: '/opt/antigravity/bin/server',
          args: const ['--acp-stdio'],
          connectionRevision: transport.connectionRevision,
        ),
    ],
  ),
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

AnyworkClient _client(_AcpTransport transport) {
  final client = AnyworkClient(transport: transport, clientId: 'acp');
  client.applyBootstrap(_bootstrap(transport));
  addTearDown(client.close);
  return client;
}

/// 该接入最近一次认证命令对应的 operation（MutationBoard 保留最新意图）。
OperationHandle _operation(AnyworkClient client) =>
    client.mutations.latest('acp-auth:acp-1')!;

const _authenticating = AcpAuthSnapshotView(
  revision: 5,
  updatedAt: 5,
  accounts: [
    AcpAuthAccountView(
      accountId: 'acp-1',
      connectionRevision: 7,
      state: AcpAuthenticatingState(
        operationId: 'op-auth',
        methodId: 'browser',
      ),
    ),
  ],
);

void main() {
  test('check 受理后由 canonical 水位解除 pending，close 报告无残留', () async {
    final transport = _AcpTransport();
    final client = _client(transport);

    await client.acpCommands.check('acp-1');

    expect(transport.lastAction, isA<AcpCheckActionView>());
    expect(transport.lastExpectedConnectionRevision, 7);
    final state = _operation(client).state.value;
    expect(state.observed, isTrue);
    expect(state.isPending, isFalse);
    expect(state.phase, OperationPhase.effective);
    expect(client.budget.used(ResourceKind.pendingOperation), 0);

    final report = await client.close();
    expect(report.unresolved, isEmpty);
    expect(client.unresolvedResources, isEmpty);
  });

  test('login 与 cancel 走同一 acp-auth 水位', () async {
    final transport = _AcpTransport();
    final client = _client(transport);

    await client.acpCommands.check('acp-1');
    await client.acpCommands.login('acp-1', methodId: 'browser');
    expect(transport.lastAction, isA<AcpAuthenticateActionView>());
    expect(
      (transport.lastAction as AcpAuthenticateActionView).methodId,
      'browser',
    );
    expect(_operation(client).state.value.observed, isTrue);

    // topic 先给出在途 operation 身份：取消以该操作作为目标。
    client.acpAuth.apply(_authenticating);
    transport.cancelRevision = 6;
    await client.acpCommands.cancel('acp-1');

    expect(transport.lastCancelTarget?.value, 'op-auth');
    final cancelState = _operation(client).state.value;
    expect(cancelState.observed, isTrue);
    expect(cancelState.isPending, isFalse);
    expect(client.budget.used(ResourceKind.pendingOperation), 0);
    expect((await client.close()).unresolved, isEmpty);
  });

  // 注意：本用例把“canonical 帧”直接送入产品 reducer 入口（`acpAuth.apply`，即
  // 生产 topic owner 与命令响应共用的同一个 store 入口），不经过 bridge 的 topic
  // 帧编解码；真实 topic 订阅→reducer 的接线由 `acp_auth_topic_contract_test.dart`
  // 证明。这里只验证“水位先到 / 回执迟到”的收敛顺序。
  test('canonical 帧先于迟到回执时同一 operation 仍被观察', () async {
    final transport = _AcpTransport()..holdStart = true;
    final client = _client(transport);

    final connecting = client.acpCommands.check('acp-1');
    await transport.startEntered.future.timeout(const Duration(seconds: 5));
    expect(transport.pendingStart, isNotNull);
    // 回执仍挂在 transport 上：水位只能来自 reducer 收到的这一帧。
    client.acpAuth.apply(_authenticating);
    expect(_operation(client).state.value.observed, isFalse);

    transport.pendingStart!.complete();
    await connecting;

    // 迟到的回执（revision 1 < 5）不得回退水位，且同一 operation 仍被观察到。
    expect(client.acpAuth.state.revision, 5);
    final state = _operation(client).state.value;
    expect(state.observed, isTrue);
    expect(state.isPending, isFalse);
    expect((await client.close()).unresolved, isEmpty);
  });

  test('首帧 revision 0 也是有效 canonical 水位', () async {
    final transport = _AcpTransport()..startRevision = 0;
    final client = _client(transport);
    expect(client.acpAuth.state.loaded, isFalse);

    client.acpAuth.apply(
      const AcpAuthSnapshotView(
        revision: 0,
        updatedAt: 0,
        accounts: [
          AcpAuthAccountView(
            accountId: 'acp-1',
            connectionRevision: 7,
            state: AcpUncheckedState(),
          ),
        ],
      ),
    );
    expect(client.acpAuth.state.loaded, isTrue);

    await client.acpCommands.check('acp-1');

    final state = _operation(client).state.value;
    expect(state.observed, isTrue);
    expect(state.isPending, isFalse);
    expect((await client.close()).unresolved, isEmpty);
  });

  test('更旧的 revision 帧不回退水位，也不重新挂起回执', () async {
    final transport = _AcpTransport()..startRevision = 4;
    final client = _client(transport);
    await client.acpCommands.check('acp-1');
    expect(client.acpAuth.state.revision, 4);

    // 迟到/重复的旧帧进入同一 reducer 后被丢弃。
    client.acpAuth.apply(
      const AcpAuthSnapshotView(
        revision: 2,
        updatedAt: 2,
        accounts: [
          AcpAuthAccountView(
            accountId: 'acp-1',
            connectionRevision: 7,
            state: AcpCancelledState(),
          ),
        ],
      ),
    );
    expect(client.acpAuth.state.revision, 4);

    // 目标 revision 更旧（3 < 4）的回执由已登记水位覆盖，不重新进入 pending。
    transport.startRevision = 3;
    await client.acpCommands.check('acp-1');
    final state = _operation(client).state.value;
    expect(state.observed, isTrue);
    expect(state.isPending, isFalse);
    expect(client.budget.used(ResourceKind.pendingOperation), 0);
    expect((await client.close()).unresolved, isEmpty);
  });
}
