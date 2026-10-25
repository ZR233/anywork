import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/configuration_command_fixture.dart';
import '../../../anywork_client/test/support/configuration_fixture.dart';
import '../../../anywork_client/test/support/profile_model_port.dart';
import 'support/settings_accounts_fixture.dart';

ConfigurationCommandReply _reply(OperationId id, ProductReadOrigin origin, int revision,
  ModelCatalogReadTarget catalog) => ConfigurationCommandReply(
    receipt: CommitReceipt(operationId: id, disposition: CommitDisposition.applied,
      targets: [ResourceStamp(resourceKey: 'settings', ownerEpoch: origin.ownerEpoch, revision: revision)],
      effect: EffectPoint.futureSession, effective: false, durable: true),
    configuration: ConfigurationReadTarget(origin: origin,
      reference: ConfigurationReadRef(entry: 1, revision: revision)), models: catalog);

Future<void> _finish<T>(RecordedConfigurationCall<T> call, OperationTicket<Unit> ticket,
  ConfigurationCommandReply reply, Future<void> Function() publish) async {
  await call.native.resultRead(0);
  call.native.resultAt(0).reply.complete(reply);
  await publish();
  expect(await ticket.result, isA<CommittedCommandResult<Unit>>());
  final close = await call.native.closed(0);
  close.reply.complete(FeedCloseReport(feedId: call.native.callId, outcome: const FeedCloseOutcome.clean()));
}

AccountConfiguration _account() => AccountConfiguration(accountId: 'account',
  templateId: null, protocol: 'openai', name: 'Account', baseUrl: 'https://settings.invalid',
  hasBearerToken: false, pricingEnabled: false, billingKind: BillingKind.subscription,
  bearerTokenEnv: null,
  billingKindOverride: null, disabledModels: const [], usageQueryRevision: 1, catalogId: null,
  customModels: const [], modelConnectionModes: const [], modelAutoCompactLimits: const []);

void main() {
  test('model enabled command accepts its own canonical receipt', () async {
    const origin = ProductReadOrigin(ownerEpoch: 'enabled-catalog', incarnation: 1);
    const catalog = ModelCatalogReadTarget(origin: origin,
      reference: ModelCatalogReadRef(entry: 1, revision: 1));
    final modelPort = ProfileModelsPort(origin: origin, accounts: const [], textEligibleAccounts: const {});
    final fixture = ConfigurationFixture(modelsPort: modelPort);
    var canonical = _account();
    await fixture.establish(canonical);
    addTearDown(() async {
      final reports = await Future.wait([fixture.repository.close(), fixture.models.close()]);
      expect(reports.expand((report) => report.unresolved), isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    final repository = fixture.repository;
    final enabled = repository.setAccountModelEnabled('account', 'online', false);
    final enabledCall = await fixture.port.enabledChanged(0);
    canonical = canonical.copyWith(disabledModels: ['online']);
    final finishing = _finish(enabledCall, enabled,
      _reply(enabled.id, configurationFixtureOrigin, 2, catalog),
      () => fixture.port.publishAccount(2, canonical));
    await modelPort.feed.listened.future;
    modelPort.baseline();
    await finishing;
    expect((await repository.loadAccount('account')).disabledModels, contains('online'));
    expect(enabled.state.value.isPending, isFalse);
    expect(enabled.state.value.error, isNull);

    final billing = repository.setAccountBillingKind('account', BillingKind.unknown);
    final billingCall = await fixture.port.billingChanged(0);
    canonical = canonical.copyWith(billingKind: BillingKind.unknown, billingKindOverride: BillingKind.unknown);
    await _finish(billingCall, billing, _reply(billing.id, configurationFixtureOrigin, 3, catalog),
      () => fixture.port.publishAccount(3, canonical));
    expect((await repository.loadAccount('account')).billingKindOverride, BillingKind.unknown);
    final clearing = repository.setAccountBillingKind('account', null);
    final clearCall = await fixture.port.billingChanged(1);
    canonical = canonical.copyWith(billingKind: BillingKind.subscription, billingKindOverride: null);
    await _finish(clearCall, clearing, _reply(clearing.id, configurationFixtureOrigin, 4, catalog),
      () => fixture.port.publishAccount(4, canonical));
    expect((await repository.loadAccount('account')).billingKindOverride, isNull);

    final saving = repository.saveAccount(AccountEdit(accountId: 'account', create: false,
      rebuildModelConfiguration: false, templateId: const FieldEdit.keep(), protocol: const FieldEdit.keep(),
      name: const FieldEdit.keep(), baseUrl: const FieldEdit.keep(), pricingEnabled: const FieldEdit.keep(),
      secret: const AccountSecretUpdate.preserve(), customModels: [CustomModelChange.upsert(
        originalModelId: null, value: modelUpdate('manual-receipt', contextWindow: 1000, maxOutputTokens: 100))],
      connections: const [], autoCompactLimits: const []));
    final saved = await fixture.port.saved(0);
    canonical = canonical.copyWith(customModels: [customModel('manual-receipt', contextWindow: 1000, maxOutputTokens: 100)]);
    await _finish(saved, saving, _reply(saving.id, configurationFixtureOrigin, 5, catalog),
      () => fixture.port.publishAccount(5, canonical));
    expect((await repository.loadAccount('account')).customModels.single.modelId, 'manual-receipt');
    final removing = repository.removeAccountModel('account', 'manual-receipt');
    final removed = await fixture.port.removed(0);
    canonical = canonical.copyWith(customModels: []);
    await _finish(removed, removing, _reply(removing.id, configurationFixtureOrigin, 6, catalog),
      () => fixture.port.publishAccount(6, canonical));
    expect((await repository.loadAccount('account')).customModels.any((model) => model.modelId == 'manual-receipt'), isFalse);
  });

  test('old Settings ACK cannot clear newer intent and never reopens the baseline', () async {
    final fixture = SettingsAccountsFixture();
    await fixture.establish();
    addTearDown(() async {
      expect((await fixture.close()).unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    final repository = fixture.configuration;
    final first = repository.applyField(const SettingsFieldUpdate.generalFollowActiveTurn(value: false));
    final x = await fixture.configurationPort.field(0);
    final second = repository.applyField(const SettingsFieldUpdate.generalFollowActiveTurn(value: true));
    final observations = fixture.operations.observations;
    expect(first.id, isNot(second.id));
    x.accept();
    fixture.configurationPort.followAt[2] = false;
    const catalog = ModelCatalogReadTarget(origin: SettingsAccountsFixture.origin,
      reference: ModelCatalogReadRef(entry: 1, revision: 1));
    await _finish(x, first, _reply(first.id, SettingsAccountsFixture.origin, 2, catalog),
      () => fixture.configurationPort.base.publishSettings(2));
    final y = await fixture.configurationPort.field(1);
    expect(first.state.value.observed, isTrue);
    expect(second.state.value.isPending, isTrue);
    expect(observations.latest(first.state.value.target)?.id, second.id);
    expect(y.request.expectedRevision, 2);
    y.accept();
    fixture.configurationPort.followAt[3] = true;
    await _finish(y, second, _reply(second.id, SettingsAccountsFixture.origin, 3, catalog),
      () => fixture.configurationPort.base.publishSettings(3));
    expect(second.state.value.observed, isTrue);
    expect(second.state.value.isPending, isFalse);
    expect(fixture.configurationPort.base.configurationOpens, hasLength(1));
    expect(fixture.configurationPort.fields.map((call) => call.request.operationId), [first.id, second.id]);
    expect((await repository.loadGeneralSettings()).followActiveTurn, isTrue);
  });
}
