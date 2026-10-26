import 'package:freezed_annotation/freezed_annotation.dart';

import '../../modes/domain/delegation_values.dart';
import 'model_values.dart';

part 'model_evaluation_values.freezed.dart';

enum AgentTaskCategory {
  reasoning,
  coding,
  tooling,
  longContext,
  multimodal,
  general,
}

enum AgentEvaluationOutcome { passed, failed, notRated }

/// Read-only final-task evidence, separate from call/performance history. The
/// native collaboration owner, never a Dart caller, supplies frozen identity.
@Freezed(toStringOverride: false)
abstract class AgentEvaluation with _$AgentEvaluation {
  const factory AgentEvaluation({
    required String agentId,
    required String parentAgentId,
    required ModelSelection model,
    required String profileId,
    required DelegationMode mode,
    required DelegationPreference preference,
    required String turnId,
    required int revision,
    required AgentTaskCategory taskCategory,
    required AgentEvaluationOutcome outcome,
    required int? quality,
    required int? instructionFollowing,
    required String comment,
    required int createdAt,
    required int updatedAt,
  }) = _AgentEvaluation;
}

/// Canonical recent-window summary. Dart does not recompute averages, infer
/// missing samples or merge local evaluations with external benchmarks.
@freezed
abstract class AgentEvaluationSummary with _$AgentEvaluationSummary {
  const factory AgentEvaluationSummary({
    required int window,
    required int ratedSamples,
    required int passed,
    required int failed,
    required int notRated,
    required double? averageQuality,
    required double? averageInstructionFollowing,
  }) = _AgentEvaluationSummary;
}
