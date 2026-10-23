import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/feedback/studio_messages.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_pane.dart';
import '../../widgets/settings_source_status_view.dart';
import '../state/general_settings_state.dart';

class GeneralSettingsView extends StatelessWidget {
  const GeneralSettingsView({required this.state, required this.errors,
    required this.onFollow, required this.onCompact, required this.onSearch,
    required this.onFetch, required this.onMode, required this.onContextSize,
    required this.onDomains, required this.onCountry, required this.onRegion,
    required this.onCity, required this.onTimezone, required this.onSaveWeb,
    required this.onRetryRead, this.updates, super.key});

  final GeneralSettingsViewState state;
  final List<String> errors;
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
  final Widget? updates;

  bool _blocked(GeneralSettingAction key) => state.actions[key]?.preventsResubmission ?? false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final web = state.webSearch;
    const modes = ['disabled', 'cached', 'indexed', 'live'];
    const sizes = ['low', 'medium', 'high'];
    return SettingsPane(
      title: l10n.settingsGeneralTitle, subtitle: l10n.settingsGeneralSubtitle,
      child: ListView(children: [
        SettingsSourceStatusView(title: l10n.settingsGeneralTitle, brief: state.source.projection.header?.source.brief,
          read: state.source.sourceStatus, origin: state.source.projection.stamp?.origin,
          reference: state.source.projection.header?.source.status, onRetry: onRetryRead),
        SettingsSourceStatusView(title: l10n.settingsAccountModelsTitle, brief: state.modelSource.projection.header?.source.brief,
          read: state.modelSource.sourceStatus, origin: state.modelSource.projection.stamp?.origin,
          reference: state.modelSource.projection.header?.source.status, onRetry: onRetryRead),
        if (state.canonical case final general?) SettingsSection(title: l10n.settingsAppearanceGroup, children: [
          SwitchListTile(key: const ValueKey('general-follow-active-turn'),
            title: Text(l10n.settingsFollowActiveTurn), subtitle: Text(l10n.settingsFollowActiveTurnSubtitle),
            value: general.followActiveTurn,
            onChanged: _blocked(GeneralSettingAction.followActiveTurn) ? null : onFollow),
          SwitchListTile(key: const ValueKey('general-compact-timeline'),
            title: Text(l10n.settingsCompactTimeline), subtitle: Text(l10n.settingsCompactTimelineSubtitle),
            value: general.compactTimeline,
            onChanged: _blocked(GeneralSettingAction.compactTimeline) ? null : onCompact),
        ]),
        if (web != null && state.configuredWebSearch != null) SettingsSection(title: l10n.settingsWebSearchTitle, children: [
          Text(l10n.settingsWebSearchSubtitle),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 8, children: [
            _value(l10n.settingsWebSearchConfiguredMode, _modeLabel(context, state.configuredWebSearch!.configuredMode)),
            _value(l10n.settingsWebSearchEffectiveMode, state.effectiveWebSearch == null
              ? '—' : _modeLabel(context, state.effectiveWebSearch!.effectiveMode)),
            _value(l10n.settingsWebSearchAccount, state.effectiveWebSearch?.accountId ?? '—'),
            _value(l10n.settingsWebSearchModel, state.effectiveWebSearch?.modelId ?? '—'),
          ]),
          if (state.effectiveWebSearch case final effective?) ...[
            const SizedBox(height: 8), Text(_availability(context, effective.availability)),
          ],
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            DropdownMenu<String>(key: const ValueKey('web_search_mode'),
              initialSelection: web.mode, enabled: !state.webSaving,
              label: Text(l10n.settingsWebSearchMode),
              dropdownMenuEntries: [
                if (!modes.contains(web.mode)) DropdownMenuEntry(value: web.mode, label: web.mode, enabled: false),
                for (final mode in modes) DropdownMenuEntry(value: mode,
                  label: _modeLabel(context, mode), labelWidget: Text(_modeLabel(context, mode),
                    key: ValueKey('web_search_mode_$mode'))),
              ], onSelected: (value) { if (value != null) onMode(value); }),
            DropdownMenu<String>(key: const ValueKey('web_search_context_size'),
              initialSelection: web.contextSize ?? '', enabled: !state.webSaving,
              label: Text(l10n.settingsWebSearchContextSize),
              dropdownMenuEntries: [
                DropdownMenuEntry(value: '', label: l10n.settingsServiceDefault,
                  labelWidget: Text(l10n.settingsServiceDefault, key: const ValueKey('web_search_context_size_default'))),
                if (web.contextSize != null && !sizes.contains(web.contextSize))
                  DropdownMenuEntry(value: web.contextSize!, label: web.contextSize!, enabled: false),
                for (final size in sizes) DropdownMenuEntry(value: size, label: _sizeLabel(context, size),
                  labelWidget: Text(_sizeLabel(context, size), key: ValueKey('web_search_context_size_$size'))),
              ], onSelected: (value) { if (value != null) onContextSize(value.isEmpty ? null : value); }),
          ]),
          const SizedBox(height: 12),
          SettingsFormField(key: const ValueKey('web_search_domains'), value: web.domains,
            label: l10n.settingsWebSearchAllowedDomains, hint: l10n.settingsWebSearchDomainsHint,
            enabled: !state.webSaving, onChanged: onDomains),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) => Wrap(spacing: 12, runSpacing: 12, children: [
            for (final field in [
              (id: 'country', value: web.country, label: l10n.settingsWebSearchCountry, change: onCountry),
              (id: 'region', value: web.region, label: l10n.settingsWebSearchRegion, change: onRegion),
              (id: 'city', value: web.city, label: l10n.settingsWebSearchCity, change: onCity),
              (id: 'timezone', value: web.timezone, label: l10n.settingsWebSearchTimezone, change: onTimezone),
            ]) SizedBox(width: constraints.maxWidth >= 620 ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth,
              child: SettingsFormField(key: ValueKey('web_search_${field.id}'), value: field.value,
                label: field.label, enabled: !state.webSaving, onChanged: field.change)),
          ])),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: FilledButton.icon(
            key: const ValueKey('web_search_save'), onPressed: state.webSaving ? null : onSaveWeb,
            icon: state.webSaving ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined), label: Text(l10n.settingsSaveWebSearch))),
          if (web.dirtyFields.isNotEmpty) Text(l10n.settingsWebSearchUnsaved),
        ]),
        if (state.configuredDeepSeek case final deepSeek?) SettingsSection(title: l10n.settingsDeepSeekWebSearchTitle, children: [
          Text(l10n.settingsDeepSeekWebSearchSubtitle),
          SwitchListTile(key: const ValueKey('deepseek_web_search_enabled'),
            title: Text(l10n.settingsDeepSeekWebSearchEnableLabel), value: deepSeek.configuredEnabled,
            onChanged: _blocked(GeneralSettingAction.deepSeekSearch) ? null : onSearch),
          SwitchListTile(key: const ValueKey('deepseek_web_fetch_enabled'),
            title: Text(l10n.settingsDeepSeekWebFetchEnableLabel), value: deepSeek.configuredFetchEnabled,
            onChanged: _blocked(GeneralSettingAction.deepSeekFetch) ? null : onFetch),
          Wrap(spacing: 16, runSpacing: 8, children: [
            _value(l10n.settingsDeepSeekWebSearchConfigured, _enabled(context, deepSeek.configuredEnabled)),
            _value(l10n.settingsDeepSeekWebFetchConfigured, _enabled(context, deepSeek.configuredFetchEnabled)),
            _value(l10n.settingsDeepSeekWebSearchEffective, state.effectiveDeepSeek == null
              ? '—' : _enabled(context, state.effectiveDeepSeek!.effectiveEnabled)),
            _value(l10n.settingsDeepSeekWebFetchEffective, state.effectiveDeepSeek == null
              ? '—' : _enabled(context, state.effectiveDeepSeek!.effectiveFetchEnabled)),
            _value(l10n.settingsDeepSeekWebSearchAccount, state.effectiveDeepSeek?.accountId ?? '—'),
          ]),
          if (state.effectiveDeepSeek case final effective?) Text(_availability(context, effective.availability)),
        ]),
        if (updates != null) SettingsSection(title: l10n.settingsUpdatesGroup, children: [updates!]),
        for (final error in errors) Padding(padding: const EdgeInsets.only(bottom: 12),
          child: StudioInlineMessage(icon: Icons.error_outline, message: error,
            color: Theme.of(context).colorScheme.error)),
        if (state.readErrors.isNotEmpty) Align(alignment: Alignment.centerLeft,
          child: TextButton(onPressed: state.readPending ? null : onRetryRead, child: Text(l10n.sidebarRetry))),
      ]),
    );
  }

  Widget _value(String label, String value) => SizedBox(width: 180,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), SelectableText(value)]));
}

String _modeLabel(BuildContext context, String value) => switch (value) {
  'disabled' => context.l10n.settingsWebSearchModeDisabled,
  'cached' => context.l10n.settingsWebSearchModeCached,
  'indexed' => context.l10n.settingsWebSearchModeIndexed,
  'live' => context.l10n.settingsWebSearchModeLive,
  _ => value,
};
String _sizeLabel(BuildContext context, String value) => switch (value) {
  'low' => context.l10n.settingsWebSearchContextLow,
  'medium' => context.l10n.settingsWebSearchContextMedium,
  'high' => context.l10n.settingsWebSearchContextHigh,
  _ => value,
};
String _availability(BuildContext context, String value) => switch (value) {
  'available' => context.l10n.settingsWebSearchAvailable,
  'disabled' => context.l10n.settingsWebSearchDisabled,
  'missingCredential' => context.l10n.settingsWebSearchMissingCredential,
  'accountUnsupported' => context.l10n.settingsWebSearchUnsupportedAccount,
  'modelUnsupported' => context.l10n.settingsWebSearchUnsupportedModel,
  _ => value,
};
String _enabled(BuildContext context, bool value) => value
    ? context.l10n.settingsDeepSeekWebSearchEnabled : context.l10n.settingsWebSearchDisabled;
