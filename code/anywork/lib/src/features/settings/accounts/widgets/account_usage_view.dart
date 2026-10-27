import 'package:flutter/material.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import 'account_sections.dart';
import 'account_usage_metrics.dart';

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
    final semantic = Theme.of(context).extension<StudioSemanticColors>()!;
    final meteredHealth = billing == AccountBilling.metered;
    final label = meteredHealth && health != AccountBalanceHealth.unknown
        ? health == AccountBalanceHealth.sufficient
              ? l10n.settingsUsageBalanceSufficient
              : l10n.settingsUsageBalanceInsufficient
        : accountBillingLabel(l10n, billing);
    final (foreground, background) = switch ((billing, health)) {
      (AccountBilling.metered, AccountBalanceHealth.sufficient) => (
        semantic.success,
        semantic.successContainer,
      ),
      (AccountBilling.metered, AccountBalanceHealth.insufficient) => (
        scheme.onErrorContainer,
        scheme.errorContainer,
      ),
      (AccountBilling.subscription, _) => (
        scheme.onSurface,
        Color.alphaBlend(
          semantic.eyeAccent.withValues(alpha: .12),
          scheme.surfaceContainerLowest,
        ),
      ),
      (AccountBilling.noCharge, _) => (
        scheme.onTertiaryContainer,
        scheme.tertiaryContainer,
      ),
      _ => (scheme.onSurfaceVariant, scheme.surfaceContainerLow),
    };
    return AccountStatusBadge(
      label: label,
      foreground: foreground,
      background: background,
      indicator: billing == AccountBilling.subscription
          ? semantic.activeIndicator
          : foreground,
    );
  }
}

/// ACP can share the status geometry without pretending to have Native billing.
class AccountStatusBadge extends StatelessWidget {
  const AccountStatusBadge({
    required this.label,
    this.foreground,
    this.background,
    this.indicator,
    super.key,
  });
  final String label;
  final Color? foreground;
  final Color? background;
  final Color? indicator;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = foreground ?? scheme.onSurfaceVariant;
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: background ?? scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: indicator ?? textColor,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 8),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  color: textColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
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
    this.showUpdated = true,
    super.key,
  });
  final AccountUsagePresentation value;
  final VoidCallback? onRetry;
  final bool compact;
  final bool showUpdated;

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
            child: AccountBalanceMetrics(value: balance, compact: compact),
          ),
        if (value.quotas.isNotEmpty)
          AccountQuotaMetrics(values: value.quotas, compact: compact),
        if (phaseLabel != null && value.phase != AccountQueryPhase.failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (value.balances.isEmpty && value.quotas.isEmpty)
                  Text('—', style: Theme.of(context).textTheme.titleLarge),
                Text(
                  phaseLabel,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(fontSize: 16),
                ),
              ],
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
        if (showUpdated && value.updatedLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.settingsUsageUpdated(value.updatedLabel!),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontSize: 14),
            ),
          ),
      ],
    );
  }
}
