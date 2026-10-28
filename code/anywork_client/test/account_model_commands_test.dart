import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';

const _identity = NativeAccountIdentity('account');
const _model = AccountModelView(
  modelId: 'online',
  displayName: 'Online',
  reasoningEfforts: ['high'],
  typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
  origin: ModelOrigin.online,
);
const _manual = AccountModelView(
  modelId: 'manual',
  displayName: 'Manual',
  reasoningEfforts: [],
  typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
  origin: ModelOrigin.manual,
);
const _account = AccountSettingsView(
  id: 'account',
  name: 'Account',
  baseUrl: 'https://original.invalid',
  defaultModelId: 'online',
  models: [_model, _manual],
  status: 'ready',
  usageLabel: '',
  billingKind: BillingKind.subscription,
);
SettingsStateSnapshot _snapshot(int revision, AccountSettingsView account) =>
    SettingsStateSnapshot(
      revision: revision,
      modelCatalogRevision: revision,
      accounts: [account],
      modeModelRoutes: const [
        ModeModelRouteView(
          modeId: ThreadModeId.simple,
          accountId: 'account',
          modelId: 'online',
          effort: 'high',
        ),
      ],
    );

final class _Call {
  _Call(
    this.kind,
    this.revision,
    this.accountId,
    this.operationId, {
    this.modelId,
    this.enabled,
    this.billingKind,
  });
  final String kind;
  final int revision;
  final String accountId;
  final String? modelId;
  final bool? enabled;
  final BillingKind? billingKind;
  final OperationId operationId;
  final reply = Completer<SettingsCommandReply>();
  void complete(
    SettingsStateSnapshot snapshot, {
    OperationId? foreignId,
    CommitDisposition disposition = CommitDisposition.applied,
  }) => reply.complete(
    accountReply(
      snapshot: snapshot,
      receipt: StudioCommandReceipt(
        operationId: foreignId ?? operationId,
        disposition: disposition,
        targets: [testStamp('settings', snapshot.revision)],
        effect: EffectPoint.futureSession,
        effective: false,
        durable: true,
      ),
    ),
  );
}

/// Only scripts owner replies. Real domain mutations own CAS, identity and merge.
final class _Transport extends AccountsTestTransport {
  final calls = StreamController<_Call>.broadcast();
  SettingsStateSnapshot? refreshed;
  int refreshes = 0;
  @override
  Future<SettingsStateSnapshot> readSettingsState() async {
    refreshes++;
    return refreshed!;
  }

  @override
  Future<SettingsCommandReply> setAccountModelEnabled(
    int revision,
    String accountId,
    String modelId,
    bool enabled, {
    required OperationId operationId,
  }) {
    final call = _Call(
      'enabled',
      revision,
      accountId,
      operationId,
      modelId: modelId,
      enabled: enabled,
    );
    calls.add(call);
    return call.reply.future;
  }

  @override
  Future<SettingsCommandReply> setAccountBillingKind(
    int revision,
    String accountId,
    BillingKind? billingKind, {
    required OperationId operationId,
  }) {
    final call = _Call(
      'billing',
      revision,
      accountId,
      operationId,
      billingKind: billingKind,
    );
    calls.add(call);
    return call.reply.future;
  }

  @override
  Future<SettingsCommandReply> removeAccountModel(
    int revision,
    String accountId,
    String modelId, {
    required OperationId operationId,
  }) {
    final call = _Call(
      'remove',
      revision,
      accountId,
      operationId,
      modelId: modelId,
    );
    calls.add(call);
    return call.reply.future;
  }
}

AccountsTestRuntime _client(_Transport transport) {
  final runtime = AccountsTestRuntime(transport, clientId: 'narrow');
  runtime.seed(_snapshot(1, _account));
  addTearDown(() async {
    await runtime.close();
    await transport.calls.close();
  });
  return runtime;
}

AccountModelCatalog _catalog(AccountsTestRuntime runtime) =>
    runtime.domains.models.state.value.accounts[_identity]!.value!;
AccountModelConfiguration _configuration(AccountsTestRuntime runtime) =>
    runtime.domains.models.state.value.configurations[_identity]!.value!;
AccountSummary _summary(AccountsTestRuntime runtime) =>
    runtime.domains.accounts.state.value.account(_identity)!;
const _enabledKey = 'model:enabled:7:account:online';

void main() {
  test('rapid enabled intents survive CAS refresh and preserve unrelated canonical fields', () async {
    final transport = _Transport();
    final client = _client(transport);
    final firstCall = transport.calls.stream.first;
    final first = client.domains.models.setEnabled(
      modelIdentity('account', 'online'),
      false,
    );
    final firstId = client.board.latest(_enabledKey)!.id;
    final second = client.domains.models.setEnabled(
      modelIdentity('account', 'online'),
      true,
    );
    final secondId = client.board.latest(_enabledKey)!.id;
    final call = await firstCall;
    expect(call.operationId, firstId);
    expect(call.revision, 1);
    final concurrent = _account.copyWith(
      baseUrl: 'https://changed.invalid',
      hasBearerToken: true,
      usageQueryRevision: 4,
      modelConnectionModes: const {'online': 'web_socket'},
      autoCompactLimits: const {
        'online': AccountModelAutoCompactView(
          modelId: 'online',
          overrideLimit: 777,
        ),
      },
    );
    transport.refreshed = _snapshot(2, concurrent);
    final retryCall = transport.calls.stream.first;
    call.reply.completeError(
      const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'Concurrent settings',
        retryable: true,
        correlationId: 'remote-conflict',
      ),
    );
    final retry = await retryCall;
    expect(retry.operationId, firstId);
    expect(retry.revision, 2);
    expect(retry.enabled, isFalse);
    final disabled = concurrent.copyWith(
      modelEnabledOverrides: const {'online': false},
      models: [_model.copyWith(enabled: false), _manual],
    );
    final secondCall = transport.calls.stream.first;
    retry.complete(_snapshot(3, disabled));
    await first;
    expect(
      client.board.latest(_enabledKey)!.id,
      secondId,
      reason: 'An older ACK cannot clear the newer intent',
    );
    expect(client.board.latest(_enabledKey)!.state.value.isPending, isTrue);
    expect(
      client.client.settings.state.canonical!.modeModelRoutes.single.modelId,
      'online',
    );
    expect(
      modelSelectionAccounts(
        client.domains.accounts.state.value,
        client.domains.models.state.value,
      ).single.modelsFor(type: ModelType.text).map((m) => m.modelId),
      ['manual'],
    );
    final next = await secondCall;
    expect(next.operationId, secondId);
    expect(next.operationId, isNot(firstId));
    expect(next.revision, 3);
    expect(next.enabled, isTrue);
    next.complete(_snapshot(4, concurrent));
    await second;
    expect(
      transport.refreshes,
      2,
      reason: 'CAS retries refresh the target detail and its independent model source, not an aggregate bootstrap',
    );
    final detail =
        client.domains.accounts.details(_identity).value.value!
            as NativeAccountDetails;
    expect(detail.baseUrl, concurrent.baseUrl);
    expect(detail.hasBearerToken, isTrue);
    expect(detail.usageQueryRevision, 4);
    expect(_configuration(client).connections, {
      'online': AccountConnectionMode.webSocket,
    });
    expect(_configuration(client).autoCompactLimits, {'online': 777});
    expect(_summary(client).billingKind, BillingKind.subscription);
    expect(_catalog(client).models.first.origin, ModelOrigin.online);
    expect(client.board.latest(_enabledKey)!.state.value.isPending, isFalse);
    expect(
      client.client.settings.state.canonical!.modeModelRoutes.single.modelId,
      'online',
    );
  });

  test('billing and removal preserve identity, explicit clear, failures and foreign-receipt rejection', () async {
    final transport = _Transport();
    final client = _client(transport);
    var entered = transport.calls.stream.first;
    var pending = client.domains.accounts.setBillingKind(
      _identity,
      BillingKind.noCharge,
    );
    var call = await entered;
    expect(call.billingKind, BillingKind.noCharge);
    expect(
      _summary(client).billingKind,
      BillingKind.subscription,
      reason: 'No optimistic billing success',
    );
    expect(
      call.operationId,
      client.board.latest('account:billing:account')!.id,
    );
    call.complete(
      _snapshot(
        2,
        _account.copyWith(
          billingKind: BillingKind.noCharge,
          billingKindOverride: BillingKind.noCharge,
        ),
      ),
    );
    await pending;
    expect(_summary(client).billingKind, BillingKind.noCharge);
    entered = transport.calls.stream.first;
    pending = client.domains.accounts.setBillingKind(_identity, null);
    call = await entered;
    expect(
      call.billingKind,
      isNull,
      reason: 'Clear must not replay the effective classification',
    );
    call.complete(_snapshot(3, _account));
    await pending;
    expect(_summary(client).billingKind, BillingKind.subscription);
    expect(_summary(client).billingKindOverride, isNull);
    entered = transport.calls.stream.first;
    pending = client.domains.accounts.setBillingKind(
      _identity,
      BillingKind.noCharge,
    );
    call = await entered;
    const billingError = StudioFailure(
      code: StudioFailureCode.storage,
      message: 'Billing write failed',
      retryable: false,
      correlationId: 'billing-write-failure',
    );
    call.reply.completeError(billingError);
    final billingFailure = await pending;
    expect(billingFailure.id, call.operationId);
    expect(billingFailure.failurePhase, OperationPhase.unknownOutcome);
    expect(billingFailure.error, same(billingError));
    expect(billingFailure.receipt, isNull);
    expect(_summary(client).billingKind, BillingKind.subscription);
    expect(_summary(client).billingKindOverride, isNull);
    entered = transport.calls.stream.first;
    pending = client.domains.models.removeManual(
      modelIdentity('account', 'manual'),
    );
    call = await entered;
    expect(call.kind, 'remove');
    expect(call.modelId, 'manual');
    expect(
      call.operationId,
      client.board.latest('model:remove:7:account:manual')!.id,
    );
    call.complete(_snapshot(4, _account.copyWith(models: const [_model])));
    await pending;
    expect(_catalog(client).models.map((m) => m.modelId), ['online']);
    entered = transport.calls.stream.first;
    pending = client.domains.models.setEnabled(
      modelIdentity('account', 'online'),
      true,
    );
    call = await entered;
    call.complete(
      _snapshot(4, _account.copyWith(models: const [_model])),
      disposition: CommitDisposition.noChange,
    );
    await pending;
    expect(client.board.latest(_enabledKey)!.state.value.isPending, isFalse);
    entered = transport.calls.stream.first;
    pending = client.domains.models.setEnabled(
      modelIdentity('account', 'online'),
      false,
    );
    call = await entered;
    const writeError = StudioFailure(
      code: StudioFailureCode.storage,
      message: 'Write failed before commit',
      retryable: true,
      correlationId: 'owner-write-failure',
    );
    call.reply.completeError(writeError);
    final writeFailure = await pending;
    expect(writeFailure.id, call.operationId);
    expect(writeFailure.failurePhase, OperationPhase.unknownOutcome);
    expect(writeFailure.error, same(writeError));
    expect(writeFailure.receipt, isNull);
    expect(_catalog(client).models.single.enabled, isTrue);
    expect(
      (client.board.latest(_enabledKey)!.state.value.error as StudioFailure)
          .message,
      'Write failed before commit',
    );
    entered = transport.calls.stream.first;
    pending = client.domains.models.setEnabled(
      modelIdentity('account', 'online'),
      false,
    );
    call = await entered;
    call.complete(
      _snapshot(
        99,
        _account.copyWith(modelEnabledOverrides: const {'online': false}),
      ),
      foreignId: const OperationId('foreign'),
    );
    final foreignReceiptFailure = await pending;
    expect(foreignReceiptFailure.id, call.operationId);
    expect(foreignReceiptFailure.failurePhase, OperationPhase.unknownOutcome);
    expect(foreignReceiptFailure.receipt, isNull);
    expect(
      (foreignReceiptFailure.error as StudioFailure).code,
      StudioFailureCode.protocol,
    );
    expect(
      client
          .domains
          .models
          .state
          .value
          .configurations[_identity]!
          .stamp!
          .revision,
      4,
      reason: 'Foreign receipts cannot poison canonical state',
    );
    final failed = client.board.latest(_enabledKey)!.state.value;
    expect(foreignReceiptFailure, same(failed));
    expect(
      failed.isPending,
      isTrue,
      reason: 'A foreign receipt cannot prove rejection or observation of this operation',
    );
    expect((failed.error as StudioFailure).code, StudioFailureCode.protocol);
    expect(_catalog(client).models.single.enabled, isTrue);
  });
}
