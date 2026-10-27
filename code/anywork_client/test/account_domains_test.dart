import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart'
    show
        MutationBoard,
        ResourceBudget,
        ResourceKind,
        OperationId,
        OperationPhase,
        SettingsCommandReply,
        SettingsStateSnapshot,
        StudioCommandReceipt,
        CommitDisposition,
        EffectPoint,
        ResourceStamp,
        StudioFailure,
        StudioFailureCode,
        DelegationModelKey,
        DelegationModelDetail,
        AnyworkClient,
        StudioTransport;
import 'package:test/test.dart';

const _native = NativeAccountIdentity('same');
const _acp = AcpAccountIdentity('same');
const _model = AccountModelIdentity(account: _native, modelId: 'configured');
ResourceStamp _stamp(String source, int revision, {String epoch = 'owner'}) =>
    ResourceStamp(resourceKey: source, ownerEpoch: epoch, revision: revision);

AccountSummary _summary({
  NativeAccountIdentity identity = _native,
  int query = 1,
  BillingKind kind = BillingKind.noCharge,
  bool queryUsage = true,
  bool credentialReady = true,
}) => AccountSummary(
  identity: identity,
  name: 'Native',
  isDefault: true,
  billingKind: kind,
  credentialReady: credentialReady,
  usageQueryRevision: query,
  capabilities: AccountCapabilities(
    setDefault: true,
    edit: true,
    remove: true,
    queryUsage: queryUsage,
    syncModels: true,
    editModels: true,
    acpAuth: false,
  ),
);

NativeAccountDetails _details({
  NativeAccountIdentity identity = _native,
  String name = 'Native',
  int query = 1,
}) => NativeAccountDetails(
  identity: identity,
  name: name,
  protocol: 'compatible',
  baseUrl: 'https://example.invalid',
  hasBearerToken: true,
  credentialRequired: true,
  usageQueryRevision: query,
  customModels: const [],
);

AccountModelsFrame _models(
  NativeAccountIdentity identity,
  int revision, {
  String label = 'Effective',
  String epoch = 'owner',
}) => AccountModelsFrame(
  _stamp('model-catalog', revision, epoch: epoch),
  identity,
  AccountModelCatalog(
    identity: identity,
    models: [
      AccountModelView(
        modelId: 'configured',
        displayName: label,
        reasoningEfforts: const ['high'],
        origin: ModelOrigin.online,
      ),
    ],
    status: const ModelCatalogStatusView(),
  ),
);

final class _Handle implements AccountDomainObservation {
  Completer<AccountDomainFrame?>? _next;
  bool closed = false;
  int closeCalls = 0;
  int closeFailures = 0;
  final requested = Completer<void>();
  final reading = Completer<void>();
  void Function()? onRequestClose;
  @override
  Future<AccountDomainFrame?> next() {
    if (closed) return Future.value(null);
    if (_next != null) throw StateError('Concurrent next');
    if (!reading.isCompleted) reading.complete();
    return (_next = Completer<AccountDomainFrame?>()).future;
  }

  @override
  void requestClose() {
    closed = true;
    if (!requested.isCompleted) requested.complete();
    _next?.complete(null);
    _next = null;
    final callback = onRequestClose;
    onRequestClose = null;
    callback?.call();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    if (closeFailures-- > 0) throw StateError('Scripted native close failure');
  }
}

final class _Port
    implements
        StudioTransport,
        AccountFeedPort,
        AccountConfigurationPort,
        AccountModelsPort,
        AccountUsagePort,
        AcpPort {
  Future<ModelSyncAdmission> Function(NativeAccountIdentity, OperationId)?
  syncModels;
  final Map<AccountObservationTarget, _Handle> handles = {};
  final Map<AccountObservationTarget, AccountDomainFrame> reads = {};
  final List<AccountObservationTarget> opens = [];
  final List<AccountObservationTarget> readCalls = [];
  Completer<AccountDomainObservation>? lateOpen;
  Future<SettingsCommandReply> Function(int, PatchAccountCommand, OperationId)?
  patch;
  Future<SettingsCommandReply> Function(int, AutoCompactIntent, OperationId)?
  compact;
  Future<AccountUsageFrame> Function(NativeAccountIdentity)? usage;
  Future<AcpAuthCommandReply> Function(
    OperationId,
    String,
    int,
    AcpAuthActionView,
  )?
  auth;
  Future<AcpAuthCommandReply> Function(OperationId, String, OperationId)?
  cancel;
  Future<AcpInstallCommandReply> Function(OperationId, AcpProviderView)?
  installStart;
  Future<AcpInstallCommandReply> Function(
    OperationId,
    AcpProviderView,
    OperationId,
  )?
  installCancel;
  void Function()? onOpen;
  Future<DelegationModelDetail> Function(DelegationModelKey)? modelDetail;

  @override
  Future<AccountDomainObservation> openAccountObservation(
    AccountObservationTarget target,
  ) async {
    opens.add(target);
    if (lateOpen case final pending?) return pending.future;
    // Each open owns a distinct native handle, including overlapping late opens
    // from retired generations. The map only exposes the latest test handle.
    final handle = handles[target] = _Handle();
    final callback = onOpen;
    onOpen = null;
    callback?.call();
    return handle;
  }

  @override
  Future<AccountDomainFrame> readAccountDomain(
    AccountObservationTarget target,
  ) async {
    readCalls.add(target);
    return reads[target]!;
  }

  @override
  Future<SettingsCommandReply> patchAccount(
    int revision,
    PatchAccountCommand command, {
    required OperationId operationId,
  }) => patch!(revision, command, operationId);
  @override
  Future<SettingsCommandReply> setAccountModelAutoCompact(
    int revision,
    AccountModelIdentity identity,
    AutoCompactIntent intent, {
    required OperationId operationId,
  }) {
    expect(identity, _model);
    return compact!(revision, intent, operationId);
  }

  @override
  Future<AccountUsageFrame> queryAccountUsage(NativeAccountIdentity identity) =>
      usage!(identity);
  @override
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  }) => auth!(operationId, accountId, expectedConnectionRevision, action);
  @override
  Future<AcpAuthCommandReply> cancelAcpAuth({
    required OperationId operationId,
    required String accountId,
    required OperationId targetOperationId,
  }) => cancel!(operationId, accountId, targetOperationId);
  @override
  Future<ModelSyncAdmission> syncAccountModels(
    NativeAccountIdentity identity, {
    required OperationId operationId,
  }) => syncModels!(identity, operationId);

  @override
  Future<AcpInstallCommandReply> startAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
  }) => installStart!(operationId, provider);

  @override
  Future<AcpInstallCommandReply> cancelAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
    required OperationId targetOperationId,
  }) => installCancel!(operationId, provider, targetOperationId);

  @override
  Future<DelegationModelDetail> getDelegationModel(DelegationModelKey key) =>
      modelDetail!(key);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}

final class _Fixture {
  _Fixture({String owner = 'client'}) {
    board = MutationBoard(clientId: owner, budget: budget);
    resources = AccountDomainResources(
      feed: port,
      configuration: port,
      modelPort: port,
      usagePort: port,
      acpPort: port,
      coordinator: coordinator,
      mutations: board,
      budget: budget,
      owner: owner,
    );
    resources.adoptOwnerEpoch('owner');
    resources.acceptFrame(
      AccountSummariesFrame(_stamp('settings', 1), [_summary()]),
    );
  }
  final port = _Port();
  final budget = ResourceBudget();
  final coordinator = SettingsWriteCoordinator();
  late final MutationBoard board;
  late final AccountDomainResources resources;
  Future<void> close() async {
    await coordinator.close();
    final report = await resources.close(
      deadline: DateTime.now().add(const Duration(seconds: 1)),
    );
    expect(
      report.complete,
      isTrue,
      reason: '${report.unresolved.map((item) => item.reason)}',
    );
    expect(budget.used(ResourceKind.observer), 0);
  }
}

StudioCommandReceipt _receipt(
  OperationId operation, {
  int settings = 2,
  int? catalog,
  String resource = 'settings',
}) => StudioCommandReceipt(
  operationId: operation,
  disposition: CommitDisposition.applied,
  targets: [
    _stamp(resource, settings),
    if (catalog != null) _stamp('model-catalog', catalog),
  ],
  effect: EffectPoint.futureSession,
  effective: false,
  durable: true,
);

void main() {
  for (final action in [
    'auth start',
    'auth cancel',
    'install start',
    'install cancel',
  ]) {
    for (final boundary in ['late reply', 'receipt', 'content', 'healthy']) {
      test(
        'ACP lifecycle $action preserves receipt and observation qualification at $boundary',
        () async {
          final fixture = _Fixture();
          addTearDown(fixture.close);
          final client = AnyworkClient(
            transport: fixture.port,
            clientId: fixture.board.clientId,
            budget: fixture.budget,
            settingsWrites: fixture.coordinator,
            mutationBoard: fixture.board,
            accountDomains: fixture.resources,
          );
          addTearDown(client.close);
          final isAuth = action.startsWith('auth');
          final isCancel = action.endsWith('cancel');
          void detail(int connection) => fixture.resources.acceptFrame(
            AccountDetailFrame(
              _stamp('settings', connection),
              _acp,
              AcpAccountDetails(
                AcpAccountSettingsView(
                  accountId: 'same',
                  name: 'ACP',
                  provider: AcpProviderView.antigravity,
                  connectionRevision: connection,
                ),
              ),
            ),
          );
          AcpAuthSnapshotView authSnapshot(
            String operation,
            int revision,
            int connection,
          ) => AcpAuthSnapshotView(
            revision: revision,
            updatedAt: revision,
            accounts: [
              AcpAuthAccountView(
                accountId: 'same',
                connectionRevision: connection,
                state: isCancel
                    ? AcpCancellingState(operationId: operation)
                    : AcpCheckingState(operationId: operation),
              ),
            ],
          );
          AcpInstallSnapshotView installSnapshot(
            String operation,
            int revision,
          ) => AcpInstallSnapshotView(
            revision: revision,
            updatedAt: revision,
            installations: [
              AcpInstallEntryView(
                provider: AcpProviderView.antigravity,
                state: isCancel
                    ? AcpInstallCancellingState(operationId: operation)
                    : AcpResolvingState(operationId: operation),
              ),
            ],
          );
          if (isAuth) detail(7);
          if (isCancel) {
            fixture.resources.acceptFrame(
              isAuth
                  ? AcpAuthFrame(
                      _stamp('acp-auth', 0),
                      authSnapshot('target', 0, 7),
                    )
                  : AcpInstallFrame(
                      _stamp('acp-install', 0),
                      installSnapshot('target', 0),
                    ),
            );
          }
          final entered = Completer<OperationId>();
          final authReply = Completer<AcpAuthCommandReply>();
          final installReply = Completer<AcpInstallCommandReply>();
          fixture.port.auth = (id, account, connection, _) {
            expect((account, connection), ('same', 7));
            entered.complete(id);
            return authReply.future;
          };
          fixture.port.cancel = (id, account, target) {
            expect((account, target.value), ('same', 'target'));
            entered.complete(id);
            return authReply.future;
          };
          fixture.port.installStart = (id, _) {
            entered.complete(id);
            return installReply.future;
          };
          fixture.port.installCancel = (id, _, target) {
            expect(target.value, 'target');
            entered.complete(id);
            return installReply.future;
          };
          final command = switch (action) {
            'auth start' => fixture.resources.acp.check(_acp),
            'auth cancel' => fixture.resources.acp.cancelAuth(_acp),
            'install start' => fixture.resources.acp.prepare(
              AcpProviderView.antigravity,
            ),
            _ => fixture.resources.acp.cancelPreparation(
              AcpProviderView.antigravity,
            ),
          };
          final outcome = command.then<Object?>(
            (_) => null,
            onError: (Object error) => error,
          );
          final id = await entered.future;
          final operation = fixture.board.lookup(id)!;
          var retired = false;
          Object? replacement;
          Object? retirementFailure;
          void retire() {
            if (retired) return;
            retired = true;
            fixture.resources.adoptOwnerEpoch('next');
            fixture.resources.adoptOwnerEpoch('owner');
            if (operation.state.value.failurePhase ==
                OperationPhase.syncFailed) {
              retirementFailure = operation.state.value.error;
            }
            if (isAuth) detail(8);
            fixture.resources.acceptFrame(
              isAuth
                  ? AcpAuthFrame(
                      _stamp('acp-auth', 1),
                      authSnapshot('replacement', 1, 8),
                    )
                  : AcpInstallFrame(
                      _stamp('acp-install', 1),
                      installSnapshot('replacement', 1),
                    ),
            );
            replacement = isAuth
                ? fixture.resources.acp.auth.value
                : fixture.resources.acp.install.value;
          }

          final operationListener = operation.state.watch((value) {
            if (boundary == 'receipt' && value.receipt != null) retire();
          });
          addTearDown(operationListener.cancel);
          final sourceListener = isAuth
              ? fixture.resources.acp.auth.watch((value) {
                  if (boundary == 'content' &&
                      value.stamp?.revision == 2 &&
                      !value.stale)
                    retire();
                })
              : fixture.resources.acp.install.watch((value) {
                  if (boundary == 'content' &&
                      value.stamp?.revision == 2 &&
                      !value.stale)
                    retire();
                });
          addTearDown(sourceListener.cancel);
          if (boundary == 'late reply') retire();
          final wireReceipt = StudioCommandReceipt(
            operationId: id,
            disposition: CommitDisposition.applied,
            targets: [_stamp(isAuth ? 'acp-auth' : 'acp-install', 2)],
            effect: EffectPoint.immediate,
            effective: true,
            durable: true,
          );
          if (isAuth) {
            authReply.complete(
              AcpAuthCommandReply(
                receipt: wireReceipt,
                snapshot: authSnapshot(isCancel ? 'target' : id.value, 2, 7),
              ),
            );
          } else {
            installReply.complete(
              AcpInstallCommandReply(
                receipt: wireReceipt,
                snapshot: installSnapshot(isCancel ? 'target' : id.value, 2),
              ),
            );
          }
          final error = await outcome;
          final state = operation.state.value;
          expect(state.receipt, isNotNull);
          expect(state.receipt!.operationId, id);
          expect(state.receipt!.targets, wireReceipt.targets);
          expect(state.receipt!.disposition, CommitDisposition.applied);
          expect((state.effective, state.durable), (true, true));
          if (boundary == 'healthy') {
            expect(error, isNull);
            expect(state.observed, isTrue);
            expect(state.failurePhase, isNull);
          } else {
            expect(retired, isTrue);
            expect(error, isA<StateError>());
            expect(state.observed, isFalse);
            expect(state.failurePhase, OperationPhase.syncFailed);
            operation.markObserved();
            expect(
              operation.state.value.observed,
              isFalse,
              reason: 'The board must retain the frozen owner qualification, not only the command tail',
            );
            expect(operation.state.value.error, same(state.error));
            if (retirementFailure != null)
              expect(state.error, same(retirementFailure));
            expect(
              isAuth
                  ? fixture.resources.acp.auth.value
                  : fixture.resources.acp.install.value,
              same(replacement),
            );
          }
          final domainsClosed = await fixture.resources.close(
            deadline: DateTime.now().add(const Duration(seconds: 1)),
          );
          expect(domainsClosed.complete, isTrue);
          final closed = await client.close(
            deadline: DateTime.now().add(const Duration(seconds: 1)),
          );
          expect(closed.complete, boundary == 'healthy');
          expect(
            closed.unresolved.any(
              (issue) => issue.owner == 'operation:${id.value}',
            ),
            boundary != 'healthy',
          );
          expect(
            fixture.budget.used(ResourceKind.pendingOperation),
            boundary == 'healthy' ? 0 : 1,
          );
        },
      );
    }
  }

  for (final isAuth in [true, false]) {
    test(
      'ACP lifecycle rejects an unsent ${isAuth ? 'auth' : 'install'} intent reentered during open',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.close);
        void detail(int connection) => fixture.resources.acceptFrame(
          AccountDetailFrame(
            _stamp('settings', connection),
            _acp,
            AcpAccountDetails(
              AcpAccountSettingsView(
                accountId: 'same',
                name: 'ACP',
                provider: AcpProviderView.antigravity,
                connectionRevision: connection,
              ),
            ),
          ),
        );
        if (isAuth) detail(7);
        var requests = 0;
        fixture.port.auth = (id, _, connection, _) async {
          requests++;
          return AcpAuthCommandReply(
            receipt: _receipt(id, resource: 'acp-auth'),
            snapshot: AcpAuthSnapshotView(
              revision: 2,
              updatedAt: 1,
              accounts: [
                AcpAuthAccountView(
                  accountId: 'same',
                  connectionRevision: connection,
                  state: AcpCheckingState(operationId: id.value),
                ),
              ],
            ),
          );
        };
        fixture.port.installStart = (id, _) async {
          requests++;
          return AcpInstallCommandReply(
            receipt: _receipt(id, resource: 'acp-install'),
            snapshot: AcpInstallSnapshotView(
              revision: 2,
              updatedAt: 1,
              installations: [
                AcpInstallEntryView(
                  provider: AcpProviderView.antigravity,
                  state: AcpResolvingState(operationId: id.value),
                ),
              ],
            ),
          );
        };
        fixture.port.onOpen = () {
          fixture.resources.adoptOwnerEpoch('next');
          fixture.resources.adoptOwnerEpoch('owner');
          if (isAuth) detail(8);
        };
        final error = await Future<Object?>.sync(
          () => isAuth
              ? fixture.resources.acp.check(_acp)
              : fixture.resources.acp.prepare(AcpProviderView.antigravity),
        ).then<Object?>((_) => null, onError: (Object error) => error);
        expect(error, isA<StateError>());
        expect(requests, 0);
        final state = fixture.board.operations.single;
        expect(state.failurePhase, OperationPhase.rejected);
        expect(state.receipt, isNull);
        expect(fixture.budget.used(ResourceKind.pendingOperation), 0);
      },
    );
  }

  for (final boundary in ['summaries', 'native close']) {
    test(
      'same-next owner preparation preserves new model and ACP responsibilities from $boundary while joining old work',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.close);
        fixture.resources.acceptFrame(_models(_native, 99));
        const untouched = NativeAccountIdentity('untouched');
        fixture.resources.acceptFrame(_models(untouched, 99));
        fixture.resources.acceptFrame(
          AccountDetailFrame(
            _stamp('settings', 99),
            untouched,
            _details(identity: untouched),
            modelConfiguration: AccountModelConfiguration(
              autoCompactLimits: const {'configured': 99},
            ),
          ),
        );
        final performanceCalls = <Completer<DelegationModelDetail>>[];
        fixture.port.modelDetail = (_) {
          final response = Completer<DelegationModelDetail>();
          performanceCalls.add(response);
          return response.future;
        };
        final oldPerformance = fixture.resources.models.performance(_model);
        oldPerformance.ignore();
        final syncCalls = <(OperationId, Completer<ModelSyncAdmission>)>[];
        fixture.port.syncModels = (_, id) {
          final response = Completer<ModelSyncAdmission>();
          syncCalls.add((id, response));
          return response.future;
        };
        final installCalls =
            <(OperationId, Completer<AcpInstallCommandReply>)>[];
        fixture.port.installStart = (id, _) {
          final response = Completer<AcpInstallCommandReply>();
          installCalls.add((id, response));
          return response.future;
        };
        var admitted = false;
        late Future<DelegationModelDetail> performance;
        late Future<ModelSyncAdmission> syncing;
        late Future<AcpInstallSnapshotView> preparing;
        void admit() {
          if (admitted) return;
          admitted = true;
          fixture.resources.acceptFrame(
            AccountSummariesFrame(_stamp('settings', 1, epoch: 'next'), [
              _summary(),
            ]),
          );
          fixture.resources.acceptFrame(
            AccountDetailFrame(
              _stamp('settings', 1, epoch: 'next'),
              _native,
              _details(name: 'Replacement'),
              modelConfiguration: AccountModelConfiguration(
                autoCompactLimits: const {'configured': 17},
              ),
            ),
          );
          fixture.resources.acceptFrame(_models(_native, 1, epoch: 'next'));
          performance = fixture.resources.models.performance(_model);
          performance.ignore();
          syncing = fixture.resources.models.sync(_native);
          syncing.ignore();
          preparing = fixture.resources.acp.prepare(
            AcpProviderView.antigravity,
          );
          preparing.ignore();
        }

        if (boundary == 'native close') {
          final demand = fixture.resources.accounts.observeSummaries();
          addTearDown(demand.release);
          final handle = fixture.port.handles[const AccountSummariesTarget()]!;
          await handle.reading.future;
          handle.onRequestClose = admit;
        } else {
          final listener = fixture.resources.accounts.state.watch((value) {
            if (value.stale) admit();
          });
          addTearDown(listener.cancel);
        }
        fixture.resources.adoptOwnerEpoch('next');
        final duplicatePerformance = fixture.resources.models.performance(
          _model,
        );
        duplicatePerformance.ignore();
        final duplicateSync = fixture.resources.models.sync(_native);
        duplicateSync.ignore();
        final duplicateInstall = fixture.resources.acp.prepare(
          AcpProviderView.antigravity,
        );
        duplicateInstall.ignore();
        final counts = (
          performanceCalls.length,
          syncCalls.length,
          installCalls.length,
        );
        final operations = fixture.board.operations.length;
        final aliasedOld = identical(performance, oldPerformance);
        final catalog = fixture.resources.models.state.value.accounts[_native]!;
        final configuration =
            fixture.resources.models.state.value.configurations[_native]!;
        final oldCatalog =
            fixture.resources.models.state.value.accounts[untouched]!;
        final oldConfiguration =
            fixture.resources.models.state.value.configurations[untouched]!;
        final oldDetail = fixture.resources.accounts.details(untouched).value;
        // Drain every possibly duplicated RPC before assertions; retain only the
        // intentional old request to prove real join rather than dropped ownership.
        for (final response in performanceCalls.skip(1)) {
          response.completeError(
            StateError('Scripted new performance failure'),
          );
        }
        if (aliasedOld) {
          performanceCalls.first.completeError(
            StateError('A new owner incorrectly reused the old request'),
          );
        }
        for (final (id, response) in syncCalls) {
          response.complete(
            ModelSyncAdmission(
              operationId: id,
              account: _native,
              queryGeneration: 5,
              joinedExisting: false,
            ),
          );
        }
        for (final (id, response) in installCalls) {
          response.complete(
            AcpInstallCommandReply(
              receipt: StudioCommandReceipt(
                operationId: id,
                disposition: CommitDisposition.applied,
                targets: [_stamp('acp-install', 1, epoch: 'next')],
                effect: EffectPoint.immediate,
                effective: true,
                durable: false,
              ),
              snapshot: AcpInstallSnapshotView(
                revision: 1,
                updatedAt: 1,
                installations: [
                  AcpInstallEntryView(
                    provider: AcpProviderView.antigravity,
                    state: AcpResolvingState(operationId: id.value),
                  ),
                ],
              ),
            ),
          );
        }
        await Future.wait([
          performance.then<void>((_) {}, onError: (Object _) {}),
          duplicatePerformance.then<void>((_) {}, onError: (Object _) {}),
          syncing.then<void>((_) {}),
          duplicateSync.then<void>((_) {}),
          preparing.then<void>((_) {}),
          duplicateInstall.then<void>((_) {}, onError: (Object _) {}),
        ]);
        final modelHandle =
            fixture.port.handles[const AccountModelsTarget(_native)]!;
        final installHandle = fixture.port.handles[const AcpInstallTarget()]!;
        final retained = (!modelHandle.closed, !installHandle.closed);
        fixture.resources.acceptFrame(
          AcpInstallFrame(
            _stamp('acp-install', 2, epoch: 'next'),
            const AcpInstallSnapshotView(
              revision: 2,
              updatedAt: 2,
              installations: [
                AcpInstallEntryView(
                  provider: AcpProviderView.antigravity,
                  state: AcpInstallIdleState(),
                ),
              ],
            ),
          ),
        );
        final retainedAfterIdle = !installHandle.closed;
        final closing = await fixture.resources.close(
          deadline: DateTime.now().add(const Duration(milliseconds: 100)),
        );
        if (!performanceCalls.first.isCompleted) {
          performanceCalls.first.completeError(
            StateError('Scripted old performance completion'),
          );
        }
        await oldPerformance.then<void>((_) {}, onError: (Object _) {});
        expect(admitted, isTrue);
        expect(
          aliasedOld,
          isFalse,
          reason: 'New-owner reads cannot reuse a retired request',
        );
        expect(identical(performance, duplicatePerformance), isTrue);
        expect(identical(syncing, duplicateSync), isTrue);
        expect(counts, (2, 1, 1));
        expect(
          operations,
          1,
          reason: 'A new ACP reservation must not be cleared by the old batch',
        );
        expect((catalog.loaded, configuration.loaded), (true, true));
        expect(configuration.value!.autoCompactLimits, {'configured': 17});
        expect(
          (oldCatalog.stale, oldConfiguration.stale, oldDetail.stale),
          (true, true, true),
          reason: 'Preserving a new target cannot leave untouched old targets ready',
        );
        expect(retained, (true, true));
        expect(retainedAfterIdle, isTrue);
        expect(
          closing.unresolved.any(
            (issue) => issue.owner == 'account-domain-command:0',
          ),
          isTrue,
          reason: 'The old performance Future must remain joined until its actual completion',
        );
      },
    );
  }

  test('same-next owner preparation preserves the new usage attempt and ready baseline across accounts notification', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final response = Completer<AccountUsageFrame>();
    const failure = StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'Scripted query rejection',
      retryable: false,
      correlationId: 'same-next-query',
    );
    var queries = 0;
    fixture.port.usage = (_) {
      queries++;
      return queries == 1 ? response.future : Future.error(failure);
    };
    var admitted = false;
    late AccountDemand visible;
    final listener = fixture.resources.accounts.state.watch((value) {
      if (admitted || !value.stale) return;
      admitted = true;
      fixture.resources.acceptFrame(
        AccountSummariesFrame(_stamp('settings', 1, epoch: 'next'), [
          _summary(),
        ]),
      );
      fixture.resources.acceptFrame(
        AccountUsageFrame(_stamp('account-usage', 1, epoch: 'next'), const [
          AccountUsageObservation(
            identity: _native,
            queryRevision: 1,
            revision: 1,
            phase: AccountUsagePhase.unchecked,
          ),
        ]),
      );
      visible = fixture.resources.usage.observeVisible();
    });
    addTearDown(listener.cancel);
    fixture.resources.adoptOwnerEpoch('next');
    addTearDown(visible.release);
    final ready = fixture.resources.usage.state.value;
    final query = fixture.resources.usage.refresh(_native);
    final failed = expectLater(query, throwsA(same(failure)));
    response.completeError(failure);
    await failed;
    fixture.resources.acceptFrame(
      AccountSummariesFrame(_stamp('settings', 2, epoch: 'next'), [_summary()]),
    );
    expect(admitted, isTrue);
    expect(
      queries,
      1,
      reason: 'A new owner attempt cannot be erased and automatically retried by the old invalidation',
    );
    expect((ready.loaded, ready.stale, ready.loading), (true, false, false));
    expect(fixture.resources.usage.queryFailures.value[_native], same(failure));
  });

  test('same-next first usage query cannot inherit the retired owner revision barrier', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    fixture.resources.acceptFrame(
      AccountUsageFrame(_stamp('account-usage', 99), const [
        AccountUsageObservation(
          identity: _native,
          queryRevision: 1,
          revision: 99,
          phase: AccountUsagePhase.succeeded,
        ),
      ]),
    );
    final response = Completer<AccountUsageFrame>();
    fixture.port.usage = (_) => response.future;
    late AccountDemand visible;
    var admitted = false;
    final listener = fixture.resources.accounts.state.watch((value) {
      if (admitted || !value.stale) return;
      admitted = true;
      fixture.resources.acceptFrame(
        AccountSummariesFrame(_stamp('settings', 1, epoch: 'next'), [
          _summary(),
        ]),
      );
      visible = fixture.resources.usage.observeVisible();
    });
    addTearDown(listener.cancel);
    fixture.resources.adoptOwnerEpoch('next');
    final query = fixture.resources.usage.refresh(_native);
    final failure = expectLater(query, throwsStateError);
    response.completeError(StateError('Unknown new-owner query outcome'));
    await failure;
    final handle = fixture.port.handles[const AccountUsageTarget()]!;
    final retainedBeforeTerminal = !handle.closed;
    await visible.release();
    final retainedWithoutDisplay = !handle.closed;
    fixture.resources.acceptFrame(
      AccountUsageFrame(_stamp('account-usage', 1, epoch: 'next'), const [
        AccountUsageObservation(
          identity: _native,
          queryRevision: 1,
          revision: 1,
          phase: AccountUsagePhase.succeeded,
        ),
      ]),
    );
    expect(admitted, isTrue);
    expect(retainedBeforeTerminal, isTrue);
    expect(
      retainedWithoutDisplay,
      isTrue,
      reason:
          'The new unknown outcome owns its demand independently of visibility',
    );
    expect(
      handle.closed,
      isTrue,
      reason: 'The new revision1 terminal settles the new query, not an old revision99 barrier',
    );
    expect(fixture.resources.usage.queryFailures.value, isEmpty);
    expect(fixture.resources.usage.state.value.loaded, isTrue);
  });

  test('reentrant model invalidation retains the replacement performance request and ready catalog', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    fixture.resources.acceptFrame(_models(_native, 99));
    final response = Completer<DelegationModelDetail>();
    var requests = 0;
    fixture.port.modelDetail = (_) {
      requests++;
      return response.future;
    };
    var replaced = false;
    late Future<DelegationModelDetail> nested;
    final listener = fixture.resources.models.state.watch((value) {
      if (!replaced && value.accounts[_native]?.stale == true) {
        replaced = true;
        fixture.resources.adoptOwnerEpoch('third');
        fixture.resources.acceptFrame(
          AccountModelsFrame(
            _stamp('model-catalog', 1, epoch: 'third'),
            _native,
            _models(_native, 1, label: 'replacement').catalog,
          ),
        );
        nested = fixture.resources.models.performance(_model);
        nested.ignore();
      }
    });
    addTearDown(listener.cancel);
    fixture.resources.adoptOwnerEpoch('next');
    final duplicate = fixture.resources.models.performance(_model);
    duplicate.ignore();
    final sameRequest = identical(duplicate, nested);
    response.completeError(StateError('Scripted detail failure'));
    await Future.wait([
      nested.then<void>((_) {}, onError: (Object _) {}),
      duplicate.then<void>((_) {}, onError: (Object _) {}),
    ]);
    expect(replaced, isTrue);
    expect(
      sameRequest,
      isTrue,
      reason: 'The old invalidation cannot clear a replacement request',
    );
    expect(requests, 1);
    expect(
      fixture.resources.models.state.value.accounts[_native]!.loaded,
      isTrue,
    );
    expect(
      fixture
          .resources
          .models
          .state
          .value
          .accounts[_native]!
          .value!
          .models
          .single
          .displayName,
      'replacement',
    );
  });

  test('reentrant usage failure reset cannot invalidate the replacement usage baseline', () {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    var replaced = false;
    final listener = fixture.resources.usage.queryFailures.watch((_) {
      if (replaced) return;
      replaced = true;
      fixture.resources.adoptOwnerEpoch('third');
      fixture.resources.acceptFrame(
        AccountSummariesFrame(_stamp('settings', 1, epoch: 'third'), [
          _summary(),
        ]),
      );
      fixture.resources.acceptFrame(
        AccountUsageFrame(_stamp('account-usage', 1, epoch: 'third'), const [
          AccountUsageObservation(
            identity: _native,
            queryRevision: 1,
            revision: 1,
            phase: AccountUsagePhase.succeeded,
          ),
        ]),
      );
    });
    addTearDown(listener.cancel);
    fixture.resources.adoptOwnerEpoch('next');
    final usage = fixture.resources.usage.state.value;
    expect(replaced, isTrue);
    expect((usage.loaded, usage.stale, usage.loading), (true, false, false));
    expect(usage.stamp, _stamp('account-usage', 1, epoch: 'third'));
    expect(usage.value![_native]!.phase, AccountUsagePhase.succeeded);
  });

  test('reentrant ACP auth invalidation cannot invalidate the replacement install baseline', () {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    var replaced = false;
    final listener = fixture.resources.acp.auth.watch((value) {
      if (replaced || !value.stale) return;
      replaced = true;
      fixture.resources.adoptOwnerEpoch('third');
      fixture.resources.acceptFrame(
        AcpAuthFrame(
          _stamp('acp-auth', 1, epoch: 'third'),
          const AcpAuthSnapshotView(revision: 1, updatedAt: 1),
        ),
      );
      fixture.resources.acceptFrame(
        AcpInstallFrame(
          _stamp('acp-install', 1, epoch: 'third'),
          const AcpInstallSnapshotView(revision: 1, updatedAt: 1),
        ),
      );
    });
    addTearDown(listener.cancel);
    fixture.resources.adoptOwnerEpoch('next');
    expect(replaced, isTrue);
    final auth = fixture.resources.acp.auth.value;
    final install = fixture.resources.acp.install.value;
    expect((auth.loaded, auth.stale, auth.loading), (true, false, false));
    expect(
      (install.loaded, install.stale, install.loading),
      (true, false, false),
    );
    expect(install.stamp, _stamp('acp-install', 1, epoch: 'third'));
  });

  test('reentrant ACP operation invalidation retains replacement reservations and business observations', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final calls = <(OperationId, Completer<AcpInstallCommandReply>)>[];
    fixture.port.installStart = (operation, _) {
      final response = Completer<AcpInstallCommandReply>();
      calls.add((operation, response));
      return response.future;
    };
    final old = fixture.resources.acp.prepare(AcpProviderView.antigravity);
    old.ignore();
    final operation = fixture.board.lookup(calls.single.$1)!;
    var replaced = false;
    late Future<AcpInstallSnapshotView> replacement;
    final listener = operation.state.watch((value) {
      if (replaced || value.phase != OperationPhase.unknownOutcome) return;
      replaced = true;
      fixture.resources.adoptOwnerEpoch('third');
      replacement = fixture.resources.acp.prepare(AcpProviderView.antigravity);
      replacement.ignore();
    });
    addTearDown(listener.cancel);
    fixture.resources.adoptOwnerEpoch('next');
    final duplicate = fixture.resources.acp.prepare(
      AcpProviderView.antigravity,
    );
    duplicate.ignore();
    final requestsBeforeCompletion = calls.length;
    final operationsAfterDuplicate = fixture.board.operations.length;
    // Complete every admitted RPC so failed assertions never leave a live task.
    for (final (id, response) in calls.toList()) {
      response.complete(
        AcpInstallCommandReply(
          receipt: StudioCommandReceipt(
            operationId: id,
            disposition: CommitDisposition.applied,
            targets: [_stamp('acp-install', 1, epoch: 'third')],
            effect: EffectPoint.immediate,
            effective: true,
            durable: false,
          ),
          snapshot: AcpInstallSnapshotView(
            revision: 1,
            updatedAt: 1,
            installations: [
              AcpInstallEntryView(
                provider: AcpProviderView.antigravity,
                state: AcpResolvingState(operationId: id.value),
              ),
            ],
          ),
        ),
      );
    }
    await old.then<void>((_) {}, onError: (Object _) {});
    await replacement;
    await duplicate.then<void>((_) {}, onError: (Object _) {});
    expect(replaced, isTrue);
    expect(
      requestsBeforeCompletion,
      2,
      reason: 'A retired cleanup cannot remove the replacement reservation or retained business',
    );
    expect(
      operationsAfterDuplicate,
      2,
      reason: 'The replacement reservation must reject duplicates before allocating another operation',
    );
    final handle = fixture.port.handles[const AcpInstallTarget()]!;
    expect(handle.closed, isFalse);
    fixture.resources.acceptFrame(
      AcpInstallFrame(
        _stamp('acp-install', 2, epoch: 'third'),
        const AcpInstallSnapshotView(
          revision: 2,
          updatedAt: 2,
          installations: [
            AcpInstallEntryView(
              provider: AcpProviderView.antigravity,
              state: AcpInstallIdleState(),
            ),
          ],
        ),
      ),
    );
    expect(
      handle.closed,
      isFalse,
      reason: 'Unrelated idle content cannot settle the retained replacement business',
    );
  });

  test('reentrant detail reduction cannot restore old configuration or target clocks after an owner incarnation changes', () {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    var replaced = false;
    final listener = fixture.resources.accounts.details(_native).watch((value) {
      if (!replaced && value.stamp?.revision == 99) {
        replaced = true;
        fixture.resources.adoptOwnerEpoch('next');
        fixture.resources.adoptOwnerEpoch('owner');
        fixture.resources.acceptFrame(
          AccountDetailFrame(
            _stamp('settings', 1),
            _native,
            _details(name: 'replacement'),
            modelConfiguration: AccountModelConfiguration(
              autoCompactLimits: const {'configured': 17},
            ),
          ),
        );
      }
    });
    addTearDown(listener.cancel);
    fixture.resources.acceptFrame(
      AccountDetailFrame(
        _stamp('settings', 99),
        _native,
        _details(name: 'retired'),
        modelConfiguration: AccountModelConfiguration(
          autoCompactLimits: const {'configured': 999},
        ),
      ),
    );
    expect(replaced, isTrue);
    expect(
      fixture
          .resources
          .models
          .state
          .value
          .configurations[_native]!
          .value!
          .autoCompactLimits,
      {'configured': 17},
    );
    expect(fixture.coordinator.stamp, _stamp('settings', 1));
    fixture.resources.acceptFrame(
      AccountDetailFrame(
        _stamp('settings', 2),
        _native,
        _details(name: 'current'),
        modelConfiguration: AccountModelConfiguration(
          autoCompactLimits: const {'configured': 18},
        ),
      ),
    );
    expect(
      (fixture.resources.accounts.details(_native).value.value!
              as NativeAccountDetails)
          .name,
      'current',
      reason: 'The retired outer frame must not restore its high target clock',
    );
    expect(
      fixture
          .resources
          .models
          .state
          .value
          .configurations[_native]!
          .value!
          .autoCompactLimits,
      {'configured': 18},
    );
    expect(fixture.coordinator.stamp, _stamp('settings', 2));
  });

  test('authorized runtime owner switch invalidates old content and ignores late owners and receipts', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    fixture.resources.acceptFrame(
      AccountDetailFrame(
        _stamp('settings', 99),
        _native,
        _details(name: 'old'),
      ),
    );
    final display = fixture.resources.accounts.observeDetails(_native);
    addTearDown(display.release);
    final invoked = Completer<OperationId>();
    final response = Completer<SettingsCommandReply>();
    fixture.port.compact = (_, _, operation) {
      invoked.complete(operation);
      return response.future;
    };
    final saving = fixture.resources.models.setAutoCompact(
      _model,
      AutoCompactIntent.set(123),
    );
    final operation = await invoked.future;
    final oldHandle = fixture.port.handles[const AccountDetailTarget(_native)]!;
    fixture.resources.adoptOwnerEpoch('next');
    final stale = fixture.resources.accounts.details(_native).value;
    expect(stale.stale, isTrue);
    expect(stale.loaded, isFalse);
    expect(oldHandle.requested.isCompleted, isTrue);
    fixture.resources.acceptFrame(
      AccountDetailFrame(
        _stamp('settings', 1, epoch: 'next'),
        _native,
        _details(name: 'new'),
      ),
    );
    fixture.resources.acceptFrame(
      AccountModelsFrame(
        _stamp('model-catalog', 1, epoch: 'next'),
        _native,
        _models(_native, 1).catalog,
      ),
    );
    fixture.resources.acceptFrame(
      AccountDetailFrame(
        _stamp('settings', 999),
        _native,
        _details(name: 'late old'),
      ),
    );
    fixture.resources.acceptFrame(
      AccountDetailFrame(
        _stamp('settings', 999, epoch: 'unannounced'),
        _native,
        _details(name: 'unauthorized'),
      ),
    );
    response.complete(
      SettingsCommandReply(
        snapshot: SettingsStateSnapshot(revision: 100),
        receipt: _receipt(operation, settings: 100),
        accountFrames: [
          AccountDetailFrame(
            _stamp('settings', 100),
            _native,
            _details(name: 'old response'),
          ),
        ],
      ),
    );
    await expectLater(saving, throwsA(isA<Exception>()));
    expect(
      (fixture.resources.accounts.details(_native).value.value
              as NativeAccountDetails)
          .name,
      'new',
    );
    expect(fixture.resources.accounts.details(_native).value.loaded, isTrue);
    expect(fixture.board.lookup(operation)!.state.value.observed, isFalse);
    expect(
      fixture.board.lookup(operation)!.state.value.phase,
      OperationPhase.syncFailed,
    );
    expect(fixture.coordinator.stamp!.ownerEpoch, 'next');
    expect(fixture.coordinator.stamp!.revision, 1);
  });
  test('ACP idle baseline before install admission cannot release the new business observation', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final response = Completer<AcpInstallCommandReply>();
    late OperationId operation;
    fixture.port.installStart = (id, _) {
      operation = id;
      return response.future;
    };
    final preparing = fixture.resources.acp.prepare(
      AcpProviderView.antigravity,
    );
    fixture.resources.acceptFrame(
      AcpInstallFrame(
        _stamp('acp-install', 1),
        const AcpInstallSnapshotView(
          revision: 1,
          updatedAt: 1,
          installations: [
            AcpInstallEntryView(
              provider: AcpProviderView.antigravity,
              state: AcpInstallIdleState(),
            ),
          ],
        ),
      ),
    );
    final handle = fixture.port.handles[const AcpInstallTarget()]!;
    response.complete(
      AcpInstallCommandReply(
        receipt: _receipt(operation, settings: 2, resource: 'acp-install'),
        snapshot: AcpInstallSnapshotView(
          revision: 2,
          updatedAt: 1,
          installations: [
            AcpInstallEntryView(
              provider: AcpProviderView.antigravity,
              state: AcpResolvingState(operationId: operation.value),
            ),
          ],
        ),
      ),
    );
    await preparing;
    expect(
      handle.requested.isCompleted,
      isFalse,
      reason: 'An old idle baseline is not this operation terminal',
    );
    expect(fixture.budget.used(ResourceKind.observer), greaterThan(0));
  });

  test('ACP old auth terminal before start admission cannot release its operation observation', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    fixture.resources.acceptFrame(
      AccountDetailFrame(
        _stamp('settings', 2),
        _acp,
        AcpAccountDetails(
          const AcpAccountSettingsView(
            accountId: 'same',
            name: 'ACP',
            provider: AcpProviderView.antigravity,
            connectionRevision: 7,
          ),
        ),
      ),
    );
    final invoked = Completer<OperationId>();
    final response = Completer<AcpAuthCommandReply>();
    fixture.port.auth = (id, _, _, _) {
      invoked.complete(id);
      return response.future;
    };
    final checking = fixture.resources.acp.check(_acp);
    final operation = await invoked.future;
    fixture.resources.acceptFrame(
      AcpAuthFrame(
        _stamp('acp-auth', 1),
        const AcpAuthSnapshotView(
          revision: 1,
          updatedAt: 1,
          accounts: [
            AcpAuthAccountView(
              accountId: 'same',
              connectionRevision: 7,
              state: AcpVerifiedState(checkedAt: 1, server: null),
            ),
          ],
        ),
      ),
    );
    final handle = fixture.port.handles[const AcpAuthTarget()]!;
    response.complete(
      AcpAuthCommandReply(
        receipt: _receipt(operation, settings: 2, resource: 'acp-auth'),
        snapshot: AcpAuthSnapshotView(
          revision: 2,
          updatedAt: 1,
          accounts: [
            AcpAuthAccountView(
              accountId: 'same',
              connectionRevision: 7,
              state: AcpCheckingState(operationId: operation.value),
            ),
          ],
        ),
      ),
    );
    await checking;
    expect(
      handle.requested.isCompleted,
      isFalse,
      reason: 'A previous verified baseline cannot conclude the pending check',
    );
    expect(fixture.budget.used(ResourceKind.observer), greaterThan(0));
  });

  test('model sync admissions do not merge across a changed canonical query generation', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    AccountModelsFrame catalog(int revision, int generation) =>
        AccountModelsFrame(
          _stamp('model-catalog', revision),
          _native,
          AccountModelCatalog(
            identity: _native,
            models: _models(_native, revision).catalog!.models,
            status: ModelCatalogStatusView(
              supported: true,
              queryGeneration: generation,
            ),
          ),
        );
    fixture.resources.acceptFrame(catalog(1, 1));
    final pending = <(OperationId, Completer<ModelSyncAdmission>)>[];
    fixture.port.syncModels = (_, operation) {
      final completion = Completer<ModelSyncAdmission>();
      pending.add((operation, completion));
      return completion.future;
    };
    final first = fixture.resources.models.sync(_native);
    fixture.resources.acceptFrame(catalog(2, 2));
    final second = fixture.resources.models.sync(_native);
    pending[0].$2.complete(
      ModelSyncAdmission(
        operationId: pending[0].$1,
        account: _native,
        queryGeneration: 1,
        joinedExisting: false,
      ),
    );
    await first;
    final third = fixture.resources.models.sync(_native);
    for (final (operation, completion) in pending.skip(1)) {
      completion.complete(
        ModelSyncAdmission(
          operationId: operation,
          account: _native,
          queryGeneration: 2,
          joinedExisting: false,
        ),
      );
    }
    final current = await second;
    await third;
    expect(identical(first, second), isFalse);
    expect(
      identical(second, third),
      isTrue,
      reason: 'Old completion cannot remove the current generation entry',
    );
    expect(pending, hasLength(2));
    expect(current.queryGeneration, 2);
  });

  test('summary demand is lightweight and Native/ACP equal strings remain distinct targets', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final accounts = fixture.resources.accounts;
    final demand = accounts.observeSummaries();
    fixture.resources.acceptFrame(
      AccountSummariesFrame(_stamp('settings', 2), [
        _summary(),
        const AccountSummary(
          identity: _acp,
          name: 'ACP',
          isDefault: false,
          capabilities: AccountCapabilities(
            setDefault: false,
            edit: true,
            remove: true,
            queryUsage: false,
            syncModels: false,
            editModels: false,
            acpAuth: true,
          ),
        ),
      ]),
    );
    fixture.resources.acceptFrame(
      AccountDetailFrame(_stamp('settings', 2), _native, _details()),
    );
    fixture.resources.acceptFrame(
      AccountDetailFrame(
        _stamp('settings', 2),
        _acp,
        AcpAccountDetails(
          const AcpAccountSettingsView(
            accountId: 'same',
            name: 'ACP',
            provider: AcpProviderView.antigravity,
            connectionRevision: 7,
          ),
        ),
      ),
    );
    expect(accounts.state.value.accounts.map((item) => item.identity), [
      _native,
      _acp,
    ]);
    expect(accounts.details(_native).value.value, isA<NativeAccountDetails>());
    expect(accounts.details(_acp).value.value, isA<AcpAccountDetails>());
    expect(fixture.port.opens, [const AccountSummariesTarget()]);
    expect(fixture.resources.models.state.value.accounts, isEmpty);
    await demand.release();
  });

  test('target and source barriers reject unrelated high clocks and preserve newer intent', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final invoked = Completer<void>();
    final reply = Completer<SettingsCommandReply>();
    fixture.port.compact = (revision, intent, operation) {
      expect(revision, 1);
      expect((intent as SetAutoCompactLimit).limit, 12345);
      invoked.complete();
      return reply.future;
    };
    final saving = fixture.resources.models.setAutoCompact(
      _model,
      AutoCompactIntent.set(12345),
    );
    await invoked.future;
    final operation = fixture.board.operations.single;
    final newer = fixture.board.begin(target: operation.target);
    final other = const NativeAccountIdentity('other');
    fixture.resources.acceptFrame(
      AccountDetailFrame(
        _stamp('settings', 99),
        other,
        _details(identity: other),
      ),
    );
    fixture.resources.acceptFrame(_models(other, 100));
    fixture.board.observe(_stamp('settings', 999));
    reply.complete(
      SettingsCommandReply(
        snapshot: SettingsStateSnapshot(revision: 5),
        receipt: _receipt(operation.id, settings: 5, catalog: 8),
        accountFrames: [
          AccountDetailFrame(_stamp('settings', 5), _native, _details()),
        ],
      ),
    );
    final accepted = await saving;
    expect(accepted.observed, isFalse);
    expect(accepted.durable, isTrue);
    expect(accepted.effective, isFalse);
    fixture.resources.acceptFrame(_models(_native, 7));
    expect(fixture.board.lookup(operation.id)!.state.value.observed, isFalse);
    fixture.resources.acceptFrame(_models(_native, 8));
    expect(fixture.board.lookup(operation.id)!.state.value.observed, isTrue);
    expect(fixture.board.latest(operation.target)!.id, newer.id);
    expect(
      fixture
          .resources
          .models
          .state
          .value
          .accounts[_native]!
          .value!
          .models
          .single
          .displayName,
      'Effective',
    );
    expect(
      fixture.port.readCalls,
      isEmpty,
      reason:
          'Actual receipt target content does not require bootstrap/readback',
    );
    newer.reject(StateError('Test newer intent cancelled before admission'));
  });

  test('CAS retry refreshes only targets and replays frozen patch, not a stale account card', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    fixture.port.reads[const AccountDetailTarget(_native)] = AccountDetailFrame(
      _stamp('settings', 4),
      _native,
      _details(name: 'Concurrent name'),
    );
    fixture.port.reads[const AccountModelsTarget(_native)] = _models(
      _native,
      7,
      label: 'Concurrent model',
    );
    final calls = <(int, PatchAccountCommand, OperationId)>[];
    fixture.port.patch = (revision, command, operation) async {
      calls.add((revision, command, operation));
      if (calls.length == 1)
        throw const StudioFailure(
          code: StudioFailureCode.staleRevision,
          message: 'stale',
          retryable: true,
          correlationId: 'test',
        );
      return SettingsCommandReply(
        snapshot: SettingsStateSnapshot(revision: 5),
        receipt: _receipt(operation, settings: 5),
        accountFrames: [
          AccountDetailFrame(
            _stamp('settings', 5),
            _native,
            _details(name: 'New name'),
          ),
        ],
      );
    };
    const command = PatchAccountCommand(
      identity: _native,
      name: AccountTextPatch.set('New name'),
    );
    final result = await fixture.resources.accounts.patch(command);
    expect(calls.map((call) => call.$1), [1, 4]);
    expect(calls.every((call) => identical(call.$2, command)), isTrue);
    expect(calls.first.$3, calls.last.$3);
    expect(command.baseUrl, isA<AccountTextKeep>());
    expect(command.customModels, isA<AccountModelsKeep>());
    expect(command.secret.action, AccountSecretAction.preserve);
    expect(result.observed, isTrue);
    expect(
      fixture
          .resources
          .models
          .state
          .value
          .accounts[_native]!
          .value!
          .models
          .single
          .displayName,
      'Concurrent model',
    );
    expect(fixture.port.readCalls.toSet(), {
      const AccountDetailTarget(_native),
      const AccountModelsTarget(_native),
    });
  });

  test('usage identity dedup, exact money and failure last-good stay independent of noCharge', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final pending = <Completer<AccountUsageFrame>>[];
    fixture.port.usage = (identity) {
      expect(identity, _native);
      final query = Completer<AccountUsageFrame>();
      pending.add(query);
      return query.future;
    };
    final usage = fixture.resources.usage;
    final first = usage.refresh(_native);
    final duplicate = usage.refresh(_native);
    expect(identical(first, duplicate), isTrue);
    fixture.resources.acceptFrame(
      AccountSummariesFrame(_stamp('settings', 2), [_summary(query: 2)]),
    );
    final second = usage.refresh(_native);
    expect(pending, hasLength(2));
    final success = AccountUsageSuccess(
      checkedAt: 12,
      value: AccountBalance(
        available: true,
        balances: const [
          AccountMoneyBalance(
            currency: 'USD',
            total: '123456789.0000000001',
            granted: '0.0000000001',
            toppedUp: '123456789',
          ),
          AccountMoneyBalance(
            currency: 'CNY',
            total: '0.03',
            granted: '0.01',
            toppedUp: '0.02',
          ),
        ],
      ),
    );
    pending[1].complete(
      AccountUsageFrame(_stamp('account-usage', 8), [
        AccountUsageObservation(
          identity: _native,
          queryRevision: 2,
          revision: 8,
          phase: AccountUsagePhase.succeeded,
          lastGood: success,
        ),
      ]),
    );
    await second;
    pending[0].complete(
      AccountUsageFrame(_stamp('account-usage', 9), [
        const AccountUsageObservation(
          identity: _native,
          queryRevision: 1,
          revision: 9,
          phase: AccountUsagePhase.failed,
        ),
      ]),
    );
    await first;
    // Old-query complete frames cannot delete the current query's value.
    expect(usage.state.value.value![_native]!.queryRevision, 2);
    fixture.resources.acceptFrame(
      AccountUsageFrame(_stamp('account-usage', 10), [
        AccountUsageObservation(
          identity: _native,
          queryRevision: 2,
          revision: 10,
          phase: AccountUsagePhase.failed,
          failure: const AccountUsageFailure(
            code: AccountUsageFailureCode.query,
            retryable: true,
          ),
          lastGood: success,
        ),
      ]),
    );
    final observed = usage.state.value.value![_native]!;
    final balance = observed.lastGood!.value as AccountBalance;
    expect(
      balance.balances.map(
        (value) => (value.currency, value.total, value.granted, value.toppedUp),
      ),
      [
        ('USD', '123456789.0000000001', '0.0000000001', '123456789'),
        ('CNY', '0.03', '0.01', '0.02'),
      ],
    );
    expect(observed.phase, AccountUsagePhase.failed);
    expect(
      fixture.resources.accounts.state.value.account(_native)!.billingKind,
      BillingKind.noCharge,
    );
    final demand = usage.observeVisible();
    expect(
      pending,
      hasLength(2),
      reason: 'Failed is attempted; visibility must not loop',
    );
    await demand.release();
    fixture.resources.acceptFrame(
      AccountSummariesFrame(_stamp('settings', 3), []),
    );
    expect(usage.state.value.value, isEmpty);

    // The port supplies owner facts, not client scheduling or classification.
    // Remote query capability must not prevent a local Unsupported check.
    const added = NativeAccountIdentity('unsupported-added');
    const missing = NativeAccountIdentity('quota-without-key');
    final queries = <(NativeAccountIdentity, int)>[];
    final replies = <Completer<AccountUsageFrame>>[];
    fixture.port.usage = (identity) {
      queries.add((
        identity,
        fixture.resources.accounts.state.value
            .account(identity)!
            .usageQueryRevision!,
      ));
      final reply = Completer<AccountUsageFrame>();
      replies.add(reply);
      return reply.future;
    };
    final unsupportedAccount = _summary(
      query: 3,
      queryUsage: false,
      credentialReady: false,
    );
    final addedAccount = _summary(identity: added, queryUsage: false);
    final missingAccount = _summary(identity: missing, credentialReady: false);
    void summaries(int revision, List<AccountSummary> values) {
      fixture.resources.acceptFrame(
        AccountSummariesFrame(_stamp('settings', revision), values),
      );
    }

    summaries(4, [unsupportedAccount]);
    expect(queries, isEmpty, reason: 'Hidden summaries do not start checks');
    var visible = usage.observeVisible();
    addTearDown(() => visible.release());
    expect(
      queries,
      [(_native, 3)],
      reason:
          'First visibility must classify even without remote query capability',
    );
    final initial = usage.refresh(_native);
    expect(identical(initial, usage.refresh(_native)), isTrue);
    expect(queries, [
      (_native, 3),
    ], reason: 'Manual refresh joins automatic work');
    const unsupported = AccountUsageObservation(
      identity: _native,
      queryRevision: 3,
      revision: 1,
      phase: AccountUsagePhase.unsupported,
      operationId: 'local-unsupported',
      checkedAt: 20,
    );
    replies[0].complete(
      AccountUsageFrame(_stamp('account-usage', 11), const [unsupported]),
    );
    await initial;
    expect(usage.state.value.value![_native], same(unsupported));
    expect(usage.queryFailures.value, isEmpty);
    await visible.release();
    visible = usage.observeVisible();
    expect(queries, [
      (_native, 3),
    ], reason: 'Reopening does not repeat a terminal check');

    // Config commits can publish the usage baseline before the new summary.
    fixture.resources.acceptFrame(
      AccountUsageFrame(_stamp('account-usage', 12), const [
        unsupported,
        AccountUsageObservation(
          identity: added,
          queryRevision: 1,
          revision: 0,
          phase: AccountUsagePhase.unchecked,
        ),
      ]),
    );
    expect(usage.state.value.value, isNot(contains(added)));
    expect(queries, [(_native, 3)]);
    summaries(5, [unsupportedAccount, addedAccount]);
    expect(
      queries,
      [(_native, 3), (added, 1)],
      reason: 'The arriving summary starts only its previously unseen identity',
    );
    final addition = usage.refresh(added);
    expect(identical(addition, usage.refresh(added)), isTrue);
    const addedUnsupported = AccountUsageObservation(
      identity: added,
      queryRevision: 1,
      revision: 2,
      phase: AccountUsagePhase.unsupported,
      operationId: 'added-unsupported',
      checkedAt: 21,
    );
    replies[1].complete(
      AccountUsageFrame(_stamp('account-usage', 13), const [
        unsupported,
        addedUnsupported,
      ]),
    );
    await addition;
    expect(usage.state.value.value![added], same(addedUnsupported));
    expect(usage.state.value.value![_native], same(unsupported));

    summaries(6, [unsupportedAccount, addedAccount, missingAccount]);
    expect(queries, [(_native, 3), (added, 1), (missing, 1)]);
    final missingCheck = usage.refresh(missing);
    const missingCredential = AccountUsageObservation(
      identity: missing,
      queryRevision: 1,
      revision: 2,
      phase: AccountUsagePhase.missingCredential,
      operationId: 'missing-credential',
      checkedAt: 22,
    );
    replies[2].complete(
      AccountUsageFrame(_stamp('account-usage', 14), const [
        unsupported,
        addedUnsupported,
        missingCredential,
      ]),
    );
    await missingCheck;
    expect(usage.state.value.value![missing], same(missingCredential));
    expect(usage.queryFailures.value, isEmpty);
    expect(
      fixture.resources.accounts.state.value
          .account(_native)!
          .capabilities
          .queryUsage,
      isFalse,
      reason: 'Classification does not change the manual-refresh capability',
    );
    expect(
      fixture.resources.accounts.state.value.account(_native)!.billingKind,
      BillingKind.noCharge,
    );

    await visible.release();
    summaries(7, [
      unsupportedAccount,
      _summary(identity: added, query: 2, queryUsage: false),
      missingAccount,
    ]);
    expect(queries, [(_native, 3), (added, 1), (missing, 1)]);
    visible = usage.observeVisible();
    expect(
      queries,
      [(_native, 3), (added, 1), (missing, 1), (added, 2)],
      reason: 'Visibility resumes only the changed query identity, not its siblings',
    );
    final deletedCheck = usage.refresh(added);
    summaries(8, [unsupportedAccount, missingAccount]);
    replies[3].complete(
      AccountUsageFrame(_stamp('account-usage', 15), const [
        unsupported,
        missingCredential,
        AccountUsageObservation(
          identity: added,
          queryRevision: 2,
          revision: 2,
          phase: AccountUsagePhase.unsupported,
        ),
      ]),
    );
    await deletedCheck;
    expect(usage.state.value.value, isNot(contains(added)));
    expect(usage.state.value.value![_native], same(unsupported));
    expect(usage.state.value.value![missing], same(missingCredential));
    expect(queries, [(_native, 3), (added, 1), (missing, 1), (added, 2)]);
  });

  test('late open and failed native close keep the exact owner and permit for retry', () async {
    final fixture = _Fixture();
    fixture.port.lateOpen = Completer<AccountDomainObservation>();
    final demand = fixture.resources.accounts.observeDetails(_native);
    final releasing = demand.release();
    final releaseFailure = expectLater(releasing, throwsStateError);
    final early = await fixture.resources.close(deadline: DateTime.now());
    expect(early.complete, isFalse);
    expect(fixture.budget.used(ResourceKind.observer), 1);
    final handle = _Handle()..closeFailures = 1;
    fixture.port.lateOpen!.complete(handle);
    await releaseFailure;
    expect(handle.requested.isCompleted, isTrue);
    expect(fixture.budget.used(ResourceKind.observer), 1);
    final retried = await fixture.resources.close(
      deadline: DateTime.now().add(const Duration(seconds: 1)),
    );
    expect(retried.complete, isTrue);
    expect(handle.closeCalls, 2);
    expect(fixture.port.opens, [const AccountDetailTarget(_native)]);
    expect(fixture.budget.used(ResourceKind.observer), 0);
    await fixture.coordinator.close();
  });

  test(
    'ACP cancellation reaches its lane while start admission is still pending',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      fixture.resources.acceptFrame(
        AccountDetailFrame(
          _stamp('settings', 2),
          _acp,
          AcpAccountDetails(
            const AcpAccountSettingsView(
              accountId: 'same',
              name: 'ACP',
              provider: AcpProviderView.antigravity,
              connectionRevision: 7,
            ),
          ),
        ),
      );
      final started = Completer<OperationId>();
      final startReply = Completer<AcpAuthCommandReply>();
      fixture.port.auth = (operation, account, revision, action) {
        expect((account, revision), ('same', 7));
        started.complete(operation);
        return startReply.future;
      };
      fixture.port.cancel = (operation, account, target) async {
        expect(target, await started.future);
        return AcpAuthCommandReply(
          receipt: _receipt(operation, settings: 4, resource: 'acp-auth'),
          snapshot: AcpAuthSnapshotView(
            revision: 4,
            updatedAt: 1,
            accounts: [
              AcpAuthAccountView(
                accountId: account,
                connectionRevision: 7,
                state: AcpCancellingState(operationId: target.value),
              ),
            ],
          ),
        );
      };
      final start = fixture.resources.acp.check(_acp);
      final operation = await started.future;
      fixture.resources.acceptFrame(
        AcpAuthFrame(
          _stamp('acp-auth', 3),
          AcpAuthSnapshotView(
            revision: 3,
            updatedAt: 1,
            accounts: [
              AcpAuthAccountView(
                accountId: 'same',
                connectionRevision: 7,
                state: AcpCheckingState(operationId: operation.value),
              ),
            ],
          ),
        ),
      );
      final cancelled = await fixture.resources.acp.cancelAuth(_acp);
      expect(cancelled.revision, 4);
      expect(startReply.isCompleted, isFalse);
      startReply.complete(
        AcpAuthCommandReply(
          receipt: _receipt(operation, settings: 3, resource: 'acp-auth'),
          snapshot: AcpAuthSnapshotView(
            revision: 3,
            updatedAt: 1,
            accounts: [
              AcpAuthAccountView(
                accountId: 'same',
                connectionRevision: 7,
                state: AcpCheckingState(operationId: operation.value),
              ),
            ],
          ),
        ),
      );
      await start;
      expect(fixture.resources.acp.auth.value.value!.revision, 4);
    },
  );

  test('model sync admission deduplicates and retains demand until its exact query generation settles', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    fixture.resources.acceptFrame(_models(_native, 1));
    var calls = 0;
    fixture.port.syncModels = (identity, operation) async {
      calls++;
      return ModelSyncAdmission(
        operationId: operation,
        account: identity,
        queryGeneration: 5,
        joinedExisting: false,
      );
    };
    final first = fixture.resources.models.sync(_native);
    final duplicate = fixture.resources.models.sync(_native);
    expect(identical(first, duplicate), isTrue);
    final admission = await first;
    expect(calls, 1);
    expect(
      fixture.board.operations,
      isEmpty,
      reason: 'No synthetic commit/effect/durability is created for query acceptance',
    );
    final handle = fixture.port.handles[const AccountModelsTarget(_native)]!;
    AccountModelsFrame terminal(int revision, int generation) =>
        AccountModelsFrame(
          _stamp('model-catalog', revision),
          _native,
          AccountModelCatalog(
            identity: _native,
            models: _models(_native, revision).catalog!.models,
            status: ModelCatalogStatusView(
              supported: true,
              queryGeneration: generation,
              operationId: admission.operationId.value,
              error: const ModelCatalogErrorView(
                ModelCatalogFailure.taskFailed,
              ),
            ),
          ),
        );
    fixture.resources.acceptFrame(terminal(8, 4));
    expect(
      handle.requested.isCompleted,
      isFalse,
      reason: 'Same operation string is insufficient without the frozen query generation',
    );
    final drained = Completer<void>();
    final availability = fixture.budget.watchAvailability(
      ResourceKind.observer,
      () {
        if (fixture.budget.used(ResourceKind.observer) == 0 &&
            !drained.isCompleted)
          drained.complete();
      },
    );
    fixture.resources.acceptFrame(terminal(9, 5));
    await drained.future;
    availability.cancel();
    expect(
      fixture
          .resources
          .models
          .state
          .value
          .accounts[_native]!
          .value!
          .models
          .single
          .modelId,
      'configured',
    );
    expect(
      fixture
          .resources
          .models
          .state
          .value
          .accounts[_native]!
          .value!
          .status
          .error!
          .kind,
      ModelCatalogFailure.taskFailed,
    );
  });

  test(
    'application assemblies share neither canonical values nor CAS ordering',
    () async {
      final first = _Fixture(owner: 'first');
      final second = _Fixture(owner: 'second');
      addTearDown(first.close);
      addTearDown(second.close);
      first.resources.acceptFrame(
        AccountDetailFrame(
          _stamp('settings', 10),
          _native,
          _details(name: 'Only first'),
        ),
      );
      first.resources.acceptFrame(_models(_native, 30));
      expect(second.resources.accounts.details(_native).value.loaded, isFalse);
      expect(second.resources.models.state.value.accounts, isEmpty);
      expect(
        (first.coordinator.stamp!.revision, second.coordinator.stamp!.revision),
        (10, 1),
      );
      final blocked = Completer<void>();
      final entered = Completer<void>();
      final firstWrite = first.coordinator.enqueue(() async {
        entered.complete();
        await blocked.future;
      });
      await entered.future;
      var secondRan = false;
      await second.coordinator.enqueue(() async {
        secondRan = true;
      });
      expect(secondRan, isTrue);
      blocked.complete();
      await firstWrite;
      expect(
        first.board.operations.where(
          (value) => value.phase == OperationPhase.rejected,
        ),
        isEmpty,
      );
    },
  );
}
