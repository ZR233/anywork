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
    this.providerId,
    this.model,
    this.effort,
    this.enabled,
    this.label,
  });

  final String? providerId;
  final String? model;
  final String? effort;
  final bool? enabled;
  final String? label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandTarget &&
          providerId == other.providerId &&
          model == other.model &&
          effort == other.effort &&
          enabled == other.enabled &&
          label == other.label;

  @override
  int get hashCode => Object.hash(providerId, model, effort, enabled, label);
}

class CommandStatus {
  const CommandStatus({
    required this.key,
    required this.phase,
    this.target = const CommandTarget(),
    this.error,
  });

  final String key;
  final CommandPhase phase;
  final CommandTarget target;
  final StudioFailure? error;

  bool get isPending => phase == CommandPhase.pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandStatus &&
          key == other.key &&
          phase == other.phase &&
          target == other.target &&
          error == other.error;

  @override
  int get hashCode => Object.hash(key, phase, target, error);
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
