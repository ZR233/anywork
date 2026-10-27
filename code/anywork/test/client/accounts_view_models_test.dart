import 'dart:async';

import 'package:anywork/src/features/settings/accounts/connectors/account_strings.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_state.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_models_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_details_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_projection.dart';
import 'package:anywork/src/presentation/providers/account_domains.dart';
import 'package:anywork/src/presentation/providers/account_operation_observation.dart';
import 'package:anywork/src/l10n/app_localizations_en.dart';
import 'package:anywork/src/l10n/app_localizations_zh.dart';
import 'package:anywork_client/accounts.dart';
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
AccountSummary vmSummary(
  AccountIdentity identity, {
  String? name,
  int? acpRevision = 1,
}) => AccountSummary(
  identity: identity,
  name: name ?? identity.accountId,
  isDefault: false,
  billingKind: identity is NativeAccountIdentity ? BillingKind.metered : null,
  usageQueryRevision: 1,
  acpConnectionRevision: identity is AcpAccountIdentity ? acpRevision : null,
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
}) => NativeAccountDetails(
  identity: NativeAccountIdentity(id),
  name: name,
  protocol: 'open_ai',
  templateId: 'native',
  baseUrl: 'https://native.example/v1',
  hasBearerToken: true,
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
  final removals = <NativeAccountIdentity>[];
  Future<OperationState> Function()? write;
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
    return write?.call() ?? Future.value(savedVmOperation());
  }

  @override
  Future<OperationState> create(
    CreateAccountCommand command, {
    DraftStamp? draft,
  }) {
    creates.add(command);
    return write?.call() ?? Future.value(savedVmOperation());
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
    return write?.call() ?? Future.value(savedVmOperation());
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
  final connections = <(AccountModelIdentity, ModelConnectionIntent)>[];
  final removed = <AccountModelIdentity>[];
  Future<OperationState> Function()? compactWrite;
  Future<OperationState> Function()? connectionWrite;
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
    return savedVmOperation();
  }

  @override
  Future<DelegationModelDetail> performance(AccountModelIdentity id) =>
      readout!();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
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
  Future<AccountsViewModel> navigation() async {
    _listeners.add(
      container.listen(accountsViewModelProvider, (_, _) {}).close,
    );
    await container.read(accountsViewModelProvider.future);
    return container.read(accountsViewModelProvider.notifier);
  }

  Future<AccountEditorViewModel> editor(AccountEditorKey key) async {
    _listeners.add(
      container.listen(accountEditorViewModelProvider(key), (_, _) {}).close,
    );
    await container.read(accountEditorViewModelProvider(key).future);
    return container.read(accountEditorViewModelProvider(key).notifier);
  }

  Future<AccountModelsViewModel> modelOwner() async {
    _listeners.add(
      container
          .listen(accountModelsViewModelProvider(nativeKey), (_, _) {})
          .close,
    );
    await container.read(accountModelsViewModelProvider(nativeKey).future);
    return container.read(accountModelsViewModelProvider(nativeKey).notifier);
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
    ratedSamples: 12,
    passed: 12,
    failed: 0,
    notRated: 0,
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
        outcome: AgentEvaluationOutcome.passed,
        comment: 'evaluation-$i',
        createdAt: i,
        updatedAt: i,
      ),
  ],
);

void main() {
  test('current Native detail observes default and delete failures outside the filtered list', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final navigation = await h.navigation();
    navigation.search('not-a-visible-row');
    navigation.open(nativeKey);
    final owner = await h.details(nativeKey);
    final provider = accountDetailsViewModelProvider(nativeKey);
    AccountDetailsPresentation current() =>
        h.container.read(provider).requireValue.details;
    for (final command in [navigation.setDefault, navigation.remove]) {
      final work = Completer<OperationState>();
      h.accounts.write = () => work.future;
      final saving = command(nativeKey);
      expect(current().loading, isTrue);
      expect(
        (current().canEdit, current().canSetDefault, current().canDelete),
        (false, false, false),
      );
      work.completeError(
        const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Header command failed',
          retryable: true,
          correlationId: 'header',
        ),
      );
      expect(await saving, isFalse);
      expect(current().error, 'Header command failed');
      expect(current().loading, isFalse);
      expect(current().canDelete, isTrue);
      expect(owner.presentation().error, 'Header command failed');
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
      final navigation = await h.navigation();
      navigation.search('not-a-visible-row');
      navigation.open(vmAcpKey.target);
      final owner = await h.details(vmAcpKey.target);
      await listenVmAcp(h, vmAcpKey);
      final provider = accountDetailsViewModelProvider(vmAcpKey.target);
      final work = Completer<OperationState>();
      h.acp.removeWrite = () => work.future;
      final deleting = navigation.remove(vmAcpKey.target);
      expect(h.container.read(provider).requireValue.details.loading, isTrue);
      work.completeError(
        const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'ACP delete failed',
          retryable: true,
          correlationId: 'delete',
        ),
      );
      expect(await deleting, isFalse);
      expect(
        h.container.read(provider).requireValue.details.error,
        'ACP delete failed',
      );
      final active = owner.presentation(
        acp: h.container
            .read(acpAccountViewModelProvider(vmAcpKey))
            .requireValue
            .panel,
      );
      expect(active.error, 'ACP delete failed');
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
    final navigation = await h.navigation();
    navigation.setStrings(
      const AccountStrings({
        'awaitingObservation': 'Waiting for observation',
        'unknownOutcome': 'Outcome unknown',
      }),
    );
    navigation.search('not-a-visible-row');
    navigation.open(nativeKey);
    await h.details(nativeKey);
    final provider = accountDetailsViewModelProvider(nativeKey);
    AccountDetailsPresentation current() =>
        h.container.read(provider).requireValue.details;
    final operation = board.begin(target: 'native-default');
    h.accounts.write = () async => operation.state.value;
    expect(await navigation.setDefault(nativeKey), isFalse);
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
    expect(await navigation.setDefault(nativeKey), isFalse);
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
  test('current detail qualifies action feedback by typed target and observed ACP connection', () async {
    final h = AccountsVmHarness();
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
    final navigation = await h.navigation();
    navigation.search('not-a-visible-row');
    navigation.open(acp);
    await h.details(acp);
    await h.details(native);
    final provider = accountDetailsViewModelProvider(acp);
    AccountDetailsPresentation current() =>
        h.container.read(provider).requireValue.details;
    final old = Completer<OperationState>();
    h.acp.removeWrite = () => old.future;
    final first = navigation.remove(acp);
    h.accounts.write = () => Future.error(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Native only',
        retryable: true,
        correlationId: 'native',
      ),
    );
    await navigation.setDefault(native);
    expect(
      h.container
          .read(accountDetailsViewModelProvider(native))
          .requireValue
          .details
          .error,
      'Native only',
    );
    expect((current().loading, current().error), (true, null));
    summaries(2);
    final next = Completer<OperationState>();
    h.acp.removeWrite = () => next.future;
    final second = navigation.remove(acp);
    // A new summary cannot attach its action to the retained old detail.
    expect((current().loading, current().error), (false, null));
    details(2);
    expect(current().loading, isTrue);
    old.completeError(StateError('retired'));
    expect(await first, isFalse);
    expect((current().loading, current().error), (true, null));
    next.completeError(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Current connection failed',
        retryable: true,
        correlationId: 'current',
      ),
    );
    expect(await second, isFalse);
    expect(current().error, 'Current connection failed');
    expect(h.acp.removals, hasLength(2));
  });
  test('current detail action ownership does not revive after owner epoch A to B to A', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final navigation = await h.navigation();
    navigation.search('not-a-visible-row');
    navigation.open(nativeKey);
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
    final first = navigation.setDefault(nativeKey);
    publish('owner', stale: true);
    publish('replacement');
    publish('replacement', stale: true);
    publish('owner');
    final next = Completer<OperationState>();
    h.accounts.write = () => next.future;
    final second = navigation.setDefault(nativeKey);
    old.complete(savedVmOperation('old-lifecycle'));
    expect(await first, isFalse);
    expect((current().loading, current().error), (true, null));
    next.completeError(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Current owner failed',
        retryable: true,
        correlationId: 'current',
      ),
    );
    expect(await second, isFalse);
    expect(current().error, 'Current owner failed');
    expect(h.accounts.defaultCalls, hasLength(2));
  });
  test('editor declarations omit compact data while the real details model remains editable', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
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
      final facts = h.container
          .read(accountModelsViewModelProvider(nativeKey))
          .requireValue
          .catalog
          .models
          .single
          .capabilities;
      expect(
        facts.where(
          (fact) =>
              fact.label == l10n.settingsOutputBudget ||
              fact.label == modalitiesLabel,
        ),
        [
          AccountDisplayFact(label: l10n.settingsOutputBudget, value: '4096'),
          AccountDisplayFact(label: modalitiesLabel, value: 'text'),
        ],
      );
    }
  });
  test('a display demand failure after create preserves durable baseline and saved manual identity', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final navigation = await h.navigation();
    final key = navigation.create(
      const AccountTemplateKey(kind: AccountKind.native, id: 'native'),
    )!;
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
    h.accounts.state.publish(
      AccountsState(
        stamp: vmStamp,
        templates: h.accounts.state.value.templates,
        accounts: [
          vmSummary(const NativeAccountIdentity('shared')),
          vmSummary(const AcpAccountIdentity('shared')),
        ],
      ),
    );
    final owner = await h.navigation();
    final deleting = Completer<OperationState>();
    h.acp.removeWrite = () => deleting.future;
    final removal = owner.remove(acp);
    h.accounts.write = () => Future.error(
      const StudioFailure(
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
    expect(rows[native]!.operationError, 'Native failed');
    expect(rows[acp]!.operationError, isNull);
    expect(rows[acp]!.actions, isEmpty);
    deleting.completeError(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'ACP failed',
        retryable: true,
        correlationId: 'acp',
      ),
    );
    await removal;
    rows = {
      for (final row
          in h.container.read(accountsViewModelProvider).requireValue.list.rows)
        row.key: row,
    };
    expect(rows[native]!.operationError, 'Native failed');
    expect(rows[acp]!.operationError, 'ACP failed');
    expect(
      h.accounts.defaultCalls.single,
      const NativeAccountIdentity('shared'),
    );
    expect(h.acp.removals.single, const AcpAccountIdentity('shared'));
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
  });
  test('summary-only ACP actions isolate late failure and finally from a rebuilt same-id connection', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    const identity = AcpAccountIdentity('acp');
    const key = AccountDisplayKey(kind: AccountKind.acp, id: 'acp');
    void publish(int? revision, {bool stale = false, String owner = 'owner'}) =>
        h.accounts.state.publish(
          AccountsState(
            stamp: ResourceStamp(
              resourceKey: 'test',
              ownerEpoch: owner,
              revision: 1,
            ),
            templates: h.accounts.state.value.templates,
            accounts: [vmSummary(identity, acpRevision: revision)],
            stale: stale,
          ),
        );
    publish(1);
    final navigation = await h.navigation();
    final old = Completer<OperationState>();
    h.acp.removeWrite = () => old.future;
    final first = navigation.remove(key);
    publish(2); // No intermediate deletion frame.
    final current = Completer<OperationState>();
    h.acp.removeWrite = () => current.future;
    final second = navigation.remove(key);
    expect(h.acp.removals, hasLength(2));
    old.completeError(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Old deletion failed',
        retryable: true,
        correlationId: 'old',
      ),
    );
    expect(await first, isFalse);
    var row = h.container
        .read(accountsViewModelProvider)
        .requireValue
        .list
        .rows
        .single;
    expect(row.operationError, isNull);
    expect(row.actions, isEmpty);
    current.completeError(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Current deletion failed',
        retryable: true,
        correlationId: 'new',
      ),
    );
    expect(await second, isFalse);
    row = h.container
        .read(accountsViewModelProvider)
        .requireValue
        .list
        .rows
        .single;
    expect(row.operationError, 'Current deletion failed');
    expect(row.actions, contains(AccountRowAction.delete));
    publish(null);
    expect(await navigation.remove(key), isFalse);
    publish(3, stale: true);
    expect(await navigation.remove(key), isFalse);
    expect(h.acp.removals, hasLength(2));
    expect(h.accounts.detailDemands, isEmpty);
    expect(h.accounts.detailReads, 0);
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
    final navigation = await h.navigation();
    final old = Completer<OperationState>();
    h.acp.removeWrite = () => old.future;
    final first = navigation.remove(key);
    publish('owner-A', stale: true);
    publish('owner-B');
    publish('owner-B', stale: true);
    publish('owner-A');
    final current = Completer<OperationState>();
    h.acp.removeWrite = () => current.future;
    final second = navigation.remove(key);
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
    current.completeError(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'New owner failure',
        retryable: true,
        correlationId: 'new',
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
      'New owner failure',
    );
    expect(h.accounts.detailDemands, isEmpty);
    expect(h.accounts.detailReads, 0);
  });
  test(
    'Native default failure is an operation error, never provider usage health',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      final navigation = await h.navigation();
      h.accounts.write = () => Future.error(
        const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Default failed',
          retryable: true,
          correlationId: 'default',
        ),
      );
      expect(await navigation.setDefault(nativeKey), isFalse);
      final row = h.container
          .read(accountsViewModelProvider)
          .requireValue
          .list
          .rows
          .single;
      expect(row.operationError, 'Default failed');
      expect(row.usage!.phase, AccountQueryPhase.idle);
      expect(row.billing, AccountBilling.metered);
      expect(h.accounts.detailReads, 0);
    },
  );
  test('new native create uses template defaults and explicit no-secret semantics, never upserts', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final navigation = await h.navigation();
    final key = navigation.create(
      const AccountTemplateKey(kind: AccountKind.native, id: 'native'),
    )!;
    final owner = await h.editor(key);
    expect(await owner.save(), isTrue);
    expect(h.accounts.patches, isEmpty);
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
    expect(created.secret.action, AccountSecretAction.clear);
    expect(created.customModels, isEmpty);
  });
  test('list projects exact decimals and transport failure independently of billing and canonical health', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    await h.navigation();
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
    expect(row.billing, AccountBilling.metered);
    expect(
      row.usage!.balances.map((b) => (b.currency, b.total, b.granted)).toList(),
      [('USD', '0.100000000000000001', null), ('CNY', '10.80', '0.80')],
    );
    expect(row.usage!.hasLastGood, isTrue);
    expect(row.usage!.error, 'Transport unavailable');
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
    final navigation = await h.navigation();
    final acp = navigation.create(
      const AccountTemplateKey(kind: AccountKind.acp, id: 'antigravity'),
    )!;
    expect(
      acp.target,
      const AccountDisplayKey(kind: AccountKind.acp, id: 'antigravity-3'),
    );
    navigation.finishEditor(acp);
    final native = navigation.create(
      const AccountTemplateKey(kind: AccountKind.native, id: 'native'),
    )!;
    final owner = await h.editor(native);
    final view = h.editorState(native).native!;
    expect(
      (view.name.raw, view.endpoint.raw, view.protocolLabel),
      ('Native brand', 'https://native.example/v1', 'open_ai'),
    );
    expect(view.credential.helper, 'API token · NATIVE_TOKEN');
    expect(view.declaredModels.single.key.modelId, 'suggested');
    owner.changeTemplate(
      const AccountTemplateKey(kind: AccountKind.native, id: 'custom'),
    );
    expect(h.editorState(native).native!.declaredModels, isEmpty);
    expect(h.editorState(native).native!.endpoint.raw, '');
    owner.changeTemplate(
      const AccountTemplateKey(kind: AccountKind.native, id: 'missing'),
    );
    expect(h.editorState(native).native!.templateKey.id, 'custom');
    expect(
      navigation.create(
        const AccountTemplateKey(kind: AccountKind.native, id: 'missing'),
      ),
      isNull,
    );
    owner.finish();
    navigation.finishEditor(native);
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
            ),
          ],
          modelCatalogs: {},
        ),
      ),
    );
    expect(
      navigation
          .create(
            const AccountTemplateKey(kind: AccountKind.native, id: 'fresh'),
          )!
          .target
          .id,
      'fresh',
    );
  });

  test('ordinary edit sends only diff, preserves blank secret, invalid model raw is not discarded', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final key = editKey();
    final owner = await h.editor(key);
    owner.changeField(NativeAccountField.name, '  Renamed  ');
    expect(await owner.save(), isTrue);
    final patch = h.accounts.patches.single;
    expect((patch.name as AccountTextSet).value, 'Renamed');
    expect(patch.baseUrl, isA<AccountTextKeep>());
    expect(patch.customModels, isA<AccountModelsKeep>());
    expect(patch.secret.action, AccountSecretAction.preserve);
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
    h.accounts.write = () => Future.error(StateError('offline'));
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
      expect(await owner.removeModel(row), isTrue);
      expect(h.models.removed.single.modelId, 'manual');
    },
  );

  test('visibility and provider disposal release display demand without cancelling accepted writes', () async {
    final h = AccountsVmHarness();
    final navigation = await h.navigation();
    expect(h.accounts.detailReads, 0);
    navigation.setVisible(true);
    navigation.setVisible(true);
    expect(h.usage.demands, hasLength(1));
    navigation.setVisible(false);
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
