import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_chrome.dart';
import 'settings_common.dart';
import 'settings_provider_drafts.dart';

class ProviderUsagePanel extends StatelessWidget {
  const ProviderUsagePanel({
    super.key,
    required this.provider,
    required this.usage,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final ProviderSettingsView provider;
  final ProviderUsageView? usage;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final usage = this.usage;
    return StudioPanel(
      backgroundColor: context.colors.surfaceContainer,
      borderColor: context.colors.outlineVariant,
      radius: StudioRadii.sm,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 17,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  context.l10n.settingsUsageTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                usageUpdatedLabel(context, usage?.updatedAt),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: context.l10n.settingsRefreshUsage,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                onPressed: loading ? null : onRefresh,
              ),
            ],
          ),
          if (error != null && error!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ProviderUsageMessage(
              icon: Icons.error_outline,
              message: error!,
              tone: UsageTone.failed,
            ),
          ],
          const SizedBox(height: 8),
          if (usage == null)
            ProviderUsageMessage(
              icon: loading
                  ? Icons.hourglass_empty
                  : Icons.account_balance_wallet_outlined,
              message: loading
                  ? context.l10n.settingsUsageChecking
                  : context.l10n.settingsUsageNotLoaded,
              tone: loading ? UsageTone.neutral : UsageTone.muted,
            )
          else
            switch (usage.state) {
              ReadyProviderUsageView(
                data: DeepSeekBalanceProviderUsageView(:final balance),
              ) =>
                DeepSeekBalanceReadout(usage: balance),
              ReadyProviderUsageView(
                data: ZhipuCodingPlanProviderUsageView(:final codingPlan),
              ) =>
                _ZhipuCodingPlanUsage(usage: codingPlan),
              UnsupportedProviderUsageView() ||
              MissingCredentialProviderUsageView() ||
              FailedProviderUsageView() => ProviderUsageMessage(
                icon: usage.state is UnsupportedProviderUsageView
                    ? Icons.info_outline
                    : Icons.error_outline,
                message: providerUsageMessage(context, provider, usage),
                tone: switch (usage.state) {
                  FailedProviderUsageView() => UsageTone.failed,
                  MissingCredentialProviderUsageView() => UsageTone.warning,
                  UnsupportedProviderUsageView() => UsageTone.muted,
                  ReadyProviderUsageView() => UsageTone.neutral,
                },
              ),
            },
        ],
      ),
    );
  }
}

/// Displays the canonical DeepSeek balance fields without recalculating them.
///
/// DeepSeek returns one balance record per currency. The same readout is used
/// in the provider detail view and in the compact provider list card so both
/// surfaces keep the provider's terminology and ordering aligned.
class DeepSeekBalanceReadout extends StatelessWidget {
  const DeepSeekBalanceReadout({
    super.key,
    required this.usage,
    this.compact = false,
  });

  final DeepSeekBalanceUsageView usage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final balances = _orderedDeepSeekBalances(usage.balances);
    if (balances.isEmpty) {
      return ProviderUsageMessage(
        icon: Icons.info_outline,
        message: context.l10n.settingsUsageUnavailable,
        tone: UsageTone.muted,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudioPill(
          icon: usage.isAvailable
              ? Icons.check_circle_outline
              : Icons.warning_amber_outlined,
          label: usage.isAvailable
              ? context.l10n.settingsUsageBalanceSufficient
              : context.l10n.settingsUsageBalanceInsufficient,
          tone: usage.isAvailable ? StudioTone.success : StudioTone.warning,
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < balances.length; index++) ...[
          _DeepSeekCurrencyBalanceCard(
            balance: balances[index],
            compact: compact,
          ),
          if (index < balances.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

List<DeepSeekBalanceInfoView> _orderedDeepSeekBalances(
  List<DeepSeekBalanceInfoView> balances,
) {
  final ordered = List<DeepSeekBalanceInfoView>.of(balances);
  final cnyIndex = ordered.indexWhere(
    (item) => item.currency.toUpperCase() == 'CNY',
  );
  if (cnyIndex > 0) {
    final cny = ordered.removeAt(cnyIndex);
    ordered.insert(0, cny);
  }
  return ordered;
}

class _DeepSeekCurrencyBalanceCard extends StatelessWidget {
  const _DeepSeekCurrencyBalanceCard({
    required this.balance,
    required this.compact,
  });

  final DeepSeekBalanceInfoView balance;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metricWidth = compact ? 132.0 : 160.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 9 : 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: compact ? 15 : 16,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  balance.currency,
                  style: context.text.labelLarge?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < metricWidth
                    ? constraints.maxWidth
                    : metricWidth;
                return Wrap(
                  spacing: compact ? 14 : 18,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: width,
                      child: _DeepSeekBalanceMetric(
                        label: context.l10n.settingsUsageTotalBalance,
                        value: '${balance.currency} ${balance.totalBalance}',
                        prominent: true,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _DeepSeekBalanceMetric(
                        label: context.l10n.settingsUsageGrantedBalance,
                        value: '${balance.currency} ${balance.grantedBalance}',
                        icon: Icons.card_giftcard_outlined,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _DeepSeekBalanceMetric(
                        label: context.l10n.settingsUsageToppedUpBalance,
                        value: '${balance.currency} ${balance.toppedUpBalance}',
                        icon: Icons.payments_outlined,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DeepSeekBalanceMetric extends StatelessWidget {
  const _DeepSeekBalanceMetric({
    required this.label,
    required this.value,
    this.icon,
    this.prominent = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      value: value,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: context.colors.onSurfaceVariant),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            softWrap: true,
            style:
                (prominent ? context.text.titleSmall : context.text.bodySmall)
                    ?.copyWith(
                      color: context.colors.onSurface,
                      fontWeight: prominent ? FontWeight.w700 : FontWeight.w600,
                    ),
          ),
        ],
      ),
    );
  }
}

class _ZhipuCodingPlanUsage extends StatelessWidget {
  const _ZhipuCodingPlanUsage({required this.usage});

  final ZhipuCodingPlanUsageView usage;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      findQuotaLimit(usage.limits, 'fiveHour'),
      findQuotaLimit(usage.limits, 'weekly'),
      findQuotaLimit(usage.limits, 'mcpMonthly'),
      ...usage.limits.where((limit) => limit.window == 'other'),
    ].whereType<ZhipuQuotaLimitView>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (usage.level != null && usage.level!.isNotEmpty) ...[
          SettingsInfoPill(
            icon: Icons.workspace_premium_outlined,
            label: usage.level!,
          ),
          const SizedBox(height: 8),
        ],
        if (ordered.isEmpty)
          ProviderUsageMessage(
            icon: Icons.info_outline,
            message: context.l10n.settingsUsageUnavailable,
            tone: UsageTone.muted,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 650;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final limit in ordered)
                    SizedBox(
                      width: twoColumns
                          ? (constraints.maxWidth - 10) / 2
                          : constraints.maxWidth,
                      child: _QuotaCard(limit: limit),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.limit});

  final ZhipuQuotaLimitView limit;

  @override
  Widget build(BuildContext context) {
    final percent = quotaRemainingPercent(limit);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quotaTitle(context, limit),
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: context.colors.onSurface),
                  ),
                ),
                Text(
                  quotaResetLabel(context, limit.nextResetAt),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              formatPercent(percent),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: context.colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              quotaDetail(context, limit),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: percent / 100,
                  backgroundColor: context.colors.surfaceContainerHigh,
                  color: percent >= 65
                      ? context.statusColors.success
                      : context.colors.primary,
                ),
              ),
            ),
            if (limit.usageDetails.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final detail in limit.usageDetails)
                    Tooltip(
                      message: detail.name,
                      child: StudioPill(
                        tone: StudioTone.neutral,
                        label: '${detail.name} ${formatToolUsage(detail)}',
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProviderUsageMessage extends StatelessWidget {
  const ProviderUsageMessage({
    super.key,
    required this.icon,
    required this.message,
    required this.tone,
  });

  final IconData icon;
  final String message;
  final UsageTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (tone) {
      UsageTone.failed => colors.error,
      UsageTone.warning => context.statusColors.warning,
      UsageTone.neutral || UsageTone.muted => colors.onSurfaceVariant,
    };
    return StudioInlineMessage(icon: icon, message: message, color: color);
  }
}

enum UsageTone { failed, warning, neutral, muted }
