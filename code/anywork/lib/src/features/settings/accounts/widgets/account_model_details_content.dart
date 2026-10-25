import 'package:anywork_client/configuration.dart' show DelegationSettings;
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/labels/delegation_labels.dart';

/// All guide/evaluation text belongs to this dialog's exact immutable read.
/// This view neither ranks models nor fills unknown measurements with zero.
class AccountModelDetailsContent extends StatelessWidget {
  const AccountModelDetailsContent({
    required this.detail,
    required this.billingOverrideKnown,
    required this.billingOverride,
    super.key,
  });
  final DelegationModelDetail detail;
  final bool billingOverrideKnown;
  final BillingKind? billingOverride;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final model = detail.descriptor;
    final capabilities = model.capabilities;
    final guide = detail.guide;
    final performance = detail.performance;
    final pricing = model.pricing;
    final summary = detail.evaluations;
    final capabilityLabels = [
      if (capabilities.streaming) 'Streaming',
      if (capabilities.reasoning) 'Reasoning',
      if (capabilities.webSearch) 'Web search',
      if (capabilities.functionCalling) 'Tools',
      if (capabilities.parallelToolCalls) 'Parallel tools',
      if (capabilities.temperature) 'Temperature',
      if (capabilities.customTools) 'Custom tools',
      if (capabilities.freeformTools) 'Freeform tools',
      if (capabilities.instructionSnapshotOverrides) 'Instruction snapshot',
      ?capabilities.nativeContextFamily,
    ];
    String unknown(Object? value) => value?.toString() ?? l.modelDetailUnknown;
    String score(num? value) =>
        value == null ? l.modelDetailUnknown : '$value/5';
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
    Widget field(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text('$label: $value'),
    );
    String date(int? seconds) => seconds == null
        ? l.modelDetailUnknown
        : DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
              .format(
                DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal(),
              );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!model.enabled) Text(l.settingsModelDisabled),
        Text(
          detail.available
              ? l.modelDetailAvailable
              : detail.unavailableReason ??
                    l.statusModelRouteUnavailableFallback,
        ),
        Text(l.modelDetailAvailabilityHint),
        section(l.modelDetailSummary),
        Text(
          guide?.summary.isNotEmpty == true
              ? guide!.summary
              : model.description?.isNotEmpty == true
              ? model.description!
              : l.modelDetailUnknown,
        ),
        if (guide != null && guide.taskSuitability.isNotEmpty)
          Text(
            guide.taskSuitability.map(context.taskCategoryLabel).join(' · '),
          ),
        if (guide != null && guide.limitations.isNotEmpty) ...[
          section(l.modelDetailLimitations),
          for (final limitation in guide.limitations) Text('• $limitation'),
        ],
        section(l.modelDetailCapabilities),
        Text(
          capabilityLabels.isEmpty
              ? l.modelDetailUnknown
              : capabilityLabels.join(' · '),
        ),
        Text(
          capabilities.input.isEmpty
              ? l.modelDetailUnknown
              : capabilities.input
                    .map((input) => context.modalityLabel(input.modality))
                    .join(' · '),
        ),
        Text(
          l.settingsModelOutputCapabilities(
            capabilities.output.isEmpty
                ? l.modelDetailUnknown
                : capabilities.output.map(context.modalityLabel).join(' · '),
          ),
        ),
        field(
          l.settingsContextBudget,
          unknown(
            model.context.contextWindow ??
                model.contextWindow ??
                model.maxContextWindow,
          ),
        ),
        field(l.statisticsOutputTokens, unknown(model.maxOutputTokens)),
        field(
          l.modelDetailEfforts,
          model.reasoning?.candidates.isNotEmpty == true
              ? model.reasoning!.candidates.join(' · ')
              : l.modelDetailNoEffort,
        ),
        section(l.settingsBillingKind),
        field(
          l.settingsBillingEffective,
          context.billingKindLabel(detail.billingKind),
        ),
        field(
          l.settingsBillingOverride,
          billingOverrideKnown
              ? context.billingKindLabel(billingOverride)
              : l.modelDetailUnknown,
        ),
        Text(l.settingsBillingHint),
        section(l.modelDetailPricing),
        if (pricing == null || pricing.tiers.isEmpty)
          Text(l.settingsModelPriceUnknown)
        else ...[
          Text(
            pricing.currency.isEmpty ? l.modelDetailUnknown : pricing.currency,
          ),
          for (final tier in pricing.tiers) ...[
            Text(tier.label, style: Theme.of(context).textTheme.labelLarge),
            field(l.modelDetailPriceInput, '${tier.inputPerMtok}'),
            field(l.modelDetailPriceOutput, '${tier.outputPerMtok}'),
            field(l.modelDetailPriceCacheRead, unknown(tier.cacheReadPerMtok)),
            field(
              l.modelDetailPriceCacheWrite,
              unknown(tier.cacheWritePerMtok),
            ),
          ],
          Text(pricing.source.isEmpty ? l.modelDetailUnknown : pricing.source),
          field(l.modelDetailVerifiedAt, date(pricing.verifiedAt)),
        ],
        section(l.modelDetailSources),
        if (guide == null || guide.sources.isEmpty)
          Text(l.modelDetailUnknown)
        else
          for (final source in guide.sources) ...[
            Text(switch (source.kind) {
              ModelSelectionSourceKind.official => l.modelDetailOfficial,
              ModelSelectionSourceKind.benchmark => l.modelDetailBenchmark,
              ModelSelectionSourceKind.community => l.modelDetailCommunity,
            }),
            Text(source.url),
            field(l.modelDetailVerifiedAt, date(source.verifiedAt)),
            if (source.measurement case final measurement?)
              field(
                l.modelDetailMeasurement,
                '${measurement.model} · ${measurement.effort ?? l.modelDetailUnknown} · ${measurement.metric} '
                '${measurement.metricVersion ?? l.modelDetailUnknown} · ${unknown(measurement.score)}',
              ),
            const SizedBox(height: 8),
          ],
        section(l.modelDetailPerformance),
        field(
          l.modelDetailThroughput,
          performance.tokensPerSecond?.toStringAsFixed(2) ??
              l.modelDetailUnknown,
        ),
        field(
          l.modelDetailTtft,
          performance.averageTtftMillis?.toStringAsFixed(1) ??
              l.modelDetailUnknown,
        ),
        field(l.modelDetailSamples, '${performance.sampleCount}'),
        field(l.modelDetailTtftSamples, '${performance.ttftSampleCount}'),
        field(l.modelDetailUpdatedAt, date(performance.updatedAt)),
        Text(l.modelDetailPerformanceHint),
        section(l.modelDetailEvaluations),
        Text(l.modelDetailEvaluationsHint),
        // Summary counters and averages are native facts, not UI calculations.
        Text(
          '${l.modelDetailSamples}: ${summary.ratedSamples} / ${summary.window}',
        ),
        Text(
          '${l.modelDetailEvaluationPassed}: ${summary.passed} · '
          '${l.modelDetailEvaluationFailed}: ${summary.failed} · ${l.modelDetailEvaluationNotRated}: ${summary.notRated}',
        ),
        field(l.modelDetailQuality, score(summary.averageQuality)),
        field(
          l.modelDetailInstructionFollowing,
          score(summary.averageInstructionFollowing),
        ),
        Column(
          key: StudioDriverKeys.modelDetailEvaluations,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (detail.recentEvaluations.isEmpty)
              Text(l.modelDetailEvaluationsEmpty),
            for (final evaluation in detail.recentEvaluations)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${context.taskCategoryLabel(evaluation.taskCategory)} · ${switch (evaluation.outcome) {
                        AgentEvaluationOutcome.passed => l.modelDetailEvaluationPassed,
                        AgentEvaluationOutcome.failed => l.modelDetailEvaluationFailed,
                        AgentEvaluationOutcome.notRated => l.modelDetailEvaluationNotRated,
                      }} · ${date(evaluation.updatedAt)}',
                    ),
                    Text(
                      '${evaluation.profileId} · ${evaluation.model.model.accountId} / '
                      '${evaluation.model.model.modelId} · ${evaluation.model.effort ?? l.modelDetailUnknown}',
                    ),
                    Text(
                      '${evaluation.agentId} · ${evaluation.turnId} · r${evaluation.revision}',
                    ),
                    Text(
                      context.delegationSummary(
                        DelegationSettings(
                          mode: evaluation.mode,
                          preference: evaluation.preference,
                        ),
                      ),
                    ),
                    Text(
                      l.delegationFrozen,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    field(l.modelDetailQuality, score(evaluation.quality)),
                    field(
                      l.modelDetailInstructionFollowing,
                      score(evaluation.instructionFollowing),
                    ),
                    Text(evaluation.comment),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
