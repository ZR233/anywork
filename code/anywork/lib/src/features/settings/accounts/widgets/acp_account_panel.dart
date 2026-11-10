import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import 'account_sections.dart';
import 'account_usage_metrics.dart';

String acpActionLabel(AppLocalizations l10n, AcpAccountAction action) =>
    switch (action) {
      AcpAccountAction.prepare => l10n.acpInstallStart,
      AcpAccountAction.cancelPreparation => l10n.acpInstallCancel,
      AcpAccountAction.usePrepared => l10n.acpInstallUsePrepared,
      AcpAccountAction.check => l10n.acpAuthCheck,
      AcpAccountAction.login => l10n.acpAuthLogin,
      AcpAccountAction.cancelAuthentication => l10n.acpAuthCancel,
      AcpAccountAction.retry => l10n.acpAuthRetry,
      AcpAccountAction.queryUsage => l10n.acpUsageQuery,
      AcpAccountAction.openGuide => l10n.acpAccountInstallOpen,
      AcpAccountAction.openTerms => l10n.acpAccountTermsOpen,
    };

IconData _acpActionIcon(AcpAccountAction action) => switch (action) {
  AcpAccountAction.prepare => Icons.download_outlined,
  AcpAccountAction.cancelPreparation => Icons.close,
  AcpAccountAction.usePrepared => Icons.check_circle_outline,
  AcpAccountAction.check => Icons.sync,
  AcpAccountAction.login => Icons.open_in_browser,
  AcpAccountAction.cancelAuthentication => Icons.close,
  AcpAccountAction.retry => Icons.refresh,
  AcpAccountAction.queryUsage => Icons.pie_chart_outline,
  AcpAccountAction.openGuide => Icons.open_in_new,
  AcpAccountAction.openTerms => Icons.open_in_new,
};

class AcpAccountPanel extends StatelessWidget {
  const AcpAccountPanel({
    required this.value,
    required this.onAction,
    required this.onLoginMethodChanged,
    this.showUsage = false,
    this.omitQueryUsageAction = false,
    super.key,
  });
  final AcpAccountPresentation value;
  final ValueChanged<AcpAccountAction> onAction;
  final ValueChanged<String> onLoginMethodChanged;
  final bool showUsage;
  final bool omitQueryUsageAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<StudioSemanticColors>();
    final (
      Color accentColor,
      Color containerColor,
      IconData statusIcon,
    ) = switch (value.phase) {
      AcpPresentationPhase.connected || AcpPresentationPhase.ready => (
        semantic?.success ?? scheme.primary,
        Color.alphaBlend(
          (semantic?.success ?? scheme.primary).withValues(alpha: 0.08),
          scheme.surfaceContainerLow,
        ),
        Icons.check_circle_outline,
      ),
      AcpPresentationPhase.needsLogin => (
        semantic?.warning ?? scheme.tertiary,
        Color.alphaBlend(
          (semantic?.warning ?? scheme.tertiary).withValues(alpha: 0.10),
          scheme.surfaceContainerLow,
        ),
        Icons.login_outlined,
      ),
      AcpPresentationPhase.failed => (
        scheme.error,
        Color.alphaBlend(
          scheme.error.withValues(alpha: 0.08),
          scheme.surfaceContainerLow,
        ),
        Icons.error_outline,
      ),
      AcpPresentationPhase.preparing ||
      AcpPresentationPhase.checking ||
      AcpPresentationPhase.authenticating ||
      AcpPresentationPhase.verifying => (
        scheme.primary,
        Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.08),
          scheme.surfaceContainerLow,
        ),
        Icons.sync,
      ),
      AcpPresentationPhase.idle ||
      AcpPresentationPhase.cancelling ||
      AcpPresentationPhase.closing => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerLow,
        Icons.dns_outlined,
      ),
    };

    final showPrimary =
        value.hasPrimaryAction &&
        !(omitQueryUsageAction &&
            value.primaryAction == AcpAccountAction.queryUsage);
    final secondaryActions = [
      for (final action in value.availableActions)
        if (action != AcpAccountAction.openGuide &&
            action != AcpAccountAction.openTerms &&
            !(omitQueryUsageAction && action == AcpAccountAction.queryUsage) &&
            (!value.hasPrimaryAction || action != value.primaryAction))
          action,
    ];
    final docActions = [
      for (final action in value.availableActions)
        if (action == AcpAccountAction.openGuide ||
            action == AcpAccountAction.openTerms)
          action,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accentColor.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(statusIcon, size: 22, color: accentColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value.status,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (value.message != null) ...[
                  const SizedBox(height: 12),
                  AccountSelectableText(
                    value.message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (value.phase == AcpPresentationPhase.preparing ||
                    value.progress != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value.progress,
                      minHeight: 6,
                    ),
                  ),
                ],
                if (value.progressLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    value.progressLabel!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (value.error != null) ...[
          const SizedBox(height: 12),
          AccountInlineError(message: value.error!),
        ],
        if (value.loginMethods.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l10n.acpAuthMethodSelectHint,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final method in value.loginMethods)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AcpLoginMethodCard(
                method: method,
                selected: value.selectedLoginMethod == method.id,
                enabled: value.canSelectLoginMethod,
                recommendedLabel: l10n.acpAuthRecommendedBadge,
                onTap: () => onLoginMethodChanged(method.id),
              ),
            ),
        ],
        if (showPrimary || secondaryActions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (showPrimary)
                FilledButton(
                  style: accountActionButtonStyle(context),
                  key: ValueKey<String>(
                    AccountViewKeyValues.acpAction(value.primaryAction!.name),
                  ),
                  onPressed: () => onAction(value.primaryAction!),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_acpActionIcon(value.primaryAction!), size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(acpActionLabel(l10n, value.primaryAction!)),
                      ),
                    ],
                  ),
                ),
              for (final action in secondaryActions)
                OutlinedButton(
                  style: accountActionButtonStyle(context),
                  key: ValueKey<String>(
                    AccountViewKeyValues.acpAction(action.name),
                  ),
                  onPressed: () => onAction(action),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_acpActionIcon(action), size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          action == AcpAccountAction.queryUsage &&
                                  value.usage.queried
                              ? l10n.acpUsageRefresh
                              : acpActionLabel(l10n, action),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (showUsage) ...[
          const SizedBox(height: 20),
          Text(
            l10n.acpUsageTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          AcpUsageMetrics(value: value.usage),
        ],
        if (value.facts.isNotEmpty || docActions.isNotEmpty) ...[
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (value.facts.isNotEmpty) AccountFacts(facts: value.facts),
                  if (value.facts.isNotEmpty && docActions.isNotEmpty)
                    const Divider(height: 16),
                  if (docActions.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final action in docActions)
                          TextButton.icon(
                            key: ValueKey<String>(
                              AccountViewKeyValues.acpAction(action.name),
                            ),
                            onPressed: () => onAction(action),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: Text(acpActionLabel(l10n, action)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AcpLoginMethodCard extends StatelessWidget {
  const _AcpLoginMethodCard({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.recommendedLabel,
    required this.onTap,
  });

  final AcpLoginMethodPresentation method;
  final bool selected;
  final bool enabled;
  final String recommendedLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final borderColor = selected ? scheme.primary : scheme.outlineVariant;
    final backgroundColor = selected
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.08),
            scheme.surfaceContainerLowest,
          )
        : scheme.surfaceContainerLowest;
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        backgroundColor: backgroundColor,
        side: BorderSide(color: borderColor, width: selected ? 1.5 : 1),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      method.label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (method.recommended)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            recommendedLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
