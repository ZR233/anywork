import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates_ports.dart';

import '../../../../rust/api/studio/products/read/updates.dart' as native;
import '../../../../rust/api/studio/types/chat.dart' as lifecycle;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/resource_owner.dart';
import '../product_native_opening.dart';
import '../update_references.dart';

StudioFailure updateTaskFailure(Object error) {
  if (error case CommandDispatchFailure(:final failure)) return failure;
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(mappingError, operation: 'update-task-error');
  }
}

/// One original task and its in-flight RPCs. Progress is exclusively observed
/// through Updates feed. Cancel seals new admission, but cannot erase an
/// already-entered finish result (Ready may have won the native cancel race).
final class FrbUpdateTaskConnection implements UpdateTaskConnection {
  FrbUpdateTaskConnection(
    this._operation,
    Future<native.BridgeUpdateTask> Function() open,
  ) {
    _owner = AdapterResourceOwner(
      resource: 'update-task',
      requestNativeClose: () => _opening.handle?.requestCancel(),
      closeNative: () => _closeNative(retry: false),
      retryNativeClose: () => _closeNative(retry: true),
      disposeNative: () => _opening.handle!.dispose(),
      cancelNativeStream: () => Future<void>.value(),
      mapFailure: updateTaskFailure,
      expectedIdentity: () => _rawIdentity?.taskId ?? '',
    );
    _opening.start(
      _owner,
      open,
      (handle) => handle.requestCancel(),
      attached: _rememberRawIdentity,
    );
  }

  final OperationId _operation;
  final _opening = ProductNativeOpening<native.BridgeUpdateTask>();
  late final AdapterResourceOwner _owner;
  native.BridgeUpdateTaskIdentity? _rawIdentity;
  UpdateTaskIdentity? _identity;
  Future<void>? _started;
  Future<UpdatesReadTarget>? _finished;

  Future<void> get opened async {
    try {
      await _opening.ready;
    } on Object catch (error, stack) {
      // A generic bridge error is not typed evidence of a rejected opening.
      Error.throwWithStackTrace(
        CommandDispatchFailure.unknownOutcome(
          failure: updateTaskFailure(error),
        ),
        stack,
      );
    }
  }

  void _rememberRawIdentity(native.BridgeUpdateTask handle) {
    final raw = handle.identity();
    if (raw.taskId.isEmpty || _rawIdentity != null && raw != _rawIdentity) {
      throw adapterProtocol('update-task-identity');
    }
    _rawIdentity ??= raw;
  }

  UpdateTaskIdentity _originalIdentity(native.BridgeUpdateTask handle) {
    _rememberRawIdentity(handle);
    final raw = _rawIdentity!;
    if (raw.runtimeEpoch.isEmpty ||
        raw.operationId.isEmpty ||
        raw.operationId != _operation.value) {
      throw adapterProtocol('update-task-operation');
    }
    return _identity ??= UpdateTaskIdentity(
      runtimeEpoch: raw.runtimeEpoch,
      taskId: raw.taskId,
      operationId: _operation,
    );
  }

  @override
  UpdateTaskIdentity get identity {
    if (_owner.isDisposed) return _identity!;
    try {
      final handle = _opening.handle;
      if (handle == null) throw adapterProtocol('update-task-not-open');
      return _originalIdentity(handle);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        _owner.failure(error, stack, source: 'identity'),
        stack,
      );
    }
  }

  @override
  Future<void> start() {
    final void Function() settled;
    try {
      _owner.ensureOpen();
      if (_started case final started?) return started;
      settled = _owner.registerOpening();
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.rejected(
          failure: _owner.failure(error, stack, source: 'start-admission'),
        ),
        stack,
      );
    }
    return _started = _start(settled);
  }

  Future<void> _start(void Function() settled) async {
    try {
      final native.BridgeUpdateTask handle;
      try {
        handle = await _opening.ready;
        _owner.ensureOpen();
        _originalIdentity(handle);
      } on Object catch (error, stack) {
        // No native start has been invoked by this path.
        Error.throwWithStackTrace(
          CommandDispatchFailure.rejected(
            failure: _owner.failure(error, stack, source: 'start-admission'),
          ),
          stack,
        );
      }
      try {
        await handle.start();
      } on Object catch (error, stack) {
        Error.throwWithStackTrace(
          CommandDispatchFailure.unknownOutcome(
            failure: _owner.failure(error, stack, source: 'start'),
          ),
          stack,
        );
      }
    } finally {
      settled();
    }
  }

  @override
  Future<UpdatesReadTarget> finish() {
    if (_finished case final finished?) return finished;
    final void Function() settled;
    try {
      settled = _owner.registerOpening();
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        _owner.failure(error, stack, source: 'finish-admission'),
        stack,
      );
    }
    return _finished = _finish(settled);
  }

  Future<UpdatesReadTarget> _finish(void Function() settled) async {
    try {
      final handle = await _opening.ready;
      _owner.ensureOpen();
      final original = _originalIdentity(handle);
      final nativeTarget = await handle.finish();
      try {
        final target = updatesTargetFromBridge(nativeTarget);
        if (target.origin.ownerEpoch != original.runtimeEpoch ||
            target.origin.incarnation < 1) {
          throw adapterProtocol('update-task-result-origin');
        }
        // Deliberately no ensureOpen after awaiting: an accepted finish is
        // committed observation, not a cancellable read of whichever is latest.
        return target;
      } on Object catch (error, stack) {
        Error.throwWithStackTrace(
          CommandDispatchFailure.confirmedWithoutUsableReceipt(
            failure: _owner.failure(error, stack, source: 'finish-result'),
          ),
          stack,
        );
      }
    } on CommandDispatchFailure {
      rethrow;
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.unknownOutcome(
          failure: _owner.failure(error, stack, source: 'finish'),
        ),
        stack,
      );
    } finally {
      settled();
    }
  }

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.ready;
    // Join first, even when the original descriptor cannot yet be converted.
    final report = await (retry ? handle.retryClose() : handle.close());
    final original = _originalIdentity(handle);
    if (report.identity.runtimeEpoch != original.runtimeEpoch ||
        report.identity.taskId != original.taskId ||
        report.identity.operationId != original.operationId.value) {
      throw adapterProtocol('update-task-close-identity');
    }
    // Reuse the existing close-outcome/issue mapper and owner. The full task
    // identity was checked above; taskId is only the local owner's join key.
    return feedCloseReportFromBridge(
      lifecycle.BridgeFeedCloseReport(
        feedId: report.identity.taskId,
        outcome: report.outcome,
      ),
    );
  }

  @override
  void requestCancel() => _owner.requestClose();

  Future<UpdateTaskCloseReport> _close({required bool retry}) async {
    final report = await (retry ? _owner.retryClose() : _owner.close());
    return UpdateTaskCloseReport(identity: identity, outcome: report.outcome);
  }

  @override
  Future<UpdateTaskCloseReport> close() => _close(retry: false);
  @override
  Future<UpdateTaskCloseReport> retryClose() => _close(retry: true);
}
