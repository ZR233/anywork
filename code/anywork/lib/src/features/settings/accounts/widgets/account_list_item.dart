import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import 'account_identity.dart';
import 'account_sections.dart';
import 'account_usage_metrics.dart';
import 'account_usage_view.dart';
import 'acp_upgrade_banner.dart';

class AccountListItem extends StatelessWidget {
  const AccountListItem({
    required this.value,
    required this.layout,
    this.selected = false,
    super.key,
    required this.onOpen,
    required this.onAction,
  });

  final AccountRowPresentation value;
  final AccountItemLayout layout;
  final bool selected;
  final VoidCallback onOpen;
  final ValueChanged<AccountRowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final acpContent = switch (value.content) {
      final AcpAccountRowContent acp => acp,
      _ => null,
    };
    final nativeContent = switch (value.content) {
      final NativeAccountRowContent native => native,
      _ => null,
    };
    final upgradeAvailable =
        acpContent?.upgrade?.phase == AcpUpgradePhase.updateAvailable;

    final identity = AccountIdentity(
      name: value.name,
      iconKey: value.iconKey,
      isDefault: value.isDefault,
      subtitleLayout: AccountIdentitySubtitleLayout.singleLine,
      subtitle: nativeContent == null
          ? null
          : nativeContent.accountLabel ?? nativeContent.displayEndpoint,
    );

    final metaChips = acpContent == null
        ? const <Widget>[]
        : [
            if (acpContent.sourceLabel case final source?
                when source.isNotEmpty)
              _MetadataTag(
                label: source,
                accent: acpContent.isManaged
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
                background: acpContent.isManaged
                    ? scheme.primaryContainer.withValues(alpha: 0.42)
                    : scheme.surfaceContainerHigh,
              ),
            if (acpContent.versionLabel case final version?
                when version.isNotEmpty)
              _MetadataTag(
                label: version,
                accent: scheme.onSurfaceVariant,
                background: scheme.surfaceContainerHigh,
                tabular: true,
              ),
          ];

    final detailTarget = InkWell(
      key: ValueKey<String>(
        AccountViewKeyValues.row(value.key.kind.name, value.key.id),
      ),
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            if (metaChips.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 50),
                child: Wrap(spacing: 6, runSpacing: 6, children: metaChips),
              ),
            ],
          ],
        ),
      ),
    );

    final statusBadge = switch (value.content) {
      NativeAccountRowContent(:final billing) => AccountBillingBadge(
        billing: billing,
        labelLayout: AccountStatusLabelLayout.singleLine,
      ),
      AcpAccountRowContent(:final status, :final phase) => () {
        final style = acpPhaseStyle(context, phase);
        return AccountStatusBadge(
          label: status,
          foreground: style.accent,
          background: style.background,
          indicator: style.accent,
          labelLayout: AccountStatusLabelLayout.singleLine,
        );
      }(),
    };

    final menuActions = [
      for (final action in value.actions)
        if (action != AccountRowAction.upgrade &&
            action != AccountRowAction.cancelUpgrade)
          action,
    ];

    // Menu is a sibling of the detail target: opening/actions never bubble to it.
    final menu = AccountMenuButton(
      buttonKey: ValueKey<String>(
        AccountViewKeyValues.rowMenu(value.key.kind.name, value.key.id),
      ),
      tooltip: l10n.settingsAccountActions,
      menuChildren: [
        for (final action in menuActions)
          MenuItemButton(
            onPressed: () => onAction(action),
            child: Text(switch (action) {
              AccountRowAction.refresh => l10n.settingsRefreshUsage,
              AccountRowAction.checkUpdate => l10n.acpUpgradeCheck,
              AccountRowAction.setDefault => l10n.settingsSetAsDefaultAccount,
              AccountRowAction.edit => l10n.settingsEditAccount,
              AccountRowAction.delete => l10n.settingsDeleteAccount,
              AccountRowAction.upgrade => l10n.acpUpgradeActionGeneric,
              AccountRowAction.cancelUpgrade => l10n.acpInstallCancel,
            }),
          ),
      ],
    );

    final usage = switch (value.content) {
      NativeAccountRowContent(:final usage) => AccountUsageView(
        value: usage,
        density: AccountMetricDensity.summary,
        showUpdated: false,
        onRetry: () => onAction(AccountRowAction.refresh),
      ),
      AcpAccountRowContent(:final usage) =>
        usage == null
            ? const SizedBox.shrink()
            : AcpUsageMetrics(
                value: usage,
                density: AccountMetricDensity.summary,
              ),
    };

    final hasUsage = switch (value.content) {
      NativeAccountRowContent() => true,
      AcpAccountRowContent(:final usage) => usage != null,
    };

    final showUpgradeBanner = switch (acpContent?.upgrade?.phase) {
      AcpUpgradePhase.checking ||
      AcpUpgradePhase.updateAvailable ||
      AcpUpgradePhase.upgrading ||
      AcpUpgradePhase.pendingSwitch ||
      AcpUpgradePhase.incompatibleMajor ||
      AcpUpgradePhase.failed => true,
      _ => false,
    };

    final cardColor = selected
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLow;
    final borderColor = selected
        ? scheme.primary.withValues(alpha: 0.45)
        : upgradeAvailable
        ? scheme.primary.withValues(alpha: 0.35)
        : scheme.outlineVariant.withValues(alpha: 0.48);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: layout == AccountItemLayout.columns ? 20 : 16,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: layout == AccountItemLayout.columns
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: detailTarget),
                            const SizedBox(width: 12),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: statusBadge,
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            detailTarget,
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: statusBadge,
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 8),
                menu,
              ],
            ),
            if (value.operationError case final error?) ...[
              const SizedBox(height: 10),
              AccountInlineError(message: error),
            ],
            if (showUpgradeBanner && acpContent?.upgrade != null) ...[
              const SizedBox(height: 12),
              AcpUpgradeBanner(
                upgrade: acpContent!.upgrade!,
                compact: true,
                upgradeButtonKey: ValueKey<String>(
                  AccountViewKeyValues.rowUpgrade(
                    value.key.kind.name,
                    value.key.id,
                  ),
                ),
                cancelButtonKey: ValueKey<String>(
                  AccountViewKeyValues.rowCancelUpgrade(
                    value.key.kind.name,
                    value.key.id,
                  ),
                ),
                checkButtonKey: ValueKey<String>(
                  AccountViewKeyValues.rowCheckUpdate(
                    value.key.kind.name,
                    value.key.id,
                  ),
                ),
                onUpgrade: () => onAction(AccountRowAction.upgrade),
                onCancel: () => onAction(AccountRowAction.cancelUpgrade),
                onCheckUpdate: () => onAction(AccountRowAction.checkUpdate),
              ),
            ],
            if (hasUsage) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: usage,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetadataTag extends StatelessWidget {
  const _MetadataTag({
    required this.label,
    required this.accent,
    required this.background,
    this.tabular = false,
  });

  final String label;
  final Color accent;
  final Color background;
  final bool tabular;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: accent,
        fontWeight: FontWeight.w600,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      ),
    ),
  );
}
