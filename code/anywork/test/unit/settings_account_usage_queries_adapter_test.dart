import '../support/test_app_lifecycle.dart';

import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/presentation/providers/account_domains.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_usage_transport.dart';
import '../support/test_statistics_feed.dart';

AppGraph _graph(ScriptedUsageTransport transport) {
  final graph = testAppGraph(
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
    () => graph.close(budget: ClientCloseBudget(const Duration(seconds: 3))),
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
      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      addTearDown(container.dispose);
      final list = container.listen(accountsViewModelProvider, (_, _) {});
      addTearDown(list.close);
      await container.read(accountsViewModelProvider.future);
      container.read(accountsViewModelProvider.notifier).setVisible(true);
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

  test('a fast refresh terminal replaces old success without requiring a querying frame', () async {
    final transport = ScriptedUsageTransport();
    final graph = _graph(transport);
    const identity = NativeAccountIdentity('a');
    graph.accountDomains.acceptFrame(transport.seedSuccess(identity));
    await graph.accountUsage.state.waitFor(
      (resource) =>
          resource.value?[identity]?.phase == AccountUsagePhase.succeeded,
    );
    final previous = graph.accountUsage.state.value.value![identity]!;
    final terminalRevision = Completer<int>();
    final usageWatch = graph.accountUsage.state.watchLatest((resource) {
      final usage = resource.value?[identity];
      if (usage != null &&
          usage.revision > previous.revision &&
          usage.queryRevision == previous.queryRevision &&
          usage.operationId != null &&
          usage.operationId != previous.operationId &&
          usage.phase == AccountUsagePhase.succeeded &&
          usage.lastGood != null &&
          !terminalRevision.isCompleted) {
        terminalRevision.complete(usage.revision);
      }
    });
    addTearDown(usageWatch.observation.cancel);

    final refresh = graph.accountUsage.refresh(identity);
    final call = await transport.started('a');
    // Complete immediately after the backend accepts the request. The test
    // deliberately does not wait for a later sample of Querying.
    transport.succeedWithQuota(call);
    await refresh;

    expect(terminalRevision.isCompleted, isTrue);
    expect(await terminalRevision.future, greaterThan(previous.revision));
    final refreshed = graph.accountUsage.state.value.value![identity]!;
    expect(refreshed.operationId, call.operationId);
    expect(refreshed.phase, AccountUsagePhase.succeeded);
    expect(refreshed.lastGood!.value, isA<AccountSubscription>());
  });

  test(
    'a delayed refresh transport failure cannot reuse the prior success',
    () async {
      final transport = ScriptedUsageTransport();
      final graph = _graph(transport);
      const identity = NativeAccountIdentity('a');
      graph.accountDomains.acceptFrame(transport.seedSuccess(identity));
      await graph.accountUsage.state.waitFor(
        (resource) =>
            resource.value?[identity]?.phase == AccountUsagePhase.succeeded,
      );
      final previous = graph.accountUsage.state.value.value![identity]!;
      final failuresBefore = graph.accountUsage.queryFailures.value;
      var sawTerminalSuccess = false;
      final failed = Completer<void>();
      final usageWatch = graph.accountUsage.state.watchLatest((resource) {
        final usage = resource.value?[identity];
        if (usage != null &&
            usage.revision > previous.revision &&
            usage.queryRevision == previous.queryRevision &&
            usage.operationId != null &&
            usage.operationId != previous.operationId &&
            usage.phase == AccountUsagePhase.succeeded) {
          sawTerminalSuccess = true;
        }
      });
      final failureWatch = graph.accountUsage.queryFailures.watchLatest((next) {
        if (!failed.isCompleted &&
            !identical(next, failuresBefore) &&
            next.containsKey(identity)) {
          failed.complete();
        }
      });
      addTearDown(usageWatch.observation.cancel);
      addTearDown(failureWatch.observation.cancel);

      final refresh = graph.accountUsage.refresh(identity);
      final call = await transport.started('a');
      // Hold the response until the real feed publishes the in-flight state.
      await graph.accountUsage.state.waitFor(
        (resource) =>
            resource.value?[identity]?.operationId == call.operationId,
      );
      transport.fail(call);
      await expectLater(refresh, throwsStateError);
      expect(failed.isCompleted, isTrue);
      await failed.future;
      expect(sawTerminalSuccess, isFalse);
      expect(
        graph.accountUsage.state.value.value![identity]!.phase,
        AccountUsagePhase.querying,
      );
    },
  );

  test('a late result for an obsolete usage query is not accepted as the refresh result', () async {
    final transport = ScriptedUsageTransport();
    final graph = _graph(transport);
    const identity = NativeAccountIdentity('a');
    graph.accountDomains.acceptFrame(transport.seedSuccess(identity));
    await graph.accountUsage.state.waitFor(
      (resource) =>
          resource.value?[identity]?.phase == AccountUsagePhase.succeeded,
    );
    final previous = graph.accountUsage.state.value.value![identity]!;
    var acceptedTerminal = false;
    final usageWatch = graph.accountUsage.state.watchLatest((resource) {
      final usage = resource.value?[identity];
      if (usage != null &&
          usage.revision > previous.revision &&
          usage.queryRevision == previous.queryRevision &&
          usage.operationId != null &&
          usage.operationId != previous.operationId &&
          usage.phase == AccountUsagePhase.succeeded) {
        acceptedTerminal = true;
      }
    });
    addTearDown(usageWatch.observation.cancel);

    final refresh = graph.accountUsage.refresh(identity);
    final call = await transport.started('a');
    graph.accountDomains.acceptFrame(
      transport.publishAccounts([
        usageAccount('a', query: 2),
        usageAccount('b'),
      ]),
    );
    expect(
      graph.accountUsage.state.value.value!.containsKey(identity),
      isFalse,
    );
    transport.succeedWithQuota(call);
    await refresh;

    expect(acceptedTerminal, isFalse);
    expect(
      graph.accountUsage.state.value.value!.containsKey(identity),
      isFalse,
    );
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
