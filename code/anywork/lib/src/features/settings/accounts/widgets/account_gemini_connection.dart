import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/account_brand.dart';
import '../state/account_presentations.dart';

const String _vertexGlobalEndpoint =
    'https://aiplatform.googleapis.com/v1/publishers/google';
const String _aiStudioEndpoint =
    'https://generativelanguage.googleapis.com/v1beta';

bool isGeminiAccountPresentation(NativeAccountEditorPresentation value) {
  final templateId = value.templateKey.id;
  if (templateId == 'gemini' || templateId == 'vertex-ai') {
    return true;
  }
  return value.protocolLabel.toLowerCase().contains('gemini');
}

bool _isVertexMode(NativeAccountEditorPresentation value) {
  if (value.templateKey.id == 'vertex-ai') {
    return true;
  }
  if (value.templateKey.id == 'gemini') {
    return false;
  }
  return value.endpoint.raw.toLowerCase().contains('aiplatform.googleapis.com');
}

String geminiCredentialLabel(
  AppLocalizations l10n,
  NativeAccountEditorPresentation value,
) => _isVertexMode(value)
    ? l10n.accountsGeminiCredentialLabelVertex
    : l10n.accountsGeminiCredentialLabelAiStudio;

String _normalizedEndpoint(String raw) =>
    raw.trim().replaceFirst(RegExp(r'/+$'), '');

/// Focused guidance, access-mode switcher and official endpoint presets for
/// Google Gemini REST accounts (AI Studio & GCP Vertex AI).
class AccountGeminiConnectionPanel extends StatelessWidget {
  const AccountGeminiConnectionPanel({
    required this.value,
    required this.onTemplateChanged,
    required this.onEndpointPresetSelected,
    super.key,
  });

  final NativeAccountEditorPresentation value;
  final ValueChanged<AccountTemplateKey> onTemplateChanged;
  final ValueChanged<String> onEndpointPresetSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasVertexTemplate = value.templates.any(
      (t) => t.key.kind == AccountKind.native && t.key.id == 'vertex-ai',
    );
    final hasGeminiTemplate = value.templates.any(
      (t) => t.key.kind == AccountKind.native && t.key.id == 'gemini',
    );
    final canSwitchMode =
        value.canChangeTemplate && hasVertexTemplate && hasGeminiTemplate;
    final isVertex = _isVertexMode(value);
    final normalized = _normalizedEndpoint(value.endpoint.raw);
    final isCustomEndpoint =
        normalized.isNotEmpty &&
        !normalized.contains('aiplatform.googleapis.com') &&
        !normalized.contains('generativelanguage.googleapis.com');

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
        ? <(String label, String url)>[
            (l10n.accountsGeminiPresetGlobal, _vertexGlobalEndpoint),
            (
              'us-central1',
              'https://us-central1-aiplatform.googleapis.com/v1/publishers/google',
            ),
            (
              'europe-west4',
              'https://europe-west4-aiplatform.googleapis.com/v1/publishers/google',
            ),
            (
              'asia-northeast1',
              'https://asia-northeast1-aiplatform.googleapis.com/v1/publishers/google',
            ),
          ]
        : <(String label, String url)>[
            (l10n.accountsGeminiPresetAiStudioOfficial, _aiStudioEndpoint),
          ];

    final badges = <(IconData icon, String label)>[
      (Icons.vpn_key_outlined, l10n.accountsGeminiBadgeHeader),
      (Icons.image_outlined, l10n.accountsGeminiBadgeMultimodal),
      if (isVertex)
        (Icons.inventory_2_outlined, l10n.accountsGeminiBadgeBundledCatalog)
      else
        (Icons.travel_explore_outlined, l10n.accountsGeminiBadgeDiscovery),
      if (!isCustomEndpoint)
        (Icons.bolt_outlined, l10n.accountsGeminiBadgeImplicitCache),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canSwitchMode) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<String>(
              key: const ValueKey<String>('gemini-access-mode-switcher'),
              segments: [
                ButtonSegment(
                  value: 'vertex-ai',
                  icon: const Icon(Icons.cloud_outlined),
                  label: Text(l10n.accountsGeminiModeVertexAi),
                ),
                ButtonSegment(
                  value: 'gemini',
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(l10n.accountsGeminiModeAiStudio),
                ),
              ],
              selected: {isVertex ? 'vertex-ai' : 'gemini'},
              onSelectionChanged: value.saving
                  ? null
                  : (selection) {
                      final id = selection.single;
                      if (id == value.templateKey.id) return;
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
                        key: ValueKey<String>('gemini-preset:${preset.$2}'),
                        label: preset.$1,
                        selected: normalized == preset.$2,
                        enabled: !value.saving,
                        onTap: () => onEndpointPresetSelected(preset.$2),
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
    final backgroundColor = selected
        ? colors.primaryContainer
        : colors.surfaceContainerLowest;
    final borderColor = selected
        ? colors.primary.withValues(alpha: 0.45)
        : colors.outlineVariant;
    final foregroundColor = selected
        ? colors.onPrimaryContainer
        : colors.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check, size: 16, color: foregroundColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    height: 1.25,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foregroundColor,
                  ),
                ),
              ],
            ),
          ),
        ),
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
