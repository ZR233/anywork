import 'dart:async';

import 'package:anywork/src/features/settings/settings_provider_usage_demand.dart';
import 'package:anywork/src/features/settings/settings_views.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/presentation/providers/provider_usage_queries.dart';
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
        providers: [
          _provider('a', usageQueryRevision: 1),
          _provider('b', usageQueryRevision: 1),
        ],
      ),
    );
    final demand = ProviderUsageAutoDemand();
    final queries = client.providerUsageQueries;
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      demand.apply(
        visible: true,
        providers: const [
          ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 1),
          ProviderUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
        ],
        refresh: (id) => ignoreProviderUsageQueryErrors(queries.refresh(id)),
      );
      await transport.started('a').future;
      await transport.started('b').future;
      expect(transport.startedIds, ['a', 'b']);
      expect(queries.state.loadingProviderIds, containsAll(['a', 'b']));
      transport.release('a').complete(_usage('a'));
      await queries.source.waitFor(
        (state) => !state.loadingProviderIds.contains('a'),
      );
      expect(queries.state.loadingProviderIds.contains('b'), isTrue);
      expect(queries.state.errorsByProviderId.containsKey('a'), isFalse);
      transport.release('b').completeError(StateError('b failed'));
      await queries.source.waitFor(
        (state) =>
            !state.loadingProviderIds.contains('b') &&
            state.errorsByProviderId.containsKey('b'),
      );
      expect(queries.state.errorsByProviderId['b'], isNotNull);
      expect(queries.state.errorsByProviderId.containsKey('a'), isFalse);
      demand.apply(
        visible: true,
        providers: const [
          ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 1),
          ProviderUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
        ],
        refresh: (id) => ignoreProviderUsageQueryErrors(queries.refresh(id)),
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
          providers: [
            _provider('a', name: 'Alpha', usageQueryRevision: 1),
            _provider('b', name: 'Beta', usageQueryRevision: 1),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [anyworkClientProvider.overrideWith((ref) => client)],
      );
      addTearDown(container.dispose);
      final querySub = container.listen(
        providerUsageQueriesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(querySub.close);
      final identityNotifications = <ProviderUsageQueryIdentitySnapshot>[];
      final identitySub = container.listen(
        settingsProviderUsageQueryIdentitiesProvider,
        (_, next) => identityNotifications.add(next),
        fireImmediately: true,
      );
      addTearDown(identitySub.close);

      expect(querySub.read().loadingProviderIds, isEmpty);
      expect(transport.startedIds, isEmpty);
      expect(identitySub.read().identities, const [
        ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 1),
        ProviderUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
      ]);
      identityNotifications.clear();

      ignoreProviderUsageQueryErrors(client.providerUsageQueries.refresh('a'));
      await transport.started('a').future;
      await client.providerUsageQueries.source.waitFor(
        (state) => state.loadingProviderIds.contains('a'),
      );
      expect(querySub.read().loadingProviderIds, contains('a'));
      transport.release('a').complete(_usage('a'));
      await client.providerUsageQueries.source.waitFor(
        (state) => state.loadingProviderIds.isEmpty,
      );
      expect(querySub.read().loadingProviderIds, isEmpty);
      expect(querySub.read().errorsByProviderId, isEmpty);
      expect(transport.startedIds, ['a']);

      client.settings.merge(
        SettingsStateSnapshot(
          revision: 2,
          providers: [
            _provider('a', name: 'Alpha renamed', usageQueryRevision: 1),
            _provider('b', name: 'Beta', usageQueryRevision: 1),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(identityNotifications, isEmpty);
      expect(transport.startedIds, ['a']);

      client.settings.merge(
        SettingsStateSnapshot(
          revision: 3,
          providers: [
            _provider('a', name: 'Alpha renamed', usageQueryRevision: 2),
            _provider('b', name: 'Beta', usageQueryRevision: 1),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(identityNotifications, [
        ProviderUsageQueryIdentitySnapshot(const [
          ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 2),
          ProviderUsageQueryIdentity(id: 'b', usageQueryRevision: 1),
        ]),
      ]);
      expect(transport.startedIds, ['a']);

      client.settings.merge(
        SettingsStateSnapshot(
          revision: 4,
          providers: [
            _provider('a', name: 'Alpha renamed', usageQueryRevision: 2),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        identityNotifications.last,
        const ProviderUsageQueryIdentitySnapshot([
          ProviderUsageQueryIdentity(id: 'a', usageQueryRevision: 2),
        ]),
      );
      expect(transport.startedIds, ['a']);
    },
  );
}

ProviderSettingsView _provider(
  String id, {
  String? name,
  int usageQueryRevision = 1,
}) {
  return ProviderSettingsView(
    id: id,
    name: name ?? id,
    baseUrl: 'http://local.invalid',
    defaultModel: 'model',
    models: const [
      ProviderModelView(
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

ProviderUsageStateSnapshot _usage(String providerId) {
  return ProviderUsageStateSnapshot(
    revision: 1,
    usages: [
      ProviderUsageView(
        providerId: providerId,
        updatedAt: 1,
        state: const UnsupportedProviderUsageView(),
      ),
    ],
  );
}

class _UsageTransport implements StudioTransport {
  final startedGates = <String, Completer<void>>{};
  final releaseGates = <String, Completer<ProviderUsageStateSnapshot>>{};
  final startedIds = <String>[];

  Completer<void> started(String providerId) =>
      startedGates.putIfAbsent(providerId, Completer<void>.new);

  Completer<ProviderUsageStateSnapshot> release(String providerId) =>
      releaseGates.putIfAbsent(
        providerId,
        Completer<ProviderUsageStateSnapshot>.new,
      );

  @override
  Future<ProviderUsageStateSnapshot> checkProviderUsage(
    String providerId,
  ) async {
    startedIds.add(providerId);
    started(providerId).complete();
    return release(providerId).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}
