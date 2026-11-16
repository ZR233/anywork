import 'dart:async';
import 'dart:math';

import '../../../accounts.dart';
import '../../../accounts_ports.dart';
import '../../../account_usage.dart';
import '../../../acp.dart';
import '../../../acp_ports.dart';
import '../../../model_directory.dart';
import '../../../lifecycle.dart';
import '../../acp/data/acp_service_impl.dart';
import '../../commands/mutation_board.dart';
import '../../contracts/stamps.dart';
import '../../models/command_receipts.dart';
import '../../models/studio_state_snapshots.dart';
import '../../models_domain/data/models_repository_impl.dart';
import '../../usage/data/account_usage_repository_impl.dart';
import 'account_observations.dart';
import 'account_settings_mutations.dart';
import 'accounts_repository_impl.dart';

/// Composition/lifecycle only. Consumers borrow the four domain interfaces.
/// No repository points to another repository's writable source or commands.
final class AccountDomainResources {
  AccountDomainResources({
    required AccountFeedPort feed,
    required AccountConfigurationPort configuration,
    required AccountModelsPort modelPort,
    required AccountUsagePort usagePort,
    required AcpPort acpPort,
    required this.coordinator,
    required this.mutations,
    required ClientScope scope,
    required String owner,
  }) {
    _observations = AccountObservations(
      feed: feed,
      owner: owner,
      scope: scope,
      consume: _consume,
      failed: _failed,
    );
    _settingsMutations = AccountSettingsMutations(
      coordinator: coordinator,
      board: mutations,
      observations: _observations,
      applyReply: acceptReply,
    );
    _accounts = AccountsRepositoryImpl(
      port: configuration,
      observations: _observations,
      mutations: _settingsMutations,
    );
    _models = ModelsRepositoryImpl(
      port: modelPort,
      observations: _observations,
      mutations: _settingsMutations,
      board: mutations,
    );
    _usage = AccountUsageRepositoryImpl(
      port: usagePort,
      observations: _observations,
      accounts: _accounts.state,
    );
    _acp = AcpServiceImpl(
      port: acpPort,
      observations: _observations,
      mutations: _settingsMutations,
      accounts: _accounts,
      board: mutations,
    );
  }
  final SettingsWriteCoordinator coordinator;
  final MutationBoard mutations;
  late final AccountObservations _observations;
  late final AccountSettingsMutations _settingsMutations;
  late final AccountsRepositoryImpl _accounts;
  late final ModelsRepositoryImpl _models;
  late final AccountUsageRepositoryImpl _usage;
  late final AcpServiceImpl _acp;
  final String _commandScopeId = _newCommandScopeId();
  final Map<String, ClientResourceId> _commandResourceIds = {};
  final Map<String, Future<void>> _commandJoins = {};
  final Map<String, UnresolvedResource> _commandFailures = {};
  Future<CloseReport>? _closing;
  AccountsRepository get accounts => _accounts;
  ModelsRepository get models => _models;
  AccountUsageRepository get usage => _usage;
  AcpService get acp => _acp;

  /// Authorized runtime/bootstrap rebinding; never called from an incoming
  /// domain frame. Old resources retain their real retirement/join owners.
  void adoptOwnerEpoch(String ownerEpoch) => prepareOwnerEpoch(ownerEpoch)();

  /// Composition-only two-phase rebinding. Preparation cannot notify or close:
  /// every domain detaches its old scope before any caller callback can install
  /// the new baseline. Invoke the returned one-shot completion in a finally.
  void Function() prepareOwnerEpoch(String ownerEpoch) {
    if (_observations.ownerEpoch == ownerEpoch) return () {};
    coordinator.adoptOwnerEpoch(ownerEpoch);
    final owner = coordinator.captureOwner();
    final observationChange = _observations.prepareOwnerEpoch(ownerEpoch);
    bool isCurrent() =>
        owner.isCurrent &&
        observationChange.generation == _observations.generation;
    final commits = [
      observationChange.commit,
      _accounts.prepareOwnerChange(isCurrent),
      _models.prepareOwnerChange(isCurrent),
      _usage.prepareOwnerChange(isCurrent),
      _acp.prepareOwnerChange(isCurrent),
    ];
    var committed = false;
    return () {
      if (committed) return;
      committed = true;
      Object? failure;
      StackTrace? failureStack;
      // A reentrant owner replacement stops stale publications, not the real
      // cleanup of captured old objects. Siblings retain their join duty even
      // when an earlier completion throws.
      for (final commit in commits) {
        try {
          commit();
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    };
  }

  /// The existing product-topic registry retains the valid shared directory
  /// subscription. It hands all actual catalog content to this same reducer.
  void attachDirectoryDemand(AccountDemand Function() acquire) =>
      _models.directoryDemand = acquire;

  /// General settings are still owned by the Client; this callback is routing,
  /// not a second cache, and must be attached by the composition root.
  void Function(SettingsStateSnapshot snapshot)? onSettings;

  void acceptReply(SettingsCommandReply reply, {SettingsWriteOwner? owner}) {
    final captured = owner ?? coordinator.captureOwner();
    coordinator.requireOwner(captured);
    if (reply.receipt.targets.any((stamp) => !_observations.accepts(stamp)))
      throw StateError(
        'Account reply belongs to an unauthorized runtime owner',
      );
    for (final stamp in reply.receipt.targets) {
      if (stamp.resourceKey == 'settings') coordinator.observe(stamp);
    }
    onSettings?.call(reply.snapshot);
    coordinator.requireOwner(captured);
    for (final frame in reply.accountFrames) {
      coordinator.requireOwner(captured);
      acceptFrame(frame);
    }
    coordinator.requireOwner(captured);
    final settingsStamp = reply.receipt.targets
        .where((stamp) => stamp.resourceKey == 'settings')
        .firstOrNull;
    if (settingsStamp == null || reply.snapshot.state.value == null) return;
    final present = <AccountIdentity>{
      for (final account in reply.snapshot.accounts)
        NativeAccountIdentity(account.id),
      for (final account in reply.snapshot.acpAccounts)
        AcpAccountIdentity(account.accountId),
      for (final frame in reply.accountFrames)
        if (frame is AccountDetailFrame && frame.account != null)
          frame.identity,
    };
    // Full command replies also prove absence. Deletions need no redundant
    // bootstrap/readback, but only the absent target's reducer gets the proof.
    for (final target in _observations.targets.toList()) {
      coordinator.requireOwner(captured);
      if (target is AccountDetailTarget &&
          !present.contains(target.identity) &&
          !reply.accountFrames.any((frame) => frame.target == target)) {
        acceptFrame(
          AccountDetailFrame(
            ResourceStamp(
              resourceKey: 'settings',
              ownerEpoch: settingsStamp.ownerEpoch,
              revision: reply.snapshot.revision,
            ),
            target.identity,
            null,
          ),
        );
      } else if (target is AccountModelsTarget &&
          !present.contains(target.identity) &&
          !reply.accountFrames.any((frame) => frame.target == target)) {
        acceptFrame(
          AccountModelsFrame(
            ResourceStamp(
              resourceKey: 'model-catalog',
              ownerEpoch: settingsStamp.ownerEpoch,
              revision: reply.snapshot.modelCatalogRevision,
            ),
            target.identity,
            null,
          ),
        );
      }
    }
    coordinator.requireOwner(captured);
  }

  void acceptFrame(AccountDomainFrame frame) => _observations.apply(frame);

  void acceptCatalog(
    SettingsStateSnapshot snapshot,
    String ownerEpoch, {
    SettingsWriteOwner? owner,
  }) {
    final captured = owner ?? coordinator.captureOwner();
    coordinator.requireOwner(captured);
    // Full catalog frames are decomposed to targets, with per-target clocks.
    // A high A frame never causes the unobserved B baseline to be discarded.
    final stamp = ResourceStamp(
      resourceKey: 'model-catalog',
      ownerEpoch: ownerEpoch,
      revision: snapshot.modelCatalogRevision,
    );
    final incoming = {
      for (final account in snapshot.accounts)
        NativeAccountIdentity(account.id): account,
    };
    for (final entry in incoming.entries) {
      coordinator.requireOwner(captured);
      acceptFrame(
        AccountModelsFrame(
          stamp,
          entry.key,
          AccountModelCatalog(
            identity: entry.key,
            models: entry.value.models,
            status: entry.value.modelCatalog,
          ),
        ),
      );
    }
    for (final identity in _models.state.value.accounts.keys.toList()) {
      coordinator.requireOwner(captured);
      if (!incoming.containsKey(identity))
        acceptFrame(AccountModelsFrame(stamp, identity, null));
    }
    coordinator.requireOwner(captured);
  }

  void _consume(AccountDomainFrame frame) {
    final generation = _observations.generation;
    final owner = coordinator.captureOwner();
    bool isCurrent() =>
        generation == _observations.generation && owner.isCurrent;
    switch (frame) {
      case AccountSummariesFrame() || AccountDetailFrame():
        _accounts.apply(frame);
        if (!isCurrent()) return;
        if (frame is AccountDetailFrame) _acp.accountChanged(frame);
        if (!isCurrent()) return;
        if (frame is AccountDetailFrame &&
            frame.identity is NativeAccountIdentity &&
            (frame.modelConfiguration != null || frame.account == null)) {
          _models.applyConfiguration(
            frame.identity as NativeAccountIdentity,
            frame.stamp,
            frame.modelConfiguration,
          );
        }
        if (!isCurrent()) return;
        coordinator.observe(frame.stamp);
      case ChatGptLoginFrame():
        _accounts.apply(frame);
      case AccountModelsFrame():
        _models.apply(frame);
      case AccountUsageFrame():
        _usage.apply(frame);
      case AcpAuthFrame() || AcpInstallFrame() || AcpLocalDetectionFrame():
        _acp.apply(frame);
    }
  }

  void _failed(AccountObservationTarget target, StudioFailure failure) {
    switch (target) {
      case AccountSummariesTarget() || AccountDetailTarget():
        _accounts.fail(target, failure);
      case AccountModelsTarget():
        _models.fail(target, failure);
      case AccountUsageTarget():
        _usage.fail(failure);
      case AcpAuthTarget() || AcpInstallTarget() || AcpLocalDetectionTarget():
      case ChatGptLoginTarget():
        if (target is ChatGptLoginTarget) {
          _accounts.fail(target, failure);
        } else {
          _acp.fail(target, failure);
        }
    }
  }

  Future<CloseReport> close({required ClientCloseBudget budget}) {
    final existing = _closing;
    if (existing != null) return existing;
    final completion = Completer<CloseReport>();
    final result = _closing = completion.future;
    completion.complete(Future<CloseReport>.sync(() => _close(budget)));
    return result;
  }

  Future<CloseReport> _close(ClientCloseBudget budget) async {
    // Synchronously seal all command lanes before awaiting any sibling owner.
    final commandJoins = <Future<void>>[
      _joinCommand(
        'account-model-commands',
        Future<void>.sync(_models.close),
        budget,
      ),
      _joinCommand(
        'account-usage-commands',
        Future<void>.sync(_usage.close),
        budget,
      ),
      _joinCommand('acp-commands', Future<void>.sync(_acp.close), budget),
      _joinCommand(
        'account-commands',
        Future<void>.sync(_accounts.close),
        budget,
      ),
    ];
    final observations = _observations.close(budget: budget);
    await Future.wait(commandJoins);
    return _finishCloseReport(await observations);
  }

  Future<CloseReport> retryCleanup({required ClientCloseBudget budget}) async {
    final observations = _observations.retryCleanup(budget: budget);
    // These are joins of already admitted commands, never command replays.
    await Future.wait([
      for (final entry in _commandJoins.entries.toList())
        _joinCommand(entry.key, entry.value, budget),
    ]);
    return _finishCloseReport(await observations);
  }

  CloseReport _finishCloseReport(CloseReport observations) {
    if (_closing != null && _commandFailures.isEmpty && observations.complete)
      _settingsMutations.disposeConfirmations();
    return CloseReport(
      unresolved: [...observations.unresolved, ..._commandFailures.values],
    );
  }

  Future<void> _joinCommand(
    String owner,
    Future<void> task,
    ClientCloseBudget budget,
  ) async {
    final resourceId = _commandResourceIds.putIfAbsent(
      owner,
      () => ClientResourceId(_commandScopeId, _commandResourceIds.length + 1),
    );
    _commandJoins[owner] = task;
    final settled = task.then<void>(
      (_) {
        if (identical(_commandJoins[owner], task)) {
          unawaited(_commandJoins.remove(owner));
          _commandFailures.remove(owner);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_commandJoins[owner], task)) {
          _commandFailures[owner] = UnresolvedResource(
            resourceId: resourceId,
            owner: owner,
            attemptId: AttemptId(resourceId.sequence),
            reason: error,
            stages: [
              ClientResourceStage(
                owner: owner,
                phase: ClientClosePhase.close,
                error: error,
                stackTrace: stack,
              ),
            ],
          );
        }
      },
    );
    try {
      await settled.timeout(budget.remaining);
    } on TimeoutException catch (error) {
      // Keep the original task: a late real completion clears only this join.
      _commandFailures[owner] = UnresolvedResource(
        resourceId: resourceId,
        owner: owner,
        attemptId: AttemptId(resourceId.sequence),
        reason: error,
        stages: [
          ClientResourceStage(
            owner: owner,
            phase: ClientClosePhase.close,
            pending: true,
          ),
        ],
      );
    }
  }
}

String _newCommandScopeId() {
  final random = Random.secure();
  final nonce = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'account-commands-$nonce';
}
