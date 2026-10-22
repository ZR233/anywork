import '../../../models.dart';
import '../../../studio_ports.dart';
import '../../../anywork_client.dart' show OperationHandle;
import '../anywork_client.dart';
import '../stores/domain_sync.dart';
import 'command_lane.dart';

/// ACP 接入的 Client 动作。
///
/// 保存/删除走 Native 配置写入的同一 settings 通道（同一 CAS lane），认证检查、
/// 登录与取消走独立认证通道。两类事实互不撤销：保存成功后连接失败只说明连接未完成，
/// 已保存的接入仍是 canonical 事实。
///
/// 每次认证动作都按 **账号身份 + 连接身份** 读取 canonical 观察：旧 program/args
/// 或删除后重建的同 ID 账号的结果不能套用到当前配置。
class AcpCommands {
  AcpCommands(this._client);

  final AnyworkClient _client;
  final CommandLane _authLane = CommandLane();

  /// 取消走**独立**通道：一旦 topic 已给出 operation 身份，用户必须能在 start
  /// 请求仍挂着的情况下取消；不能排在 start lane 之后。
  final CommandLane _cancelLane = CommandLane();

  /// 每个接入至多一个在途的取消意图。
  final Map<String, OperationId> _cancelling = {};

  /// 每个接入至多一个已受理的认证操作。
  ///
  /// 平台对同一账号的并发 start 只受理一次；Client 侧同样在提交前拒绝第二个意图，
  /// 让“重复输入”在到达 transport 之前就有确定答案，而不是靠 UI 按钮是否可见。
  final Map<String, OperationId> _active = {};

  /// 保存（或更新）接入配置并返回 canonical 行。
  Future<AcpAccountSettingsView> saveAccount(
    AcpAccountUpdateView account,
  ) async {
    final snapshot = await _client.settingsCommands.saveAcpAccount(account);
    final saved = snapshot.acpAccounts
        .where((candidate) => candidate.accountId == account.accountId)
        .firstOrNull;
    if (saved == null) {
      throw StateError(
        'ACP account save returned a canonical snapshot without '
        '${account.accountId}.',
      );
    }
    return saved;
  }

  /// 删除接入配置；成功后该接入不再有可操作的连接身份。
  Future<void> removeAccount(String accountId) async {
    final snapshot = await _client.settingsCommands.removeAcpAccount(accountId);
    if (snapshot.acpAccounts.any(
      (candidate) => candidate.accountId == accountId,
    )) {
      throw StateError(
        'ACP account removal returned a canonical snapshot that still contains '
        '$accountId.',
      );
    }
  }

  /// “保存并连接”：先确认 canonical 保存，再提交连接检查。
  ///
  /// 第二步被拒绝时不撤销第一步，也不重建账号；调用方据 [result.saved] 显示已保存
  /// 行，并按 [result.checkFailure] 就地说明“账号已保存，连接未完成”。保存本身失败
  /// 才按保存失败上报。
  Future<AcpSaveAndConnectResult> saveAndConnect(
    AcpAccountUpdateView account,
  ) async {
    final saved = await saveAccount(account);
    try {
      await check(saved.accountId);
      return AcpSaveAndConnectResult(saved: saved);
    } on Object catch (error) {
      return AcpSaveAndConnectResult(
        saved: saved,
        checkFailure: typedCommandFailure(
          error,
          correlationId: 'client-acp-connect',
        ),
      );
    }
  }

  /// 显式按需读取当前 canonical 观察并进入同一 reducer。
  ///
  /// 只用于调用方明确要求的重新读取（例如诊断）；正常进展全部来自 `acpAuth` topic，
  /// 这里不轮询、也不制造状态。
  Future<AcpAuthSnapshotView> readState() async {
    if (_client.isClosed) throw StateError('Client is closed');
    final snapshot = await _api.readAcpAuthState();
    if (!_client.isClosed) _client.acpAuth.apply(snapshot);
    return snapshot;
  }

  /// 连接检查：initialize + `session/new` 探测，不发送 prompt。
  Future<AcpAuthSnapshotView> check(String accountId) =>
      _start(accountId, const AcpCheckActionView());

  /// 按服务端实际宣告的 agent 方法登录。
  Future<AcpAuthSnapshotView> login(
    String accountId, {
    required String methodId,
  }) {
    if (methodId.trim().isEmpty) {
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message: 'ACP authentication method is required',
          retryable: false,
          correlationId: 'client-acp-auth',
        ),
      );
    }
    return _start(accountId, AcpAuthenticateActionView(methodId));
  }

  /// 取消当前 operation；必须命中同一连接身份下当前代次。
  ///
  /// 取消不受 start 的 pending lane 或 UI 的 busy 布尔值影响：只要 canonical 观察给出
  /// operation 身份，就立即提交取消。迟到的 start 回执仍进入同一 revision reducer，
  /// 不得覆盖更新的 Cancelling/终态。
  Future<AcpAuthSnapshotView> cancel(String accountId) {
    if (_client.isClosed) return Future.error(StateError('Client is closed'));
    final connectionRevision = _connectionRevision(accountId);
    final target = _client.acpAuth.stateOf(
      accountId,
      connectionRevision: connectionRevision,
    );
    final targetOperationId = target.operationId;
    if (targetOperationId == null) {
      return Future.error(
        StudioFailure(
          code: StudioFailureCode.notFound,
          message: 'No ACP authentication operation is active for $accountId',
          retryable: false,
          correlationId: 'client-acp-auth',
        ),
      );
    }
    if (_cancelling.containsKey(accountId)) {
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.busy,
          message: 'An ACP cancel is already in flight',
          retryable: false,
          correlationId: 'client-acp-auth',
        ),
      );
    }
    final admitted = OperationId('acp-cancel:${_client.clientId}:$accountId');
    _cancelling[accountId] = admitted;
    // run（并行）而不是 enqueue：取消不排在任何 start 之后。
    return _cancelLane.run(() async {
      final operation = _client.mutations.begin(target: 'acp-auth:$accountId');
      try {
        final reply = await _api.cancelAcpAuth(
          operationId: operation.id,
          accountId: accountId,
          targetOperationId: OperationId(targetOperationId),
        );
        return _accept(operation, reply);
      } catch (error, stack) {
        _reject(operation, error);
        Error.throwWithStackTrace(error, stack);
      } finally {
        if (identical(_cancelling[accountId], admitted)) {
          _cancelling.remove(accountId);
        }
      }
    });
  }

  Future<AcpAuthSnapshotView> _start(
    String accountId,
    AcpAuthActionView action,
  ) async {
    if (_client.isClosed) throw StateError('Client is closed');
    final expectedConnectionRevision = _connectionRevision(accountId);
    if (_active.containsKey(accountId)) {
      throw StudioFailure(
        code: StudioFailureCode.busy,
        message: 'An ACP authentication operation is already active',
        retryable: false,
        correlationId: 'client-acp-auth',
      );
    }
    final admitted = OperationId(
      'acp-admission:${_client.clientId}:$accountId',
    );
    _active[accountId] = admitted;
    try {
      return await _authLane.enqueue(() async {
        final operation = _client.mutations.begin(
          target: 'acp-auth:$accountId',
        );
        try {
          final reply = await _api.startAcpAuth(
            operationId: operation.id,
            accountId: accountId,
            expectedConnectionRevision: expectedConnectionRevision,
            action: action,
          );
          return _accept(operation, reply);
        } catch (error, stack) {
          _reject(operation, error);
          Error.throwWithStackTrace(error, stack);
        }
      });
    } finally {
      if (identical(_active[accountId], admitted)) {
        _active.remove(accountId);
      }
    }
  }

  AcpAuthSnapshotView _accept(
    OperationHandle operation,
    AcpAuthCommandReply reply,
  ) {
    if (!_client.isClosed) _client.acpAuth.apply(reply.snapshot);
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

  /// 当前配置的连接身份；账号不存在时明确失败，不用旧观察猜测。
  int _connectionRevision(String accountId) {
    final account = _client.settings.state.canonical?.acpAccounts
        .where((candidate) => candidate.accountId == accountId)
        .firstOrNull;
    if (account == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'ACP account is unavailable: $accountId',
        retryable: false,
        correlationId: 'client-acp-auth',
      );
    }
    return account.connectionRevision;
  }

  StudioTransport get _api => _client.transport;

  Future<void> close() {
    _authLane.seal();
    _cancelLane.seal();
    return Future.wait([_authLane.join(), _cancelLane.join()]);
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
