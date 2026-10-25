import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/configuration_commands.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/resource_owner.dart';
import '../product_native_opening.dart';
import 'call_failures.dart';
import 'command_inputs.dart';
import 'command_results.dart';

/// Only this invocation's opaque/result/cleanup, not the SDK's CAS, find or
/// observation policy. No result path closes or releases its read materials.
final class FrbConfigurationCommandCall implements ConfigurationCommandCall {
  FrbConfigurationCommandCall.begin(
    OperationId operation,
    native.BridgeConfigurationCommandRequest request,
  ) : this._(
        operation,
        () => native.beginConfigurationCommand(request: request),
        admission: true,
      );
  FrbConfigurationCommandCall.find(OperationId operation)
    : this._(
        operation,
        () => native.findConfigurationCommand(
          operationId: configurationOperationToBridge(operation),
        ),
        admission: false,
      );

  FrbConfigurationCommandCall._(
    this._operation,
    Future<native.BridgeConfigurationCommandCall?> Function() open, {
    required bool admission,
  }) {
    _owner = AdapterResourceOwner(
      resource: 'configuration-command',
      requestNativeClose: () => _opening.handle?.requestClose(),
      closeNative: () => _closeNative(retry: false),
      retryNativeClose: () => _closeNative(retry: true),
      disposeNative: () => _opening.handle!.dispose(),
      cancelNativeStream: () => Future<void>.value(),
      mapFailure: configurationCallFailure,
      expectedIdentity: () => _callId ?? '',
    );
    _opening.start(
      _owner,
      () async {
        try {
          return await open();
        } on Object catch (error, stack) {
          _openFailure = (
            failure: admission
                ? configurationBeginFailure(error)
                : CommandDispatchFailure.unknownOutcome(
                    failure: configurationCallFailure(error),
                  ),
            stack: stack,
          );
          rethrow;
        }
      },
      (handle) => handle?.requestClose(),
      attached: (handle) {
        if (handle != null) _captureIdentity(handle);
      },
    );
  }

  final OperationId _operation;
  final _opening =
      ProductNativeOpening<native.BridgeConfigurationCommandCall?>();
  late final AdapterResourceOwner _owner;
  String? _callId;
  String? _nativeOperation;
  ({CommandDispatchFailure failure, StackTrace stack})? _openFailure;

  Future<bool> get opened async {
    try {
      return await _opening.ready != null;
    } on Object catch (error, stack) {
      final original = _openFailure;
      Error.throwWithStackTrace(
        original?.failure ?? configurationUnknownFailure(error),
        original?.stack ?? stack,
      );
    }
  }

  void _rememberCallId(native.BridgeConfigurationCommandCall handle) {
    final raw = handle.callId();
    if (raw.isEmpty || _callId != null && raw != _callId) {
      throw adapterProtocol('configuration-command-call-id');
    }
    _callId ??= raw;
  }

  void _captureIdentity(native.BridgeConfigurationCommandCall handle) {
    _rememberCallId(handle);
    final rawOperation = handle.operationId();
    requireConfigurationOperation(rawOperation, _operation);
    _nativeOperation = rawOperation;
  }

  @override
  String get callId =>
      _callId ??
      (throw adapterProtocol('configuration-command-call-unavailable'));
  @override
  OperationId get operationId {
    final actual = _nativeOperation;
    if (actual == null) {
      throw adapterProtocol('configuration-command-operation-unavailable');
    }
    requireConfigurationOperation(actual, _operation);
    return OperationId(actual);
  }

  @override
  Future<ConfigurationCommandReply> result() async {
    void Function()? finish;
    try {
      // Unlike owner.query, this marker does not cancel publication of an
      // already returned Committed/CommittedButUnobserved native outcome.
      finish = _owner.registerOpening();
      final handle = _opening.handle ?? await _opening.ready;
      _owner.ensureOpen();
      if (handle == null) {
        throw adapterProtocol('configuration-command-not-found');
      }
      _captureIdentity(handle);
      final outcome = await handle.result();
      return configurationOutcomeFromBridge(outcome, _operation);
    } on Object catch (error, stack) {
      _owner.failure(error, stack, source: 'result');
      Error.throwWithStackTrace(configurationUnknownFailure(error), stack);
    } finally {
      finish?.call();
    }
  }

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.ready;
    if (handle == null) {
      throw adapterProtocol('configuration-command-not-found');
    }
    if (_callId == null) {
      try {
        _rememberCallId(handle);
      } on Object catch (error, stack) {
        _owner.failure(error, stack, source: 'close-identity');
      }
    }
    return feedCloseReportFromBridge(
      await (retry ? handle.retryClose() : handle.close()),
    );
  }

  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
