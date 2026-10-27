import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';
import 'package:anywork_client/model_directory.dart';

import 'support/accounts_test_runtime.dart';

const _online = AccountModelView(
  modelId: 'online-model',
  displayName: 'Online',
  reasoningEfforts: [],
  origin: ModelOrigin.online,
);
const _bundled = AccountModelView(
  modelId: 'bundled-model',
  displayName: 'Bundled',
  reasoningEfforts: [],
  origin: ModelOrigin.bundled,
);
const _manual = AccountModelView(
  modelId: 'manual-model',
  displayName: 'Manual',
  reasoningEfforts: [],
  origin: ModelOrigin.manual,
);

AccountSettingsView _account({
  List<AccountModelView> models = const [_online, _bundled, _manual],
  Map<String, String> connections = const {'manual-model': 'http'},
  Map<String, AccountModelAutoCompactView>? limits,
}) {
  return AccountSettingsView(
    id: 'fixture',
    name: 'Fixture',
    baseUrl: 'http://fixture.invalid',
    defaultModelId: 'manual-model',
    status: 'ready',
    usageLabel: '',
    models: models,
    modelConnectionModes: connections,
    autoCompactLimits:
        limits ??
        {
          'manual-model': AccountModelAutoCompactView(
            modelId: _manual.modelId,
            overrideLimit: 111,
          ),
          'online-model': AccountModelAutoCompactView(modelId: _online.modelId),
        },
  );
}

SettingsStateSnapshot _snapshot(
  int revision,
  AccountSettingsView account, {
  int modelCatalogRevision = 0,
}) => SettingsStateSnapshot(
  revision: revision,
  modelCatalogRevision: modelCatalogRevision,
  accounts: [account],
);

class _RemoveCall {
  _RemoveCall(this.revision, this.accountId, this.modelId, this.operationId);
  final int revision;
  final String accountId;
  final String modelId;
  final OperationId operationId;
  final reply = Completer<SettingsCommandReply>();
}

class _Transport extends AccountsTestTransport {
  final calls = StreamController<_RemoveCall>.broadcast();
  SettingsStateSnapshot? refreshed;
  int refreshes = 0;

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) =>
      const Stream.empty();

  @override
  Future<SettingsStateSnapshot> readSettingsState() async {
    refreshes++;
    return refreshed!;
  }

  @override
  Future<SettingsCommandReply> removeAccountModel(
    int revision,
    String accountId,
    String modelId, {
    required OperationId operationId,
  }) {
    final call = _RemoveCall(revision, accountId, modelId, operationId);
    calls.add(call);
    return call.reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused: ${invocation.memberName}');
}

AccountsTestRuntime _client(_Transport transport, AccountSettingsView account) {
  transport.epoch = 'origin-owner';
  final client = AccountsTestRuntime(transport, clientId: 'origin-client');
  client.seed(_snapshot(7, account, modelCatalogRevision: 1));
  addTearDown(client.close);
  addTearDown(transport.calls.close);
  return client;
}

void main() {
  test('one model domain preserves origin groups without modelId diffs', () {
    final runtime = _client(_Transport(), _account());
    final joined = runtime
        .domains
        .models
        .state
        .value
        .accounts[const NativeAccountIdentity('fixture')]!
        .value!;
    expect(
      joined.models
          .where((model) => model.origin == ModelOrigin.online)
          .map((model) => model.modelId),
      ['online-model'],
    );
    expect(
      joined.models
          .where((model) => model.origin == ModelOrigin.bundled)
          .map((model) => model.modelId),
      ['bundled-model'],
    );
    expect(
      joined.models
          .where((model) => model.origin == ModelOrigin.manual)
          .map((model) => model.modelId),
      ['manual-model'],
    );
    expect(joined.models.map((model) => model.origin), [
      ModelOrigin.online,
      ModelOrigin.bundled,
      ModelOrigin.manual,
    ]);
  });

  test(
    'removeAccountModel uses canonical revision and merges returned snapshot',
    () async {
      final transport = _Transport();
      final client = _client(transport, _account());
      final pending = client.domains.models.removeManual(
        modelIdentity('fixture', 'manual-model'),
      );
      final call = await transport.calls.stream.first;
      expect(call.revision, 7);
      expect(call.accountId, 'fixture');
      expect(call.modelId, 'manual-model');
      expect(
        call.operationId,
        client.board.latest('model:remove:7:fixture:manual-model')!.id,
      );
      final remaining = _account(
        models: const [_online, _bundled],
        connections: const {},
        limits: {
          'online-model': AccountModelAutoCompactView(modelId: _online.modelId),
        },
      );
      call.reply.complete(
        accountReply(
          snapshot: _snapshot(8, remaining, modelCatalogRevision: 2),
          receipt: StudioCommandReceipt(
            operationId: call.operationId,
            disposition: CommitDisposition.applied,
            targets: [
              ResourceStamp(
                resourceKey: 'settings',
                ownerEpoch: 'origin-owner',
                revision: 8,
              ),
            ],
            effect: EffectPoint.immediate,
            effective: true,
            durable: true,
          ),
        ),
      );
      final snapshot = await pending;
      expect((snapshot.receipt!.targets.single as ResourceStamp).revision, 8);
      final account = client
          .domains
          .models
          .state
          .value
          .accounts[const NativeAccountIdentity('fixture')]!
          .value!;
      expect(account.models.map((model) => model.modelId), [
        'online-model',
        'bundled-model',
      ]);
      expect(
        account.models.where((model) => model.origin == ModelOrigin.manual),
        isEmpty,
      );
      final configuration = client
          .domains
          .models
          .state
          .value
          .configurations[const NativeAccountIdentity('fixture')]!
          .value!;
      expect(configuration.connections.containsKey('manual-model'), isFalse);
      expect(
        configuration.autoCompactLimits.containsKey('manual-model'),
        isFalse,
      );
    },
  );

  test('a newer config response cannot roll back type support and parameter defaults', () {
    final transport = _Transport();
    final subscription = transport.calls.stream.listen((_) {});
    addTearDown(subscription.cancel);
    final client = _client(transport, _account());
    final updated = _online.copyWith(
      typeSupport: const [ModelTypeSupportView(modelType: ModelType.text)],
      contextWindow: 4096,
      reasoningEfforts: const ['low', 'high'],
      defaultReasoningEffort: 'high',
    );
    client.seed(
      _snapshot(7, _account(models: [updated]), modelCatalogRevision: 4),
    );
    client.seed(
      _snapshot(8, _account(models: const [_online]), modelCatalogRevision: 2),
    );
    final merged = client.domains.models.state.value;
    expect(
      merged
          .configurations[const NativeAccountIdentity('fixture')]!
          .stamp!
          .revision,
      8,
    );
    expect(
      merged.accounts[const NativeAccountIdentity('fixture')]!.stamp!.revision,
      4,
    );
    final model = merged
        .accounts[const NativeAccountIdentity('fixture')]!
        .value!
        .models
        .where((model) => model.enabled && model.matchesType(ModelType.text))
        .single;
    expect(model.modelId, 'online-model');
    expect(model.defaultReasoningEffort, 'high');
    expect(model.reasoningEfforts, ['low', 'high']);
    final excluded = updated.copyWith(
      typeSupport: const [
        ModelTypeSupportView(
          modelType: ModelType.text,
          exclusions: [ModelTypeExclusion.contextWindowUnknown],
        ),
      ],
    );
    client.seed(
      _snapshot(8, _account(models: [excluded]), modelCatalogRevision: 5),
    );
    expect(
      client
          .domains
          .models
          .state
          .value
          .accounts[const NativeAccountIdentity('fixture')]!
          .value!
          .models
          .where((model) => model.enabled && model.matchesType(ModelType.text)),
      isEmpty,
    );
    expect(
      client
          .domains
          .models
          .state
          .value
          .accounts[const NativeAccountIdentity('fixture')]!
          .value!
          .models
          .single
          .modelId,
      'online-model',
    );
  });
}
