import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../../account_usage/domain/statistics_values.dart';
import '../../modes/domain/delegation_values.dart';
import '../domain/delegation_model_values.dart';
import '../domain/model_evaluation_values.dart';
import '../domain/model_guide_values.dart';
import '../domain/model_values.dart';
import 'model_reads.dart';

part 'delegation_model_reads.freezed.dart';

/// The scope pins material resolved by the original Rust pairing credential.
/// Guide/performance/evaluation windows are captured when the scope opens and
/// then immutable, not part of a fabricated cross-database transaction. Returning
/// this complete target echo does not replace native verification/pinning.
@Freezed(toStringOverride: false)
abstract class DelegationModelReadHeader with _$DelegationModelReadHeader {
  const factory DelegationModelReadHeader({
    required ProductReadScopeIdentity scope,
    required DelegationModelReadTarget target,
    required ReadText accountName,
    required ModelDescriptorRead descriptor,
    required bool available,
    required ReadText? unavailableReason,
    required BillingKind billingKind,
    required ModelSelectionGuideRead? guide,
    required LocalModelPerformanceSummary performance,
    required AgentEvaluationSummary evaluations,
    required TypedListRef recentEvaluations,
  }) = _DelegationModelReadHeader;
}

@Freezed(toStringOverride: false)
final class ModelSelectionGuideRead with _$ModelSelectionGuideRead {
  ModelSelectionGuideRead({
    required this.summary,
    required List<AgentTaskCategory> taskSuitability,
    required this.limitations,
    required this.sources,
  }) : taskSuitability = List.unmodifiable(taskSuitability);
  final ReadText summary;
  final List<AgentTaskCategory> taskSuitability;
  final TypedListRef limitations;
  final TypedListRef sources;
}

@Freezed(toStringOverride: false)
abstract class ModelSelectionSourceRead with _$ModelSelectionSourceRead {
  const factory ModelSelectionSourceRead({
    required ModelSelectionSourceKind kind,
    required ReadText url,
    required int verifiedAt,
    required ModelSelectionMeasurementRead? measurement,
  }) = _ModelSelectionSourceRead;
}

@Freezed(toStringOverride: false)
abstract class ModelSelectionMeasurementRead
    with _$ModelSelectionMeasurementRead {
  const factory ModelSelectionMeasurementRead({
    required ReadText model,
    required ReadText? effort,
    required ReadText metric,
    required ReadText? metricVersion,
    required double? score,
  }) = _ModelSelectionMeasurementRead;
}

@Freezed(toStringOverride: false)
abstract class AgentEvaluationRead with _$AgentEvaluationRead {
  const factory AgentEvaluationRead({
    required ReadText agentId,
    required ReadText parentAgentId,
    required ReadText accountId,
    required ReadText modelId,
    required ReadText? effort,
    required ReadText profileId,
    required DelegationMode mode,
    required DelegationPreference preference,
    required ReadText turnId,
    required int revision,
    required AgentTaskCategory taskCategory,
    required AgentEvaluationOutcome outcome,
    required int? quality,
    required int? instructionFollowing,
    required ReadText comment,
    required int createdAt,
    required int updatedAt,
  }) = _AgentEvaluationRead;
}

@Freezed(toStringOverride: false)
final class ModelSelectionSourceReadPage with _$ModelSelectionSourceReadPage {
  ModelSelectionSourceReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<ModelSelectionSourceRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ModelSelectionSourceRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class AgentEvaluationReadPage with _$AgentEvaluationReadPage {
  AgentEvaluationReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<AgentEvaluationRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<AgentEvaluationRead> items;
  final int? nextOffset;
}
