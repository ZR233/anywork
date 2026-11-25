import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/account_brand.dart';
import '../state/account_presentations.dart';

/// Focused guidance, access-mode switcher and official endpoint presets for
/// Google Gemini REST accounts (AI Studio & GCP Vertex AI).
class AccountGeminiConnectionPanel extends StatelessWidget {
  const AccountGeminiConnectionPanel({
    required this.value,
    required this.saving,
    required this.onTemplateChanged,
    required this.onEndpointPresetSelected,
    super.key,
  });

  final AccountGeminiConnectionPresentation value;
  final bool saving;
  final ValueChanged<AccountTemplateKey> onTemplateChanged;
  final ValueChanged<String> onEndpointPresetSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isVertex = value.mode == AccountGeminiGuidanceMode.vertexAi;
    final isCustomEndpoint =
        value.endpointKind == AccountGeminiEndpointKind.custom;

    final modeTitle = isCustomEndpoint
        ? l10n.accountsGeminiModeCustom
        : isVertex
        ? l10n.accountsGeminiModeVertexAi
        : l10n.accountsGeminiModeAiStudio;
    final modeHint = isCustomEndpoint
        ? l10n.accountsGeminiHintCustom
        : isVertex
        ? l10n.accountsGeminiHintVertexAi
        : l10n.accountsGeminiHintAiStudio;

    final presets = isVertex
        ? <(String, AccountGeminiEndpointPreset)>[
            (
              l10n.accountsGeminiPresetGlobal,
              AccountGeminiEndpointPreset.vertexGlobal,
            ),
            ('us-central1', AccountGeminiEndpointPreset.vertexUsCentral1),
            ('europe-west4', AccountGeminiEndpointPreset.vertexEuropeWest4),
            (
              'asia-northeast1',
              AccountGeminiEndpointPreset.vertexAsiaNortheast1,
            ),
          ]
        : <(String, AccountGeminiEndpointPreset)>[
            (
              l10n.accountsGeminiPresetAiStudioOfficial,
              AccountGeminiEndpointPreset.aiStudio,
            ),
          ];

    final badges = <(IconData icon, String label)>[
      (Icons.vpn_key_outlined, l10n.accountsGeminiBadgeHeader),
      (Icons.image_outlined, l10n.accountsGeminiBadgeMultimodal),
      if (value.hasBundledCatalog)
        (Icons.inventory_2_outlined, l10n.accountsGeminiBadgeBundledCatalog),
      if (value.supportsModelDiscovery == true)
        (Icons.travel_explore_outlined, l10n.accountsGeminiBadgeDiscovery),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value.canSwitchMode) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<AccountGeminiGuidanceMode>(
              key: const ValueKey<String>('gemini-access-mode-switcher'),
              segments: [
                ButtonSegment(
                  value: AccountGeminiGuidanceMode.vertexAi,
                  icon: const Icon(Icons.cloud_outlined),
                  label: Text(l10n.accountsGeminiModeVertexAi),
                ),
                ButtonSegment(
                  value: AccountGeminiGuidanceMode.aiStudio,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(l10n.accountsGeminiModeAiStudio),
                ),
              ],
              selected: {value.mode},
              onSelectionChanged: saving
                  ? null
                  : (selection) {
                      final mode = selection.single;
                      if (mode == value.mode) return;
                      final id = mode == AccountGeminiGuidanceMode.vertexAi
                          ? 'vertex-ai'
                          : 'gemini';
                      onTemplateChanged(
                        AccountTemplateKey(kind: AccountKind.native, id: id),
                      );
                    },
            ),
          ),
          const SizedBox(height: 16),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AccountBrandMark(
                      iconKey: isVertex ? 'vertex' : 'gemini',
                      fallbackName: modeTitle,
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            modeTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            modeHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final badge in badges)
                      _GeminiCapabilityBadge(icon: badge.$1, label: badge.$2),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.accountsGeminiEndpointPresetsLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in presets)
                      _GeminiEndpointPresetChip(
                        key: ValueKey<String>(
                          'gemini-preset:${preset.$2.endpoint}',
                        ),
                        label: preset.$1,
                        selected: value.selectedPreset == preset.$2,
                        enabled: !saving,
                        onTap: () =>
                            onEndpointPresetSelected(preset.$2.endpoint),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GeminiEndpointPresetChip extends StatelessWidget {
  const _GeminiEndpointPresetChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(8);
    final borderColor = selected
        ? colors.primary.withValues(alpha: 0.45)
        : colors.outlineVariant;
    final foregroundColor = selected
        ? colors.onPrimaryContainer
        : colors.onSurface;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled ? (_) => onTap() : null,
      backgroundColor: colors.surfaceContainerLowest,
      selectedColor: colors.primaryContainer,
      checkmarkColor: foregroundColor,
      showCheckmark: true,
      side: BorderSide(color: borderColor),
      shape: RoundedRectangleBorder(borderRadius: radius),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        height: 1.25,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: foregroundColor,
      ),
    );
  }
}

class _GeminiCapabilityBadge extends StatelessWidget {
  const _GeminiCapabilityBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
