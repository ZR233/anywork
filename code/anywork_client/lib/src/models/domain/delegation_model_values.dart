import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../../account_usage/domain/statistics_values.dart';
import '../../configuration/domain/configuration_state.dart';
import 'model_evaluation_values.dart';
import 'model_guide_values.dart';
import 'model_values.dart';

part 'delegation_model_values.freezed.dart';

enum DelegationModelCapability {
  toolCalling,
  parallelToolCalls,
  reasoning,
  imageInput,
  audioInput,
  videoInput,
  fileInput,
  customTools,
  freeformTools,
  webSearch,
  streaming,
}

/// Filters are native policy inputs, not a Dart ranking/qualification engine.
@freezed
final class ListDelegationModelsRequest with _$ListDelegationModelsRequest {
  ListDelegationModelsRequest({
    List<DelegationModelCapability> capabilities = const [],
    this.taskCategory,
    this.accountId,
    this.billingKind,
    this.minContextWindow,
    this.limit,
    this.cursor,
  }) : capabilities = List.unmodifiable(capabilities);
  final List<DelegationModelCapability> capabilities;
  final AgentTaskCategory? taskCategory;
  final String? accountId;
  final BillingKind? billingKind;
  final int? minContextWindow;
  final int? limit;
  final String? cursor;
}

@Freezed(toStringOverride: false)
final class DelegationModelList with _$DelegationModelList {
  DelegationModelList({
    required List<DelegationModelListItem> models,
    required this.catalogRevision,
    required this.nextCursor,
  }) : models = List.unmodifiable(models);
  final List<DelegationModelListItem> models;
  final int catalogRevision;
  final String? nextCursor;
}

@Freezed(toStringOverride: false)
final class DelegationModelListItem with _$DelegationModelListItem {
  DelegationModelListItem({
    required this.key,
    required this.accountName,
    required this.displayName,
    required this.summary,
    required List<AgentTaskCategory> taskSuitability,
    required this.contextWindow,
    required this.capabilities,
    required List<String> reasoningEfforts,
    required this.pricing,
    required this.billingKind,
    required this.performance,
    required this.evaluations,
  }) : taskSuitability = List.unmodifiable(taskSuitability),
       reasoningEfforts = List.unmodifiable(reasoningEfforts);
  final AccountModelKey key;
  final String accountName;
  final String displayName;
  final String? summary;
  final List<AgentTaskCategory> taskSuitability;
  final int? contextWindow;
  final ModelCapabilities capabilities;
  final List<String> reasoningEfforts;
  final ModelPricing? pricing;
  final BillingKind billingKind;
  final LocalModelPerformanceSummary performance;
  final AgentEvaluationSummary evaluations;
}

/// Original Rust-issued pairing credential from ConfigurationHeader.roleRead,
/// plus the exact account/model. Native must resolve sources.reference and
/// verify the complete original pair and its two business clocks before pinning
/// material. An echo or independently observed latest targets are not proof.
@freezed
abstract class DelegationModelReadTarget with _$DelegationModelReadTarget {
  const factory DelegationModelReadTarget({
    required ConfigurationRoleReadTarget sources,
    required AccountModelKey model,
  }) = _DelegationModelReadTarget;
}

@Freezed(toStringOverride: false)
final class DelegationModelDetail with _$DelegationModelDetail {
  DelegationModelDetail({
    required this.target,
    required this.scope,
    required this.accountName,
    required this.descriptor,
    required this.available,
    required this.unavailableReason,
    required this.billingKind,
    required this.guide,
    required this.performance,
    required this.evaluations,
    required List<AgentEvaluation> recentEvaluations,
  }) : recentEvaluations = List.unmodifiable(recentEvaluations);
  final DelegationModelReadTarget target;

  /// Value identity, not the runtime resource owner/handle.
  final ProductReadScopeIdentity scope;
  final String accountName;
  final ModelDescriptor descriptor;
  final bool available;
  final String? unavailableReason;
  final BillingKind billingKind;
  final ModelSelectionGuide? guide;
  final LocalModelPerformanceSummary performance;
  final AgentEvaluationSummary evaluations;
  final List<AgentEvaluation> recentEvaluations;
}
