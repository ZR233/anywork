import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

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

class _Call {
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
    SettingsCommandReply(
      snapshot: snapshot,
      receipt: StudioCommandReceipt(
        operationId: foreignId ?? operationId,
        disposition: disposition,
        targets: [
          ResourceStamp(
            resourceKey: 'settings',
            ownerEpoch: 'owner',
            revision: snapshot.revision,
          ),
        ],
        effect: EffectPoint.futureSession,
        effective: false,
        durable: true,
      ),
    ),
  );
}

/// Supplies scripted owner replies only; the real Client owns retries/lane/merge.
class _Transport implements StudioTransport {
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

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}

AnyworkClient _client(_Transport transport) {
  final client = AnyworkClient(transport: transport, clientId: 'narrow');
  client.applyBootstrap(
    StudioBootstrap(
      ownerEpoch: 'owner',
      projectDirectory: ProjectDirectoryState(values: const [], revision: 1),
      threadDirectory: const ThreadDirectoryWindow(),
      agentDirectory: AgentDirectoryState(revision: 1),
      settingsState: _snapshot(1, _account),
      recoveryState: RecoveryStateSnapshot(revision: 1),
      mcpState: McpStateSnapshot(revision: 1),
      lspState: LspStateSnapshot(revision: 1),
      skillsByProject: const {},
      threadModeCatalog: const ThreadModeCatalogView(),
      accountUsageState: AccountUsageStateSnapshot(revision: 1),
      updaterState: DisabledUpdaterStateSnapshot(
        revision: 1,
        updatedAt: DateTime.utc(2026),
      ),
      persistenceState: const PersistenceStateSnapshot.ready(),
    ),
  );
  addTearDown(() async {
    await client.close();
    await transport.calls.close();
  });
  return client;
}

void main() {
  test('rapid enabled intents survive CAS refresh and keep unrelated canonical fields', () async {
    final transport = _Transport();
    final client = _client(transport);
    final commands = client.settingsCommands;
    final firstCall = transport.calls.stream.first;
    final first = commands.setAccountModelEnabled('account', 'online', false);
    final firstId = client.mutations
        .latest(
          'settings:${accountModelEnabledMutationKey('account', 'online')}',
        )!
        .id;
    final second = commands.setAccountModelEnabled('account', 'online', true);
    final secondId = client.mutations
        .latest(
          'settings:${accountModelEnabledMutationKey('account', 'online')}',
        )!
        .id;
    final call = await firstCall;
    expect(call.operationId, firstId);
    expect(call.revision, 1);
    final concurrent = _account.copyWith(
      baseUrl: 'https://changed.invalid',
      hasBearerToken: true,
      usageQueryRevision: 4,
      modelConnectionModes: const {'online': 'websocket'},
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
    final key = accountModelEnabledMutationKey('account', 'online');
    expect(
      client.settings.state.commands[key]?.target.enabled,
      isTrue,
      reason: 'The older ACK must not clear the newer intent',
    );
    final preservedRoute =
        client.settings.state.canonical!.modeModelRoutes.single;
    expect(preservedRoute.modelId, 'online');
    expect(
      client.settings.state.canonical!.accounts.single
          .modelsFor(type: ModelType.text)
          .map((m) => m.modelId),
      ['manual'],
    );
    final next = await secondCall;
    expect(next.operationId, secondId);
    expect(next.operationId, isNot(firstId));
    expect(next.revision, 3);
    expect(next.enabled, isTrue);
    next.complete(_snapshot(4, concurrent));
    await second;
    expect(transport.refreshes, 1);
    final canonical = client.settings.state.canonical!.accounts.single;
    expect(canonical.baseUrl, concurrent.baseUrl);
    expect(canonical.hasBearerToken, isTrue);
    expect(canonical.usageQueryRevision, 4);
    expect(canonical.modelConnectionModes, concurrent.modelConnectionModes);
    expect(canonical.autoCompactLimits['online']?.overrideLimit, 777);
    expect(canonical.billingKind, BillingKind.subscription);
    expect(canonical.models.first.origin, ModelOrigin.online);
    expect(client.settings.state.commands[key], isNull);
    expect(
      client.settings.state.canonical!.modeModelRoutes.single.modelId,
      'online',
    );
  });

  test('narrow billing and removal keep operation identity, null intent, and foreign receipts rejected', () async {
    final transport = _Transport();
    final client = _client(transport);
    var entered = transport.calls.stream.first;
    var pending = client.settingsCommands.setAccountBillingKind(
      'account',
      BillingKind.noCharge,
    );
    var call = await entered;
    expect(call.billingKind, BillingKind.noCharge);
    expect(
      client.settings.state.canonical!.accounts.single.billingKind,
      BillingKind.subscription,
      reason: 'No optimistic billing success',
    );
    expect(
      call.operationId,
      client.mutations.latest('settings:account-billing-kind:account')!.id,
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
    expect(
      client.settings.state.canonical!.accounts.single.billingKind,
      BillingKind.noCharge,
    );
    entered = transport.calls.stream.first;
    pending = client.settingsCommands.setAccountBillingKind('account', null);
    call = await entered;
    expect(
      call.billingKind,
      isNull,
      reason: 'Turning no charge off must clear, not replay the effective kind',
    );
    call.complete(_snapshot(3, _account));
    await pending;
    expect(
      client.settings.state.canonical!.accounts.single.billingKind,
      BillingKind.subscription,
    );
    expect(
      client.settings.state.canonical!.accounts.single.billingKindOverride,
      isNull,
    );
    entered = transport.calls.stream.first;
    pending = client.settingsCommands.setAccountBillingKind(
      'account',
      BillingKind.noCharge,
    );
    final billingFailure = expectLater(pending, throwsA(isA<StudioFailure>()));
    call = await entered;
    call.reply.completeError(
      const StudioFailure(
        code: StudioFailureCode.storage,
        message: 'Billing write failed',
        retryable: false,
        correlationId: 'billing-write-failure',
      ),
    );
    await billingFailure;
    expect(
      client.settings.state.canonical!.accounts.single.billingKind,
      BillingKind.subscription,
    );
    expect(
      client.settings.state.canonical!.accounts.single.billingKindOverride,
      isNull,
    );
    entered = transport.calls.stream.first;
    pending = client.settingsCommands.removeAccountModel('account', 'manual');
    call = await entered;
    expect(call.kind, 'remove');
    expect(call.modelId, 'manual');
    expect(
      call.operationId,
      client.mutations.latest('settings:account-model:7:account:manual')!.id,
    );
    call.complete(_snapshot(4, _account.copyWith(models: const [_model])));
    await pending;
    expect(
      client.settings.state.canonical!.accounts.single.models.map(
        (m) => m.modelId,
      ),
      ['online'],
    );
    entered = transport.calls.stream.first;
    pending = client.settingsCommands.setAccountModelEnabled(
      'account',
      'online',
      true,
    );
    call = await entered;
    call.complete(
      _snapshot(4, _account.copyWith(models: const [_model])),
      disposition: CommitDisposition.noChange,
    );
    await pending;
    expect(
      client.settings.state.commands[accountModelEnabledMutationKey(
        'account',
        'online',
      )],
      isNull,
    );
    entered = transport.calls.stream.first;
    pending = client.settingsCommands.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final writeFailure = expectLater(
      pending,
      throwsA(
        isA<StudioFailure>().having(
          (e) => e.code,
          'code',
          StudioFailureCode.storage,
        ),
      ),
    );
    call = await entered;
    call.reply.completeError(
      const StudioFailure(
        code: StudioFailureCode.storage,
        message: 'Write failed before commit',
        retryable: true,
        correlationId: 'owner-write-failure',
      ),
    );
    await writeFailure;
    expect(
      client.settings.state.canonical!.accounts.single.models.single.enabled,
      isTrue,
    );
    expect(
      client
          .settings
          .state
          .commands[accountModelEnabledMutationKey('account', 'online')]
          ?.error
          ?.message,
      'Write failed before commit',
    );
    entered = transport.calls.stream.first;
    pending = client.settingsCommands.setAccountModelEnabled(
      'account',
      'online',
      false,
    );
    final rejected = expectLater(
      pending,
      throwsA(
        isA<StudioFailure>().having(
          (e) => e.code,
          'code',
          StudioFailureCode.protocol,
        ),
      ),
    );
    call = await entered;
    call.complete(
      _snapshot(
        99,
        _account.copyWith(modelEnabledOverrides: const {'online': false}),
      ),
      foreignId: const OperationId('foreign'),
    );
    await rejected;
    expect(
      client.settings.state.settingsRevision,
      4,
      reason: 'Foreign receipts cannot poison canonical state',
    );
    final failed = client
        .settings
        .state
        .commands[accountModelEnabledMutationKey('account', 'online')];
    expect(failed?.isPending, isFalse);
    expect(failed?.error?.code, StudioFailureCode.protocol);
    expect(
      client.settings.state.canonical!.accounts.single.models.single.enabled,
      isTrue,
    );
  });
}
