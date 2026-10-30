import 'dart:async';

import 'package:anywork/src/features/settings/accounts/connectors/account_strings.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_state.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_session_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_models_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_details_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_projection.dart';
import 'package:anywork/src/presentation/providers/account_domains.dart';
import 'package:anywork/src/presentation/providers/account_operation_observation.dart';
import 'package:anywork/src/l10n/app_localizations_en.dart';
import 'package:anywork/src/l10n/app_localizations_zh.dart';
import 'package:anywork_client/accounts.dart'
    hide
        AccountAuthenticationMethod,
        ChatGptAccountInfo,
        ChatGptLoginPhase,
        ChatGptLoginSnapshot;
import 'package:anywork_client/accounts.dart'
    as account_domain
    show
        AccountAuthenticationMethod,
        ChatGptAccountInfo,
        ChatGptLoginPhase,
        ChatGptLoginSnapshot;
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const vmStamp = ResourceStamp(
  resourceKey: 'test',
  ownerEpoch: 'owner',
  revision: 1,
);
const nativeKey = AccountDisplayKey(kind: AccountKind.native, id: 'native');
const nativeTemplate = AccountTemplateView(
  id: 'native',
  displayName: 'Native brand',
  description: 'Official endpoint',
  baseUrl: 'https://native.example/v1',
  credentialLabel: 'API token',
  credentialEnv: 'NATIVE_TOKEN',
  modelCatalogId: 'bundled',
  protocol: 'open_ai',
  suggestedModelId: 'suggested',
  defaultBillingKind: BillingKind.subscription,
  supportsModelDiscovery: false,
  supportsUsageQuery: null,
);
const customTemplate = AccountTemplateView(
  id: 'custom',
  displayName: 'Custom',
  description: '',
  baseUrl: '',
  credentialLabel: 'Optional token',
  credentialEnv: '',
  modelCatalogId: '',
  protocol: 'open_ai',
  suggestedModelId: '',
  defaultBillingKind: BillingKind.noCharge,
  supportsModelDiscovery: true,
  supportsUsageQuery: false,
);
const openaiTemplate = AccountTemplateView(
  id: 'openai',
  displayName: 'OpenAI',
  description: 'Official OpenAI API',
  baseUrl: 'https://api.openai.com/v1',
  credentialLabel: 'API key',
  credentialEnv: 'OPENAI_API_KEY',
  modelCatalogId: 'openai',
  protocol: 'open_ai',
  suggestedModelId: 'gpt-4o',
  defaultBillingKind: BillingKind.subscription,
  supportsModelDiscovery: true,
  supportsUsageQuery: false,
);
const vmAcpTemplate = AcpAccountTemplateView(
  provider: AcpProviderView.antigravity,
  displayName: 'Antigravity',
  supportedVersion: '1.4.1',
  automaticInstall: AcpInstallAvailableView(target: 'linux-x86_64'),
);
const vmCapabilities = AccountCapabilities(
  setDefault: true,
  edit: true,
  remove: true,
  queryUsage: true,
  syncModels: true,
  editModels: true,
  acpAuth: false,
);

OperationState savedVmOperation([String id = 'saved']) => OperationState(
  id: OperationId(id),
  target: 'test',
  observed: true,
  durable: true,
  receipt: CommitReceipt(
    operationId: OperationId(id),
    disposition: CommitDisposition.applied,
    targets: const [],
    effect: EffectPoint.immediate,
    durable: true,
  ),
);

const vmOperationStrings = AccountStrings({
  'unknownOutcome': 'Outcome unknown',
  'saveFailed': 'Save failed',
  'awaitingObservation': 'Waiting for observation',
  'unconfirmedDiscard': 'May still change canonical settings',
});

/// Typed SDK outcomes are environment inputs, not a test-side classifier.
OperationState failedVmOperation(
  OperationPhase phase, {
  required String id,
  required Object error,
}) => OperationState(
  id: OperationId(id),
  target: 'test',
  failurePhase: phase,
  error: error,
  receipt: phase == OperationPhase.syncFailed
      ? CommitReceipt(
          operationId: OperationId(id),
          disposition: CommitDisposition.applied,
          targets: const [vmStamp],
          effect: EffectPoint.immediate,
          durable: true,
        )
      : null,
);
AccountSummary vmSummary(
  AccountIdentity identity, {
  String? name,
  String? displayEndpoint,
  int? acpRevision = 1,
  bool? credentialReady,
}) => AccountSummary(
  identity: identity,
  name: name ?? identity.accountId,
  displayEndpoint: displayEndpoint,
  isDefault: false,
  billingKind: identity is NativeAccountIdentity ? BillingKind.metered : null,
  usageQueryRevision: 1,
  acpConnectionRevision: identity is AcpAccountIdentity ? acpRevision : null,
  credentialReady: credentialReady,
  capabilities: identity is NativeAccountIdentity
      ? vmCapabilities
      : const AccountCapabilities(
          setDefault: false,
          edit: true,
          remove: true,
          queryUsage: false,
          syncModels: false,
          editModels: false,
          acpAuth: true,
        ),
);
NativeAccountDetails vmNative({
  String id = 'native',
  String name = 'Saved name',
  List<AccountModelCommand> manual = const [],
  bool hasBearerToken = true,
  account_domain.AccountAuthenticationMethod authentication =
      account_domain.AccountAuthenticationMethod.apiKey,
}) => NativeAccountDetails(
  identity: NativeAccountIdentity(id),
  name: name,
  authentication: authentication,
  protocol: 'open_ai',
  templateId: 'native',
  baseUrl: 'https://native.example/v1',
  hasBearerToken: hasBearerToken,
  credentialRequired: true,
  usageQueryRevision: 1,
  customModels: manual,
);

/// These stubs provide domain publications and controllable action completion.
/// They do not implement draft, validation, navigation, retry or ownership rules.
/// Kept here because this task owns exactly six contract-test files, not support/.
class VmDemand implements AccountDemand {
  int releases = 0;
  @override
  Future<void> release() async {
    releases++;
  }
}

class VmAccounts implements AccountsRepository {
  VmAccounts()
    : state = LatestValue(
        AccountsState(
          stamp: vmStamp,
          accounts: [vmSummary(const NativeAccountIdentity('native'))],
          templates: const AccountCatalogView(
            schemaVersion: 1,
            revision: 'templates',
            templates: [nativeTemplate, customTemplate],
            modelCatalogs: {
              'bundled': [
                AccountModelView(
                  modelId: 'suggested',
                  displayName: 'Suggested',
                  reasoningEfforts: [],
                ),
              ],
            },
          ),
        ),
      );
  @override
  final LatestValue<AccountsState> state;
  final slots =
      <AccountIdentity, LatestValue<AccountResource<AccountDetails>>>{};
  final detailDemands = <VmDemand>[];
  final summaryDemands = <VmDemand>[];
  final patches = <PatchAccountCommand>[];
  final creates = <CreateAccountCommand>[];
  final billing = <BillingKind?>[];
  final defaultCalls = <NativeAccountIdentity>[];
  final chatGptLoginDemands = <VmDemand>[];
  final chatGptLoginIntentDemands = <VmDemand>[];
  final chatGptLoginTargets = <(String, String, String)>[];
  final chatGptLoginRegistrations = <(String, String, String)>[];
  final chatGptLoginCallOrder = <String>[];
  final chatGptLoginIdentities = <String, (String, String)>{};
  final chatGptLoginValues =
      <
        String,
        LatestValue<AccountResource<account_domain.ChatGptLoginSnapshot>>
      >{};
  final removals = <NativeAccountIdentity>[];
  final mutationCalls = <String>[];
  Future<OperationState> Function()? write;
  Future<OperationState> Function()? createWrite;
  Future<OperationState> Function()? patchWrite;
  Future<OperationState> Function()? defaultWrite;
  Future<account_domain.ChatGptLoginSnapshot> Function(String, String, String)?
  loginStart;
  Future<account_domain.ChatGptLoginSnapshot> Function(String, String, String)?
  loginCancel;
  int detailReads = 0;
  Object? detailFailure;
  void put(AccountDetails details, {bool stale = false}) =>
      (slots[details.identity] ??= LatestValue(
        const AccountResource(),
      )).publish(AccountResource(stamp: vmStamp, value: details, stale: stale));
  @override
  ValueObservation<AccountResource<AccountDetails>> details(
    AccountIdentity id,
  ) {
    detailReads++;
    return slots.putIfAbsent(id, () => LatestValue(const AccountResource()));
  }

  @override
  ValueObservation<AccountResource<account_domain.ChatGptLoginSnapshot>>
  chatGptLogin(String loginId) => chatGptLoginValues.putIfAbsent(
    loginId,
    () => LatestValue(const AccountResource()),
  );

  @override
  AccountDemand registerChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) {
    chatGptLoginCallOrder.add('register');
    chatGptLoginRegistrations.add((loginId, editorId, accountId));
    chatGptLoginIdentities[loginId] = (editorId, accountId);
    final demand = VmDemand();
    chatGptLoginIntentDemands.add(demand);
    return demand;
  }

  @override
  AccountDemand observeChatGptLogin(String loginId) {
    chatGptLoginCallOrder.add('observe');
    final identity = chatGptLoginIdentities[loginId];
    if (identity == null) throw StateError('Login intent is not registered');
    chatGptLoginTargets.add((loginId, identity.$1, identity.$2));
    final demand = VmDemand();
    chatGptLoginDemands.add(demand);
    return demand;
  }

  void publishChatGptLogin(account_domain.ChatGptLoginSnapshot snapshot) {
    chatGptLoginValues
        .putIfAbsent(
          snapshot.loginId,
          () => LatestValue(const AccountResource()),
        )
        .publish(
          AccountResource(
            stamp: ResourceStamp(
              resourceKey: 'settings',
              ownerEpoch: 'owner',
              revision: snapshot.revision,
            ),
            value: snapshot,
          ),
        );
  }

  @override
  Future<account_domain.ChatGptLoginSnapshot> startChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) async {
    chatGptLoginCallOrder.add('start');
    final snapshot = await loginStart!(loginId, editorId, accountId);
    publishChatGptLogin(snapshot);
    return snapshot;
  }

  @override
  Future<account_domain.ChatGptLoginSnapshot> cancelChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) async {
    final snapshot = await loginCancel!(loginId, editorId, accountId);
    publishChatGptLogin(snapshot);
    return snapshot;
  }

  @override
  AccountDemand observeDetails(AccountIdentity identity) {
    if (detailFailure case final error?) {
      throw error;
    }
    final demand = VmDemand();
    detailDemands.add(demand);
    return demand;
  }

  @override
  AccountDemand observeSummaries() {
    final demand = VmDemand();
    summaryDemands.add(demand);
    return demand;
  }

  @override
  Future<void> loadTemplates() async {}
  @override
  Future<OperationState> patch(
    PatchAccountCommand command, {
    DraftStamp? draft,
  }) {
    patches.add(command);
    mutationCalls.add('patch');
    return patchWrite?.call() ??
        write?.call() ??
        Future.value(savedVmOperation());
  }

  @override
  Future<OperationState> create(
    CreateAccountCommand command, {
    DraftStamp? draft,
  }) {
    creates.add(command);
    mutationCalls.add('create');
    return createWrite?.call() ??
        write?.call() ??
        Future.value(savedVmOperation());
  }

  @override
  Future<OperationState> setBillingKind(
    NativeAccountIdentity id,
    BillingKind? kind,
  ) async {
    billing.add(kind);
    return savedVmOperation();
  }

  @override
  Future<OperationState> setDefault(NativeAccountIdentity identity) {
    defaultCalls.add(identity);
    mutationCalls.add('default');
    return defaultWrite?.call() ??
        write?.call() ??
        Future.value(savedVmOperation());
  }

  @override
  Future<OperationState> remove(
    NativeAccountIdentity identity, {
    NativeAccountIdentity? replacement,
  }) {
    removals.add(identity);
    return write?.call() ?? Future.value(savedVmOperation());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class VmModels implements ModelsRepository {
  VmModels()
    : state = LatestValue(
        ModelDirectoryState(
          accounts: {
            const NativeAccountIdentity('native'): AccountResource(
              stamp: vmStamp,
              value: AccountModelCatalog(
                identity: const NativeAccountIdentity('native'),
                models: const [
                  AccountModelView(
                    modelId: 'model',
                    displayName: 'Model',
                    reasoningEfforts: [],
                    maxOutputTokens: 4096,
                    outputModalities: [ModelModalityView.text],
                    context: ModelContextView(
                      unavailable: null,
                      contextWindow: 2000,
                      autoCompactLimit: 1000,
                    ),
                  ),
                ],
                status: const ModelCatalogStatusView(supported: true),
              ),
            ),
          },
          configurations: {
            const NativeAccountIdentity('native'): AccountResource(
              stamp: vmStamp,
              value: AccountModelConfiguration(),
            ),
          },
        ),
      );
  @override
  final LatestValue<ModelDirectoryState> state;
  final demands = <VmDemand>[];
  final compactCalls = <(AccountModelIdentity, AutoCompactIntent)>[];
  final compactDrafts = <DraftStamp?>[];
  final connections = <(AccountModelIdentity, ModelConnectionIntent)>[];
  final removed = <AccountModelIdentity>[];
  Future<OperationState> Function()? compactWrite;
  Future<OperationState> Function()? connectionWrite;
  Future<OperationState> Function()? removeWrite;
  Future<DelegationModelDetail> Function()? readout;
  @override
  AccountDemand observeAccount(NativeAccountIdentity identity) {
    final demand = VmDemand();
    demands.add(demand);
    return demand;
  }

  @override
  Future<OperationState> setAutoCompact(
    AccountModelIdentity id,
    AutoCompactIntent intent, {
    DraftStamp? draft,
  }) {
    compactCalls.add((id, intent));
    compactDrafts.add(draft);
    return compactWrite?.call() ?? Future.value(savedVmOperation());
  }

  @override
  Future<OperationState> setConnection(
    AccountModelIdentity id,
    ModelConnectionIntent intent,
  ) {
    connections.add((id, intent));
    return connectionWrite?.call() ?? Future.value(savedVmOperation());
  }

  @override
  Future<OperationState> removeManual(AccountModelIdentity id) async {
    removed.add(id);
    return removeWrite?.call() ?? savedVmOperation();
  }

  @override
  Future<DelegationModelDetail> performance(AccountModelIdentity id) =>
      readout!();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

/// Canonical manual-model input for deletion consumers, not deletion behavior.
void publishVmManualModel(
  VmModels models,
  NativeAccountIdentity identity, {
  String modelId = 'manual',
}) {
  final current = models.state.value;
  final existing = current.accounts[identity];
  models.state.publish(
    ModelDirectoryState(
      accounts: {
        ...current.accounts,
        identity: AccountResource(
          stamp: existing?.stamp ?? vmStamp,
          value: AccountModelCatalog(
            identity: identity,
            models: [
              for (final model
                  in existing?.value?.models ?? <AccountModelView>[])
                if (model.modelId != modelId) model,
              AccountModelView(
                modelId: modelId,
                displayName: 'Manual model',
                reasoningEfforts: const [],
                origin: ModelOrigin.manual,
                context: const ModelContextView(
                  unavailable: null,
                  contextWindow: 2000,
                  autoCompactLimit: 1000,
                ),
              ),
            ],
            status: const ModelCatalogStatusView(supported: true),
          ),
        ),
      },
      configurations: {
        ...current.configurations,
        identity:
            current.configurations[identity] ??
            AccountResource(stamp: vmStamp, value: AccountModelConfiguration()),
      },
    ),
  );
}

class VmUsage implements AccountUsageRepository {
  @override
  final LatestValue<
    AccountResource<Map<NativeAccountIdentity, AccountUsageObservation>>
  >
  state =
      LatestValue<
        AccountResource<Map<NativeAccountIdentity, AccountUsageObservation>>
      >(const AccountResource(stamp: vmStamp, value: {}));
  @override
  final LatestValue<Map<NativeAccountIdentity, StudioFailure>> queryFailures =
      LatestValue<Map<NativeAccountIdentity, StudioFailure>>({});
  final demands = <VmDemand>[];
  @override
  AccountDemand observeVisible() {
    final demand = VmDemand();
    demands.add(demand);
    return demand;
  }

  @override
  Future<void> refresh(NativeAccountIdentity identity) async {}
}

class VmAcp implements AcpService {
  @override
  final LatestValue<AcpAccountCatalogView> templates = LatestValue(
    const AcpAccountCatalogView(templates: [vmAcpTemplate]),
  );
  @override
  final LatestValue<AccountResource<AcpAuthSnapshotView>> auth =
      LatestValue<AccountResource<AcpAuthSnapshotView>>(
        const AccountResource(
          stamp: vmStamp,
          value: AcpAuthSnapshotView.empty(),
        ),
      );
  @override
  final LatestValue<AccountResource<AcpInstallSnapshotView>> install =
      LatestValue<AccountResource<AcpInstallSnapshotView>>(
        const AccountResource(
          stamp: vmStamp,
          value: AcpInstallSnapshotView.empty(),
        ),
      );
  final demands = <VmDemand>[];
  final starts = <Completer<AcpInstallSnapshotView>>[];
  Completer<void>? prepareStarted;
  final cancels = <Completer<AcpInstallSnapshotView>>[];
  final authStarts = <Completer<AcpAuthSnapshotView>>[];
  final authCancels = <Completer<AcpAuthSnapshotView>>[];
  final saves = <AcpAccountUpdateView>[];
  final removals = <AcpAccountIdentity>[];
  Future<OperationState> Function()? removeWrite;
  Future<AcpSaveAndConnectResult> Function(AcpAccountUpdateView command)?
  connect;
  Future<OperationState> Function()? write;
  @override
  Future<void> loadTemplates() async {}
  @override
  Future<OperationState> remove(AcpAccountIdentity identity) {
    removals.add(identity);
    return removeWrite?.call() ?? Future.value(savedVmOperation());
  }

  @override
  AccountDemand observeAuth() {
    final demand = VmDemand();
    demands.add(demand);
    return demand;
  }

  @override
  AccountDemand observeInstall() {
    final demand = VmDemand();
    demands.add(demand);
    return demand;
  }

  @override
  Future<AcpInstallSnapshotView> prepare(AcpProviderView provider) {
    final work = Completer<AcpInstallSnapshotView>();
    starts.add(work);
    final started = prepareStarted;
    if (started != null && !started.isCompleted) started.complete();
    return work.future;
  }

  @override
  Future<AcpInstallSnapshotView> cancelPreparation(AcpProviderView provider) {
    final work = Completer<AcpInstallSnapshotView>();
    cancels.add(work);
    return work.future;
  }

  @override
  Future<AcpAuthSnapshotView> check(AcpAccountIdentity identity) {
    final work = Completer<AcpAuthSnapshotView>();
    authStarts.add(work);
    return work.future;
  }

  @override
  Future<AcpAuthSnapshotView> login(
    AcpAccountIdentity identity, {
    required String methodId,
  }) => check(identity);
  @override
  Future<AcpAuthSnapshotView> cancelAuth(AcpAccountIdentity identity) {
    final work = Completer<AcpAuthSnapshotView>();
    authCancels.add(work);
    return work.future;
  }

  @override
  Future<OperationState> save(
    AcpAccountUpdateView account, {
    DraftStamp? draft,
  }) {
    saves.add(account);
    return write?.call() ?? Future.value(savedVmOperation());
  }

  @override
  Future<AcpSaveAndConnectResult> saveAndConnect(
    AcpAccountUpdateView account, {
    DraftStamp? draft,
  }) {
    saves.add(account);
    return connect!(account);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class AccountsVmHarness {
  AccountsVmHarness({AccountOperationLookup? operationLookup}) {
    container = ProviderContainer(
      overrides: [
        accountsRepositoryProvider.overrideWithValue(accounts),
        modelsRepositoryProvider.overrideWithValue(models),
        accountUsageRepositoryProvider.overrideWithValue(usage),
        acpServiceProvider.overrideWithValue(acp),
        accountOperationObservationProvider.overrideWithValue(
          operationLookup ?? (id) => null,
        ),
      ],
    );
  }
  final accounts = VmAccounts();
  final models = VmModels();
  final usage = VmUsage();
  final acp = VmAcp();
  late final ProviderContainer container;
  final List<void Function()> _listeners = [];
  final _sessionSlots =
      Map<AccountEditorSessionOwner, AccountEditorSessionViewModel>.identity();
  Future<AccountsViewModel> listOwner() async {
    _listeners.add(
      container.listen(accountsViewModelProvider, (_, _) {}).close,
    );
    await container.read(accountsViewModelProvider.future);
    return container.read(accountsViewModelProvider.notifier);
  }

  AccountEditorSessionOwner claimSession(AccountEditorEntryKey entry) {
    final slot = container.read(
      accountEditorSessionViewModelProvider(entry).notifier,
    );
    final owner = slot.claimMount(Object());
    _sessionSlots[owner] = slot;
    return owner;
  }

  void releaseSession(AccountEditorSessionOwner owner) {
    final slot = _sessionSlots[owner];
    if (slot == null) throw StateError('Session owner was not claimed here.');
    slot.releaseMount(owner);
  }

  Future<AccountEditorSessionOwner> session(AccountEditorEntryKey entry) async {
    final provider = accountEditorSessionViewModelProvider(entry);
    _listeners.add(container.listen(provider, (_, _) {}).close);
    await container.read(provider.future);
    final owner = claimSession(entry);
    await owner.initialize();
    expect(container.read(provider).requireValue.ownerId, owner.ownerId);
    return owner;
  }

  Future<AccountEditorViewModel> editor(AccountEditorKey key) async {
    _listeners.add(
      container.listen(accountEditorViewModelProvider(key), (_, _) {}).close,
    );
    await container.read(accountEditorViewModelProvider(key).future);
    return container.read(accountEditorViewModelProvider(key).notifier);
  }

  Future<AccountModelsViewModel> modelOwner({
    AccountDisplayKey key = nativeKey,
  }) async {
    final provider = accountModelsViewModelProvider(key);
    _listeners.add(container.listen(provider, (_, _) {}).close);
    await container.read(provider.future);
    return container.read(provider.notifier);
  }

  Future<AccountDetailsViewModel> details(AccountDisplayKey key) async {
    final provider = accountDetailsViewModelProvider(key);
    _listeners.add(container.listen(provider, (_, _) {}).close);
    await container.read(provider.future);
    return container.read(provider.notifier);
  }

  AccountEditorViewState editorState(AccountEditorKey key) =>
      container.read(accountEditorViewModelProvider(key)).requireValue;
  void dispose() {
    for (final entry in _sessionSlots.entries) {
      entry.value.releaseMount(entry.key);
    }
    for (final close in _listeners) {
      close();
    }
    container.dispose();
  }
}

AccountEditorKey editKey([String editorId = 'edit']) =>
    AccountEditorKey(editorId: editorId, target: nativeKey, creating: false);

const vmAcpAccount = AcpAccountSettingsView(
  accountId: 'acp',
  name: 'Acp',
  provider: AcpProviderView.antigravity,
  connectionRevision: 1,
);
const vmAcpKey = AccountAcpKey(
  target: AccountDisplayKey(kind: AccountKind.acp, id: 'acp'),
  providerId: 'antigravity',
  connectionRevision: 1,
);
void publishVmAcp(
  AccountsVmHarness h,
  AcpAuthStateView auth, {
  AcpAccountSettingsView account = vmAcpAccount,
}) {
  h.accounts.state.publish(
    AccountsState(
      stamp: vmStamp,
      accounts: [
        vmSummary(const NativeAccountIdentity('native')),
        vmSummary(
          AcpAccountIdentity(account.accountId),
          acpRevision: account.connectionRevision,
        ),
      ],
      templates: h.accounts.state.value.templates,
    ),
  );
  h.accounts.put(AcpAccountDetails(account));
  h.acp.auth.publish(
    AccountResource(
      stamp: vmStamp,
      value: AcpAuthSnapshotView(
        revision: 1,
        updatedAt: 1,
        accounts: [
          AcpAuthAccountView(
            accountId: account.accountId,
            connectionRevision: account.connectionRevision,
            state: auth,
          ),
        ],
      ),
    ),
  );
}

void publishVmAcpReady(AccountsVmHarness h) {
  h.acp.install.publish(
    AccountResource(
      stamp: vmStamp,
      value: AcpInstallSnapshotView(
        revision: 1,
        updatedAt: 1,
        installations: [
          const AcpInstallEntryView(
            provider: AcpProviderView.antigravity,
            state: AcpInstallReadyState(
              operationId: 'prepared',
              server: AcpInstalledServerView(
                installationId: 'id',
                release: AcpInstallReleaseView(
                  version: '1.4.1',
                  target: 'linux-x86_64',
                  archiveUrl: 'https://example.test/archive',
                ),
                program: '/managed/program',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<AcpAccountViewModel> listenVmAcp(
  AccountsVmHarness h,
  AccountAcpKey key,
) async {
  final subscription = h.container.listen(
    acpAccountViewModelProvider(key),
    (_, _) {},
  );
  addTearDown(subscription.close);
  await h.container.read(acpAccountViewModelProvider(key).future);
  return h.container.read(acpAccountViewModelProvider(key).notifier);
}

DelegationModelDetail vmPerformance() => DelegationModelDetail(
  key: const DelegationModelKey(accountId: 'native', modelId: 'model'),
  accountName: 'Native',
  descriptor: const AccountModelView(
    modelId: 'model',
    displayName: 'Model',
    reasoningEfforts: [],
  ),
  available: true,
  billingKind: BillingKind.metered,
  performance: const LocalModelPerformanceSummary(
    sampleCount: 2,
    tokensPerSecond: 12.5,
    ttftSampleCount: 2,
  ),
  evaluations: const AgentEvaluationSummary(
    window: 12,
    ratedSamples: 11,
    passed: 6,
    failed: 5,
    notRated: 1,
  ),
  recentEvaluations: [
    for (var i = 0; i < 12; i++)
      AgentEvaluation(
        agentId: 'agent-$i',
        parentAgentId: 'parent',
        model: const NewThreadModelRoute(accountId: 'native', modelId: 'model'),
        profileId: 'profile',
        mode: DelegationMode.profile,
        preference: DelegationPreference.balanced,
        turnId: 'turn',
        revision: 1,
        taskCategory: AgentTaskCategory.coding,
        outcome: i == 11
            ? AgentEvaluationOutcome.notRated
            : i.isEven
            ? AgentEvaluationOutcome.passed
            : AgentEvaluationOutcome.failed,
        quality: i == 11 ? null : i % 5 + 1,
        instructionFollowing: i == 11 ? null : 5,
        comment: 'evaluation-$i',
        createdAt: i,
        updatedAt: i,
      ),
  ],
);

void main() {
  test('OpenAI subscription save requires the current editor login with direct permission', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final current = h.accounts.state.value;
    h.accounts.state.publish(
      AccountsState(
        stamp: current.stamp,
        accounts: current.accounts,
        templates: const AccountCatalogView(
          schemaVersion: 1,
          revision: 'openai-catalog',
          templates: [openaiTemplate],
          modelCatalogs: {},
        ),
      ),
    );
    const editorId = 'openai-editor';
    const key = AccountEditorKey(
      editorId: editorId,
      target: nativeKey,
      creating: true,
      template: AccountTemplateKey(kind: AccountKind.native, id: 'openai'),
    );
    final owner = await h.editor(key);
    owner.setStrings(
      const AccountStrings({
        'required': 'Required',
        'chatGptApiKeyRequired': 'A new API key is required',
      }),
    );
    owner.changeAuthentication(AccountAuthenticationMethod.chatGpt);
    expect(h.editorState(key).native!.canSave, isFalse);
    expect(h.editorState(key).native!.error, isNull);

    account_domain.ChatGptLoginSnapshot snapshot(
      String loginId,
      String editor,
      int revision,
      account_domain.ChatGptLoginPhase phase, {
      account_domain.ChatGptAccountInfo? account,
      String? authorizationUrl,
    }) => account_domain.ChatGptLoginSnapshot(
      loginId: loginId,
      editorId: editor,
      accountId: key.target.id,
      revision: revision,
      phase: phase,
      account: account,
      authorizationUrl: authorizationUrl,
    );
    h.accounts.loginStart = (loginId, receivedEditor, accountId) async {
      expect(accountId, key.target.id);
      expect(receivedEditor, editorId);
      expect(loginId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      // A same-login frame from an obsolete editor may not grant save rights.
      h.accounts.publishChatGptLogin(
        snapshot(
          loginId,
          'obsolete-editor',
          2,
          account_domain.ChatGptLoginPhase.succeeded,
          account: const account_domain.ChatGptAccountInfo(
            issuer: 'https://auth.openai.com',
            subject: 'obsolete',
            clientId: 'issued-client',
            planUsageEnabled: true,
          ),
        ),
      );
      expect(h.editorState(key).native!.canSave, isFalse);
      return snapshot(
        loginId,
        editorId,
        3,
        account_domain.ChatGptLoginPhase.awaitingBrowser,
        authorizationUrl: 'https://auth.openai.com/oauth/authorize?state=x',
      );
    };
    await owner.startChatGptLogin();
    expect(h.accounts.chatGptLoginTargets, hasLength(1));
    expect(h.accounts.chatGptLoginTargets.single.$2, editorId);
    expect(h.accounts.chatGptLoginCallOrder, ['register', 'start', 'observe']);
    expect(h.editorState(key).native!.canSave, isFalse);
    // Re-selecting the active method must preserve the in-flight login.
    owner.changeAuthentication(AccountAuthenticationMethod.chatGpt);
    expect(
      owner.claimAuthorizationUrlForAutomaticOpen(),
      'https://auth.openai.com/oauth/authorize?state=x',
    );
    expect(owner.claimAuthorizationUrlForAutomaticOpen(), isNull);

    final loginId = h.accounts.chatGptLoginTargets.single.$1;
    h.accounts.publishChatGptLogin(
      snapshot(
        loginId,
        editorId,
        4,
        account_domain.ChatGptLoginPhase.succeeded,
        account: const account_domain.ChatGptAccountInfo(
          issuer: 'https://auth.openai.com',
          subject: 'account-subject',
          clientId: 'issued-client',
          email: 'person@example.test',
          planUsageEnabled: true,
        ),
      ),
    );
    expect(h.editorState(key).native!.canSave, isTrue);
    expect(await owner.save(), isTrue);
    expect(h.accounts.creates, hasLength(1));
    final intent = h.accounts.creates.single.authentication;
    expect(intent, isA<SelectChatGptAuthentication>());
    expect((intent as SelectChatGptAuthentication).loginId, loginId);
    expect(intent.editorId, editorId);
    expect(
      h.accounts.creates.single.secret.action,
      AccountSecretAction.preserve,
    );
  });

  test(
    'discarding a pending ChatGPT login cancels and clears save intent',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      final current = h.accounts.state.value;
      h.accounts.state.publish(
        AccountsState(
          stamp: current.stamp,
          accounts: current.accounts,
          templates: const AccountCatalogView(
            schemaVersion: 1,
            revision: 'openai-catalog',
            templates: [openaiTemplate],
            modelCatalogs: {},
          ),
        ),
      );
      const editorId = 'discard-editor';
      const key = AccountEditorKey(
        editorId: editorId,
        target: nativeKey,
        creating: true,
        template: AccountTemplateKey(kind: AccountKind.native, id: 'openai'),
      );
      final owner = await h.editor(key);
      owner.changeAuthentication(AccountAuthenticationMethod.chatGpt);
      h.accounts.loginStart = (loginId, editor, accountId) async =>
          account_domain.ChatGptLoginSnapshot(
            loginId: loginId,
            editorId: editor,
            accountId: accountId,
            revision: 2,
            phase: account_domain.ChatGptLoginPhase.awaitingBrowser,
          );
      h.accounts.loginCancel = (loginId, editor, accountId) async =>
          account_domain.ChatGptLoginSnapshot(
            loginId: loginId,
            editorId: editor,
            accountId: accountId,
            revision: 3,
            phase: account_domain.ChatGptLoginPhase.cancelled,
          );
      await owner.startChatGptLogin();
      expect(h.editorState(key).native!.canSave, isFalse);
      expect(await owner.requestLeave(AccountLeaveChoice.discard), isTrue);
      expect(h.editorState(key).native!.chatGptLogin, isNull);
      expect(h.accounts.chatGptLoginDemands.single.releases, 1);
    },
  );

  test('compact typing and presets stay drafts until explicit Save, preserving exact positive intent', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final owner = await h.modelOwner();
    AccountCompactPresentation current() => h.container
        .read(accountModelsViewModelProvider(nativeKey))
        .requireValue
        .catalog
        .models
        .single
        .compact!;
    void editWithoutTimer(void Function() edit) {
      final timers = <Duration>[];
      runZoned(
        edit,
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            timers.add(duration);
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
      // The contract forbids scheduling submission, not merely a write before
      // the next frame. Catch the former debounce without a wall-clock sleep.
      expect(timers, isEmpty);
    }

    editWithoutTimer(() => owner.changeCompact('model', '9999999'));
    expect(h.models.compactCalls, isEmpty);
    expect(
      (current().raw, current().dirty, current().canSave),
      ('9999999', true, true),
    );
    await owner.saveCompact('model');
    expect(
      h.models.compactCalls.single.$1,
      const AccountModelIdentity(
        account: NativeAccountIdentity('native'),
        modelId: 'model',
      ),
    );
    expect(
      (h.models.compactCalls.single.$2 as SetAutoCompactLimit).limit,
      9999999,
    );
    expect(current().dirty, isFalse);
    editWithoutTimer(() => owner.presetCompact('model', 25));
    expect(current().raw, '500');
    expect(h.models.compactCalls, hasLength(1));
    owner.changeCompact('model', '1.5');
    await owner.saveCompact('model');
    expect((current().raw, current().canSave), ('1.5', false));
    expect(h.models.compactCalls, hasLength(1));
  });

  test('compact leave freezes revisions and blocks failed or unknown saves without replay', () async {
    final board = MutationBoard(clientId: 'compact-leave');
    final newerObservations = <OperationId, LatestValue<OperationState>>{};
    final h = AccountsVmHarness(
      operationLookup: (id) => newerObservations[id] ?? board.lookup(id)?.state,
    );
    addTearDown(h.dispose);
    final owner = await h.modelOwner();
    owner.changeCompact('model', '1200');
    expect(await owner.requestLeaveCompact(AccountLeaveChoice.cancel), isFalse);
    final completing = Completer<OperationState>();
    h.models.compactWrite = () => completing.future;
    final leaving = owner.requestLeaveCompact(AccountLeaveChoice.save);
    expect(owner.compactLeaveBlocked(), isTrue);
    final frozenRevision = h.models.compactDrafts.single!.revision;
    await owner.saveCompact('model');
    await owner.resetCompact('model');
    await owner.retryCompact('model');
    expect(
      await owner.requestLeaveCompact(AccountLeaveChoice.discard),
      isFalse,
    );
    expect(h.models.compactCalls, hasLength(1));
    owner.changeCompact('model', '1300');
    completing.complete(savedVmOperation());
    expect(await leaving, isFalse);
    expect(owner.compactLeaveBlocked(), isFalse);
    expect(owner.hasCompactDrafts(), isTrue);
    // Before-admission exceptions remain throws; this is not dispatch loss.
    h.models.compactWrite = () => Future.error(StateError('before admission'));
    expect(await owner.requestLeaveCompact(AccountLeaveChoice.save), isFalse);
    expect(h.models.compactDrafts.last!.revision, greaterThan(frozenRevision));
    owner.setStrings(
      const AccountStrings({
        'unconfirmedDiscard': 'May still change canonical settings',
      }),
    );
    for (final phase in [
      OperationPhase.unknownOutcome,
      OperationPhase.syncFailed,
    ]) {
      for (final clearing in [false, true]) {
        owner.changeCompact('model', '1350');
        final operation = board.begin(target: 'compact');
        if (phase == OperationPhase.unknownOutcome) {
          operation.unknownOutcome(StateError('unobserved'));
        } else {
          operation.accept(
            CommitReceipt(
              operationId: operation.id,
              disposition: CommitDisposition.applied,
              targets: const [vmStamp],
              effect: EffectPoint.immediate,
              durable: true,
            ),
          );
          operation.syncFailed(StateError('observation failed'));
        }
        // A later board value cannot upgrade the one-shot result's frozen failure.
        newerObservations[operation.id] = LatestValue(
          savedVmOperation(operation.id.value),
        );
        final response = Completer<OperationState>();
        h.models.compactWrite = () => response.future;
        final saving = clearing
            ? owner.resetCompact('model')
            : owner.saveCompact('model');
        expect(owner.compactLeaveBlocked(), isTrue);
        if (!clearing) owner.changeCompact('model', '1375');
        response.complete(operation.state.value);
        await saving;
        expect(owner.compactLeaveBlocked(), isFalse);
        expect(owner.hasUnconfirmedCompactSave(), isTrue);
        // The Router contract checks the production dialog's localized warning.
        final compact = h.container
            .read(accountModelsViewModelProvider(nativeKey))
            .requireValue
            .catalog
            .models
            .single
            .compact!;
        expect(
          (
            compact.raw,
            compact.dirty,
            compact.canSave,
            compact.canReset,
            compact.canRetry,
          ),
          (clearing ? '' : '1375', true, false, false, false),
        );
        if (clearing) {
          expect(h.models.compactCalls.last.$2, isA<ClearAutoCompactLimit>());
        } else {
          expect(
            (h.models.compactCalls.last.$2 as SetAutoCompactLimit).limit,
            1350,
          );
        }
        final calls = h.models.compactCalls.length;
        owner.changeCompact('model', '1400');
        expect(owner.hasUnconfirmedCompactSave(), isTrue);
        await owner.saveCompact('model');
        await owner.resetCompact('model');
        await owner.retryCompact('model');
        expect(
          await owner.requestLeaveCompact(AccountLeaveChoice.save),
          isFalse,
        );
        expect(
          await owner.requestLeaveCompact(AccountLeaveChoice.cancel),
          isFalse,
        );
        expect(h.models.compactCalls, hasLength(calls));
        expect(
          h.container
              .read(accountModelsViewModelProvider(nativeKey))
              .requireValue
              .catalog
              .models
              .single
              .compact!
              .raw,
          '1400',
        );
        expect(
          await owner.requestLeaveCompact(AccountLeaveChoice.discard),
          isTrue,
        );
        expect(owner.hasCompactDrafts(), isTrue);
        expect(owner.hasUnconfirmedCompactSave(), isTrue);
        expect(owner.discardCompactDrafts(owner.compactLeaveToken()), isTrue);
        expect(owner.hasCompactDrafts(), isFalse);
        expect(owner.hasUnconfirmedCompactSave(), isFalse);
        // Discard retires only the local draft, not the admitted domain operation.
        expect(board.lookup(operation.id), same(operation));
        expect(operation.state.value.failurePhase, phase);
        expect(operation.state.value.isPending, isTrue);
        expect(h.models.compactCalls, hasLength(calls));
      }
    }
  });

  test('rejected compact CLEAR stays a clear draft for leave Save and explicit retry', () async {
    final board = MutationBoard(clientId: 'compact-clear');
    final h = AccountsVmHarness(
      operationLookup: (id) => board.lookup(id)?.state,
    );
    addTearDown(h.dispose);
    final owner = await h.modelOwner();
    for (final leaveSave in [true, false]) {
      final rejected = board.begin(target: 'compact-clear');
      rejected.reject(StateError('rejected clear'));
      h.models.compactWrite = () async => rejected.state.value;
      await owner.resetCompact('model');
      expect(owner.hasCompactDrafts(), isTrue);
      expect(owner.compactLeaveBlocked(), isFalse);
      expect(owner.hasUnconfirmedCompactSave(), isFalse);
      final compact = h.container
          .read(accountModelsViewModelProvider(nativeKey))
          .requireValue
          .catalog
          .models
          .single
          .compact!;
      expect(
        (compact.raw, compact.canRetry, compact.canSave),
        ('', true, true),
      );
      h.models.compactWrite = () async => savedVmOperation();
      if (leaveSave) {
        expect(
          await owner.requestLeaveCompact(AccountLeaveChoice.save),
          isTrue,
        );
      } else {
        await owner.retryCompact('model');
      }
      expect(owner.hasCompactDrafts(), isFalse);
    }
    expect(h.models.compactCalls, hasLength(4));
    expect(
      h.models.compactCalls.every((call) => call.$2 is ClearAutoCompactLimit),
      isTrue,
    );
  });

  test(
    'account scopes retain one compact owner and discard only on actual commit',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      final accountsOwner = await h.listOwner();
      final models = await h.modelOwner();
      final releaseDetails = models.retainAccountScope();
      final releaseModel = models.retainAccountScope();
      accountsOwner.search('saved query');
      models.changeCompact('model', '1250');
      final token = models.compactLeaveToken();
      releaseModel();
      releaseModel(); // A disposed child cannot release its parent's retention.
      expect(
        h.container.read(accountsViewModelProvider).requireValue.list.search,
        'saved query',
      );
      expect(models.matchesCompactLeaveToken(token), isTrue);
      expect(models.hasCompactDrafts(), isTrue);
      expect(h.models.compactCalls, isEmpty);
      expect(
        await models.requestLeaveCompact(AccountLeaveChoice.discard),
        isTrue,
      );
      expect(models.hasCompactDrafts(), isTrue);
      models.changeCompact('model', '1300');
      expect(models.discardCompactDrafts(token), isFalse);
      expect(models.hasCompactDrafts(), isTrue);
      expect(models.discardCompactDrafts(models.compactLeaveToken()), isTrue);
      expect(models.hasCompactDrafts(), isFalse);
      releaseDetails();
    },
  );

  test('catalog refresh and temporary stale frames preserve compact ownership and the actual save await', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final owner = await h.modelOwner();
    const identity = NativeAccountIdentity('native');
    final baseline = h.models.state.value;
    final descriptors = baseline.accounts[identity]!.value!.models;
    void publish(int generation, {bool stale = false, bool removed = false}) {
      h.models.state.publish(
        ModelDirectoryState(
          accounts: {
            identity: AccountResource(
              stamp: ResourceStamp(
                resourceKey: 'catalog',
                ownerEpoch: 'owner',
                revision: generation,
              ),
              stale: stale,
              value: AccountModelCatalog(
                identity: identity,
                models: removed ? const [] : descriptors,
                status: ModelCatalogStatusView(
                  supported: true,
                  queryGeneration: generation,
                ),
              ),
            ),
          },
          configurations: baseline.configurations,
        ),
      );
    }

    AccountCompactPresentation compact() => h.container
        .read(accountModelsViewModelProvider(nativeKey))
        .requireValue
        .catalog
        .models
        .single
        .compact!;
    owner.changeCompact('model', '1200');
    final token = owner.compactLeaveToken();
    final work = Completer<OperationState>();
    h.models.compactWrite = () => work.future;
    final saving = owner.saveCompact('model');
    publish(2);
    expect(owner.matchesCompactLeaveToken(token), isTrue);
    expect(
      (compact().raw, compact().saving, owner.compactLeaveBlocked()),
      ('1200', true, true),
    );
    expect(
      await owner.requestLeaveCompact(AccountLeaveChoice.discard),
      isFalse,
    );
    work.complete(savedVmOperation());
    await saving;
    expect(owner.hasCompactDrafts(), isFalse);
    owner.changeCompact('model', '1300');
    final nextToken = owner.compactLeaveToken();
    publish(3, stale: true);
    expect((compact().raw, compact().canSave), ('1300', false));
    await owner.saveCompact('model');
    expect(h.models.compactCalls, hasLength(1));
    publish(4);
    expect(owner.matchesCompactLeaveToken(nextToken), isTrue);
    expect((compact().raw, compact().canSave), ('1300', true));
    publish(5, removed: true);
    expect(owner.hasCompactDrafts(), isTrue);
    expect(owner.canSaveCompactDrafts(), isFalse);
    expect(await owner.requestLeaveCompact(AccountLeaveChoice.save), isFalse);
    expect(await owner.requestLeaveCompact(AccountLeaveChoice.discard), isTrue);
    expect(h.models.compactCalls, hasLength(1));
  });

  test('leaving multiple compact drafts keeps real partial success and newer edits without a transaction', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    const identity = NativeAccountIdentity('native');
    final baseline = h.models.state.value;
    h.models.state.publish(
      ModelDirectoryState(
        accounts: {
          identity: AccountResource(
            stamp: vmStamp,
            value: AccountModelCatalog(
              identity: identity,
              models: [
                baseline.accounts[identity]!.value!.models.single,
                const AccountModelView(
                  modelId: 'other',
                  displayName: 'Other',
                  reasoningEfforts: [],
                ),
              ],
              status: const ModelCatalogStatusView(supported: true),
            ),
          ),
        },
        configurations: baseline.configurations,
      ),
    );
    final owner = await h.modelOwner();
    owner.changeCompact('model', '1200');
    owner.changeCompact('other', '600');
    final secondEntered = Completer<void>();
    final second = Completer<OperationState>();
    h.models.compactWrite = () {
      if (h.models.compactCalls.length == 1) {
        return Future.value(savedVmOperation('first'));
      }
      secondEntered.complete();
      return second.future;
    };
    final leaving = owner.requestLeaveCompact(AccountLeaveChoice.save);
    await secondEntered.future;
    second.complete(
      failedVmOperation(
        OperationPhase.rejected,
        id: 'second-model-rejected',
        error: const StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message: 'Second model rejected',
          retryable: false,
          correlationId: 'second-model',
        ),
      ),
    );
    expect(await leaving, isFalse);
    Map<String, AccountCompactPresentation> drafts() => {
      for (final model
          in h.container
              .read(accountModelsViewModelProvider(nativeKey))
              .requireValue
              .catalog
              .models)
        model.key.modelId: model.compact!,
    };
    expect(
      (
        drafts()['model']!.dirty,
        drafts()['other']!.raw,
        drafts()['other']!.dirty,
      ),
      (false, '600', true),
    );
    expect(h.models.compactCalls.map((call) => call.$1.modelId), [
      'model',
      'other',
    ]);
    final retry = Completer<OperationState>();
    h.models.compactWrite = () => retry.future;
    final retrying = owner.requestLeaveCompact(AccountLeaveChoice.save);
    owner.changeCompact('model', '1500');
    retry.complete(savedVmOperation('second'));
    expect(await retrying, isFalse);
    expect(
      (
        drafts()['model']!.raw,
        drafts()['model']!.dirty,
        drafts()['other']!.dirty,
      ),
      ('1500', true, false),
    );
    expect(h.models.compactCalls.map((call) => call.$1.modelId), [
      'model',
      'other',
      'other',
    ]);
  });
  test('account removal confirms the same operation and canonical absence in either order', () async {
    for (final absenceFirst in [true, false]) {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      final accounts = await h.listOwner();
      final models = await h.modelOwner();
      final modelsProvider = accountModelsViewModelProvider(nativeKey);
      final token = models.compactLeaveToken();
      var cleanChecks = 0;
      final completion = Completer<OperationState>();
      h.accounts.write = () => completion.future;
      bool? outcome;
      final removing = accounts.remove(
        nativeKey,
        isCompactClean: () {
          cleanChecks++;
          return h.container.exists(modelsProvider) &&
              identical(h.container.read(modelsProvider.notifier), models) &&
              models.canRemove(expectedToken: token);
        },
      );
      final observedCompletion = removing.then((value) => outcome = value);
      expect(cleanChecks, 1);
      expect(h.accounts.removals, [const NativeAccountIdentity('native')]);
      expect(accounts.isRemovalBlocked(nativeKey), isTrue);
      final saved = savedVmOperation(
        absenceFirst ? 'absence-before-saved' : 'saved-before-absence',
      );
      void publishAbsence() {
        h.accounts.state.publish(
          AccountsState(
            stamp: const ResourceStamp(
              resourceKey: 'test',
              ownerEpoch: 'owner',
              revision: 2,
            ),
            accounts: const [],
            templates: h.accounts.state.value.templates,
          ),
        );
      }

      if (absenceFirst) {
        publishAbsence();
      } else {
        completion.complete(saved);
      }
      await h.container.pump();
      expect(outcome, isNull, reason: 'One deletion fact is not success.');
      expect(accounts.isRemovalBlocked(nativeKey), isTrue);
      expect(cleanChecks, 1);
      if (absenceFirst) {
        completion.complete(saved);
      } else {
        publishAbsence();
      }
      expect(await removing, isTrue);
      await observedCompletion;
      expect(outcome, isTrue);
      expect(accounts.isRemovalBlocked(nativeKey), isFalse);
      expect(
        h.accounts.state.value.account(const NativeAccountIdentity('native')),
        isNull,
      );
      expect(h.accounts.removals, hasLength(1));
      expect(cleanChecks, 1);
      expect(h.accounts.creates, isEmpty);
      expect(h.accounts.patches, isEmpty);
    }
  });

  test(
    'Native details distinguish ChatGPT readiness from API key presence',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      void publishReadiness(bool ready) => h.accounts.state.publish(
        AccountsState(
          stamp: vmStamp,
          accounts: [
            vmSummary(
              const NativeAccountIdentity('native'),
              credentialReady: ready,
            ),
          ],
        ),
      );
      publishReadiness(true);
      h.accounts.put(
        vmNative(
          hasBearerToken: false,
          authentication: account_domain.AccountAuthenticationMethod.chatGpt,
        ),
      );
      await h.details(nativeKey);
      NativeAccountDetailsPresentation current() =>
          (h.container
                      .read(accountDetailsViewModelProvider(nativeKey))
                      .requireValue
                      .details
                      .content
                  as NativeAccountDetailsContent)
              .value;
      expect(current().authentication, AccountAuthenticationMethod.chatGpt);
      expect(current().credentialReady, isTrue);

      publishReadiness(false);
      await h.container.pump();
      expect(current().authentication, AccountAuthenticationMethod.chatGpt);
      expect(current().credentialReady, isFalse);

      h.accounts.put(vmNative());
      await h.container.pump();
      expect(current().authentication, AccountAuthenticationMethod.apiKey);
      expect(current().credentialReady, isTrue);
    },
  );
  test('current Native detail observes default and delete failures outside the filtered list', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final accountsOwner = await h.listOwner();
    accountsOwner.setStrings(vmOperationStrings);
    accountsOwner.search('not-a-visible-row');
    final owner = await h.details(nativeKey);
    final provider = accountDetailsViewModelProvider(nativeKey);
    AccountDetailsPresentation current() =>
        h.container.read(provider).requireValue.details;
    for (final command in <Future<bool> Function(AccountDisplayKey)>[
      accountsOwner.setDefault,
      (key) => accountsOwner.remove(key, isCompactClean: () => true),
    ]) {
      final work = Completer<OperationState>();
      h.accounts.write = () => work.future;
      final saving = command(nativeKey);
      expect(current().loading, isTrue);
      expect(
        (current().canEdit, current().canSetDefault, current().canDelete),
        (false, false, false),
      );
      // An explicit owner rejection is correctable; both header actions stay available.
      work.complete(
        failedVmOperation(
          OperationPhase.rejected,
          id: 'header-${h.accounts.defaultCalls.length}-${h.accounts.removals.length}',
          error: const StudioFailure(
            code: StudioFailureCode.invalidArgument,
            message: 'Header command rejected',
            retryable: false,
            correlationId: 'header',
          ),
        ),
      );
      expect(await saving, isFalse);
      expect(current().error, 'Save failed');
      expect(current().loading, isFalse);
      expect(current().canDelete, isTrue);
      expect(owner.presentation().error, 'Save failed');
      final content = current().content as NativeAccountDetailsContent;
      expect(content.value.usage.phase, AccountQueryPhase.idle);
      expect(content.value.billing.error, isNull);
    }
    expect(h.accounts.defaultCalls, [const NativeAccountIdentity('native')]);
    expect(h.accounts.removals, [const NativeAccountIdentity('native')]);
    expect(
      h.container.read(accountsViewModelProvider).requireValue.list.rows,
      isEmpty,
    );
  });
  test(
    'current ACP detail keeps deletion feedback independent of Verified auth',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      publishVmAcp(h, const AcpVerifiedState(checkedAt: 1, server: null));
      final accountsOwner = await h.listOwner();
      accountsOwner.setStrings(vmOperationStrings);
      accountsOwner.search('not-a-visible-row');
      final owner = await h.details(vmAcpKey.target);
      await listenVmAcp(h, vmAcpKey);
      final provider = accountDetailsViewModelProvider(vmAcpKey.target);
      final work = Completer<OperationState>();
      h.acp.removeWrite = () => work.future;
      final deleting = accountsOwner.remove(
        vmAcpKey.target,
        isCompactClean: () => true,
      );
      expect(h.container.read(provider).requireValue.details.loading, isTrue);
      work.complete(
        failedVmOperation(
          OperationPhase.unknownOutcome,
          id: 'acp-delete-unknown',
          error: const StudioFailure(
            code: StudioFailureCode.unavailable,
            message: 'ACP delete failed',
            retryable: true,
            correlationId: 'delete',
          ),
        ),
      );
      expect(await deleting, isFalse);
      expect(
        h.container.read(provider).requireValue.details.error,
        'Outcome unknown',
      );
      final active = owner.presentation(
        acp: h.container
            .read(acpAccountViewModelProvider(vmAcpKey))
            .requireValue
            .panel,
      );
      expect(active.error, 'Outcome unknown');
      expect(active.loading, isTrue);
      expect(
        await accountsOwner.remove(vmAcpKey.target, isCompactClean: () => true),
        isFalse,
      );
      expect(h.acp.removals, hasLength(1));
      expect(
        (active.content as AcpAccountDetailsContent).value.phase,
        AcpPresentationPhase.connected,
      );
    },
  );
  test('current detail follows submitting, awaiting and unknown outcomes from the admitted operation', () async {
    final board = MutationBoard(clientId: 'detail');
    final h = AccountsVmHarness(
      operationLookup: (id) => board.lookup(id)?.state,
    );
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final accountsOwner = await h.listOwner();
    accountsOwner.setStrings(
      const AccountStrings({
        'awaitingObservation': 'Waiting for observation',
        'unknownOutcome': 'Outcome unknown',
      }),
    );
    accountsOwner.search('not-a-visible-row');
    await h.details(nativeKey);
    final provider = accountDetailsViewModelProvider(nativeKey);
    AccountDetailsPresentation current() =>
        h.container.read(provider).requireValue.details;
    final operation = board.begin(target: 'native-default');
    h.accounts.write = () async => operation.state.value;
    expect(await accountsOwner.setDefault(nativeKey), isFalse);
    expect(
      (current().loading, current().error, current().canSetDefault),
      (true, 'Waiting for observation', false),
    );
    const observed = ResourceStamp(
      resourceKey: 'native-detail',
      ownerEpoch: 'owner',
      revision: 2,
    );
    final receipt = CommitReceipt(
      operationId: operation.id,
      disposition: CommitDisposition.applied,
      targets: const [observed],
      effect: EffectPoint.immediate,
      durable: true,
    );
    operation.accept(receipt);
    expect(current().error, 'Waiting for observation');
    operation.unknownOutcome(StateError('transport'));
    expect(
      (current().loading, current().error, current().canSetDefault),
      (true, 'Outcome unknown', false),
    );
    expect(await accountsOwner.setDefault(nativeKey), isFalse);
    expect(h.accounts.defaultCalls, hasLength(1));
    // Only new authoritative evidence for this admitted id clears uncertainty.
    operation.accept(receipt);
    board.observe(observed);
    expect(
      (current().loading, current().error, current().canSetDefault),
      (false, null, true),
    );
    expect(h.accounts.defaultCalls, hasLength(1));
  });
  test('current typed detail retains account deletion responsibility across ACP connection revisions', () async {
    final board = MutationBoard(clientId: 'typed-detail-delete');
    final h = AccountsVmHarness(
      operationLookup: (id) => board.lookup(id)?.state,
    );
    addTearDown(h.dispose);
    const native = AccountDisplayKey(kind: AccountKind.native, id: 'shared');
    const acp = AccountDisplayKey(kind: AccountKind.acp, id: 'shared');
    void summaries(int revision) => h.accounts.state.publish(
      AccountsState(
        stamp: vmStamp,
        accounts: [
          vmSummary(const NativeAccountIdentity('shared')),
          vmSummary(const AcpAccountIdentity('shared'), acpRevision: revision),
        ],
      ),
    );
    void details(int revision) => h.accounts.put(
      AcpAccountDetails(
        AcpAccountSettingsView(
          accountId: 'shared',
          name: 'Acp',
          provider: AcpProviderView.antigravity,
          connectionRevision: revision,
        ),
      ),
    );
    summaries(1);
    details(1);
    h.accounts.put(vmNative(id: 'shared'));
    final accountsOwner = await h.listOwner();
    accountsOwner.setStrings(vmOperationStrings);
    accountsOwner.search('not-a-visible-row');
    expect(
      h.container.read(accountsViewModelProvider).requireValue.list.rows,
      isEmpty,
    );
    await h.details(acp);
    await h.details(native);
    final provider = accountDetailsViewModelProvider(acp);
    AccountDetailsPresentation current() =>
        h.container.read(provider).requireValue.details;
    final completing = Completer<OperationState>();
    h.acp.removeWrite = () => completing.future;
    final first = accountsOwner.remove(acp, isCompactClean: () => true);
    expect(accountsOwner.isRemovalBlocked(acp), isTrue);
    expect(accountsOwner.isRemovalBlocked(native), isFalse);
    h.accounts.write = () async => failedVmOperation(
      OperationPhase.unknownOutcome,
      id: 'native-only-unknown',
      error: const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Native only',
        retryable: true,
        correlationId: 'native',
      ),
    );
    await accountsOwner.setDefault(native);
    expect(
      h.container
          .read(accountDetailsViewModelProvider(native))
          .requireValue
          .details
          .error,
      'Outcome unknown',
    );
    expect((current().loading, current().error), (true, null));
    expect(current().canDelete, isFalse);
    summaries(2);
    expect(
      await accountsOwner.remove(acp, isCompactClean: () => true),
      isFalse,
    );
    expect(h.acp.removals, hasLength(1));
    expect(accountsOwner.isRemovalBlocked(acp), isTrue);
    // Retained old detail is not yet the newly observed connection.
    expect((current().loading, current().error), (false, null));
    details(2);
    // Once current typed detail arrives, the same account's deletion still owns
    // its pending feedback; a connection revision did not create a new owner.
    expect(
      (current().loading, current().error, current().canDelete),
      (true, null, false),
    );
    final operation = board.begin(target: 'typed-acp-account-delete');
    operation.accept(
      CommitReceipt(
        operationId: operation.id,
        disposition: CommitDisposition.applied,
        targets: const [vmStamp],
        effect: EffectPoint.immediate,
        durable: true,
      ),
    );
    operation.syncFailed(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Account deletion observation failed',
        retryable: true,
        correlationId: 'delete',
      ),
    );
    completing.complete(operation.state.value);
    expect(await first, isFalse);
    expect(
      (current().loading, current().error, current().canDelete),
      (true, 'Save failed', false),
    );
    expect(board.lookup(operation.id), same(operation));
    expect(operation.state.value.failurePhase, OperationPhase.syncFailed);
    expect(accountsOwner.isRemovalBlocked(acp), isTrue);
    summaries(3);
    details(3);
    expect(
      (current().loading, current().error, current().canDelete),
      (true, 'Save failed', false),
    );
    expect(
      await accountsOwner.remove(acp, isCompactClean: () => true),
      isFalse,
    );
    expect(h.acp.removals, hasLength(1));
    expect(accountsOwner.isRemovalBlocked(native), isFalse);
    expect(
      h.container
          .read(accountDetailsViewModelProvider(native))
          .requireValue
          .details
          .error,
      'Outcome unknown',
    );
    expect(h.accounts.defaultCalls, hasLength(1));
  });
  test('current detail action ownership does not revive after owner epoch A to B to A', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final accountsOwner = await h.listOwner();
    accountsOwner.setStrings(vmOperationStrings);
    accountsOwner.search('not-a-visible-row');
    await h.details(nativeKey);
    final provider = accountDetailsViewModelProvider(nativeKey);
    AccountDetailsPresentation current() =>
        h.container.read(provider).requireValue.details;
    void publish(String epoch, {bool stale = false}) =>
        h.accounts.state.publish(
          AccountsState(
            stamp: ResourceStamp(
              resourceKey: 'test',
              ownerEpoch: epoch,
              revision: 1,
            ),
            accounts: [vmSummary(const NativeAccountIdentity('native'))],
            stale: stale,
          ),
        );
    final old = Completer<OperationState>();
    h.accounts.write = () => old.future;
    final first = accountsOwner.setDefault(nativeKey);
    publish('owner', stale: true);
    publish('replacement');
    publish('replacement', stale: true);
    publish('owner');
    final next = Completer<OperationState>();
    h.accounts.write = () => next.future;
    final second = accountsOwner.setDefault(nativeKey);
    old.complete(savedVmOperation('old-lifecycle'));
    expect(await first, isFalse);
    expect((current().loading, current().error), (true, null));
    next.complete(
      failedVmOperation(
        OperationPhase.unknownOutcome,
        id: 'current-owner-default',
        error: const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Current owner failed',
          retryable: true,
          correlationId: 'current',
        ),
      ),
    );
    expect(await second, isFalse);
    expect(current().error, 'Outcome unknown');
    expect(current().loading, isTrue);
    expect(await accountsOwner.setDefault(nativeKey), isFalse);
    expect(h.accounts.defaultCalls, hasLength(2));
  });
  test('editor declarations omit compact data while the real details model remains editable', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    const identity = NativeAccountIdentity('native');
    final baseline = h.models.state.value;
    void publishDescriptor(AccountModelView descriptor) {
      h.models.state.publish(
        ModelDirectoryState(
          accounts: {
            identity: AccountResource(
              stamp: vmStamp,
              value: AccountModelCatalog(
                identity: identity,
                models: [descriptor],
                status: const ModelCatalogStatusView(supported: true),
              ),
            ),
          },
          configurations: baseline.configurations,
        ),
      );
    }

    publishDescriptor(
      baseline.accounts[identity]!.value!.models.single.copyWith(
        reasoningEfforts: const ['low', 'high'],
        inputCapabilities: const [
          ModelInputCapabilityView(
            modality: ModelModalityView.image,
            sources: [
              ModelInputSourceView.local,
              ModelInputSourceView.remoteUrl,
            ],
          ),
        ],
        capabilities: const ['function_calling'],
        maxContextWindow: 4000,
        context: const ModelContextView(
          unavailable: null,
          contextWindow: 2000,
          inputTokenLimit: 1500,
          autoCompactLimit: 1000,
        ),
        wireApi: 'responses',
        supportedConnectionModes: const ['http', 'web_socket'],
      ),
    );
    h.accounts.put(vmNative());
    final editor = await h.editor(editKey());
    final models = await h.modelOwner();
    final detailsProvider = accountDetailsViewModelProvider(nativeKey);
    final subscription = h.container.listen(detailsProvider, (_, _) {});
    addTearDown(subscription.close);
    await h.container.read(detailsProvider.future);
    models.changeCompact('model', '1.5');
    final catalog = h.container
        .read(accountModelsViewModelProvider(nativeKey))
        .requireValue
        .catalog;
    expect(catalog.models.single.origin, AccountModelOrigin.bundled);
    expect(catalog.models.single.connection, AccountConnection.automatic);
    expect(catalog.models.single.allowedConnections, [
      AccountConnection.automatic,
      AccountConnection.http,
      AccountConnection.webSocket,
    ]);
    final edited = editor.presentation(catalog: catalog).native!;
    expect(edited.declaredModels, isNotEmpty);
    expect(
      edited.declaredModels.every((model) => model.compact == null),
      isTrue,
    );
    expect(
      edited.declaredModels.single.connection,
      catalog.models.single.connection,
    );
    expect(
      edited.declaredModels.single.allowedConnections,
      catalog.models.single.allowedConnections,
    );
    final details = h.container
        .read(detailsProvider.notifier)
        .presentation(catalog: catalog);
    final compact = (details.content as NativeAccountDetailsContent)
        .value
        .catalog
        .models
        .single
        .compact!;
    expect((compact.raw, compact.canEdit), ('1.5', true));
    await models.resetCompact('model');
    expect(h.models.compactCalls.single.$2, isA<ClearAutoCompactLimit>());
    for (final (l10n, modalitiesLabel) in [
      (AppLocalizationsEn(), 'Output modalities'),
      (AppLocalizationsZh(), '输出模态'),
    ]) {
      models.setStrings(accountStrings(l10n));
      final strings = accountStrings(l10n);
      final facts = h.container
          .read(accountModelsViewModelProvider(nativeKey))
          .requireValue
          .catalog
          .models
          .single
          .specificationFacts;
      expect(facts.modalityCapabilities, [
        AccountDisplayFact(label: strings['efforts'], value: 'low / high'),
        AccountDisplayFact(
          label: '${strings['capability']} · image',
          value: 'local / remoteUrl',
        ),
        AccountDisplayFact(label: modalitiesLabel, value: 'text'),
        AccountDisplayFact(
          label: strings['capability'],
          value: 'function_calling',
        ),
      ]);
      expect(facts.context, [
        AccountDisplayFact(label: strings['context'], value: '2000'),
        AccountDisplayFact(label: strings['maxContext'], value: '4000'),
        AccountDisplayFact(label: strings['inputBudget'], value: '1500'),
        AccountDisplayFact(label: l10n.settingsOutputBudget, value: '4096'),
      ]);
      expect(facts.connection, [
        AccountDisplayFact(label: strings['modelId'], value: 'model'),
        AccountDisplayFact(label: strings['protocol'], value: 'responses'),
      ]);
      // Complete ordered groups also reject accidental copies across groups.
      final allFacts = [
        ...facts.modalityCapabilities,
        ...facts.context,
        ...facts.connection,
      ];
      expect(allFacts, hasLength(10));
      expect(allFacts.toSet(), hasLength(10));
    }
    for (final unavailable in [ModelContextUnavailable.windowUnknown, null]) {
      publishDescriptor(
        AccountModelView(
          modelId: 'model',
          displayName: 'Model',
          reasoningEfforts: const [],
          context: ModelContextView(unavailable: unavailable),
        ),
      );
      final projected = h.container
          .read(accountModelsViewModelProvider(nativeKey))
          .requireValue
          .catalog
          .models
          .single;
      final facts = projected.specificationFacts;
      final strings = accountStrings(AppLocalizationsZh());
      expect(facts.modalityCapabilities, isEmpty);
      expect(
        facts.context,
        unavailable == null
            ? <AccountDisplayFact>[]
            : [
                AccountDisplayFact(
                  label: strings['context'],
                  value: strings['contextUnavailable.windowUnknown'],
                ),
              ],
      );
      expect(facts.connection, [
        AccountDisplayFact(label: strings['modelId'], value: 'model'),
        AccountDisplayFact(
          label: strings['protocol'],
          value: 'chat_completions',
        ),
      ]);
      expect(projected.origin, AccountModelOrigin.bundled);
      expect(projected.connection, AccountConnection.automatic);
      expect(projected.allowedConnections, [
        AccountConnection.automatic,
        AccountConnection.http,
      ]);
      expect(
        (
          projected.compact!.raw,
          projected.compact!.effective,
          projected.compact!.contextWindow,
        ),
        ('', null, null),
      );
      expect(projected.priceTiers, isEmpty);
      expect(projected.performance, isNull);
      expect(projected.evaluations, isEmpty);
    }
    expect(h.models.compactCalls, hasLength(1));
  });
  test('a display demand failure after create preserves durable baseline and saved manual identity', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final session = await h.session(
      const AccountEditorEntryKey.creating(routeEntryId: 'create'),
    );
    final key = session.currentEditor!;
    final owner = await h.editor(key);
    owner.addModel();
    final row = h.editorState(key).native!.manualModels.single.editorKey;
    owner.changeModel(row, field: ManualModelField.id, raw: 'saved-model');
    owner.changeModel(row, connection: AccountConnection.http);
    h.accounts.detailFailure = StateError('display budget');
    expect(await owner.save(), isFalse);
    expect(h.editorState(key).dirty, isFalse);
    expect(owner.isSavedModel(row), isTrue);
    expect(h.editorState(key).native!.manualModels.single.canEditId, isFalse);
    expect(await owner.save(), isFalse);
    expect(h.accounts.creates, hasLength(1));
    expect(h.accounts.patches, isEmpty);
  });
  test('Native and ACP rows with the same bare id keep operation errors and pending separate', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    const native = AccountDisplayKey(kind: AccountKind.native, id: 'shared');
    const acp = AccountDisplayKey(kind: AccountKind.acp, id: 'shared');
    const accountName = 'https://name-hint.example/private';
    const displayEndpoint = 'https://display.example:8443';
    h.accounts.put(vmNative(id: 'shared'));
    h.accounts.state.publish(
      AccountsState(
        stamp: vmStamp,
        templates: h.accounts.state.value.templates,
        accounts: [
          vmSummary(
            const NativeAccountIdentity('shared'),
            name: accountName,
            displayEndpoint: displayEndpoint,
          ),
          vmSummary(const AcpAccountIdentity('shared')),
        ],
      ),
    );
    final owner = await h.listOwner();
    owner.setStrings(vmOperationStrings);
    final deleting = Completer<OperationState>();
    h.acp.removeWrite = () => deleting.future;
    final removal = owner.remove(acp, isCompactClean: () => true);
    h.accounts.write = () async => failedVmOperation(
      OperationPhase.unknownOutcome,
      id: 'shared-native-default',
      error: const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Native failed',
        retryable: true,
        correlationId: 'native',
      ),
    );
    expect(await owner.setDefault(native), isFalse);
    var rows = {
      for (final row
          in h.container.read(accountsViewModelProvider).requireValue.list.rows)
        row.key: row,
    };
    expect(rows[native]!.operationError, 'Outcome unknown');
    expect(rows[native]!.actions, isEmpty);
    expect(
      (rows[native]!.content as NativeAccountRowContent).displayEndpoint,
      displayEndpoint,
    );
    expect(rows[acp]!.content, isA<AcpAccountRowContent>());
    expect(rows[acp]!.operationError, isNull);
    expect(rows[acp]!.actions, isEmpty);
    deleting.complete(
      failedVmOperation(
        OperationPhase.syncFailed,
        id: 'shared-acp-delete',
        error: const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'ACP failed',
          retryable: true,
          correlationId: 'acp',
        ),
      ),
    );
    await removal;
    rows = {
      for (final row
          in h.container.read(accountsViewModelProvider).requireValue.list.rows)
        row.key: row,
    };
    expect(rows[native]!.operationError, 'Outcome unknown');
    expect(rows[acp]!.operationError, 'Save failed');
    expect(rows[acp]!.actions, isEmpty);
    expect(await owner.setDefault(native), isFalse);
    expect(await owner.remove(acp, isCompactClean: () => true), isFalse);
    expect(
      h.accounts.defaultCalls.single,
      const NativeAccountIdentity('shared'),
    );
    expect(h.acp.removals.single, const AcpAccountIdentity('shared'));
    h.accounts.state.publish(
      AccountsState(
        stamp: vmStamp,
        templates: h.accounts.state.value.templates,
        accounts: [
          vmSummary(const NativeAccountIdentity('shared'), name: accountName),
          vmSummary(const AcpAccountIdentity('shared')),
        ],
      ),
    );
    rows = {
      for (final row
          in h.container.read(accountsViewModelProvider).requireValue.list.rows)
        row.key: row,
    };
    expect(rows[native]!.name, accountName);
    expect(
      (rows[native]!.content as NativeAccountRowContent).displayEndpoint,
      isNull,
    );
    expect(rows[acp]!.content, isA<AcpAccountRowContent>());
    expect(h.accounts.detailReads, 0);
    expect(h.accounts.detailDemands, isEmpty);
  });
  test(
    'owner replacement keeps editor raw but cannot revive an old save baseline',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      h.accounts.put(vmNative());
      final key = editKey();
      final owner = await h.editor(key);
      owner.changeField(NativeAccountField.name, 'Kept input');
      final previous = h.accounts.state.value;
      h.accounts.state.publish(
        AccountsState(
          stamp: vmStamp,
          accounts: previous.accounts,
          templates: previous.templates,
          stale: true,
        ),
      );
      h.accounts.state.publish(
        AccountsState(
          stamp: const ResourceStamp(
            resourceKey: 'test',
            ownerEpoch: 'new-owner',
            revision: 1,
          ),
          accounts: previous.accounts,
          templates: previous.templates,
        ),
      );
      expect(h.editorState(key).native!.name.raw, 'Kept input');
      expect(h.editorState(key).stale, isTrue);
      expect(await owner.save(), isFalse);
      expect(h.accounts.patches, isEmpty);
    },
  );
  test('an old compact completion cannot clear raw intent after its model owner was replaced', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final owner = await h.modelOwner();
    final work = Completer<OperationState>();
    h.models.compactWrite = () => work.future;
    final resetting = owner.resetCompact('model');
    final previous = h.models.state.value;
    const stamp = ResourceStamp(
      resourceKey: 'models',
      ownerEpoch: 'new-owner',
      revision: 1,
    );
    h.models.state.publish(
      ModelDirectoryState(
        accounts: {
          const NativeAccountIdentity('native'): AccountResource(
            stamp: stamp,
            value:
                previous.accounts[const NativeAccountIdentity('native')]!.value,
          ),
        },
        configurations: {
          const NativeAccountIdentity('native'): AccountResource(
            stamp: stamp,
            value: AccountModelConfiguration(
              autoCompactLimits: const {'model': 300},
            ),
          ),
        },
      ),
    );
    work.complete(savedVmOperation());
    await resetting;
    final compact = h.container
        .read(accountModelsViewModelProvider(nativeKey))
        .requireValue
        .catalog
        .models
        .single
        .compact!;
    expect(compact.raw, '');
    expect(compact.error, isNotNull);
    expect(compact.canSave, isFalse);
    expect(await owner.requestLeaveCompact(AccountLeaveChoice.discard), isTrue);
    expect(owner.hasCompactDrafts(), isTrue);
    expect(owner.discardCompactDrafts(owner.compactLeaveToken()), isTrue);
    owner.changeCompact('model', '700');
    h.models.compactWrite = () async => savedVmOperation('new-owner');
    await owner.saveCompact('model');
    expect((h.models.compactCalls.last.$2 as SetAutoCompactLimit).limit, 700);
    expect(owner.hasCompactDrafts(), isFalse);
  });
  test('summary-only ACP deletion keeps its exact unresolved operation across connection revisions and finally', () async {
    for (final phase in [
      OperationPhase.unknownOutcome,
      OperationPhase.syncFailed,
    ]) {
      final board = MutationBoard(clientId: 'summary-delete-${phase.name}');
      final h = AccountsVmHarness(
        operationLookup: (id) => board.lookup(id)?.state,
      );
      addTearDown(h.dispose);
      const identity = AcpAccountIdentity('acp');
      const key = AccountDisplayKey(kind: AccountKind.acp, id: 'acp');
      void publish(int? revision, {bool stale = false}) =>
          h.accounts.state.publish(
            AccountsState(
              stamp: vmStamp,
              templates: h.accounts.state.value.templates,
              accounts: [vmSummary(identity, acpRevision: revision)],
              stale: stale,
            ),
          );
      AccountRowPresentation row() => h.container
          .read(accountsViewModelProvider)
          .requireValue
          .list
          .rows
          .single;
      publish(1);
      final accountsOwner = await h.listOwner();
      accountsOwner.setStrings(vmOperationStrings);
      final completing = Completer<OperationState>();
      h.acp.removeWrite = () => completing.future;
      final first = accountsOwner.remove(key, isCompactClean: () => true);
      expect(accountsOwner.isRemovalBlocked(key), isTrue);
      expect(row().operationError, isNull);
      expect(row().actions, isEmpty);
      publish(2); // Same account owner, with no intermediate deletion frame.
      expect(
        await accountsOwner.remove(key, isCompactClean: () => true),
        isFalse,
      );
      expect(h.acp.removals, hasLength(1));
      expect(accountsOwner.isRemovalBlocked(key), isTrue);
      final operation = board.begin(target: 'summary-acp-account-delete');
      const failure = StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Account deletion remains unresolved',
        retryable: true,
        correlationId: 'delete',
      );
      if (phase == OperationPhase.unknownOutcome) {
        operation.unknownOutcome(failure);
      } else {
        operation.accept(
          CommitReceipt(
            operationId: operation.id,
            disposition: CommitDisposition.applied,
            targets: const [vmStamp],
            effect: EffectPoint.immediate,
            durable: true,
          ),
        );
        operation.syncFailed(failure);
      }
      completing.complete(operation.state.value);
      expect(await first, isFalse);
      final message = phase == OperationPhase.unknownOutcome
          ? 'Outcome unknown'
          : 'Save failed';
      // Returning false and running finally settle only this caller's wait.
      // They do not release this typed account's deletion fence or feedback.
      expect(row().operationError, message);
      expect(row().actions, isEmpty);
      expect(accountsOwner.isRemovalBlocked(key), isTrue);
      expect(board.lookup(operation.id), same(operation));
      expect(operation.state.value.failurePhase, phase);
      expect(operation.state.value.isPending, isTrue);
      for (final revision in [null, 3, 4]) {
        publish(revision, stale: revision == 3);
        expect(
          await accountsOwner.remove(key, isCompactClean: () => true),
          isFalse,
        );
        expect(accountsOwner.isRemovalBlocked(key), isTrue);
        expect(row().operationError, message);
        expect(row().actions, isEmpty);
        expect(h.acp.removals, hasLength(1));
        expect(board.lookup(operation.id), same(operation));
        expect(operation.state.value.failurePhase, phase);
      }
      expect(h.accounts.detailDemands, isEmpty);
      expect(h.accounts.detailReads, 0);
    }
  });
  test('summary action ownership does not revive when an old owner epoch name returns', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    const key = AccountDisplayKey(kind: AccountKind.acp, id: 'acp');
    void publish(String owner, {bool stale = false}) =>
        h.accounts.state.publish(
          AccountsState(
            stamp: ResourceStamp(
              resourceKey: 'test',
              ownerEpoch: owner,
              revision: 1,
            ),
            templates: h.accounts.state.value.templates,
            accounts: [vmSummary(const AcpAccountIdentity('acp'))],
            stale: stale,
          ),
        );
    publish('owner-A');
    final accountsOwner = await h.listOwner();
    accountsOwner.setStrings(vmOperationStrings);
    final old = Completer<OperationState>();
    h.acp.removeWrite = () => old.future;
    final first = accountsOwner.remove(key, isCompactClean: () => true);
    publish('owner-A', stale: true);
    publish('owner-B');
    publish('owner-B', stale: true);
    publish('owner-A');
    final current = Completer<OperationState>();
    h.acp.removeWrite = () => current.future;
    final second = accountsOwner.remove(key, isCompactClean: () => true);
    expect(h.acp.removals, hasLength(2));
    old.complete(savedVmOperation('old'));
    expect(await first, isFalse);
    expect(
      h.container
          .read(accountsViewModelProvider)
          .requireValue
          .list
          .rows
          .single
          .actions,
      isEmpty,
    );
    current.complete(
      failedVmOperation(
        OperationPhase.unknownOutcome,
        id: 'new-owner-delete',
        error: const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'New owner failure',
          retryable: true,
          correlationId: 'new',
        ),
      ),
    );
    await second;
    expect(
      h.container
          .read(accountsViewModelProvider)
          .requireValue
          .list
          .rows
          .single
          .operationError,
      'Outcome unknown',
    );
    expect(
      await accountsOwner.remove(key, isCompactClean: () => true),
      isFalse,
    );
    expect(h.accounts.detailDemands, isEmpty);
    expect(h.accounts.detailReads, 0);
  });
  test(
    'Native default failure is an operation error, never provider usage health',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      final accountsOwner = await h.listOwner();
      accountsOwner.setStrings(vmOperationStrings);
      h.accounts.write = () async => failedVmOperation(
        OperationPhase.unknownOutcome,
        id: 'default-unknown-health',
        error: const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Default failed',
          retryable: true,
          correlationId: 'default',
        ),
      );
      expect(await accountsOwner.setDefault(nativeKey), isFalse);
      final row = h.container
          .read(accountsViewModelProvider)
          .requireValue
          .list
          .rows
          .single;
      expect(row.operationError, 'Outcome unknown');
      expect(row.actions, isEmpty);
      expect(await accountsOwner.setDefault(nativeKey), isFalse);
      expect(h.accounts.defaultCalls, hasLength(1));
      expect(
        (row.content as NativeAccountRowContent).usage.phase,
        AccountQueryPhase.idle,
      );
      expect(
        (row.content as NativeAccountRowContent).billing,
        AccountBilling.metered,
      );
      expect(h.accounts.detailReads, 0);
    },
  );
  test('new native create uses template defaults and explicit no-secret semantics, never upserts', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final session = await h.session(
      const AccountEditorEntryKey.creating(routeEntryId: 'create'),
    );
    final key = session.currentEditor!;
    final owner = await h.editor(key);
    AccountBillingPresentation billing() => h.editorState(key).native!.billing;
    expect(
      (billing().billingKindOverride, billing().effective),
      (null, AccountBilling.subscription),
    );
    const changedEndpoint = 'https://different-endpoint.example/v2';
    owner.changeField(NativeAccountField.endpoint, changedEndpoint);
    expect(
      (billing().billingKindOverride, billing().effective),
      (null, AccountBilling.unknown),
    );
    owner.changeBilling(AccountBilling.noCharge);
    expect(
      (billing().billingKindOverride, billing().effective),
      (AccountBilling.noCharge, AccountBilling.noCharge),
    );
    owner.changeField(NativeAccountField.endpoint, nativeTemplate.baseUrl);
    expect(billing().effective, AccountBilling.noCharge);
    owner.changeBilling(AccountBilling.unknown);
    expect(
      (billing().billingKindOverride, billing().effective),
      (AccountBilling.unknown, AccountBilling.unknown),
    );
    owner.changeField(NativeAccountField.endpoint, changedEndpoint);
    owner.changeBilling(null);
    expect(
      (billing().billingKindOverride, billing().effective),
      (null, AccountBilling.unknown),
    );
    owner.changeField(
      NativeAccountField.endpoint,
      '${nativeTemplate.baseUrl}/',
    );
    expect(
      (billing().billingKindOverride, billing().effective),
      (null, AccountBilling.unknown),
    );
    owner.changeField(NativeAccountField.endpoint, nativeTemplate.baseUrl);
    expect(
      (billing().billingKindOverride, billing().effective),
      (null, AccountBilling.subscription),
    );
    expect(h.accounts.mutationCalls, isEmpty);
    expect(h.accounts.billing, isEmpty);
    expect(
      (
        h.editorState(key).native!.showSetDefaultOnCreate,
        h.editorState(key).native!.setDefaultOnCreate,
      ),
      (true, false),
    );
    expect(await owner.save(), isTrue);
    expect(h.accounts.patches, isEmpty);
    expect(h.accounts.defaultCalls, isEmpty);
    expect(h.accounts.mutationCalls, ['create']);
    final created = h.accounts.creates.single;
    expect(
      (
        created.identity.accountId,
        created.name,
        created.protocol,
        created.baseUrl,
      ),
      ('native-2', 'Native brand', 'open_ai', 'https://native.example/v1'),
    );
    expect(created.secret.action, AccountSecretAction.preserve);
    expect(created.customModels, isEmpty);
    expect(created.initialBillingKind, isNull);
    expect(
      (billing().billingKindOverride, billing().effective),
      (null, AccountBilling.unknown),
    );
  });
  test('creating Native with default waits for durable creation and retries only the remaining default or field diff', () async {
    final board = MutationBoard(clientId: 'create-default');
    final h = AccountsVmHarness(
      operationLookup: (id) => board.lookup(id)?.state,
    );
    addTearDown(h.dispose);
    final session = await h.session(
      const AccountEditorEntryKey.creating(routeEntryId: 'create'),
    );
    final key = session.currentEditor!;
    final owner = await h.editor(key);
    expect(h.editorState(key).native!.accountKey, isNull);
    owner.changeSetDefaultOnCreate(true);
    const createdStamp = ResourceStamp(
      resourceKey: 'accounts',
      ownerEpoch: 'owner',
      revision: 2,
    );
    final creation = board.begin(target: 'create-native');
    creation.accept(
      CommitReceipt(
        operationId: creation.id,
        disposition: CommitDisposition.applied,
        targets: const [createdStamp],
        effect: EffectPoint.immediate,
      ),
    );
    h.accounts.createWrite = () async => creation.state.value;
    h.accounts.defaultWrite = () async {
      final rejected = board.begin(target: 'default-native');
      rejected.reject(StateError('default rejected'));
      return rejected.state.value;
    };
    final creating = owner.save();
    await h.container.pump();
    expect(h.accounts.mutationCalls, ['create']);
    expect(h.editorState(key).saving, isTrue);
    expect(h.editorState(key).native!.accountKey, isNull);
    final created = h.accounts.creates.single;
    h.accounts.put(
      vmNative(id: key.target.id, name: created.name, hasBearerToken: false),
    );
    final previous = h.accounts.state.value;
    h.accounts.state.publish(
      AccountsState(
        stamp: createdStamp,
        accounts: [
          ...previous.accounts,
          vmSummary(created.identity, name: created.name),
        ],
        templates: previous.templates,
      ),
    );
    board.observe(createdStamp);
    await h.container.pump();
    expect(h.accounts.mutationCalls, ['create']);
    expect(h.editorState(key).saving, isTrue);
    expect(
      (
        h.editorState(key).native!.billing.billingKindOverride,
        h.editorState(key).native!.billing.effective,
      ),
      (null, AccountBilling.metered),
    );
    creation.markDurable();
    expect(await creating, isFalse);
    expect(h.editorState(key).native!.accountKey, key.target);
    expect(h.editorState(key).native!.showSetDefaultOnCreate, isTrue);
    expect(h.accounts.defaultCalls, [created.identity]);
    expect(h.accounts.mutationCalls, ['create', 'default']);
    expect(session.isEditorCurrent(key), isTrue);
    expect(
      (
        h.editorState(key).native!.billing.billingKindOverride,
        h.editorState(key).native!.billing.effective,
      ),
      (null, AccountBilling.metered),
    );
    expect(h.editorState(key).dirty, isTrue);
    expect(h.editorState(key).error, isNotNull);
    expect(h.editorState(key).native!.canChangeTemplate, isFalse);
    expect(owner.hasUnconfirmedSave(), isFalse);
    expect(await owner.save(), isFalse);
    expect(h.accounts.mutationCalls, ['create', 'default', 'default']);
    expect(h.accounts.creates, hasLength(1));
    expect(h.accounts.patches, isEmpty);
    owner.changeField(NativeAccountField.name, 'Changed after partial success');
    final defaultEntered = Completer<void>();
    final defaultCompletion = Completer<OperationState>();
    h.accounts.defaultWrite = () {
      defaultEntered.complete();
      return defaultCompletion.future;
    };
    final retrying = owner.save();
    await defaultEntered.future.timeout(const Duration(seconds: 5));
    expect(h.accounts.mutationCalls, [
      'create',
      'default',
      'default',
      'patch',
      'default',
    ]);
    expect(
      (h.accounts.patches.single.name as AccountTextSet).value,
      'Changed after partial success',
    );
    expect(
      h.accounts.patches.single.secret.action,
      AccountSecretAction.preserve,
    );
    owner.changeField(NativeAccountField.name, 'Newer while setting default');
    defaultCompletion.complete(savedVmOperation('default-saved'));
    expect(await retrying, isFalse);
    expect(
      (h.editorState(key).native!.name.raw, h.editorState(key).dirty),
      ('Newer while setting default', true),
    );
    expect(session.isEditorCurrent(key), isTrue);
    h.accounts.defaultWrite = () =>
        Future.error(StateError('must not repeat a saved default'));
    expect(await owner.save(), isTrue);
    expect(h.accounts.mutationCalls, [
      'create',
      'default',
      'default',
      'patch',
      'default',
      'patch',
    ]);
    expect(
      (h.accounts.patches.last.name as AccountTextSet).value,
      'Newer while setting default',
    );
    expect(h.accounts.creates, hasLength(1));
    expect(h.accounts.defaultCalls, everyElement(created.identity));
    expect(h.editorState(key).dirty, isFalse);
  });
  test('an unconfirmed default after Native creation never replays create or default and explicit discard keeps the domain operation', () async {
    for (final phase in [
      OperationPhase.unknownOutcome,
      OperationPhase.syncFailed,
    ]) {
      final board = MutationBoard(clientId: 'create-default-${phase.name}');
      final h = AccountsVmHarness(
        operationLookup: (id) => board.lookup(id)?.state,
      );
      addTearDown(h.dispose);
      final session = await h.session(
        const AccountEditorEntryKey.creating(routeEntryId: 'create'),
      );
      final key = session.currentEditor!;
      final owner = await h.editor(key);
      owner.changeSetDefaultOnCreate(true);
      final operation = board.begin(target: 'default-native');
      if (phase == OperationPhase.unknownOutcome) {
        operation.unknownOutcome(StateError('default response unknown'));
      } else {
        operation.syncFailed(StateError('default observation failed'));
      }
      h.accounts.defaultWrite = () async => operation.state.value;
      expect(await owner.save(), isFalse);
      expect(h.editorState(key).native!.accountKey, key.target);
      expect(h.editorState(key).native!.showSetDefaultOnCreate, isTrue);
      expect(h.accounts.mutationCalls, ['create', 'default']);
      expect(h.accounts.creates, hasLength(1));
      expect(
        h.accounts.defaultCalls.single,
        h.accounts.creates.single.identity,
      );
      expect((owner.leaveBlocked(), owner.hasUnconfirmedSave()), (false, true));
      expect(
        (
          h.editorState(key).native!.billing.billingKindOverride,
          h.editorState(key).native!.billing.effective,
        ),
        (null, AccountBilling.unknown),
      );
      owner.changeSetDefaultOnCreate(false);
      expect(h.editorState(key).native!.setDefaultOnCreate, isTrue);
      expect(
        (owner.hasUnconfirmedSave(), h.editorState(key).canSave),
        (true, false),
      );
      expect(await owner.save(), isFalse);
      expect(session.isEditorCurrent(key), isTrue);
      expect(h.accounts.mutationCalls, ['create', 'default']);
      owner.changeField(
        NativeAccountField.name,
        'New raw cannot bypass uncertainty',
      );
      expect(await owner.save(), isFalse);
      expect(await owner.requestLeave(AccountLeaveChoice.save), isFalse);
      expect(await owner.requestLeave(AccountLeaveChoice.cancel), isFalse);
      expect(session.isEditorCurrent(key), isTrue);
      expect(h.accounts.mutationCalls, ['create', 'default']);
      expect(await owner.requestLeave(AccountLeaveChoice.discard), isTrue);
      h.releaseSession(session);
      expect(board.lookup(operation.id), same(operation));
      expect(operation.state.value.failurePhase, phase);
      expect(operation.state.value.isPending, isTrue);
      expect(h.accounts.mutationCalls, ['create', 'default']);
    }
  });
  test('list projects exact decimals and transport failure independently of billing and canonical health', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    await h.listOwner();
    const id = NativeAccountIdentity('native');
    h.usage.state.publish(
      AccountResource(
        stamp: vmStamp,
        value: {
          id: AccountUsageObservation(
            identity: id,
            queryRevision: 1,
            revision: 1,
            phase: AccountUsagePhase.succeeded,
            lastGood: AccountUsageSuccess(
              checkedAt: 100,
              value: AccountBalance(
                available: true,
                balances: const [
                  AccountMoneyBalance(
                    currency: 'USD',
                    total: '0.100000000000000001',
                    granted: '',
                    toppedUp: '0.1',
                  ),
                  AccountMoneyBalance(
                    currency: 'CNY',
                    total: '10.80',
                    granted: '0.80',
                    toppedUp: '10.00',
                  ),
                ],
              ),
            ),
          ),
        },
      ),
    );
    h.usage.queryFailures.publish({
      id: const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Transport unavailable',
        retryable: true,
        correlationId: 'test',
      ),
    });
    final row = h.container
        .read(accountsViewModelProvider)
        .requireValue
        .list
        .rows
        .single;
    expect(
      (row.content as NativeAccountRowContent).billing,
      AccountBilling.metered,
    );
    expect(
      (row.content as NativeAccountRowContent).usage.balances
          .map((b) => (b.currency, b.total, b.granted))
          .toList(),
      [('USD', '0.100000000000000001', null), ('CNY', '10.80', '0.80')],
    );
    expect((row.content as NativeAccountRowContent).usage.hasLastGood, isTrue);
    expect(
      (row.content as NativeAccountRowContent).usage.error,
      'Transport unavailable',
    );
    expect(h.usage.state.value.value![id]!.phase, AccountUsagePhase.succeeded);
  });
  test('readout is explicit, bounded and invalidated across catalog identity; stale completion cannot replace a new request', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final owner = await h.modelOwner();
    final old = Completer<DelegationModelDetail>();
    h.models.readout = () => old.future;
    expect(owner.readObservedPerformance(), isEmpty);
    final first = owner.loadReadout('model');
    expect(
      h.container
          .read(accountModelsViewModelProvider(nativeKey))
          .requireValue
          .readouts['model']!
          .phase,
      AccountReadoutPhase.loading,
    );
    final current = h.models.state.value;
    h.models.state.publish(
      ModelDirectoryState(
        accounts: {
          const NativeAccountIdentity('native'): AccountResource(
            stamp: const ResourceStamp(
              resourceKey: 'test',
              ownerEpoch: 'owner',
              revision: 2,
            ),
            value: AccountModelCatalog(
              identity: const NativeAccountIdentity('native'),
              models: current
                  .accounts[const NativeAccountIdentity('native')]!
                  .value!
                  .models,
              status: const ModelCatalogStatusView(queryGeneration: 2),
            ),
          ),
        },
        configurations: current.configurations,
      ),
    );
    expect(
      h.container
          .read(accountModelsViewModelProvider(nativeKey))
          .requireValue
          .readouts['model']!
          .phase,
      AccountReadoutPhase.failed,
    );
    final next = Completer<DelegationModelDetail>();
    h.models.readout = () => next.future;
    final second = owner.loadReadout('model');
    old.complete(vmPerformance());
    await first;
    expect(owner.readObservedPerformance(), isEmpty);
    next.complete(vmPerformance());
    await second;
    final value = h.container
        .read(accountModelsViewModelProvider(nativeKey))
        .requireValue
        .readouts['model']!;
    expect(value.phase, AccountReadoutPhase.ready);
    expect(value.evaluations, hasLength(10));
    expect(value.evaluations.first.comment, 'evaluation-11');
    expect(owner.readObservedPerformance().keys, ['model']);
    AccountModelPresentation model() => h.container
        .read(accountModelsViewModelProvider(nativeKey))
        .requireValue
        .catalog
        .models
        .single;
    expect(model().performance!.tokensPerSecond, 12.5);
    expect(model().performance!.averageTtftMillis, isNull);
    expect(
      (model().performance!.sampleCount, model().performance!.ttftSampleCount),
      (2, 2),
    );
    expect(model().priceTiers, isEmpty);
    expect(model().currency, isNull);
    expect(model().evaluationSummary.count, 10);
    expect(model().evaluationSummary.quality, closeTo(28 / 9, .000001));
    expect(model().evaluationSummary.instructionFollowing, 5);
    expect(model().evaluationSummary.qualityDistribution, {
      1: 2,
      2: 1,
      3: 2,
      4: 2,
      5: 2,
    });
    expect(
      (
        model().evaluations.first.category,
        model().evaluations.first.outcome,
        model().evaluations.first.updatedAt,
      ),
      (AccountEvaluationCategory.coding, AccountEvaluationOutcome.notRated, 11),
    );
    owner.filterEvaluations(
      'model',
      const AccountEvaluationFilter(
        outcome: AccountEvaluationOutcome.failed,
        minimumQuality: 4,
        sort: AccountEvaluationSort.lowestQuality,
      ),
    );
    expect(model().evaluationSummary.visible.map((item) => item.comment), [
      'evaluation-3',
      'evaluation-9',
    ]);
    expect(model().evaluationSummary.count, 10);
    owner.filterEvaluations(
      'model',
      const AccountEvaluationFilter(
        category: AccountEvaluationCategory.general,
      ),
    );
    expect(model().evaluationSummary.visible, isEmpty);
  });
  test('template selection owns defaults, bundled declarations and typed suggested identity', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.state.publish(
      AccountsState(
        stamp: vmStamp,
        templates: h.accounts.state.value.templates,
        accounts: [
          vmSummary(const AcpAccountIdentity('antigravity')),
          vmSummary(const AcpAccountIdentity('antigravity-2')),
          vmSummary(const NativeAccountIdentity('antigravity-3')),
        ],
      ),
    );
    const entry = AccountEditorEntryKey.creating(routeEntryId: 'templates');
    final session = await h.session(entry);
    var templateEntry = entry;
    const expectedNative = AccountTemplateContent.native(
      defaultBilling: AccountBilling.subscription,
      protocolLabel: 'open_ai',
      defaultEndpoint: 'https://native.example/v1',
      supportsModelDiscovery: false,
      supportsUsageQuery: null,
    );
    const expectedCustom = AccountTemplateContent.native(
      defaultBilling: AccountBilling.noCharge,
      protocolLabel: 'open_ai',
      defaultEndpoint: '',
      supportsModelDiscovery: true,
      supportsUsageQuery: false,
    );
    AccountTemplateContent templateContent(AccountTemplateKey key) => h
        .container
        .read(accountEditorSessionViewModelProvider(templateEntry))
        .requireValue
        .templates
        .singleWhere((template) => template.key == key)
        .content;
    expect(
      templateContent(
        const AccountTemplateKey(kind: AccountKind.native, id: 'native'),
      ),
      expectedNative,
    );
    expect(
      templateContent(
        const AccountTemplateKey(kind: AccountKind.native, id: 'custom'),
      ),
      expectedCustom,
    );
    expect(
      templateContent(
        const AccountTemplateKey(kind: AccountKind.acp, id: 'antigravity'),
      ),
      const AccountTemplateContent.acp(),
    );
    final initial = session.currentEditor!;
    final acp = session.replaceTemplate(
      source: initial,
      template: const AccountTemplateKey(
        kind: AccountKind.acp,
        id: 'antigravity',
      ),
      token: session.beginTemplateReplacement(initial)!,
    )!;
    expect(
      acp.target,
      const AccountDisplayKey(kind: AccountKind.acp, id: 'antigravity-3'),
    );
    final native = session.replaceTemplate(
      source: acp,
      template: const AccountTemplateKey(
        kind: AccountKind.native,
        id: 'native',
      ),
      token: session.beginTemplateReplacement(acp)!,
    )!;
    final owner = await h.editor(native);
    final view = h.editorState(native).native!;
    expect(
      (view.name.raw, view.endpoint.raw, view.protocolLabel),
      ('Native brand', 'https://native.example/v1', 'open_ai'),
    );
    expect(view.credential.helper, 'API token · NATIVE_TOKEN');
    expect(view.declaredModels.single.key.modelId, 'suggested');
    const draftEndpoint = 'https://editor-draft.example/private';
    owner.changeField(NativeAccountField.endpoint, draftEndpoint);
    final edited = h.editorState(native).native!;
    expect(edited.endpoint.raw, draftEndpoint);
    expect(
      edited.templates
          .singleWhere((template) => template.key == native.template)
          .content,
      expectedNative,
    );
    expect(
      edited.templates
          .singleWhere((template) => template.key.id == 'custom')
          .content,
      expectedCustom,
    );
    expect(templateContent(native.template!), expectedNative);
    owner.changeField(
      NativeAccountField.credential,
      'secret that must not cross templates',
    );
    expect(await owner.requestLeave(AccountLeaveChoice.cancel), isFalse);
    expect(
      h.editorState(native).native!.credential.raw,
      'secret that must not cross templates',
    );
    expect(await owner.requestLeave(AccountLeaveChoice.discard), isTrue);
    expect(session.isEditorCurrent(native), isTrue);
    final custom = session.replaceTemplate(
      source: native,
      template: const AccountTemplateKey(
        kind: AccountKind.native,
        id: 'custom',
      ),
      token: session.beginTemplateReplacement(native)!,
    )!;
    final customOwner = await h.editor(custom);
    expect(custom.editorId, isNot(native.editorId));
    expect(h.editorState(custom).native!.declaredModels, isEmpty);
    expect(h.editorState(custom).native!.endpoint.raw, '');
    expect(h.editorState(custom).native!.credential.raw, '');
    expect(
      h
          .editorState(custom)
          .native!
          .templates
          .singleWhere((template) => template.key == custom.template)
          .content,
      expectedCustom,
    );
    expect(
      session.replaceTemplate(
        source: custom,
        template: const AccountTemplateKey(
          kind: AccountKind.native,
          id: 'missing',
        ),
        token: session.beginTemplateReplacement(custom)!,
      ),
      isNull,
    );
    expect(session.isEditorCurrent(custom), isTrue);
    final customToken = customOwner.leaveToken();
    h.releaseSession(session);
    expect(customOwner.matchesLeaveToken(customToken), isFalse);
    h.accounts.state.publish(
      AccountsState(
        stamp: vmStamp,
        accounts: h.accounts.state.value.accounts,
        templates: const AccountCatalogView(
          schemaVersion: 1,
          revision: 'fresh-catalog',
          templates: [
            AccountTemplateView(
              id: 'fresh',
              displayName: 'Fresh',
              description: '',
              baseUrl: 'https://fresh.example/v1',
              credentialLabel: '',
              credentialEnv: '',
              modelCatalogId: '',
              protocol: 'open_ai',
              suggestedModelId: '',
              defaultBillingKind: BillingKind.metered,
              supportsModelDiscovery: false,
              supportsUsageQuery: true,
            ),
          ],
          modelCatalogs: {},
        ),
      ),
    );
    const freshEntry = AccountEditorEntryKey.creating(routeEntryId: 'fresh');
    final freshSession = await h.session(freshEntry);
    templateEntry = freshEntry;
    expect(freshSession.currentEditor!.target.id, 'fresh');
    expect(
      templateContent(
        const AccountTemplateKey(kind: AccountKind.native, id: 'fresh'),
      ),
      const AccountTemplateContent.native(
        defaultBilling: AccountBilling.metered,
        protocolLabel: 'open_ai',
        defaultEndpoint: 'https://fresh.example/v1',
        supportsModelDiscovery: false,
        supportsUsageQuery: true,
      ),
    );
    expect(
      templateContent(
        const AccountTemplateKey(kind: AccountKind.acp, id: 'antigravity'),
      ),
      const AccountTemplateContent.acp(),
    );
  });

  test('ordinary edit sends only diff, preserves blank secret, invalid model raw is not discarded', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final key = editKey();
    final owner = await h.editor(key);
    expect(h.editorState(key).native!.accountKey, key.target);
    owner.changeSetDefaultOnCreate(true);
    owner.changeField(NativeAccountField.name, '  Renamed  ');
    expect(await owner.save(), isTrue);
    final patch = h.accounts.patches.single;
    expect((patch.name as AccountTextSet).value, 'Renamed');
    expect(patch.baseUrl, isA<AccountTextKeep>());
    expect(patch.customModels, isA<AccountModelsKeep>());
    expect(patch.secret.action, AccountSecretAction.preserve);
    expect(h.accounts.defaultCalls, isEmpty);
    expect(h.editorState(key).native!.showSetDefaultOnCreate, isFalse);
    owner.addModel();
    final row = h.editorState(key).native!.manualModels.single.editorKey;
    owner.changeModel(row, field: ManualModelField.id, raw: '');
    owner.changeModel(row, field: ManualModelField.contextWindow, raw: '1e3');
    expect(await owner.save(), isFalse);
    expect(
      h.editorState(key).native!.manualModels.single.contextWindow.raw,
      '1e3',
    );
    expect(h.accounts.patches, hasLength(1));
    owner.changeModel(
      row,
      field: ManualModelField.id,
      raw: 'provider/model.v2',
    );
    owner.changeModel(row, field: ManualModelField.contextWindow, raw: '100');
    owner.changeModel(row, field: ManualModelField.maxOutputTokens, raw: '101');
    expect(await owner.save(), isFalse);
    owner.changeModel(row, field: ManualModelField.maxOutputTokens, raw: '80');
    expect(h.editorState(key).native!.manualModels.single.allowedConnections, [
      AccountConnection.automatic,
      AccountConnection.http,
    ]);
    expect(await owner.save(), isTrue);
    expect(
      (h.accounts.patches.last.customModels as AccountModelsSet)
          .models
          .single
          .modelId,
      'provider/model.v2',
    );
  });

  test('old save does not clear newer input or permit navigation, failed save keeps raw', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final key = editKey();
    final owner = await h.editor(key);
    final completion = Completer<OperationState>();
    h.accounts.write = () => completion.future;
    owner.changeField(NativeAccountField.name, 'First');
    final saving = owner.save();
    owner.changeField(NativeAccountField.name, 'Second');
    completion.complete(savedVmOperation());
    expect(await saving, isFalse);
    expect(
      (
        h.editorState(key).native!.name.raw,
        h.editorState(key).dirty,
        h.editorState(key).saving,
      ),
      ('Second', true, false),
    );
    // This failure occurs before admission, not after dispatch or a receipt.
    h.accounts.write = () => Future.error(StateError('before admission'));
    expect(await owner.save(), isFalse);
    expect(h.editorState(key).native!.name.raw, 'Second');
    expect(h.editorState(key).dirty, isTrue);
  });

  test(
    'saving a new manual declaration makes deletion a narrow confirmed intent',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      h.accounts.put(vmNative());
      final key = editKey();
      final owner = await h.editor(key);
      owner.addModel();
      final row = h.editorState(key).native!.manualModels.single.editorKey;
      owner.changeModel(row, field: ManualModelField.id, raw: 'manual');
      expect(await owner.save(), isTrue);
      expect(owner.isSavedModel(row), isTrue);
      expect(h.editorState(key).native!.manualModels.single.canEditId, isFalse);
      publishVmManualModel(h.models, const NativeAccountIdentity('native'));
      final models = await h.modelOwner(key: key.target);
      h.models.removeWrite = () async => failedVmOperation(
        OperationPhase.rejected,
        id: 'manual-delete-rejected',
        error: const StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message: 'Model removal rejected',
          retryable: false,
          correlationId: 'manual-delete',
        ),
      );
      expect(
        await owner.removeModel(
          row,
          modelsOwner: models,
          expectedCompactToken: models.compactLeaveToken(),
        ),
        isFalse,
      );
      expect(owner.hasUnconfirmedSave(), isFalse);
      expect(h.editorState(key).native!.manualModels.single.editorKey, row);
      h.models.removeWrite = () async =>
          savedVmOperation('manual-delete-saved');
      expect(
        await owner.removeModel(
          row,
          modelsOwner: models,
          expectedCompactToken: models.compactLeaveToken(),
        ),
        isTrue,
      );
      expect(h.models.removed.map((id) => id.modelId), ['manual', 'manual']);
    },
  );

  test('uncertain saved-model removal locks the editor without discarding its row or newer raw', () async {
    for (final phase in [
      OperationPhase.unknownOutcome,
      OperationPhase.syncFailed,
    ]) {
      final failure = failedVmOperation(
        phase,
        id: 'manual-delete-${phase.name}',
        error: StateError('admitted removal not confirmed'),
      );
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      h.accounts.put(
        vmNative(
          manual: const [
            AccountModelCommand(
              modelId: 'manual',
              displayName: 'Manual',
              wireApi: 'chat_completions',
              contextWindow: null,
              maxOutputTokens: null,
            ),
          ],
        ),
      );
      final session = await h.session(
        const AccountEditorEntryKey.editing(
          routeEntryId: 'remove-model',
          account: nativeKey,
        ),
      );
      final key = session.currentEditor!;
      final owner = await h.editor(key);
      publishVmManualModel(h.models, const NativeAccountIdentity('native'));
      final models = await h.modelOwner(key: key.target);
      owner.setStrings(vmOperationStrings);
      owner.changeField(NativeAccountField.name, 'Local before removal');
      final row = h.editorState(key).native!.manualModels.single.editorKey;
      h.models.removeWrite = () async => failure;
      expect(
        await owner.removeModel(
          row,
          modelsOwner: models,
          expectedCompactToken: models.compactLeaveToken(),
        ),
        isFalse,
      );
      expect(h.editorState(key).native!.manualModels.single.editorKey, row);
      expect(h.editorState(key).native!.name.raw, 'Local before removal');
      expect(h.editorState(key).key, key);
      expect(
        (
          owner.hasUnconfirmedSave(),
          owner.leaveBlocked(),
          h.editorState(key).canSave,
        ),
        (true, false, false),
      );
      expect(
        h.editorState(key).error,
        phase == OperationPhase.unknownOutcome
            ? 'Outcome unknown'
            : 'Save failed',
      );
      expect(
        await owner.removeModel(
          row,
          modelsOwner: models,
          expectedCompactToken: models.compactLeaveToken(),
        ),
        isFalse,
      );
      expect(await owner.save(), isFalse);
      owner.changeField(
        NativeAccountField.name,
        'New raw cannot replay removal',
      );
      expect(
        await owner.removeModel(
          row,
          modelsOwner: models,
          expectedCompactToken: models.compactLeaveToken(),
        ),
        isFalse,
      );
      expect(await owner.save(), isFalse);
      expect(
        h.editorState(key).native!.name.raw,
        'New raw cannot replay removal',
      );
      expect(h.editorState(key).native!.manualModels.single.editorKey, row);
      expect(h.models.removed, hasLength(1));
      expect(h.accounts.patches, isEmpty);
      expect(h.accounts.creates, isEmpty);
      expect(await owner.requestLeave(AccountLeaveChoice.cancel), isFalse);
      expect(session.isEditorCurrent(key), isTrue);
      expect(await owner.requestLeave(AccountLeaveChoice.discard), isTrue);
      h.releaseSession(session);
      expect(session.currentEditor, isNull);
      expect(h.models.removed, hasLength(1));
    }
  });

  test('visibility and provider disposal release display demand without cancelling accepted writes', () async {
    final h = AccountsVmHarness();
    final accountsOwner = await h.listOwner();
    expect(h.accounts.detailReads, 0);
    accountsOwner.setVisible(true);
    accountsOwner.setVisible(true);
    expect(h.usage.demands, hasLength(1));
    accountsOwner.setVisible(false);
    expect(h.usage.demands.single.releases, 1);
    h.accounts.put(vmNative());
    final key = editKey();
    final owner = await h.editor(key);
    final completion = Completer<OperationState>();
    h.accounts.write = () => completion.future;
    owner.changeField(NativeAccountField.name, 'Pending');
    final saving = owner.save();
    owner.finish();
    h.dispose();
    completion.complete(savedVmOperation());
    expect(await saving, isFalse);
    expect(h.accounts.detailDemands.every((d) => d.releases == 1), isTrue);
    expect(h.accounts.patches, hasLength(1));
  });

  test(
    'compact invalid raw and a newer revision survive an old reset completion',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      final owner = await h.modelOwner();
      final completion = Completer<OperationState>();
      h.models.compactWrite = () => completion.future;
      final saving = owner.resetCompact('model');
      owner.changeCompact('model', '1.5');
      completion.complete(savedVmOperation());
      await saving;
      final model = h.container
          .read(accountModelsViewModelProvider(nativeKey))
          .requireValue
          .catalog
          .models
          .single;
      expect(model.compact!.raw, '1.5');
      expect(model.compact!.canRetry, isFalse);
      expect(h.models.compactCalls.single.$2, isA<ClearAutoCompactLimit>());
      for (final raw in ['-1', '1e3', '0', '']) {
        owner.changeCompact('model', raw);
        expect(
          h.container
              .read(accountModelsViewModelProvider(nativeKey))
              .requireValue
              .catalog
              .models
              .single
              .compact!
              .raw,
          raw,
        );
      }
      expect(h.models.compactCalls, hasLength(1));
    },
  );
}
