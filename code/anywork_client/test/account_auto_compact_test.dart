import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

const _alpha = AccountModelView(
  modelId: 'alpha',
  displayName: 'Alpha',
  reasoningEfforts: [],
  contextWindow: 1000,
  maxContextWindow: 4000,
  autoCompactTokenLimit: 200,
);
const _beta = AccountModelView(
  modelId: 'beta',
  displayName: 'Beta',
  reasoningEfforts: [],
  maxContextWindow: 2000,
);
const _orphan = AccountModelAutoCompactView(
  modelId: 'temporarily-unlisted',
  defaultLimit: null,
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
    'alpha': AccountModelAutoCompactView.forModel(_alpha),
    'beta': AccountModelAutoCompactView.forModel(_beta).withOverride(250),
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
    'catalog revisions reproject limits while preserving stored overrides',
    () {
      final configured = _account.withAutoCompactLimit(
        AccountModelAutoCompactView.forModel(_alpha).withOverride(150),
      );
      var state = mergeSettingsProjection(
        const SettingsProjectionState(),
        _snapshot(1, configured),
      );

      AccountSettingsView currentAccount() => state.canonical!.accounts.single;
      AccountModelAutoCompactView alphaLimit() =>
          currentAccount().autoCompactLimits['alpha']!;
      SettingsStateSnapshot catalogFrame(
        int revision,
        List<AccountModelView> models,
      ) {
        return SettingsStateSnapshot(
          revision: 999,
          modelCatalogRevision: revision,
          accounts: [
            _account.copyWith(
              name: 'Catalog metadata',
              models: models,
              autoCompactLimits: {
                'alpha': AccountModelAutoCompactView.forModel(_alpha)
                    .withOverride(999),
              },
            ),
          ],
        );
      }

      const enlarged = AccountModelView(
        modelId: 'alpha',
        displayName: 'Alpha',
        reasoningEfforts: [],
        contextWindow: 2000,
        maxContextWindow: 4000,
      );
      state = mergeSettingsProjection(
        state,
        catalogFrame(2, [enlarged, _beta]),
        scope: SettingsMergeScope.catalogOnly,
      );
      expect(state.settingsRevision, 1);
      expect(currentAccount().name, 'Fixture');
      expect(alphaLimit().defaultLimit, 1800);
      expect(alphaLimit().safeLimit, 1800);
      expect(alphaLimit().overrideLimit, 150);
      expect(alphaLimit().effectiveLimit, 150);

      const unknownWithTemplate = AccountModelView(
        modelId: 'alpha',
        displayName: 'Alpha',
        reasoningEfforts: [],
        autoCompactTokenLimit: 150,
      );
      state = mergeSettingsProjection(
        state,
        catalogFrame(3, [unknownWithTemplate, _beta]),
        scope: SettingsMergeScope.catalogOnly,
      );
      expect(alphaLimit().defaultLimit, 150);
      expect(
        alphaLimit().overrideLimit,
        150,
        reason:
            'read-only projection must not consume an equal stored override',
      );
      expect(alphaLimit().safeLimit, isNull);
      expect(alphaLimit().effectiveLimit, isNull);

      state = mergeSettingsProjection(
        state,
        catalogFrame(4, [_beta]),
        scope: SettingsMergeScope.catalogOnly,
      );
      expect(alphaLimit().overrideLimit, 150);
      expect(alphaLimit().defaultLimit, isNull);
      expect(alphaLimit().safeLimit, isNull);
      expect(alphaLimit().effectiveLimit, isNull);
      expect(
        currentAccount().autoCompactLimits[_orphan.modelId]?.overrideLimit,
        777,
      );

      const restored = AccountModelView(
        modelId: 'alpha',
        displayName: 'Alpha',
        reasoningEfforts: [],
        contextWindow: 1000,
      );
      state = mergeSettingsProjection(
        state,
        catalogFrame(5, [restored, _beta]),
        scope: SettingsMergeScope.catalogOnly,
      );
      expect(alphaLimit().defaultLimit, 900);
      expect(alphaLimit().overrideLimit, 150);
      expect(alphaLimit().effectiveLimit, 150);
      expect(_limits(AccountCommandBuilder.buildAccount(currentAccount())), {
        'alpha': 150,
        'beta': 250,
        _orphan.modelId: 777,
      });

      final configReply = _snapshot(
        2,
        configured.withAutoCompactLimit(
          AccountModelAutoCompactView.forModel(_alpha).withOverride(300),
        ),
      );
      state = mergeSettingsProjection(
        state,
        configReply,
        scope: SettingsMergeScope.configOnly,
      );
      expect(state.modelCatalogRevision, 5);
      expect(
        alphaLimit().defaultLimit,
        900,
        reason: 'config replies retain the newer catalog metadata',
      );
      expect(alphaLimit().overrideLimit, 300);
      expect(alphaLimit().effectiveLimit, 300);
      expect(
        mergeSettingsProjection(state, _snapshot(1, configured)),
        same(state),
        reason: 'older combined snapshots cannot roll either watermark back',
      );
    },
  );

  test('model metadata derives nullable defaults and payload stores only complete overrides', () {
    final template = AccountModelAutoCompactView.forModel(_alpha);
    final derived = AccountModelAutoCompactView.forModel(_beta);
    expect(template.defaultLimit, 200);
    expect(template.safeLimit, 900, reason: 'current window precedes maximum');
    expect(derived.defaultLimit, 1800, reason: 'maximum is a fallback');
    expect(template.withOverride(1500).effectiveLimit, 900);
    expect(template.withOverride(200).overrideLimit, isNull);
    expect(derived.withOverride(null).effectiveLimit, 1800);
    for (final capacity in [null, 0, 1]) {
      final model = AccountModelView(
        modelId: 'unknown',
        displayName: '',
        reasoningEfforts: const [],
        contextWindow: capacity,
      );
      final unknown = AccountModelAutoCompactView.forModel(model);
      expect(unknown.defaultLimit, isNull);
      expect(unknown.withOverride(15).effectiveLimit, isNull);
      final declared = AccountModelAutoCompactView.forModel(
        model.copyWith(autoCompactTokenLimit: 20),
      );
      expect(declared.defaultLimit, 20);
      expect(declared.effectiveLimit, isNull);
    }
    expect(
      AccountModelAutoCompactView.safeLimitForContext(9000000000000000001),
      8100000000000000000,
    );
    final command = AccountCommandBuilder.buildAccount(_account);
    expect(_limits(command), {'beta': 250, _orphan.modelId: 777});
    expect(_account.autoCompactLimits['alpha']?.overrideLimit, isNull);
    final joined = accountWithCatalogMetadata(
      _account.copyWith(
        models: [
          _alpha.copyWith(origin: ModelOrigin.manual, contextWindow: 1000),
          _beta,
        ],
      ),
      const AccountCatalogView.empty(),
    );
    expect(joined.customModels.map((model) => model.modelId), ['alpha']);
    expect(joined.onlineModels, isEmpty);
    expect(
      joined.customModels.single.autoCompactTokenLimit,
      _alpha.autoCompactTokenLimit,
      reason: 'origin grouping does not drop catalog token templates',
    );
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
          pricingEnabled: true,
        )
        .withAutoCompactLimit(
          AccountModelAutoCompactView.forModel(_beta).withOverride(400),
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
    expect(retried.command.pricingEnabled, isTrue);
    expect(_limits(retried.command), {
      'alpha': 100,
      'beta': 400,
      _orphan.modelId: 777,
    });
    final afterFirst = external.withAutoCompactLimit(
      AccountModelAutoCompactView.forModel(_alpha).withOverride(100),
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
      AccountModelAutoCompactView.forModel(_alpha).withOverride(150),
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
        AccountModelAutoCompactView.forModel(_beta),
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
        AccountModelAutoCompactView.forModel(_alpha).withOverride(150),
      ),
    );
    await retry;
    expect(client.settings.state.commands.containsKey(key), isFalse);
  });
}
