import '../../../models.dart';
import '../../../studio_ports.dart';
import '../../../anywork_client.dart' show OperationHandle;
import '../anywork_client.dart';
import 'command_lane.dart';

/// ACP 官方 server 准备的 Client 动作。
///
/// 准备是共享资产操作，不属于某个账号：同一 provider 同时最多一个操作，重复
/// start 在到达 transport 之前就被拒绝；取消命中 canonical 观察给出的 operation
/// 身份，走**独立** lane，绝不排在 start 之后。
///
/// 命令只快速返回受理身份与 canonical 快照；进度与终态全部由 `acpInstall`
/// topic 推进。这里不推断“已下载”或“可运行”，也不等待长任务 future。
class AcpInstallCommands {
  AcpInstallCommands(this._client);

  final AnyworkClient _client;
  final CommandLane _startLane = CommandLane();

  /// 取消与开始互不排队：topic 一旦给出 operation 身份，用户必须能立刻取消。
  final CommandLane _cancelLane = CommandLane();

  /// 每个 provider 至多一个已受理的 start 意图。
  final Map<AcpProviderView, OperationId> _active = {};

  /// 在途取消意图按**完整目标**（provider + 目标 operation）去重：同一目标重复
  /// 取消是 typed busy；不同目标允许并行取消（旧回执不阻塞新的 canonical 操作）。
  final Map<(AcpProviderView, String), OperationId> _cancelling = {};

  /// 显式重新读取 canonical 快照；只观察，不联网、不启动下载。
  Future<AcpInstallSnapshotView> readState() async {
    if (_client.isClosed) throw StateError('Client is closed');
    final snapshot = await _api.readAcpInstallState();
    if (!_client.isClosed) _client.acpInstall.apply(snapshot);
    return snapshot;
  }

  /// 受理一次准备；返回受理后的 canonical 快照（不是完成）。
  ///
  /// 返回快照里该 provider 的 state 携带本次 operation 身份，调用方可据此把
  /// 结果绑定到草稿；重复调用被拒绝，不会创建第二个任务。
  Future<AcpInstallSnapshotView> start(AcpProviderView provider) async {
    if (_client.isClosed) throw StateError('Client is closed');
    if (_active.containsKey(provider)) {
      throw StudioFailure(
        code: StudioFailureCode.busy,
        message: 'An ACP server preparation is already active',
        retryable: false,
        correlationId: 'client-acp-install',
      );
    }
    final admitted = OperationId(
      'acp-install-admission:${_client.clientId}:${provider.wire}',
    );
    _active[provider] = admitted;
    try {
      return await _startLane.enqueue(() async {
        final operation = _client.mutations.begin(target: 'acp-install');
        try {
          final reply = await _api.startAcpInstall(
            operationId: operation.id,
            provider: provider,
          );
          return _accept(operation, reply);
        } catch (error, stack) {
          _reject(operation, error);
          Error.throwWithStackTrace(error, stack);
        }
      });
    } finally {
      if (identical(_active[provider], admitted)) {
        _active.remove(provider);
      }
    }
  }

  /// 取消该 provider 当前操作；没有 canonical 操作身份时明确失败。
  ///
  /// 目标身份来自 canonical `acpInstall` 快照（含终态保留的身份），因此即使
  /// start 回执仍在等待观察，也能提交取消。
  Future<AcpInstallSnapshotView> cancel(AcpProviderView provider) {
    if (_client.isClosed) return Future.error(StateError('Client is closed'));
    final targetOperationId = _client.acpInstall.stateOf(provider).operationId;
    if (targetOperationId == null) {
      return Future.error(
        StudioFailure(
          code: StudioFailureCode.notFound,
          message: 'No ACP server preparation is active for ${provider.wire}',
          retryable: false,
          correlationId: 'client-acp-install',
        ),
      );
    }
    final key = (provider, targetOperationId);
    if (_cancelling.containsKey(key)) {
      return Future.error(
        StudioFailure(
          code: StudioFailureCode.busy,
          message:
              'An ACP preparation cancel for $targetOperationId is already '
              'in flight',
          retryable: false,
          correlationId: 'client-acp-install',
        ),
      );
    }
    final admitted = OperationId(
      'acp-install-cancel:${_client.clientId}:${provider.wire}:'
      '$targetOperationId',
    );
    _cancelling[key] = admitted;
    // run（并行）而不是 enqueue：取消不排在任何 start 之后。
    late final Future<AcpInstallSnapshotView> running;
    try {
      running = _cancelLane.run(() async {
        // begin 可能在预算耗尽时同步抛错，也在 lane 回调内执行；释放统一交给
        // 下面 whenComplete 覆盖**整条 future 生命周期**。
        final operation = _client.mutations.begin(target: 'acp-install');
        try {
          final reply = await _api.cancelAcpInstall(
            operationId: operation.id,
            provider: provider,
            targetOperationId: OperationId(targetOperationId),
          );
          return _accept(operation, reply);
        } catch (error, stack) {
          _reject(operation, error);
          Error.throwWithStackTrace(error, stack);
        }
      });
    } catch (error, stack) {
      // lane 自身同步 throw（已 seal）或回调内同步失败（预算拒绝）：先释放本地
      // reservation，再以 Future.error 交回调用方（保持 stack，不改变 API 语义）。
      if (identical(_cancelling[key], admitted)) _cancelling.remove(key);
      return Future<AcpInstallSnapshotView>.error(error, stack);
    }
    // 所有成功/失败路径（lane 未执行、MutationBoard.begin 预算拒绝、transport
    // 失败）都只释放**自己的**完整 key；不吞原错误、不改 stack。
    return running.whenComplete(() {
      if (identical(_cancelling[key], admitted)) _cancelling.remove(key);
    });
  }

  AcpInstallSnapshotView _accept(
    OperationHandle operation,
    AcpInstallCommandReply reply,
  ) {
    if (!_client.isClosed) _client.acpInstall.apply(reply.snapshot);
    operation.accept(reply.receipt.toCommitReceipt());
    return reply.snapshot;
  }

  void _reject(OperationHandle operation, Object error) {
    if (operation.state.value.receipt != null) {
      operation.syncFailed(error);
    } else if (_knownRejection(error)) {
      operation.reject(error);
    } else {
      operation.unknownOutcome(error);
    }
  }

  StudioTransport get _api => _client.transport;

  /// 关闭只放弃自己的受理记录，不伪造完成、不取消运行时下载。
  Future<void> close() {
    _startLane.seal();
    _cancelLane.seal();
    return Future.wait([_startLane.join(), _cancelLane.join()]);
  }
}

bool _knownRejection(Object error) =>
    error is StudioFailure &&
    switch (error.code) {
      StudioFailureCode.invalidArgument ||
      StudioFailureCode.notFound ||
      StudioFailureCode.busy ||
      StudioFailureCode.conflict ||
      StudioFailureCode.staleRevision ||
      StudioFailureCode.permissionDenied ||
      StudioFailureCode.overloaded ||
      StudioFailureCode.notInitialized ||
      StudioFailureCode.cancelled ||
      StudioFailureCode.cancellationTooLate => true,
      _ => false,
    };
