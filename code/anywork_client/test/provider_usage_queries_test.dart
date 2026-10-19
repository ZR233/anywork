import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class _UsageCall {
  _UsageCall(this.providerId);
  final String providerId;
  final entered = Completer<void>();
  final reply = Completer<ProviderUsageStateSnapshot>();
}

final class _UsageTransport implements StudioTransport {
  _UsageTransport(this._snapshot);
  final ProviderUsageStateSnapshot Function(String providerId, int revision)
  _snapshot;
  final calls = <_UsageCall>[];
  final published = <ProviderUsageStateSnapshot>[];
  var _nextRevision = 1;

  int get nextRevision => _nextRevision;

  ProviderUsageStateSnapshot publishEvent(String providerId) {
    final snapshot = _snapshot(providerId, _nextRevision++);
    published.add(snapshot);
    return snapshot;
  }

  @override
  Future<ProviderUsageStateSnapshot> checkProviderUsage(String providerId) {
    final call = _UsageCall(providerId);
    calls.add(call);
    call.entered.complete();
    return call.reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}

ProviderSettingsView _provider(String id, {int usageQueryRevision = 1}) {
  return ProviderSettingsView(
    id: id,
    name: id,
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

ProviderUsageView _usageView(String providerId, {required int updatedAt}) {
  return ProviderUsageView(
    providerId: providerId,
    revision: updatedAt,
    updatedAt: updatedAt,
    state: const UnsupportedProviderUsageView(),
  );
}

class _CanonicalUsageClock {
  _CanonicalUsageClock(this.providerIds);

  final List<String> providerIds;
  final Map<String, ProviderUsageView> _usages = {};

  ProviderUsageStateSnapshot snapshot(String providerId, int revision) {
    _usages[providerId] = _usageView(providerId, updatedAt: revision);
    return ProviderUsageStateSnapshot(
      revision: revision,
      usages: [
        for (final id in providerIds)
          if (_usages[id] case final usage?) usage,
      ],
    );
  }
}

SettingsStateSnapshot _settings(
  List<ProviderSettingsView> providers, {
  int revision = 1,
}) {
  return SettingsStateSnapshot(revision: revision, providers: providers);
}

List<ProviderUsageView> _usages(AnyworkClient client) {
  return client.providerUsage.state.value?.usages ?? const [];
}

int _usageRevision(AnyworkClient client) {
  return client.providerUsage.state.revision;
}

AnyworkClient _client(
  _UsageTransport transport,
  List<ProviderSettingsView> providers,
) {
  final client = AnyworkClient(transport: transport, clientId: 'usage');
  client.settings.merge(_settings(providers));
  addTearDown(client.close);
  return client;
}

_UsageTransport _transportFor(List<String> providerIds) {
  final clock = _CanonicalUsageClock(providerIds);
  return _UsageTransport(clock.snapshot);
}

void main() {
  test(
    'same provider and usageQueryRevision reuse one in-flight query',
    () async {
      final transport = _transportFor(['a']);
      final client = _client(transport, [_provider('a')]);
      final first = client.providerUsageQueries.refresh('a');
      await transport.calls.single.entered.future;
      final second = client.providerUsageQueries.refresh('a');
      expect(identical(first, second), isTrue);
      expect(client.providerUsageQueries.state.loadingProviderIds, {'a'});
      transport.calls.single.reply.complete(transport.publishEvent('a'));
      await first;
      expect(client.providerUsageQueries.state.loadingProviderIds, isEmpty);
      expect(_usages(client).map((item) => item.providerId), ['a']);
      expect(_usageRevision(client), 1);
    },
  );

  test('slow A does not block later B from applying a full snapshot', () async {
    final transport = _transportFor(['a', 'b']);
    final client = _client(transport, [_provider('a'), _provider('b')]);
    unawaited(client.providerUsageQueries.refresh('a'));
    unawaited(client.providerUsageQueries.refresh('b'));
    await transport.calls[0].entered.future;
    await transport.calls[1].entered.future;
    transport.calls[1].reply.complete(transport.publishEvent('b'));
    await Future<void>.delayed(Duration.zero);
    expect(_usages(client).map((item) => item.providerId), ['b']);
    expect(_usageRevision(client), 1);
    transport.calls[0].reply.complete(transport.publishEvent('a'));
    await Future<void>.delayed(Duration.zero);
    expect(_usages(client).map((item) => item.providerId).toSet(), {'a', 'b'});
    expect(_usageRevision(client), 2);
  });

  test('usageQueryRevision change starts an independent query and rejects the old ACK', () async {
    final transport = _transportFor(['a']);
    final client = _client(transport, [_provider('a', usageQueryRevision: 1)]);
    unawaited(client.providerUsageQueries.refresh('a'));
    await transport.calls.single.entered.future;
    client.settings.merge(
      _settings([_provider('a', usageQueryRevision: 2)], revision: 2),
    );
    unawaited(client.providerUsageQueries.refresh('a'));
    await transport.calls[1].entered.future;
    transport.calls[0].reply.complete(transport.publishEvent('a'));
    await Future<void>.delayed(Duration.zero);
    expect(_usages(client), isEmpty);
    transport.calls[1].reply.complete(transport.publishEvent('a'));
    await Future<void>.delayed(Duration.zero);
    expect(_usages(client).single.providerId, 'a');
    expect(_usageRevision(client), 2);
    expect(client.providerUsageQueries.state.loadingProviderIds, isEmpty);
  });

  test(
    'deleted provider rejects a late ACK and does not resurrect loading',
    () async {
      final transport = _transportFor(['a']);
      final client = _client(transport, [_provider('a')]);
      unawaited(client.providerUsageQueries.refresh('a'));
      await transport.calls.single.entered.future;
      client.settings.merge(_settings(const []));
      client.providerUsageQueries.forget('a');
      transport.calls.single.reply.complete(transport.publishEvent('a'));
      await Future<void>.delayed(Duration.zero);
      expect(_usages(client), isEmpty);
      expect(client.providerUsageQueries.state.loadingProviderIds, isEmpty);
    },
  );

  test(
    'close rejects new queries and waits for admitted work without applying',
    () async {
      final transport = _transportFor(['a']);
      final client = _client(transport, [_provider('a')]);
      final pending = client.providerUsageQueries.refresh('a');
      await transport.calls.single.entered.future;
      final closing = client.providerUsageQueries.close();
      await expectLater(
        client.providerUsageQueries.refresh('a'),
        throwsStateError,
      );
      transport.calls.single.reply.complete(transport.publishEvent('a'));
      await pending;
      await closing;
      expect(_usages(client), isEmpty);
    },
  );

  test('AppGraph instances isolate in-flight usage queries', () async {
    final firstTransport = _transportFor(['a']);
    final secondTransport = _transportFor(['a']);
    final first = _client(firstTransport, [_provider('a')]);
    final second = _client(secondTransport, [_provider('a')]);
    unawaited(first.providerUsageQueries.refresh('a'));
    await firstTransport.calls.single.entered.future;
    expect(second.providerUsageQueries.state.loadingProviderIds, isEmpty);
    unawaited(second.providerUsageQueries.refresh('a'));
    await secondTransport.calls.single.entered.future;
    secondTransport.calls.single.reply.complete(
      secondTransport.publishEvent('a'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(_usages(first), isEmpty);
    expect(_usages(second).single.providerId, 'a');
    firstTransport.calls.single.reply.complete(
      firstTransport.publishEvent('a'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(_usages(first).single.providerId, 'a');
  });

  test(
    'refreshAll starts each provider immediately and waits for the batch',
    () async {
      final transport = _transportFor(['a', 'b']);
      final client = _client(transport, [_provider('a'), _provider('b')]);
      final started = client.providerUsageQueries.refreshAll();
      await transport.calls[0].entered.future;
      await transport.calls[1].entered.future;
      expect(client.providerUsageQueries.state.loadingProviderIds, {'a', 'b'});
      transport.calls[1].reply.complete(transport.publishEvent('b'));
      await Future<void>.delayed(Duration.zero);
      expect(_usages(client).map((item) => item.providerId), ['b']);
      var batchDone = false;
      unawaited(started.then((_) => batchDone = true));
      await Future<void>.delayed(Duration.zero);
      expect(batchDone, isFalse);
      transport.calls[0].reply.complete(transport.publishEvent('a'));
      await started;
      expect(batchDone, isTrue);
      expect(_usages(client).map((item) => item.providerId).toSet(), {
        'a',
        'b',
      });
      expect(_usageRevision(client), 2);
    },
  );

  test(
    'event-first then matching response keeps the server revision',
    () async {
      final transport = _transportFor(['a']);
      final client = _client(transport, [_provider('a')]);
      unawaited(client.providerUsageQueries.refresh('a'));
      await transport.calls.single.entered.future;
      final snapshot = transport.publishEvent('a');
      client.providerUsage.apply(snapshot);
      expect(_usageRevision(client), 1);
      transport.calls.single.reply.complete(snapshot);
      await Future<void>.delayed(Duration.zero);
      expect(_usageRevision(client), 1);
      client.providerUsage.apply(
        ProviderUsageStateSnapshot(
          revision: 2,
          usages: [_usageView('a', updatedAt: 2)],
        ),
      );
      expect(_usageRevision(client), 2);
    },
  );

  test(
    'duplicate server revision is a no-op and a later revision is accepted',
    () async {
      final transport = _transportFor(['a']);
      final client = _client(transport, [_provider('a')]);
      final first = transport.publishEvent('a');
      client.providerUsage.apply(first);
      client.providerUsage.apply(first);
      expect(_usageRevision(client), 1);
      client.providerUsage.apply(transport.publishEvent('a'));
      expect(_usageRevision(client), 2);
    },
  );

  test(
    'refreshAll records A failure without uncaught error or clearing B',
    () async {
      final transport = _transportFor(['a', 'b']);
      final client = _client(transport, [_provider('a'), _provider('b')]);
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final started = client.providerUsageQueries.refreshAll();
        await transport.calls[0].entered.future;
        await transport.calls[1].entered.future;
        transport.calls[0].reply.completeError(StateError('usage failed'));
        await Future<void>.delayed(Duration.zero);
        expect(
          client.providerUsageQueries.state.errorsByProviderId['a'],
          contains('usage failed'),
        );
        expect(client.providerUsageQueries.state.loadingProviderIds, {'b'});
        transport.calls[1].reply.complete(transport.publishEvent('b'));
        await started;
        expect(
          client.providerUsageQueries.state.errorsByProviderId['a'],
          contains('usage failed'),
        );
        expect(_usages(client).map((item) => item.providerId), ['b']);
        expect(client.providerUsageQueries.state.loadingProviderIds, isEmpty);
      }, (error, stack) => errors.add(error));
      expect(errors, isEmpty);
    },
  );
}
