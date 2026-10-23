import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/model_detail_queries.dart';
import '../../presentation/providers/settings_store.dart';
import '../../shared/delegation_labels.dart';
import '../../shared/studio_driver_keys.dart';

Future<void> showModelDetails(BuildContext context, DelegationModelKey model) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ModelDetails(model: model),
    );

class _ModelDetails extends ConsumerStatefulWidget {
  const _ModelDetails({required this.model});
  final DelegationModelKey model;
  @override
  ConsumerState<_ModelDetails> createState() => _ModelDetailsState();
}

class _ModelDetailsState extends ConsumerState<_ModelDetails> {
  late final AnyworkClient _client;
  @override
  void initState() {
    super.initState();
    _client = ref.read(anyworkClientProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  void _refresh() => unawaited(
    _client.modelDetailQueries
        .refresh(widget.model)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
  );
  @override
  void dispose() {
    _client.modelDetailQueries.forget(widget.model);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(modelDetailQueriesProvider)[widget.model];
    final detail = query?.value;
    final account = ref
        .watch(settingsStoreProvider)
        .canonical
        ?.accounts
        .where((a) => a.id == widget.model.accountId)
        .firstOrNull;
    final viewport = MediaQuery.sizeOf(context);
    return AlertDialog(
      key: StudioDriverKeys.modelDetailDialog,
      title: Text(
        detail?.descriptor.displayName.isNotEmpty == true
            ? detail!.descriptor.displayName
            : widget.model.modelId,
      ),
      content: SizedBox(
        width: (viewport.width - 80).clamp(0, 720).toDouble(),
        height: (viewport.height - 220).clamp(120, 680).toDouble(),
        child: SelectionArea(
          child: ListView(
            children: [
              Text('${widget.model.accountId} / ${widget.model.modelId}'),
              if (detail != null) Text(detail.accountName),
              const SizedBox(height: 12),
              if (query == null || query.loading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(context.l10n.modelDetailLoading),
              ] else if (query.error case final error?) ...[
                Text(
                  error.code == StudioFailureCode.staleRevision
                      ? context.l10n.modelDetailStale
                      : error.message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                Text(error.toString()),
              ] else if (detail != null)
                ..._content(context, detail, account),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: StudioDriverKeys.modelDetailReload,
          onPressed: query?.loading == true ? null : _refresh,
          child: Text(context.l10n.modelDetailRetry),
        ),
        TextButton(
          key: StudioDriverKeys.modelDetailClose,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.modelDetailClose),
        ),
      ],
    );
  }

  List<Widget> _content(
    BuildContext context,
    DelegationModelDetail detail,
    AccountSettingsView? account,
  ) {
    final l = context.l10n;
    final model = detail.descriptor;
    final guide = detail.guide;
    final performance = detail.performance;
    String unknown(Object? value) => value?.toString() ?? l.modelDetailUnknown;
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
    return [
      Text(
        detail.available
            ? l.modelDetailAvailable
            : detail.unavailableReason ?? l.statusModelRouteUnavailableFallback,
      ),
      Text(l.modelDetailAvailabilityHint),
      section(l.modelDetailSummary),
      Text(
        guide?.summary ??
            (model.description.isEmpty
                ? l.modelDetailUnknown
                : model.description),
      ),
      if (guide != null && guide.taskSuitability.isNotEmpty)
        Text(guide.taskSuitability.map(context.taskCategoryLabel).join(' · ')),
      if (guide != null && guide.limitations.isNotEmpty) ...[
        section(l.modelDetailLimitations),
        for (final limitation in guide.limitations) Text('• $limitation'),
      ],
      section(l.modelDetailCapabilities),
      Text(
        model.capabilities.isEmpty
            ? l.modelDetailUnknown
            : model.capabilities.join(' · '),
      ),
      Text(
        model.inputCapabilities.isEmpty
            ? l.modelDetailUnknown
            : model.inputCapabilities
                  .map((input) => context.modalityLabel(input.modality))
                  .join(' · '),
      ),
      Text(
        l.settingsModelOutputCapabilities(
          model.outputModalities.isEmpty
              ? l.modelDetailUnknown
              : model.outputModalities.map(context.modalityLabel).join(' · '),
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
        model.reasoningEfforts.isEmpty
            ? l.modelDetailNoEffort
            : model.reasoningEfforts.join(' · '),
      ),
      section(l.settingsBillingKind),
      field(
        l.settingsBillingEffective,
        context.billingKindLabel(detail.billingKind),
      ),
      field(
        l.settingsBillingOverride,
        account == null
            ? l.modelDetailUnknown
            : context.billingKindLabel(account.billingKindOverride),
      ),
      Text(l.settingsBillingHint),
      section(l.modelDetailPricing),
      if (model.priceTiers.isEmpty)
        Text(l.settingsModelPriceUnknown)
      else ...[
        Text(model.currency.isEmpty ? l.modelDetailUnknown : model.currency),
        for (final tier in model.priceTiers) ...[
          Text(tier.label, style: Theme.of(context).textTheme.labelLarge),
          field(l.modelDetailPriceInput, '${tier.input}'),
          field(l.modelDetailPriceOutput, '${tier.output}'),
          field(l.modelDetailPriceCacheRead, unknown(tier.cacheRead)),
          field(l.modelDetailPriceCacheWrite, unknown(tier.cacheWrite)),
        ],
        Text(
          model.priceSource.isEmpty ? l.modelDetailUnknown : model.priceSource,
        ),
        field(l.modelDetailVerifiedAt, date(model.priceVerifiedAt)),
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
        performance.tokensPerSecond?.toStringAsFixed(2) ?? l.modelDetailUnknown,
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
                    '${evaluation.profileId} · ${evaluation.model.accountId} / ${evaluation.model.modelId} · ${evaluation.model.effort ?? l.modelDetailUnknown}',
                  ),
                  Text(
                    '${evaluation.agentId} · ${evaluation.turnId} · r${evaluation.revision}',
                  ),
                  Text(
                    context.delegationSummary(
                      DelegationSettingsView(
                        mode: evaluation.mode,
                        preference: evaluation.preference,
                      ),
                    ),
                  ),
                  if (evaluation.quality != null)
                    Text(
                      '${l.modelDetailQuality}: ${evaluation.quality}/5 · ${l.modelDetailInstructionFollowing}: ${evaluation.instructionFollowing}/5',
                    ),
                  Text(evaluation.comment),
                ],
              ),
            ),
        ],
      ),
    ];
  }
}
