import 'dart:async';

import 'package:anywork/src/features/settings/accounts/view_models/account_usage_checks.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/settings_usage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production auto demand exposes query errors without uncaught zone failures', () async {
    final fixture = await settingsUsageFixture({'a': 1, 'b': 1});
    final queries = fixture.usage;
    final presentation = AccountUsageChecks(
      fixture.configuration,
      queries,
      (_) {},
    );
    addTearDown(presentation.dispose);
    presentation.visibleAccounts({'a', 'b'});
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      queries.setVisibleAccounts({'a', 'b'});
      final a = await fixture.usagePort.called(0);
      final b = await fixture.usagePort.called(1);
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'b']);
      expect(
        presentation.snapshot.entries
            .where((entry) => entry.value.operation.isPending)
            .map((entry) => entry.key),
        containsAll(['a', 'b']),
      );
      expect(
        presentation.snapshot.map((id, check) => MapEntry(id, check.identity)),
        {
          'a': AccountUsageQueryIdentity(
            accountId: 'a',
            usageQueryRevision: 1,
            ownerEpoch: usageFixtureOrigin.ownerEpoch,
          ),
          'b': AccountUsageQueryIdentity(
            accountId: 'b',
            usageQueryRevision: 1,
            ownerEpoch: usageFixtureOrigin.ownerEpoch,
          ),
        },
      );
      final aTicket = queries.checks.value['a']!.ticket;
      final bTicket = queries.checks.value['b']!.ticket;
      fixture.declareUsage(1, {'a': usageRecord('a', 1)});
      a.succeed(1);
      await fixture.publishUsage(1);
      expect(
        await aTicket.result,
        isA<AcknowledgedCommandResult<AccountUsageRecord>>(),
      );
      expect(presentation.snapshot['b']!.operation.isPending, isTrue);
      expect(presentation.snapshot['a']!.operation.error, isNull);
      b.reply.completeError(
        const CommandDispatchFailure.rejected(failure: settingsUsageFailure),
      );
      await bTicket.result;
      expect(presentation.snapshot['b']!.operation.isPending, isFalse);
      expect(presentation.snapshot['b']!.operation.error, settingsUsageFailure);
      expect(presentation.snapshot['a']!.operation.error, isNull);
      queries.setVisibleAccounts({'a', 'b'});
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'b']);
    }, (error, _) => uncaught.add(error));
    expect(uncaught, isEmpty);
  });

  test('readonly check adapter observes progress and exact canonical query identity without scheduling', () async {
    final fixture = await settingsUsageFixture({'a': 1, 'b': 1});
    final queries = fixture.usage;
    final presentation = AccountUsageChecks(
      fixture.configuration,
      queries,
      (_) {},
    );
    addTearDown(presentation.dispose);
    presentation.visibleAccounts({'a', 'b'});
    expect(presentation.snapshot, isEmpty);
    expect(fixture.usagePort.calls, isEmpty);
    final ticket = queries.check('a');
    final call = await fixture.usagePort.called(0);
    final identity = AccountUsageQueryIdentity(
      accountId: 'a',
      usageQueryRevision: 1,
      ownerEpoch: usageFixtureOrigin.ownerEpoch,
    );
    expect(presentation.snapshot['a']!.identity, identity);
    expect(presentation.snapshot['a']!.operation.isPending, isTrue);
    fixture.declareUsage(1, {'a': usageRecord('a', 1)});
    call.succeed(1);
    await fixture.publishUsage(1);
    await ticket.result;
    expect(presentation.snapshot['a']!.operation.isPending, isFalse);
    expect(presentation.snapshot['a']!.operation.error, isNull);
    expect(fixture.usagePort.calls.map((call) => call.accountId), ['a']);

    // The fixture changes account display names on every configuration version.
    // An unrelated rename is not a new usage identity or a network demand.
    queries.setVisibleAccounts({'a'});
    await fixture.configurationChanged({'a': 1, 'b': 1});
    await queries.checks
        .waitFor((checks) => checks['a']?.identity == identity)
        .timeout(const Duration(seconds: 3));
    presentation.refresh();
    expect(presentation.snapshot['a']!.identity, identity);
    expect(presentation.snapshot['a']!.operation.id, ticket.id);
    expect(fixture.usagePort.calls.map((call) => call.accountId), ['a']);

    queries.setVisibleAccounts({});
    await fixture.configurationChanged({'a': 2, 'b': 1});
    presentation.refresh();
    expect(
      presentation.snapshot.containsKey('a'),
      isFalse,
      reason: 'The old revision cannot remain current or trigger a replacement read by observation alone',
    );
    expect(fixture.usagePort.calls.map((call) => call.accountId), ['a']);
    final current = queries.check('a');
    final next = await fixture.usagePort.called(1);
    expect(
      presentation.snapshot['a']!.identity,
      AccountUsageQueryIdentity(
        accountId: 'a',
        usageQueryRevision: 2,
        ownerEpoch: usageFixtureOrigin.ownerEpoch,
      ),
    );
    next.reply.completeError(
      const CommandDispatchFailure.rejected(failure: settingsUsageFailure),
    );
    await current.result;
    await fixture.configurationChanged({'b': 1});
    presentation.refresh();
    expect(presentation.snapshot.containsKey('a'), isFalse);
    expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'a']);
  });
}
