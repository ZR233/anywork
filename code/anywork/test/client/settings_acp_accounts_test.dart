import 'dart:async';

import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/settings/accounts/connectors/accounts_connector.dart';
import 'package:anywork/src/features/settings/accounts/state/acp_account_save_state.dart';
import 'package:anywork/src/features/settings/accounts/state/acp_account_target.dart';
import 'package:anywork/src/features/settings/accounts/state/acp_command_notice.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_auth_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_save_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork/src/features/settings/state/settings_navigation_state.dart';
import 'package:anywork/src/features/settings/view_models/settings_navigation_view_model.dart';
import 'package:anywork/src/features/settings/widgets/settings_form_field.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/acp_port_fixture.dart';
import 'support/pump_client_future.dart';
import 'support/settings_accounts_fixture.dart';

/// ACP 接入的三个界面编排契约。全部事实来自真实 Repository 与脚本化的 native
/// 边界：本文件既不实现读取合并、CAS、观察 reducer，也不从本地布尔值推断成功。
const _workAccountId = 'acct-work';
const _workConnectionRevision = 2;

const _checkRefusal = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The scripted native boundary declined the connection check',
  retryable: true,
  correlationId: 'settings-acp-check',
);

/// 固定 scope 的一行 ACP 接入：ID/名称是内联文本，连接代次按原值声明。
AcpAccountConfigurationRead _acpRow({
  String accountId = 'antigravity',
  String name = 'Work',
  int connectionRevision = _workConnectionRevision,
}) => AcpAccountConfigurationRead(
  accountId: ReadText.inline(text: accountId),
  name: ReadText.inline(text: name),
  provider: AcpProvider.antigravity,
  connectionRevision: connectionRevision,
);

List<AcpAccountConfigurationRead> _workRows() => [
  _acpRow(accountId: _workAccountId),
];

AcpAccountTemplate _template() => const AcpAccountTemplate(
  provider: AcpProvider.antigravity,
  displayName: 'Antigravity',
  description: 'Managed ACP server',
  iconKey: 'antigravity',
  supportedVersion: '1.4.1',
  installUrl: 'https://example.invalid/install',
  termsUrl: 'https://example.invalid/terms',
  automaticInstall: AcpInstallAvailability.available(target: 'linux-x86_64'),
);

/// 真实 Settings 回执（唯一目标为 settings 资源）+ 本次提交捕获的配置读取目标。
CommitReceipt _acpReceipt(OperationId operationId, int revision) =>
    CommitReceipt(
      operationId: operationId,
      disposition: CommitDisposition.applied,
      targets: [
        ResourceStamp(
          resourceKey: 'settings',
          ownerEpoch: SettingsAccountsFixture.origin.ownerEpoch,
          revision: revision,
        ),
      ],
      effect: EffectPoint.immediate,
      effective: false,
      durable: true,
    );

ConfigurationReadTarget _acpTarget(int revision) => ConfigurationReadTarget(
  origin: SettingsAccountsFixture.origin,
  reference: ConfigurationReadRef(entry: 1, revision: revision),
);

/// Settings 回执 revision 与材料 revision 是两件事：回执证明写入水位，材料只
/// 证明本次提交捕获的配置读取目标。
AcpAccountCommandReply _acpReply(
  OperationId operationId, {
  required int receiptRevision,
  required ConfigurationReadTarget material,
}) => AcpAccountCommandReply(
  receipt: _acpReceipt(operationId, receiptRevision),
  configuration: material,
);

typedef _AcpEditorScene = ({
  SettingsAccountsFixture fixture,
  AcpPortFixture acp,
  ProviderContainer container,
  ScriptedAcpInstallFeed installFeed,
});

const _renamedAccount = 'Work renamed';

/// 目录读取的真实失败：code/correlationId 与“身份不可观察”必须可区分。
const _directoryReadFailure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The ACP account directory is unavailable',
  retryable: true,
  correlationId: 'acp-directory-read',
);

List<AcpAccountConfigurationRead> _savedRows({required String name}) => [
  _acpRow(accountId: AcpProvider.antigravity.name, name: name),
];

/// 完成一次真实保存并结算配置写入；连接检查尚未受理。
Future<RecordedAcpCall<UpdateAcpAccountRequest>> _settleCreateSave(
  WidgetTester tester,
  _AcpEditorScene scene, {
  required String name,
}) async {
  final fixture = scene.fixture;
  await tester.enterText(find.byKey(StudioDriverKeys.acpAccountName), name);
  await tester.pump();
  await tester.tap(find.byKey(StudioDriverKeys.accountSave));
  await tester.pump();
  final saved = await pumpClientFuture(
    tester,
    fixture.configurationPort.acpSaved(0),
    'acp account save',
  );
  // 提交捕获的配置目标使用独立材料版本（9），与 Settings 回执水位（2）不同。
  final submitted = fixture.configurationPort.declareAcpMaterial(
    revision: 9,
    rows: _savedRows(name: name),
  );
  saved.native.accept(
    _acpReply(
      saved.request.operationId,
      receiptRevision: 2,
      material: submitted,
    ),
  );
  // 写入回执捕获的配置目标由 Repository 自己消费：先用原目标读取行集。
  final consumed = await pumpClientFuture(
    tester,
    fixture.configurationPort.acpPage(0),
    'write target rows',
  );
  consumed.complete();
  // 水位推进后目录刷新/检查解析绑定新的原准入（material revision 2）：
  // 先声明不可变材料，再推进 Settings 事件；读不靠时序补空 pin。
  fixture.configurationPort.declareAcpMaterial(
    revision: 2,
    rows: _savedRows(name: name),
  );
  await pumpClientFuture(
    tester,
    fixture.configurationPort.base.publishSettings(2),
    'settings revision',
  );
  return saved;
}

/// 应答一次目录读取（给出已保存账号）并提交第 [checkIndex] 次连接检查。
Future<ScriptedAcpCommand<AcpAuthStartRequest, AcpAuthCommandReply>>
_admitCheck(
  WidgetTester tester,
  _AcpEditorScene scene, {
  required int readIndex,
  required int checkIndex,
  required String name,
}) async {
  final resolution = await pumpClientFuture(
    tester,
    scene.fixture.configurationPort.acpPage(readIndex),
    'connection resolution $readIndex',
  );
  resolution.complete();
  return pumpClientFuture(
    tester,
    scene.acp.port.authStarted(checkIndex),
    'connection check $checkIndex',
  );
}

/// 真实装配下打开 ACP 新建表单并准备到 Ready。
///
/// 挂载的是生产 `AccountsConnector`（含真实 `AcpAccountEditorConnector` 与视图）；
/// 只有 native ACP 端口的帧与命令回执由测试声明，导航、VMs、Repository 都是生产实现。
Future<_AcpEditorScene> _openPreparedCreateEditor(WidgetTester tester) async {
  final fixture = SettingsAccountsFixture();
  // 该场景还没有已保存的 ACP 接入：声明真实空目录（`rows: const []` 就是
  // “已知为空”），并委托 base 提供原生账号实体。声明必须早于任何 Settings
  // 读取：读取拿不到材料时不得回退成伪空目录。
  fixture.configurationPort.declareAcpMaterial(
    revision: 1,
    rows: const [],
    delegateBase: true,
  );
  await fixture.establish();
  final acp = AcpPortFixture();
  final container = ProviderContainer(
    overrides: [
      configurationRepositoryProvider.overrideWithValue(fixture.configuration),
      modelsRepositoryProvider.overrideWithValue(fixture.models),
      accountUsageRepositoryProvider.overrideWithValue(fixture.usage),
      acpAuthRepositoryProvider.overrideWithValue(acp.auth),
      acpInstallRepositoryProvider.overrideWithValue(acp.install),
    ],
  );
  addTearDown(() async {
    container.dispose();
    // 关闭同样要推进 real/fake 两个队列：在 widget 测试的 fake-async 区间里直接
    // await 关闭 future 不会给 pending 的 fake 任务任何一帧，会一直等下去。
    final fixtureReport = await pumpClientFuture(
      tester,
      fixture.close(),
      'ACP fixture close',
    );
    expect(fixtureReport.unresolved, isEmpty);
    final reports = await pumpClientFuture(
      tester,
      Future.wait([acp.auth.close(), acp.install.close()]),
      'ACP auth/install close',
    );
    expect(reports.expand((report) => report.unresolved), isEmpty);
    expect(fixture.budget.usage, isEmpty);
    expect(acp.budget.usage, isEmpty);
  });

  // 真实导航进入设置页账号 Tab：ACP 观察租约只在页面可见时取得。
  await pumpClientFuture(
    tester,
    container.read(settingsNavigationViewModelProvider.future),
    'settings navigation',
  );
  container
      .read(settingsNavigationViewModelProvider.notifier)
      .enter(SettingsTab.accounts);

  // 目录与 ACP 模板目录是两条独立的有界读取；pin 级空目录（`total == 0`，
  // 不发生分页读取）已在 establish 之前声明。
  final accountsReady = container.read(accountsViewModelProvider.future);
  await pumpClientUntil(
    tester,
    () => acp.port.catalogReads.isNotEmpty,
    'acp catalog read',
  );
  acp.port.answerCatalogRead(0, AcpAccountCatalog(templates: [_template()]));
  await pumpClientFuture(tester, accountsReady, 'accounts view model');
  // 账号面板可见时会取得自己的 `acpAuth` 租约：给出真实基线让这次同步完成。
  final accountsAuthFeed = await pumpClientFuture(
    tester,
    acp.port.authFeedOpened(0),
    'accounts acpAuth feed',
  );
  await pumpClientFuture(
    tester,
    accountsAuthFeed.publishBaseline(
      acpAuthSnapshot(revision: 1, state: const AcpAuthState.unchecked()),
    ),
    'accounts acpAuth baseline',
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        // 生产主题唯一装配入口：StudioSemanticColors 等 extension 由它提供；
        // 缺了它时 StudioNotice/StudioPill 的 tone 取色会在真实 connector 上崩。
        theme: pureStudioTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AccountsConnector()),
      ),
    ),
  );
  await tester.pump();

  final accounts = container.read(accountsViewModelProvider.notifier);
  unawaited(accounts.startCreate(AccountTemplateChoice.acp(_template())));
  await tester.pump();
  final create = AcpAccountCreateTarget(
    accountId: AcpProvider.antigravity.name,
    template: _template(),
  );
  expect(
    container.read(accountsViewModelProvider).requireValue.acpEditor,
    create,
  );
  await pumpClientFuture(
    tester,
    container.read(acpAccountEditorViewModelProvider(create).future),
    'acp editor form',
  );
  // 表单可见后才取安装观察租约。
  final installFeed = await pumpClientFuture(
    tester,
    acp.port.installFeedOpened(0),
    'acp install feed',
  );
  await pumpClientFuture(
    tester,
    installFeed.publishBaseline(
      acpInstallSnapshot(revision: 1, state: const AcpInstallState.idle()),
    ),
    'acp install baseline',
  );
  await tester.pump();

  // 真实“准备服务器”主操作：受理回执认领 operation，canonical 随后给出 Ready。
  await tester.tap(find.byKey(StudioDriverKeys.acpInstallPrepare));
  await tester.pump();
  final start = await pumpClientFuture(
    tester,
    acp.port.installStarted(0),
    'install start admission',
  );
  final prepared = acpInstallSnapshot(
    revision: 2,
    state: AcpInstallState.resolving(
      operationId: start.request.operationId.value,
    ),
  );
  start.accept(
    AcpInstallCommandReply(
      receipt: acpInstallReceipt(start.request.operationId, revision: 2),
      snapshot: prepared,
    ),
  );
  final ready = acpInstallSnapshot(
    revision: 2,
    state: AcpInstallState.ready(
      operationId: start.request.operationId.value,
      server: AcpInstalledServer(
        installationId: 'install-1',
        release: acpRelease(),
        program: '/managed/agy-acp-server',
        readyAt: 2,
        reused: false,
      ),
    ),
  );
  await pumpClientFuture(
    tester,
    installFeed.publishChanged(ready, baseRevision: 1),
    'install ready',
  );
  await pumpClientUntil(
    tester,
    () => find.byKey(StudioDriverKeys.accountSave).evaluate().isNotEmpty,
    'save admitted after preparation',
  );
  return (
    fixture: fixture,
    acp: acp,
    container: container,
    installFeed: installFeed,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('删除结算后重新读取 ACP 目录，列表与选择都不再显示该接入', () async {
    final fixture = SettingsAccountsFixture();
    // 该用例初始有一条已保存接入：pin 声明 1 行，分页读取是显式控制点。
    // 与非 ACP 字段共用同一目标，因此显式委托 base 的原生账号实体。
    fixture.configurationPort.declareAcpMaterial(
      revision: 1,
      rows: _workRows(),
      delegateBase: true,
    );
    await fixture.establish();
    final acp = AcpPortFixture();
    final container = ProviderContainer(
      overrides: [
        configurationRepositoryProvider.overrideWithValue(
          fixture.configuration,
        ),
        modelsRepositoryProvider.overrideWithValue(fixture.models),
        accountUsageRepositoryProvider.overrideWithValue(fixture.usage),
        acpAuthRepositoryProvider.overrideWithValue(acp.auth),
        acpInstallRepositoryProvider.overrideWithValue(acp.install),
      ],
    );
    addTearDown(() async {
      container.dispose();
      expect((await fixture.close()).unresolved, isEmpty);
      final reports = await Future.wait([
        acp.auth.close(),
        acp.install.close(),
      ]);
      expect(reports.expand((report) => report.unresolved), isEmpty);
      expect(fixture.budget.usage, isEmpty);
      expect(acp.budget.usage, isEmpty);
    });

    final list = container.read(accountsViewModelProvider.notifier);
    final ready = container.read(accountsViewModelProvider.future);
    final directoryPage = await fixture.configurationPort.acpPage(0);
    directoryPage.complete();
    // 目录与 ACP 模板目录是两条独立的有界读取。
    await pumpEventQueue();
    expect(acp.port.catalogReads, hasLength(1));
    acp.port.answerCatalogRead(0, AcpAccountCatalog.empty);
    await ready;

    final initial = container.read(accountsViewModelProvider).requireValue;
    expect(
      initial.directory!.acpEntries.single.account.accountId,
      _workAccountId,
    );
    list.selectAcp(_workAccountId);
    expect(
      container
          .read(accountsViewModelProvider)
          .requireValue
          .selectedAcpAccountId,
      _workAccountId,
    );

    // 操作前基线恰好两次当前 Settings 水位（revision 1）的独立只读 query：
    // establish 预热读取 + 账号页目录读取（同一缓存 pin 的第二次 header）。
    // 数量必须精确，不能用 everyElement/isPositive 把更多读取吞进基线。
    expect(fixture.configurationPort.acpHeaderTargets, [
      _acpTarget(1),
      _acpTarget(1),
    ], reason: '删除前只读取两次当前水位的 canonical 目录');
    final before = fixture.configurationPort.acpHeaderTargets.length;

    final removal = list.removeAcp(_workAccountId);
    final call = await fixture.configurationPort.acpRemoved(0);
    expect(call.request.accountId, _workAccountId);
    final submitted = fixture.configurationPort.declareAcpMaterial(
      revision: 9,
      rows: _workRows(),
    );
    call.native.accept(
      _acpReply(
        call.request.operationId,
        receiptRevision: 2,
        material: submitted,
      ),
    );
    // 写入回执捕获的配置目标由 Repository 自己消费（原调用关闭前完成整页读取）。
    final consumed = await fixture.configurationPort.acpPage(1);
    consumed.complete();
    // 只有结算成功才刷新：先声明新水位的不可变材料（“删除后目录为空”），
    // 再推进 Settings 事件；读不得等事件之后才补空 pin。
    fixture.configurationPort.declareAcpMaterial(revision: 2, rows: const []);
    await fixture.configurationPort.base.publishSettings(2);
    await removal;

    expect(fixture.configurationPort.acpHeaderTargets.skip(before).toList(), [
      _acpTarget(9),
      _acpTarget(2),
    ], reason: '删除结算后必须按提交目标与新水位各重读一次 canonical 目录');
    expect(
      fixture.configurationPort.acpPageCalls,
      hasLength(2),
      reason: '初始 1 页 + 提交目标 1 页；空刷新不分页',
    );
    final settled = container.read(accountsViewModelProvider).requireValue;
    expect(settled.directory!.acpEntries, isEmpty);
    expect(settled.selectedAcpAccountId, isNull);
    expect(
      settled.acpRemovals.containsKey(_workAccountId),
      isFalse,
      reason: '结算成功后不再保留在途删除意图',
    );

    // 负向信号：revision 2 是 ACP-only 材料（没有声明 delegateBase）。真实读取
    // 契约在这里必须拒绝原生账号能力，而不是悄悄把共享 base 的账号数/ID 交给
    // 调用方——防的是“漏写 delegateBase 也能通过”。
    final acpOnly = await fixture.configurationPort.openConfigurationRead(
      _acpTarget(2).reference,
      origin: SettingsAccountsFixture.origin,
    );
    addTearDown(acpOnly.close);
    expect(
      (await acpOnly.header()).accounts.total,
      0,
      reason: 'ACP-only 材料只声明自己的 ACP 列表，不继承 base 的账号数',
    );
    await expectLater(
      acpOnly.lookupAccount('account-0'),
      throwsA(isA<UnsupportedError>()),
      reason: '未委托的 pin 不得回答原生账号身份',
    );
    // `entries()` 的实现是 `=> _delegate.entries(...)`：没有委托时在返回 Future 之前
    // 就同步 throw。用闭包捕获，既覆盖同步 throw，也兼容将来改成先返回 Future 再失败。
    await expectLater(
      () => acpOnly.entries(),
      throwsA(isA<UnsupportedError>()),
      reason: '未委托的 pin 不得读取原生账号条目',
    );
  });

  test('隐藏的 ACP 节点不建立任何 feed demand，可见后才各开一次', () async {
    final acp = AcpPortFixture();
    final container = ProviderContainer(
      overrides: [
        acpAuthRepositoryProvider.overrideWithValue(acp.auth),
        acpInstallRepositoryProvider.overrideWithValue(acp.install),
      ],
    );
    addTearDown(() async {
      container.dispose();
      final reports = await Future.wait([
        acp.auth.close(),
        acp.install.close(),
      ]);
      expect(reports.expand((report) => report.unresolved), isEmpty);
      expect(acp.budget.usage, isEmpty);
    });

    const target = AcpAccountTarget(
      accountId: _workAccountId,
      connectionRevision: _workConnectionRevision,
      provider: AcpProvider.antigravity,
    );
    final create = AcpAccountCreateTarget(
      accountId: 'acct-new',
      template: _template(),
    );
    final authProvider = acpAccountAuthViewModelProvider(target);
    final editorProvider = acpAccountEditorViewModelProvider(create);
    final authFuture = container.read(authProvider.future);
    final editorFuture = container.read(editorProvider.future);
    final authVm = container.read(authProvider.notifier);
    final editorVm = container.read(editorProvider.notifier);
    await authFuture;
    await editorFuture;

    // 已挂载但不可见：只有未加载状态，没有订阅、没有 synchronize。
    expect(acp.port.authFeeds, isEmpty);
    expect(acp.port.installFeeds, isEmpty);
    final hiddenAuth = container.read(authProvider).requireValue;
    final hiddenEditor = container.read(editorProvider).requireValue;
    expect(hiddenAuth.visible, isFalse);
    expect(hiddenAuth.auth, const AcpAuthState.unchecked());
    expect(hiddenEditor.visible, isFalse);
    expect(hiddenEditor.install, const AcpInstallState.idle());

    authVm.setVisible(true);
    editorVm.setVisible(true);
    final authFeed = await acp.port.authFeedOpened(0);
    final installFeed = await acp.port.installFeedOpened(0);
    expect(acp.port.authFeeds, hasLength(1));
    expect(acp.port.installFeeds, hasLength(1));
    await authFeed.publishBaseline(
      acpAuthSnapshot(revision: 1, state: const AcpAuthState.unchecked()),
    );
    await installFeed.publishBaseline(
      acpInstallSnapshot(revision: 1, state: const AcpInstallState.idle()),
    );
    expect(container.read(authProvider).requireValue.visible, isTrue);
    expect(container.read(editorProvider).requireValue.visible, isTrue);

    // 再次隐藏只释放自己的租约，不取消、不重开、也不产生第二个 feed。
    authVm.setVisible(false);
    editorVm.setVisible(false);
    expect(container.read(authProvider).requireValue.visible, isFalse);
    expect(container.read(editorProvider).requireValue.visible, isFalse);
    expect(acp.port.authFeeds, hasLength(1));
    expect(acp.port.installFeeds, hasLength(1));
  });

  test('连接检查失败保留草稿且不重放保存，重试只走第二次检查', () async {
    final fixture = SettingsAccountsFixture();
    // 已保存的接入在真实 Settings 目标上声明；native 账号实体仍由 base 回答。
    fixture.configurationPort.declareAcpMaterial(
      revision: 1,
      rows: _workRows(),
      delegateBase: true,
    );
    await fixture.establish();
    final acp = AcpPortFixture();
    final container = ProviderContainer(
      overrides: [
        configurationRepositoryProvider.overrideWithValue(
          fixture.configuration,
        ),
        acpAuthRepositoryProvider.overrideWithValue(acp.auth),
      ],
    );
    addTearDown(() async {
      container.dispose();
      expect((await fixture.close()).unresolved, isEmpty);
      final reports = await Future.wait([
        acp.auth.close(),
        acp.install.close(),
      ]);
      expect(reports.expand((report) => report.unresolved), isEmpty);
      expect(fixture.budget.usage, isEmpty);
      expect(acp.budget.usage, isEmpty);
    });

    // 连接事实来自 canonical 观察：先声明一次基线，之后按真实水位推进。
    final synchronizing = acp.auth.synchronize();
    final authFeed = await acp.port.authFeedOpened(0);
    await authFeed.publishBaseline(
      acpAuthSnapshot(revision: 1, state: const AcpAuthState.unchecked()),
    );
    await synchronizing;

    final saveProvider = acpAccountSaveViewModelProvider(_workAccountId);
    final saveFuture = container.read(saveProvider.future);
    final saveVm = container.read(saveProvider.notifier);
    await saveFuture;

    // 固定 scope 的材料：该用例只关心写入目标的提交捕获材料（revision 9）。
    final submitted = fixture.configurationPort.declareAcpMaterial(
      revision: 9,
      rows: [_acpRow(accountId: _workAccountId)],
    );

    final saving = saveVm.save(
      const AcpAccountUpdate(
        accountId: _workAccountId,
        name: 'Work',
        provider: AcpProvider.antigravity,
      ),
      create: true,
    );
    final saveCall = await fixture.configurationPort.acpSaved(0);
    saveCall.native.accept(
      _acpReply(
        saveCall.request.operationId,
        receiptRevision: 2,
        material: submitted,
      ),
    );
    // 原调用捕获的配置目标由 Repository 消费：先完整读取该目标的 ACP 行集。
    final consumed = await fixture.configurationPort.acpPage(0);
    consumed.complete();
    // 先声明新水位的不可变材料，再推进 Settings 事件：读不得等时序补空 pin。
    fixture.configurationPort.declareAcpMaterial(
      revision: 2,
      rows: [_acpRow(accountId: _workAccountId)],
    );
    await fixture.configurationPort.base.publishSettings(2);

    // 保存结算后解析连接代次并提交检查；检查被原生边界拒绝。
    final resolution = await fixture.configurationPort.acpPage(1);
    resolution.complete();
    final check = await acp.port.authStarted(0);
    expect(check.request.accountId, _workAccountId);
    expect(check.request.expectedConnectionRevision, _workConnectionRevision);
    check.reject(const CommandDispatchFailure.rejected(failure: _checkRefusal));

    final outcome = await saving;
    expect(outcome.saved, isTrue, reason: '配置写入已结算');
    expect(outcome.checkFailure, _checkRefusal);
    expect(acpSaveCompletesEditor(outcome), isFalse, reason: '连接未完成时不得关闭表单');
    expect(acpSaveKeepsDraft(outcome), isTrue);
    expect(fixture.configurationPort.acpSaves, hasLength(1));
    final afterFailure = container.read(saveProvider).requireValue;
    expect(afterFailure.saved, isTrue);
    expect(afterFailure.checkError, _checkRefusal);
    expect(afterFailure.busy, isFalse);
    expect(afterFailure.checkAction!.error, _checkRefusal);

    // 重试只重新解析目录并检查：绝不重放保存。
    final retrying = saveVm.retryCheck();
    final reressolution = await fixture.configurationPort.acpPage(2);
    reressolution.complete();
    final secondCheck = await acp.port.authStarted(1);
    expect(secondCheck.request.operationId, isNot(check.request.operationId));
    secondCheck.reject(
      const CommandDispatchFailure.rejected(failure: _checkRefusal),
    );
    final retried = await retrying;
    expect(retried.saved, isTrue);
    expect(retried.checkFailure, _checkRefusal);
    expect(
      fixture.configurationPort.acpSaves,
      hasLength(1),
      reason: 'retryCheck 不得提交第二次保存',
    );
    expect(acp.port.authStarts, hasLength(2), reason: '重试第二次检查走新的操作身份');
    final afterRetry = container.read(saveProvider).requireValue;
    expect(afterRetry.checkAction!.operation, isNotNull);
    expect(afterRetry.saved, isTrue);
    expect(afterRetry.checkError, _checkRefusal);
  });

  // ---------------------------------------------------------------------------
  // 真实 Connector/widget 层回归。
  //
  // 上面的编排用例只到 save VM；连接器是否真的保留表单、保留用户输入的名称、
  // 不切换导航，以及“重试”是否只多一次检查，必须在真实 `AccountsConnector` →
  // `AcpAccountEditorConnector` → 视图上证明。这里只脚本化 native 端口，VMs、
  // Repository、导航与视图全部是生产实现。
  // ---------------------------------------------------------------------------

  testWidgets('连接检查失败时表单仍挂载、名称与已保存事实保留，重试只再检查一次', (WidgetTester tester) async {
    final scene = await _openPreparedCreateEditor(tester);
    final fixture = scene.fixture;
    final acp = scene.acp;
    final container = scene.container;
    const saveId = 'antigravity';
    final saveProvider = acpAccountSaveViewModelProvider(saveId);

    final saved = await _settleCreateSave(tester, scene, name: _renamedAccount);
    expect(saved.request.account.accountId, saveId);
    expect(saved.request.account.name, _renamedAccount);
    expect(
      tester
          .widget<SettingsFormField>(
            find.byKey(StudioDriverKeys.acpAccountName),
          )
          .value,
      _renamedAccount,
      reason: '保存前名称输入是用户的真实输入',
    );
    // 保存结算后重新解析连接代次，再提交第一次连接检查。
    final firstCheck = await _admitCheck(
      tester,
      scene,
      readIndex: 1,
      checkIndex: 0,
      name: _renamedAccount,
    );
    expect(firstCheck.request.accountId, saveId);
    expect(
      firstCheck.request.expectedConnectionRevision,
      _workConnectionRevision,
    );
    firstCheck.reject(
      const CommandDispatchFailure.rejected(failure: _checkRefusal),
    );
    await pumpClientUntil(
      tester,
      () => container.read(saveProvider).requireValue.checkError != null,
      'check failure settled',
    );
    await tester.pump();

    // 表单仍挂载：名称输入框还在，且保留用户实际输入。
    final nameField = find.byKey(StudioDriverKeys.acpAccountName);
    expect(nameField, findsOneWidget, reason: '连接失败不得关闭编辑器');
    expect(
      tester.widget<SettingsFormField>(nameField).value,
      _renamedAccount,
      reason: '草稿名称为用户的真实输入，不是模板默认名',
    );
    // 导航未切换：仍在编辑态，没有进入详情，也没有“已保存但未连接”的通知路径。
    final accounts = container.read(accountsViewModelProvider).requireValue;
    expect(accounts.acpEditor, isNotNull);
    expect(accounts.showDetails, isFalse);
    expect(accounts.acpNotices, isEmpty);
    // 已保存事实保留，且保存只提交过一次。
    expect(container.read(saveProvider).requireValue.saved, isTrue);
    expect(fixture.configurationPort.acpSaves, hasLength(1));
    // 保存入口已让位给“重新检查”，不是可重复点击的保存。
    expect(find.byKey(StudioDriverKeys.accountSave), findsNothing);
    final retry = find.byKey(StudioDriverKeys.acpAccountCheck);
    expect(retry, findsOneWidget);
    expect(
      tester.widget<FilledButton>(retry).onPressed,
      isNotNull,
      reason: '连接失败后必须可以显式重试连接',
    );

    // 重试只多一次检查，绝不重放保存。
    await tester.tap(retry);
    await tester.pump();
    final secondCheck = await _admitCheck(
      tester,
      scene,
      readIndex: 2,
      checkIndex: 1,
      name: _renamedAccount,
    );
    expect(
      secondCheck.request.operationId,
      isNot(firstCheck.request.operationId),
      reason: '重试走新的操作身份',
    );
    secondCheck.reject(
      const CommandDispatchFailure.rejected(failure: _checkRefusal),
    );
    await pumpClientUntil(
      tester,
      () => container.read(saveProvider).requireValue.busy == false,
      'retry settled',
    );
    await tester.pump();

    expect(
      fixture.configurationPort.acpSaves,
      hasLength(1),
      reason: 'retryCheck 不得提交第二次保存',
    );
    expect(acp.port.authStarts, hasLength(2));
    expect(find.byKey(StudioDriverKeys.acpAccountName), findsOneWidget);
    expect(
      tester
          .widget<SettingsFormField>(
            find.byKey(StudioDriverKeys.acpAccountName),
          )
          .value,
      _renamedAccount,
    );
  });

  testWidgets('首次连接检查在途时重试入口不可点击', (WidgetTester tester) async {
    final scene = await _openPreparedCreateEditor(tester);
    final fixture = scene.fixture;
    final acp = scene.acp;
    const saveId = 'antigravity';

    await _settleCreateSave(tester, scene, name: _renamedAccount);
    final firstCheck = await _admitCheck(
      tester,
      scene,
      readIndex: 1,
      checkIndex: 0,
      name: _renamedAccount,
    );
    await tester.pump();

    // 首 check 仍在途：视图必须区分 checking 与 failed，重试入口此时不可点击。
    final retry = find.byKey(StudioDriverKeys.acpAccountCheck);
    expect(retry, findsOneWidget);
    expect(
      tester.widget<FilledButton>(retry).onPressed,
      isNull,
      reason: '连接检查尚未结算，重试入口不得提前可用',
    );
    expect(find.byKey(StudioDriverKeys.accountSave), findsNothing);
    expect(fixture.configurationPort.acpSaves, hasLength(1));
    expect(acp.port.authStarts, hasLength(1));
    expect(
      scene.container
          .read(acpAccountSaveViewModelProvider(saveId))
          .requireValue
          .saved,
      isTrue,
      reason: '保存事实在检查在途时已成立，不因重试门控而丢失',
    );

    // 收束在途检查，避免留下未结算命令。
    firstCheck.reject(
      const CommandDispatchFailure.rejected(failure: _checkRefusal),
    );
    await pumpClientUntil(
      tester,
      () =>
          scene.container
              .read(acpAccountSaveViewModelProvider(saveId))
              .requireValue
              .busy ==
          false,
      'check settled',
    );
  });

  testWidgets('保存结算后连接身份尚未解析时处于检查中，重试不可点且不显示已连接', (WidgetTester tester) async {
    final scene = await _openPreparedCreateEditor(tester);
    final fixture = scene.fixture;
    final container = scene.container;
    const saveId = 'antigravity';
    final saveProvider = acpAccountSaveViewModelProvider(saveId);

    await _settleCreateSave(tester, scene, name: _renamedAccount);
    // 目录读取被刻意挂起：连接代次尚未解析，第二次命令也还没受理。
    await pumpClientUntil(
      tester,
      () => fixture.configurationPort.acpPageCalls.length >= 2,
      'held directory read',
    );
    await tester.pump();
    expect(
      fixture.configurationPort.acpPageCalls,
      hasLength(2),
      reason: '目录读取已在分页点挂起（身份尚未解析）',
    );

    final held = container.read(saveProvider).requireValue;
    expect(held.saved, isTrue, reason: '配置写入已结算');
    // 连接编排（解析连接身份→提交检查）仍在进行：保存已提交不代表整个编排结束，
    // 因此只约束公开编排状态 busy，不把 checking 限定为“原生已受理命令”。
    expect(held.busy, isTrue, reason: '解析连接身份期间连接编排仍在进行');
    expect(
      held.phase,
      AcpAccountSavePhase.savedChecking,
      reason: '连接身份尚未解析时不得报告“已连接”',
    );
    expect(fixture.configurationPort.acpSaves, hasLength(1));
    expect(scene.acp.port.authStarts, isEmpty, reason: '身份未解析前不得提交连接检查');

    // 表单仍在：名称与已保存事实保留；重试可见但不可点，保存入口不再出现。
    final nameField = find.byKey(StudioDriverKeys.acpAccountName);
    expect(nameField, findsOneWidget);
    expect(tester.widget<SettingsFormField>(nameField).value, _renamedAccount);
    final retry = find.byKey(StudioDriverKeys.acpAccountCheck);
    expect(retry, findsOneWidget);
    expect(
      tester.widget<FilledButton>(retry).onPressed,
      isNull,
      reason: '检查尚未结算，重试不得提前可用',
    );
    expect(find.byKey(StudioDriverKeys.accountSave), findsNothing);

    // 收束：应答目录 → 受理并拒绝检查，阶段落到可重试的失败。
    final check = await _admitCheck(
      tester,
      scene,
      readIndex: 1,
      checkIndex: 0,
      name: _renamedAccount,
    );
    check.reject(const CommandDispatchFailure.rejected(failure: _checkRefusal));
    await pumpClientUntil(
      tester,
      () => container.read(saveProvider).requireValue.busy == false,
      'check settled',
    );
    await tester.pump();
    expect(
      container.read(saveProvider).requireValue.phase,
      AcpAccountSavePhase.savedCheckFailed,
    );
  });

  testWidgets('重试时目录读取失败或缺少账号都会结算动作并保留真实原因', (WidgetTester tester) async {
    final scene = await _openPreparedCreateEditor(tester);
    final fixture = scene.fixture;
    final container = scene.container;
    const saveId = 'antigravity';
    final saveProvider = acpAccountSaveViewModelProvider(saveId);
    final retry = find.byKey(StudioDriverKeys.acpAccountCheck);

    await _settleCreateSave(tester, scene, name: _renamedAccount);
    final firstCheck = await _admitCheck(
      tester,
      scene,
      readIndex: 1,
      checkIndex: 0,
      name: _renamedAccount,
    );
    firstCheck.reject(
      const CommandDispatchFailure.rejected(failure: _checkRefusal),
    );
    await pumpClientUntil(
      tester,
      () => container.read(saveProvider).requireValue.busy == false,
      'first check failed',
    );

    // 第一次重试：真实目录读取失败，必须结算在途动作并保留原始原因。
    await tester.tap(retry);
    await tester.pump();
    await pumpClientUntil(
      tester,
      () => fixture.configurationPort.acpPageCalls.length >= 3,
      'retry directory read',
    );
    final failedPage = await pumpClientFuture(
      tester,
      fixture.configurationPort.acpPage(2),
      'retry directory page',
    );
    failedPage.fail(_directoryReadFailure);
    await pumpClientUntil(
      tester,
      () => container.read(saveProvider).requireValue.busy == false,
      'retry read failure settled',
    );
    await tester.pump();
    final afterReadFailure = container.read(saveProvider).requireValue;
    expect(
      afterReadFailure.phase,
      AcpAccountSavePhase.savedCheckFailed,
      reason: '读取失败后仍停在“已保存、检查失败可重试”',
    );
    expect(
      afterReadFailure.checkAction?.pending,
      isFalse,
      reason: '读取失败也必须结算在途检查动作，不能留下永久的 checking',
    );
    expect(
      afterReadFailure.checkError?.code,
      StudioFailureCode.unavailable,
      reason: '真实读取失败不得降级成 generic/身份不可观察',
    );
    expect(
      afterReadFailure.checkError?.correlationId,
      _directoryReadFailure.correlationId,
      reason: '原始失败证据必须保留',
    );
    expect(afterReadFailure.saved, isTrue);
    expect(fixture.configurationPort.acpSaves, hasLength(1));
    expect(scene.acp.port.authStarts, hasLength(1), reason: '读取失败不提交第二次检查');
    expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);

    // 第二次重试：新水位声明“目录不再包含该账号” → 连接身份不可观察。
    // 这是新的原准入（material revision 3）：不改写已捕获的 revision 2 材料。
    // 声明必须早于 Settings 事件推进。
    fixture.configurationPort.declareAcpMaterial(revision: 3, rows: const []);
    await fixture.configurationPort.base.publishSettings(3);
    await tester.tap(retry);
    await tester.pump();
    await pumpClientUntil(
      tester,
      () => container.read(saveProvider).requireValue.busy == false,
      'missing identity settled',
    );
    await tester.pump();
    final afterMissing = container.read(saveProvider).requireValue;
    expect(afterMissing.phase, AcpAccountSavePhase.savedCheckFailed);
    expect(
      afterMissing.checkError?.code,
      StudioFailureCode.superseded,
      reason: '缺少连接身份是明确的完成度失败',
    );
    expect(afterMissing.saved, isTrue);
    expect(
      fixture.configurationPort.acpSaves,
      hasLength(1),
      reason: '重试从不重放保存',
    );
    expect(scene.acp.port.authStarts, hasLength(1));
    expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
  });

  testWidgets('已保存但连接未完成时取消进入详情并保留保存事实与真实通知', (WidgetTester tester) async {
    final scene = await _openPreparedCreateEditor(tester);
    final fixture = scene.fixture;
    final container = scene.container;
    const saveId = 'antigravity';
    final saveProvider = acpAccountSaveViewModelProvider(saveId);

    await _settleCreateSave(tester, scene, name: _renamedAccount);
    final firstCheck = await _admitCheck(
      tester,
      scene,
      readIndex: 1,
      checkIndex: 0,
      name: _renamedAccount,
    );
    firstCheck.reject(
      const CommandDispatchFailure.rejected(failure: _checkRefusal),
    );
    await pumpClientUntil(
      tester,
      () => container.read(saveProvider).requireValue.checkError != null,
      'check failed',
    );
    await tester.pump();

    // 原操作保存结果：在取消前从**同一个** owner 读取。该 provider 是 autoDispose，
    // 取消关闭编辑器后会被释放，取消后再 read 拿到的是新的 AsyncLoading owner，
    // 无法用来证明保存事实。
    final savedState = container.read(saveProvider).requireValue;
    expect(savedState.saved, isTrue, reason: '配置写入已结算');
    expect(savedState.checkError, _checkRefusal, reason: '连接检查失败不改写保存事实');

    // 真实取消按钮：已保存时把“已保存但未连接”交回调用方，而不是回滚保存。
    await tester.tap(find.byKey(StudioDriverKeys.accountCancel));
    await tester.pump();
    final refresh = await pumpClientFuture(
      tester,
      fixture.configurationPort.acpPage(2),
      'cancel directory refresh',
    );
    refresh.complete();
    await pumpClientUntil(
      tester,
      () =>
          container.read(accountsViewModelProvider).requireValue.acpEditor ==
          null,
      'editor closed after cancel',
    );
    await tester.pump();

    final accounts = container.read(accountsViewModelProvider).requireValue;
    expect(accounts.acpEditor, isNull, reason: '取消后离开编辑表单');
    expect(accounts.selectedAcpAccountId, saveId);
    expect(accounts.showDetails, isTrue, reason: '进入该接入详情而不是列表');
    final notice = accounts.acpNotices[saveId];
    expect(notice, isNotNull, reason: '“已保存但连接未完成”的通知必须保留');
    expect(notice!.connectIncomplete, isTrue);
    expect(notice.kind, AcpCommandNoticeKind.authentication);
    expect(notice.failure?.code, _checkRefusal.code);
    expect(notice.connectionRevision, _workConnectionRevision);
    expect(notice.accountId, saveId);

    // 取消不是回滚：从取消后重新读取的 canonical 目录证明已保存的接入仍在（身份与
    // 名称都是用户真实的保存值），而不是重新实例化 autoDispose 的 save VM 冒充证据。
    final canonical = accounts.directory!;
    final savedEntry = canonical.acpEntries.single;
    expect(savedEntry.account.accountId, saveId);
    expect(savedEntry.account.name, _renamedAccount, reason: '取消不回滚已保存的名称');
    expect(fixture.configurationPort.acpSaves, hasLength(1));
    expect(scene.acp.port.authStarts, hasLength(1));
    expect(fixture.configurationPort.acpRemovals, isEmpty);
    expect(
      find.byKey(StudioDriverKeys.acpAccountName),
      findsNothing,
      reason: '编辑器已关闭',
    );
  });
}
