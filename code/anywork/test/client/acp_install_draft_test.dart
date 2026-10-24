import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/features/settings/settings_acp_account_draft.dart';
import 'package:anywork/src/features/settings/settings_account_draft_save.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _release = AcpInstallReleaseView(
  version: '1.4.1',
  target: 'linux-x86_64',
  archiveUrl: 'https://dl.google.com/agy-extensions/releases/a.zip',
);

const _prepared = AcpInstalledServerView(
  installationId: 'installation-1',
  release: _release,
  program: '/home/studio/acp-servers/antigravity/program',
  readyAt: 100,
);

AcpAccountTemplateView _template({bool automatic = true}) =>
    AcpAccountTemplateView(
      provider: AcpProviderView.antigravity,
      displayName: 'Antigravity',
      supportedVersion: '1.4.1',
      installUrl: 'https://antigravity.google/docs/ide/extensions',
      automaticInstall: automatic
          ? const AcpInstallAvailableView(target: 'linux-x86_64')
          : const AcpInstallUnsupportedPlatformView(),
    );

/// transport 边界：`start` 的真实回执由测试逐个放行，其余入口由 noSuchMethod 拒绝。
final class _StartTransport implements StudioTransport {
  final List<Completer<AcpInstallCommandReply>> pending = [];

  /// Client 为每次命令生成的受理身份：回执必须回显它，不能自造。
  final List<OperationId> commandIds = [];
  int startCalls = 0;

  @override
  Future<AcpInstallCommandReply> startAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
  }) {
    startCalls += 1;
    final completer = Completer<AcpInstallCommandReply>();
    pending.add(completer);
    commandIds.add(operationId);
    return completer.future;
  }

  /// 等到第 [count] 次 start 真正到达 transport（命令 lane 是异步的）。
  Future<void> waitStarts(int count) async {
    for (var attempt = 0; attempt < 1000; attempt++) {
      if (pending.length >= count) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('transport saw ${pending.length} starts, expected $count');
  }

  void succeed(
    int index,
    AcpSnapshotIntent intent, {
    required String operationId,
  }) {
    final snapshot = intent.snapshot(operationId);
    pending[index].complete(
      AcpInstallCommandReply(
        receipt: StudioCommandReceipt(
          // 回执身份必须是 Client 生成的受理 identity，快照里才是安装 operation。
          operationId: commandIds[index],
          disposition: CommitDisposition.applied,
          targets: [
            ResourceStamp(
              resourceKey: 'acp-install',
              ownerEpoch: 'owner-1',
              revision: snapshot.revision,
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

  void fail(int index, Object error) => pending[index].completeError(error);

  @override
  Future<StudioBootstrap> readBootstrap() async => StudioBootstrap(
    ownerEpoch: 'owner-1',
    projectDirectory: ProjectDirectoryState(revision: 1),
    threadDirectory: ThreadDirectoryWindow(revision: 1),
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
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) =>
      const Stream<ProductTopicFrame>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused start transport: ${invocation.memberName}',
  );
}

/// 可控 cancel transport：真实命令挂起回执，并记录 transport 看到的**目标 operation**。
final class _CancelTransport implements StudioTransport {
  final List<Completer<AcpInstallCommandReply>> pending = [];
  final List<OperationId> commandIds = [];
  final List<String> targets = [];

  @override
  Future<AcpInstallCommandReply> cancelAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
    required OperationId targetOperationId,
  }) {
    commandIds.add(operationId);
    targets.add(targetOperationId.value);
    final completer = Completer<AcpInstallCommandReply>();
    pending.add(completer);
    return completer.future;
  }

  void succeed(int index, AcpInstallSnapshotView snapshot) {
    pending[index].complete(
      AcpInstallCommandReply(
        receipt: StudioCommandReceipt(
          operationId: commandIds[index],
          disposition: CommitDisposition.applied,
          targets: [
            ResourceStamp(
              resourceKey: 'acp-install',
              ownerEpoch: 'owner-1',
              revision: snapshot.revision,
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
  Future<StudioBootstrap> readBootstrap() async => StudioBootstrap(
    ownerEpoch: 'owner-1',
    projectDirectory: ProjectDirectoryState(revision: 1),
    threadDirectory: ThreadDirectoryWindow(revision: 1),
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
      const AcpAccountCatalogView.empty();

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) =>
      const Stream<ProductTopicFrame>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused cancel transport: ${invocation.memberName}',
  );
}

/// canonical 安装快照：指定 operation 与阶段。
AcpInstallSnapshotView _installSnapshot(
  String operationId, {
  required int revision,
}) => AcpInstallSnapshotView(
  revision: revision,
  updatedAt: revision,
  installations: [
    AcpInstallEntryView(
      provider: AcpProviderView.antigravity,
      state: AcpDownloadingState(
        operationId: operationId,
        release: _release,
        progress: const AcpInstallProgressView(completedBytes: 1),
        retryCount: 0,
      ),
    ),
  ],
);

/// 每次成功回执的 canonical 快照形状（解析中，只是给出 operation 身份）。
class AcpSnapshotIntent {
  const AcpSnapshotIntent();

  AcpInstallSnapshotView snapshot(String operationId) => AcpInstallSnapshotView(
    revision: 1,
    updatedAt: 1,
    installations: [
      AcpInstallEntryView(
        provider: AcpProviderView.antigravity,
        state: AcpResolvingState(operationId: operationId),
      ),
    ],
  );
}

void main() {
  test('a new draft exposes the template supported version, never a client version', () {
    final automatic = AcpAccountDraft.create(
      template: _template(),
      accountId: 'antigravity',
    );
    expect(automatic.supportedVersion, '1.4.1');
    expect(automatic.canPrepareAutomatically, isTrue);

    final unsupported = AcpAccountDraft.create(
      template: _template(automatic: false),
      accountId: 'antigravity',
    );
    expect(unsupported.canPrepareAutomatically, isFalse);
  });

  test('the save intent only carries identity and display name', () {
    final draft = AcpAccountDraft.create(
      template: _template(),
      accountId: 'antigravity',
    ).copyWith(name: '  Work  ');
    final update = draft.toUpdate();
    expect(update.accountId, 'antigravity');
    expect(update.name, 'Work');
    expect(update.provider, AcpProviderView.antigravity);
    // 空白显示名回落到模板名，不提交空名称。
    expect(draft.copyWith(name: '   ').toUpdate().name, 'Antigravity');
  });

  test(
    'an edit draft only renames: no prepare binding, revision preserved',
    () {
      const account = AcpAccountSettingsView(
        accountId: 'antigravity',
        name: 'Work',
        provider: AcpProviderView.antigravity,
        connectionRevision: 4,
      );
      final draft = AcpAccountDraft.edit(account: account);
      expect(draft.isCreate, isFalse);
      expect(draft.connectionRevision, 4);
      expect(draft.intent.operationId, isNull);
      final update = draft.copyWith(name: 'Renamed').toUpdate();
      expect(update.accountId, 'antigravity');
      expect(update.name, 'Renamed');
    },
  );

  test('a claim binds the ready result, a fresh draft does not inherit it', () {
    final draft = AcpAccountDraft.create(
      template: _template(),
      accountId: 'antigravity',
    ).claimOperation('op-1');
    final ready = AcpInstallReadyState(operationId: 'op-1', server: _prepared);
    expect(
      draft.intent.resolve(ready, provider: AcpProviderView.antigravity),
      isNotNull,
    );

    // 另开草稿（新 formId）不继承旧认领：认领是显式的表单事实。
    final fresh = AcpAccountDraft.create(
      template: _template(),
      accountId: 'antigravity',
    );
    expect(fresh.intent.operationId, isNull);
    expect(
      fresh.intent.resolve(ready, provider: AcpProviderView.antigravity),
      isNull,
    );
  });

  test('a ready result from another operation needs an explicit claim', () {
    final draft = AcpAccountDraft.create(
      template: _template(),
      accountId: 'antigravity',
    ).claimOperation('op-mine');
    final other = AcpInstallReadyState(
      operationId: 'op-other',
      server: _prepared,
    );
    expect(
      draft.intent.availableElsewhere(
        other,
        provider: AcpProviderView.antigravity,
      ),
      isNotNull,
    );
    final claimed = draft.claimOperation('op-other');
    expect(
      claimed.intent.resolve(other, provider: AcpProviderView.antigravity),
      isNotNull,
    );
  });

  test(
    'the coordinator continues only the draft that is still current',
    () async {
      final transport = _StartTransport();
      final client = AnyworkClient(transport: transport, clientId: 'acp-draft');
      addTearDown(client.close);
      final coordinator = AcpPreparationCoordinator(
        commands: client.acpInstallCommands,
      );

      // 同一草稿：成功回执认领它自己的 operation。
      AcpAccountDraft? current = AcpAccountDraft.create(
        template: _template(),
        accountId: 'antigravity',
      );
      final first = coordinator.prepare(
        draft: current,
        currentDraft: () => current,
      );
      expect(coordinator.isPending, isTrue);
      // 在途时第二次请求不产生新的 start（不重叠）。
      expect(
        await coordinator.prepare(draft: current, currentDraft: () => current),
        isNull,
      );
      expect(transport.startCalls, 1);
      await transport.waitStarts(1);
      transport.succeed(0, const AcpSnapshotIntent(), operationId: 'op-1');
      final outcome = await first;
      expect(outcome?.stale, isFalse);
      expect(outcome?.claimed?.intent.operationId, 'op-1');
      expect(coordinator.isPending, isFalse);

      // 用户重开表单（新 formId）：迟到的成功回执不再匹配旧草稿。
      current = AcpAccountDraft.create(
        template: _template(),
        accountId: 'antigravity',
      );
      final second = coordinator.prepare(
        draft: current,
        currentDraft: () => current,
      );
      await transport.waitStarts(2);
      current = AcpAccountDraft.create(
        template: _template(),
        accountId: 'antigravity',
      );
      transport.succeed(1, const AcpSnapshotIntent(), operationId: 'op-2');
      final stale = await second;
      expect(stale?.stale, isTrue);
      expect(stale?.claimed, isNull);
      expect(stale?.error, isNull);
      expect(current.intent.operationId, isNull);

      // 另建同 account/provider/source 的新草稿（不同表单实例）也不认领。
      final fresh = AcpAccountDraft.create(
        template: _template(),
        accountId: 'antigravity',
      );
      current = fresh;
      final third = coordinator.prepare(
        draft: fresh,
        currentDraft: () => current,
      );
      await transport.waitStarts(3);
      current = AcpAccountDraft.create(
        template: _template(),
        accountId: 'antigravity',
      );
      transport.succeed(2, const AcpSnapshotIntent(), operationId: 'op-3');
      final otherForm = await third;
      expect(otherForm?.stale, isTrue);
      expect(otherForm?.claimed, isNull);
    },
  );

  test('a late failure never writes the new draft error', () async {
    final transport = _StartTransport();
    final client = AnyworkClient(transport: transport, clientId: 'acp-draft');
    addTearDown(client.close);
    final coordinator = AcpPreparationCoordinator(
      commands: client.acpInstallCommands,
    );

    AcpAccountDraft? current = AcpAccountDraft.create(
      template: _template(),
      accountId: 'antigravity',
    );
    final pending = coordinator.prepare(
      draft: current,
      currentDraft: () => current,
    );
    await transport.waitStarts(1);
    // 用户重开表单后命令才失败：错误只属于旧意图。
    current = AcpAccountDraft.create(
      template: _template(),
      accountId: 'antigravity',
    );
    transport.fail(
      0,
      const StudioFailure(
        code: StudioFailureCode.busy,
        message: 'Another preparation is running',
        retryable: false,
        correlationId: 'test',
      ),
    );
    final stale = await pending;
    expect(stale?.stale, isTrue);
    expect(stale?.error, isNull);
    expect(coordinator.isPending, isFalse);

    // 匹配的失败仍然要写回当前草稿。
    current = AcpAccountDraft.create(
      template: _template(),
      accountId: 'antigravity',
    );
    final matching = coordinator.prepare(
      draft: current,
      currentDraft: () => current,
    );
    await transport.waitStarts(2);
    transport.fail(
      1,
      const StudioFailure(
        code: StudioFailureCode.busy,
        message: 'Another preparation is running',
        retryable: false,
        correlationId: 'test',
      ),
    );
    final failure = await matching;
    expect(failure?.stale, isFalse);
    expect(failure?.error, isA<StudioFailure>());
  });

  test('an attempt only claims under its own sequence number', () {
    final draft = AcpAccountDraft.create(
      template: _template(),
      accountId: 'antigravity',
    );
    final attempt = AcpPreparationAttempt.of(draft, attempt: 2);
    final snapshot = const AcpSnapshotIntent().snapshot('op-1');
    // 当前尝试序号不同（例如又发起过一次 start）时不得回填。
    expect(
      claimFromStartReply(
        current: draft,
        attempt: attempt,
        snapshot: snapshot,
        currentAttempt: 3,
      ),
      isNull,
    );
    expect(
      claimFromStartReply(
        current: draft,
        attempt: attempt,
        snapshot: snapshot,
        currentAttempt: 2,
      )?.intent.operationId,
      'op-1',
    );
    expect(
      acceptsStartFailure(current: draft, attempt: attempt, currentAttempt: 3),
      isFalse,
    );
  });

  test('an explicit claim is rejected while a start is in flight', () async {
    final transport = _StartTransport();
    final client = AnyworkClient(transport: transport, clientId: 'acp-claim');
    addTearDown(client.close);
    final coordinator = AcpPreparationCoordinator(
      commands: client.acpInstallCommands,
    );

    AcpAccountDraft? current = AcpAccountDraft.create(
      template: _template(),
      accountId: 'antigravity',
    );
    final starting = coordinator.prepare(
      draft: current,
      currentDraft: () => current,
    );
    await transport.waitStarts(1);

    // 在途期间认领另一操作的 Ready：拒绝，且不改当前草稿、不产生第二个 start。
    expect(
      coordinator.claim(
        draft: current,
        currentDraft: () => current,
        operationId: 'op-old',
      ),
      isNull,
    );
    expect(current.intent.operationId, isNull);
    expect(transport.startCalls, 1);

    // 迟到的 start 回执只认领它自己的 operation。
    transport.succeed(0, const AcpSnapshotIntent(), operationId: 'op-new');
    final outcome = await starting;
    expect(outcome?.claimed?.intent.operationId, 'op-new');

    // 在途结束后，显式认领另一操作的 Ready 是合法动作。
    current = outcome!.claimed!;
    final claimed = coordinator.claim(
      draft: current,
      currentDraft: () => current,
      operationId: 'op-old',
    );
    expect(claimed?.intent.operationId, 'op-old');

    // 已经不是当前表单实例的认领请求同样被拒绝。
    expect(
      coordinator.claim(
        draft: AcpAccountDraft.create(
          template: _template(),
          accountId: 'antigravity',
        ),
        currentDraft: () => current,
        operationId: 'op-other',
      ),
      isNull,
    );
  });

  test('the Driver snapshot exposes the install facts the peer asserts', () {
    final facts = StudioDriverFacts(
      acpAuthLoaded: false,
      acpInstall: StudioDriverAcpInstallFacts(
        loaded: true,
        revision: 0,
        installations: [
          const StudioDriverAcpInstallEntryFacts(
            provider: 'antigravity',
            phase: 'downloading',
            operationId: 'op-9',
            stage: 'download',
            completedBytes: 2048,
            retryCount: 1,
            version: '1.4.1',
            target: 'linux-x86_64',
            archiveUrl: 'https://dl.google.com/agy-extensions/releases/a.zip',
          ),
        ],
      ),
    );
    final json =
        jsonDecode(StudioDriverState.snapshotJson(observed: facts)) as Map;
    final install = (json['settings'] as Map)['acpInstall'] as Map;
    expect(install['loaded'], isTrue);
    expect(install['revision'], 0);
    final entry = (install['installations'] as List).single as Map;
    expect(entry['phase'], 'downloading');
    expect(entry['operationId'], 'op-9');
    expect((entry['progress'] as Map)['completedBytes'], 2048);
    expect((entry['progress'] as Map)['totalBytes'], isNull);
    final release = entry['release'] as Map;
    expect(release['version'], '1.4.1');
    expect(release['target'], 'linux-x86_64');
    expect(
      release['archiveUrl'],
      'https://dl.google.com/agy-extensions/releases/a.zip',
    );
    expect(release['sha256'], isNull);
  });

  test('旧取消挂起时换草稿：迟到失败不污染新表单，旧 finally 不清新 pending', () async {
    final session = AccountDraftCancelSession();
    const provider = AcpProviderView.antigravity;

    final oldCommand = Completer<void>();
    final oldAttempt = session.begin(
      formId: 'form-a',
      provider: provider,
      operationId: 'op-1',
    )!;
    // 完全相同目标（表单+provider+operation）重复点击不再产生第二次取消。
    expect(
      session.begin(formId: 'form-a', provider: provider, operationId: 'op-1'),
      isNull,
    );

    Object? reportedToNewForm;
    final oldFlow = () async {
      try {
        await oldCommand.future;
      } catch (error) {
        if (session.accepts(
          oldAttempt,
          currentFormId: 'form-b',
          currentProvider: provider,
          currentOperationId: 'op-2',
        )) {
          reportedToNewForm = error;
        }
      } finally {
        session.finish(oldAttempt);
      }
    }();

    // 新草稿新 operation：旧在途不禁新取消。
    expect(
      session.isPending(
        formId: 'form-b',
        provider: provider,
        operationId: 'op-2',
      ),
      isFalse,
    );
    final newAttempt = session.begin(
      formId: 'form-b',
      provider: provider,
      operationId: 'op-2',
    )!;

    oldCommand.completeError(StateError('cancel failed late'));
    await oldFlow;

    expect(reportedToNewForm, isNull); // 新表单没有旧错误
    expect(
      session.isPending(
        formId: 'form-b',
        provider: provider,
        operationId: 'op-2',
      ),
      isTrue,
    ); // 旧 finally 没清新尝试
    expect(session.finish(newAttempt), isTrue);
  });

  test('同一表单换了 operation：旧在途不禁新 op 取消，旧失败被过滤', () {
    final session = AccountDraftCancelSession();
    const provider = AcpProviderView.antigravity;
    final attempt = session.begin(
      formId: 'form-c',
      provider: provider,
      operationId: 'op-old',
    )!;

    // 旧 op 已由事件终止、用户显式重试新 op：pending 必须按 operation 判定。
    expect(
      session.isPending(
        formId: 'form-c',
        provider: provider,
        operationId: 'op-new',
      ),
      isFalse,
    );
    final fresh = session.begin(
      formId: 'form-c',
      provider: provider,
      operationId: 'op-new',
    )!;
    expect(fresh.operationId, 'op-new');

    // 旧回执结束不清新尝试；旧失败也不落到新操作上。
    expect(session.finish(attempt), isFalse);
    expect(
      session.accepts(
        attempt,
        currentFormId: 'form-c',
        currentProvider: provider,
        currentOperationId: 'op-new',
      ),
      isFalse,
    );
    // 同一目标（新 op）的失败必须仍能提示。
    expect(
      session.accepts(
        fresh,
        currentFormId: 'form-c',
        currentProvider: provider,
        currentOperationId: 'op-new',
      ),
      isTrue,
    );
    expect(session.finish(fresh), isTrue);
  });

  test('真实 cancel 命令：不同目标可并行取消、同目标 busy、旧回执不回退', () async {
    final transport = _CancelTransport();
    final client = AnyworkClient(transport: transport, clientId: 'acp-cancel');
    addTearDown(() async {
      try {
        await client.close();
      } catch (_) {
        // 测试内已显式关闭；teardown 只兜底。
      }
    });
    final session = AccountDraftCancelSession();
    const provider = AcpProviderView.antigravity;
    final commands = client.acpInstallCommands;

    // 旧 operation 正在下载：canonical 给出可取消目标。
    client.acpInstall.apply(_installSnapshot('op-old', revision: 1));
    final oldAttempt = session.begin(
      formId: 'form-a',
      provider: provider,
      operationId: 'op-old',
    )!;
    final oldCommand = commands.cancel(provider);
    await Future<void>.delayed(Duration.zero);
    // transport 真实收到目标 operation 身份。
    expect(transport.targets, ['op-old']);

    // 同一目标重复取消 → typed busy，且不产生第二条 transport 请求。
    await expectLater(
      commands.cancel(provider),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.busy,
        ),
      ),
    );
    expect(transport.targets, ['op-old']);

    // 旧回执**仍未返回**：canonical 推进到新 op（旧操作由事件终止、用户重试）。
    client.acpInstall.apply(_installSnapshot('op-new', revision: 2));
    expect(
      session.isPending(
        formId: 'form-a',
        provider: provider,
        operationId: 'op-new',
      ),
      isFalse,
    );
    final freshAttempt = session.begin(
      formId: 'form-a',
      provider: provider,
      operationId: 'op-new',
    )!;

    // 立刻并行取消新 op：不先释放旧回执。
    final newCommand = commands.cancel(provider);
    await Future<void>.delayed(Duration.zero);
    expect(transport.targets, ['op-old', 'op-new']);

    // Client 关闭必须等待两个真实 future（seal + join），不丢旧 owner。
    var closed = false;
    final closing = client.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);

    // 旧回执迟到（内容仍是旧 op）。注意：close 之后 `_accept` 会跳过 store.apply，
    // 因此这里**不**作为 revision gate 的证据（该证明见
    // acp_install_client_test 的 topic rev2 / reply rev1 用例）；此处只断言旧回执
    // 收束不改变新 canonical 的可见事实。
    transport.succeed(0, _installSnapshot('op-old', revision: 1));
    await oldCommand;
    expect(client.acpInstall.stateOf(provider).operationId, 'op-new');
    // 旧 finally 不清新在途/新 pending；旧失败也不落新表单。
    expect(session.finish(oldAttempt), isFalse);
    expect(
      session.isPending(
        formId: 'form-a',
        provider: provider,
        operationId: 'op-new',
      ),
      isTrue,
    );
    expect(
      session.accepts(
        oldAttempt,
        currentFormId: 'form-a',
        currentProvider: provider,
        currentOperationId: 'op-new',
      ),
      isFalse,
    );
    transport.succeed(1, _installSnapshot('op-new', revision: 4));
    final newest = await newCommand;
    expect(newest.stateOf(provider).operationId, 'op-new');
    expect(client.acpInstall.stateOf(provider).operationId, 'op-new');
    expect(session.finish(freshAttempt), isTrue);

    await closing;
    expect(closed, isTrue);
  });

  test('预算耗尽导致 begin 失败时不残留取消 key，容量恢复后可重试到 transport', () async {
    final transport = _CancelTransport();
    final budget = ResourceBudget(
      capacities: const {
        ResourceKind.chatHandle: 2,
        ResourceKind.pendingOperation: 1,
        ResourceKind.draft: 64,
        ResourceKind.attachment: 256,
        ResourceKind.observer: 1024,
        ResourceKind.readModel: 256,
      },
    );
    final client = AnyworkClient(
      transport: transport,
      clientId: 'acp-budget',
      budget: budget,
    );
    addTearDown(() async {
      try {
        await client.close();
      } catch (_) {
        // 显式关闭兜底。
      }
    });
    const provider = AcpProviderView.antigravity;
    final commands = client.acpInstallCommands;

    // 唯一 pendingOperation permit 被在途取消占用。
    client.acpInstall.apply(_installSnapshot('op-old', revision: 1));
    final first = commands.cancel(provider);
    await Future<void>.delayed(Duration.zero);
    expect(transport.targets, ['op-old']);

    // 新目标：预算耗尽 → MutationBoard.begin 抛 ResourceBudgetExceeded，
    // 且没有到达 transport。
    client.acpInstall.apply(_installSnapshot('op-new', revision: 2));
    Object? budgetFailure;
    try {
      await commands.cancel(provider);
    } on Object catch (error) {
      budgetFailure = error;
    }
    expect(budgetFailure, isA<ResourceBudgetExceeded>());
    expect(transport.targets, ['op-old']);

    // 释放 permit（第一个取消以 typed 失败收束，permit 随之归还）后，同一目标
    // 重试必须能真正下发：若失败路径残留了完整 key，这里会一直 busy。
    transport.pending[0].completeError(
      const StudioFailure(
        code: StudioFailureCode.busy,
        message: 'transport rejected the first cancel',
        retryable: false,
        correlationId: 'test-cancel',
      ),
    );
    await expectLater(first, throwsA(isA<StudioFailure>()));
    final retry = commands.cancel(provider);
    await Future<void>.delayed(Duration.zero);
    expect(transport.targets, ['op-old', 'op-new']);
    transport.succeed(1, _installSnapshot('op-new', revision: 4));
    final settled = await retry;
    expect(settled.stateOf(provider).operationId, 'op-new');
  });
}
