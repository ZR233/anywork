part of 'studio_api.dart';

DelegationMode _delegationModeFromFrb(frb.BridgeDelegationMode value) =>
    switch (value) {
      frb.BridgeDelegationMode.profile => DelegationMode.profile,
      frb.BridgeDelegationMode.automatic => DelegationMode.automatic,
    };

frb.BridgeDelegationMode _delegationModeToFrb(DelegationMode value) =>
    switch (value) {
      DelegationMode.profile => frb.BridgeDelegationMode.profile,
      DelegationMode.automatic => frb.BridgeDelegationMode.automatic,
    };

DelegationPreference _delegationPreferenceFromFrb(
  frb.BridgeDelegationPreference value,
) => switch (value) {
  frb.BridgeDelegationPreference.economy => DelegationPreference.economy,
  frb.BridgeDelegationPreference.balanced => DelegationPreference.balanced,
  frb.BridgeDelegationPreference.fast => DelegationPreference.fast,
};

frb.BridgeDelegationPreference _delegationPreferenceToFrb(
  DelegationPreference value,
) => switch (value) {
  DelegationPreference.economy => frb.BridgeDelegationPreference.economy,
  DelegationPreference.balanced => frb.BridgeDelegationPreference.balanced,
  DelegationPreference.fast => frb.BridgeDelegationPreference.fast,
};

BillingKind _billingKindFromFrb(frb.BridgeBillingKind value) => switch (value) {
  frb.BridgeBillingKind.metered => BillingKind.metered,
  frb.BridgeBillingKind.subscription => BillingKind.subscription,
  frb.BridgeBillingKind.noCharge => BillingKind.noCharge,
  frb.BridgeBillingKind.unknown => BillingKind.unknown,
};

frb.BridgeBillingKind _billingKindToFrb(BillingKind value) => switch (value) {
  BillingKind.metered => frb.BridgeBillingKind.metered,
  BillingKind.subscription => frb.BridgeBillingKind.subscription,
  BillingKind.noCharge => frb.BridgeBillingKind.noCharge,
  BillingKind.unknown => frb.BridgeBillingKind.unknown,
};

NewThreadModelRoute _savedRouteFromFrb(frb.BridgeNewThreadModelRoute value) =>
    NewThreadModelRoute(
      accountId: value.accountId,
      modelId: value.modelId,
      effort: value.effort,
    );

AgentTaskCategory _taskCategoryFromFrb(frb.BridgeAgentTaskCategory value) =>
    switch (value) {
      frb.BridgeAgentTaskCategory.reasoning => AgentTaskCategory.reasoning,
      frb.BridgeAgentTaskCategory.coding => AgentTaskCategory.coding,
      frb.BridgeAgentTaskCategory.tooling => AgentTaskCategory.tooling,
      frb.BridgeAgentTaskCategory.longContext => AgentTaskCategory.longContext,
      frb.BridgeAgentTaskCategory.multimodal => AgentTaskCategory.multimodal,
      frb.BridgeAgentTaskCategory.general => AgentTaskCategory.general,
    };

frb.BridgeAgentTaskCategory _taskCategoryToFrb(AgentTaskCategory value) =>
    switch (value) {
      AgentTaskCategory.reasoning => frb.BridgeAgentTaskCategory.reasoning,
      AgentTaskCategory.coding => frb.BridgeAgentTaskCategory.coding,
      AgentTaskCategory.tooling => frb.BridgeAgentTaskCategory.tooling,
      AgentTaskCategory.longContext => frb.BridgeAgentTaskCategory.longContext,
      AgentTaskCategory.multimodal => frb.BridgeAgentTaskCategory.multimodal,
      AgentTaskCategory.general => frb.BridgeAgentTaskCategory.general,
    };

frb.BridgeDelegationModelCapability _delegationCapabilityToFrb(
  DelegationModelCapability value,
) => switch (value) {
  DelegationModelCapability.toolCalling =>
    frb.BridgeDelegationModelCapability.toolCalling,
  DelegationModelCapability.parallelToolCalls =>
    frb.BridgeDelegationModelCapability.parallelToolCalls,
  DelegationModelCapability.reasoning =>
    frb.BridgeDelegationModelCapability.reasoning,
  DelegationModelCapability.imageInput =>
    frb.BridgeDelegationModelCapability.imageInput,
  DelegationModelCapability.audioInput =>
    frb.BridgeDelegationModelCapability.audioInput,
  DelegationModelCapability.videoInput =>
    frb.BridgeDelegationModelCapability.videoInput,
  DelegationModelCapability.fileInput =>
    frb.BridgeDelegationModelCapability.fileInput,
  DelegationModelCapability.customTools =>
    frb.BridgeDelegationModelCapability.customTools,
  DelegationModelCapability.freeformTools =>
    frb.BridgeDelegationModelCapability.freeformTools,
  DelegationModelCapability.webSearch =>
    frb.BridgeDelegationModelCapability.webSearch,
  DelegationModelCapability.streaming =>
    frb.BridgeDelegationModelCapability.streaming,
};

frb.BridgeListDelegationModelsRequest _delegationListRequestToFrb(
  ListDelegationModelsRequest value,
) => frb.BridgeListDelegationModelsRequest(
  capabilities: value.capabilities.map(_delegationCapabilityToFrb).toList(),
  taskCategory: value.taskCategory == null
      ? null
      : _taskCategoryToFrb(value.taskCategory!),
  accountId: value.accountId,
  billingKind: value.billingKind == null
      ? null
      : _billingKindToFrb(value.billingKind!),
  minContextWindow: value.minContextWindow == null
      ? null
      : BigInt.from(value.minContextWindow!),
  limit: value.limit,
  cursor: value.cursor,
);

LocalModelPerformanceSummary _delegationPerformanceFromFrb(
  frb.BridgeLocalModelPerformanceSummary value,
) => LocalModelPerformanceSummary(
  sampleCount: value.sampleCount.toInt(),
  tokensPerSecond: value.tokensPerSecond,
  averageTtftMillis: value.averageTtftMillis,
  ttftSampleCount: value.ttftSampleCount.toInt(),
  updatedAt: value.updatedAt?.toInt(),
);

AgentEvaluationSummary _evaluationSummaryFromFrb(
  frb.BridgeAgentEvaluationSummary value,
) => AgentEvaluationSummary(
  window: value.window,
  ratedSamples: value.ratedSamples,
  passed: value.passed,
  failed: value.failed,
  notRated: value.notRated,
  averageQuality: value.averageQuality,
  averageInstructionFollowing: value.averageInstructionFollowing,
);

ModelPricingView _modelPricingFromFrb(frb.BridgeModelPricing value) =>
    ModelPricingView(
      currency: value.currency,
      source: value.source,
      verifiedAt: value.verifiedAt.toInt(),
      tiers: List.unmodifiable(
        value.tiers.map(
          (tier) => ModelPriceTierView(
            label: tier.label,
            input: tier.inputPerMtok,
            output: tier.outputPerMtok,
            cacheRead: tier.cacheReadPerMtok,
            cacheWrite: tier.cacheWritePerMtok,
          ),
        ),
      ),
    );

DelegationModelList _delegationListFromFrb(
  frb.BridgeDelegationModelList value,
) => DelegationModelList(
  catalogRevision: value.catalogRevision.toInt(),
  nextCursor: value.nextCursor,
  models: List.unmodifiable(
    value.models.map(
      (model) => DelegationModelListItem(
        key: DelegationModelKey(
          accountId: model.accountId,
          modelId: model.modelId,
        ),
        accountName: model.accountName,
        displayName: model.displayName,
        summary: model.summary,
        taskSuitability: List.unmodifiable(
          model.taskSuitability.map(_taskCategoryFromFrb),
        ),
        contextWindow: model.contextWindow?.toInt(),
        capabilities: DelegationModelCapabilities(
          input: List.unmodifiable(
            model.capabilities.input.map(_modelInputCapabilityFromFrb),
          ),
          output: List.unmodifiable(
            model.capabilities.output.map(_modelModalityFromFrb),
          ),
          streaming: model.capabilities.streaming,
          temperature: model.capabilities.temperature,
          reasoning: model.capabilities.reasoning,
          webSearch: model.capabilities.webSearch,
          functionCalling: model.capabilities.functionCalling,
          parallelToolCalls: model.capabilities.parallelToolCalls,
          customTools: model.capabilities.customTools,
          freeformTools: model.capabilities.freeformTools,
          instructionSnapshotOverrides:
              model.capabilities.instructionSnapshotOverrides,
          nativeContextFamily: model.capabilities.nativeContextFamily,
        ),
        reasoningEfforts: List.unmodifiable(model.reasoningEfforts),
        pricing: model.pricing == null
            ? null
            : _modelPricingFromFrb(model.pricing!),
        billingKind: _billingKindFromFrb(model.billingKind),
        performance: _delegationPerformanceFromFrb(model.performance),
        evaluations: _evaluationSummaryFromFrb(model.evaluations),
      ),
    ),
  ),
);

/// Public adapter boundary also used by the typed Client contract suite.
DelegationModelDetail delegationModelDetailFromFrb(
  frb.BridgeDelegationModelDetail value,
) {
  final guide = value.guide;
  return DelegationModelDetail(
    key: DelegationModelKey(
      accountId: value.accountId,
      modelId: value.descriptor.modelId,
    ),
    accountName: value.accountName,
    descriptor: accountModelFromCatalog(value.descriptor),
    available: value.available,
    unavailableReason: value.unavailableReason,
    billingKind: _billingKindFromFrb(value.billingKind),
    guide: guide == null
        ? null
        : ModelSelectionGuide(
            summary: guide.summary,
            taskSuitability: List.unmodifiable(
              guide.taskSuitability.map(_taskCategoryFromFrb),
            ),
            limitations: List.unmodifiable(guide.limitations),
            sources: List.unmodifiable(
              guide.sources.map(
                (source) => ModelSelectionSource(
                  kind: switch (source.kind) {
                    frb.BridgeModelSelectionSourceKind.official =>
                      ModelSelectionSourceKind.official,
                    frb.BridgeModelSelectionSourceKind.benchmark =>
                      ModelSelectionSourceKind.benchmark,
                    frb.BridgeModelSelectionSourceKind.community =>
                      ModelSelectionSourceKind.community,
                  },
                  url: source.url,
                  verifiedAt: source.verifiedAt.toInt(),
                  measurement: source.measurement == null
                      ? null
                      : ModelSelectionMeasurement(
                          model: source.measurement!.model,
                          effort: source.measurement!.effort,
                          metric: source.measurement!.metric,
                          metricVersion: source.measurement!.metricVersion,
                          score: source.measurement!.score,
                        ),
                ),
              ),
            ),
          ),
    performance: _delegationPerformanceFromFrb(value.performance),
    evaluations: _evaluationSummaryFromFrb(value.evaluations),
    recentEvaluations: List.unmodifiable(
      value.recentEvaluations.map(
        (evaluation) => AgentEvaluation(
          agentId: evaluation.agentId,
          parentAgentId: evaluation.parentAgentId,
          model: _savedRouteFromFrb(evaluation.model),
          profileId: evaluation.profileId,
          mode: _delegationModeFromFrb(evaluation.mode),
          preference: _delegationPreferenceFromFrb(evaluation.preference),
          turnId: evaluation.turnId,
          revision: evaluation.revision.toInt(),
          taskCategory: _taskCategoryFromFrb(evaluation.taskCategory),
          outcome: switch (evaluation.outcome) {
            frb.BridgeAgentEvaluationOutcome.passed =>
              AgentEvaluationOutcome.passed,
            frb.BridgeAgentEvaluationOutcome.failed =>
              AgentEvaluationOutcome.failed,
            frb.BridgeAgentEvaluationOutcome.notRated =>
              AgentEvaluationOutcome.notRated,
          },
          quality: evaluation.quality,
          instructionFollowing: evaluation.instructionFollowing,
          comment: evaluation.comment,
          createdAt: evaluation.createdAt.toInt(),
          updatedAt: evaluation.updatedAt.toInt(),
        ),
      ),
    ),
  );
}
