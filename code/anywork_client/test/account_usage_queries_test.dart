import 'dart:async';

import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';

final class _UsageCall {
  _UsageCall(this.accountId, this.queryRevision);
  final String accountId;
  final int queryRevision;
  final entered = Completer<void>();
  final reply = Completer<AccountUsageFrame>();
}

/// Scripted backend facts, including canonical Querying before provider await.
/// No client deduplication, lifecycle or acceptance rule lives in this fixture.
final class _UsageTransport extends AccountsTestTransport {
  final calls = <_UsageCall>[];
  final published = <AccountUsageFrame>[];
  final queryRevisions = <String, int>{};
  final values = <String, AccountUsageObservation>{};
  int revision = 0;
  AccountUsageFrame frame(String id, AccountUsagePhase phase, {int? query}) {
    revision++;
    values[id] = AccountUsageObservation(
      identity: NativeAccountIdentity(id),
      queryRevision: query ?? queryRevisions[id] ?? 1,
      revision: revision,
      phase: phase,
      checkedAt: phase == AccountUsagePhase.querying ? null : revision,
    );
    final snapshot = usageFrame(revision, values.values);
    published.add(snapshot);
    return snapshot;
  }

  AccountUsageFrame publishEvent(String id, {int? query}) =>
      frame(id, AccountUsagePhase.unsupported, query: query);
  @override
  Future<AccountUsageFrame> queryAccountUsage(NativeAccountIdentity identity) {
    final call = _UsageCall(
      identity.accountId,
      queryRevisions[identity.accountId] ?? 1,
    );
    calls.add(call);
    emitAccount(
      frame(
        identity.accountId,
        AccountUsagePhase.querying,
        query: call.queryRevision,
      ),
    );
    call.entered.complete();
    return call.reply.future;
  }

  void complete(int index) {
    final call = calls[index];
    call.reply.complete(
      publishEvent(call.accountId, query: call.queryRevision),
    );
  }
}

AccountSettingsView _account(String id, {int usageQueryRevision = 1}) =>
    AccountSettingsView(
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
SettingsStateSnapshot _settings(
  List<AccountSettingsView> accounts, {
  int revision = 1,
}) => SettingsStateSnapshot(revision: revision, accounts: accounts);
AccountsTestRuntime _client(
  _UsageTransport transport,
  List<AccountSettingsView> accounts,
) {
  final runtime = AccountsTestRuntime(transport, clientId: 'usage');
  runtime.seed(_settings(accounts));
  for (final account in accounts) {
    transport.queryRevisions[account.id] = account.usageQueryRevision;
  }
  addTearDown(runtime.close);
  return runtime;
}

List<AccountUsageObservation> _usages(AccountsTestRuntime runtime) =>
    runtime.domains.usage.state.value.value?.values
        .where(
          (value) =>
              value.phase != AccountUsagePhase.querying &&
              value.phase != AccountUsagePhase.unchecked,
        )
        .toList() ??
    [];
Set<String> _loading(AccountsTestRuntime runtime) => {
  for (final value
      in runtime.domains.usage.state.value.value?.values ??
          <AccountUsageObservation>[])
    if (value.phase == AccountUsagePhase.querying) value.identity.accountId,
};
int _usageRevision(AccountsTestRuntime runtime) =>
    runtime.domains.usage.state.value.stamp?.revision ?? 0;
Future<void> _waitLoading(AccountsTestRuntime runtime, Set<String> ids) async {
  await runtime.domains.usage.state.waitFor(
    (state) => ids.every(
      (id) =>
          state.value?[NativeAccountIdentity(id)]?.phase ==
          AccountUsagePhase.querying,
    ),
  );
}

Future<void> _refresh(AccountsTestRuntime runtime, String id) =>
    runtime.domains.usage.refresh(NativeAccountIdentity(id));

void main() {
  test(
    'same account and usageQueryRevision reuse one in-flight query',
    () async {
      final transport = _UsageTransport();
      final client = _client(transport, [_account('a')]);
      final first = _refresh(client, 'a');
      await transport.calls.single.entered.future;
      final second = _refresh(client, 'a');
      expect(identical(first, second), isTrue);
      await _waitLoading(client, {'a'});
      expect(_loading(client), {'a'});
      transport.complete(0);
      await first;
      expect(_loading(client), isEmpty);
      expect(_usages(client).map((item) => item.identity.accountId), ['a']);
      expect(_usageRevision(client), transport.revision);
    },
  );

  test('slow A does not block later B from applying a full snapshot', () async {
    final transport = _UsageTransport();
    final client = _client(transport, [_account('a'), _account('b')]);
    final a = _refresh(client, 'a');
    final b = _refresh(client, 'b');
    await transport.calls[0].entered.future;
    await transport.calls[1].entered.future;
    transport.complete(1);
    await b;
    expect(_usages(client).map((item) => item.identity.accountId), ['b']);
    expect(_usageRevision(client), transport.revision);
    transport.complete(0);
    await a;
    expect(_usages(client).map((item) => item.identity.accountId).toSet(), {
      'a',
      'b',
    });
    expect(_usageRevision(client), transport.revision);
  });

  test('usageQueryRevision change starts an independent query and rejects the old ACK', () async {
    final transport = _UsageTransport();
    final client = _client(transport, [_account('a')]);
    final old = _refresh(client, 'a');
    await transport.calls.single.entered.future;
    transport.queryRevisions['a'] = 2;
    client.seed(_settings([_account('a', usageQueryRevision: 2)], revision: 2));
    final next = _refresh(client, 'a');
    await transport.calls[1].entered.future;
    transport.complete(0);
    await old;
    expect(_usages(client), isEmpty);
    transport.complete(1);
    await next;
    expect(_usages(client).single.identity.accountId, 'a');
    expect(_usages(client).single.queryRevision, 2);
    expect(_usageRevision(client), transport.revision);
    expect(_loading(client), isEmpty);
  });

  test(
    'deleted account rejects a late ACK and does not resurrect loading',
    () async {
      final transport = _UsageTransport();
      final client = _client(transport, [_account('a')]);
      final pending = _refresh(client, 'a');
      await transport.calls.single.entered.future;
      client.seed(_settings(const [], revision: 2));
      transport.complete(0);
      await pending;
      expect(_usages(client), isEmpty);
      expect(_loading(client), isEmpty);
    },
  );

  test(
    'close rejects new queries and joins the admitted response before disposal',
    () async {
      final transport = _UsageTransport();
      final client = _client(transport, [_account('a')]);
      final pending = _refresh(client, 'a');
      await transport.calls.single.entered.future;
      var joined = false;
      final closing = client.close().then((report) {
        joined = true;
        return report;
      });
      await expectLater(_refresh(client, 'a'), throwsStateError);
      expect(joined, isFalse);
      transport.complete(0);
      await pending;
      expect((await closing).complete, isTrue);
      expect(joined, isTrue);
      expect(
        _usages(client).single.phase,
        AccountUsagePhase.unsupported,
        reason: 'The application owner consumes already admitted facts while it really joins; it is not a disposed Widget',
      );
      expect(client.budget.used(ResourceKind.observer), 0);
    },
  );

  test('AppGraph instances isolate in-flight usage queries', () async {
    final firstTransport = _UsageTransport();
    final secondTransport = _UsageTransport();
    final first = _client(firstTransport, [_account('a')]);
    final second = _client(secondTransport, [_account('a')]);
    final a = _refresh(first, 'a');
    await firstTransport.calls.single.entered.future;
    expect(_loading(second), isEmpty);
    final b = _refresh(second, 'a');
    await secondTransport.calls.single.entered.future;
    secondTransport.complete(0);
    await b;
    expect(_usages(first), isEmpty);
    expect(_usages(second).single.identity.accountId, 'a');
    firstTransport.complete(0);
    await a;
    expect(_usages(first).single.identity.accountId, 'a');
  });

  test('visible demand starts each account immediately and admitted queries remain joined as a batch', () async {
    final transport = _UsageTransport();
    final client = _client(transport, [_account('a'), _account('b')]);
    final visible = client.domains.usage.observeVisible();
    addTearDown(visible.release);
    await transport.calls[0].entered.future;
    await transport.calls[1].entered.future;
    await _waitLoading(client, {'a', 'b'});
    expect(_loading(client), {'a', 'b'});
    final started = Future.wait([_refresh(client, 'a'), _refresh(client, 'b')]);
    var batchDone = false;
    final joined = started.then((_) {
      batchDone = true;
    });
    transport.complete(1);
    await client.domains.usage.state.waitFor(
      (state) =>
          state.value?[const NativeAccountIdentity('b')]?.phase ==
          AccountUsagePhase.unsupported,
    );
    expect(_usages(client).map((item) => item.identity.accountId), ['b']);
    expect(batchDone, isFalse);
    transport.complete(0);
    await joined;
    expect(batchDone, isTrue);
    expect(_usages(client).map((item) => item.identity.accountId).toSet(), {
      'a',
      'b',
    });
    expect(_usageRevision(client), transport.revision);
    expect(transport.calls, hasLength(2));
  });

  test(
    'event-first then matching response keeps the server revision',
    () async {
      final transport = _UsageTransport();
      final client = _client(transport, [_account('a')]);
      final pending = _refresh(client, 'a');
      await transport.calls.single.entered.future;
      final snapshot = transport.publishEvent('a');
      client.domains.acceptFrame(snapshot);
      expect(_usageRevision(client), snapshot.stamp.revision);
      transport.calls.single.reply.complete(snapshot);
      await pending;
      expect(_usageRevision(client), snapshot.stamp.revision);
      final later = transport.publishEvent('a');
      client.domains.acceptFrame(later);
      expect(_usageRevision(client), later.stamp.revision);
    },
  );

  test(
    'duplicate server revision is a no-op and a later revision is accepted',
    () async {
      final transport = _UsageTransport();
      final client = _client(transport, [_account('a')]);
      final first = transport.publishEvent('a');
      client.domains.acceptFrame(first);
      final state = client.domains.usage.state.value;
      client.domains.acceptFrame(first);
      expect(client.domains.usage.state.value, same(state));
      expect(_usageRevision(client), first.stamp.revision);
      final second = transport.publishEvent('a');
      client.domains.acceptFrame(second);
      expect(_usageRevision(client), second.stamp.revision);
    },
  );

  test('visible automatic queries retain A transport failure without uncaught errors or clearing B', () async {
    final transport = _UsageTransport();
    final client = _client(transport, [_account('a'), _account('b')]);
    // package:test's own guarded zone fails on any uncaught automatic query
    // error, including errors after another account's successful response.
    final visible = client.domains.usage.observeVisible();
    addTearDown(visible.release);
    await transport.calls[0].entered.future;
    await transport.calls[1].entered.future;
    await _waitLoading(client, {'a', 'b'});
    transport.calls[0].reply.completeError(StateError('usage failed'));
    await client.domains.usage.queryFailures.waitFor(
      (failures) => failures.containsKey(const NativeAccountIdentity('a')),
    );
    expect(
      client
          .domains
          .usage
          .queryFailures
          .value[const NativeAccountIdentity('a')]!
          .code,
      StudioFailureCode.internal,
    );
    transport.complete(1);
    await client.domains.usage.state.waitFor(
      (state) =>
          state.value?[const NativeAccountIdentity('b')]?.phase ==
          AccountUsagePhase.unsupported,
    );
    expect(
      client.domains.usage.queryFailures.value.containsKey(
        const NativeAccountIdentity('a'),
      ),
      isTrue,
    );
    expect(_usages(client).map((item) => item.identity.accountId), ['b']);
    expect(
      transport.calls,
      hasLength(2),
      reason: 'A failed visible attempt does not automatically loop',
    );
    final retry = _refresh(client, 'a');
    final failedRetry = expectLater(retry, throwsStateError);
    await transport.calls[2].entered.future;
    transport.calls[2].reply.completeError(StateError('retry also unknown'));
    await failedRetry;
    client.domains.acceptFrame(transport.publishEvent('a'));
    expect(
      client.domains.usage.queryFailures.value,
      isEmpty,
      reason:
          'Only a new terminal for A can settle its unknown transport result',
    );
    expect(_loading(client), isEmpty);
    await visible.release();
    expect(
      client.budget.used(ResourceKind.observer),
      0,
      reason: 'A repeated unknown RPC must not overwrite and leak its original business demand',
    );

    final rejected = _refresh(client, 'a');
    final rejection = expectLater(rejected, throwsA(isA<StudioFailure>()));
    await transport.calls[3].entered.future;
    transport.calls[3].reply.completeError(
      const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'No longer supported',
        retryable: false,
        correlationId: 'usage-rejected',
      ),
    );
    await rejection;
    expect(
      client.domains.usage.queryFailures.value,
      contains(const NativeAccountIdentity('a')),
    );
    client.seed(_settings([_account('b')], revision: 2));
    expect(
      client.domains.usage.queryFailures.value,
      isEmpty,
      reason: 'Deleting an identity also invalidates known-rejection diagnostics, not just unknown outcomes',
    );
  });
}
