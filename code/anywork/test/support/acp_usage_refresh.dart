import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart';

import 'observed.dart';

/// Evidence for one quota-button invocation, from admission through completion.
/// A cancelled query deliberately retains old verified/ready data, so the auth
/// revision alone cannot prove success. Keep the admitted command current too.
final class AcpUsageRefresh {
  AcpUsageRefresh._(
    this._service,
    this._mutations,
    this._operation,
    this._admitted,
    this._accountId,
    this._connectionRevision,
  );

  final AcpService _service;
  final MutationBoard _mutations;
  final OperationHandle _operation;
  final ResourceStamp _admitted;
  final String _accountId;
  final int _connectionRevision;

  static Future<AcpUsageRefresh> submit({
    required AcpService service,
    required MutationBoard mutations,
    required String accountId,
    required int connectionRevision,
    required Future<void> Function() trigger,
  }) async {
    final target = 'acp-auth:$accountId';
    final before = service.auth.value;
    final entry = before.value?.account(
      accountId,
      connectionRevision: connectionRevision,
    );
    if (before.stale ||
        before.stamp == null ||
        entry == null ||
        entry.activeOperation != null ||
        entry.state is! AcpVerifiedState) {
      throw StateError(
        'ACP quota refresh requires an idle verified connection',
      );
    }
    final previous = {
      for (final state in mutations.operations)
        if (state.target == target) state.id,
    };
    await trigger();
    final submitted = mutations.operations.where(
      (state) => state.target == target && !previous.contains(state.id),
    );
    // Query and cancel may both complete during the button's pump. The latest
    // command alone would then identify cancellation as if it were the query.
    if (submitted.length != 1) {
      throw StateError('Expected exactly one new ACP quota command');
    }
    final operation = mutations.lookup(submitted.single.id)!;
    void requireCurrent() => _requireCurrent(mutations, operation);
    await untilObserved(operation.state, (state) {
      requireCurrent();
      return state.receipt != null;
    });
    requireCurrent();
    final admitted = operation.state.value.receipt!.targets
        .whereType<ResourceStamp>()
        .singleWhere((stamp) => stamp.resourceKey == 'acp-auth');
    if (admitted.ownerEpoch != before.stamp!.ownerEpoch ||
        admitted.revision <= before.value!.revision) {
      throw StateError('ACP quota admission does not advance the same owner');
    }
    return AcpUsageRefresh._(
      service,
      mutations,
      operation,
      admitted,
      accountId,
      connectionRevision,
    );
  }

  Future<AcpUsageReadyView> waitForReady() async {
    late AcpUsageReadyView ready;
    await untilObserved(_service.auth, (resource) {
      _requireCurrent(_mutations, _operation);
      if (resource.failure case final error?) throw error;
      if (resource.stamp?.ownerEpoch != _admitted.ownerEpoch) {
        throw StateError('ACP owner changed during quota refresh');
      }
      final snapshot = resource.value;
      if (snapshot == null || snapshot.revision <= _admitted.revision) {
        return false;
      }
      final entry = snapshot.account(
        _accountId,
        connectionRevision: _connectionRevision,
      );
      if (entry == null || entry.state is AcpFailedState) {
        throw StateError('ACP connection changed or authentication failed');
      }
      if (entry.usage?.state case AcpUsageFailedView(:final code)) {
        throw StateError('ACP usage query failed: ${code.name}');
      }
      if (entry.activeOperation != null) return false;
      final usage = entry.usage?.state;
      if (entry.state is AcpVerifiedState && usage is AcpUsageReadyView) {
        ready = usage;
        return true;
      }
      throw StateError('ACP quota operation ended without ready usage');
    });
    _requireCurrent(_mutations, _operation);
    return ready;
  }

  static void _requireCurrent(
    MutationBoard mutations,
    OperationHandle operation,
  ) {
    if (mutations.latest(operation.state.value.target)?.id != operation.id) {
      throw StateError('ACP quota command was cancelled or replaced');
    }
    final state = operation.state.value;
    if (state.failurePhase != null) {
      throw state.error ?? StateError('ACP quota command failed');
    }
  }
}
