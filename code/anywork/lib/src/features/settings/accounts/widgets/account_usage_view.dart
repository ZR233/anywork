import 'package:flutter/material.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import 'account_sections.dart';
import 'account_usage_metrics.dart';

enum AccountStatusLabelLayout { singleLine, wrap }

/// The main billing label and query health deliberately use separate channels.
class AccountBillingBadge extends StatelessWidget {
  const AccountBillingBadge({
    required this.billing,
    this.health = AccountBalanceHealth.unknown,
    this.labelLayout = AccountStatusLabelLayout.singleLine,
    super.key,
  });
  final AccountBilling billing;
  final AccountBalanceHealth health;
  final AccountStatusLabelLayout labelLayout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<StudioSemanticColors>()!;
    final label = accountBillingLabel(l10n, billing);
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
      labelLayout: labelLayout,
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
    this.labelLayout = AccountStatusLabelLayout.singleLine,
    super.key,
  });
  final String label;
  final Color? foreground;
  final Color? background;
  final Color? indicator;
  final AccountStatusLabelLayout labelLayout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = foreground ?? scheme.onSurfaceVariant;
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      alignment: AlignmentDirectional.centerStart,
      child: Chip(
        avatar:
            labelLayout == AccountStatusLabelLayout.wrap || indicator == null
            ? null
            : Icon(Icons.circle, size: 8, color: indicator),
        labelPadding: labelLayout == AccountStatusLabelLayout.wrap
            ? EdgeInsets.zero
            : null,
        label: switch (labelLayout) {
          AccountStatusLabelLayout.singleLine => Text(label),
          AccountStatusLabelLayout.wrap => Builder(
            builder: (labelContext) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (indicator != null) ...[
                    Icon(Icons.circle, size: 8, color: indicator),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    fit: FlexFit.loose,
                    child: RichText(
                      text: TextSpan(
                        text: label,
                        style: DefaultTextStyle.of(labelContext).style,
                      ),
                      maxLines: null,
                      softWrap: true,
                      overflow: TextOverflow.clip,
                      textScaler: MediaQuery.textScalerOf(labelContext),
                      locale: Localizations.localeOf(labelContext),
                      textDirection: Directionality.of(labelContext),
                    ),
                  ),
                ],
              ),
            ),
          ),
        },
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        labelStyle: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: textColor),
        backgroundColor: background ?? scheme.surfaceContainerLow,
      ),
    );
  }
}

class AccountUsageView extends StatelessWidget {
  const AccountUsageView({
    required this.value,
    this.onRetry,
    this.density = AccountMetricDensity.detailed,
    this.showUpdated = true,
    this.showHealth = true,
    super.key,
  });
  final AccountUsagePresentation value;
  final VoidCallback? onRetry;
  final AccountMetricDensity density;
  final bool showUpdated;
  final bool showHealth;

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
        if (showHealth && value.balanceHealth != AccountBalanceHealth.unknown)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              value.balanceHealth == AccountBalanceHealth.sufficient
                  ? l10n.settingsUsageBalanceSufficient
                  : l10n.settingsUsageBalanceInsufficient,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: value.balanceHealth == AccountBalanceHealth.sufficient
                    ? Theme.of(context)
                          .extension<StudioSemanticColors>()!
                          .success
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        if (value.phase == AccountQueryPhase.loading) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
        ],
        for (final balance in value.balances)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AccountBalanceMetrics(value: balance, density: density),
          ),
        if (value.quotas.isNotEmpty)
          AccountQuotaMetrics(values: value.quotas, density: density),
        if (phaseLabel != null && value.phase != AccountQueryPhase.failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(phaseLabel, style: Theme.of(context).textTheme.bodyMedium),
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
        if ((showUpdated ||
                value.phase == AccountQueryPhase.failed && value.hasLastGood) &&
            value.updatedLabel != null)
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
