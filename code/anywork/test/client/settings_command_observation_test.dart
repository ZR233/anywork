import 'dart:async';

import 'package:anywork_client/studio_client.dart';
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
    final client = AnyworkClient(
      transport: RecordingDemoTransport(),
      clientId: 'created-billing',
    );
    addTearDown(client.close);
    await client.bootstrap();
    const id = 'created-no-charge';
    final catalog = client.settings.state.accountCatalog;
    final template = catalog.templates.first;
    final draft = template.createAccount(
      id,
      catalog.modelsFor(template.modelCatalogId),
    );
    await client.settingsCommands.saveAccount(
      AccountCommandBuilder.buildAccount(
        draft,
        initialBillingKind: BillingKind.noCharge,
      ),
    );
    AccountSettingsView current() => client.settings.state.canonical!.accounts
        .singleWhere((account) => account.id == id);
    expect(current().billingKind, BillingKind.noCharge);
    expect(current().billingKindOverride, BillingKind.noCharge);
    // An ordinary endpoint edit preserves the explicit initial intent.
    await client.settingsCommands.saveAccount(
      AccountCommandBuilder.buildAccount(
        draft.copyWith(
          name: 'Edited connection',
          baseUrl: 'https://changed.example/v1',
        ),
      ),
    );
    expect(current().billingKind, BillingKind.noCharge);
    expect(current().billingKindOverride, BillingKind.noCharge);
    await client.settingsCommands.setAccountBillingKind(id, null);
    // Demo templates are synthetic and supply no canonical native billing facts.
    expect(current().billingKind, BillingKind.unknown);
    expect(current().billingKindOverride, isNull);
    // Stale connection drafts cannot restore the cleared no-charge override.
    await client.settingsCommands.saveAccount(
      AccountCommandBuilder.buildAccount(
        draft.copyWith(
          billingKind: BillingKind.noCharge,
          billingKindOverride: BillingKind.noCharge,
        ),
      ),
    );
    expect(current().billingKind, BillingKind.unknown);
    expect(current().billingKindOverride, isNull);
    await client.settingsCommands.setAccountBillingKind(
      id,
      BillingKind.subscription,
    );
    await client.settingsCommands.saveAccount(
      AccountCommandBuilder.buildAccount(draft),
    );
    expect(current().billingKind, BillingKind.subscription);
    expect(current().billingKindOverride, BillingKind.subscription);
    await client.settingsCommands.removeAccount(id);
    // Reusing an ID is a new resource, not an old inferred-category cache hit.
    await client.settingsCommands.saveAccount(
      AccountCommandBuilder.buildAccount(draft),
    );
    expect(current().billingKind, BillingKind.unknown);
    expect(current().billingKindOverride, isNull);
    await client.settingsCommands.setAccountBillingKind(
      id,
      BillingKind.noCharge,
    );
    await client.settingsCommands.setAccountBillingKind(id, null);
    expect(current().billingKind, BillingKind.unknown);
  });

  test('model enabled command accepts its own canonical receipt', () async {
    final transport = RecordingDemoTransport();
    final client = AnyworkClient(
      transport: transport,
      clientId: 'enabled-receipt',
    );
    addTearDown(client.close);
    await client.bootstrap();
    final account = client.settings.state.canonical!.accounts.first;
    final model = account.models.first;
    final key = accountModelEnabledMutationKey(account.id, model.modelId);
    await client.settingsCommands.setAccountModelEnabled(
      account.id,
      model.modelId,
      false,
    );
    expect(
      client.settings.state.canonical!.accounts.first.models.first.enabled,
      isFalse,
    );
    expect(client.settings.state.commands[key]?.isPending ?? false, isFalse);
    expect(client.settings.state.commands[key]?.error, isNull);
    await client.settingsCommands.setAccountBillingKind(
      account.id,
      BillingKind.noCharge,
    );
    expect(
      client.settings.state.canonical!.accounts.first.billingKindOverride,
      BillingKind.noCharge,
    );
    expect(
      client.settings.state.canonical!.accounts.first.billingKind,
      BillingKind.noCharge,
    );
    await client.settingsCommands.setAccountBillingKind(account.id, null);
    expect(
      client.settings.state.canonical!.accounts.first.billingKindOverride,
      isNull,
    );
    final current = client.settings.state.canonical!.accounts.first;
    await client.settingsCommands.saveAccount(
      AccountCommandBuilder.buildAccount(
        current.copyWith(
          models: [
            ...current.models,
            const AccountModelView(
              modelId: 'manual-receipt',
              displayName: 'Manual',
              reasoningEfforts: [],
              contextWindow: 1000,
              maxOutputTokens: 100,
              origin: ModelOrigin.manual,
            ),
          ],
        ),
        secret: const AccountSecretCommand.preserve(),
      ),
    );
    await client.settingsCommands.removeAccountModel(
      account.id,
      'manual-receipt',
    );
    expect(
      client.settings.state.canonical!.accounts.first.models.any(
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
