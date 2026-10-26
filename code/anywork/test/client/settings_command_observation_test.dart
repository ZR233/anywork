import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/configuration_command_fixture.dart';
import '../../../anywork_client/test/support/configuration_fixture.dart';
import '../../../anywork_client/test/support/profile_model_port.dart';
import 'support/settings_accounts_fixture.dart';

ConfigurationCommandReply _reply(
  OperationId id,
  ProductReadOrigin origin,
  int revision,
  ModelCatalogReadTarget catalog,
) => ConfigurationCommandReply(
  receipt: CommitReceipt(
    operationId: id,
    disposition: CommitDisposition.applied,
    targets: [
      ResourceStamp(
        resourceKey: 'settings',
        ownerEpoch: origin.ownerEpoch,
        revision: revision,
      ),
    ],
    effect: EffectPoint.futureSession,
    effective: false,
    durable: true,
  ),
  configuration: ConfigurationReadTarget(
    origin: origin,
    reference: ConfigurationReadRef(entry: 1, revision: revision),
  ),
  models: catalog,
);

Future<void> _finish<T>(
  RecordedConfigurationCall<T> call,
  OperationTicket<Unit> ticket,
  ConfigurationCommandReply reply,
  Future<void> Function() publish,
) async {
  await call.native.resultRead(0);
  call.native.resultAt(0).reply.complete(reply);
  await publish();
  expect(await ticket.result, isA<CommittedCommandResult<Unit>>());
  final close = await call.native.closed(0);
  close.reply.complete(
    FeedCloseReport(
      feedId: call.native.callId,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
}

AccountConfiguration _account() => AccountConfiguration(
  accountId: 'account',
  templateId: null,
  protocol: 'openai',
  name: 'Account',
  baseUrl: 'https://settings.invalid',
  hasBearerToken: false,
  billingKind: BillingKind.subscription,
  bearerTokenEnv: null,
  billingKindOverride: null,
  disabledModels: const [],
  usageQueryRevision: 1,
  catalogId: null,
  customModels: const [],
  modelConnectionModes: const [],
  modelAutoCompactLimits: const [],
);

void main() {
  test('model enabled command accepts its own canonical receipt', () async {
    const origin = ProductReadOrigin(
      ownerEpoch: 'enabled-catalog',
      incarnation: 1,
    );
    const catalog = ModelCatalogReadTarget(
      origin: origin,
      reference: ModelCatalogReadRef(entry: 1, revision: 1),
    );
    final modelPort = ProfileModelsPort(
      origin: origin,
      accounts: const [],
      textEligibleAccounts: const {},
    );
    final fixture = ConfigurationFixture(modelsPort: modelPort);
    var canonical = _account();
    await fixture.establish(canonical);
    addTearDown(() async {
      final reports = await Future.wait([
        fixture.repository.close(),
        fixture.models.close(),
      ]);
      expect(reports.expand((report) => report.unresolved), isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    final repository = fixture.repository;
    final enabled = repository.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final enabledCall = await fixture.port.enabledChanged(0);
    canonical = canonical.copyWith(disabledModels: ['online']);
    final finishing = _finish(
      enabledCall,
      enabled,
      _reply(enabled.id, configurationFixtureOrigin, 2, catalog),
      () => fixture.port.publishAccount(2, canonical),
    );
    await modelPort.feed.listened.future;
    modelPort.baseline();
    await finishing;
    expect(
      (await repository.loadAccount('account')).disabledModels,
      contains('online'),
    );
    expect(enabled.state.value.isPending, isFalse);
    expect(enabled.state.value.error, isNull);

    final billing = repository.setAccountBillingKind(
      'account',
      BillingKind.unknown,
    );
    final billingCall = await fixture.port.billingChanged(0);
    expect(
      (await repository.loadAccount('account')).billingKind,
      BillingKind.subscription,
      reason: 'No optimistic billing success',
    );
    canonical = canonical.copyWith(
      billingKind: BillingKind.unknown,
      billingKindOverride: BillingKind.unknown,
    );
    await _finish(
      billingCall,
      billing,
      _reply(billing.id, configurationFixtureOrigin, 3, catalog),
      () => fixture.port.publishAccount(3, canonical),
    );
    expect(
      (await repository.loadAccount('account')).billingKindOverride,
      BillingKind.unknown,
    );
    final clearing = repository.setAccountBillingKind('account', null);
    final clearCall = await fixture.port.billingChanged(1);
    canonical = canonical.copyWith(
      billingKind: BillingKind.subscription,
      billingKindOverride: null,
    );
    await _finish(
      clearCall,
      clearing,
      _reply(clearing.id, configurationFixtureOrigin, 4, catalog),
      () => fixture.port.publishAccount(4, canonical),
    );
    expect(
      (await repository.loadAccount('account')).billingKindOverride,
      isNull,
    );

    final saving = repository.saveAccount(
      AccountEdit(
        accountId: 'account',
        create: false,
        rebuildModelConfiguration: false,
        templateId: const FieldEdit.keep(),
        protocol: const FieldEdit.keep(),
        name: const FieldEdit.keep(),
        baseUrl: const FieldEdit.keep(),
        secret: const AccountSecretUpdate.preserve(),
        // 编辑既有账号：不提交初始计费类别（类别只由窄命令改写）。
        initialBillingKind: null,
        customModels: [
          CustomModelChange.upsert(
            originalModelId: null,
            value: modelUpdate(
              'manual-receipt',
              contextWindow: 1000,
              maxOutputTokens: 100,
            ),
          ),
        ],
        connections: const [],
        autoCompactLimits: const [],
      ),
    );
    final saved = await fixture.port.saved(0);
    canonical = canonical.copyWith(
      customModels: [
        customModel(
          'manual-receipt',
          contextWindow: 1000,
          maxOutputTokens: 100,
        ),
      ],
    );
    await _finish(
      saved,
      saving,
      _reply(saving.id, configurationFixtureOrigin, 5, catalog),
      () => fixture.port.publishAccount(5, canonical),
    );
    expect(
      (await repository.loadAccount('account')).customModels.single.modelId,
      'manual-receipt',
    );
    final removing = repository.removeAccountModel('account', 'manual-receipt');
    final removed = await fixture.port.removed(0);
    canonical = canonical.copyWith(customModels: []);
    await _finish(
      removed,
      removing,
      _reply(removing.id, configurationFixtureOrigin, 6, catalog),
      () => fixture.port.publishAccount(6, canonical),
    );
    expect(
      (await repository.loadAccount('account')).customModels
          .any((model) => model.modelId == 'manual-receipt'),
      isFalse,
    );
  });

  test(
    'old Settings ACK cannot clear newer intent and never reopens the baseline',
    () async {
      final fixture = SettingsAccountsFixture();
      // 本用例不涉及 ACP 目录：先声明真实空目录并委托 base 的原生账号实体，
      // 再读取 Settings（未声明的目标不会回退成伪空目录）。
      fixture.configurationPort.declareAcpMaterial(
        revision: 1,
        rows: const [],
        delegateBase: true,
      );
      await fixture.establish();
      addTearDown(() async {
        expect((await fixture.close()).unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
      });
      final repository = fixture.configuration;
      final first = repository.applyField(
        const SettingsFieldUpdate.generalFollowActiveTurn(value: false),
      );
      final x = await fixture.configurationPort.field(0);
      final second = repository.applyField(
        const SettingsFieldUpdate.generalFollowActiveTurn(value: true),
      );
      final observations = fixture.operations.observations;
      expect(first.id, isNot(second.id));
      x.accept();
      fixture.configurationPort.followAt[2] = false;
      const catalog = ModelCatalogReadTarget(
        origin: SettingsAccountsFixture.origin,
        reference: ModelCatalogReadRef(entry: 1, revision: 1),
      );
      // 水位 2 的 ACP 材料必须先声明：写入回执与 Settings 事件都可能先读取该目标，
      // 读不到材料时不得补成伪空目录。
      fixture.configurationPort.declareAcpMaterial(
        revision: 2,
        rows: const [],
        delegateBase: true,
      );
      await _finish(
        x,
        first,
        _reply(first.id, SettingsAccountsFixture.origin, 2, catalog),
        () => fixture.configurationPort.base.publishSettings(2),
      );
      final y = await fixture.configurationPort.field(1);
      expect(first.state.value.observed, isTrue);
      expect(second.state.value.isPending, isTrue);
      expect(observations.latest(first.state.value.target)?.id, second.id);
      expect(y.request.expectedRevision, 2);
      y.accept();
      fixture.configurationPort.followAt[3] = true;
      fixture.configurationPort.declareAcpMaterial(
        revision: 3,
        rows: const [],
        delegateBase: true,
      );
      await _finish(
        y,
        second,
        _reply(second.id, SettingsAccountsFixture.origin, 3, catalog),
        () => fixture.configurationPort.base.publishSettings(3),
      );
      expect(second.state.value.observed, isTrue);
      expect(second.state.value.isPending, isFalse);
      expect(fixture.configurationPort.base.configurationOpens, hasLength(1));
      expect(
        fixture.configurationPort.fields.map(
          (call) => call.request.operationId,
        ),
        [first.id, second.id],
      );
      expect((await repository.loadGeneralSettings()).followActiveTurn, isTrue);
    },
  );

  test('an explicit no-charge account keeps the category until the override is cleared and a stale draft cannot replay it', () async {
    const origin = ProductReadOrigin(
      ownerEpoch: 'no-charge-catalog',
      incarnation: 1,
    );
    const catalog = ModelCatalogReadTarget(
      origin: origin,
      reference: ModelCatalogReadRef(entry: 1, revision: 1),
    );
    final modelPort = ProfileModelsPort(
      origin: origin,
      accounts: const [],
      textEligibleAccounts: const {},
    );
    final fixture = ConfigurationFixture(modelsPort: modelPort);
    // The account was created with an explicit no-charge category.
    var canonical = _account().copyWith(
      billingKind: BillingKind.noCharge,
      billingKindOverride: BillingKind.noCharge,
    );
    await fixture.establish(canonical);
    addTearDown(() async {
      final reports = await Future.wait([
        fixture.repository.close(),
        fixture.models.close(),
      ]);
      expect(reports.expand((report) => report.unresolved), isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    final repository = fixture.repository;
    Future<AccountConfiguration> current() => repository.loadAccount('account');

    // An ordinary endpoint edit preserves the explicit initial category: the
    // account write carries no billing intent at all.
    final saving = repository.saveAccount(
      AccountEdit(
        accountId: 'account',
        create: false,
        rebuildModelConfiguration: false,
        templateId: const FieldEdit.keep(),
        protocol: const FieldEdit.keep(),
        name: const FieldEdit.set('Edited connection'),
        baseUrl: const FieldEdit.set('https://changed.example/v1'),
        secret: const AccountSecretUpdate.preserve(),
        // 编辑既有账号：普通连接编辑不回传也不改写计费类别。
        initialBillingKind: null,
        customModels: const [],
        connections: const [],
        autoCompactLimits: const [],
      ),
    );
    final saved = await fixture.port.saved(0);
    expect(
      fixture.port.billingChanges,
      isEmpty,
      reason: 'An ordinary connection edit must not replay billing intent',
    );
    canonical = canonical.copyWith(
      name: 'Edited connection',
      baseUrl: 'https://changed.example/v1',
    );
    final finishing = _finish(
      saved,
      saving,
      _reply(saving.id, configurationFixtureOrigin, 2, catalog),
      () => fixture.port.publishAccount(2, canonical),
    );
    await modelPort.feed.listened.future;
    modelPort.baseline();
    await finishing;
    expect((await current()).billingKind, BillingKind.noCharge);
    expect((await current()).billingKindOverride, BillingKind.noCharge);

    // Turning no charge off writes a null intent and restores automatic
    // inference; it never replays the effective category as an override.
    final clearing = repository.setAccountBillingKind('account', null);
    final clearCall = await fixture.port.billingChanged(0);
    expect(
      clearCall.request.billingKind,
      isNull,
      reason: 'Turning no charge off must clear, not replay the effective kind',
    );
    expect(
      (await current()).billingKind,
      BillingKind.noCharge,
      reason: 'No optimistic billing success',
    );
    canonical = canonical.copyWith(
      billingKind: BillingKind.unknown,
      billingKindOverride: null,
    );
    await _finish(
      clearCall,
      clearing,
      _reply(clearing.id, configurationFixtureOrigin, 3, catalog),
      () => fixture.port.publishAccount(3, canonical),
    );
    expect((await current()).billingKind, BillingKind.unknown);
    expect((await current()).billingKindOverride, isNull);

    // A stale connection draft cannot restore the cleared override: an
    // account save never carries a category, so only canonical decides.
    final stale = repository.saveAccount(
      AccountEdit(
        accountId: 'account',
        create: false,
        rebuildModelConfiguration: false,
        templateId: const FieldEdit.keep(),
        protocol: const FieldEdit.keep(),
        name: const FieldEdit.set('Stale draft'),
        baseUrl: const FieldEdit.keep(),
        secret: const AccountSecretUpdate.preserve(),
        // 编辑既有账号：陈旧草稿同样不能携带初始类别。
        initialBillingKind: null,
        customModels: const [],
        connections: const [],
        autoCompactLimits: const [],
      ),
    );
    final staleCall = await fixture.port.saved(1);
    expect(
      fixture.port.billingChanges,
      hasLength(1),
      reason: 'Only the explicit narrow command may change the category',
    );
    canonical = canonical.copyWith(name: 'Stale draft');
    await _finish(
      staleCall,
      stale,
      _reply(stale.id, configurationFixtureOrigin, 4, catalog),
      () => fixture.port.publishAccount(4, canonical),
    );
    expect((await current()).billingKind, BillingKind.unknown);
    expect((await current()).billingKindOverride, isNull);
  });
}
