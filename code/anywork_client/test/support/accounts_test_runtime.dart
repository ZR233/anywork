import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';

/// Scripted environment only. All production ordering, reduction, identity
/// checks, mutation ownership and shutdown execute in the real SDK domains.
abstract class AccountsTestTransport
    implements
        StudioTransport,
        AccountFeedPort,
        AccountConfigurationPort,
        AccountModelsPort,
        AccountUsagePort,
        AcpPort {
  String epoch = 'owner';
  final Map<AccountObservationTarget, Set<TestAccountObservation>>
  observations = {};
  final Map<AccountObservationTarget, AccountDomainFrame> baselines = {};
  final Map<AccountObservationTarget, Completer<TestAccountObservation>>
  _opening = {};
  final List<AccountObservationTarget> accountReads = [];
  Future<AccountDomainFrame> Function(AccountObservationTarget)? accountRead;

  @override
  Future<ChatGptLoginCommandReply> startChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) => Future.error(
    UnsupportedError('ChatGPT login was not scripted for this test'),
  );

  @override
  Future<ChatGptLoginCommandReply> cancelChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) => Future.error(
    UnsupportedError('ChatGPT login was not scripted for this test'),
  );

  @override
  Future<AccountDomainObservation> openAccountObservation(
    AccountObservationTarget target,
  ) async {
    late final TestAccountObservation observation;
    observation = TestAccountObservation(() {
      observations[target]?.remove(observation);
    });
    observations.putIfAbsent(target, () => {}).add(observation);
    final opening = _opening.remove(target);
    if (opening != null && !opening.isCompleted) opening.complete(observation);
    final baseline = baselines[target];
    if (baseline != null) observation.emit(baseline);
    return observation;
  }

  Future<TestAccountObservation> attachedAccount(
    AccountObservationTarget target,
  ) {
    final current = observations[target]?.firstOrNull;
    return current == null
        ? (_opening[target] ??= Completer<TestAccountObservation>()).future
        : Future.value(current);
  }

  @override
  Future<AccountDomainFrame> readAccountDomain(
    AccountObservationTarget target,
  ) async {
    accountReads.add(target);
    final read = accountRead;
    if (read != null) return read(target);
    final snapshot = await readSettingsState();
    final frames = accountFrames(snapshot, epoch: epoch);
    return frames.where((frame) => frame.target == target).firstOrNull ??
        switch (target) {
          AccountDetailTarget(:final identity) => AccountDetailFrame(
            testStamp('settings', snapshot.revision, epoch: epoch),
            identity,
            null,
          ),
          AccountModelsTarget(:final identity) => AccountModelsFrame(
            testStamp(
              'model-catalog',
              snapshot.modelCatalogRevision,
              epoch: epoch,
            ),
            identity,
            null,
          ),
          _ => throw StateError('No scripted account read: ${target.key}'),
        };
  }

  void emitAccount(AccountDomainFrame frame) {
    baselines[frame.target] = frame;
    for (final observation
        in observations[frame.target]?.toList() ?? <TestAccountObservation>[]) {
      observation.emit(frame);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}

final class TestAccountObservation implements AccountDomainObservation {
  TestAccountObservation(this.onClosed);
  final void Function() onClosed;
  AccountDomainFrame? _latest;
  Object? _error;
  Completer<AccountDomainFrame?>? _next;
  bool closed = false;
  final stopped = Completer<void>();
  int closeCalls = 0;
  void fail(Object error) {
    if (closed) throw StateError('The observation is closed');
    final pending = _next;
    if (pending == null) {
      _error = error;
    } else {
      _next = null;
      pending.completeError(error);
    }
  }

  void emit(AccountDomainFrame frame) {
    if (closed) return;
    final waiting = _next;
    if (waiting == null) {
      _latest = frame;
    } else {
      _next = null;
      waiting.complete(frame);
    }
  }

  @override
  Future<AccountDomainFrame?> next() {
    if (_next != null) return Future.error(StateError('Concurrent next'));
    if (closed) return Future.value(null);
    final error = _error;
    if (error != null) {
      _error = null;
      return Future.error(error);
    }
    final latest = _latest;
    if (latest != null) {
      _latest = null;
      return Future.value(latest);
    }
    return (_next = Completer<AccountDomainFrame?>()).future;
  }

  @override
  void requestClose() {
    closed = true;
    _latest = null;
    _next?.complete(null);
    _next = null;
  }

  @override
  Future<void> close() async {
    requestClose();
    closeCalls++;
    onClosed();
    if (!stopped.isCompleted) stopped.complete();
  }
}

final class AccountsTestRuntime {
  AccountsTestRuntime(this.transport, {String clientId = 'test'}) {
    board = MutationBoard(clientId: clientId, budget: budget);
    domains = AccountDomainResources(
      feed: transport,
      configuration: transport,
      modelPort: transport,
      usagePort: transport,
      acpPort: transport,
      coordinator: coordinator,
      mutations: board,
      budget: budget,
      owner: clientId,
    );
    client = AnyworkClient(
      transport: transport,
      clientId: clientId,
      budget: budget,
      settingsWrites: coordinator,
      mutationBoard: board,
      accountDomains: domains,
    );
    domains.onSettings = client.acceptSettingsSnapshot;
    domains.attachDirectoryDemand(
      () =>
          _TopicDemand(client.channels.acquireTopic(const ModelCatalogTopic())),
    );
    domains.adoptOwnerEpoch(transport.epoch);
  }
  final AccountsTestTransport transport;
  final ResourceBudget budget = ResourceBudget();
  final SettingsWriteCoordinator coordinator = SettingsWriteCoordinator();
  late final MutationBoard board;
  late final AccountDomainResources domains;
  late final AnyworkClient client;

  void seed(SettingsStateSnapshot snapshot) {
    for (final frame in accountFrames(snapshot, epoch: transport.epoch)) {
      transport.baselines[frame.target] = frame;
      domains.acceptFrame(frame);
    }
    coordinator.observe(
      testStamp('settings', snapshot.revision, epoch: transport.epoch),
    );
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    final bound = deadline ?? DateTime.now().add(const Duration(seconds: 1));
    final clientClose = client.close(deadline: bound);
    final domainClose = domains.close(deadline: bound);
    return CloseReport(
      unresolved: [
        ...(await clientClose).unresolved,
        ...(await domainClose).unresolved,
      ],
    );
  }
}

final class _TopicDemand implements AccountDemand {
  _TopicDemand(this.lease);
  final BridgeTopicLease lease;
  @override
  Future<void> release() => lease.release();
}

ResourceStamp testStamp(String key, int revision, {String epoch = 'owner'}) =>
    ResourceStamp(resourceKey: key, ownerEpoch: epoch, revision: revision);

SettingsCommandReply accountReply({
  required SettingsStateSnapshot snapshot,
  required StudioCommandReceipt receipt,
}) => SettingsCommandReply(
  snapshot: snapshot,
  receipt: receipt,
  accountFrames: accountFrames(
    snapshot,
    epoch: receipt.targets.firstOrNull?.ownerEpoch ?? 'owner',
  ),
);

/// Fixture projection of complete owner responses, not a business reducer.
List<AccountDomainFrame> accountFrames(
  SettingsStateSnapshot snapshot, {
  String epoch = 'owner',
}) => [
  AccountSummariesFrame(
    testStamp('settings', snapshot.revision, epoch: epoch),
    [
      for (final account in snapshot.accounts)
        AccountSummary(
          identity: NativeAccountIdentity(account.id),
          name: account.name,
          brandKey: account.templateId,
          isDefault: account.id == snapshot.defaultAccountId,
          billingKind: account.billingKind,
          billingKindOverride: account.billingKindOverride,
          credentialReady:
              account.hasBearerToken || !account.credentialRequired,
          usageQueryRevision: account.usageQueryRevision,
          capabilities: AccountCapabilities(
            setDefault: true,
            edit: true,
            remove: true,
            queryUsage: true,
            syncModels: account.modelCatalog.supported,
            editModels: true,
            acpAuth: false,
          ),
        ),
      for (final account in snapshot.acpAccounts)
        AccountSummary(
          identity: AcpAccountIdentity(account.accountId),
          name: account.name,
          isDefault: false,
          brandKey: account.provider.wire,
          capabilities: const AccountCapabilities(
            setDefault: false,
            edit: true,
            remove: true,
            queryUsage: false,
            syncModels: false,
            editModels: false,
            acpAuth: true,
          ),
        ),
    ],
  ),
  for (final account in snapshot.accounts)
    AccountDetailFrame(
      testStamp('settings', snapshot.revision, epoch: epoch),
      NativeAccountIdentity(account.id),
      NativeAccountDetails(
        identity: NativeAccountIdentity(account.id),
        name: account.name,
        protocol: account.protocol,
        templateId: account.templateId,
        baseUrl: account.baseUrl,
        hasBearerToken: account.hasBearerToken,
        credentialRequired: account.credentialRequired,
        usageQueryRevision: account.usageQueryRevision,
        customModels: [
          for (final model in account.models.where(
            (model) => model.origin == ModelOrigin.manual,
          ))
            AccountModelCommand(
              modelId: model.modelId,
              displayName: model.displayName,
              wireApi: model.wireApi,
              contextWindow: model.contextWindow,
              maxOutputTokens: model.maxOutputTokens,
            ),
        ],
      ),
      modelConfiguration: AccountModelConfiguration(
        modelEnabledOverrides: account.modelEnabledOverrides,
        connections: {
          for (final entry in account.modelConnectionModes.entries)
            entry.key: switch (entry.value) {
              'http' => AccountConnectionMode.http,
              'web_socket' => AccountConnectionMode.webSocket,
              final mode => throw ArgumentError.value(
                mode,
                'mode',
                'Unknown account connection',
              ),
            },
        },
        autoCompactLimits: {
          for (final entry in account.autoCompactLimits.entries)
            if (entry.value.overrideLimit case final limit?) entry.key: limit,
        },
      ),
    ),
  for (final account in snapshot.accounts)
    AccountModelsFrame(
      testStamp('model-catalog', snapshot.modelCatalogRevision, epoch: epoch),
      NativeAccountIdentity(account.id),
      AccountModelCatalog(
        identity: NativeAccountIdentity(account.id),
        models: account.models,
        status: account.modelCatalog,
      ),
    ),
  for (final account in snapshot.acpAccounts)
    AccountDetailFrame(
      testStamp('settings', snapshot.revision, epoch: epoch),
      AcpAccountIdentity(account.accountId),
      AcpAccountDetails(account),
    ),
];

AccountModelIdentity modelIdentity(String account, String model) =>
    AccountModelIdentity(
      account: NativeAccountIdentity(account),
      modelId: model,
    );

List<ModelSelectionAccount> selectionAccounts(
  Iterable<AccountSettingsView> accounts,
) => [
  for (final account in accounts)
    ModelSelectionAccount(
      id: account.id,
      name: account.name,
      brandKey: account.iconKey,
      billingKind: account.billingKind,
      models: account.models,
    ),
];

AccountUsageFrame usageFrame(
  int revision,
  Iterable<AccountUsageObservation> accounts, {
  String epoch = 'owner',
}) => AccountUsageFrame(
  testStamp('account-usage', revision, epoch: epoch),
  accounts,
);
