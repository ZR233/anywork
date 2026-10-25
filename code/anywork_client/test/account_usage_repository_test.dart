import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/account_usage_fixture.dart';

const _refused = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The scripted native check was explicitly rejected',
  retryable: true,
  correlationId: 'usage-native-refusal',
);

Future<AccountUsageFixture> _fixture({
  Map<String, int> accounts = const {'a': 1},
  String clientId = 'usage-test',
  OperationFailurePhase? retainedFailure,
  bool establish = true,
}) async {
  final fixture = AccountUsageFixture(clientId: clientId);
  addTearDown(() async {
    final report = await fixture.close(
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    );
    if (retainedFailure == null) {
      expect(report.unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    } else {
      expect(report.unresolved, hasLength(1));
      final retained = report.unresolved.single;
      expect(retained.owner, startsWith('account-usage:operation:'));
      expect(retained.issues.single.diagnostic.code, retainedFailure.name);
      expect(retained.issues.single.recovery, CleanupRecovery.terminal);
      expect(
        fixture.budget.used(ResourceKind.readModel),
        0,
        reason: 'Only original operation evidence may remain, never a native feed/read handle',
      );
    }
  });
  if (establish) await fixture.establish(accounts);
  return fixture;
}

List<AccountUsageRecord> _records(AccountUsageRepository repository) {
  final mirror = repository.state.value.usages;
  if (mirror is! CurrentCollectionMirror<AccountUsageRecord>) return const [];
  return [
    for (final row in mirror.window.rows.values)
      if (row is ReadyReadValue<AccountUsageRecord, ProductEntityRef>)
        row.current.value,
  ];
}

AccountUsageRecord _acknowledged(CommandResult<AccountUsageRecord> result) {
  expect(result, isA<AcknowledgedCommandResult<AccountUsageRecord>>());
  return (result as AcknowledgedCommandResult<AccountUsageRecord>).value;
}

void main() {
  test('unknown configuration is a visible preparation, never a guessed native usage identity', () async {
    final fixture = await _fixture(establish: false);
    final ticket = fixture.usage.check('a');
    expect(fixture.usage.checks.value['a']!.ticket, same(ticket));
    expect(fixture.usage.checks.value['a']!.identity, isNull);
    await fixture.configPort.feed.listened.future;
    expect(
      fixture.usagePort.calls,
      isEmpty,
      reason: 'The real Configuration read has started, but no account identity is materialized',
    );
    await fixture.establish(const {'a': 9});
    final call = await fixture.usagePort.called(0);
    expect(call.expectedUsageQueryRevision, 9);
    expect(
      fixture.usage.checks.value['a']!.identity,
      AccountUsageQueryIdentity(
        accountId: 'a',
        usageQueryRevision: 9,
        ownerEpoch: usageFixtureOrigin.ownerEpoch,
      ),
    );
    expect(fixture.usage.check('a'), same(ticket));
    call.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _refused),
    );
    expect(
      await ticket.result,
      isA<RejectedCommandResult<AccountUsageRecord>>(),
    );
    expect(fixture.usagePort.calls, hasLength(1));
  });

  test('same real configuration identity joins one ticket and reply waits for Usage feed observation', () async {
    final fixture = await _fixture();
    final repository = fixture.usage;
    final ticket = repository.check('a');
    final call = await fixture.usagePort.called(0);
    expect(call.expectedUsageQueryRevision, 1);
    expect(
      repository.checks.value['a']!.identity,
      AccountUsageQueryIdentity(
        accountId: 'a',
        usageQueryRevision: 1,
        ownerEpoch: usageFixtureOrigin.ownerEpoch,
      ),
    );
    expect(repository.check('a'), same(ticket));
    expect(repository.checks.value['a']!.ticket, same(ticket));
    expect(() => repository.checks.value.clear(), throwsUnsupportedError);
    final record = usageRecord('a', 17);
    fixture.declareUsage(1, {'a': record});
    call.succeed(1);
    await fixture.usagePort.headerRead(1);
    expect(
      _records(repository),
      isEmpty,
      reason: 'A successful native reply and readable target are not canonical feed observation',
    );
    expect(ticket.state.value.acknowledged, isFalse);
    expect(ticket.state.value.observed, isFalse);
    await fixture.publishUsage(1);
    expect(_acknowledged(await ticket.result), record);
    expect(_records(repository), [record]);
    expect(repository.state.value.projection.stamp!.revision, 1);
    expect(ticket.state.value.acknowledged, isTrue);
    expect(ticket.state.value.observed, isTrue);
    expect(ticket.state.value.durable, isFalse);
    expect(fixture.usagePort.calls, hasLength(1));
  });

  test('slow A does not block B and each observed native version preserves the other account', () async {
    final fixture = await _fixture(accounts: const {'a': 1, 'b': 8});
    final a = fixture.usage.check('a');
    final aCall = await fixture.usagePort.called(0);
    final b = fixture.usage.check('b');
    final bCall = await fixture.usagePort.called(1);
    expect(bCall.expectedUsageQueryRevision, 8);
    final bRecord = usageRecord('b', 50);
    fixture.declareUsage(1, {'b': bRecord});
    await fixture.publishUsage(1);
    bCall.succeed(1);
    expect(_acknowledged(await b.result), bRecord);
    expect(_records(fixture.usage), [bRecord]);
    expect(a.state.value.isPending, isTrue);
    final aRecord = usageRecord('a', 70);
    fixture.declareUsage(2, {'a': aRecord, 'b': bRecord});
    await fixture.publishUsage(2);
    aCall.succeed(2);
    expect(_acknowledged(await a.result), aRecord);
    expect(_records(fixture.usage).toSet(), {aRecord, bRecord});
    expect(fixture.usage.state.value.projection.stamp!.revision, 2);
  });

  test('credential query revision changes start an independent check and retain the old unobserved ACK', () async {
    final fixture = await _fixture(
      retainedFailure: OperationFailurePhase.syncFailed,
    );
    final old = fixture.usage.check('a');
    final oldCall = await fixture.usagePort.called(0);
    await fixture.configurationChanged(const {'a': 2});
    expect(fixture.usage.checks.value, isEmpty);
    final current = fixture.usage.check('a');
    final currentCall = await fixture.usagePort.called(1);
    expect(current, isNot(same(old)));
    expect(oldCall.expectedUsageQueryRevision, 1);
    expect(currentCall.expectedUsageQueryRevision, 2);
    final record = usageRecord('a', 90);
    fixture.declareUsage(1, {'a': record});
    oldCall.succeed(1);
    final rejectedIdentity = await old.result;
    expect(
      rejectedIdentity,
      isA<AcknowledgedSyncFailedCommandResult<AccountUsageRecord>>(),
    );
    expect(
      (rejectedIdentity
              as AcknowledgedSyncFailedCommandResult<AccountUsageRecord>)
          .error
          .code,
      StudioFailureCode.superseded,
    );
    expect(old.state.value.acknowledged, isTrue);
    expect(old.state.value.observed, isFalse);
    expect(_records(fixture.usage), isEmpty);
    expect(fixture.usage.checks.value['a']!.ticket, same(current));
    await fixture.publishUsage(1);
    currentCall.succeed(1);
    expect(_acknowledged(await current.result), record);
    expect(_records(fixture.usage), [record]);
    expect(fixture.usagePort.calls, hasLength(2));
  });

  test('deleted account cannot be resurrected by its late native check reply or checks presentation', () async {
    final fixture = await _fixture(
      retainedFailure: OperationFailurePhase.syncFailed,
    );
    final ticket = fixture.usage.check('a');
    final call = await fixture.usagePort.called(0);
    await fixture.configurationChanged(const {});
    expect(fixture.usage.checks.value, isEmpty);
    fixture.declareUsage(1, {'a': usageRecord('a', 5)});
    call.succeed(1);
    final result = await ticket.result;
    expect(
      result,
      isA<AcknowledgedSyncFailedCommandResult<AccountUsageRecord>>(),
    );
    expect(
      (result as AcknowledgedSyncFailedCommandResult<AccountUsageRecord>)
          .error
          .code,
      StudioFailureCode.notFound,
    );
    expect(_records(fixture.usage), isEmpty);
    expect(fixture.usage.checks.value, isEmpty);
    expect(ticket.state.value.observed, isFalse);
    expect(fixture.usagePort.calls, hasLength(1));
  });

  test('synchronous native reentry cannot escape close join and only a proven rejection releases the job', () async {
    final fixture = await _fixture();
    late Future<CloseReport> closing;
    fixture.usagePort.onCheck = (_) {
      closing = fixture.usage.close(deadline: DateTime.utc(2000));
    };
    final ticket = fixture.usage.check('a');
    final call = await fixture.usagePort.called(0);
    final report = await closing;
    expect(report.complete, isFalse);
    expect(
      report.unresolved
          .expand((resource) => resource.issues)
          .any((issue) => issue.recovery == CleanupRecovery.awaitCompletion),
      isTrue,
    );
    expect(fixture.budget.used(ResourceKind.readModel), greaterThan(0));
    expect(
      () => fixture.usage.check('a'),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    expect(fixture.usagePort.calls, hasLength(1));
    call.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _refused),
    );
    final result = await ticket.result;
    expect(result, isA<RejectedCommandResult<AccountUsageRecord>>());
    expect(
      (result as RejectedCommandResult<AccountUsageRecord>).error,
      _refused,
    );
    expect((await fixture.usage.retryCleanup()).complete, isTrue);
    expect(_records(fixture.usage), isEmpty);
  });

  test('an expired close cannot turn its later native ACK into Clean or install late usage', () async {
    final fixture = await _fixture(
      retainedFailure: OperationFailurePhase.syncFailed,
    );
    final ticket = fixture.usage.check('a');
    final call = await fixture.usagePort.called(0);
    fixture.declareUsage(1, {'a': usageRecord('a', 6)});
    final closing = await fixture.usage.close(deadline: DateTime.utc(2000));
    expect(closing.complete, isFalse);
    expect(
      () => fixture.usage.load('a'),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    call.succeed(1);
    final result = await ticket.result;
    expect(
      result,
      isA<AcknowledgedSyncFailedCommandResult<AccountUsageRecord>>(),
    );
    expect(
      (result as AcknowledgedSyncFailedCommandResult<AccountUsageRecord>)
          .error
          .code,
      StudioFailureCode.cancelled,
    );
    expect(ticket.state.value.acknowledged, isTrue);
    expect(ticket.state.value.observed, isFalse);
    expect(_records(fixture.usage), isEmpty);
  });

  test('separate assembled owners isolate same-account in-flight tickets and canonical observations', () async {
    final first = await _fixture(clientId: 'first-usage');
    final second = await _fixture(clientId: 'second-usage');
    final a = first.usage.check('a');
    final firstCall = await first.usagePort.called(0);
    expect(second.usage.checks.value, isEmpty);
    final b = second.usage.check('a');
    final secondCall = await second.usagePort.called(0);
    expect(a.id, isNot(b.id));
    final record = usageRecord('a', 11);
    second.declareUsage(1, {'a': record});
    await second.publishUsage(1);
    secondCall.succeed(1);
    expect(_acknowledged(await b.result), record);
    expect(_records(first.usage), isEmpty);
    expect(a.state.value.isPending, isTrue);
    first.declareUsage(1, {'a': record});
    await first.publishUsage(1);
    firstCall.succeed(1);
    expect(_acknowledged(await a.result), record);
    expect(_records(first.usage), [record]);
  });

  test('event-first response keeps the server watermark and later native versions remain readable', () async {
    final fixture = await _fixture();
    final ticket = fixture.usage.check('a');
    final call = await fixture.usagePort.called(0);
    final initial = usageRecord('a', 101);
    fixture.declareUsage(1, {'a': initial});
    await fixture.publishUsage(1);
    expect(fixture.usage.state.value.projection.stamp!.revision, 1);
    call.succeed(1);
    expect(_acknowledged(await ticket.result), initial);
    expect(
      fixture.usage.state.value.projection.stamp!.revision,
      1,
      reason:
          'Matching a response never allocates a local publication revision',
    );
    expect(await fixture.usage.load('a'), initial);
    expect(fixture.usage.state.value.projection.stamp!.revision, 1);
    final later = usageRecord('a', 205);
    fixture.declareUsage(2, {'a': later});
    await fixture.publishUsage(2);
    expect(await fixture.usage.load('a'), later);
    expect(fixture.usage.state.value.projection.stamp!.revision, 2);
  });

  test('automatic and manual checks share the actual ticket and failures consume only that identity attempt', () async {
    final fixture = await _fixture();
    final ids = {'a'};
    fixture.usage.setVisibleAccounts(ids);
    ids.clear();
    final call = await fixture.usagePort.called(0);
    final original = fixture.usage.checks.value['a']!.ticket;
    expect(fixture.usage.check('a'), same(original));
    fixture.usage.setVisibleAccounts(const {});
    expect(
      original.state.value.isPending,
      isTrue,
      reason:
          'Hiding stops future automatic demand, not an admitted native call',
    );
    call.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _refused),
    );
    expect(
      await original.result,
      isA<RejectedCommandResult<AccountUsageRecord>>(),
    );
    fixture.usage.setVisibleAccounts(const {'a'});
    final automatic = <OperationId, OperationTicket<AccountUsageRecord>>{};
    fixture.usagePort.onCheck = (unexpected) {
      unexpected.reply.completeError(
        const CommandDispatchFailure.rejected(failure: _refused),
      );
    };
    final observation = fixture.usage.checks.watch((checks) {
      final check = checks['a'];
      if (check != null && check.ticket.id != original.id)
        automatic[check.ticket.id] = check.ticket;
    });
    addTearDown(observation.cancel);
    await fixture.configurationChanged(const {'a': 1});
    // Drain any actually admitted preparation. This is not a timing sample:
    // an erroneous native redispatch has an explicit rejection receipt above.
    for (final preparation in automatic.values.toList()) {
      await preparation.result;
    }
    expect(
      fixture.usagePort.calls,
      hasLength(1),
      reason: 'An unchanged business query identity cannot form an automatic retry loop',
    );
    fixture.usagePort.onCheck = null;
    final retry = fixture.usage.check('a');
    final retried = await fixture.usagePort.called(1);
    expect(retry, isNot(same(original)));
    final record = usageRecord('a', 3);
    fixture.declareUsage(1, {'a': record});
    await fixture.publishUsage(1);
    retried.succeed(1);
    expect(_acknowledged(await retry.result), record);
  });

  test('unknown network outcome remains the original ticket and is never automatically or manually resent', () async {
    final fixture = await _fixture(
      retainedFailure: OperationFailurePhase.unknownOutcome,
    );
    fixture.usage.setVisibleAccounts(const {'a'});
    final call = await fixture.usagePort.called(0);
    final ticket = fixture.usage.checks.value['a']!.ticket;
    call.reply.completeError(
      const CommandDispatchFailure.unknownOutcome(failure: _refused),
    );
    final result = await ticket.result;
    expect(result, isA<UnknownOutcomeCommandResult<AccountUsageRecord>>());
    expect(
      (result as UnknownOutcomeCommandResult<AccountUsageRecord>).error,
      _refused,
    );
    fixture.usage.setVisibleAccounts(const {});
    fixture.usage.setVisibleAccounts(const {'a'});
    expect(fixture.usage.check('a'), same(ticket));
    expect(fixture.usagePort.calls, hasLength(1));
    expect(
      ticket.state.value.failurePhase,
      OperationFailurePhase.unknownOutcome,
    );
    expect(ticket.state.value.isPending, isTrue);
    expect(_records(fixture.usage), isEmpty);
  });
}
