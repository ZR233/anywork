import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

const _alpha = AccountModelView(
  modelId: 'alpha',
  displayName: 'Alpha',
  reasoningEfforts: [],
  contextWindow: 1000,
  maxContextWindow: 4000,
  context: ModelContextView(
    unavailable: null,
    contextWindow: 1000,
    inputTokenLimit: 900,
    autoCompactLimit: 200,
  ),
);
const _beta = AccountModelView(
  modelId: 'beta',
  displayName: 'Beta',
  reasoningEfforts: [],
  maxContextWindow: 2000,
);
const _orphan = AccountModelAutoCompactView(
  modelId: 'temporarily-unlisted',
  overrideLimit: 777,
);
final _account = AccountSettingsView(
  id: 'fixture',
  name: 'Fixture',
  baseUrl: 'http://fixture.invalid',
  defaultModelId: 'alpha',
  status: 'ready',
  usageLabel: '',
  models: const [_alpha, _beta],
  autoCompactLimits: {
    'alpha': AccountModelAutoCompactView(modelId: _alpha.modelId),
    'beta': AccountModelAutoCompactView(
      modelId: _beta.modelId,
      overrideLimit: 250,
    ),
    _orphan.modelId: _orphan,
  },
);

SettingsStateSnapshot _snapshot(int revision, AccountSettingsView account) =>
    SettingsStateSnapshot(revision: revision, accounts: [account]);

class _SaveCall {
  _SaveCall(this.revision, this.command, this.id);
  final int revision;
  final AccountCommand command;
  final OperationId id;
  final reply = Completer<SettingsCommandReply>();

  void complete(int revision, AccountSettingsView account) {
    reply.complete(
      SettingsCommandReply(
        snapshot: _snapshot(revision, account),
        receipt: StudioCommandReceipt(
          operationId: id,
          disposition: CommitDisposition.applied,
          targets: [
            ResourceStamp(
              resourceKey: 'settings',
              ownerEpoch: 'fixture-owner',
              revision: revision,
            ),
          ],
          effect: EffectPoint.immediate,
          effective: true,
          durable: true,
        ),
      ),
    );
  }
}

/// 只脚本化远端 CAS/响应，不实现命令构造、解析、lane 或 reducer。
class _Transport implements StudioTransport {
  final calls = StreamController<_SaveCall>();
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
  Future<SettingsCommandReply> saveAccount(
    int revision,
    AccountCommand command, {
    required OperationId operationId,
  }) {
    final call = _SaveCall(revision, command, operationId);
    calls.add(call);
    return call.reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused: ${invocation.memberName}');
}

AnyworkClient _client(_Transport transport) {
  final client = AnyworkClient(
    transport: transport,
    clientId: 'fixture-client',
  );
  client.applyBootstrap(
    StudioBootstrap(
      ownerEpoch: 'fixture-owner',
      projectDirectory: ProjectDirectoryState(values: const [], revision: 1),
      threadDirectory: ThreadDirectoryWindow(threads: const [], revision: 1),
      agentDirectory: AgentDirectoryState(revision: 1),
      settingsState: _snapshot(1, _account),
      recoveryState: RecoveryStateSnapshot(revision: 1),
      mcpState: McpStateSnapshot(revision: 1),
      lspState: LspStateSnapshot(revision: 1),
      skillsByProject: const {},
      threadModeCatalog: const ThreadModeCatalogView(),
      accountUsageState: AccountUsageStateSnapshot(revision: 1),
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

Map<String, int> _limits(AccountCommand command) => {
  for (final item in command.modelAutoCompactLimits) item.modelId: item.limit,
};

void main() {
  test('one catalog revision updates shared metadata across routes and rejects older responses', () {
    SettingsStateSnapshot frame(int settings, int catalog, int context) =>
        SettingsStateSnapshot(
          revision: settings,
          modelCatalogRevision: catalog,
          accounts: [
            for (final id in ['first', 'second'])
              AccountSettingsView(
                id: id,
                name: id,
                baseUrl: '',
                defaultModelId: 'shared',
                status: '',
                usageLabel: '',
                models: [
                  AccountModelView(
                    modelId: 'shared',
                    displayName: 'Shared',
                    reasoningEfforts: const [],
                    contextWindow: context,
                  ),
                ],
              ),
          ],
        );
    var state = mergeSettingsProjection(
      const SettingsProjectionState(),
      frame(1, 1, 1000),
    );
    state = mergeSettingsProjection(
      state,
      frame(1, 2, 2000),
      scope: SettingsMergeScope.catalogOnly,
    );
    expect(
      state.canonical!.accounts.map(
        (account) => account.models.single.contextWindow,
      ),
      [2000, 2000],
    );
    state = mergeSettingsProjection(state, frame(2, 1, 1000));
    expect(state.settingsRevision, 2);
    expect(state.modelCatalogRevision, 2);
    expect(
      state.canonical!.accounts.map(
        (account) => account.models.single.contextWindow,
      ),
      [2000, 2000],
    );
    expect(mergeSettingsProjection(state, frame(1, 1, 1000)), same(state));
  });

  test(
    'catalog policy is passed through unchanged across independent watermarks',
    () {
      final configured = _account.withAutoCompactLimit(
        const AccountModelAutoCompactView(modelId: 'alpha', overrideLimit: 150),
      );
      var state = mergeSettingsProjection(
        const SettingsProjectionState(),
        _snapshot(1, configured),
      );
      AccountSettingsView current() => state.canonical!.accounts.single;
      AccountModelAutoCompactView limit() => current().autoCompactLimitFor(
        current().models
                .where((model) => model.modelId == 'alpha')
                .firstOrNull ??
            const AccountModelView(
              modelId: 'alpha',
              displayName: '',
              reasoningEfforts: [],
            ),
      );
      SettingsStateSnapshot frame(
        int revision,
        List<AccountModelView> models,
      ) => SettingsStateSnapshot(
        revision: 999,
        modelCatalogRevision: revision,
        accounts: [_account.copyWith(name: 'catalog', models: models)],
      );
      const backendPolicy = ModelContextView(
        unavailable: null,
        contextWindow: 2000,
        inputTokenLimit: 1500,
        autoCompactLimit: 137,
        adjustment: ModelContextAdjustment.safetyLimit,
      );
      state = mergeSettingsProjection(
        state,
        frame(2, [
          _alpha.copyWith(contextWindow: 2000, context: backendPolicy),
          _beta,
        ]),
        scope: SettingsMergeScope.catalogOnly,
      );
      expect(state.settingsRevision, 1);
      expect(current().name, 'Fixture');
      expect(limit().overrideLimit, 150);
      expect(
        limit().context,
        same(backendPolicy),
        reason: 'backend policy is not reconstructed from capacity or override',
      );
      state = mergeSettingsProjection(
        state,
        frame(3, [
          const AccountModelView(
            modelId: 'alpha',
            displayName: '',
            reasoningEfforts: [],
          ),
          _beta,
        ]),
        scope: SettingsMergeScope.catalogOnly,
      );
      expect(limit().overrideLimit, 150);
      expect(limit().context.autoCompactLimit, isNull);
      state = mergeSettingsProjection(
        state,
        frame(4, [_beta]),
        scope: SettingsMergeScope.catalogOnly,
      );
      expect(current().autoCompactLimits['alpha']?.overrideLimit, 150);
      expect(current().autoCompactLimits[_orphan.modelId]?.overrideLimit, 777);
      state = mergeSettingsProjection(
        state,
        frame(5, [_alpha.copyWith(context: backendPolicy), _beta]),
        scope: SettingsMergeScope.catalogOnly,
      );
      final reply = configured.withAutoCompactLimit(
        const AccountModelAutoCompactView(modelId: 'alpha', overrideLimit: 300),
      );
      state = mergeSettingsProjection(
        state,
        _snapshot(2, reply),
        scope: SettingsMergeScope.configOnly,
      );
      expect(state.modelCatalogRevision, 5);
      expect(limit().overrideLimit, 300);
      expect(
        limit().context,
        same(backendPolicy),
        reason: 'old config replies cannot roll back final catalog policy',
      );
      expect(_limits(AccountCommandBuilder.buildAccount(current())), {
        'alpha': 300,
        'beta': 250,
        _orphan.modelId: 777,
      });
      expect(
        mergeSettingsProjection(state, _snapshot(1, configured)),
        same(state),
      );
    },
  );

  test('payload preserves raw intent and unknown manual capacities', () {
    final selected = _account.withAutoCompactLimit(
      const AccountModelAutoCompactView(modelId: 'alpha', overrideLimit: 200),
    );
    final command = AccountCommandBuilder.buildAccount(selected);
    expect(_limits(command), {
      'alpha': 200,
      'beta': 250,
      _orphan.modelId: 777,
    }, reason: 'only the backend normalizes an equal default');
    final unknown = AccountModelView(
      modelId: 'unknown',
      displayName: '',
      reasoningEfforts: const [],
      origin: ModelOrigin.manual,
    );
    final saved = AccountCommandBuilder.buildAccount(
      selected.copyWith(models: [unknown]),
    );
    expect(saved.customModels.single.contextWindow, isNull);
    expect(saved.customModels.single.maxOutputTokens, isNull);
  });

  test('inline intents rebuild at lane entry and every CAS retry without dropping siblings or unavailable overrides', () async {
    final transport = _Transport();
    final client = _client(transport);
    final calls = StreamIterator(transport.calls.stream);
    addTearDown(calls.cancel);
    final commands = client.settingsCommands;
    final first = commands.setModelAutoCompactLimit('fixture', 'alpha', 100);
    await calls.moveNext();
    final initial = calls.current;
    expect(initial.revision, 1);
    expect(initial.command.secret.action, AccountSecretAction.preserve);
    expect(initial.command.id, 'fixture');
    final second = commands.setModelAutoCompactLimit('fixture', 'alpha', 150);
    final reset = commands.setModelAutoCompactLimit('fixture', 'beta', null);
    final alphaKey = 'model-auto-compact:7:fixture:alpha';
    final latest = client.mutations.latest('settings:$alphaKey')!;
    final external = _account
        .copyWith(
          name: 'External name',
          baseUrl: 'http://changed.invalid',
          billingKind: BillingKind.noCharge,
          billingKindOverride: BillingKind.noCharge,
        )
        .withAutoCompactLimit(
          AccountModelAutoCompactView(
            modelId: _beta.modelId,
            overrideLimit: 400,
          ),
        );
    transport.refreshed = _snapshot(2, external);
    initial.reply.completeError(
      const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'External write',
        retryable: true,
        correlationId: 'fixture',
      ),
    );
    await calls.moveNext();
    final retried = calls.current;
    expect(retried.id, initial.id);
    expect(retried.revision, 2);
    expect(retried.command.name, 'External name');
    expect(retried.command.baseUrl, 'http://changed.invalid');
    expect(retried.command.initialBillingKind, isNull);
    expect(_limits(retried.command), {
      'alpha': 100,
      'beta': 400,
      _orphan.modelId: 777,
    });
    final afterFirst = external.withAutoCompactLimit(
      AccountModelAutoCompactView(modelId: _alpha.modelId, overrideLimit: 100),
    );
    retried.complete(3, afterFirst);
    await first;
    await calls.moveNext();
    expect(client.mutations.latest('settings:$alphaKey')?.id, latest.id);
    expect(
      client.settings.state.commands[alphaKey]?.isPending,
      isTrue,
      reason: 'old ACK cannot clear newer intent',
    );
    expect(
      client
          .settings
          .state
          .canonical!
          .accounts
          .single
          .autoCompactLimits['alpha']!
          .overrideLimit,
      100,
      reason: 'no optimistic canonical',
    );
    final next = calls.current;
    expect(next.revision, 3);
    expect(_limits(next.command), {
      'alpha': 150,
      'beta': 400,
      _orphan.modelId: 777,
    });
    final afterSecond = external.withAutoCompactLimit(
      AccountModelAutoCompactView(modelId: _alpha.modelId, overrideLimit: 150),
    );
    next.complete(4, afterSecond);
    await second;
    await calls.moveNext();
    final restoring = calls.current;
    expect(restoring.revision, 4);
    expect(_limits(restoring.command), {'alpha': 150, _orphan.modelId: 777});
    var joined = false;
    final closing = commands.close().then((_) => joined = true);
    await Future<void>.delayed(Duration.zero);
    expect(
      joined,
      isFalse,
      reason: 'settings owner waits for the in-flight response',
    );
    restoring.complete(
      5,
      afterSecond.withAutoCompactLimit(
        AccountModelAutoCompactView(modelId: _beta.modelId),
      ),
    );
    await reset;
    await closing;
    expect(joined, isTrue, reason: 'Client settings owner joins queued writes');
    expect(transport.refreshes, 1);
  });

  test('old failed intent cannot erase newer pending edit; latest failure can be explicitly retried', () async {
    final transport = _Transport();
    final client = _client(transport);
    final calls = StreamIterator(transport.calls.stream);
    addTearDown(calls.cancel);
    final commands = client.settingsCommands;
    final first = commands.setModelAutoCompactLimit('fixture', 'alpha', 100);
    final firstFailure = expectLater(first, throwsA(isA<StudioFailure>()));
    await calls.moveNext();
    final older = calls.current;
    final second = commands.setModelAutoCompactLimit('fixture', 'alpha', 150);
    final secondFailure = expectLater(second, throwsA(isA<StudioFailure>()));
    const key = 'model-auto-compact:7:fixture:alpha';
    const error = StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'Rejected by owner',
      retryable: false,
      correlationId: 'fixture',
    );
    older.reply.completeError(error);
    await firstFailure;
    await calls.moveNext();
    expect(client.settings.state.commands[key]?.isPending, isTrue);
    calls.current.reply.completeError(error);
    await secondFailure;
    expect(client.settings.state.commands[key]?.phase, CommandPhase.failed);
    final retry = commands.setModelAutoCompactLimit('fixture', 'alpha', 150);
    await calls.moveNext();
    expect(_limits(calls.current.command)['alpha'], 150);
    calls.current.complete(
      2,
      _account.withAutoCompactLimit(
        AccountModelAutoCompactView(
          modelId: _alpha.modelId,
          overrideLimit: 150,
        ),
      ),
    );
    await retry;
    expect(client.settings.state.commands.containsKey(key), isFalse);
  });
}
