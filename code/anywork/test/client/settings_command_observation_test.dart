import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork/src/app/app_graph.dart';

import 'support/test_statistics_feed.dart';

import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

class _SettingsTransport extends RecordingDemoTransport {
  final entered = <OperationId, Completer<void>>{};
  final released = <OperationId, Completer<void>>{};
  final calls = <OperationId>[];

  Completer<void> entry(OperationId id) =>
      entered.putIfAbsent(id, Completer<void>.new);
  Completer<void> release(OperationId id) =>
      released.putIfAbsent(id, Completer<void>.new);

  @override
  Future<SettingsCommandReply> applySettingsField(
    int revision,
    SettingsFieldCommand command, {
    required OperationId operationId,
  }) async {
    calls.add(operationId);
    entry(operationId).complete();
    await release(operationId).future;
    return super.applySettingsField(
      revision,
      command,
      operationId: operationId,
    );
  }
}

void main() {
  test('created no-charge account clears to automatic without replaying an override', () async {
    final graph = AppGraph(
      transport: RecordingDemoTransport(),
      statisticsFeed: const TestStatisticsFeedPort(),
      clientId: 'created-billing',
    );
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    );
    await graph.client.bootstrap();
    final summaries = graph.accounts.observeSummaries();
    addTearDown(summaries.release);
    await graph.accounts.state.waitFor((value) => value.loaded);
    await graph.accounts.loadTemplates();
    final template = graph.accounts.state.value.templates.templates.first;
    const identity = NativeAccountIdentity('created-no-charge');
    final create = CreateAccountCommand(
      identity: identity,
      name: template.displayName,
      templateId: template.id,
      protocol: template.protocol,
      baseUrl: template.baseUrl,
      secret: const AccountSecretCommand.clear(),
      initialBillingKind: BillingKind.noCharge,
    );
    await graph.accounts.create(create);
    await graph.accounts.state.waitFor(
      (value) => value.account(identity) != null,
    );
    AccountSummary current() => graph.accounts.state.value.account(identity)!;
    expect(current().billingKind, BillingKind.noCharge);
    expect(current().billingKindOverride, BillingKind.noCharge);
    await graph.accounts.patch(
      const PatchAccountCommand(
        identity: identity,
        name: AccountTextPatch.set('Edited connection'),
        baseUrl: AccountTextPatch.set('https://changed.example/v1'),
      ),
    );
    expect(current().billingKind, BillingKind.noCharge);
    expect(current().billingKindOverride, BillingKind.noCharge);
    await graph.accounts.setBillingKind(identity, null);
    await graph.accounts.state.waitFor(
      (value) => value.account(identity)?.billingKindOverride == null,
    );
    expect(current().billingKind, BillingKind.unknown);
    expect(current().billingKindOverride, isNull);
    // Ordinary patches cannot carry any billing snapshot to replay a stale override.
    await graph.accounts.patch(
      const PatchAccountCommand(
        identity: identity,
        name: AccountTextPatch.set('Stale editor name'),
      ),
    );
    expect(current().billingKind, BillingKind.unknown);
    expect(current().billingKindOverride, isNull);
    await graph.accounts.setBillingKind(identity, BillingKind.subscription);
    await graph.accounts.state.waitFor(
      (value) =>
          value.account(identity)?.billingKindOverride ==
          BillingKind.subscription,
    );
    await graph.accounts.patch(const PatchAccountCommand(identity: identity));
    expect(current().billingKind, BillingKind.subscription);
    expect(current().billingKindOverride, BillingKind.subscription);
    await graph.accounts.remove(identity);
    await graph.accounts.state.waitFor(
      (value) => value.account(identity) == null,
    );
    await graph.accounts.create(
      CreateAccountCommand(
        identity: identity,
        name: template.displayName,
        templateId: template.id,
        protocol: template.protocol,
        baseUrl: template.baseUrl,
        secret: const AccountSecretCommand.clear(),
      ),
    );
    await graph.accounts.state.waitFor(
      (value) => value.account(identity) != null,
    );
    expect(current().billingKind, BillingKind.unknown);
    expect(current().billingKindOverride, isNull);
    await graph.accounts.setBillingKind(identity, BillingKind.noCharge);
    await graph.accounts.setBillingKind(identity, null);
    await graph.accounts.state.waitFor(
      (value) => value.account(identity)?.billingKindOverride == null,
    );
    expect(current().billingKind, BillingKind.unknown);
  });

  test('model commands observe their own canonical content and retain independent settings', () async {
    final graph = AppGraph(
      transport: RecordingDemoTransport(),
      statisticsFeed: const TestStatisticsFeedPort(),
      clientId: 'enabled-receipt',
    );
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    );
    await graph.client.bootstrap();
    final summaries = graph.accounts.observeSummaries();
    addTearDown(summaries.release);
    final directory = graph.models.observeDirectory();
    addTearDown(directory.release);
    await graph.accounts.state.waitFor((value) => value.loaded);
    await graph.models.state.waitFor(
      (value) => value.accounts.values.any(
        (resource) => resource.loaded && resource.value!.models.isNotEmpty,
      ),
    );
    final account = modelSelectionAccounts(
      graph.accounts.state.value,
      graph.models.state.value,
    ).first;
    final identity = NativeAccountIdentity(account.id);
    final model = AccountModelIdentity(
      account: identity,
      modelId: account.models.first.modelId,
    );
    final operation = await graph.models.setEnabled(model, false);
    expect(graph.models.state.value.model(model)!.enabled, isFalse);
    expect(operation.isPending, isFalse);
    expect(operation.error, isNull);
    expect(operation.observed, isTrue);
    await graph.accounts.setBillingKind(identity, BillingKind.noCharge);
    expect(
      graph.accounts.state.value.account(identity)!.billingKindOverride,
      BillingKind.noCharge,
    );
    expect(
      graph.accounts.state.value.account(identity)!.billingKind,
      BillingKind.noCharge,
    );
    await graph.accounts.setBillingKind(identity, null);
    expect(
      graph.accounts.state.value.account(identity)!.billingKindOverride,
      isNull,
    );
    await graph.accounts.patch(
      PatchAccountCommand(
        identity: identity,
        customModels: AccountModelsPatch.set([
          for (final model in account.models.where(
            (model) => model.origin == ModelOrigin.manual,
          ))
            AccountModelCommand(
              modelId: model.modelId,
              displayName: model.displayName,
              wireApi: model.wireApi,
              contextWindow: model.contextWindow,
              maxOutputTokens: model.maxOutputTokens,
            ),
          const AccountModelCommand(
            modelId: 'manual-receipt',
            displayName: 'Manual',
            wireApi: 'chat',
            contextWindow: 1000,
            maxOutputTokens: 100,
          ),
        ]),
      ),
    );
    await graph.models.removeManual(
      AccountModelIdentity(account: identity, modelId: 'manual-receipt'),
    );
    expect(
      graph.models.state.value.accounts[identity]!.value!.models.any(
        (m) => m.modelId == 'manual-receipt',
      ),
      isFalse,
    );
  });

  test(
    'old Settings ACK cannot clear newer intent and never rereads bootstrap',
    () async {
      final transport = _SettingsTransport();
      final client = AnyworkClient(transport: transport, clientId: 'settings');
      await client.bootstrap();
      final commands = client.settingsCommands;
      final first = commands.applySettingsField(
        const GeneralFollowActiveTurnCommand(false),
        mutationKey: 'follow',
      );
      final x = client.mutations.latest('settings:follow')!;
      final second = commands.applySettingsField(
        const GeneralFollowActiveTurnCommand(true),
        mutationKey: 'follow',
      );
      final y = client.mutations.latest('settings:follow')!;
      expect(x.id, isNot(y.id));
      await transport.entry(x.id).future;
      transport.release(x.id).complete();
      await first;
      await transport.entry(y.id).future;
      expect(x.state.value.observed, isTrue);
      expect(client.settings.state.commands['follow']?.isPending, isTrue);
      expect(client.mutations.latest('settings:follow')?.id, y.id);
      transport.release(y.id).complete();
      await second;
      expect(y.state.value.observed, isTrue);
      expect(client.settings.state.commands.containsKey('follow'), isFalse);
      expect(transport.bootstrapCalls, 1);
      expect(transport.calls, [x.id, y.id]);
      expect((await client.close()).complete, isTrue);
    },
  );
}
