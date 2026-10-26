import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/account_usage_fixture.dart';

/// Usage reads for a visible-account set and direct record reads. The ticket /
/// watermark lifecycle is covered by account_usage_repository_test.dart; these
/// two cases lock what a batch demand and a missing record must never invent.
const _refused = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The scripted native check was explicitly rejected',
  retryable: false,
  correlationId: 'usage-queries-refusal',
);

Future<AccountUsageFixture> _fixture({
  Map<String, int> accounts = const {'a': 1, 'b': 1},
  String clientId = 'usage-queries',
}) async {
  final fixture = AccountUsageFixture(clientId: clientId);
  addTearDown(() async {
    final report = await fixture.close(
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    );
    expect(report.unresolved, isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });
  await fixture.establish(accounts);
  return fixture;
}

List<AccountUsageRecord> _records(AccountUsageRepository repository) {
  final mirror = repository.state.value.usages;
  if (mirror is! CurrentCollectionMirror<AccountUsageRecord>) return const [];
  return [
    for (final row in mirror.window.rows.values)
      if (row is ReadyReadValue<AccountUsageRecord, ProductEntityRef>)
        row.current.value,
  ];
}

void main() {
  test('a visible-account batch starts every account immediately and one failure keeps the rest pending', () async {
    final fixture = await _fixture();
    fixture.usage.setVisibleAccounts(const {'a', 'b'});
    final a = await fixture.usagePort.called(0);
    final b = await fixture.usagePort.called(1);
    expect({a.accountId, b.accountId}, {'a', 'b'});
    expect(fixture.usage.checks.value.keys.toSet(), {'a', 'b'});

    a.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _refused),
    );
    final failed = fixture.usage.checks.value['a']!.ticket;
    await failed.result;
    expect(failed.state.value.isPending, isFalse);
    // The other account's admitted check is untouched by that failure.
    expect(
      fixture.usage.checks.value['b']!.ticket.state.value.isPending,
      isTrue,
    );
    expect(fixture.usagePort.calls, hasLength(2));

    final record = usageRecord('b', 5);
    fixture.declareUsage(1, {'b': record});
    await fixture.publishUsage(1);
    b.succeed(1);
    expect(await fixture.usage.load('b'), record);
    expect(_records(fixture.usage), [record]);
    expect(fixture.usagePort.calls, hasLength(2));
  });

  test(
    'a record the native source does not contain is a typed failure',
    () async {
      final fixture = await _fixture(accounts: const {'a': 1});
      final record = usageRecord('a', 9);
      fixture.declareUsage(1, {'a': record});
      await fixture.publishUsage(1);
      expect(await fixture.usage.load('a'), record);

      // A retracted account must fail visibly instead of returning an empty or
      // synthesized record for the missing identity.
      await expectLater(
        fixture.usage.load('ghost'),
        throwsA(
          isA<StudioFailure>().having(
            (StudioFailure failure) => failure.code,
            'code',
            StudioFailureCode.notFound,
          ),
        ),
      );
      expect(_records(fixture.usage), [record]);
    },
  );
}
