import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_card_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_details_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_usage_transport.dart';
import '../support/test_statistics_feed.dart';

const _a = AccountDisplayKey(kind: AccountKind.native, id: 'a');
const _b = AccountDisplayKey(kind: AccountKind.native, id: 'b');

final class _Harness {
  _Harness({bool summariesLoaded = true}) {
    graph = AppGraph(
      transport: transport,
      statisticsFeed: const TestStatisticsFeedPort(),
      clientId: 'usage-card',
    );
    graph.accountDomains.adoptOwnerEpoch(ScriptedUsageTransport.epoch);
    if (summariesLoaded) {
      publish([
        usageAccount('a', name: 'Alpha'),
        usageAccount('b', name: 'Beta'),
      ]);
    }
    container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    container.listen(accountsViewModelProvider, (_, _) {});
    addTearDown(() async {
      container.dispose();
      await graph.close(
        deadline: DateTime.now().add(const Duration(seconds: 3)),
      );
    });
  }

  final transport = ScriptedUsageTransport();
  late final AppGraph graph;
  late final ProviderContainer container;
  AccountsViewModel get owner =>
      container.read(accountsViewModelProvider.notifier);
  AccountRowPresentation row(AccountDisplayKey key) =>
      container.read(accountCardViewModelProvider(key)).requireValue!;
  AccountQueryPhase phase(AccountDisplayKey key) =>
      (row(key).content as NativeAccountRowContent).usage.phase;
  void publish(List<AccountSummary> accounts) =>
      graph.accountDomains.acceptFrame(transport.publishAccounts(accounts));
  Future<void> mount() async {
    await container.read(accountsViewModelProvider.future);
    owner.setVisible(true);
  }

  Future<void> settled(String id, AccountUsagePhase phase) =>
      graph.accountUsage.state.waitFor(
        (value) => value.value?[NativeAccountIdentity(id)]?.phase == phase,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'card creation refreshes once; search and rebuild retain hidden members',
    () async {
      final h = _Harness();
      await h.mount();
      final a = await h.transport.started('a');
      final b = await h.transport.started('b');
      final original = h.container.read(
        accountCardViewModelProvider(_b).notifier,
      );
      h.owner.search('Alpha');
      h.owner.setVisible(true);
      h.container.read(accountsViewModelProvider);
      expect(
        h.container.read(accountsViewModelProvider).requireValue.list.members,
        [_a],
      );
      expect(
        h.container.read(accountCardViewModelProvider(_b).notifier),
        same(original),
      );
      h.owner.search('');
      await h.container.pump();
      expect(h.transport.calls, hasLength(2));
      h.transport.succeed(a);
      h.transport.succeed(b);
      await h.settled('b', AccountUsagePhase.unsupported);
    },
  );

  test('slow and failed A do not block B or publish B and list projections', () async {
    final h = _Harness();
    await h.mount();
    final a = await h.transport.started('a');
    final b = await h.transport.started('b');
    await h.container.pump();
    var listPublications = 0;
    var aPublications = 0;
    var bPublications = 0;
    h.container.listen(accountsViewModelProvider, (_, _) => listPublications++);
    h.container.listen(
      accountCardViewModelProvider(_a),
      (_, _) => aPublications++,
    );
    h.container.listen(
      accountCardViewModelProvider(_b),
      (_, _) => bPublications++,
    );
    h.transport.succeed(b);
    await h.settled('b', AccountUsagePhase.unsupported);
    expect(h.phase(_b), AccountQueryPhase.unsupported);
    expect(h.phase(_a), AccountQueryPhase.loading);
    expect(aPublications, 0);
    expect(bPublications, 1);
    expect(listPublications, 0);
    final beforeB = h.row(_b);
    h.transport.fail(a);
    await h.graph.accountUsage.queryFailures.waitFor(
      (value) => value.containsKey(const NativeAccountIdentity('a')),
    );
    expect(h.phase(_a), AccountQueryPhase.failed);
    expect(h.row(_b), same(beforeB));
    expect(bPublications, 1);
    expect(listPublications, 0);
    expect(aPublications, greaterThan(0));

    // A summary-only change also belongs to that card, not the membership list.
    h.publish([
      usageAccount('a', name: 'Renamed'),
      usageAccount('b', name: 'Beta'),
    ]);
    expect(h.row(_a).name, 'Renamed');
    expect(h.row(_b), same(beforeB));
    expect(listPublications, 0);
    expect(bPublications, 1);
  });

  test('single refresh touches one account; all refresh includes hidden members concurrently', () async {
    final h = _Harness();
    await h.mount();
    h.transport.succeed(await h.transport.started('a'));
    h.transport.succeed(await h.transport.started('b'));
    await h.settled('b', AccountUsagePhase.unsupported);
    h.owner.search('Alpha');
    final single = h.owner.refresh(_a);
    final secondA = await h.transport.started('a', number: 2);
    expect(
      h.transport.calls.where((call) => call.identity.accountId == 'b'),
      hasLength(1),
    );
    h.transport.succeed(secondA);
    await single;
    final all = h.owner.refreshAll();
    final thirdA = await h.transport.started('a', number: 3);
    final secondB = await h.transport.started('b', number: 2);
    h.transport.succeed(secondB);
    await h.settled('b', AccountUsagePhase.unsupported);
    expect(h.phase(_a), AccountQueryPhase.loading);
    h.transport.succeed(thirdA);
    await all;
  });

  test('leaving before initial intent runs revokes it; returning creates new resources', () async {
    final h = _Harness();
    await h.container.read(accountsViewModelProvider.future);
    h.owner.setVisible(true);
    final old = h.container.read(accountCardViewModelProvider(_a).notifier);
    h.owner.setVisible(false);
    await h.container.pump();
    expect(h.transport.calls, isEmpty);
    h.owner.setVisible(true);
    final a = await h.transport.started('a');
    final b = await h.transport.started('b');
    expect(
      h.container.read(accountCardViewModelProvider(_a).notifier),
      isNot(same(old)),
    );
    h.transport.succeed(a);
    h.transport.succeed(b);
    await h.settled('b', AccountUsagePhase.unsupported);
    h.owner.setVisible(false);
    await h.container.pump();
    h.owner.setVisible(true);
    final nextA = await h.transport.started('a', number: 2);
    final nextB = await h.transport.started('b', number: 2);
    h.transport.succeed(nextA);
    h.transport.succeed(nextB);
    await h.settled('b', AccountUsagePhase.unsupported);
  });

  test(
    'detail created before summaries waits and refreshes only its account once',
    () async {
      final h = _Harness(summariesLoaded: false);
      h.graph.accountDomains.acceptFrame(h.transport.publishDetails('a'));
      final provider = accountDetailsViewModelProvider(_a);
      final detail = h.container.listen(provider, (_, _) {});
      addTearDown(detail.close);
      await h.container.read(provider.future);
      await h.container.pump();
      expect(h.transport.calls, isEmpty);
      h.publish([usageAccount('a', query: null), usageAccount('b')]);
      await h.container.pump();
      expect(h.transport.calls, isEmpty);
      h.publish([usageAccount('a'), usageAccount('b')]);
      final a = await h.transport.started('a');
      expect(h.transport.calls.map((call) => call.identity.accountId), ['a']);
      expect(a.queryRevision, 1);
      h.owner.setVisible(false);
      final secondListener = h.container.listen(provider, (_, _) {});
      secondListener.close();
      h.container.read(provider);
      h.graph.accountDomains.acceptFrame(h.transport.publishDetails('a'));
      h.publish([usageAccount('a', name: 'Renamed'), usageAccount('b')]);
      await h.container.pump();
      expect(h.transport.calls, hasLength(1));
      final other = h.graph.accountUsage.refresh(
        const NativeAccountIdentity('b'),
      );
      h.transport.succeed(await h.transport.started('b'));
      await other;
      expect(h.transport.calls.map((call) => call.identity.accountId), [
        'a',
        'b',
      ]);
      h.transport.succeed(a);
      await h.settled('a', AccountUsagePhase.unsupported);
      final usage =
          (h.container.read(provider).requireValue.details.content
                  as NativeAccountDetailsContent)
              .value
              .usage;
      expect(usage.phase, AccountQueryPhase.unsupported);
      expect(h.container.read(provider).requireValue.details.error, isNull);
      final explicit = h.container.read(provider.notifier).refreshUsage();
      h.transport.succeed(await h.transport.started('a', number: 2));
      await explicit;
      h.publish([usageAccount('a'), usageAccount('b')]);
      await h.container.pump();
      expect(h.transport.calls.map((call) => call.identity.accountId), [
        'a',
        'b',
        'a',
      ]);
    },
  );

  test('detail revision replacement refreshes the new query and ignores the old failure', () async {
    final h = _Harness();
    h.graph.accountDomains.acceptFrame(h.transport.publishDetails('a'));
    final provider = accountDetailsViewModelProvider(_a);
    final detail = h.container.listen(provider, (_, _) {});
    addTearDown(detail.close);
    await h.container.read(provider.future);
    final old = await h.transport.started('a');
    h.publish([usageAccount('a', query: 2), usageAccount('b')]);
    final current = await h.transport.started('a', number: 2);
    expect(current.queryRevision, 2);
    h.transport.succeed(current);
    await h.settled('a', AccountUsagePhase.unsupported);
    h.transport.fail(old);
    await h.container.pump();
    final projected = h.container.read(provider).requireValue.details;
    expect(projected.error, isNull);
    final usage =
        (projected.content as NativeAccountDetailsContent).value.usage;
    expect(usage.phase, AccountQueryPhase.unsupported);
    expect(usage.error, isNull);
    h.graph.accountDomains.acceptFrame(
      h.transport.publishDetails('a', query: 2),
    );
    h.publish([usageAccount('a', query: 2), usageAccount('b')]);
    await h.container.pump();
    expect(h.transport.calls, hasLength(2));
  });

  test('detail identity switch releases A without cancelling admitted work or polluting B', () async {
    final h = _Harness();
    h.graph.accountDomains.acceptFrame(h.transport.publishDetails('a'));
    h.graph.accountDomains.acceptFrame(h.transport.publishDetails('b'));
    final aProvider = accountDetailsViewModelProvider(_a);
    final aDetail = h.container.listen(aProvider, (_, _) {});
    await h.container.read(aProvider.future);
    final a = await h.transport.started('a');
    final oldOwner = h.container.read(aProvider.notifier);
    aDetail.close();
    await h.container.pump();
    final bProvider = accountDetailsViewModelProvider(_b);
    final bDetail = h.container.listen(bProvider, (_, _) {});
    addTearDown(bDetail.close);
    await h.container.read(bProvider.future);
    final b = await h.transport.started('b');
    h.transport.fail(a);
    await h.graph.accountUsage.queryFailures.waitFor(
      (value) => value.containsKey(const NativeAccountIdentity('a')),
    );
    expect(h.container.read(bProvider).requireValue.details.error, isNull);
    h.transport.succeed(b);
    await h.settled('b', AccountUsagePhase.unsupported);
    final returned = h.container.listen(aProvider, (_, _) {});
    addTearDown(returned.close);
    await h.container.read(aProvider.future);
    final nextA = await h.transport.started('a', number: 2);
    expect(h.container.read(aProvider.notifier), isNot(same(oldOwner)));
    h.transport.succeed(nextA);
    await h.settled('a', AccountUsagePhase.unsupported);
    expect(h.container.read(aProvider).requireValue.details.error, isNull);
    expect(h.container.read(bProvider).requireValue.details.error, isNull);
    expect(h.transport.calls.map((call) => call.identity.accountId), [
      'a',
      'b',
      'a',
    ]);
  });

  test('released detail does not issue a delayed initial query', () async {
    final h = _Harness(summariesLoaded: false);
    final provider = accountDetailsViewModelProvider(_a);
    final detail = h.container.listen(provider, (_, _) {});
    await h.container.read(provider.future);
    detail.close();
    await h.container.pump();
    h.publish([usageAccount('a'), usageAccount('b')]);
    await h.container.pump();
    expect(h.transport.calls, isEmpty);
  });

  test('card waits for a non-null query revision before consuming its initial refresh', () async {
    final h = _Harness(summariesLoaded: false);
    h.publish([usageAccount('a', query: null)]);
    await h.mount();
    await h.container.pump();
    final owner = h.container.read(accountCardViewModelProvider(_a).notifier);
    expect(h.transport.calls, isEmpty);
    expect(h.row(_a).operationError, isNull);
    h.publish([usageAccount('a', query: 7)]);
    final call = await h.transport.started('a');
    expect(call.queryRevision, 7);
    expect(
      h.container.read(accountCardViewModelProvider(_a).notifier),
      same(owner),
    );
    h.owner.setVisible(true);
    h.publish([usageAccount('a', query: 7)]);
    await h.container.pump();
    expect(h.transport.calls, hasLength(1));
    h.transport.succeed(call);
    await h.settled('a', AccountUsagePhase.unsupported);
  });

  test(
    'deletion retires only that card; late failure cannot reach a replacement',
    () async {
      final h = _Harness();
      await h.mount();
      final a = await h.transport.started('a');
      final b = await h.transport.started('b');
      final oldA = h.container.read(accountCardViewModelProvider(_a).notifier);
      final oldB = h.container.read(accountCardViewModelProvider(_b).notifier);
      h.publish([usageAccount('b', name: 'Beta')]);
      await h.container.pump();
      expect(oldA.isObservationActive(), isFalse);
      expect(
        h.container.read(accountCardViewModelProvider(_b).notifier),
        same(oldB),
      );
      h.publish([usageAccount('a', query: 2), usageAccount('b', name: 'Beta')]);
      final replacement = await h.transport.started('a', number: 2);
      expect(replacement.queryRevision, 2);
      h.transport.succeed(replacement);
      await h.settled('a', AccountUsagePhase.unsupported);
      final current = h.row(_a);
      h.transport.fail(a);
      h.transport.succeed(b);
      await h.settled('b', AccountUsagePhase.unsupported);
      await h.container.pump();
      expect(h.row(_a), current);
      expect(h.row(_a).operationError, isNull);
      expect(h.phase(_a), AccountQueryPhase.unsupported);
      expect(h.transport.calls, hasLength(3));
    },
  );
}
