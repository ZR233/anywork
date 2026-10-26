import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/configuration_command_fixture.dart';
import 'support/configuration_fixture.dart';
import 'support/profile_model_port.dart';

const _catalogOrigin = ProductReadOrigin(
  ownerEpoch: 'narrow-native-catalog',
  incarnation: 4,
);
const _catalog = ModelCatalogReadTarget(
  origin: _catalogOrigin,
  reference: ModelCatalogReadRef(entry: 1, revision: 1),
);
const _refusal = StudioFailure(
  code: StudioFailureCode.storage,
  message: 'The native write was rejected before commit',
  retryable: true,
  correlationId: 'narrow-storage',
);
const _staleCall = StudioFailure(
  code: StudioFailureCode.staleRevision,
  message: 'The original native attempt lost its CAS base',
  retryable: true,
  correlationId: 'owned-call-cas',
);
const _joinIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'native-configuration',
    code: 'callJoinPending',
    message: 'The original invocation still needs explicit cleanup',
    retryable: true,
    correlationId: 'owned-call-cleanup',
  ),
  recovery: CleanupRecovery.retryClose,
);

AccountConfiguration _account() => AccountConfiguration(
  accountId: 'account',
  templateId: 'template',
  protocol: 'openai',
  name: 'Account',
  baseUrl: 'https://original.invalid',
  hasBearerToken: false,
  bearerTokenEnv: null,
  billingKind: BillingKind.subscription,
  billingKindOverride: null,
  disabledModels: const ['withdrawn'],
  usageQueryRevision: 1,
  catalogId: 'catalog',
  customModels: [customModel('manual')],
  modelConnectionModes: const [
    ModelConnection(modelId: 'online', connectionMode: 'http'),
  ],
  modelAutoCompactLimits: const [
    ModelAutoCompact(modelId: 'online', overrideLimit: 111),
    ModelAutoCompact(modelId: 'withdrawn', overrideLimit: 777),
  ],
);

final class _Fixture {
  final nativeModels = ProfileModelsPort(
    origin: _catalogOrigin,
    accounts: const [],
    textEligibleAccounts: const {},
  );
  late final owner = ConfigurationFixture(modelsPort: nativeModels);
  ConfigurationRepository get repository => owner.repository;
  FixtureConfigurationPort get port => owner.port;
  bool modelsPublished = false;
  CloseReport? protectedReport;
}

Future<_Fixture> _fixture({
  AccountConfiguration? account,
  bool protectedOutcome = false,
}) async {
  final fixture = _Fixture();
  await fixture.owner.establish(account ?? _account());
  addTearDown(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final reports = await Future.wait([
      if (protectedOutcome && fixture.protectedReport != null)
        Future.value(fixture.protectedReport!)
      else
        fixture.repository.close(deadline: deadline),
      fixture.owner.models.close(deadline: deadline),
    ]);
    final unresolved = reports.expand((report) => report.unresolved).toList();
    if (protectedOutcome) {
      expect(unresolved, isNotEmpty);
      expect(
        unresolved.any((item) => item.owner.startsWith('configuration:call:')),
        isTrue,
        reason: 'Unproven invocation/target evidence retains the original call and its read dependencies',
      );
    } else {
      expect(unresolved, isEmpty);
      expect(fixture.owner.budget.usage, isEmpty);
    }
  });
  return fixture;
}

ConfigurationCommandReply _reply(
  OperationId operationId,
  int revision, {
  CommitDisposition disposition = CommitDisposition.applied,
}) => ConfigurationCommandReply(
  receipt: CommitReceipt(
    operationId: operationId,
    disposition: disposition,
    targets: [
      ResourceStamp(
        resourceKey: 'settings',
        ownerEpoch: configurationFixtureOrigin.ownerEpoch,
        revision: revision,
      ),
    ],
    effect: EffectPoint.futureSession,
    effective: false,
    durable: true,
  ),
  configuration: ConfigurationReadTarget(
    origin: configurationFixtureOrigin,
    reference: ConfigurationReadRef(entry: 1, revision: revision),
  ),
  models: _catalog,
);

/// Explicit native reply + independently declared feed publication. This helper
/// never derives account fields from the request or implements command policy.
Future<CommitReceipt> _observe<T>(
  _Fixture fixture,
  RecordedConfigurationCall<T> call,
  OperationTicket<Unit> ticket,
  int revision, {
  AccountConfiguration? canonical,
  CommitDisposition disposition = CommitDisposition.applied,
}) async {
  final reply = _reply(ticket.id, revision, disposition: disposition);
  await call.native.resultRead(0);
  call.native.resultAt(0).reply.complete(reply);
  if (canonical != null) await fixture.port.publishAccount(revision, canonical);
  if (!fixture.modelsPublished) {
    await fixture.nativeModels.feed.listened.future;
    expect(
      call.native.requestCloseCalls,
      0,
      reason: 'Configuration may be observed, but the original Models target is still pending',
    );
    expect(ticket.state.value.observed, isFalse);
    fixture.nativeModels.baseline();
    await fixture.nativeModels.feed.acknowledged(1);
    fixture.modelsPublished = true;
  }
  final result = await ticket.result;
  expect(result, isA<CommittedCommandResult<Unit>>());
  final committed = result as CommittedCommandResult<Unit>;
  expect(committed.receipt, reply.receipt);
  expect(ticket.state.value.observed, isTrue);
  return committed.receipt;
}

Future<CommitReceipt> _commit<T>(
  _Fixture fixture,
  RecordedConfigurationCall<T> call,
  OperationTicket<Unit> ticket,
  int revision, {
  AccountConfiguration? canonical,
  CommitDisposition disposition = CommitDisposition.applied,
}) async {
  final receipt = await _observe(
    fixture,
    call,
    ticket,
    revision,
    canonical: canonical,
    disposition: disposition,
  );
  final closing = await call.native.closed(0);
  expect(call.native.requestCloseCalls, 1);
  closing.reply.complete(
    FeedCloseReport(
      feedId: call.native.callId,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
  return receipt;
}

Future<void> _reject<T>(
  RecordedConfigurationCall<T> call,
  OperationTicket<Unit> ticket,
) async {
  await call.native.resultRead(0);
  call.native
      .resultAt(0)
      .reply
      .completeError(const CommandDispatchFailure.rejected(failure: _refusal));
  final result = await ticket.result;
  expect(result, isA<RejectedCommandResult<Unit>>());
  expect((result as RejectedCommandResult<Unit>).error, _refusal);
  expect(ticket.state.value.receipt, isNull);
  final closing = await call.native.closed(0);
  expect(call.native.requestCloseCalls, 1);
  closing.reply.complete(
    FeedCloseReport(
      feedId: call.native.callId,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
}

void main() {
  test('rapid enabled intents retry the same operation from current CAS without erasing newer or billing work', () async {
    final fixture = await _fixture();
    final first = fixture.repository.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final initial = await fixture.port.enabledChanged(0);
    final second = fixture.repository.setAccountModelEnabled(
      'account',
      'online',
      true,
    );
    final billing = fixture.repository.setAccountBillingKind(
      'account',
      BillingKind.unknown,
    );
    final observations = fixture.owner.operations.observations;
    expect(first.state.value.target, second.state.value.target);
    expect(billing.state.value.target, isNot(second.state.value.target));
    expect(observations.latest(second.state.value.target)?.id, second.id);
    expect(observations.latest(billing.state.value.target)?.id, billing.id);
    expect(
      initial.request,
      SetAccountModelEnabledRequest(
        operationId: first.id,
        expectedRevision: 1,
        accountId: 'account',
        modelId: 'online',
        enabled: false,
      ),
    );
    expect(fixture.port.enabledChanges, hasLength(1));
    expect(fixture.port.billingChanges, isEmpty);
    expect(
      await fixture.repository.loadAccount('account'),
      _account(),
      reason: 'Dispatch does not optimistically change canonical configuration',
    );

    final concurrent = _account().copyWith(
      name: 'External name',
      baseUrl: 'https://changed.invalid',
      hasBearerToken: true,
      usageQueryRevision: 4,
      modelConnectionModes: const [
        ModelConnection(modelId: 'online', connectionMode: 'websocket'),
      ],
      modelAutoCompactLimits: const [
        ModelAutoCompact(modelId: 'online', overrideLimit: 321),
        ModelAutoCompact(modelId: 'withdrawn', overrideLimit: 999),
      ],
    );
    fixture.port.snapshots[2] = concurrent;
    const stale = StudioFailure(
      code: StudioFailureCode.staleRevision,
      message: 'The native CAS base advanced',
      retryable: true,
      correlationId: 'narrow-cas',
    );
    await initial.native.resultRead(0);
    initial.native
        .resultAt(0)
        .reply
        .completeError(const CommandDispatchFailure.rejected(failure: stale));
    final closing = await initial.native.closed(0);
    expect(fixture.port.enabledChanges, hasLength(1));
    expect(
      fixture.port.feeds,
      hasLength(1),
      reason: 'Original call closure precedes fresh CAS source capture',
    );
    closing.reply.complete(
      FeedCloseReport(
        feedId: initial.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    final replacement = await fixture.port.opened(1);
    await replacement.listened.future;
    fixture.port.baseline(replacement, 2);
    final retried = await fixture.port.enabledChanged(1);
    expect(
      retried.request,
      SetAccountModelEnabledRequest(
        operationId: first.id,
        expectedRevision: 2,
        accountId: 'account',
        modelId: 'online',
        enabled: false,
      ),
    );
    expect(retried.native.callId, isNot(initial.native.callId));
    expect(first.id, isNot(second.id));
    expect(await fixture.repository.loadAccount('account'), concurrent);

    final disabled = concurrent.copyWith(
      disabledModels: const ['withdrawn', 'online'],
    );
    await _commit(fixture, retried, first, 3, canonical: disabled);
    final next = await fixture.port.enabledChanged(2);
    expect(
      observations.latest(second.state.value.target)?.id,
      second.id,
      reason: 'An older receipt must not settle or replace the newer same-field operation',
    );
    expect(second.state.value.isPending, isTrue);
    expect(billing.state.value.isPending, isTrue);
    expect(await fixture.repository.loadAccount('account'), disabled);
    expect(
      next.request,
      SetAccountModelEnabledRequest(
        operationId: second.id,
        expectedRevision: 3,
        accountId: 'account',
        modelId: 'online',
        enabled: true,
      ),
    );
    await _commit(fixture, next, second, 4, canonical: concurrent);

    final bill = await fixture.port.billingChanged(0);
    expect(
      bill.request,
      SetAccountBillingKindRequest(
        operationId: billing.id,
        expectedRevision: 4,
        accountId: 'account',
        billingKind: BillingKind.unknown,
      ),
    );
    expect(observations.latest(second.state.value.target)?.id, second.id);
    final billed = concurrent.copyWith(
      billingKind: BillingKind.unknown,
      billingKindOverride: BillingKind.unknown,
    );
    await _commit(fixture, bill, billing, 5, canonical: billed);
    expect(
      await fixture.repository.loadAccount('account'),
      billed,
      reason: 'Credentials, pricing, catalog identity, custom models and both override lists stay native-canonical',
    );
    expect(
      fixture.port.saves,
      isEmpty,
      reason: 'A narrow intent must never submit a stale full account',
    );
    expect(fixture.port.feeds, hasLength(2));
    final retiredFeed = fixture.port.feeds.first;
    expect(
      retiredFeed.closeCalls + retiredFeed.retryCloseCalls,
      1,
      reason: 'CAS source recovery must join the original native feed before replacement',
    );
  });

  test('clearing explicit unknown billing, removal and no-change receipts stay narrow and rejection leaves canonical intact', () async {
    final initial = _account().copyWith(
      billingKind: BillingKind.unknown,
      billingKindOverride: BillingKind.unknown,
    );
    final fixture = await _fixture(account: initial);
    final clear = fixture.repository.setAccountBillingKind('account', null);
    final clearing = await fixture.port.billingChanged(0);
    expect(
      clearing.request,
      SetAccountBillingKindRequest(
        operationId: clear.id,
        expectedRevision: 1,
        accountId: 'account',
        billingKind: null,
      ),
    );
    final inferred = initial.copyWith(
      billingKind: BillingKind.subscription,
      billingKindOverride: null,
    );
    await _commit(fixture, clearing, clear, 2, canonical: inferred);
    expect(
      await fixture.repository.loadAccount('account'),
      inferred,
      reason:
          'Null clears the override; it is not an explicit Unknown override',
    );

    final remove = fixture.repository.removeAccountModel('account', 'manual');
    final removing = await fixture.port.removed(0);
    expect(
      removing.request,
      RemoveAccountModelRequest(
        operationId: remove.id,
        expectedRevision: 2,
        accountId: 'account',
        modelId: 'manual',
      ),
    );
    final removed = inferred.copyWith(customModels: const []);
    await _commit(fixture, removing, remove, 3, canonical: removed);
    expect(await fixture.repository.loadAccount('account'), removed);

    final unchanged = fixture.repository.setAccountModelEnabled(
      'account',
      'online',
      true,
    );
    final noChange = await fixture.port.enabledChanged(0);
    expect(noChange.request.expectedRevision, 3);
    final receipt = await _commit(
      fixture,
      noChange,
      unchanged,
      3,
      disposition: CommitDisposition.noChange,
    );
    expect(receipt.disposition, CommitDisposition.noChange);
    expect(unchanged.state.value.isPending, isFalse);

    final failing = fixture.repository.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final refused = await fixture.port.enabledChanged(1);
    await _reject(refused, failing);
    expect(failing.state.value.error, _refusal);
    expect(await fixture.repository.loadAccount('account'), removed);
    expect(
      fixture.repository.state.value.projection.header?.configurationRevision,
      3,
    );
    expect(fixture.port.saves, isEmpty);

    fixture.port.holdCommandBegins = true;
    final refusedAdmission = fixture.repository.setAccountBillingKind(
      'account',
      BillingKind.metered,
    );
    final admission = await fixture.port.billingChanged(1);
    const conflict = StudioFailure(
      code: StudioFailureCode.conflict,
      message:
          'Native call admission rejected an incompatible existing invocation',
      retryable: false,
      correlationId: 'narrow-admission',
    );
    admission.beginReply.completeError(
      const CommandDispatchFailure.rejected(failure: conflict),
    );
    final rejected = await refusedAdmission.result;
    expect(rejected, isA<RejectedCommandResult<Unit>>());
    expect((rejected as RejectedCommandResult<Unit>).error, conflict);
    expect(admission.native.resultCalls, 0);
    expect(admission.native.requestCloseCalls, 0);
    expect(
      admission.native.closes,
      isEmpty,
      reason: 'A rejected admission created no native call to close',
    );
    expect(
      fixture.port.lookups,
      isEmpty,
      reason: 'An admission conflict is not permission to find/join the conflicting request',
    );
    expect(await fixture.repository.loadAccount('account'), removed);
  });

  test('a foreign operation receipt is unusable evidence and cannot synchronize or poison canonical configuration', () async {
    final fixture = await _fixture(protectedOutcome: true);
    final ticket = fixture.repository.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final call = await fixture.port.enabledChanged(0);
    await call.native.resultRead(0);
    call.native
        .resultAt(0)
        .reply
        .complete(_reply(const OperationId('foreign'), 99));
    await Future.any<void>([
      ticket.result.then<void>((_) {}),
      fixture.nativeModels.feed.listened.future,
    ]);
    expect(
      fixture.nativeModels.feed.listened.isCompleted,
      isFalse,
      reason: 'A foreign receipt must be refused before any Models target synchronization, not left waiting for revision 99',
    );
    final result = await ticket.result;
    expect(result, isA<AcknowledgedSyncFailedCommandResult<Unit>>());
    expect(
      (result as AcknowledgedSyncFailedCommandResult<Unit>).error.code,
      StudioFailureCode.protocol,
    );
    expect(ticket.state.value.receipt, isNull);
    expect(ticket.state.value.observed, isFalse);
    expect(
      fixture.repository.state.value.projection.header?.configurationRevision,
      1,
    );
    expect(await fixture.repository.loadAccount('account'), _account());
    expect(
      fixture.nativeModels.feed.listened.isCompleted,
      isFalse,
      reason: 'Reject foreign receipt identity before attempting to synchronize its targets',
    );
    expect(fixture.port.readRevisions, [1]);
    final closed = await fixture.repository.close();
    fixture.protectedReport = closed;
    expect(
      closed.unresolved.any(
        (item) =>
            item.owner == 'configuration:operation:${ticket.id.value}' &&
            item.issues.single.diagnostic.code ==
                OperationFailurePhase.syncFailed.name,
      ),
      isTrue,
    );
    expect(
      closed.unresolved.any(
        (item) =>
            item.owner.startsWith('configuration:call:${ticket.id.value}:'),
      ),
      isTrue,
    );
    expect(call.native.requestCloseCalls, 0);
    expect(
      call.native.closes,
      isEmpty,
      reason:
          'Foreign receipt identity never authorizes native material release',
    );
    expect(fixture.port.enabledChanges, hasLength(1));
    expect(fixture.port.feeds, hasLength(1));
  });

  test('Unknown is never redispatched or converted to rejection and cleanup retains its original evidence responsibility', () async {
    final fixture = await _fixture(protectedOutcome: true);
    final unknown = fixture.repository.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final sent = await fixture.port.enabledChanged(0);
    const failure = StudioFailure(
      code: StudioFailureCode.storage,
      message: 'The reply was lost after dispatch',
      retryable: true,
      correlationId: 'narrow-unknown',
    );
    await sent.native.resultRead(0);
    sent.native
        .resultAt(0)
        .reply
        .completeError(
          const CommandDispatchFailure.unknownOutcome(failure: failure),
        );
    await Future.any<void>([
      unknown.result.then<void>((_) {}),
      fixture.port.enabledChanged(1).then<void>((_) {}),
    ]);
    expect(
      fixture.port.enabledChanges,
      hasLength(1),
      reason: 'Unknown must settle without redispatching the sent intent',
    );
    final result = await unknown.result;
    expect(result, isA<UnknownOutcomeCommandResult<Unit>>());
    expect((result as UnknownOutcomeCommandResult<Unit>).error, same(failure));
    expect(
      unknown.state.value.failurePhase,
      OperationFailurePhase.unknownOutcome,
    );
    expect(unknown.state.value.isPending, isTrue);

    final next = fixture.repository.setAccountBillingKind('account', null);
    await Future.any<void>([
      fixture.port.billingChanged(0).then<void>((_) {}),
      fixture.port.enabledChanged(1).then<void>((_) {}),
    ]);
    expect(fixture.port.enabledChanges, hasLength(1));
    final nextCall = await fixture.port.billingChanged(0);
    expect(nextCall.request.expectedRevision, 1);
    expect(
      fixture.port.enabledChanges,
      hasLength(1),
      reason: 'The next real lane dispatch is a barrier; Unknown must not insert an automatic retry before it',
    );
    await _reject(nextCall, next);
    expect(await fixture.repository.loadAccount('account'), _account());
    final closing = fixture.repository.close();
    await sent.native.resultRead(1);
    sent.native
        .resultAt(1)
        .reply
        .completeError(
          const CommandDispatchFailure.unknownOutcome(failure: failure),
        );
    final closed = await closing;
    expect(
      closed.unresolved.any(
        (item) =>
            item.owner == 'configuration:operation:${unknown.id.value}' &&
            item.issues.single.recovery == CleanupRecovery.retryClose,
      ),
      isTrue,
    );
    expect(
      closed.unresolved.any(
        (item) =>
            item.owner.startsWith('configuration:call:${unknown.id.value}:'),
      ),
      isTrue,
    );
    expect(fixture.owner.budget.used(ResourceKind.pendingOperation), 1);
    expect(
      fixture.port.feeds.single.closeCalls +
          fixture.port.feeds.single.retryCloseCalls,
      0,
      reason: 'Original unobserved evidence still needs its read dependencies',
    );
    final retrying = fixture.repository.retryCleanup();
    await sent.native.resultRead(2);
    sent.native
        .resultAt(2)
        .reply
        .completeError(
          const CommandDispatchFailure.unknownOutcome(failure: failure),
        );
    final retried = await retrying;
    fixture.protectedReport = retried;
    expect(
      retried.unresolved.any(
        (item) =>
            item.owner.startsWith('configuration:call:${unknown.id.value}:'),
      ),
      isTrue,
    );
    expect(
      sent.native.resultCalls,
      3,
      reason: 'Cleanup joins the original result anew; it does not permanently cache a failed Future',
    );
    expect(sent.native.closes, isEmpty);
    expect(
      fixture.port.lookups,
      isEmpty,
      reason: 'A known original handle needs no new mutation or lookup',
    );
    expect(fixture.port.enabledChanges, hasLength(1));
    expect(fixture.port.billingChanges, hasLength(1));
    expect(
      fixture.port.feeds,
      hasLength(1),
      reason:
          'Unknown is not a CAS rejection or a reason to refresh and resend',
    );
  });

  test('an Unresolved rejected CAS call stops retry until cleanup of that original call, without resending later', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final call = await fixture.port.enabledChanged(0);
    await call.native.resultRead(0);
    call.native
        .resultAt(0)
        .reply
        .completeError(
          const CommandDispatchFailure.rejected(failure: _staleCall),
        );
    final closing = await call.native.closed(0);
    expect(fixture.port.enabledChanges, hasLength(1));
    closing.reply.complete(
      FeedCloseReport(
        feedId: call.native.callId,
        outcome: FeedCloseOutcome.unresolved(issues: [_joinIssue]),
      ),
    );
    final result = await ticket.result;
    expect(result, isA<RejectedCommandResult<Unit>>());
    expect((result as RejectedCommandResult<Unit>).error, _staleCall);
    expect(fixture.port.enabledChanges, hasLength(1));
    expect(
      fixture.port.feeds,
      hasLength(1),
      reason: 'Unresolved old call cleanup must stop the CAS source refresh as well as begin',
    );
    expect(await fixture.repository.loadAccount('account'), _account());

    final unresolved = await fixture.repository.close();
    expect(
      unresolved.unresolved.any(
        (item) =>
            item.owner.startsWith('configuration:call:${ticket.id.value}:') &&
            item.issues.contains(_joinIssue),
      ),
      isTrue,
    );
    final retrying = fixture.repository.retryCleanup();
    final retry = await call.native.closed(1);
    expect(retry.retry, isTrue);
    expect(call.native.closeCalls, 1);
    retry.reply.complete(
      FeedCloseReport(
        feedId: call.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await retrying).complete, isTrue);
    expect(
      fixture.port.enabledChanges,
      hasLength(1),
      reason: 'Cleanup retries the call, not the rejected business intention',
    );
    expect(fixture.port.lookups, isEmpty);
    expect(await ticket.result, result);
  });

  for (final reuseCallId in [true, false]) {
    final fault = reuseCallId ? 'reused old callId' : 'foreign operationId';
    test(
      '$fault on a CAS retry cannot read or close the replacement handle',
      () async {
        final fixture = await _fixture(protectedOutcome: true);
        fixture.port.holdCommandBegins = true;
        final ticket = fixture.repository.setAccountModelEnabled(
          'account',
          'online',
          false,
        );
        final first = await fixture.port.enabledChanged(0);
        first.accept();
        await first.native.resultRead(0);
        first.native
            .resultAt(0)
            .reply
            .completeError(
              const CommandDispatchFailure.rejected(failure: _staleCall),
            );
        final closing = await first.native.closed(0);
        closing.reply.complete(
          FeedCloseReport(
            feedId: first.native.callId,
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
        fixture.port.snapshots[2] = _account();
        final replacement = await fixture.port.opened(1);
        await replacement.listened.future;
        fixture.port.baseline(replacement, 2);
        final next = await fixture.port.enabledChanged(1);
        expect(next.request.operationId, ticket.id);
        expect(next.request.expectedRevision, 2);
        final foreign = ScriptedConfigurationCommandCall(
          callId: reuseCallId ? first.native.callId : next.native.callId,
          operationId: reuseCallId
              ? ticket.id
              : const OperationId('foreign-operation'),
        );
        next.beginReply.complete(foreign);
        await Future.any<void>([
          ticket.result.then<void>((_) {}),
          foreign.resultRead(0).then<void>((_) {}),
        ]);
        expect(
          foreign.resultCalls,
          0,
          reason: 'Invocation identity must be validated before querying a foreign result',
        );
        final result = await ticket.result;
        expect(result, isA<UnknownOutcomeCommandResult<Unit>>());
        expect(
          (result as UnknownOutcomeCommandResult<Unit>).error.code,
          StudioFailureCode.protocol,
        );
        expect(foreign.resultCalls, 0);
        expect(foreign.requestCloseCalls, 0);
        expect(first.native.closeCalls, 1);
        final unresolved = await fixture.repository.close();
        fixture.protectedReport = unresolved;
        expect(
          unresolved.unresolved.any(
            (item) =>
                item.owner.startsWith('configuration:call:${ticket.id.value}:'),
          ),
          isTrue,
        );
        expect(
          foreign.closes,
          isEmpty,
          reason:
              'A late/foreign invocation identity is not the new call owner',
        );
        expect(first.native.closeCalls + first.native.retryCloseCalls, 1);
        expect(fixture.port.enabledChanges, hasLength(2));
        expect(fixture.port.lookups, isEmpty);
      },
    );
  }

  for (final lookupRejected in [false, true]) {
    test(
      'lost begin with ${lookupRejected ? 'rejected lookup' : 'missing lookup'} stays Unknown and only joins the original call',
      () async {
        final fixture = await _fixture();
        fixture.port.holdCommandBegins = true;
        final ticket = fixture.repository.setAccountModelEnabled(
          'account',
          'online',
          false,
        );
        final call = await fixture.port.enabledChanged(0);
        const lost = StudioFailure(
          code: StudioFailureCode.staleRevision,
          message: 'Ordinary begin transport error, not typed CAS rejection',
          retryable: true,
          correlationId: 'owned-call-lost-begin',
        );
        call.beginReply.completeError(lost);
        final lookup = await fixture.port.lookedUp(0);
        expect(lookup.operationId, ticket.id);
        if (lookupRejected) {
          lookup.reply.completeError(
            const CommandDispatchFailure.rejected(failure: _refusal),
          );
        } else {
          lookup.reply.complete(null);
        }
        final result = await ticket.result;
        expect(result, isA<UnknownOutcomeCommandResult<Unit>>());
        expect(
          (result as UnknownOutcomeCommandResult<Unit>).error,
          lost,
          reason: 'A failed lookup is not rejection of the original begin, and an error code is not dispatch-phase evidence',
        );
        expect(call.native.resultCalls, 0);
        expect(fixture.port.enabledChanges, hasLength(1));
        expect(fixture.port.feeds, hasLength(1));

        final closing = fixture.repository.close();
        final joining = await fixture.port.lookedUp(1);
        expect(joining.operationId, ticket.id);
        joining.reply.complete(call.native);
        await call.native.resultRead(0);
        call.native
            .resultAt(0)
            .reply
            .completeError(
              const CommandDispatchFailure.unknownOutcome(failure: _refusal),
            );
        final unresolved = await closing;
        expect(unresolved.complete, isFalse);
        expect(call.native.closes, isEmpty);
        expect(fixture.port.enabledChanges, hasLength(1));

        final retrying = fixture.repository.retryCleanup();
        await call.native.resultRead(1);
        final reply = _reply(ticket.id, 2);
        call.native.resultAt(1).reply.complete(reply);
        await fixture.port.publishAccount(
          2,
          _account().copyWith(disabledModels: const ['withdrawn', 'online']),
        );
        await fixture.nativeModels.feed.listened.future;
        expect(
          call.native.requestCloseCalls,
          0,
          reason:
              'Recovered native result still needs its original Models target',
        );
        fixture.nativeModels.baseline();
        await fixture.nativeModels.feed.acknowledged(1);
        fixture.modelsPublished = true;
        final nativeClose = await call.native.closed(0);
        expect(ticket.state.value.receipt, reply.receipt);
        expect(ticket.state.value.observed, isTrue);
        nativeClose.reply.complete(
          FeedCloseReport(
            feedId: call.native.callId,
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
        expect((await retrying).complete, isTrue);
        expect(
          call.native.resultCalls,
          2,
          reason: 'The failed result Future was not cached forever',
        );
        expect(call.native.closeCalls + call.native.retryCloseCalls, 1);
        expect(fixture.port.enabledChanges, hasLength(1));
        expect(fixture.port.lookups.map((item) => item.operationId), [
          ticket.id,
          ticket.id,
        ]);
        expect(
          await ticket.result,
          result,
          reason: 'Later commit evidence updates state without rewriting the original Unknown result Future',
        );
      },
    );
  }

  test('synchronous Models refusal still joins the admitted Configuration target and retains unobserved native materials', () async {
    final fixture = await _fixture(protectedOutcome: true);
    fixture.owner.models.seal(); // The real receiver now throws synchronously; no fake synchronization fallback.
    final ticket = fixture.repository.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final call = await fixture.port.enabledChanged(0);
    await call.native.resultRead(0);
    final reply = _reply(ticket.id, 2);
    call.native.resultAt(0).reply.complete(reply);
    final waiting = await fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(
      waiting.unresolved.any(
        (item) => item.owner == 'configuration:write-lane',
      ),
      isTrue,
      reason: 'A synchronous peer throw must not abandon the already-admitted Configuration target Future',
    );
    expect(ticket.state.value.failurePhase, isNull);
    expect(call.native.requestCloseCalls, 0);
    await fixture.port.publishAccount(2, _account());
    final result = await ticket.result;
    expect(result, isA<SyncFailedCommandResult<Unit>>());
    final failed = result as SyncFailedCommandResult<Unit>;
    expect(failed.receipt, reply.receipt);
    expect(failed.error.code, StudioFailureCode.cancelled);
    expect(
      fixture.repository.state.value.projection.header!.configurationRevision,
      2,
    );
    expect(
      (
        ticket.state.value.receipt,
        ticket.state.value.observed,
        ticket.state.value.isPending,
      ),
      (reply.receipt, false, true),
      reason: 'The real Settings receipt is covered, but the original Models receiver did not synchronize',
    );
    expect(
      (
        ticket.state.value.failurePhase,
        ticket.state.value.error,
        ticket.state.value.effective,
        ticket.state.value.durable,
      ),
      (OperationFailurePhase.syncFailed, failed.error, false, true),
    );
    expect(
      fixture.owner.operations.observations.lookup(ticket.id)!.state.value,
      ticket.state.value,
    );
    expect(
      fixture.owner.budget.usage.any(
        (usage) =>
            usage.kind == ResourceKind.pendingOperation &&
            usage.owner == ticket.id.value &&
            usage.phase == ResourcePhase.unresolved,
      ),
      isTrue,
    );
    expect(fixture.nativeModels.feed.listened.isCompleted, isFalse);
    final unresolved = await fixture.repository.close();
    fixture.protectedReport = unresolved;
    expect(
      unresolved.unresolved.any(
        (item) =>
            item.owner.startsWith('configuration:call:${ticket.id.value}:') &&
            item.issues.any(
              (issue) =>
                  issue.diagnostic.code ==
                  'originalConfigurationTargetsUnobserved',
            ),
      ),
      isTrue,
    );
    expect(
      (ticket.state.value.receipt, ticket.state.value.observed),
      (reply.receipt, false),
    );
    expect(
      await ticket.result,
      same(result),
      reason:
          'Cleanup cannot replace the original SyncFailed result or diagnostic',
    );
    expect(fixture.owner.budget.used(ResourceKind.pendingOperation), 1);
    expect(call.native.requestCloseCalls, 0);
    expect(
      call.native.closes,
      isEmpty,
      reason: 'Receipt evidence is not proof that both original receivers synchronized',
    );
    expect(fixture.port.enabledChanges, hasLength(1));
    expect(fixture.port.lookups, isEmpty);
  });

  test('Configuration close retains a late begin and joins both open receivers plus the original native close', () async {
    final fixture = await _fixture();
    fixture.port.holdCommandBegins = true;
    final ticket = fixture.repository.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final call = await fixture.port.enabledChanged(
      0,
    ); // begin is actually waiting at the port.
    final waiting = await fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(waiting.complete, isFalse);
    expect(
      waiting.unresolved.any(
        (item) =>
            item.owner.startsWith('configuration:call:${ticket.id.value}:'),
      ),
      isTrue,
    );
    expect(call.native.resultCalls, 0);
    call.accept();
    final receipt = await _observe(
      fixture,
      call,
      ticket,
      2,
      canonical: _account().copyWith(
        disabledModels: const ['withdrawn', 'online'],
      ),
    );
    final nativeClose = await call.native.closed(0);
    final stillClosing = await fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(stillClosing.complete, isFalse);
    expect(ticket.state.value.receipt, receipt);
    expect(ticket.state.value.observed, isTrue);
    nativeClose.reply.complete(
      FeedCloseReport(
        feedId: call.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(fixture.port.enabledChanges, hasLength(1));
    expect(fixture.port.lookups, isEmpty);
    expect(call.native.resultCalls, 1);
    expect(call.native.closeCalls + call.native.retryCloseCalls, 1);
    expect(
      ticket.state.value.receipt,
      receipt,
      reason: 'Standalone Configuration close joins admitted work; it does not resend or revoke observed success',
    );
  });

  test('observed commit survives wrong close identity and cleanup failure while retries stay on the original call', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final call = await fixture.port.enabledChanged(0);
    final receipt = await _observe(
      fixture,
      call,
      ticket,
      2,
      canonical: _account().copyWith(
        disabledModels: const ['withdrawn', 'online'],
      ),
    );
    final committed = await ticket.result;
    final closing = await call.native.closed(0);
    closing.reply.complete(
      FeedCloseReport(
        feedId: 'foreign-call',
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    final unresolved = await fixture.repository.close();
    expect(
      unresolved.unresolved.any(
        (item) =>
            item.owner.startsWith('configuration:call:${ticket.id.value}:') &&
            item.issues.any(
              (issue) =>
                  issue.diagnostic.code == StudioFailureCode.protocol.name,
            ),
      ),
      isTrue,
    );
    expect(ticket.state.value.receipt, receipt);
    expect(ticket.state.value.observed, isTrue);
    expect(await ticket.result, committed);

    final failedRetry = fixture.repository.retryCleanup();
    final retry = await call.native.closed(1);
    expect(retry.retry, isTrue);
    retry.reply.completeError(_refusal);
    await Future.any<void>([
      failedRetry.then<void>((_) {}),
      call.native.closed(2).then<void>((_) {}),
    ]);
    expect(
      call.native.retryCloseCalls,
      1,
      reason: 'One failed explicit cleanup retry must report Unresolved, not silently start a second native close in the same request',
    );
    expect((await failedRetry).complete, isFalse);
    expect(
      await ticket.result,
      committed,
      reason: 'Cleanup failure cannot convert the observed business commit into rejection',
    );

    final successfulRetry = fixture.repository.retryCleanup();
    final last = await call.native.closed(2);
    expect(last.retry, isTrue);
    last.reply.complete(
      FeedCloseReport(
        feedId: call.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await successfulRetry).complete, isTrue);
    expect(call.native.closeCalls, 1);
    expect(call.native.retryCloseCalls, 2);
    expect(
      call.native.resultCalls,
      1,
      reason: 'Already-observed original reply is retained; cleanup failure does not create a new result/attempt',
    );
    expect(fixture.port.enabledChanges, hasLength(1));
    expect(fixture.port.lookups, isEmpty);
    expect(await ticket.result, committed);
    expect(ticket.state.value.receipt, receipt);
  });

  test('an explicit no-charge toggle is not optimistically applied and a failed write leaves canonical billing intact', () async {
    final fixture = await _fixture();
    Future<AccountConfiguration> current() =>
        fixture.repository.loadAccount('account');

    final toggle = fixture.repository.setAccountBillingKind(
      'account',
      BillingKind.noCharge,
    );
    final charged = await fixture.port.billingChanged(0);
    expect(
      charged.request,
      SetAccountBillingKindRequest(
        operationId: toggle.id,
        expectedRevision: 1,
        accountId: 'account',
        billingKind: BillingKind.noCharge,
      ),
    );
    // The switch is a projection of canonical billing facts: dispatch alone
    // must not report a no-charge account.
    expect((await current()).billingKind, BillingKind.subscription);
    expect((await current()).billingKindOverride, isNull);
    await _commit(
      fixture,
      charged,
      toggle,
      2,
      canonical: _account().copyWith(
        billingKind: BillingKind.noCharge,
        billingKindOverride: BillingKind.noCharge,
      ),
    );
    expect((await current()).billingKind, BillingKind.noCharge);
    expect((await current()).billingKindOverride, BillingKind.noCharge);

    // Turning no charge off clears the override; it never replays the
    // effective category as a new explicit intent.
    final clear = fixture.repository.setAccountBillingKind('account', null);
    final clearing = await fixture.port.billingChanged(1);
    expect(clearing.request.billingKind, isNull);
    expect(
      clearing.request.billingKind,
      isNot(BillingKind.noCharge),
      reason: 'Turning no charge off must clear, not replay the effective kind',
    );
    await _commit(fixture, clearing, clear, 3, canonical: _account());
    expect((await current()).billingKind, BillingKind.subscription);
    expect((await current()).billingKindOverride, isNull);

    // A refused write cannot fabricate the switch state.
    final failing = fixture.repository.setAccountBillingKind(
      'account',
      BillingKind.noCharge,
    );
    final refused = await fixture.port.billingChanged(2);
    await _reject(refused, failing);
    expect(failing.state.value.error, _refusal);
    expect((await current()).billingKind, BillingKind.subscription);
    expect((await current()).billingKindOverride, isNull);
    expect(
      fixture.port.saves,
      isEmpty,
      reason: 'The billing switch is never a full account save',
    );
  });
}
