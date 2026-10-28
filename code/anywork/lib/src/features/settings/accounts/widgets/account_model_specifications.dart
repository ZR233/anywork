import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import 'account_sections.dart';

class AccountModelSpecifications extends StatelessWidget {
  const AccountModelSpecifications({required this.value, super.key});
  final AccountModelPresentation value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final performance = value.performance;
    final facts = value.specificationFacts;
    final compact = value.compact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.outlined(
          margin: const EdgeInsets.only(bottom: 24),
          color: accountGroupSurface(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SpecificationGroup(
                icon: Icons.layers_outlined,
                title: l10n.accountsModelModalityCapabilities,
                facts: facts.modalityCapabilities,
              ),
              const Divider(height: 1),
              _SpecificationGroup(
                icon: Icons.speed_outlined,
                title: l10n.accountsModelContextThreshold,
                incomplete: facts.context.isEmpty,
                facts: [
                  ...facts.context,
                  AccountDisplayFact(
                    label: l10n.settingsModelAutoCompactEffectiveLabel,
                    value: compact?.effective ?? l10n.modelDetailUnknown,
                  ),
                  if (compact != null) ...[
                    AccountDisplayFact(
                      label: l10n.settingsModelAutoCompactUsingDefault,
                      value: compact.automatic ?? l10n.modelDetailUnknown,
                    ),
                    AccountDisplayFact(
                      label: l10n.settingsModelAutoCompactOverrideLabel,
                      value: compact.overridden
                          ? l10n.settingsModelAutoCompactCustom
                          : l10n.settingsModelAutoCompactUsingDefault,
                    ),
                  ],
                ],
              ),
              const Divider(height: 1),
              _SpecificationGroup(
                icon: Icons.hub_outlined,
                title: l10n.accountsModelProtocolOrigin,
                incomplete: facts.connection.isEmpty,
                facts: [
                  ...facts.connection,
                  AccountDisplayFact(
                    label: l10n.accountsSource,
                    value: switch (value.origin) {
                      AccountModelOrigin.online =>
                        l10n.settingsAccountOnlineModelsTitle,
                      AccountModelOrigin.bundled =>
                        l10n.settingsModelCatalogDefault,
                      AccountModelOrigin.manual =>
                        l10n.settingsAccountCustomModelsTitle,
                    },
                  ),
                  AccountDisplayFact(
                    label: l10n.accountsConnection,
                    value: value.connection == null
                        ? l10n.modelDetailUnknown
                        : accountConnectionLabel(l10n, value.connection!),
                  ),
                  if (value.allowedConnections.isNotEmpty)
                    AccountDisplayFact(
                      label: l10n.accountsSupportedConnections,
                      value: value.allowedConnections
                          .map(
                            (connection) =>
                                accountConnectionLabel(l10n, connection),
                          )
                          .join(' / '),
                    ),
                ],
              ),
            ],
          ),
        ),
        AccountSection(
          title: l10n.accountsPerformance,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (performance == null || performance.sampleCount == 0)
                Text(l10n.accountsPerformanceMissing)
              else ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.maxWidth / 220).floor().clamp(
                      1,
                      3,
                    );
                    final readings = [
                      (
                        l10n.modelDetailTtft,
                        performance.averageTtftMillis?.toStringAsFixed(0) ??
                            '—',
                      ),
                      (
                        l10n.modelDetailThroughput,
                        performance.tokensPerSecond?.toStringAsFixed(1) ?? '—',
                      ),
                      (l10n.modelDetailSamples, '${performance.sampleCount}'),
                    ];
                    return Wrap(
                      runSpacing: 20,
                      children: [
                        for (var i = 0; i < readings.length; i++)
                          Container(
                            width: (constraints.maxWidth / columns)
                                .floorToDouble(),
                            padding: EdgeInsetsDirectional.only(
                              start: i % columns == 0 ? 0 : 20,
                              end: 16,
                            ),
                            decoration: BoxDecoration(
                              border: i % columns == 0
                                  ? null
                                  : BorderDirectional(
                                      start: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                      ),
                                    ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  readings[i].$1,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                AccountSelectableText(
                                  readings[i].$2,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const Divider(height: 32),
                AccountFacts(
                  facts: [
                    AccountDisplayFact(
                      label: l10n.modelDetailTtftSamples,
                      value: '${performance.ttftSampleCount}',
                    ),
                    if (performance.updatedLabel case final updated?)
                      AccountDisplayFact(
                        label: l10n.modelDetailUpdatedAt,
                        value: updated,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Text(
                l10n.modelDetailPerformanceHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (value.guidance.isNotEmpty)
          AccountSection(
            title: l10n.modelDetailSummary,
            child: AccountFacts(facts: value.guidance),
          ),
      ],
    );
  }
}

/// One typed specification group; formatted facts are never reclassified here.
class _SpecificationGroup extends StatelessWidget {
  const _SpecificationGroup({
    required this.icon,
    required this.title,
    required this.facts,
    this.incomplete = false,
  });
  final IconData icon;
  final String title;
  final List<AccountDisplayFact> facts;
  final bool incomplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (facts.isEmpty || incomplete)
                  Text(
                    AppLocalizations.of(context).modelDetailUnknown,
                    style: theme.textTheme.bodyMedium,
                  ),
                if (facts.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns =
                          constraints.maxWidth >=
                              640 * MediaQuery.textScalerOf(context).scale(1)
                          ? 2
                          : 1;
                      return Wrap(
                        spacing: 20,
                        runSpacing: 8,
                        children: [
                          for (final fact in facts)
                            SizedBox(
                              width:
                                  ((constraints.maxWidth - (columns - 1) * 20) /
                                          columns)
                                      .floorToDouble(),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    fact.label,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  AccountSelectableText(
                                    fact.value,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tier in the shared pricing group, also independently previewable.
class AccountModelPriceRow extends StatelessWidget {
  const AccountModelPriceRow({
    required this.value,
    required this.currency,
    super.key,
  });
  final AccountModelPriceTier value;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              AccountSelectableText(
                value.label,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                l10n.settingsPriceTierUnit(currency ?? l10n.modelDetailUnknown),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final prices = [
                (l10n.modelDetailPriceInput, value.input),
                (l10n.modelDetailPriceCacheRead, value.cacheRead),
                (l10n.modelDetailPriceOutput, value.output),
                (l10n.modelDetailPriceCacheWrite, value.cacheWrite),
              ];
              final columns =
                  (constraints.maxWidth /
                          (160 * MediaQuery.textScalerOf(context).scale(1)))
                      .floor()
                      .clamp(1, prices.length);
              return Wrap(
                runSpacing: 20,
                children: [
                  for (var i = 0; i < prices.length; i++)
                    Container(
                      width: (constraints.maxWidth / columns).floorToDouble(),
                      padding: EdgeInsetsDirectional.only(
                        start: i % columns == 0 ? 0 : 16,
                        end: 16,
                      ),
                      decoration: BoxDecoration(
                        border: i % columns == 0
                            ? null
                            : BorderDirectional(
                                start: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                              ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prices[i].$1,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          AccountSelectableText(
                            prices[i].$2 == null
                                ? '—'
                                : '${prices[i].$2} ${currency ?? l10n.modelDetailUnknown}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class AccountModelPricing extends StatelessWidget {
  const AccountModelPricing({required this.value, super.key});
  final AccountModelPresentation value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.modelDetailPricing,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        if (value.priceTiers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.accountsPriceMissing),
          )
        else
          Card.outlined(
            color: accountGroupSurface(context),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < value.priceTiers.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  AccountModelPriceRow(
                    value: value.priceTiers[i],
                    currency: value.currency,
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),
        AccountFacts(
          facts: [
            if (value.priceSource case final source?)
              AccountDisplayFact(label: l10n.modelDetailSources, value: source),
            if (value.priceVerifiedLabel case final verified?)
              AccountDisplayFact(
                label: l10n.modelDetailVerifiedAt,
                value: verified,
              ),
          ],
        ),
      ],
    );
  }
}
