import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class _UsageCall {
  _UsageCall(this.accountId);
  final String accountId;
  final entered = Completer<void>();
  final reply = Completer<AccountUsageStateSnapshot>();
}

final class _UsageTransport implements StudioTransport {
  _UsageTransport(this._snapshot);
  final AccountUsageStateSnapshot Function(String accountId, int revision)
  _snapshot;
  final calls = <_UsageCall>[];
  final published = <AccountUsageStateSnapshot>[];
  var _nextRevision = 1;

  int get nextRevision => _nextRevision;

  AccountUsageStateSnapshot publishEvent(String accountId) {
    final snapshot = _snapshot(accountId, _nextRevision++);
    published.add(snapshot);
    return snapshot;
  }

  @override
  Future<AccountUsageStateSnapshot> checkAccountUsage(String accountId) {
    final call = _UsageCall(accountId);
    calls.add(call);
    call.entered.complete();
    return call.reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}

AccountSettingsView _account(String id, {int usageQueryRevision = 1}) {
  return AccountSettingsView(
    id: id,
    name: id,
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

AccountUsageView _usageView(String accountId, {required int updatedAt}) {
  return AccountUsageView(
    accountId: accountId,
    revision: updatedAt,
    updatedAt: updatedAt,
    state: const UnsupportedAccountUsageView(),
  );
}

class _CanonicalUsageClock {
  _CanonicalUsageClock(this.accountIds);

  final List<String> accountIds;
  final Map<String, AccountUsageView> _usages = {};

  AccountUsageStateSnapshot snapshot(String accountId, int revision) {
    _usages[accountId] = _usageView(accountId, updatedAt: revision);
    return AccountUsageStateSnapshot(
      revision: revision,
      usages: [
        for (final id in accountIds)
          if (_usages[id] case final usage?) usage,
      ],
    );
  }
}

SettingsStateSnapshot _settings(
  List<AccountSettingsView> accounts, {
  int revision = 1,
}) {
  return SettingsStateSnapshot(revision: revision, accounts: accounts);
}

List<AccountUsageView> _usages(AnyworkClient client) {
  return client.accountUsage.state.value?.usages ?? const [];
}

int _usageRevision(AnyworkClient client) {
  return client.accountUsage.state.revision;
}

AnyworkClient _client(
  _UsageTransport transport,
  List<AccountSettingsView> accounts,
) {
  final client = AnyworkClient(transport: transport, clientId: 'usage');
  client.settings.merge(_settings(accounts));
  addTearDown(client.close);
  return client;
}

_UsageTransport _transportFor(List<String> accountIds) {
  final clock = _CanonicalUsageClock(accountIds);
  return _UsageTransport(clock.snapshot);
}

void main() {
  test(
    'same account and usageQueryRevision reuse one in-flight query',
    () async {
      final transport = _transportFor(['a']);
      final client = _client(transport, [_account('a')]);
      final first = client.accountUsageQueries.refresh('a');
      await transport.calls.single.entered.future;
      final second = client.accountUsageQueries.refresh('a');
      expect(identical(first, second), isTrue);
      expect(client.accountUsageQueries.state.loadingAccountIds, {'a'});
      transport.calls.single.reply.complete(transport.publishEvent('a'));
      await first;
      expect(client.accountUsageQueries.state.loadingAccountIds, isEmpty);
      expect(_usages(client).map((item) => item.accountId), ['a']);
      expect(_usageRevision(client), 1);
    },
  );

  test('slow A does not block later B from applying a full snapshot', () async {
    final transport = _transportFor(['a', 'b']);
    final client = _client(transport, [_account('a'), _account('b')]);
    unawaited(client.accountUsageQueries.refresh('a'));
    unawaited(client.accountUsageQueries.refresh('b'));
    await transport.calls[0].entered.future;
    await transport.calls[1].entered.future;
    transport.calls[1].reply.complete(transport.publishEvent('b'));
    await Future<void>.delayed(Duration.zero);
    expect(_usages(client).map((item) => item.accountId), ['b']);
    expect(_usageRevision(client), 1);
    transport.calls[0].reply.complete(transport.publishEvent('a'));
    await Future<void>.delayed(Duration.zero);
    expect(_usages(client).map((item) => item.accountId).toSet(), {'a', 'b'});
    expect(_usageRevision(client), 2);
  });

  test('usageQueryRevision change starts an independent query and rejects the old ACK', () async {
    final transport = _transportFor(['a']);
    final client = _client(transport, [_account('a', usageQueryRevision: 1)]);
    unawaited(client.accountUsageQueries.refresh('a'));
    await transport.calls.single.entered.future;
    client.settings.merge(
      _settings([_account('a', usageQueryRevision: 2)], revision: 2),
    );
    unawaited(client.accountUsageQueries.refresh('a'));
    await transport.calls[1].entered.future;
    transport.calls[0].reply.complete(transport.publishEvent('a'));
    await Future<void>.delayed(Duration.zero);
    expect(_usages(client), isEmpty);
    transport.calls[1].reply.complete(transport.publishEvent('a'));
    await Future<void>.delayed(Duration.zero);
    expect(_usages(client).single.accountId, 'a');
    expect(_usageRevision(client), 2);
    expect(client.accountUsageQueries.state.loadingAccountIds, isEmpty);
  });

  test(
    'deleted account rejects a late ACK and does not resurrect loading',
    () async {
      final transport = _transportFor(['a']);
      final client = _client(transport, [_account('a')]);
      unawaited(client.accountUsageQueries.refresh('a'));
      await transport.calls.single.entered.future;
      client.settings.merge(_settings(const []));
      client.accountUsageQueries.forget('a');
      transport.calls.single.reply.complete(transport.publishEvent('a'));
      await Future<void>.delayed(Duration.zero);
      expect(_usages(client), isEmpty);
      expect(client.accountUsageQueries.state.loadingAccountIds, isEmpty);
    },
  );

  test(
    'close rejects new queries and waits for admitted work without applying',
    () async {
      final transport = _transportFor(['a']);
      final client = _client(transport, [_account('a')]);
      final pending = client.accountUsageQueries.refresh('a');
      await transport.calls.single.entered.future;
      final closing = client.accountUsageQueries.close();
      await expectLater(
        client.accountUsageQueries.refresh('a'),
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
    final first = _client(firstTransport, [_account('a')]);
    final second = _client(secondTransport, [_account('a')]);
    unawaited(first.accountUsageQueries.refresh('a'));
    await firstTransport.calls.single.entered.future;
    expect(second.accountUsageQueries.state.loadingAccountIds, isEmpty);
    unawaited(second.accountUsageQueries.refresh('a'));
    await secondTransport.calls.single.entered.future;
    secondTransport.calls.single.reply.complete(
      secondTransport.publishEvent('a'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(_usages(first), isEmpty);
    expect(_usages(second).single.accountId, 'a');
    firstTransport.calls.single.reply.complete(
      firstTransport.publishEvent('a'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(_usages(first).single.accountId, 'a');
  });

  test(
    'refreshAll starts each account immediately and waits for the batch',
    () async {
      final transport = _transportFor(['a', 'b']);
      final client = _client(transport, [_account('a'), _account('b')]);
      final started = client.accountUsageQueries.refreshAll();
      await transport.calls[0].entered.future;
      await transport.calls[1].entered.future;
      expect(client.accountUsageQueries.state.loadingAccountIds, {'a', 'b'});
      transport.calls[1].reply.complete(transport.publishEvent('b'));
      await Future<void>.delayed(Duration.zero);
      expect(_usages(client).map((item) => item.accountId), ['b']);
      var batchDone = false;
      unawaited(started.then((_) => batchDone = true));
      await Future<void>.delayed(Duration.zero);
      expect(batchDone, isFalse);
      transport.calls[0].reply.complete(transport.publishEvent('a'));
      await started;
      expect(batchDone, isTrue);
      expect(_usages(client).map((item) => item.accountId).toSet(), {'a', 'b'});
      expect(_usageRevision(client), 2);
    },
  );

  test(
    'event-first then matching response keeps the server revision',
    () async {
      final transport = _transportFor(['a']);
      final client = _client(transport, [_account('a')]);
      unawaited(client.accountUsageQueries.refresh('a'));
      await transport.calls.single.entered.future;
      final snapshot = transport.publishEvent('a');
      client.accountUsage.apply(snapshot);
      expect(_usageRevision(client), 1);
      transport.calls.single.reply.complete(snapshot);
      await Future<void>.delayed(Duration.zero);
      expect(_usageRevision(client), 1);
      client.accountUsage.apply(
        AccountUsageStateSnapshot(
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
      final client = _client(transport, [_account('a')]);
      final first = transport.publishEvent('a');
      client.accountUsage.apply(first);
      client.accountUsage.apply(first);
      expect(_usageRevision(client), 1);
      client.accountUsage.apply(transport.publishEvent('a'));
      expect(_usageRevision(client), 2);
    },
  );

  test(
    'refreshAll records A failure without uncaught error or clearing B',
    () async {
      final transport = _transportFor(['a', 'b']);
      final client = _client(transport, [_account('a'), _account('b')]);
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final started = client.accountUsageQueries.refreshAll();
        await transport.calls[0].entered.future;
        await transport.calls[1].entered.future;
        transport.calls[0].reply.completeError(StateError('usage failed'));
        await Future<void>.delayed(Duration.zero);
        expect(
          client.accountUsageQueries.state.errorsByAccountId['a'],
          contains('usage failed'),
        );
        expect(client.accountUsageQueries.state.loadingAccountIds, {'b'});
        transport.calls[1].reply.complete(transport.publishEvent('b'));
        await started;
        expect(
          client.accountUsageQueries.state.errorsByAccountId['a'],
          contains('usage failed'),
        );
        expect(_usages(client).map((item) => item.accountId), ['b']);
        expect(client.accountUsageQueries.state.loadingAccountIds, isEmpty);
      }, (error, stack) => errors.add(error));
      expect(errors, isEmpty);
    },
  );
}
