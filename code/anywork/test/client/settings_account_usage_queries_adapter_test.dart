import 'dart:async';

import 'package:anywork/src/features/settings/settings_account_usage_demand.dart';
import 'package:anywork/src/features/settings/settings_views.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/presentation/providers/account_usage_queries.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production auto demand swallows query errors without uncaught zone failures', () async {
    final transport = _UsageTransport();
    final client = AnyworkClient(
      transport: transport,
      clientId: 'usage-demand',
    );
    addTearDown(client.close);
    client.settings.merge(
      SettingsStateSnapshot(
        revision: 1,
        accounts: [
          _account('a', usageQueryRevision: 1),
          _account('b', usageQueryRevision: 1),
        ],
      ),
    );
    final demand = AccountUsageAutoDemand();
    final queries = client.accountUsageQueries;
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      demand.apply(
        visible: true,
        accounts: const [
          AccountUsageQueryIdentity(id: 'a', usageQueryRevision: 1),
          AccountUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
        ],
        refresh: (id) => ignoreAccountUsageQueryErrors(queries.refresh(id)),
      );
      await transport.started('a').future;
      await transport.started('b').future;
      expect(transport.startedIds, ['a', 'b']);
      expect(queries.state.loadingAccountIds, containsAll(['a', 'b']));
      transport.release('a').complete(_usage('a'));
      await queries.source.waitFor(
        (state) => !state.loadingAccountIds.contains('a'),
      );
      expect(queries.state.loadingAccountIds.contains('b'), isTrue);
      expect(queries.state.errorsByAccountId.containsKey('a'), isFalse);
      transport.release('b').completeError(StateError('b failed'));
      await queries.source.waitFor(
        (state) =>
            !state.loadingAccountIds.contains('b') &&
            state.errorsByAccountId.containsKey('b'),
      );
      expect(queries.state.errorsByAccountId['b'], isNotNull);
      expect(queries.state.errorsByAccountId.containsKey('a'), isFalse);
      demand.apply(
        visible: true,
        accounts: const [
          AccountUsageQueryIdentity(id: 'a', usageQueryRevision: 1),
          AccountUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
        ],
        refresh: (id) => ignoreAccountUsageQueryErrors(queries.refresh(id)),
      );
      expect(transport.startedIds, ['a', 'b']);
    }, (error, _) => uncaught.add(error));
    expect(uncaught, isEmpty);
  });

  test(
    'readonly query adapter observes query state and identity selector',
    () async {
      final transport = _UsageTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'usage-observe',
      );
      addTearDown(client.close);
      client.settings.merge(
        SettingsStateSnapshot(
          revision: 1,
          accounts: [
            _account('a', name: 'Alpha', usageQueryRevision: 1),
            _account('b', name: 'Beta', usageQueryRevision: 1),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [anyworkClientProvider.overrideWith((ref) => client)],
      );
      addTearDown(container.dispose);
      final querySub = container.listen(
        accountUsageQueriesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(querySub.close);
      final identityNotifications = <AccountUsageQueryIdentitySnapshot>[];
      final identitySub = container.listen(
        settingsAccountUsageQueryIdentitiesProvider,
        (_, next) => identityNotifications.add(next),
        fireImmediately: true,
      );
      addTearDown(identitySub.close);

      expect(querySub.read().loadingAccountIds, isEmpty);
      expect(transport.startedIds, isEmpty);
      expect(identitySub.read().identities, const [
        AccountUsageQueryIdentity(id: 'a', usageQueryRevision: 1),
        AccountUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
      ]);
      identityNotifications.clear();

      ignoreAccountUsageQueryErrors(client.accountUsageQueries.refresh('a'));
      await transport.started('a').future;
      await client.accountUsageQueries.source.waitFor(
        (state) => state.loadingAccountIds.contains('a'),
      );
      expect(querySub.read().loadingAccountIds, contains('a'));
      transport.release('a').complete(_usage('a'));
      await client.accountUsageQueries.source.waitFor(
        (state) => state.loadingAccountIds.isEmpty,
      );
      expect(querySub.read().loadingAccountIds, isEmpty);
      expect(querySub.read().errorsByAccountId, isEmpty);
      expect(transport.startedIds, ['a']);

      client.settings.merge(
        SettingsStateSnapshot(
          revision: 2,
          accounts: [
            _account('a', name: 'Alpha renamed', usageQueryRevision: 1),
            _account('b', name: 'Beta', usageQueryRevision: 1),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(identityNotifications, isEmpty);
      expect(transport.startedIds, ['a']);

      client.settings.merge(
        SettingsStateSnapshot(
          revision: 3,
          accounts: [
            _account('a', name: 'Alpha renamed', usageQueryRevision: 2),
            _account('b', name: 'Beta', usageQueryRevision: 1),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(identityNotifications, [
        AccountUsageQueryIdentitySnapshot(const [
          AccountUsageQueryIdentity(id: 'a', usageQueryRevision: 2),
          AccountUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
        ]),
      ]);
      expect(transport.startedIds, ['a']);

      client.settings.merge(
        SettingsStateSnapshot(
          revision: 4,
          accounts: [
            _account('a', name: 'Alpha renamed', usageQueryRevision: 2),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        identityNotifications.last,
        const AccountUsageQueryIdentitySnapshot([
          AccountUsageQueryIdentity(id: 'a', usageQueryRevision: 2),
        ]),
      );
      expect(transport.startedIds, ['a']);
    },
  );
}

AccountSettingsView _account(
  String id, {
  String? name,
  int usageQueryRevision = 1,
}) {
  return AccountSettingsView(
    id: id,
    name: name ?? id,
    baseUrl: 'http://local.invalid',
    defaultModelId: 'model',
    models: const [
      AccountModelView(
        modelId: 'model',
        displayName: 'Model',
        reasoningEfforts: ['medium'],
      ),
    ],
    status: 'ready',
    usageLabel: '',
    usageQueryRevision: usageQueryRevision,
  );
}

AccountUsageStateSnapshot _usage(String accountId) {
  return AccountUsageStateSnapshot(
    revision: 1,
    usages: [
      AccountUsageView(
        accountId: accountId,
        updatedAt: 1,
        state: const UnsupportedAccountUsageView(),
      ),
    ],
  );
}

class _UsageTransport implements StudioTransport {
  final startedGates = <String, Completer<void>>{};
  final releaseGates = <String, Completer<AccountUsageStateSnapshot>>{};
  final startedIds = <String>[];

  Completer<void> started(String accountId) =>
      startedGates.putIfAbsent(accountId, Completer<void>.new);

  Completer<AccountUsageStateSnapshot> release(String accountId) => releaseGates
      .putIfAbsent(accountId, Completer<AccountUsageStateSnapshot>.new);

  @override
  Future<AccountUsageStateSnapshot> checkAccountUsage(String accountId) async {
    startedIds.add(accountId);
    started(accountId).complete();
    return release(accountId).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}
