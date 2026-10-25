import 'account_models.dart';

enum DelegationMode { profile, automatic }

enum DelegationPreference { economy, balanced, fast }

enum BillingKind { metered, subscription, noCharge, unknown }

class DelegationSettingsView {
  const DelegationSettingsView({
    this.mode = DelegationMode.profile,
    this.preference = DelegationPreference.balanced,
  });

  final DelegationMode mode;
  final DelegationPreference preference;

  @override
  bool operator ==(Object other) =>
      other is DelegationSettingsView &&
      mode == other.mode &&
      preference == other.preference;
  @override
  int get hashCode => Object.hash(mode, preference);
}

/// Exact persisted route identity shared by child summaries and evaluations.
class NewThreadModelRoute {
  const NewThreadModelRoute({
    required this.accountId,
    required this.modelId,
    this.effort,
  });
  final String accountId;
  final String modelId;
  final String? effort;

  @override
  bool operator ==(Object other) =>
      other is NewThreadModelRoute &&
      accountId == other.accountId &&
      modelId == other.modelId &&
      effort == other.effort;
  @override
  int get hashCode => Object.hash(accountId, modelId, effort);
}

class DelegationModelKey {
  const DelegationModelKey({required this.accountId, required this.modelId});
  final String accountId;
  final String modelId;

  @override
  bool operator ==(Object other) =>
      other is DelegationModelKey &&
      accountId == other.accountId &&
      modelId == other.modelId;
  @override
  int get hashCode => Object.hash(accountId, modelId);
}

enum AgentTaskCategory {
  reasoning,
  coding,
  tooling,
  longContext,
  multimodal,
  general,
}

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

class ListDelegationModelsRequest {
  const ListDelegationModelsRequest({
    this.capabilities = const [],
    this.taskCategory,
    this.accountId,
    this.billingKind,
    this.minContextWindow,
    this.limit,
    this.cursor,
  });
  final List<DelegationModelCapability> capabilities;
  final AgentTaskCategory? taskCategory;
  final String? accountId;
  final BillingKind? billingKind;
  final int? minContextWindow;
  final int? limit;
  final String? cursor;
}

class DelegationModelList {
  const DelegationModelList({
    required this.models,
    required this.catalogRevision,
    this.nextCursor,
  });
  final List<DelegationModelListItem> models;
  final int catalogRevision;
  final String? nextCursor;
}

class DelegationModelListItem {
  const DelegationModelListItem({
    required this.key,
    required this.accountName,
    required this.displayName,
    this.summary,
    required this.taskSuitability,
    this.contextWindow,
    required this.capabilities,
    required this.reasoningEfforts,
    this.pricing,
    required this.billingKind,
    required this.performance,
    required this.evaluations,
  });
  final DelegationModelKey key;
  final String accountName;
  final String displayName;
  final String? summary;
  final List<AgentTaskCategory> taskSuitability;
  final int? contextWindow;
  final DelegationModelCapabilities capabilities;
  final List<String> reasoningEfforts;
  final ModelPricingView? pricing;
  final BillingKind billingKind;
  final LocalModelPerformanceSummary performance;
  final AgentEvaluationSummary evaluations;
}

class DelegationModelCapabilities {
  const DelegationModelCapabilities({
    required this.input,
    required this.output,
    required this.streaming,
    required this.temperature,
    required this.reasoning,
    required this.webSearch,
    required this.functionCalling,
    required this.parallelToolCalls,
    required this.customTools,
    required this.freeformTools,
    required this.instructionSnapshotOverrides,
    this.nativeContextFamily,
  });
  final List<ModelInputCapabilityView> input;
  final List<ModelModalityView> output;
  final bool streaming;
  final bool temperature;
  final bool reasoning;
  final bool webSearch;
  final bool functionCalling;
  final bool parallelToolCalls;
  final bool customTools;
  final bool freeformTools;
  final bool instructionSnapshotOverrides;
  final String? nativeContextFamily;
}

class ModelPricingView {
  const ModelPricingView({
    required this.currency,
    required this.source,
    required this.verifiedAt,
    required this.tiers,
  });
  final String currency;
  final String source;
  final int verifiedAt;
  final List<ModelPriceTierView> tiers;
}

class DelegationModelDetail {
  const DelegationModelDetail({
    required this.key,
    required this.accountName,
    required this.descriptor,
    required this.available,
    this.unavailableReason,
    required this.billingKind,
    this.guide,
    required this.performance,
    required this.evaluations,
    required this.recentEvaluations,
  });
  final DelegationModelKey key;
  final String accountName;
  final AccountModelView descriptor;
  final bool available;
  final String? unavailableReason;
  final BillingKind billingKind;
  final ModelSelectionGuide? guide;
  final LocalModelPerformanceSummary performance;
  final AgentEvaluationSummary evaluations;
  final List<AgentEvaluation> recentEvaluations;
}

class LocalModelPerformanceSummary {
  const LocalModelPerformanceSummary({
    required this.sampleCount,
    this.tokensPerSecond,
    this.averageTtftMillis,
    required this.ttftSampleCount,
    this.updatedAt,
  });
  final int sampleCount;
  final double? tokensPerSecond;
  final double? averageTtftMillis;
  final int ttftSampleCount;
  final int? updatedAt;
}

class ModelSelectionGuide {
  const ModelSelectionGuide({
    required this.summary,
    required this.taskSuitability,
    required this.limitations,
    required this.sources,
  });
  final String summary;
  final List<AgentTaskCategory> taskSuitability;
  final List<String> limitations;
  final List<ModelSelectionSource> sources;
}

enum ModelSelectionSourceKind { official, benchmark, community }

class ModelSelectionSource {
  const ModelSelectionSource({
    required this.kind,
    required this.url,
    required this.verifiedAt,
    this.measurement,
  });
  final ModelSelectionSourceKind kind;
  final String url;
  final int verifiedAt;
  final ModelSelectionMeasurement? measurement;
}

class ModelSelectionMeasurement {
  const ModelSelectionMeasurement({
    required this.model,
    this.effort,
    required this.metric,
    this.metricVersion,
    this.score,
  });
  final String model;
  final String? effort;
  final String metric;
  final String? metricVersion;
  final double? score;
}

enum AgentEvaluationOutcome { passed, failed, notRated }

/// Final task evaluations are separate from call/performance samples and are read-only here.
class AgentEvaluation {
  const AgentEvaluation({
    required this.agentId,
    required this.parentAgentId,
    required this.model,
    required this.profileId,
    required this.mode,
    required this.preference,
    required this.turnId,
    required this.revision,
    required this.taskCategory,
    required this.outcome,
    this.quality,
    this.instructionFollowing,
    required this.comment,
    required this.createdAt,
    required this.updatedAt,
  });
  final String agentId;
  final String parentAgentId;
  final NewThreadModelRoute model;
  final String profileId;
  final DelegationMode mode;
  final DelegationPreference preference;
  final String turnId;
  final int revision;
  final AgentTaskCategory taskCategory;
  final AgentEvaluationOutcome outcome;
  final int? quality;
  final int? instructionFollowing;
  final String comment;
  final int createdAt;
  final int updatedAt;
}

class AgentEvaluationSummary {
  const AgentEvaluationSummary({
    required this.window,
    required this.ratedSamples,
    required this.passed,
    required this.failed,
    required this.notRated,
    this.averageQuality,
    this.averageInstructionFollowing,
  });
  final int window;
  final int ratedSamples;
  final int passed;
  final int failed;
  final int notRated;
  final double? averageQuality;
  final double? averageInstructionFollowing;
}
