enum StudioTurnStatus {
  queued,
  running,
  completed,
  cancelled,
  failed,
  budgetLimited,
}

enum StudioTurnActivity {
  preparing,
  thinking,
  responding,
  planning,
  runningTool,
  persisting,
}

sealed class StudioTurnState {
  const StudioTurnState();

  StudioTurnStatus get status;

  StudioTurnActivity? get activity => switch (this) {
    RunningStudioTurnState(:final activity) => activity,
    QueuedStudioTurnState() ||
    CompletedStudioTurnState() ||
    CancelledStudioTurnState() ||
    FailedStudioTurnState() ||
    BudgetLimitedStudioTurnState() => null,
  };

  String? get reason => switch (this) {
    CancelledStudioTurnState(:final cause) => cause.description,
    FailedStudioTurnState(:final failure) => failure.message,
    BudgetLimitedStudioTurnState(:final limit) =>
      'Turn budget limited: ${limit.kind.name}',
    QueuedStudioTurnState() ||
    RunningStudioTurnState() ||
    CompletedStudioTurnState() => null,
  };

  bool get isBusy => switch (this) {
    QueuedStudioTurnState() || RunningStudioTurnState() => true,
    CompletedStudioTurnState() ||
    CancelledStudioTurnState() ||
    FailedStudioTurnState() ||
    BudgetLimitedStudioTurnState() => false,
  };

  bool get isTerminal => !isBusy;
}

final class QueuedStudioTurnState extends StudioTurnState {
  const QueuedStudioTurnState({required this.queuedAt});

  final int queuedAt;

  @override
  StudioTurnStatus get status => StudioTurnStatus.queued;

  @override
  bool operator ==(Object other) =>
      other is QueuedStudioTurnState && other.queuedAt == queuedAt;

  @override
  int get hashCode => Object.hash(runtimeType, queuedAt);
}

final class RunningStudioTurnState extends StudioTurnState {
  const RunningStudioTurnState({
    required this.startedAt,
    required this.activity,
  });

  final int startedAt;

  @override
  final StudioTurnActivity activity;

  @override
  StudioTurnStatus get status => StudioTurnStatus.running;

  @override
  bool operator ==(Object other) =>
      other is RunningStudioTurnState &&
      other.startedAt == startedAt &&
      other.activity == activity;

  @override
  int get hashCode => Object.hash(runtimeType, startedAt, activity);
}

enum StudioTurnCompletion { normal, interactionRequested }

final class CompletedStudioTurnState extends StudioTurnState {
  const CompletedStudioTurnState({
    required this.startedAt,
    required this.completedAt,
    required this.completion,
  });

  final int? startedAt;
  final int completedAt;
  final StudioTurnCompletion completion;

  @override
  StudioTurnStatus get status => StudioTurnStatus.completed;

  @override
  bool operator ==(Object other) =>
      other is CompletedStudioTurnState &&
      other.startedAt == startedAt &&
      other.completedAt == completedAt &&
      other.completion == completion;

  @override
  int get hashCode =>
      Object.hash(runtimeType, startedAt, completedAt, completion);
}

sealed class StudioTurnCancellationCause {
  const StudioTurnCancellationCause();

  String get description => switch (this) {
    UnspecifiedTurnCancellation() => 'Cancelled',
    UserRequestedTurnCancellation() => 'Cancelled by user',
    RuntimeShutdownTurnCancellation() => 'Runtime shutdown',
    AgentClosedTurnCancellation() => 'Agent closed',
    InterruptedTurnCancellation() => 'Interrupted',
    RecoveryTurnCancellation() => 'Cancelled during recovery',
    CoalescedTurnCancellation(:final targetTurnId) =>
      'Merged into Turn $targetTurnId',
  };
}

final class UnspecifiedTurnCancellation extends StudioTurnCancellationCause {
  const UnspecifiedTurnCancellation();
}

final class UserRequestedTurnCancellation extends StudioTurnCancellationCause {
  const UserRequestedTurnCancellation();
}

final class RuntimeShutdownTurnCancellation
    extends StudioTurnCancellationCause {
  const RuntimeShutdownTurnCancellation();
}

final class AgentClosedTurnCancellation extends StudioTurnCancellationCause {
  const AgentClosedTurnCancellation();
}

final class InterruptedTurnCancellation extends StudioTurnCancellationCause {
  const InterruptedTurnCancellation();
}

final class RecoveryTurnCancellation extends StudioTurnCancellationCause {
  const RecoveryTurnCancellation();
}

final class CoalescedTurnCancellation extends StudioTurnCancellationCause {
  const CoalescedTurnCancellation({required this.targetTurnId});

  final String targetTurnId;

  @override
  bool operator ==(Object other) =>
      other is CoalescedTurnCancellation && other.targetTurnId == targetTurnId;

  @override
  int get hashCode => Object.hash(runtimeType, targetTurnId);
}

final class CancelledStudioTurnState extends StudioTurnState {
  const CancelledStudioTurnState({
    required this.startedAt,
    required this.requestedAt,
    required this.completedAt,
    required this.cause,
  });

  final int? startedAt;
  final int requestedAt;
  final int completedAt;
  final StudioTurnCancellationCause cause;

  @override
  StudioTurnStatus get status => StudioTurnStatus.cancelled;

  @override
  bool operator ==(Object other) =>
      other is CancelledStudioTurnState &&
      other.startedAt == startedAt &&
      other.requestedAt == requestedAt &&
      other.completedAt == completedAt &&
      other.cause == cause;

  @override
  int get hashCode =>
      Object.hash(runtimeType, startedAt, requestedAt, completedAt, cause);
}

final class FailedStudioTurnState extends StudioTurnState {
  const FailedStudioTurnState({
    required this.startedAt,
    required this.completedAt,
    required this.failure,
  });

  final int? startedAt;
  final int completedAt;
  final StudioTurnFailureView failure;

  @override
  StudioTurnStatus get status => StudioTurnStatus.failed;

  @override
  bool operator ==(Object other) =>
      other is FailedStudioTurnState &&
      other.startedAt == startedAt &&
      other.completedAt == completedAt &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(runtimeType, startedAt, completedAt, failure);
}

enum StudioTurnBudgetLimitKind {
  modelStep,
  toolCall,
  wait,
  wallClock,
  agentCount,
  agentDepth,
  finalization,
}

final class StudioTurnBudgetUsage {
  const StudioTurnBudgetUsage({
    required this.modelSteps,
    required this.toolCalls,
    required this.waitCalls,
    required this.elapsedMs,
  });

  final int modelSteps;
  final int toolCalls;
  final int waitCalls;
  final int elapsedMs;

  @override
  bool operator ==(Object other) =>
      other is StudioTurnBudgetUsage &&
      other.modelSteps == modelSteps &&
      other.toolCalls == toolCalls &&
      other.waitCalls == waitCalls &&
      other.elapsedMs == elapsedMs;

  @override
  int get hashCode => Object.hash(modelSteps, toolCalls, waitCalls, elapsedMs);
}

final class StudioTurnBudgetLimit {
  const StudioTurnBudgetLimit({required this.kind, required this.usage});

  final StudioTurnBudgetLimitKind kind;
  final StudioTurnBudgetUsage usage;

  @override
  bool operator ==(Object other) =>
      other is StudioTurnBudgetLimit &&
      other.kind == kind &&
      other.usage == usage;

  @override
  int get hashCode => Object.hash(kind, usage);
}

sealed class StudioTurnRolloverOutcome {
  const StudioTurnRolloverOutcome();
}

final class RolloverNotAttempted extends StudioTurnRolloverOutcome {
  const RolloverNotAttempted();
}

final class RolloverSucceeded extends StudioTurnRolloverOutcome {
  const RolloverSucceeded();
}

final class RolloverFailed extends StudioTurnRolloverOutcome {
  const RolloverFailed({required this.error});

  final String error;

  @override
  bool operator ==(Object other) =>
      other is RolloverFailed && other.error == error;

  @override
  int get hashCode => Object.hash(runtimeType, error);
}

final class BudgetLimitedStudioTurnState extends StudioTurnState {
  const BudgetLimitedStudioTurnState({
    required this.startedAt,
    required this.completedAt,
    required this.limit,
    required this.rollover,
  });

  final int? startedAt;
  final int completedAt;
  final StudioTurnBudgetLimit limit;
  final StudioTurnRolloverOutcome rollover;

  @override
  StudioTurnStatus get status => StudioTurnStatus.budgetLimited;

  @override
  bool operator ==(Object other) =>
      other is BudgetLimitedStudioTurnState &&
      other.startedAt == startedAt &&
      other.completedAt == completedAt &&
      other.limit == limit &&
      other.rollover == rollover;

  @override
  int get hashCode =>
      Object.hash(runtimeType, startedAt, completedAt, limit, rollover);
}

class StudioTurnView {
  const StudioTurnView({
    this.inputId,
    required this.turnId,
    required this.threadId,
    required this.revision,
    required this.state,
    required this.updatedAt,
  });

  final String? inputId;
  final String turnId;
  final String threadId;
  final int revision;
  final StudioTurnState state;
  final DateTime updatedAt;

  StudioTurnFailureView? get failure => switch (state) {
    FailedStudioTurnState(:final failure) => failure,
    QueuedStudioTurnState() ||
    RunningStudioTurnState() ||
    CompletedStudioTurnState() ||
    CancelledStudioTurnState() ||
    BudgetLimitedStudioTurnState() => null,
  };

  @override
  bool operator ==(Object other) {
    return other is StudioTurnView &&
        other.inputId == inputId &&
        other.turnId == turnId &&
        other.threadId == threadId &&
        other.revision == revision &&
        other.state == state &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(inputId, turnId, threadId, revision, state, updatedAt);
}

enum StudioProviderFailureStage {
  unknown,
  request,
  handshake,
  stream,
  attachment,
}

enum StudioProviderRecovery {
  none,
  httpFallback,
  refreshAttachments,
  fullContext,
}

enum StudioModelRecoveryStopReason {
  budgetExhausted,
  sideEffects,
  saveFailed,
  repairFailed,
  waitUnrepresentable,
  contextCompactionRequired,
  permanentFailure,
  cancelled,
}

enum StudioRetryDisposition { retryable, permanent, waitUnrepresentable }

enum StudioModelRecoveryPhase {
  repairing,
  waiting,
  retrying,
  recovered,
  exhausted,
  failed,
  cancelled,
}

final class StudioModelRecoveryNotice {
  const StudioModelRecoveryNotice({
    required this.phase,
    required this.retryCount,
    required this.maxRetries,
    this.failureKind,
    this.reason,
    this.effectiveWaitMillis,
    this.failure,
  });

  final StudioModelRecoveryPhase phase;
  final int retryCount;
  final int maxRetries;
  final String? failureKind;
  final StudioProviderRecovery? reason;
  final BigInt? effectiveWaitMillis;
  final StudioTurnFailureView? failure;

  static StudioModelRecoveryNotice? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final phase = StudioModelRecoveryPhase.values.asNameMap()[raw['phase']];
    final count = raw['retryCount'];
    final limit = raw['maxRetries'];
    if (phase == null ||
        count is! int ||
        count < 0 ||
        limit is! int ||
        limit < 0) {
      return null;
    }
    return StudioModelRecoveryNotice(
      phase: phase,
      retryCount: count,
      maxRetries: limit,
      failureKind: _productString(raw['failureKind']),
      reason: StudioProviderRecovery.values.asNameMap()[raw['reason']],
      effectiveWaitMillis: _productMillis(raw['effectiveWaitMillis']),
      failure: StudioTurnFailureView.fromJson(raw['failure']),
    );
  }

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'failureKind': failureKind,
    'reason': reason?.name,
    'retryCount': retryCount,
    'maxRetries': maxRetries,
    'effectiveWaitMillis': effectiveWaitMillis?.toString(),
    'failure': ?failure?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is StudioModelRecoveryNotice &&
      other.phase == phase &&
      other.retryCount == retryCount &&
      other.maxRetries == maxRetries &&
      other.failureKind == failureKind &&
      other.reason == reason &&
      other.effectiveWaitMillis == effectiveWaitMillis &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(
    phase,
    retryCount,
    maxRetries,
    failureKind,
    reason,
    effectiveWaitMillis,
    failure,
  );
}

final class StudioModelRecoveryInfo {
  const StudioModelRecoveryInfo({
    this.retryCount,
    this.maxRetries,
    this.effectiveWaitMillis,
    this.reason,
    this.stopReason,
    this.error,
  });

  final int? retryCount;
  final int? maxRetries;
  final BigInt? effectiveWaitMillis;
  final StudioProviderRecovery? reason;
  final StudioModelRecoveryStopReason? stopReason;
  final String? error;

  static StudioModelRecoveryInfo? _fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    return StudioModelRecoveryInfo(
      retryCount: _productInt(raw['retryCount']),
      maxRetries: _productInt(raw['maxRetries']),
      effectiveWaitMillis: _productMillis(raw['effectiveWaitMillis']),
      reason: StudioProviderRecovery.values.asNameMap()[raw['reason']],
      stopReason: StudioModelRecoveryStopReason.values
          .asNameMap()[raw['stopReason']],
      error: _productString(raw['error']),
    );
  }

  Map<String, Object?> _toJson() => {
    'retryCount': retryCount,
    'maxRetries': maxRetries,
    'effectiveWaitMillis': effectiveWaitMillis?.toString(),
    'reason': reason?.name,
    'stopReason': stopReason?.name,
    'error': error,
  };

  @override
  bool operator ==(Object other) =>
      other is StudioModelRecoveryInfo &&
      other.retryCount == retryCount &&
      other.maxRetries == maxRetries &&
      other.effectiveWaitMillis == effectiveWaitMillis &&
      other.reason == reason &&
      other.stopReason == stopReason &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    retryCount,
    maxRetries,
    effectiveWaitMillis,
    reason,
    stopReason,
    error,
  );
}

final class StudioTurnFailureView {
  const StudioTurnFailureView({
    required this.category,
    required this.providerKind,
    required this.code,
    required this.httpStatus,
    required this.message,
    required this.retryDisposition,
    required this.retryAfterMs,
    this.errorType,
    this.requestId,
    this.stage,
    this.recovery,
  });

  final String category;
  final String? providerKind;
  final String? code;
  final int? httpStatus;
  final String message;
  final StudioRetryDisposition retryDisposition;
  final BigInt? retryAfterMs;
  final String? errorType;
  final String? requestId;
  final StudioProviderFailureStage? stage;
  final StudioModelRecoveryInfo? recovery;

  static StudioTurnFailureView? fromJson(Object? raw) {
    if (raw is! Map<String, Object?> || raw['retry'] is! Map<String, Object?>) {
      return null;
    }
    final category = raw['category'];
    final message = raw['message'];
    final retry = raw['retry'] as Map<String, Object?>;
    final disposition = StudioRetryDisposition.values
        .asNameMap()[retry['kind']];
    if (category is! String || message is! String || disposition == null) {
      return null;
    }
    return StudioTurnFailureView(
      category: category,
      providerKind: _productString(raw['providerKind']),
      code: _productString(raw['code']),
      httpStatus: _productInt(raw['httpStatus']),
      message: message,
      retryDisposition: disposition,
      retryAfterMs: _productMillis(retry['retryAfterMs']),
      errorType: _productString(raw['errorType']),
      requestId: _productString(raw['requestId']),
      stage: StudioProviderFailureStage.values.asNameMap()[raw['stage']],
      recovery: StudioModelRecoveryInfo._fromJson(raw['recovery']),
    );
  }

  Map<String, Object?> toJson() => {
    'category': category,
    'providerKind': ?providerKind,
    'code': ?code,
    'httpStatus': ?httpStatus,
    'errorType': ?errorType,
    'requestId': ?requestId,
    'stage': ?stage?.name,
    'recovery': ?recovery?._toJson(),
    'message': message,
    'retry': {
      'kind': retryDisposition.name,
      'retryAfterMs': ?retryAfterMs?.toString(),
    },
  };

  @override
  bool operator ==(Object other) =>
      other is StudioTurnFailureView &&
      other.category == category &&
      other.providerKind == providerKind &&
      other.code == code &&
      other.httpStatus == httpStatus &&
      other.message == message &&
      other.retryDisposition == retryDisposition &&
      other.retryAfterMs == retryAfterMs &&
      other.errorType == errorType &&
      other.requestId == requestId &&
      other.stage == stage &&
      other.recovery == recovery;

  @override
  int get hashCode => Object.hash(
    category,
    providerKind,
    code,
    httpStatus,
    message,
    retryDisposition,
    retryAfterMs,
    errorType,
    requestId,
    stage,
    recovery,
  );
}

String? _productString(Object? raw) => raw is String ? raw : null;

int? _productInt(Object? raw) => raw is int ? raw : null;

BigInt? _productMillis(Object? raw) {
  if (raw is! String) return null;
  final millis = BigInt.tryParse(raw, radix: 10);
  return millis != null && !millis.isNegative && millis.bitLength <= 64
      ? millis
      : null;
}
