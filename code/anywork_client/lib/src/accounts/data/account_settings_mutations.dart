import 'dart:async';

import '../../../accounts_ports.dart';
import '../../commands/mutation_board.dart';
import '../../contracts/stamps.dart';
import '../../models/command_receipts.dart';
import '../../models/failure_models.dart';
import '../../studio/commands/command_lane.dart';
import '../domain/accounts_repository.dart';
import 'account_observations.dart';

/// Settings operations keep target-specific proof until receipt observation.
/// The coordinator carries only order and settings CAS, never these snapshots.
final class AccountSettingsMutations {
  AccountSettingsMutations({
    required this.coordinator,
    required this.board,
    required this.observations,
    required this.applyReply,
  });
  final SettingsWriteCoordinator coordinator;
  final MutationBoard board;
  final AccountObservations observations;
  final void Function(SettingsCommandReply) applyReply;
  final Set<_TargetConfirmation> _confirmations = {};

  Future<OperationState> run({
    required String key,
    DraftStamp? draft,
    required Map<String, AccountObservationTarget> targets,
    required Future<SettingsCommandReply> Function(int, OperationId) request,
  }) {
    if (coordinator.isClosed)
      return Future.error(StateError('Settings writes are closed'));
    // Freeze both intent and proof ownership before entering the shared queue.
    final owner = coordinator.captureOwner();
    final operation = board.begin(
      target: key,
      draft: draft,
      observationOwner: owner,
    );
    final generation = observations.generation;
    var issued = false;
    late final _TargetConfirmation confirmation;
    try {
      confirmation = _TargetConfirmation(operation, targets, observations);
      _confirmations.add(confirmation);
      confirmation.onDone = () => _confirmations.remove(confirmation);
    } catch (error) {
      operation.reject(error);
      rethrow;
    }
    if (coordinator.isClosed) {
      final failure = StateError('Settings writes closed during admission');
      operation.reject(failure);
      confirmation.dispose();
      return Future.error(failure);
    }
    return coordinator.enqueue(() async {
      try {
        if (generation != observations.generation)
          throw const _AccountOwnerChanged();
        Future<bool> refresh() async {
          try {
            for (final target in targets.values.toSet()) {
              await observations.refresh(target);
            }
            return coordinator.stamp != null;
          } catch (_) {
            return false;
          }
        }

        final reply = await retryRevisionConflict(() async {
          if (generation != observations.generation)
            throw const _AccountOwnerChanged();
          final revision = await coordinator.expectedRevision(() async {
            if (!await refresh())
              throw StateError('Account settings are unavailable');
          }, owner: owner);
          if (generation != observations.generation)
            throw const _AccountOwnerChanged();
          issued = true;
          return request(revision, operation.id);
        }, refresh: refresh);
        if (reply.receipt.operationId != operation.id)
          throw const StudioFailure(
            code: StudioFailureCode.protocol,
            message: 'Account receipt belongs to another operation',
            retryable: false,
            correlationId: 'accounts-receipt',
          );
        final receipt = reply.receipt;
        operation.accept(
          CommitReceipt(
            operationId: receipt.operationId,
            disposition: receipt.disposition,
            targets: receipt.targets,
            effect: receipt.effect,
            effective: receipt.effective,
            durable: receipt.durable,
            requiresIdentityObservation: true,
          ),
        );
        if (generation != observations.generation) {
          confirmation.dispose();
          throw const _AccountOwnerChanged();
        }
        coordinator.requireOwner(owner);
        applyReply(reply);
        coordinator.requireOwner(owner);
        confirmation.check();
        return operation.state.value;
      } catch (error) {
        if (operation.state.value.receipt != null) {
          operation.syncFailed(error);
        } else if (isKnownAccountRejection(error) ||
            (error is _AccountOwnerChanged ||
                    error is SettingsWriteOwnerChanged) &&
                !issued) {
          operation.reject(error);
          confirmation.dispose();
        } else {
          // Unknown outcomes remain registered and target-observed until exit.
          operation.unknownOutcome(error);
        }
        rethrow;
      }
    });
  }

  void disposeConfirmations() {
    for (final confirmation in _confirmations.toList()) {
      confirmation.dispose();
    }
  }
}

bool isKnownAccountRejection(Object error) =>
    error is ArgumentError ||
    error is StudioFailure &&
        switch (error.code) {
          StudioFailureCode.invalidArgument ||
          StudioFailureCode.notFound ||
          StudioFailureCode.busy ||
          StudioFailureCode.conflict ||
          StudioFailureCode.staleRevision ||
          StudioFailureCode.permissionDenied ||
          StudioFailureCode.overloaded ||
          StudioFailureCode.notInitialized => true,
          _ => false,
        };

final class _TargetConfirmation {
  _TargetConfirmation(
    this.operation,
    Map<String, AccountObservationTarget> targets,
    this.observations,
  ) : targets = Map.unmodifiable(targets) {
    generation = observations.generation;
    try {
      for (final target in targets.values.toSet()) {
        _demands.add(observations.acquire(target));
      }
      observations.addListener(check);
    } catch (_) {
      dispose();
      rethrow;
    }
  }
  final OperationHandle operation;
  final Map<String, AccountObservationTarget> targets;
  final AccountObservations observations;
  late final int generation;
  final List<AccountDemand> _demands = [];
  void Function()? onDone;
  bool _disposed = false;

  void check() {
    final receipt = operation.state.value.receipt;
    if (_disposed) return;
    if (generation != observations.generation) {
      if (receipt != null) operation.syncFailed(const _AccountOwnerChanged());
      dispose();
      return;
    }
    if (receipt == null) return;
    for (final target in receipt.targets) {
      final identity = targets[target.resourceKey];
      if (identity == null ||
          observations.stamp(identity)?.covers(target) != true)
        return;
    }
    operation.markObserved();
    dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    observations.removeListener(check);
    for (final demand in _demands) {
      // Failed retirement remains registered in AccountObservations for retry.
      unawaited(
        demand.release().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
    _demands.clear();
    onDone?.call();
  }
}

final class _AccountOwnerChanged implements Exception {
  const _AccountOwnerChanged();
  @override
  String toString() => 'The runtime owner changed during account mutation';
}
