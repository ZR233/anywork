import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models.dart' show BillingKind;
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/configuration_command_fixture.dart';
import 'support/configuration_fixture.dart';

/// Automatic-compaction overrides are native-canonical values with their own
/// identity per model. The layered client does not merge settings/catalog
/// watermarks or reconstruct backend context policy; it forwards the explicit
/// intent and adopts exactly the projection Rust publishes.
AccountConfiguration _account({
  List<CustomModelConfiguration>? customModels,
  List<ModelAutoCompact> limits = const [
    ModelAutoCompact(modelId: 'beta', overrideLimit: 250),
    ModelAutoCompact(modelId: 'temporarily-unlisted', overrideLimit: 777),
  ],
  String name = 'Fixture',
  BillingKind billingKind = BillingKind.metered,
  BillingKind? billingKindOverride,
}) => AccountConfiguration(
  accountId: 'fixture',
  templateId: 'template-a',
  protocol: 'openai',
  name: name,
  baseUrl: 'http://fixture.invalid',
  hasBearerToken: true,
  bearerTokenEnv: null,
  billingKind: billingKind,
  billingKindOverride: billingKindOverride,
  disabledModels: const [],
  usageQueryRevision: 7,
  catalogId: 'catalog',
  customModels:
      customModels ??
      [customModel('alpha', contextWindow: 1000), customModel('beta')],
  modelConnectionModes: const [],
  modelAutoCompactLimits: limits,
);

Map<String, int?> _limits(AccountEdit edit) => {
  for (final change in edit.autoCompactLimits)
    change.modelId: change.overrideLimit,
};
Map<String, int?> _dispatchedLimits(AccountSettingsUpdate update) => {
  for (final item in update.modelAutoCompactLimits) item.modelId: item.limit,
};

const _nativeRefusal = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The scripted native boundary declined this prepared write',
  retryable: false,
  correlationId: 'auto-compact-native-refusal',
);

Future<ConfigurationFixture> _fixture({AccountConfiguration? account}) async {
  final fixture = ConfigurationFixture();
  await fixture.establish(account ?? _account());
  addTearDown(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final reports = await Future.wait([
      fixture.repository.close(deadline: deadline),
      fixture.models.close(deadline: deadline),
    ]);
    expect(reports.expand((CloseReport report) => report.unresolved), isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });
  return fixture;
}

Future<void> _reject(
  RecordedConfigurationCall<UpdateAccountRequest> call,
  OperationTicket<Unit> ticket,
) async {
  await call.native.resultRead(0);
  call.native
      .resultAt(0)
      .reply
      .completeError(
        const CommandDispatchFailure.rejected(failure: _nativeRefusal),
      );
  final result = await ticket.result;
  expect(result, isA<RejectedCommandResult<Unit>>());
  final closing = await call.native.closed(0);
  closing.reply.complete(
    FeedCloseReport(
      feedId: call.native.callId,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
}

void main() {
  test('one projection carries shared metadata across accounts and an older response never rolls it back', () async {
    final fixture = await _fixture();
    final canonical = await fixture.repository.loadAccount('fixture');
    expect(canonical.customModels.first.contextWindow, 1000);

    // Both accounts' shared model metadata arrives with one native projection.
    await fixture.port.publishAccount(
      2,
      _account(
        name: 'catalog',
        customModels: [
          customModel('alpha', contextWindow: 2000),
          customModel('shared', contextWindow: 2000),
        ],
      ),
    );
    final updated = await fixture.repository.loadAccount('fixture');
    expect(updated.name, 'catalog');
    expect(
      updated.customModels.map(
        (CustomModelConfiguration model) => model.contextWindow,
      ),
      [2000, 2000],
    );
    // The projection the client holds is the native one, not a local merge of
    // an older settings response: the guard against a non-advancing or older
    // product frame lives in the shared feed owner (see
    // bots_client_lifecycle_test.dart "canonical bots snapshot rejects older
    // revisions and late owner frames").
    expect(fixture.repository.state.value.projection.stamp!.revision, 2);
  });

  test('override limits and catalog context stay independent facts', () async {
    final fixture = await _fixture(
      account: _account(
        limits: const [ModelAutoCompact(modelId: 'alpha', overrideLimit: 150)],
      ),
    );
    Future<AccountConfiguration> current() =>
        fixture.repository.loadAccount('fixture');

    expect((await current()).modelAutoCompactLimits, const [
      ModelAutoCompact(modelId: 'alpha', overrideLimit: 150),
    ]);
    // The explicit override never rewrites the backend's context window.
    expect((await current()).customModels.first.contextWindow, 1000);

    await fixture.port.publishAccount(
      2,
      _account(
        limits: const [ModelAutoCompact(modelId: 'alpha', overrideLimit: 150)],
        customModels: [customModel('alpha'), customModel('beta')],
      ),
    );
    expect((await current()).modelAutoCompactLimits, const [
      ModelAutoCompact(modelId: 'alpha', overrideLimit: 150),
    ]);
    expect(
      (await current()).customModels.first.contextWindow,
      isNull,
      reason: 'backend policy is not reconstructed from capacity or override',
    );

    // A withdrawn catalog member keeps its explicit override.
    await fixture.port.publishAccount(
      3,
      _account(
        limits: const [
          ModelAutoCompact(modelId: 'alpha', overrideLimit: 150),
          ModelAutoCompact(modelId: 'temporarily-unlisted', overrideLimit: 777),
        ],
        customModels: [customModel('beta')],
      ),
    );
    final limits = {
      for (final item in (await current()).modelAutoCompactLimits)
        item.modelId: item.overrideLimit,
    };
    expect(limits, {'alpha': 150, 'temporarily-unlisted': 777});
  });

  test('payload preserves raw intent and unknown manual capacities', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.saveAccount(
      AccountEdit(
        accountId: 'fixture',
        create: false,
        templateId: const FieldEdit.keep(),
        protocol: const FieldEdit.keep(),
        name: const FieldEdit.keep(),
        baseUrl: const FieldEdit.keep(),
        secret: const AccountSecretUpdate.preserve(),
        initialBillingKind: null,
        rebuildModelConfiguration: false,
        customModels: const [
          CustomModelChange.upsert(
            originalModelId: null,
            value: AccountModelUpdate(
              modelId: 'unknown',
              displayName: '',
              wireApi: 'chat',
              contextWindow: null,
              maxOutputTokens: null,
            ),
          ),
        ],
        connections: const [],
        // An override equal to a backend default is still raw intent: only the
        // backend normalizes it.
        autoCompactLimits: const [
          ModelLimitChange(modelId: 'alpha', overrideLimit: 200),
        ],
      ),
    );
    final call = await fixture.port.saved(0);
    final update = call.request.account;
    expect(_dispatchedLimits(update), {
      'beta': 250,
      'temporarily-unlisted': 777,
      'alpha': 200,
    });
    final added = update.customModels.singleWhere(
      (AccountModelUpdate model) => model.modelId == 'unknown',
    );
    // Unknown manual capacities stay null; no capacity is synthesized.
    expect(added.contextWindow, isNull);
    expect(added.maxOutputTokens, isNull);
    await _reject(call, ticket);
    // A refused write leaves the canonical overrides untouched.
    final retained = await fixture.repository.loadAccount('fixture');
    expect(
      {
        for (final item in retained.modelAutoCompactLimits)
          item.modelId: item.overrideLimit,
      },
      {'beta': 250, 'temporarily-unlisted': 777},
    );
  });

  test(
    'an explicit null removes one override without dropping siblings',
    () async {
      final fixture = await _fixture();
      final intent = AccountEdit(
        accountId: 'fixture',
        create: false,
        templateId: const FieldEdit.keep(),
        protocol: const FieldEdit.keep(),
        name: const FieldEdit.keep(),
        baseUrl: const FieldEdit.keep(),
        secret: const AccountSecretUpdate.preserve(),
        initialBillingKind: null,
        rebuildModelConfiguration: false,
        customModels: const [],
        connections: const [],
        autoCompactLimits: const [
          ModelLimitChange(modelId: 'beta', overrideLimit: null),
        ],
      );
      expect(_limits(intent), {'beta': null});
      final ticket = fixture.repository.saveAccount(intent);
      final call = await fixture.port.saved(0);
      expect(_dispatchedLimits(call.request.account), {
        'temporarily-unlisted': 777,
      });
      await _reject(call, ticket);
    },
  );

  test('a non-positive override is refused before dispatch', () async {
    final fixture = await _fixture();
    AccountEdit intent(int? limit) => AccountEdit(
      accountId: 'fixture',
      create: false,
      templateId: const FieldEdit.keep(),
      protocol: const FieldEdit.keep(),
      name: const FieldEdit.keep(),
      baseUrl: const FieldEdit.keep(),
      secret: const AccountSecretUpdate.preserve(),
      initialBillingKind: null,
      rebuildModelConfiguration: false,
      customModels: const [],
      connections: const [],
      autoCompactLimits: [
        ModelLimitChange(modelId: 'alpha', overrideLimit: limit),
      ],
    );
    for (final limit in [0, -1]) {
      expect(
        () => fixture.repository.saveAccount(intent(limit)),
        throwsA(
          isA<StudioFailure>().having(
            (StudioFailure error) => error.code,
            'code',
            StudioFailureCode.invalidArgument,
          ),
        ),
      );
    }
    expect(fixture.port.saves, isEmpty);
  });

  test('an external billing rewrite is adopted and an unrelated limit edit never replays it', () async {
    final fixture = await _fixture();
    // Another writer (or a native settings refresh) turned the account into an
    // explicit no-charge one between the two writes.
    await fixture.port.publishAccount(
      2,
      _account(
        billingKind: BillingKind.noCharge,
        billingKindOverride: BillingKind.noCharge,
      ),
    );
    var current = await fixture.repository.loadAccount('fixture');
    expect(current.billingKind, BillingKind.noCharge);
    expect(current.billingKindOverride, BillingKind.noCharge);

    // An auto-compact edit is not billing intent: the prepared account write
    // carries no category at all, so it cannot restore a stale inference or
    // clear the explicit no-charge the native surface reports.
    final ticket = fixture.repository.saveAccount(
      accountEdit(
        limits: const [ModelLimitChange(modelId: 'alpha', overrideLimit: 100)],
      ),
    );
    final call = await fixture.port.saved(0);
    expect(call.request.account.accountId, 'fixture');
    expect(_dispatchedLimits(call.request.account)['alpha'], 100);
    expect(
      fixture.port.billingChanges,
      isEmpty,
      reason: 'an ordinary edit must not replay billing intent',
    );
    await _reject(call, ticket);

    current = await fixture.repository.loadAccount('fixture');
    expect(current.billingKind, BillingKind.noCharge);
    expect(current.billingKindOverride, BillingKind.noCharge);
    expect(current.modelAutoCompactLimits, const [
      ModelAutoCompact(modelId: 'beta', overrideLimit: 250),
      ModelAutoCompact(modelId: 'temporarily-unlisted', overrideLimit: 777),
    ]);
  });
}
