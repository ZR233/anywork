import '../../../models.dart';

/// 领域传输状态：只描述订阅通道，不替代 canonical 内容。
///
/// Lagged / failure / closed 把 phase 标成重同步或失败，并保留最后有效内容。
enum DomainSyncPhase { idle, connecting, ready, reconnecting, failed }

class DomainSyncStatus {
  const DomainSyncStatus({
    this.phase = DomainSyncPhase.idle,
    this.errorMessage,
    this.retryExhausted = false,
  });

  final DomainSyncPhase phase;
  final String? errorMessage;
  final bool retryExhausted;

  static const ready = DomainSyncStatus(phase: DomainSyncPhase.ready);

  bool get isReady => phase == DomainSyncPhase.ready;

  DomainSyncStatus connected() => ready;

  /// 由 topic 连接投影转换。`null` 表示租约已全部释放，通道回到 idle。
  factory DomainSyncStatus.fromConnection(
    ProductTopicConnectionStateView? view,
  ) {
    if (view == null) return const DomainSyncStatus();
    return DomainSyncStatus(
      phase: switch (view.phase) {
        ProductTopicConnectionPhase.connecting => DomainSyncPhase.connecting,
        ProductTopicConnectionPhase.connected => DomainSyncPhase.ready,
        ProductTopicConnectionPhase.reconnecting =>
          DomainSyncPhase.reconnecting,
        ProductTopicConnectionPhase.failed => DomainSyncPhase.failed,
      },
      errorMessage: view.errorMessage,
      retryExhausted: view.retryExhausted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainSyncStatus &&
          phase == other.phase &&
          errorMessage == other.errorMessage &&
          retryExhausted == other.retryExhausted;

  @override
  int get hashCode => Object.hash(phase, errorMessage, retryExhausted);
}

/// 命令 lane 的 in-flight 结果。目标值不写入 canonical 字段。
enum CommandPhase { pending, failed, succeeded }

class CommandTarget {
  const CommandTarget({
    this.accountId,
    this.modelId,
    this.effort,
    this.enabled,
    this.label,
  });

  final String? accountId;
  final String? modelId;
  final String? effort;
  final bool? enabled;
  final String? label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandTarget &&
          accountId == other.accountId &&
          modelId == other.modelId &&
          effort == other.effort &&
          enabled == other.enabled &&
          label == other.label;

  @override
  int get hashCode => Object.hash(accountId, modelId, effort, enabled, label);
}

class CommandStatus {
  const CommandStatus({
    required this.key,
    required this.phase,
    this.target = const CommandTarget(),
    this.error,
    this.accepted = false,
    this.startedAtMs = 0,
  });

  final String key;
  final CommandPhase phase;
  final CommandTarget target;
  final StudioFailure? error;

  /// 该命令已收到**需要身份观察的受理回执**。
  ///
  /// 这是「回执已到」这一事实，不是猜测：为 `true` 时请求已受理，正在等待 canonical
  /// 状态收敛（`phase` 仍可能是 `pending`）；界面据此区分「请求在途、尚未受理」与
  /// 「已受理、等待收敛」，不得把它当作已生效。命令结算或清除时该条状态消失。
  final bool accepted;

  /// 该命令被登记时的 Unix 毫秒时间戳；`0` 表示未记录。
  ///
  /// 命令登记时写入一次；之后「已受理」「失败」的状态重建都保留它。界面可以用自己的
  /// 墙钟计算 elapsed，而不必把计时器放进会被重建的 widget 本地状态。
  final int startedAtMs;

  bool get isPending => phase == CommandPhase.pending;

  /// 保留本次命令的身份与错误，只标记「已受理」。
  CommandStatus withAccepted() => CommandStatus(
    key: key,
    phase: phase,
    target: target,
    error: error,
    accepted: true,
    startedAtMs: startedAtMs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandStatus &&
          key == other.key &&
          phase == other.phase &&
          target == other.target &&
          error == other.error &&
          accepted == other.accepted &&
          startedAtMs == other.startedAtMs;

  @override
  int get hashCode =>
      Object.hash(key, phase, target, error, accepted, startedAtMs);
}

bool commandMapsEqual(
  Map<String, CommandStatus> left,
  Map<String, CommandStatus> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

int commandMapHash(Map<String, CommandStatus> commands) => Object.hashAll(
  commands.entries.map((entry) => Object.hash(entry.key, entry.value)),
);

/// 非 [StudioFailure] 的异常包装成 typed 错误，避免 lane 丢失失败事实。
StudioFailure typedCommandFailure(Object error, {String? correlationId}) {
  if (error is StudioFailure) return error;
  return StudioFailure(
    code: StudioFailureCode.internal,
    message: error.toString(),
    retryable: false,
    correlationId: correlationId ?? 'client-command',
  );
}

bool isRetryableRevisionFailure(Object error) {
  return error is StudioFailure &&
      (error.code == StudioFailureCode.staleRevision ||
          error.code == StudioFailureCode.conflict);
}
