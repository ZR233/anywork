import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/presentation/providers/account_domains.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scripted_usage_transport.dart';
import 'support/test_statistics_feed.dart';

AppGraph _graph(ScriptedUsageTransport transport) {
  final graph = AppGraph(
    transport: transport,
    statisticsFeed: const TestStatisticsFeedPort(),
    clientId: 'usage-adapter',
  );
  graph.accountDomains.adoptOwnerEpoch(ScriptedUsageTransport.epoch);
  graph.accountDomains.acceptFrame(
    transport.publishAccounts([
      usageAccount('a', name: 'Alpha'),
      usageAccount('b', name: 'Beta'),
    ]),
  );
  addTearDown(
    () => graph.close(deadline: DateTime.now().add(const Duration(seconds: 3))),
  );
  return graph;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('application visibility demand swallows query failures without forging provider health', () async {
    final transport = ScriptedUsageTransport();
    final graph = _graph(transport);
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      final demand = graph.accountUsage.observeVisible();
      addTearDown(demand.release);
      final a = await transport.started('a');
      final b = await transport.started('b');
      expect(transport.calls.map((call) => call.identity.accountId), [
        'a',
        'b',
      ]);
      await graph.accountUsage.state.waitFor(
        (value) =>
            value.value?.values.every(
                  (value) => value.phase == AccountUsagePhase.querying,
                ) ==
                true &&
            value.value?.length == 2,
      );
      transport.succeed(a);
      await graph.accountUsage.state.waitFor(
        (value) =>
            value.value?[const NativeAccountIdentity('a')]?.phase ==
            AccountUsagePhase.unsupported,
      );
      expect(
        graph
            .accountUsage
            .state
            .value
            .value![const NativeAccountIdentity('b')]!
            .phase,
        AccountUsagePhase.querying,
      );
      expect(graph.accountUsage.queryFailures.value, isEmpty);
      transport.fail(b);
      await graph.accountUsage.queryFailures.waitFor(
        (value) => value.containsKey(const NativeAccountIdentity('b')),
      );
      expect(
        graph.accountUsage.queryFailures.value.containsKey(
          const NativeAccountIdentity('a'),
        ),
        isFalse,
      );
      expect(
        graph
            .accountUsage
            .state
            .value
            .value![const NativeAccountIdentity('b')]!
            .phase,
        AccountUsagePhase.querying,
        reason: 'A local transport error cannot invent a Rust terminal',
      );
      graph.accountDomains.acceptFrame(
        transport.publishAccounts([
          usageAccount('a', name: 'Renamed'),
          usageAccount('b'),
        ]),
      );
      expect(
        transport.calls,
        hasLength(2),
        reason:
            'A failed visible query is attempted, not an automatic retry loop',
      );
    }, (error, _) => uncaught.add(error));
    expect(uncaught, isEmpty);
  });

  test('readonly providers reflect usage and query identity changes without issuing requests', () async {
    final transport = ScriptedUsageTransport();
    final graph = _graph(transport);
    final container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    addTearDown(container.dispose);
    final usage = container.listen(accountUsageStateProvider, (_, _) {});
    addTearDown(usage.close);
    final errors = container.listen(
      accountUsageQueryFailuresProvider,
      (_, _) {},
    );
    addTearDown(errors.close);
    final accounts = container.listen(accountsStateProvider, (_, _) {});
    addTearDown(accounts.close);
    expect(usage.read().loaded, isFalse);
    expect(usage.read().value, isEmpty);
    expect(errors.read(), isEmpty);
    expect(transport.calls, isEmpty);
    expect(
      accounts.read().accounts.map(
        (value) => (value.identity.accountId, value.usageQueryRevision),
      ),
      [('a', 1), ('b', 1)],
    );
    final pending = graph.accountUsage.refresh(
      const NativeAccountIdentity('a'),
    );
    final call = await transport.started('a');
    await graph.accountUsage.state.waitFor(
      (value) =>
          value.value?[const NativeAccountIdentity('a')]?.phase ==
          AccountUsagePhase.querying,
    );
    expect(
      usage.read().value![const NativeAccountIdentity('a')]!.phase,
      AccountUsagePhase.querying,
    );
    transport.succeed(call);
    await pending;
    expect(
      usage.read().value![const NativeAccountIdentity('a')]!.phase,
      AccountUsagePhase.unsupported,
    );
    expect(errors.read(), isEmpty);
    graph.accountDomains.acceptFrame(
      transport.publishAccounts([
        usageAccount('a', name: 'Alpha renamed'),
        usageAccount('b', name: 'Beta'),
      ]),
    );
    expect(accounts.read().accounts.first.name, 'Alpha renamed');
    expect(transport.calls, hasLength(1));
    graph.accountDomains.acceptFrame(
      transport.publishAccounts([
        usageAccount('a', name: 'Alpha renamed', query: 2),
        usageAccount('b', name: 'Beta'),
      ]),
    );
    expect(
      accounts.read().accounts.map(
        (value) => (value.identity.accountId, value.usageQueryRevision),
      ),
      [('a', 2), ('b', 1)],
    );
    expect(
      usage.read().value!.containsKey(const NativeAccountIdentity('a')),
      isFalse,
      reason: 'A new query cannot reuse lastGood or health from the old query',
    );
    expect(transport.calls, hasLength(1));
    graph.accountDomains.acceptFrame(
      transport.publishAccounts([
        usageAccount('a', name: 'Alpha renamed', query: 2),
      ]),
    );
    expect(accounts.read().accounts.map((value) => value.identity.accountId), [
      'a',
    ]);
    expect(transport.calls, hasLength(1));
  });
}
