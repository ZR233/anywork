import 'package:anywork_client/modes.dart'
    show DelegationMode, DelegationPreference;
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_pane.dart';
import '../../widgets/settings_rows.dart';
import '../state/general_settings_state.dart';
import '../widgets/deepseek_web_search_settings_card.dart';
import '../widgets/delegation_defaults_section.dart';
import '../widgets/web_search_settings_card.dart';

/// General settings page.
///
/// Block order and chrome follow the pre-refactor tab: delegation defaults
/// first, then appearance, search & network, updates, and only then inline
/// failures. Read state itself is not rendered: a healthy read produces no row
/// at all, so the content keeps its original vertical position.
class GeneralSettingsView extends StatelessWidget {
  const GeneralSettingsView({
    required this.state,
    required this.errors,
    required this.webErrors,
    required this.deepSeekErrors,
    required this.onFollow,
    required this.onCompact,
    required this.onSearch,
    required this.onFetch,
    required this.onMode,
    required this.onContextSize,
    required this.onDomains,
    required this.onCountry,
    required this.onRegion,
    required this.onCity,
    required this.onTimezone,
    required this.onSaveWeb,
    required this.onDelegationMode,
    required this.onDelegationPreference,
    required this.delegationReadError,
    required this.delegationModeErrors,
    required this.delegationPreferenceErrors,
    required this.onRetryRead,
    this.updates,
    super.key,
  });

  final GeneralSettingsViewState state;

  /// Page-level failures (source sync, frozen reads, appearance toggles).
  final List<String> errors;
  final List<String> webErrors;
  final List<String> deepSeekErrors;
  final ValueChanged<bool> onFollow;
  final ValueChanged<bool> onCompact;
  final ValueChanged<bool> onSearch;
  final ValueChanged<bool> onFetch;
  final ValueChanged<String> onMode;
  final ValueChanged<String?> onContextSize;
  final ValueChanged<String> onDomains;
  final ValueChanged<String> onCountry;
  final ValueChanged<String> onRegion;
  final ValueChanged<String> onCity;
  final ValueChanged<String> onTimezone;
  final VoidCallback onSaveWeb;
  final VoidCallback onRetryRead;
  final ValueChanged<DelegationMode> onDelegationMode;
  final ValueChanged<DelegationPreference> onDelegationPreference;
  final String? delegationReadError;
  final List<String> delegationModeErrors;
  final List<String> delegationPreferenceErrors;
  final Widget? updates;

  bool _blocked(GeneralSettingAction key) =>
      state.actions[key]?.preventsResubmission ?? false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final web = state.webSearch;
    final configuredWeb = state.configuredWebSearch;
    final configuredDeepSeek = state.configuredDeepSeek;
    final canonical = state.canonical;
    // Every block stays on the page, like the pre-refactor tab: a not-yet-read
    // configuration renders its placeholder values instead of disappearing and
    // shifting the sections below it.
    final draft =
        web ??
        const WebSearchDraft(
          mode: 'disabled',
          contextSize: null,
          domains: '',
          country: '',
          region: '',
          city: '',
          timezone: '',
        );
    return SettingsPane.scrolling(
      title: l10n.settingsGeneralTitle,
      subtitle: l10n.settingsGeneralSubtitle,
      children: [
        const SizedBox(height: 16),
        DelegationDefaultsSection(
          state: state,
          readError: delegationReadError,
          modeErrors: delegationModeErrors,
          preferenceErrors: delegationPreferenceErrors,
          onMode: onDelegationMode,
          onPreference: onDelegationPreference,
          onRetry: onRetryRead,
        ),
        SettingsSection(
          title: l10n.settingsAppearanceGroup,
          children: [
            // The rows stay on the page before the first read; without canonical
            // data they report the unavailable placeholder and accept no command.
            if (canonical == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.settingsNotAvailable,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            SettingsToggleRow(
              key: const ValueKey('general-follow-active-turn'),
              icon: Icons.vertical_align_bottom,
              title: l10n.settingsFollowActiveTurn,
              subtitle: l10n.settingsFollowActiveTurnSubtitle,
              value: canonical?.followActiveTurn ?? false,
              onChanged: canonical == null
                  ? null
                  : (value) {
                      if (!_blocked(GeneralSettingAction.followActiveTurn)) {
                        onFollow(value);
                      }
                    },
            ),
            SettingsToggleRow(
              key: const ValueKey('general-compact-timeline'),
              icon: Icons.view_agenda_outlined,
              title: l10n.settingsCompactTimeline,
              subtitle: l10n.settingsCompactTimelineSubtitle,
              value: canonical?.compactTimeline ?? false,
              onChanged: canonical == null
                  ? null
                  : (value) {
                      if (!_blocked(GeneralSettingAction.compactTimeline)) {
                        onCompact(value);
                      }
                    },
            ),
          ],
        ),
        SettingsSection(
          title: l10n.settingsNetworkGroup,
          children: [
            WebSearchSettingsCard(
              web: draft,
              configured: configuredWeb,
              effective: state.effectiveWebSearch,
              editable: configuredWeb != null,
              saving: state.webSaving,
              errors: webErrors,
              onMode: onMode,
              onContextSize: onContextSize,
              onDomains: onDomains,
              onCountry: onCountry,
              onRegion: onRegion,
              onCity: onCity,
              onTimezone: onTimezone,
              onSave: onSaveWeb,
            ),
            const Divider(height: 32),
            DeepSeekWebSearchSettingsCard(
              configured: configuredDeepSeek,
              effective: state.effectiveDeepSeek,
              editable: configuredDeepSeek != null,
              searchSaving: _blocked(GeneralSettingAction.deepSeekSearch),
              fetchSaving: _blocked(GeneralSettingAction.deepSeekFetch),
              errors: deepSeekErrors,
              onSearch: onSearch,
              onFetch: onFetch,
            ),
          ],
        ),
        if (updates != null)
          SettingsSection(
            title: l10n.settingsUpdatesGroup,
            children: [updates!],
          ),
        for (final error in errors) SettingsInlineError(message: error),
      ],
    );
  }
}
