import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_execution.freezed.dart';

enum AgentExecutionPhase {
  preparing,
  awaitingStorage,
  awaitingAdmission,
  running,
  stopping,
}

/// Canonical execution identity, including preparation before a Turn exists.
@freezed
abstract class AgentExecution with _$AgentExecution {
  const factory AgentExecution({
    required String id,
    required AgentExecutionPhase phase,
    required String? turnId,
  }) = _AgentExecution;
}

enum ContinuationReason {
  userStop,
  hostShutdown,
  processInterrupted,
  stepLimit,
  executionFailed,
}

/// A persisted continuation; clients must not infer it from the last message.
@freezed
abstract class ContinuationView with _$ContinuationView {
  const factory ContinuationView({
    required String id,
    required String? sourceTurnId,
    required ContinuationReason? reason,
    required int createdAt,
    required bool claimed,
  }) = _ContinuationView;
}
