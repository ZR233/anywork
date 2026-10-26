import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork_client/accounts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scripted_usage_transport.dart';
import 'support/test_statistics_feed.dart';

AppGraph _graph(
  ScriptedUsageTransport transport,
  List<AccountSummary> accounts,
) {
  final graph = AppGraph(
    transport: transport,
    statisticsFeed: const TestStatisticsFeedPort(),
    clientId: 'usage-demand',
  );
  graph.accountDomains.adoptOwnerEpoch(ScriptedUsageTransport.epoch);
  graph.accountDomains.acceptFrame(transport.publishAccounts(accounts));
  addTearDown(
    () => graph.close(deadline: DateTime.now().add(const Duration(seconds: 3))),
  );
  return graph;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('application-owned usage visibility', () {
    test(
      'first visible demand starts each identity concurrently once',
      () async {
        final transport = ScriptedUsageTransport();
        final graph = _graph(transport, [usageAccount('a'), usageAccount('b')]);
        final demand = graph.accountUsage.observeVisible();
        final a = await transport.started('a');
        final b = await transport.started('b');
        expect(transport.calls.map((call) => call.identity.accountId), [
          'a',
          'b',
        ]);
        final second = graph.accountUsage.observeVisible();
        await second.release();
        expect(transport.calls, hasLength(2));
        final joined = Future.wait([
          graph.accountUsage.refresh(a.identity),
          graph.accountUsage.refresh(b.identity),
        ]);
        transport.succeed(a);
        transport.succeed(b);
        await joined;
        await demand.release();
        final reopened = graph.accountUsage.observeVisible();
        await reopened.release();
        expect(transport.calls, hasLength(2));
      },
    );
    test('hidden identity changes wait for visibility and only new query identities start', () async {
      final transport = ScriptedUsageTransport();
      final graph = _graph(transport, [usageAccount('a'), usageAccount('b')]);
      final visible = graph.accountUsage.observeVisible();
      final a = await transport.started('a');
      final b = await transport.started('b');
      final joined = Future.wait([
        graph.accountUsage.refresh(a.identity),
        graph.accountUsage.refresh(b.identity),
      ]);
      transport.succeed(a);
      transport.succeed(b);
      await joined;
      await visible.release();
      graph.accountDomains.acceptFrame(
        transport.publishAccounts([
          usageAccount('a', query: 2),
          usageAccount('b'),
          usageAccount('c'),
        ]),
      );
      expect(transport.calls, hasLength(2));
      final reopened = graph.accountUsage.observeVisible();
      addTearDown(reopened.release);
      final nextA = await transport.started('a', number: 2);
      final c = await transport.started('c');
      expect(
        transport.calls.map(
          (call) => (call.identity.accountId, call.queryRevision),
        ),
        [('a', 1), ('b', 1), ('a', 2), ('c', 1)],
      );
      final next = Future.wait([
        graph.accountUsage.refresh(nextA.identity),
        graph.accountUsage.refresh(c.identity),
      ]);
      transport.succeed(nextA);
      transport.succeed(c);
      await next;
    });
    test('a failed visible query is not retried by a page rebuild, only a changed query identity', () async {
      final transport = ScriptedUsageTransport();
      final graph = _graph(transport, [usageAccount('a', query: 3)]);
      final visible = graph.accountUsage.observeVisible();
      final first = await transport.started('a');
      transport.fail(first);
      await graph.accountUsage.queryFailures.waitFor(
        (value) => value.containsKey(first.identity),
      );
      await visible.release();
      final rebuilt = graph.accountUsage.observeVisible();
      addTearDown(rebuilt.release);
      expect(transport.calls, hasLength(1));
      graph.accountDomains.acceptFrame(
        transport.publishAccounts([usageAccount('a', query: 4)]),
      );
      final second = await transport.started('a', number: 2);
      expect(second.queryRevision, 4);
      final joined = graph.accountUsage.refresh(second.identity);
      transport.succeed(second);
      await joined;
      expect(graph.accountUsage.queryFailures.value, isEmpty);
    });
    test('deleting an account invalidates its attempted identity without retrying retained siblings', () async {
      final transport = ScriptedUsageTransport();
      final graph = _graph(transport, [
        usageAccount('keep'),
        usageAccount('gone'),
      ]);
      final visible = graph.accountUsage.observeVisible();
      addTearDown(visible.release);
      final keep = await transport.started('keep');
      final gone = await transport.started('gone');
      final joined = Future.wait([
        graph.accountUsage.refresh(keep.identity),
        graph.accountUsage.refresh(gone.identity),
      ]);
      transport.succeed(keep);
      transport.succeed(gone);
      await joined;
      graph.accountDomains.acceptFrame(
        transport.publishAccounts([usageAccount('keep')]),
      );
      expect(transport.calls, hasLength(2));
      graph.accountDomains.acceptFrame(
        transport.publishAccounts([usageAccount('keep'), usageAccount('gone')]),
      );
      final readded = await transport.started('gone', number: 2);
      expect(transport.calls.map((call) => call.identity.accountId), [
        'keep',
        'gone',
        'gone',
      ]);
      final next = graph.accountUsage.refresh(readded.identity);
      transport.succeed(readded);
      await next;
    });
  });
}
