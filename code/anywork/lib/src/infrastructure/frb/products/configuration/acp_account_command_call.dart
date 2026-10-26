import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/configuration_acp_commands.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/resource_owner.dart';
import '../product_native_opening.dart';
import 'call_failures.dart';
import 'command_inputs.dart';
import 'command_results.dart';

/// ACP 接入提交的原生受管调用。
///
/// 与 Configuration/Profile 调用共用同一 Configuration 调用所有者、操作身份、结果保留与
/// 关闭守卫，只是结果类型换成 ACP 专用的窄形状：真实 Settings 回执 + 本次提交捕获的配置
/// 读取目标。callId／operationId 直接来自原生 handle，不使用本地计数器，也不冒充身份；
/// 适配层不读 latest 快照、不补 origin、不构造模型目录目标。`find` 只加入原操作，
/// 绝不发起第二次提交。
final class FrbAcpAccountCommandCall implements AcpAccountCommandCall {
  FrbAcpAccountCommandCall.begin({
    required OperationId operation,
    required String operationId,
    required BigInt expectedSettingsRevision,
    required native.BridgeAcpAccountMutation mutation,
  }) : this._(
         operation,
         () => native.beginAcpAccountCommand(
           operationId: operationId,
           expectedSettingsRevision: expectedSettingsRevision,
           mutation: mutation,
         ),
         admission: true,
       );
  FrbAcpAccountCommandCall.find(OperationId operation)
    : this._(
        operation,
        () => native.findAcpAccountCommand(
          operationId: configurationOperationToBridge(operation),
        ),
        admission: false,
      );

  FrbAcpAccountCommandCall._(
    this._operation,
    Future<native.BridgeAcpAccountCommandCall?> Function() open, {
    required bool admission,
  }) {
    _owner = AdapterResourceOwner(
      resource: 'acp-account-command',
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
  final _opening = ProductNativeOpening<native.BridgeAcpAccountCommandCall?>();
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

  void _rememberCallId(native.BridgeAcpAccountCommandCall handle) {
    final raw = handle.callId();
    if (raw.isEmpty || _callId != null && raw != _callId) {
      throw adapterProtocol('acp-account-command-call-id');
    }
    _callId ??= raw;
  }

  void _captureIdentity(native.BridgeAcpAccountCommandCall handle) {
    _rememberCallId(handle);
    final rawOperation = handle.operationId();
    requireConfigurationOperation(rawOperation, _operation);
    _nativeOperation = rawOperation;
  }

  @override
  String get callId =>
      _callId ??
      (throw adapterProtocol('acp-account-command-call-unavailable'));
  @override
  OperationId get operationId {
    final actual = _nativeOperation;
    if (actual == null) {
      throw adapterProtocol('acp-account-command-operation-unavailable');
    }
    requireConfigurationOperation(actual, _operation);
    return OperationId(actual);
  }

  @override
  Future<AcpAccountCommandReply> result() async {
    void Function()? finish;
    try {
      // Unlike owner.query, this marker does not cancel publication of an
      // already returned Committed/CommittedButUnobserved native outcome.
      finish = _owner.registerOpening();
      final handle = _opening.handle ?? await _opening.ready;
      _owner.ensureOpen();
      if (handle == null) {
        throw adapterProtocol('acp-account-command-not-found');
      }
      _captureIdentity(handle);
      final outcome = await handle.result();
      return acpAccountOutcomeFromBridge(outcome, _operation);
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
      throw adapterProtocol('acp-account-command-not-found');
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
