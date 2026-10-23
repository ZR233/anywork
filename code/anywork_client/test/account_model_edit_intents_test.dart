import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/configuration_fixture.dart';

AccountConfiguration _account() => AccountConfiguration(accountId: 'fixture',
  templateId: 'template-a', protocol: 'openai', name: 'Canonical account',
  baseUrl: 'https://fixture.invalid', hasBearerToken: true, pricingEnabled: true,
  usageQueryRevision: 9, catalogId: 'catalog',
  customModels: [customModel('alpha'), customModel('beta', contextWindow: 2000)],
  modelConnectionModes: const [
    ModelConnection(modelId: 'alpha', connectionMode: 'http'),
    ModelConnection(modelId: 'beta', connectionMode: 'auto'),
    ModelConnection(modelId: 'online-not-displayed', connectionMode: 'http'),
  ], modelAutoCompactLimits: const [
    ModelAutoCompact(modelId: 'alpha', overrideLimit: 111),
    ModelAutoCompact(modelId: 'beta', overrideLimit: 250),
    ModelAutoCompact(modelId: 'online-not-displayed', overrideLimit: 777),
  ]);

Future<ConfigurationFixture> _fixture({AccountConfiguration? account}) async {
  final fixture = ConfigurationFixture();
  await fixture.establish(account ?? _account());
  addTearDown(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final reports = await Future.wait([
      fixture.repository.close(deadline: deadline),
      fixture.models.close(deadline: deadline),
    ]);
    expect(reports.expand((report) => report.unresolved), isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });
  return fixture;
}

Map<String, int> _limits(AccountSettingsUpdate update) => {
  for (final item in update.modelAutoCompactLimits) item.modelId: item.limit,
};
Map<String, String> _connections(AccountSettingsUpdate update) => {
  for (final item in update.modelConnectionModes) item.modelId: item.connectionMode,
};

const _nativeRefusal = StudioFailure(code: StudioFailureCode.invalidArgument,
  message: 'The scripted native boundary declined this prepared write',
  retryable: false, correlationId: 'configuration-native-refusal');

/// The real Repository must construct the correct full native request before
/// native validation can accept or reject it. Explicit rejection then proves
/// there was no optimistic canonical edit or fabricated command receipt.
Future<void> _reject(AccountSaveCall call, OperationTicket<Unit> ticket) async {
  call.reply.completeError(const CommandDispatchFailure.rejected(failure: _nativeRefusal));
  final result = await ticket.result;
  expect(result, isA<RejectedCommandResult<Unit>>());
  expect((result as RejectedCommandResult<Unit>).error, _nativeRefusal);
}

void main() {
  test('rename moves the explicit limit, drops the old connection and freezes caller-owned edits', () async {
    final fixture = await _fixture();
    final changes = <CustomModelChange>[CustomModelChange.upsert(
      originalModelId: 'alpha', value: modelUpdate('renamed'))];
    final ticket = fixture.repository.saveAccount(accountEdit(models: changes));
    changes.clear();
    final call = await fixture.port.saved(0);
    final update = call.request.account;
    expect(call.request.expectedRevision, 1);
    expect(update.customModels.map((model) => model.modelId), ['renamed', 'beta']);
    expect(_limits(update), {'renamed': 111, 'beta': 250, 'online-not-displayed': 777});
    expect(_connections(update), {'beta': 'auto', 'online-not-displayed': 'http'});
    expect(update.secret, isA<PreserveAccountSecret>());
    await _reject(call, ticket);
    expect(await fixture.repository.loadAccount('fixture'), _account(),
      reason: 'A rejected native write must not install the prepared rename');
  });

  test('wire API changes clear old transport overrides before applying explicit new choices', () async {
    final fixture = await _fixture();
    for (final explicit in [false, true]) {
      final ticket = fixture.repository.saveAccount(accountEdit(
        models: [CustomModelChange.upsert(originalModelId: 'alpha',
          value: modelUpdate('alpha', wireApi: 'responses'))],
        connections: explicit
            ? const [ModelConnectionChange(modelId: 'alpha', connectionMode: 'auto')]
            : const [],
      ));
      final call = await fixture.port.saved(explicit ? 1 : 0);
      expect(call.request.account.customModels.first.wireApi, 'responses');
      expect(_connections(call.request.account), {
        if (explicit) 'alpha': 'auto',
        'beta': 'auto', 'online-not-displayed': 'http',
      });
      expect(_limits(call.request.account), {
        'alpha': 111, 'beta': 250, 'online-not-displayed': 777,
      });
      await _reject(call, ticket);
    }
  });

  test('removal clears both associated overrides without filtering unrelated catalog-only members', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.saveAccount(accountEdit(
      models: const [CustomModelChange.remove(modelId: 'alpha')]));
    final call = await fixture.port.saved(0);
    expect(call.request.account.customModels.map((model) => model.modelId), ['beta']);
    expect(_limits(call.request.account), {'beta': 250, 'online-not-displayed': 777});
    expect(_connections(call.request.account), {'beta': 'auto', 'online-not-displayed': 'http'});
    await _reject(call, ticket);
  });

  test('ordinary model metadata changes preserve overrides and unknown capacities', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.saveAccount(accountEdit(models: [
      CustomModelChange.upsert(originalModelId: 'alpha',
        value: modelUpdate('alpha', name: 'New display name', maxOutputTokens: 4096)),
    ]));
    final call = await fixture.port.saved(0);
    expect(call.request.account.customModels.first.displayName, 'New display name');
    expect(call.request.account.customModels.first.contextWindow, isNull);
    expect(call.request.account.customModels.first.maxOutputTokens, 4096);
    expect(_connections(call.request.account), {
      'alpha': 'http', 'beta': 'auto', 'online-not-displayed': 'http',
    });
    expect(_limits(call.request.account), {
      'alpha': 111, 'beta': 250, 'online-not-displayed': 777,
    });
    await _reject(call, ticket);
  });

  test('renaming an account model with no explicit limit never manufactures one', () async {
    final initial = _account().copyWith(modelAutoCompactLimits: const [
      ModelAutoCompact(modelId: 'alpha', overrideLimit: null),
      ModelAutoCompact(modelId: 'beta', overrideLimit: 250),
    ]);
    final fixture = await _fixture(account: initial);
    final ticket = fixture.repository.saveAccount(accountEdit(models: [
      CustomModelChange.upsert(originalModelId: 'alpha', value: modelUpdate('renamed')),
    ]));
    final call = await fixture.port.saved(0);
    expect(_limits(call.request.account), {'beta': 250});
    await _reject(call, ticket);
  });

  test('explicit same-template rebuild clears only the model configuration base before new intents', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.saveAccount(accountEdit(rebuild: true,
      // This remains an explicit rebuild even when the final template equals
      // the canonical ID, as it does after a UI A -> B -> A switch.
      templateId: const FieldEdit.set('template-a'),
      models: [CustomModelChange.upsert(originalModelId: null,
        value: modelUpdate('fresh'))],
      connections: const [ModelConnectionChange(modelId: 'fresh', connectionMode: 'http')],
      limits: const [ModelLimitChange(modelId: 'fresh', overrideLimit: 123)],
    ));
    final call = await fixture.port.saved(0);
    final update = call.request.account;
    expect(update.templateId, 'template-a');
    expect(update.customModels.map((model) => model.modelId), ['fresh']);
    expect(_connections(update), {'fresh': 'http'});
    expect(_limits(update), {'fresh': 123});
    expect(update.accountId, 'fixture');
    expect(update.name, 'Canonical account');
    expect(update.baseUrl, 'https://fixture.invalid');
    expect(update.pricingEnabled, isTrue);
    expect(update.secret, isA<PreserveAccountSecret>());
    await _reject(call, ticket);
  });

  test('rebuild without an explicit template is rejected before any native write', () async {
    final fixture = await _fixture();
    expect(() => fixture.repository.saveAccount(accountEdit(rebuild: true)),
      throwsA(isA<StudioFailure>().having((failure) => failure.code,
        'code', StudioFailureCode.invalidArgument)));
    expect(fixture.port.saves, isEmpty);
  });

  test('CAS recovery rebuilds the same operation from the latest full canonical account', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.saveAccount(accountEdit(models: [
      CustomModelChange.upsert(originalModelId: 'alpha', value: modelUpdate('renamed')),
    ]));
    final first = await fixture.port.saved(0);
    expect(_limits(first.request.account)['renamed'], 111);
    final latest = _account().copyWith(name: 'External name', baseUrl: 'https://new.invalid',
      modelAutoCompactLimits: const [
        ModelAutoCompact(modelId: 'alpha', overrideLimit: 321),
        ModelAutoCompact(modelId: 'beta', overrideLimit: 450),
        ModelAutoCompact(modelId: 'online-not-displayed', overrideLimit: 999),
      ]);
    fixture.port.snapshots[2] = latest;
    const stale = StudioFailure(code: StudioFailureCode.staleRevision,
      message: 'The native CAS base advanced', retryable: true,
      correlationId: 'stale-account');
    first.reply.completeError(const CommandDispatchFailure.rejected(failure: stale));
    final replacement = await fixture.port.opened(1);
    await replacement.listened.future;
    fixture.port.baseline(replacement, 2);
    final retried = await fixture.port.saved(1);
    expect(retried.request.operationId, first.request.operationId);
    expect(retried.request.expectedRevision, 2);
    expect(retried.request.account.name, 'External name');
    expect(retried.request.account.baseUrl, 'https://new.invalid');
    expect(_limits(retried.request.account), {
      'renamed': 321, 'beta': 450, 'online-not-displayed': 999,
    });
    expect(_connections(retried.request.account), {
      'beta': 'auto', 'online-not-displayed': 'http',
    });
    expect(fixture.port.readRevisions, [1, 2]);
    await _reject(retried, ticket);
    expect(fixture.port.saves, hasLength(2));
    expect(await fixture.repository.loadAccount('fixture'), latest);
  });

  test('model ID collisions remain visible to native validation rather than being silently resolved', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.saveAccount(accountEdit(models: [
      CustomModelChange.upsert(originalModelId: 'alpha', value: modelUpdate('beta')),
    ]));
    final call = await fixture.port.saved(0);
    expect(call.request.account.customModels.map((model) => model.modelId), ['beta', 'beta']);
    await _reject(call, ticket);
    expect(await fixture.repository.loadAccount('fixture'), _account());
  });
}
