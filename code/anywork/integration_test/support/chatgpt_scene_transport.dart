import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/studio_client.dart';

import '../../../anywork_client/test/support/accounts_test_runtime.dart';

/// Controls external replies only. The account Client, command lanes, router,
/// Riverpod projections and widgets are production implementations.
class ChatGptSceneTransport extends DemoStudioTransport {
  ChatGptSceneTransport() : super(accountCatalog: _catalog());
  final _observers = <AccountObservationTarget, Set<TestAccountObservation>>{};
  final logins = <String, ChatGptLoginSnapshot>{};
  final authenticated = <String, ChatGptAccountInfo>{};
  String? _epoch;
  int starts = 0;
  int creates = 0;
  int cancels = 0;
  int queries = 0;
  int _usageRevision = 0;
  AccountUsageObservation? usage;
  List<AccountUsageObservation> _baseUsage = const [];
  Completer<AccountUsageFrame>? pendingUsage;
  CreateAccountCommand? created;
  PatchAccountCommand? patched;

  static AccountCatalogView _catalog() {
    const catalog = demoAccountCatalogFixture;
    return AccountCatalogView(
      schemaVersion: catalog.schemaVersion,
      revision: catalog.revision,
      templates: [
        ...catalog.templates.where((template) => template.id != 'openai'),
        const AccountTemplateView(
          id: 'openai',
          displayName: 'OpenAI',
          description: '',
          baseUrl: 'https://api.openai.com/v1',
          credentialLabel: 'API key',
          credentialEnv: 'OPENAI_API_KEY',
          modelCatalogId: 'openai',
          protocol: 'open_ai',
          suggestedModelId: 'gpt-5',
          defaultBillingKind: BillingKind.subscription,
          supportsModelDiscovery: true,
          supportsUsageQuery: false,
        ),
      ],
      modelCatalogs: catalog.modelCatalogs,
    );
  }

  static const accountInfo = ChatGptAccountInfo(
    issuer: 'https://auth.openai.com',
    subject: 'subject-test',
    clientId: 'app_EMoamEEZ73f0CkXaXp7hrann',
    email: 'subscriber@example.test',
    planUsageEnabled: true,
    codex: CodexAccountInfo(accountId: 'workspace-test', planType: 'plus'),
  );

  ResourceStamp stamp(String key, int revision) =>
      ResourceStamp(resourceKey: key, ownerEpoch: _epoch!, revision: revision);

  // The complete feed has one clock, including the Demo's unrelated accounts.
  AccountUsageFrame _usageFrame() => AccountUsageFrame(
    stamp('account-usage', _usageRevision),
    [..._baseUsage.where((value) => value.identity != usage?.identity), ?usage],
  );

  AccountDomainFrame _enrich(AccountDomainFrame frame) => switch (frame) {
    AccountSummariesFrame(:final accounts) => AccountSummariesFrame(
      frame.stamp,
      accounts.map((account) {
        final info = authenticated[account.identity.accountId];
        if (info == null) return account;
        return AccountSummary(
          identity: account.identity,
          name: account.name,
          brandKey: account.brandKey,
          displayEndpoint: account.displayEndpoint,
          chatgptAccount: info,
          isDefault: account.isDefault,
          billingKind: BillingKind.subscription,
          credentialReady: true,
          usageQueryRevision: account.usageQueryRevision,
          capabilities: const AccountCapabilities(
            setDefault: true,
            edit: true,
            remove: true,
            queryUsage: true,
            syncModels: true,
            editModels: true,
            acpAuth: false,
          ),
        );
      }),
    ),
    AccountDetailFrame(:final identity, :final account)
        when account is NativeAccountDetails &&
            authenticated.containsKey(identity.accountId) =>
      AccountDetailFrame(
        frame.stamp,
        identity,
        NativeAccountDetails(
          identity: account.identity,
          name: account.name,
          authentication: AccountAuthenticationMethod.chatGpt,
          chatgptAccount: authenticated[identity.accountId],
          protocol: account.protocol,
          templateId: account.templateId,
          baseUrl: 'https://chatgpt.com/backend-api/codex',
          hasBearerToken: false,
          credentialRequired: false,
          usageQueryRevision: account.usageQueryRevision,
          customModels: account.customModels,
        ),
        modelConfiguration: frame.modelConfiguration,
      ),
    _ => frame,
  };

  @override
  Future<AccountDomainFrame> readAccountDomain(
    AccountObservationTarget target,
  ) async {
    if (target case ChatGptLoginTarget(:final loginId)) {
      final snapshot = logins[loginId]!;
      return ChatGptLoginFrame(stamp(target.key, snapshot.revision), snapshot);
    }
    final original = await super.readAccountDomain(target);
    _epoch = original.stamp.ownerEpoch;
    if (target is AccountUsageTarget) {
      _baseUsage = (original as AccountUsageFrame).accounts;
      return _usageFrame();
    }
    return _enrich(original);
  }

  @override
  Future<AccountDomainObservation> openAccountObservation(
    AccountObservationTarget target,
  ) async {
    late TestAccountObservation observation;
    observation = TestAccountObservation(
      () => _observers[target]?.remove(observation),
    );
    _observers.putIfAbsent(target, () => {}).add(observation);
    observation.emit(await readAccountDomain(target));
    return observation;
  }

  void emit(AccountDomainFrame frame) {
    for (final observer
        in _observers[frame.target]?.toList() ?? <TestAccountObservation>[]) {
      observer.emit(frame);
    }
  }

  void loginPhase(
    String loginId,
    ChatGptLoginPhase phase, {
    int? revision,
    ChatGptLoginFailure? failure,
  }) {
    final before = logins[loginId]!;
    final snapshot = ChatGptLoginSnapshot(
      loginId: loginId,
      editorId: before.editorId,
      accountId: before.accountId,
      revision: revision ?? before.revision + 1,
      phase: phase,
      account: phase == ChatGptLoginPhase.succeeded ? accountInfo : null,
      failure: failure,
    );
    logins[loginId] = snapshot;
    emit(
      ChatGptLoginFrame(
        stamp('chatgpt-login:$loginId', snapshot.revision),
        snapshot,
      ),
    );
  }

  @override
  Future<ChatGptLoginCommandReply> startChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) async {
    starts++;
    logins[loginId] = ChatGptLoginSnapshot(
      loginId: loginId,
      editorId: editorId,
      accountId: accountId,
      revision: 1,
      phase: ChatGptLoginPhase.awaitingBrowser,
    );
    return ChatGptLoginCommandReply(
      stamp: stamp('chatgpt-login:$loginId', 1),
      snapshot: logins[loginId]!,
    );
  }

  @override
  Future<ChatGptLoginCommandReply> cancelChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) async {
    cancels++;
    loginPhase(loginId, ChatGptLoginPhase.cancelled);
    final snapshot = logins[loginId]!;
    return ChatGptLoginCommandReply(
      stamp: stamp('chatgpt-login:$loginId', snapshot.revision),
      snapshot: snapshot,
    );
  }

  Future<SettingsCommandReply> _committed(SettingsCommandReply reply) async {
    final frames = [
      await readAccountDomain(const AccountSummariesTarget()),
      ...reply.accountFrames.map(_enrich),
    ];
    for (final frame in frames) {
      emit(frame);
    }
    final receipt = reply.receipt;
    return SettingsCommandReply(
      snapshot: reply.snapshot,
      accountFrames: frames,
      receipt: StudioCommandReceipt(
        operationId: receipt.operationId,
        disposition: receipt.disposition,
        targets: receipt.targets,
        effect: receipt.effect,
        effective: receipt.effective,
        durable: true,
        requiresIdentityObservation: receipt.requiresIdentityObservation,
      ),
    );
  }

  @override
  Future<SettingsCommandReply> createAccount(
    int revision,
    CreateAccountCommand command, {
    required OperationId operationId,
  }) async {
    creates++;
    created = command;
    if (command.authentication is SelectChatGptAuthentication) {
      authenticated[command.identity.accountId] = accountInfo;
    }
    return _committed(
      await super.createAccount(revision, command, operationId: operationId),
    );
  }

  @override
  Future<SettingsCommandReply> patchAccount(
    int revision,
    PatchAccountCommand command, {
    required OperationId operationId,
  }) async {
    patched = command;
    if (command.authentication is SelectApiKeyAuthentication) {
      authenticated.remove(command.identity.accountId);
      if (usage?.identity == command.identity) usage = null;
    }
    return _committed(
      await super.patchAccount(revision, command, operationId: operationId),
    );
  }

  @override
  Future<SettingsCommandReply> removeAccount(
    int revision,
    String accountId, {
    required OperationId operationId,
    String? replacementAccountId,
  }) async => _committed(
    await super.removeAccount(
      revision,
      accountId,
      operationId: operationId,
      replacementAccountId: replacementAccountId,
    ),
  );

  @override
  Future<AccountUsageFrame> queryAccountUsage(
    NativeAccountIdentity identity,
  ) async {
    if (!authenticated.containsKey(identity.accountId)) {
      final frame = await super.queryAccountUsage(identity);
      _baseUsage = frame.accounts;
      _usageRevision++;
      final current = _usageFrame();
      emit(current);
      return current;
    }
    queries++;
    final summaries = await readAccountDomain(
      const AccountSummariesTarget(),
    ) as AccountSummariesFrame;
    final account = summaries.accounts.singleWhere(
      (account) => account.identity == identity,
    );
    usage = AccountUsageObservation(
      identity: identity,
      queryRevision: account.usageQueryRevision!,
      revision: ++_usageRevision,
      phase: AccountUsagePhase.querying,
    );
    emit(_usageFrame());
    pendingUsage = Completer<AccountUsageFrame>();
    return pendingUsage!.future;
  }

  void completeUsage({bool fail = false, bool empty = false}) {
    final before = usage!;
    usage = AccountUsageObservation(
      identity: before.identity,
      queryRevision: before.queryRevision,
      revision: ++_usageRevision,
      phase: fail ? AccountUsagePhase.failed : AccountUsagePhase.succeeded,
      failure: fail
          ? const AccountUsageFailure(
              code: AccountUsageFailureCode.query,
              retryable: true,
            )
          : null,
      lastGood: fail
          ? null
          : AccountUsageSuccess(
              checkedAt: 1800000000,
              value: AccountSubscription(
                level: 'plus',
                quotas: empty
                    ? []
                    : [
                        AccountQuota(
                          window: const AccountQuotaWindow(
                            AccountQuotaWindowKind.fiveHour,
                          ),
                          percentage: 23,
                          resetAt: 1800005000,
                        ),
                        AccountQuota(
                          window: const AccountQuotaWindow(
                            AccountQuotaWindowKind.weekly,
                          ),
                          percentage: 95,
                          resetAt: 1800600000,
                        ),
                      ],
              ),
            ),
    );
    final frame = _usageFrame();
    emit(frame);
    pendingUsage!.complete(frame);
    pendingUsage = null;
  }
}
