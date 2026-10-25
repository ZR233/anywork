import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';
import 'web_search_labels.dart';
import 'web_search_status_value.dart';

/// DeepSeek web-search card.
///
/// Same card contract as [WebSearchSettingsCard]: 16 px inner padding, icon +
/// title/subtitle header, 12 px to the two toggle rows, 16 px to the status
/// readouts and 12 px to the always-present availability line. A pending field
/// keeps the pre-refactor spinner in place of its switch instead of widening the
/// row; an unread configuration shows "not available" copy with disabled rows.
class DeepSeekWebSearchSettingsCard extends StatelessWidget {
  const DeepSeekWebSearchSettingsCard({
    required this.configured,
    required this.effective,
    required this.editable,
    required this.searchSaving,
    required this.fetchSaving,
    required this.errors,
    required this.onSearch,
    required this.onFetch,
    super.key,
  });

  final DeepSeekSearchConfiguration? configured;
  final EffectiveDeepSeekSearch? effective;
  final bool editable;
  final bool searchSaving;
  final bool fetchSaving;
  final List<String> errors;
  final ValueChanged<bool> onSearch;
  final ValueChanged<bool> onFetch;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final availability = effective?.availability;
    final searchEnabled = configured?.configuredEnabled ?? false;
    final fetchEnabled = configured?.configuredFetchEnabled ?? false;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, color: context.colors.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsDeepSeekWebSearchTitle,
                      style: context.text.titleMedium?.copyWith(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.settingsDeepSeekWebSearchSubtitle,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DeepSeekToggleRow(
            switchKey: const ValueKey('deepseek_web_search_enabled'),
            label: l10n.settingsDeepSeekWebSearchEnableLabel,
            value: searchEnabled,
            saving: searchSaving,
            onChanged: editable ? onSearch : null,
          ),
          _DeepSeekToggleRow(
            switchKey: const ValueKey('deepseek_web_fetch_enabled'),
            label: l10n.settingsDeepSeekWebFetchEnableLabel,
            value: fetchEnabled,
            saving: fetchSaving,
            onChanged: editable ? onFetch : null,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              WebSearchStatusValue(
                label: l10n.settingsDeepSeekWebSearchConfigured,
                value: configured == null
                    ? l10n.settingsNotAvailable
                    : deepSeekEnabledLabel(context, searchEnabled),
              ),
              WebSearchStatusValue(
                label: l10n.settingsDeepSeekWebSearchEffective,
                value: effective == null
                    ? l10n.settingsNotAvailable
                    : deepSeekEnabledLabel(
                        context,
                        effective!.effectiveEnabled,
                      ),
              ),
              WebSearchStatusValue(
                label: l10n.settingsDeepSeekWebFetchConfigured,
                value: configured == null
                    ? l10n.settingsNotAvailable
                    : deepSeekEnabledLabel(context, fetchEnabled),
              ),
              WebSearchStatusValue(
                label: l10n.settingsDeepSeekWebFetchEffective,
                value: effective == null
                    ? l10n.settingsNotAvailable
                    : deepSeekEnabledLabel(
                        context,
                        effective!.effectiveFetchEnabled,
                      ),
              ),
              WebSearchStatusValue(
                label: l10n.settingsDeepSeekWebSearchAccount,
                value: effective?.accountId ?? l10n.settingsNotAvailable,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            availability == null
                ? l10n.settingsNotAvailable
                : webSearchAvailabilityLabel(context, availability),
            style: context.text.bodySmall?.copyWith(
              // Pre-refactor copy tinted this line by `isAvailable`, so a
              // plainly `disabled` backend was tinted as an error too.
              color: availability == 'available'
                  ? context.colors.onSurfaceVariant
                  : context.colors.error,
            ),
          ),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 10),
            SettingsInlineError(message: errors.first),
          ],
        ],
      ),
    );
  }
}

class _DeepSeekToggleRow extends StatelessWidget {
  const _DeepSeekToggleRow({
    required this.switchKey,
    required this.label,
    required this.value,
    required this.saving,
    required this.onChanged,
  });

  final Key switchKey;
  final String label;
  final bool value;
  final bool saving;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (saving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Switch(key: switchKey, value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
