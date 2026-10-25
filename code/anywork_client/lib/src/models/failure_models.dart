enum StudioFailureCode {
  notInitialized,
  runtimeStopped,
  instanceBusy,
  invalidArgument,
  notFound,
  busy,
  conflict,
  staleRevision,
  permissionDenied,
  cancelled,
  cancellationTooLate,
  overloaded,
  unavailable,
  protocol,
  storage,
  update,
  internal,
}

/// 同类别失败下的稳定产品原因。
///
/// 错误类别说明「哪一类失败」，原因标签进一步说明具体含义，使调用方不必解析提示文本。
/// 标签与后端 `details.reason` 的 camelCase 值一一对应；未识别的标签保留为 `null`，
/// 不猜测成任何一个已知原因。
enum StudioFailureReason {
  /// 用户不能对子会话发送、继续或提交；子会话的执行由主智能体调度。
  childThreadRequiresParentScheduling,

  /// 目标会话当前没有可认领的继续点。
  continuationUnavailable,

  /// 目标继续点已被另一次受理认领。
  continuationClaimed,

  /// 调用方冻结的继续点已经不是当前继续点。
  staleContinuation,

  /// 调用方冻结的执行编号不是当前执行。
  staleExecution,

  /// 该会话仍有当前执行或正在清理，不能开始新的轮次。
  executionInProgress,

  /// 交互不允许由主会话转交处理。
  interactionNotHosted,

  /// 交互版本已经不是调用方观察到的那个。
  staleInteraction,

  /// 目标会话已归档：只读，拒绝继续、发送、停止与交互决议。
  threadArchived;

  /// Canonical camelCase 标签。
  String get label => name;

  /// 按 canonical 标签解析；未知或缺失返回 `null`。
  static StudioFailureReason? fromLabel(String? label) => switch (label) {
    'childThreadRequiresParentScheduling' =>
      StudioFailureReason.childThreadRequiresParentScheduling,
    'continuationUnavailable' => StudioFailureReason.continuationUnavailable,
    'continuationClaimed' => StudioFailureReason.continuationClaimed,
    'staleContinuation' => StudioFailureReason.staleContinuation,
    'staleExecution' => StudioFailureReason.staleExecution,
    'executionInProgress' => StudioFailureReason.executionInProgress,
    'interactionNotHosted' => StudioFailureReason.interactionNotHosted,
    'staleInteraction' => StudioFailureReason.staleInteraction,
    'threadArchived' => StudioFailureReason.threadArchived,
    _ => null,
  };
}

/// Returns the structured reason carried by [error], if it is a known one.
StudioFailureReason? studioFailureReason(Object? error) =>
    error is StudioFailure ? error.reason : null;

class StudioFailure implements Exception {
  const StudioFailure({
    required this.code,
    required this.message,
    required this.retryable,
    required this.correlationId,
    this.detailsJson,
    this.reason,
  });

  final StudioFailureCode code;
  final String message;
  final bool retryable;
  final String correlationId;
  final String? detailsJson;

  /// 结构化原因标签；`null` 表示后端未提供可识别的原因。
  final StudioFailureReason? reason;

  @override
  String toString() => '$message (correlation id: $correlationId)';
}
