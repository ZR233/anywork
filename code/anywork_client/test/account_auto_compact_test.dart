import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';

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
    'alpha': const AccountModelAutoCompactView(modelId: 'alpha'),
    'beta': const AccountModelAutoCompactView(
      modelId: 'beta',
      overrideLimit: 250,
    ),
    _orphan.modelId: _orphan,
  },
);
const _identity = NativeAccountIdentity('fixture');
SettingsStateSnapshot _snapshot(
  int revision,
  AccountSettingsView account, {
  int catalog = 0,
}) => SettingsStateSnapshot(
  revision: revision,
  modelCatalogRevision: catalog,
  accounts: [account],
);

class _SaveCall {
  _SaveCall(this.revision, this.identity, this.intent, this.id);
  final int revision;
  final AccountModelIdentity identity;
  final AutoCompactIntent intent;
  final OperationId id;
  final reply = Completer<SettingsCommandReply>();
  void complete(int revision, AccountSettingsView account) => reply.complete(
    accountReply(
      snapshot: _snapshot(revision, account),
      receipt: StudioCommandReceipt(
        operationId: id,
        disposition: CommitDisposition.applied,
        targets: [testStamp('settings', revision, epoch: 'fixture-owner')],
        effect: EffectPoint.immediate,
        effective: true,
        durable: true,
      ),
    ),
  );
}

class _Transport extends AccountsTestTransport {
  final calls = StreamController<_SaveCall>.broadcast();
  SettingsStateSnapshot? refreshed;
  int refreshes = 0;
  CreateAccountCommand? creation;
  @override
  Future<SettingsStateSnapshot> readSettingsState() async {
    refreshes++;
    return refreshed!;
  }

  @override
  Future<SettingsCommandReply> setAccountModelAutoCompact(
    int revision,
    AccountModelIdentity identity,
    AutoCompactIntent intent, {
    required OperationId operationId,
  }) {
    final call = _SaveCall(revision, identity, intent, operationId);
    calls.add(call);
    return call.reply.future;
  }

  @override
  Future<SettingsCommandReply> createAccount(
    int revision,
    CreateAccountCommand command, {
    required OperationId operationId,
  }) async {
    creation = command;
    return accountReply(
      snapshot: SettingsStateSnapshot(
        revision: revision + 1,
        accounts: [
          _account,
          AccountSettingsView(
            id: command.identity.accountId,
            name: command.name,
            protocol: command.protocol,
            baseUrl: command.baseUrl,
            defaultModelId: '',
            status: 'ready',
            usageLabel: '',
            models: [
              for (final model in command.customModels)
                AccountModelView(
                  modelId: model.modelId,
                  displayName: model.displayName,
                  reasoningEfforts: const [],
                  origin: ModelOrigin.manual,
                  contextWindow: model.contextWindow,
                  maxOutputTokens: model.maxOutputTokens,
                ),
            ],
          ),
        ],
      ),
      receipt: StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: [testStamp('settings', revision + 1, epoch: epoch)],
        effect: EffectPoint.futureSession,
        effective: false,
        durable: true,
      ),
    );
  }
}

AccountsTestRuntime _client(_Transport transport) {
  transport.epoch = 'fixture-owner';
  final runtime = AccountsTestRuntime(transport, clientId: 'fixture-client');
  runtime.seed(_snapshot(1, _account));
  addTearDown(runtime.close);
  addTearDown(transport.calls.close);
  return runtime;
}

AccountModelConfiguration _config(AccountsTestRuntime runtime) =>
    runtime.domains.models.state.value.configurations[_identity]!.value!;
AccountModelCatalog _catalog(AccountsTestRuntime runtime) =>
    runtime.domains.models.state.value.accounts[_identity]!.value!;
Future<OperationState> _set(
  AccountsTestRuntime runtime,
  String model,
  int? limit,
) => runtime.domains.models.setAutoCompact(
  modelIdentity('fixture', model),
  limit == null
      ? const AutoCompactIntent.clear()
      : AutoCompactIntent.set(limit),
);

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
    final runtime = _client(_Transport());
    runtime.seed(frame(1, 1, 1000));
    runtime.domains.acceptCatalog(frame(1, 2, 2000), 'fixture-owner');
    List<int?> windows() => [
      for (final id in ['first', 'second'])
        runtime
            .domains
            .models
            .state
            .value
            .accounts[NativeAccountIdentity(id)]!
            .value!
            .models
            .single
            .contextWindow,
    ];
    expect(windows(), [2000, 2000]);
    runtime.seed(frame(2, 1, 1000));
    expect(
      runtime
          .domains
          .models
          .state
          .value
          .configurations[const NativeAccountIdentity('first')]!
          .stamp!
          .revision,
      2,
    );
    expect(
      runtime
          .domains
          .models
          .state
          .value
          .accounts[const NativeAccountIdentity('first')]!
          .stamp!
          .revision,
      2,
    );
    expect(windows(), [2000, 2000]);
    final state = runtime.domains.models.state.value;
    runtime.seed(frame(1, 1, 1000));
    expect(runtime.domains.models.state.value, same(state));
  });

  test(
    'catalog policy is passed through unchanged across independent watermarks',
    () {
      final runtime = _client(_Transport());
      final configured = _account.withAutoCompactLimit(
        const AccountModelAutoCompactView(modelId: 'alpha', overrideLimit: 150),
      );
      runtime.seed(_snapshot(2, configured));
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
      runtime.domains.acceptCatalog(
        frame(2, [
          _alpha.copyWith(contextWindow: 2000, context: backendPolicy),
          _beta,
        ]),
        'fixture-owner',
      );
      expect(
        runtime
            .domains
            .models
            .state
            .value
            .configurations[_identity]!
            .stamp!
            .revision,
        2,
      );
      expect(
        (runtime.domains.accounts.details(_identity).value.value
                as NativeAccountDetails)
            .name,
        'Fixture',
      );
      expect(_config(runtime).autoCompactLimits['alpha'], 150);
      expect(
        _catalog(runtime).model('alpha')!.context,
        same(backendPolicy),
        reason:
            'The backend policy is not reconstructed from capacity or override',
      );
      runtime.domains.acceptCatalog(
        frame(3, [
          const AccountModelView(
            modelId: 'alpha',
            displayName: '',
            reasoningEfforts: [],
          ),
          _beta,
        ]),
        'fixture-owner',
      );
      expect(_config(runtime).autoCompactLimits['alpha'], 150);
      expect(
        _catalog(runtime).model('alpha')!.context.autoCompactLimit,
        isNull,
      );
      runtime.domains.acceptCatalog(frame(4, [_beta]), 'fixture-owner');
      expect(_config(runtime).autoCompactLimits['alpha'], 150);
      expect(_config(runtime).autoCompactLimits[_orphan.modelId], 777);
      runtime.domains.acceptCatalog(
        frame(5, [_alpha.copyWith(context: backendPolicy), _beta]),
        'fixture-owner',
      );
      runtime.seed(
        _snapshot(
          3,
          configured.withAutoCompactLimit(
            const AccountModelAutoCompactView(
              modelId: 'alpha',
              overrideLimit: 300,
            ),
          ),
        ),
      );
      expect(
        runtime.domains.models.state.value.accounts[_identity]!.stamp!.revision,
        5,
      );
      expect(_config(runtime).autoCompactLimits['alpha'], 300);
      expect(
        _catalog(runtime).model('alpha')!.context,
        same(backendPolicy),
        reason:
            'Old configuration replies cannot roll back final catalog policy',
      );
      expect(_config(runtime).autoCompactLimits, {
        'alpha': 300,
        'beta': 250,
        _orphan.modelId: 777,
      });
      final state = runtime.domains.models.state.value;
      runtime.seed(_snapshot(1, configured));
      expect(runtime.domains.models.state.value, same(state));
    },
  );

  test('payload preserves raw intent and unknown manual capacities', () async {
    final transport = _Transport();
    final runtime = _client(transport);
    final calls = StreamIterator(transport.calls.stream);
    addTearDown(calls.cancel);
    final saving = _set(runtime, 'alpha', 200);
    await calls.moveNext();
    expect(
      (calls.current.intent as SetAutoCompactLimit).limit,
      200,
      reason: 'Only the backend normalizes an equal default',
    );
    calls.current.complete(
      2,
      _account.withAutoCompactLimit(
        const AccountModelAutoCompactView(modelId: 'alpha', overrideLimit: 200),
      ),
    );
    await saving;
    expect(_config(runtime).autoCompactLimits, {
      'alpha': 200,
      'beta': 250,
      _orphan.modelId: 777,
    });
    await runtime.domains.accounts.create(
      CreateAccountCommand(
        identity: const NativeAccountIdentity('manual'),
        name: 'Manual',
        protocol: 'open_ai_compatible',
        baseUrl: 'https://example.invalid',
        secret: const AccountSecretCommand.preserve(),
        customModels: const [
          AccountModelCommand(
            modelId: 'unknown',
            displayName: '',
            wireApi: 'chat_completions',
            contextWindow: null,
            maxOutputTokens: null,
          ),
        ],
      ),
    );
    expect(transport.creation!.customModels.single.contextWindow, isNull);
    expect(transport.creation!.customModels.single.maxOutputTokens, isNull);
  });

  test('inline narrow intents replay at lane entry and CAS retry without dropping siblings or unavailable overrides', () async {
    final transport = _Transport();
    final runtime = _client(transport);
    final calls = StreamIterator(transport.calls.stream);
    addTearDown(calls.cancel);
    final first = _set(runtime, 'alpha', 100);
    await calls.moveNext();
    final initial = calls.current;
    expect(initial.revision, 1);
    expect(initial.identity.accountId, 'fixture');
    expect(initial.identity.modelId, 'alpha');
    final second = _set(runtime, 'alpha', 150);
    final reset = _set(runtime, 'beta', null);
    const key = 'model:compact:7:fixture:alpha';
    final latest = runtime.board.latest(key)!;
    final external = _account
        .copyWith(
          name: 'External name',
          baseUrl: 'http://changed.invalid',
          billingKind: BillingKind.noCharge,
          billingKindOverride: BillingKind.noCharge,
        )
        .withAutoCompactLimit(
          const AccountModelAutoCompactView(
            modelId: 'beta',
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
    expect(retried.identity, initial.identity);
    expect((retried.intent as SetAutoCompactLimit).limit, 100);
    expect(
      (runtime.domains.accounts.details(_identity).value.value
              as NativeAccountDetails)
          .name,
      'External name',
    );
    expect(
      (runtime.domains.accounts.details(_identity).value.value
              as NativeAccountDetails)
          .baseUrl,
      'http://changed.invalid',
    );
    expect(_config(runtime).autoCompactLimits, {
      'beta': 400,
      _orphan.modelId: 777,
    });
    final afterFirst = external.withAutoCompactLimit(
      const AccountModelAutoCompactView(modelId: 'alpha', overrideLimit: 100),
    );
    retried.complete(3, afterFirst);
    await first;
    expect(
      runtime.domains.accounts.state.value.account(_identity)!.billingKind,
      BillingKind.noCharge,
      reason: 'Billing is observed from summaries, not inferred from a target detail watermark',
    );
    await calls.moveNext();
    expect(runtime.board.latest(key)?.id, latest.id);
    expect(
      runtime.board.latest(key)!.state.value.isPending,
      isTrue,
      reason: 'Old ACK cannot clear newer intent',
    );
    expect(
      _config(runtime).autoCompactLimits['alpha'],
      100,
      reason: 'There is no optimistic canonical',
    );
    final next = calls.current;
    expect(next.revision, 3);
    expect((next.intent as SetAutoCompactLimit).limit, 150);
    expect(_config(runtime).autoCompactLimits['beta'], 400);
    expect(_config(runtime).autoCompactLimits[_orphan.modelId], 777);
    final afterSecond = external.withAutoCompactLimit(
      const AccountModelAutoCompactView(modelId: 'alpha', overrideLimit: 150),
    );
    next.complete(4, afterSecond);
    await second;
    await calls.moveNext();
    final restoring = calls.current;
    expect(restoring.revision, 4);
    expect(restoring.identity.modelId, 'beta');
    expect(restoring.intent, isA<ClearAutoCompactLimit>());
    var joined = false;
    final closing = runtime.coordinator.close().then((_) => joined = true);
    await Future<void>.value();
    expect(
      joined,
      isFalse,
      reason: 'The settings owner waits for its in-flight response',
    );
    restoring.complete(
      5,
      afterSecond.withAutoCompactLimit(
        const AccountModelAutoCompactView(modelId: 'beta'),
      ),
    );
    await reset;
    await closing;
    expect(joined, isTrue);
    expect(_config(runtime).autoCompactLimits, {
      'alpha': 150,
      _orphan.modelId: 777,
    });
    expect(
      transport.refreshes,
      2,
      reason: 'CAS retry refreshes the target settings and catalog, not an aggregate bootstrap',
    );
  });

  test('old failed intent cannot erase newer pending edit; latest failure can be explicitly retried', () async {
    final transport = _Transport();
    final runtime = _client(transport);
    final calls = StreamIterator(transport.calls.stream);
    addTearDown(calls.cancel);
    final first = _set(runtime, 'alpha', 100);
    final firstFailure = expectLater(first, throwsA(isA<StudioFailure>()));
    await calls.moveNext();
    final older = calls.current;
    final second = _set(runtime, 'alpha', 150);
    final secondFailure = expectLater(second, throwsA(isA<StudioFailure>()));
    const key = 'model:compact:7:fixture:alpha';
    const error = StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'Rejected by owner',
      retryable: false,
      correlationId: 'fixture',
    );
    older.reply.completeError(error);
    await firstFailure;
    await calls.moveNext();
    expect(runtime.board.latest(key)!.state.value.isPending, isTrue);
    calls.current.reply.completeError(error);
    await secondFailure;
    expect(
      runtime.board.latest(key)!.state.value.phase,
      OperationPhase.rejected,
    );
    final retry = _set(runtime, 'alpha', 150);
    await calls.moveNext();
    expect((calls.current.intent as SetAutoCompactLimit).limit, 150);
    calls.current.complete(
      2,
      _account.withAutoCompactLimit(
        const AccountModelAutoCompactView(modelId: 'alpha', overrideLimit: 150),
      ),
    );
    await retry;
    expect(runtime.board.latest(key)!.state.value.observed, isTrue);
    expect(runtime.board.latest(key)!.state.value.failurePhase, isNull);
  });
}
