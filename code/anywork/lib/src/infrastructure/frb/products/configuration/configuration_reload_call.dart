import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/profile_commands.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/resource_owner.dart';
import '../product_native_opening.dart';
import 'call_failures.dart';
import 'command_inputs.dart';
import 'command_results.dart';

final class FrbConfigurationReloadCall implements ConfigurationReloadCall {
  FrbConfigurationReloadCall.begin(
    OperationId operation,
    native.BridgeConfigurationReloadRequest request,
  ) : this._(
        operation,
        () => native.beginConfigurationReload(request: request),
        admission: true,
      );
  FrbConfigurationReloadCall.find(OperationId operation)
    : this._(
        operation,
        () => native.findConfigurationReload(
          operationId: configurationOperationToBridge(operation),
        ),
        admission: false,
      );

  FrbConfigurationReloadCall._(
    this._operation,
    Future<native.BridgeConfigurationReloadCall?> Function() open, {
    required bool admission,
  }) {
    _owner = AdapterResourceOwner(
      resource: 'configuration-reload',
      requestNativeClose: () => _requestNative(_opening.handle),
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
      _requestNative,
      attached: (handle) {
        if (handle != null) _captureIdentity(handle);
      },
    );
  }

  final OperationId _operation;
  final _opening =
      ProductNativeOpening<native.BridgeConfigurationReloadCall?>();
  late final AdapterResourceOwner _owner;
  String? _callId;
  String? _nativeOperation;
  ({CommandDispatchFailure failure, StackTrace stack})? _openFailure;
  ({StudioFailure failure, StackTrace stack})? _requestFailure;

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

  void _rememberCallId(native.BridgeConfigurationReloadCall handle) {
    final raw = handle.callId();
    if (raw.isEmpty || _callId != null && raw != _callId) {
      throw adapterProtocol('configuration-reload-call-id');
    }
    _callId ??= raw;
  }

  void _captureIdentity(native.BridgeConfigurationReloadCall handle) {
    _rememberCallId(handle);
    final rawOperation = handle.operationId();
    requireConfigurationOperation(rawOperation, _operation);
    _nativeOperation = rawOperation;
  }

  @override
  String get callId =>
      _callId ??
      (throw adapterProtocol('configuration-reload-call-unavailable'));
  @override
  OperationId get operationId {
    final actual = _nativeOperation;
    if (actual == null) {
      throw adapterProtocol('configuration-reload-operation-unavailable');
    }
    requireConfigurationOperation(actual, _operation);
    return OperationId(actual);
  }

  @override
  Future<ConfigurationReloadResult> result() async {
    void Function()? finish;
    try {
      finish = _owner.registerOpening();
      final handle = _opening.handle ?? await _opening.ready;
      _owner.ensureOpen();
      if (handle == null) {
        throw adapterProtocol('configuration-reload-not-found');
      }
      _captureIdentity(handle);
      final outcome = await handle.result();
      return reloadOutcomeFromBridge(outcome, _operation);
    } on Object catch (error, stack) {
      _owner.failure(error, stack, source: 'result');
      Error.throwWithStackTrace(configurationUnknownFailure(error), stack);
    } finally {
      finish?.call();
    }
  }

  void _requestNative(native.BridgeConfigurationReloadCall? handle) {
    if (handle == null) return;
    try {
      handle.requestClose();
    } on Object catch (error, stack) {
      _requestFailure = (
        failure: configurationCallFailure(error),
        stack: stack,
      );
      rethrow;
    }
  }

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.ready;
    if (handle == null) throw adapterProtocol('configuration-reload-not-found');
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
  void requestClose() {
    final wasClosing = _owner.isClosing;
    _owner.requestClose();
    final failure = _requestFailure;
    if (!wasClosing && failure != null) {
      Error.throwWithStackTrace(failure.failure, failure.stack);
    }
  }

  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
