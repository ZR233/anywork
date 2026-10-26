import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/modes.dart'
    show DelegationMode, DelegationPreference;

import '../../../../rust/api/studio/products/read/delegation_model_values.dart'
    as native;
import '../../../../rust/api/studio/products/read/primitives.dart' as primitive;
import '../../../../rust/api/studio/types/delegation.dart' as scalar;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../configuration/route_values.dart'
    show configurationRoleTargetFromBridge, configurationRoleTargetToBridge;
import '../configuration/scalar_values.dart'
    show configurationBillingFromBridge;
import '../identity_converters.dart';
import '../model_read_values.dart';
import 'numeric_values.dart';

native.BridgeDelegationModelReadTarget delegationTargetToBridge(
  DelegationModelReadTarget value,
) => native.BridgeDelegationModelReadTarget(
  sources: configurationRoleTargetToBridge(value.sources),
  model: primitive.BridgeAccountModelKey(
    accountId: value.model.accountId,
    modelId: value.model.modelId,
  ),
);

DelegationModelReadTarget delegationTargetFromBridge(
  native.BridgeDelegationModelReadTarget value,
) => DelegationModelReadTarget(
  sources: configurationRoleTargetFromBridge(value.sources),
  model: AccountModelKey(
    accountId: value.model.accountId,
    modelId: value.model.modelId,
  ),
);

DelegationModelReadHeader delegationHeaderFromBridge(
  native.BridgeDelegationModelReadHeader value,
) => DelegationModelReadHeader(
  scope: productScopeFromBridge(value.scope),
  target: delegationTargetFromBridge(value.target),
  accountName: readTextFromBridge(value.accountName),
  descriptor: modelDescriptorReadFromBridge(value.descriptor),
  available: value.available,
  unavailableReason: nullableReadText(value.unavailableReason),
  billingKind: configurationBillingFromBridge(value.billingKind),
  guide: value.guide == null ? null : modelGuideFromBridge(value.guide!),
  performance: modelPerformanceFromBridge(value.performance),
  evaluations: modelEvaluationSummaryFromBridge(value.evaluations),
  recentEvaluations: typedListFromBridge(value.recentEvaluations),
);

ModelSelectionGuideRead modelGuideFromBridge(
  native.BridgeModelSelectionGuideRead value,
) => ModelSelectionGuideRead(
  summary: readTextFromBridge(value.summary),
  taskSuitability: value.taskSuitability
      .map(modelTaskCategoryFromBridge)
      .toList(growable: false),
  limitations: typedListFromBridge(value.limitations),
  sources: typedListFromBridge(value.sources),
);

ModelSelectionSourceRead modelSelectionSourceFromBridge(
  native.BridgeModelSelectionSourceRead value,
) => ModelSelectionSourceRead(
  kind: switch (value.kind) {
    scalar.BridgeModelSelectionSourceKind.official =>
      ModelSelectionSourceKind.official,
    scalar.BridgeModelSelectionSourceKind.benchmark =>
      ModelSelectionSourceKind.benchmark,
    scalar.BridgeModelSelectionSourceKind.community =>
      ModelSelectionSourceKind.community,
  },
  url: readTextFromBridge(value.url),
  verifiedAt: exactI64(
    BigInt.from(value.verifiedAt),
    'model source verified Unix seconds',
  ),
  measurement: value.measurement == null
      ? null
      : modelMeasurementFromBridge(value.measurement!),
);

ModelSelectionMeasurementRead modelMeasurementFromBridge(
  native.BridgeModelSelectionMeasurementRead value,
) => ModelSelectionMeasurementRead(
  model: readTextFromBridge(value.model),
  effort: nullableReadText(value.effort),
  metric: readTextFromBridge(value.metric),
  metricVersion: nullableReadText(value.metricVersion),
  score: nullableFiniteModelNumber(value.score, 'model measurement score'),
);

LocalModelPerformanceSummary modelPerformanceFromBridge(
  scalar.BridgeLocalModelPerformanceSummary value,
) => LocalModelPerformanceSummary(
  sampleCount: exactU64(value.sampleCount, 'model performance samples'),
  tokensPerSecond: nullableFiniteModelNumber(
    value.tokensPerSecond,
    'model tokens per second',
  ),
  averageTtftMillis: nullableFiniteModelNumber(
    value.averageTtftMillis,
    'model average TTFT milliseconds',
  ),
  ttftSampleCount: exactU64(value.ttftSampleCount, 'model TTFT samples'),
  updatedAt: nullableI64(
    value.updatedAt == null ? null : BigInt.from(value.updatedAt!),
    'model performance updated Unix seconds',
  ),
);

AgentEvaluationSummary modelEvaluationSummaryFromBridge(
  scalar.BridgeAgentEvaluationSummary value,
) => AgentEvaluationSummary(
  window: value.window,
  ratedSamples: value.ratedSamples,
  passed: value.passed,
  failed: value.failed,
  notRated: value.notRated,
  averageQuality: nullableFiniteModelNumber(
    value.averageQuality,
    'model average evaluation quality',
  ),
  averageInstructionFollowing: nullableFiniteModelNumber(
    value.averageInstructionFollowing,
    'model average instruction following',
  ),
);

AgentEvaluationRead modelEvaluationFromBridge(
  native.BridgeAgentEvaluationRead value,
) => AgentEvaluationRead(
  agentId: readTextFromBridge(value.agentId),
  parentAgentId: readTextFromBridge(value.parentAgentId),
  accountId: readTextFromBridge(value.accountId),
  modelId: readTextFromBridge(value.modelId),
  effort: nullableReadText(value.effort),
  profileId: readTextFromBridge(value.profileId),
  mode: switch (value.mode) {
    scalar.BridgeDelegationMode.profile => DelegationMode.profile,
    scalar.BridgeDelegationMode.automatic => DelegationMode.automatic,
  },
  preference: switch (value.preference) {
    scalar.BridgeDelegationPreference.economy => DelegationPreference.economy,
    scalar.BridgeDelegationPreference.balanced => DelegationPreference.balanced,
    scalar.BridgeDelegationPreference.fast => DelegationPreference.fast,
  },
  turnId: readTextFromBridge(value.turnId),
  revision: exactU64(value.revision, 'model evaluation revision'),
  taskCategory: modelTaskCategoryFromBridge(value.taskCategory),
  outcome: switch (value.outcome) {
    scalar.BridgeAgentEvaluationOutcome.passed => AgentEvaluationOutcome.passed,
    scalar.BridgeAgentEvaluationOutcome.failed => AgentEvaluationOutcome.failed,
    scalar.BridgeAgentEvaluationOutcome.notRated =>
      AgentEvaluationOutcome.notRated,
  },
  quality: value.quality,
  instructionFollowing: value.instructionFollowing,
  comment: readTextFromBridge(value.comment),
  createdAt: exactI64(
    BigInt.from(value.createdAt),
    'model evaluation created Unix seconds',
  ),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'model evaluation updated Unix seconds',
  ),
);

AgentTaskCategory modelTaskCategoryFromBridge(
  scalar.BridgeAgentTaskCategory value,
) => switch (value) {
  scalar.BridgeAgentTaskCategory.reasoning => AgentTaskCategory.reasoning,
  scalar.BridgeAgentTaskCategory.coding => AgentTaskCategory.coding,
  scalar.BridgeAgentTaskCategory.tooling => AgentTaskCategory.tooling,
  scalar.BridgeAgentTaskCategory.longContext => AgentTaskCategory.longContext,
  scalar.BridgeAgentTaskCategory.multimodal => AgentTaskCategory.multimodal,
  scalar.BridgeAgentTaskCategory.general => AgentTaskCategory.general,
};

ModelSelectionSourceReadPage modelSelectionSourcesPageFromBridge(
  native.BridgeModelSelectionSourceReadPage value,
) => ModelSelectionSourceReadPage(
  listId: exactU64(value.listId, 'model selection sources list'),
  offset: exactU64(value.offset, 'model selection sources offset'),
  total: exactU64(value.total, 'model selection sources total'),
  items: value.items
      .map(modelSelectionSourceFromBridge)
      .toList(growable: false),
  nextOffset: nullableU64(
    value.nextOffset,
    'model selection sources next offset',
  ),
);

AgentEvaluationReadPage modelEvaluationsPageFromBridge(
  native.BridgeAgentEvaluationReadPage value,
) => AgentEvaluationReadPage(
  listId: exactU64(value.listId, 'model evaluations list'),
  offset: exactU64(value.offset, 'model evaluations offset'),
  total: exactU64(value.total, 'model evaluations total'),
  items: value.items.map(modelEvaluationFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'model evaluations next offset'),
);
