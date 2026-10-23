import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

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

class _Transport implements StudioTransport {
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

AnyworkClient _client(_Transport transport) {
  final client = AnyworkClient(transport: transport, clientId: 'details');
  client.settings.merge(_settings(1));
  addTearDown(client.close);
  return client;
}

void main() {
  test('exact account/model queries dedupe and never substitute stale or other-account details', () async {
    final transport = _Transport();
    final client = _client(transport);
    final owner = client.modelDetailQueries;
    final a = owner.refresh(_a);
    expect(identical(owner.refresh(_a), a), isTrue);
    final b = owner.refresh(_b);
    expect(transport.calls.map((call) => call.$1), [_a, _b]);
    transport.calls[1].$2.complete(_detail(_b));
    await b;
    expect(owner.state[_b]?.value?.key, _b);
    expect(owner.state[_a]?.loading, isTrue);
    client.settings.merge(_settings(2));
    expect(
      owner.state[_b]?.value,
      isNull,
      reason: 'Previously cached data must invalidate immediately',
    );
    expect(owner.state[_b]?.error?.code, StudioFailureCode.staleRevision);
    final stale = expectLater(
      a,
      throwsA(
        isA<StudioFailure>().having(
          (e) => e.message,
          'identity',
          contains('a/shared'),
        ),
      ),
    );
    transport.calls[0].$2.complete(_detail(_a));
    await stale;
    expect(owner.state[_a]?.value, isNull);
    final wrong = owner.refresh(_a);
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
    expect(owner.state[_a]?.value, isNull);
    expect(
      owner.state[_b]?.value,
      isNull,
      reason: 'Wrong-account return must not populate another key',
    );
    final latest = owner.refresh(_a);
    transport.calls[3].$2.complete(_detail(_a));
    await latest;
    expect(owner.state[_a]?.value?.performance.averageTtftMillis, 250);
    expect(
      owner.state[_a]?.value?.recentEvaluations,
      isEmpty,
      reason: '55 call samples cannot become task evaluations',
    );
    owner.forget(_a);
    expect(owner.state.containsKey(_a), isFalse);
  });

  test('dismissed and closed detail queries remain owned until their real futures settle', () async {
    final transport = _Transport();
    final client = _client(transport);
    final owner = client.modelDetailQueries;
    final pending = owner.refresh(_a);
    owner.forget(_a);
    var joined = false;
    final closing = owner.close().then((_) => joined = true);
    await Future<void>.value();
    expect(
      joined,
      isFalse,
      reason: 'Forget must not drop ownership of in-flight queries',
    );
    transport.calls.single.$2.complete(_detail(_a));
    await pending;
    await closing;
    expect(owner.state, isEmpty);
    expect(owner.refresh(_b), throwsStateError);
  });
}
