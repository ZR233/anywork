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
