import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/general_settings_state.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_form_field.dart';
import 'web_search_labels.dart';
import 'web_search_status_value.dart';

/// Web-search configuration card.
///
/// Geometry follows the pre-refactor settings card: 16 px inner padding, an
/// icon + title/subtitle header with the always-present availability chip,
/// 16 px to the status readouts, 18 px to the field grid and 14 px to the save
/// row. The card is always rendered; a not-yet-read configuration shows the
/// "not available" copy with disabled controls instead of disappearing.
class WebSearchSettingsCard extends StatelessWidget {
  const WebSearchSettingsCard({
    required this.web,
    required this.configured,
    required this.effective,
    required this.editable,
    required this.saving,
    required this.errors,
    required this.onMode,
    required this.onContextSize,
    required this.onDomains,
    required this.onCountry,
    required this.onRegion,
    required this.onCity,
    required this.onTimezone,
    required this.onSave,
    super.key,
  });

  final WebSearchDraft web;
  final WebSearchConfiguration? configured;
  final EffectiveWebSearch? effective;
  final bool editable;
  final bool saving;
  final List<String> errors;
  final ValueChanged<String> onMode;
  final ValueChanged<String?> onContextSize;
  final ValueChanged<String> onDomains;
  final ValueChanged<String> onCountry;
  final ValueChanged<String> onRegion;
  final ValueChanged<String> onCity;
  final ValueChanged<String> onTimezone;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final availability = effective?.availability;
    final contextSizeValue = web.contextSize ?? '';
    final enabled = editable && !saving;
    final configuredMode = configured?.configuredMode;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.travel_explore,
                color: context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsWebSearchTitle,
                      style: context.text.titleMedium?.copyWith(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.settingsWebSearchSubtitle,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  availability == null
                      ? l10n.settingsNotAvailable
                      : webSearchAvailabilityLabel(context, availability),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              WebSearchStatusValue(
                label: l10n.settingsWebSearchConfiguredMode,
                value: configuredMode == null
                    ? l10n.settingsNotAvailable
                    : webSearchModeLabel(context, configuredMode),
              ),
              WebSearchStatusValue(
                label: l10n.settingsWebSearchEffectiveMode,
                value: effective == null
                    ? l10n.settingsNotAvailable
                    : webSearchModeLabel(context, effective!.effectiveMode),
              ),
              WebSearchStatusValue(
                label: l10n.settingsWebSearchAccount,
                value: effective?.accountId ?? l10n.settingsNotAvailable,
              ),
              WebSearchStatusValue(
                label: l10n.settingsWebSearchModel,
                value: effective?.modelId ?? l10n.settingsNotAvailable,
              ),
            ],
          ),
          if (availability != null &&
              webSearchShowsAvailabilityReason(availability)) ...[
            const SizedBox(height: 12),
            Text(
              webSearchAvailabilityReason(context, availability),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ],
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = constraints.maxWidth >= 620
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownMenu<String>(
                      key: const ValueKey('web_search_mode'),
                      initialSelection: web.mode,
                      label: Text(l10n.settingsWebSearchMode),
                      hintText: knownWebSearchModes.contains(web.mode)
                          ? null
                          : webSearchModeLabel(context, web.mode),
                      expandedInsets: EdgeInsets.zero,
                      dropdownMenuEntries: [
                        for (final mode in knownWebSearchModes)
                          DropdownMenuEntry<String>(
                            value: mode,
                            label: webSearchModeLabel(context, mode),
                            labelWidget: KeyedSubtree(
                              key: ValueKey('web_search_mode_$mode'),
                              child: Text(webSearchModeLabel(context, mode)),
                            ),
                          ),
                      ],
                      onSelected: enabled
                          ? (value) {
                              if (value != null) onMode(value);
                            }
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownMenu<String>(
                      key: const ValueKey('web_search_context_size'),
                      initialSelection: contextSizeValue,
                      label: Text(l10n.settingsWebSearchContextSize),
                      hintText:
                          contextSizeValue.isEmpty ||
                              knownWebSearchContextSizes.contains(
                                contextSizeValue,
                              )
                          ? null
                          : webSearchContextSizeLabel(
                              context,
                              contextSizeValue,
                            ),
                      expandedInsets: EdgeInsets.zero,
                      dropdownMenuEntries: [
                        DropdownMenuEntry<String>(
                          value: '',
                          label: l10n.settingsServiceDefault,
                          labelWidget: KeyedSubtree(
                            key: const ValueKey(
                              'web_search_context_size_default',
                            ),
                            child: Text(l10n.settingsServiceDefault),
                          ),
                        ),
                        for (final size in knownWebSearchContextSizes)
                          DropdownMenuEntry<String>(
                            value: size,
                            label: webSearchContextSizeLabel(context, size),
                            labelWidget: KeyedSubtree(
                              key: ValueKey('web_search_context_size_$size'),
                              child: Text(
                                webSearchContextSizeLabel(context, size),
                              ),
                            ),
                          ),
                      ],
                      onSelected: enabled
                          ? (value) => onContextSize(
                              value == null || value.isEmpty ? null : value,
                            )
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: SettingsFormField(
                      key: const ValueKey('web_search_domains'),
                      value: web.domains,
                      label: l10n.settingsWebSearchAllowedDomains,
                      hint: l10n.settingsWebSearchDomainsHint,
                      enabled: enabled,
                      onChanged: onDomains,
                    ),
                  ),
                  for (final field in [
                    (
                      fieldKey: const ValueKey('web_search_country'),
                      value: web.country,
                      label: l10n.settingsWebSearchCountry,
                      change: onCountry,
                    ),
                    (
                      fieldKey: const ValueKey('web_search_region'),
                      value: web.region,
                      label: l10n.settingsWebSearchRegion,
                      change: onRegion,
                    ),
                    (
                      fieldKey: const ValueKey('web_search_city'),
                      value: web.city,
                      label: l10n.settingsWebSearchCity,
                      change: onCity,
                    ),
                    (
                      fieldKey: const ValueKey('web_search_timezone'),
                      value: web.timezone,
                      label: l10n.settingsWebSearchTimezone,
                      change: onTimezone,
                    ),
                  ])
                    SizedBox(
                      width: fieldWidth,
                      child: SettingsFormField(
                        key: field.fieldKey,
                        value: field.value,
                        label: field.label,
                        enabled: enabled,
                        onChanged: field.change,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                key: const ValueKey('web_search_save'),
                onPressed: enabled ? onSave : null,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(l10n.settingsSaveWebSearch),
              ),
              if (web.dirtyFields.isNotEmpty && !saving) ...[
                const SizedBox(width: 12),
                Text(
                  l10n.settingsWebSearchUnsaved,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (errors.isNotEmpty) ...[
                const SizedBox(width: 12),
                Expanded(child: SettingsInlineError(message: errors.first)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
