import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

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
          'manual-model': AccountModelAutoCompactView.forModel(_manual)
              .withOverride(111),
          'online-model': AccountModelAutoCompactView.forModel(_online),
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
  _RemoveCall(this.revision, this.accountId, this.modelId);
  final int revision;
  final String accountId;
  final String modelId;
  final reply = Completer<SettingsCommandReply>();
}

class _Transport implements StudioTransport {
  final calls = StreamController<_RemoveCall>();
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
    String modelId,
  ) {
    final call = _RemoveCall(revision, accountId, modelId);
    calls.add(call);
    return call.reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused: ${invocation.memberName}');
}

AnyworkClient _client(_Transport transport, AccountSettingsView account) {
  final client = AnyworkClient(transport: transport, clientId: 'origin-client');
  client.applyBootstrap(
    StudioBootstrap(
      ownerEpoch: 'origin-owner',
      projectDirectory: ProjectDirectoryState(values: const [], revision: 1),
      threadDirectory: ThreadDirectoryWindow(threads: const [], revision: 1),
      agentDirectory: AgentDirectoryState(revision: 1),
      settingsState: _snapshot(7, account, modelCatalogRevision: 1),
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
    ),
  );
  addTearDown(client.close);
  addTearDown(transport.calls.close);
  return client;
}

void main() {
  test(
    'accountWithCatalogMetadata projects origin groups without modelId diffs',
    () {
      final joined = accountWithCatalogMetadata(
        _account(),
        const AccountCatalogView.empty(),
      );
      expect(joined.onlineModels.map((model) => model.modelId), [
        'online-model',
      ]);
      expect(joined.bundledModels.map((model) => model.modelId), [
        'bundled-model',
      ]);
      expect(joined.customModels.map((model) => model.modelId), [
        'manual-model',
      ]);
      expect(joined.models.map((model) => model.origin), [
        ModelOrigin.online,
        ModelOrigin.bundled,
        ModelOrigin.manual,
      ]);
    },
  );

  test(
    'removeAccountModel uses canonical revision and merges returned snapshot',
    () async {
      final transport = _Transport();
      final client = _client(transport, _account());
      final pending = client.settingsCommands.removeAccountModel(
        'fixture',
        'manual-model',
      );
      final call = await transport.calls.stream.first;
      expect(call.revision, 7);
      expect(call.accountId, 'fixture');
      expect(call.modelId, 'manual-model');
      final remaining = _account(
        models: const [_online, _bundled],
        connections: const {},
        limits: {'online-model': AccountModelAutoCompactView.forModel(_online)},
      );
      call.reply.complete(
        SettingsCommandReply(
          snapshot: _snapshot(8, remaining, modelCatalogRevision: 2),
          receipt: StudioCommandReceipt(
            operationId: client.mutations
                .latest('settings:account-model:7:fixture:manual-model')!
                .id,
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
      expect(snapshot.revision, 8);
      final account = client.settings.state.canonical!.accounts.single;
      expect(account.models.map((model) => model.modelId), [
        'online-model',
        'bundled-model',
      ]);
      expect(account.customModels, isEmpty);
      expect(account.modelConnectionModes.containsKey('manual-model'), isFalse);
      expect(account.autoCompactLimits.containsKey('manual-model'), isFalse);
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
    client.settings.merge(
      _snapshot(7, _account(models: [updated]), modelCatalogRevision: 4),
    );
    client.settings.merge(
      _snapshot(8, _account(models: const [_online]), modelCatalogRevision: 2),
    );
    final merged = client.settings.state.canonical!;
    expect(merged.revision, 8);
    expect(merged.modelCatalogRevision, 4);
    final model = merged.accounts.single.modelsFor(type: ModelType.text).single;
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
    client.settings.merge(
      _snapshot(8, _account(models: [excluded]), modelCatalogRevision: 5),
    );
    expect(
      client.settings.state.canonical!.accounts.single.modelsFor(
        type: ModelType.text,
      ),
      isEmpty,
    );
    expect(
      client.settings.state.canonical!.accounts.single.models.single.modelId,
      'online-model',
    );
  });
}
