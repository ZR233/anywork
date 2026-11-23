import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import 'account_sections.dart';

typedef AcpPhaseStyle = ({Color accent, Color background, IconData icon});

/// Shared visual mapping for ACP connection & authentication phase badges.
AcpPhaseStyle acpPhaseStyle(BuildContext context, AcpPresentationPhase phase) {
  final scheme = Theme.of(context).colorScheme;
  final semantic = Theme.of(context).extension<StudioSemanticColors>();
  return switch (phase) {
    AcpPresentationPhase.connected || AcpPresentationPhase.ready => (
      accent: semantic?.success ?? scheme.primary,
      background:
          semantic?.successContainer ??
          Color.alphaBlend(
            (semantic?.success ?? scheme.primary).withValues(alpha: 0.12),
            scheme.surfaceContainerHigh,
          ),
      icon: Icons.check_circle_rounded,
    ),
    AcpPresentationPhase.needsLogin => (
      accent: semantic?.warning ?? scheme.tertiary,
      background:
          semantic?.warningContainer ??
          Color.alphaBlend(
            (semantic?.warning ?? scheme.tertiary).withValues(alpha: 0.14),
            scheme.surfaceContainerHigh,
          ),
      icon: Icons.login_rounded,
    ),
    AcpPresentationPhase.failed => (
      accent: scheme.error,
      background: scheme.errorContainer.withValues(alpha: 0.55),
      icon: Icons.error_outline_rounded,
    ),
    AcpPresentationPhase.preparing ||
    AcpPresentationPhase.checking ||
    AcpPresentationPhase.reconnecting ||
    AcpPresentationPhase.authenticating ||
    AcpPresentationPhase.verifying => (
      accent: scheme.primary,
      background: scheme.primaryContainer.withValues(alpha: 0.45),
      icon: Icons.sync_rounded,
    ),
    AcpPresentationPhase.idle ||
    AcpPresentationPhase.cancelling ||
    AcpPresentationPhase.closing => (
      accent: scheme.onSurfaceVariant,
      background: scheme.surfaceContainerHigh,
      icon: Icons.dns_outlined,
    ),
  };
}

/// Inline managed `1.x` upgrade banner shared between account cards and details.
class AcpUpgradeBanner extends StatelessWidget {
  const AcpUpgradeBanner({
    required this.upgrade,
    this.upgradeButtonKey,
    this.cancelButtonKey,
    this.checkButtonKey,
    this.onUpgrade,
    this.onCancel,
    this.onCheckUpdate,
    this.compact = false,
    this.embedded = false,
    super.key,
  });

  final AcpCardUpgradePresentation upgrade;
  final Key? upgradeButtonKey;
  final Key? cancelButtonKey;
  final Key? checkButtonKey;
  final VoidCallback? onUpgrade;
  final VoidCallback? onCancel;
  final VoidCallback? onCheckUpdate;
  final bool compact;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<StudioSemanticColors>();

    switch (upgrade.phase) {
      case AcpUpgradePhase.idle:
      case AcpUpgradePhase.upToDate:
        if (compact) return const SizedBox.shrink();
        final version = upgrade.installedVersion ?? upgrade.latestVersion ?? '';
        return _BannerSurface(
          background: scheme.surfaceContainerLow,
          borderColor: scheme.outlineVariant.withValues(alpha: 0.55),
          embedded: embedded,
          child: Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 18,
                color: semantic?.success ?? scheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  version.isNotEmpty
                      ? l10n.acpUpgradeUpToDate(version)
                      : l10n.acpInstallReadyTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        );

      case AcpUpgradePhase.checking:
        return _BannerSurface(
          background: scheme.surfaceContainerHigh.withValues(alpha: 0.65),
          borderColor: scheme.outlineVariant.withValues(alpha: 0.5),
          embedded: embedded,
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 8 : 12,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.acpUpgradeChecking,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );

      case AcpUpgradePhase.updateAvailable:
        final latest = upgrade.latestVersion ?? '';
        final current = upgrade.installedVersion ?? upgrade.runningVersion;
        final accent = scheme.primary;
        final versionDelta =
            current != null &&
                current.isNotEmpty &&
                latest.isNotEmpty &&
                current != latest
            ? l10n.acpUpgradeAvailableVersions(current, latest)
            : (latest.isNotEmpty ? l10n.acpVersionTag(latest) : null);
        return _BannerSurface(
          background: Color.alphaBlend(
            accent.withValues(alpha: 0.08),
            scheme.surfaceContainerLow,
          ),
          borderColor: accent.withValues(alpha: 0.34),
          embedded: embedded,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      size: 17,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.acpUpgradeAvailableTitle,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        if (versionDelta != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            versionDelta,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (upgrade.canUpgrade && onUpgrade != null)
                FilledButton.icon(
                  key: upgradeButtonKey,
                  style: accountActionButtonStyle(context),
                  onPressed: onUpgrade,
                  icon: const Icon(Icons.upgrade_rounded, size: 18),
                  label: Text(
                    latest.isNotEmpty
                        ? l10n.acpUpgradeAction(latest)
                        : l10n.acpUpgradeActionGeneric,
                  ),
                ),
            ],
          ),
        );

      case AcpUpgradePhase.upgrading:
        final target = upgrade.latestVersion ?? '';
        final title = target.isNotEmpty
            ? l10n.acpUpgradeUpgrading(target)
            : (upgrade.stageLabel ?? l10n.acpInstallStageDownload);
        return _BannerSurface(
          background: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.07),
            scheme.surfaceContainerLow,
          ),
          borderColor: scheme.primary.withValues(alpha: 0.28),
          embedded: embedded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (upgrade.stageLabel != null && target.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.6,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              upgrade.stageLabel!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (upgrade.canCancel && onCancel != null)
                    TextButton(
                      key: cancelButtonKey,
                      onPressed: onCancel,
                      child: Text(l10n.acpInstallCancel),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: upgrade.progress,
                  minHeight: 6,
                ),
              ),
              if (upgrade.progressLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  upgrade.progressLabel!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        );

      case AcpUpgradePhase.pendingSwitch:
        final nextVersion =
            upgrade.installedVersion ?? upgrade.latestVersion ?? '';
        final accent = semantic?.warning ?? scheme.tertiary;
        return _BannerSurface(
          background:
              semantic?.warningContainer ??
              Color.alphaBlend(
                accent.withValues(alpha: 0.1),
                scheme.surfaceContainerLow,
              ),
          borderColor: accent.withValues(alpha: 0.34),
          embedded: embedded,
          child: Row(
            children: [
              Icon(Icons.swap_horiz_rounded, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.acpUpgradePendingSwitch(nextVersion),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        );

      case AcpUpgradePhase.incompatibleMajor:
        final nextVersion = upgrade.latestVersion ?? '';
        final accent = semantic?.warning ?? scheme.tertiary;
        return _BannerSurface(
          background:
              semantic?.warningContainer ??
              Color.alphaBlend(
                accent.withValues(alpha: 0.1),
                scheme.surfaceContainerLow,
              ),
          borderColor: accent.withValues(alpha: 0.34),
          embedded: embedded,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: accent),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      l10n.acpUpgradeIncompatibleMajor(nextVersion),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              if (upgrade.canCheck && onCheckUpdate != null)
                TextButton(
                  key: checkButtonKey,
                  onPressed: onCheckUpdate,
                  child: Text(l10n.acpUpgradeRetryCheck),
                ),
            ],
          ),
        );

      case AcpUpgradePhase.failed:
        return _BannerSurface(
          background: scheme.errorContainer.withValues(alpha: 0.35),
          borderColor: scheme.error.withValues(alpha: 0.35),
          embedded: embedded,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      upgrade.error ?? l10n.acpUpgradeCheckFailed,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (upgrade.canUpgrade && onUpgrade != null)
                    FilledButton(
                      key: upgradeButtonKey,
                      onPressed: onUpgrade,
                      child: Text(
                        upgrade.latestVersion != null
                            ? l10n.acpUpgradeAction(upgrade.latestVersion!)
                            : l10n.acpInstallFailureRetry,
                      ),
                    ),
                  if (upgrade.canCheck && onCheckUpdate != null)
                    TextButton(
                      key: checkButtonKey,
                      onPressed: onCheckUpdate,
                      child: Text(l10n.acpUpgradeRetryCheck),
                    ),
                ],
              ),
            ],
          ),
        );
    }
  }
}

/// Dedicated managed component card for account details view.
class AcpManagedVersionCard extends StatelessWidget {
  const AcpManagedVersionCard({
    required this.upgrade,
    required this.onAction,
    super.key,
  });

  final AcpCardUpgradePresentation upgrade;
  final ValueChanged<AcpAccountAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentVersion = upgrade.installedVersion ?? upgrade.runningVersion;
    final busy =
        upgrade.phase == AcpUpgradePhase.checking ||
        upgrade.phase == AcpUpgradePhase.upgrading;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.acpManagedServerTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (currentVersion != null &&
                        currentVersion.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          l10n.acpVersionTag(currentVersion),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                OutlinedButton.icon(
                  style: accountActionButtonStyle(context),
                  key: ValueKey<String>(
                    AccountViewKeyValues.acpAction(
                      AcpAccountAction.checkUpdate.name,
                    ),
                  ),
                  onPressed: (!busy && upgrade.canCheck)
                      ? () => onAction(AcpAccountAction.checkUpdate)
                      : null,
                  icon: busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : const Icon(Icons.update_rounded, size: 18),
                  label: Text(
                    upgrade.phase == AcpUpgradePhase.checking
                        ? l10n.acpUpgradeChecking
                        : l10n.acpUpgradeCheck,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            AcpUpgradeBanner(
              upgrade: upgrade,
              embedded: true,
              upgradeButtonKey: ValueKey<String>(
                AccountViewKeyValues.acpAction(AcpAccountAction.upgrade.name),
              ),
              cancelButtonKey: ValueKey<String>(
                AccountViewKeyValues.acpAction(
                  AcpAccountAction.cancelPreparation.name,
                ),
              ),
              onUpgrade: () => onAction(AcpAccountAction.upgrade),
              onCancel: () => onAction(AcpAccountAction.cancelPreparation),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerSurface extends StatelessWidget {
  const _BannerSurface({
    required this.background,
    required this.borderColor,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.embedded = false,
  });

  final Color background;
  final Color borderColor;
  final EdgeInsetsGeometry padding;
  final bool embedded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (embedded) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
