import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import 'account_sections.dart';

/// The main billing label and query health deliberately use separate channels.
class AccountBillingBadge extends StatelessWidget {
  const AccountBillingBadge({
    required this.billing,
    this.health = AccountBalanceHealth.unknown,
    super.key,
  });
  final AccountBilling billing;
  final AccountBalanceHealth health;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final label =
        billing == AccountBilling.metered &&
            health != AccountBalanceHealth.unknown
        ? health == AccountBalanceHealth.sufficient
              ? l10n.settingsUsageBalanceSufficient
              : l10n.settingsUsageBalanceInsufficient
        : accountBillingLabel(l10n, billing);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: health == AccountBalanceHealth.insufficient
              ? scheme.errorContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: health == AccountBalanceHealth.insufficient
                ? scheme.onErrorContainer
                : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class AccountUsageView extends StatelessWidget {
  const AccountUsageView({
    required this.value,
    this.onRetry,
    this.compact = false,
    super.key,
  });
  final AccountUsagePresentation value;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phaseLabel = switch (value.phase) {
      AccountQueryPhase.idle => l10n.accountsQueryIdle,
      AccountQueryPhase.loading => l10n.settingsUsageRefreshing,
      AccountQueryPhase.unsupported => l10n.accountsQueryUnsupported,
      AccountQueryPhase.missingCredential => l10n.settingsUsageApiKeyMissing,
      AccountQueryPhase.failed => l10n.accountsQueryFailed,
      AccountQueryPhase.ready => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value.phase == AccountQueryPhase.loading) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
        ],
        for (final balance in value.balances)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 420
                    ? constraints.maxWidth / 3 - 8
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 8,
                  runSpacing: 12,
                  children: [
                    for (final metric in [
                      (l10n.settingsUsageAvailableBalance, balance.total),
                      (l10n.settingsUsageGrantedBalance, balance.granted),
                      (l10n.settingsUsageToppedUpBalance, balance.toppedUp),
                    ])
                      if (metric.$2 != null)
                        SizedBox(
                          width: width,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metric.$1,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${balance.currency} ${metric.$2}',
                                style: compact
                                    ? Theme.of(context).textTheme.titleMedium
                                    : Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        if (value.quotas.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 520
                  ? 3
                  : constraints.maxWidth >= 340
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final quota in value.quotas)
                    SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            quota.label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${l10n.accountsRemaining} ${quota.remaining}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (quota.remainingFraction != null) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: quota.remainingFraction,
                              color: quota.low
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                          if (quota.resetLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                l10n.settingsUsageReset(quota.resetLabel!),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (quota.low)
                            Text(
                              l10n.accountsLowQuota,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        if (phaseLabel != null && value.phase != AccountQueryPhase.failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              phaseLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (value.phase == AccountQueryPhase.failed)
          AccountInlineError(
            message: [
              l10n.accountsQueryFailed,
              if (value.hasLastGood) l10n.accountsUsageLastGood,
              ?value.error,
            ].join('\n'),
            onRetry: value.canRetry ? onRetry : null,
          ),
        if (value.updatedLabel != null)
          Text(
            l10n.settingsUsageUpdated(value.updatedLabel!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
