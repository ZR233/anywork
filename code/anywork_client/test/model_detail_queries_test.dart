import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';

const _a = DelegationModelKey(accountId: 'a', modelId: 'shared');
const _b = DelegationModelKey(accountId: 'b', modelId: 'shared');
const _model = AccountModelView(
  modelId: 'shared',
  displayName: 'Shared',
  reasoningEfforts: [],
);

SettingsStateSnapshot _settings(int revision) => SettingsStateSnapshot(
  revision: revision,
  modelCatalogRevision: revision,
  accounts: [
    for (final id in ['a', 'b'])
      AccountSettingsView(
        id: id,
        name: id,
        baseUrl: '',
        defaultModelId: 'shared',
        models: const [_model],
        status: '',
        usageLabel: '',
      ),
  ],
);

DelegationModelDetail _detail(DelegationModelKey key) => DelegationModelDetail(
  key: key,
  accountName: key.accountId,
  descriptor: _model,
  available: true,
  billingKind: BillingKind.unknown,
  performance: const LocalModelPerformanceSummary(
    sampleCount: 55,
    ttftSampleCount: 31,
    tokensPerSecond: 12.5,
    averageTtftMillis: 250,
  ),
  evaluations: const AgentEvaluationSummary(
    window: 10,
    ratedSamples: 0,
    passed: 0,
    failed: 0,
    notRated: 0,
  ),
  recentEvaluations: const [],
);

class _Transport extends AccountsTestTransport {
  final calls = <(DelegationModelKey, Completer<DelegationModelDetail>)>[];
  @override
  Future<DelegationModelDetail> getDelegationModel(DelegationModelKey key) {
    final reply = Completer<DelegationModelDetail>();
    calls.add((key, reply));
    return reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}

AccountsTestRuntime _client(_Transport transport) {
  final runtime = AccountsTestRuntime(transport, clientId: 'details');
  runtime.seed(_settings(1));
  addTearDown(runtime.close);
  return runtime;
}

void main() {
  test('exact account/model queries dedupe and never substitute stale or other-account details', () async {
    final transport = _Transport();
    final client = _client(transport);
    final owner = client.domains.models;
    final a = owner.performance(modelIdentity(_a.accountId, _a.modelId));
    expect(
      identical(owner.performance(modelIdentity(_a.accountId, _a.modelId)), a),
      isTrue,
    );
    final b = owner.performance(modelIdentity(_b.accountId, _b.modelId));
    expect(transport.calls.map((call) => call.$1), [_a, _b]);
    transport.calls[1].$2.complete(_detail(_b));
    expect((await b).key, _b);
    expect(transport.calls[0].$2.isCompleted, isFalse);
    client.seed(_settings(2));
    final stale = expectLater(
      a,
      throwsA(
        isA<StudioFailure>().having(
          (e) => e.code,
          'identity failure',
          StudioFailureCode.staleRevision,
        ),
      ),
    );
    transport.calls[0].$2.complete(_detail(_a));
    await stale;
    expect(
      owner.state.value.model(modelIdentity('a', 'shared'))?.displayName,
      'Shared',
    );
    final wrong = owner.performance(modelIdentity('a', 'shared'));
    final rejected = expectLater(
      wrong,
      throwsA(
        isA<StudioFailure>().having(
          (e) => e.code,
          'code',
          StudioFailureCode.staleRevision,
        ),
      ),
    );
    transport.calls[2].$2.complete(_detail(_b));
    await rejected;
    expect(
      owner.state.value.model(modelIdentity('a', 'shared'))?.displayName,
      'Shared',
    );
    expect(
      owner.state.value.model(modelIdentity('b', 'shared'))?.displayName,
      'Shared',
      reason:
          'Wrong-account return must not mutate another canonical descriptor',
    );
    final latest = owner.performance(modelIdentity('a', 'shared'));
    transport.calls[3].$2.complete(_detail(_a));
    final detail = await latest;
    expect(detail.performance.averageTtftMillis, 250);
    expect(
      detail.recentEvaluations,
      isEmpty,
      reason: '55 call samples cannot become task evaluations',
    );
    final fresh = owner.performance(modelIdentity('a', 'shared'));
    expect(
      identical(fresh, latest),
      isFalse,
      reason: 'Completed performance data is not retained in a parallel history cache',
    );
    transport.calls[4].$2.complete(_detail(_a));
    expect((await fresh).key, _a);
  });

  test('dismissed and closed detail queries remain owned until their real futures settle', () async {
    final transport = _Transport();
    final client = _client(transport);
    final owner = client.domains.models;
    final pending = owner.performance(modelIdentity('a', 'shared'));
    final display = owner.state.watch((_) {});
    display.cancel();
    var joined = false;
    final closing = client.close().then((_) => joined = true);
    await Future<void>.value();
    expect(
      joined,
      isFalse,
      reason: 'Forget must not drop ownership of in-flight queries',
    );
    transport.calls.single.$2.complete(_detail(_a));
    await pending;
    await closing;
    expect(display.isCancelled, isTrue);
    expect(owner.performance(modelIdentity('b', 'shared')), throwsStateError);
  });
}
