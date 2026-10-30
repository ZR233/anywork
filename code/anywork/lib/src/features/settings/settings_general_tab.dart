import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import 'settings_common.dart';
import 'settings_update_row.dart';
import 'settings_web_search.dart';
import 'settings_delegation.dart';

class GeneralTab extends StatefulWidget {
  const GeneralTab({
    super.key,
    required this.settings,
    required this.webSearch,
    required this.deepSeekWebSearch,
    required this.onCommand,
    required this.onSaveWebSearch,
    required this.onDeepSeekSearchChanged,
    required this.onDeepSeekFetchChanged,
  });

  final GeneralSettingsView settings;
  final WebSearchSettingsView webSearch;
  final DeepSeekWebSearchSettingsView deepSeekWebSearch;
  final Future<void> Function(SettingsFieldCommand) onCommand;
  final Future<WebSearchSettingsView> Function(List<SettingsFieldCommand>)
  onSaveWebSearch;
  final Future<void> Function(bool) onDeepSeekSearchChanged;
  final Future<void> Function(bool) onDeepSeekFetchChanged;

  @override
  State<GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<GeneralTab> {
  String? _error;
  bool _savingLanguage = false;

  @override
  Widget build(BuildContext context) {
    return SettingsPane(
      header: SettingsHeader(
        title: context.l10n.settingsGeneralTitle,
        subtitle: context.l10n.settingsGeneralSubtitle,
      ),
      children: [
        const SizedBox(height: 16),
        const DelegationDefaultsPanel(),
        SettingsSectionPanel(
          title: context.l10n.settingsAppearanceGroup,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: DropdownMenu<UiLanguage>(
                // DropdownMenu owns its displayed selection. Recreate it from
                // canonical state after saves (including failures) or relabeling.
                key: ValueKey((
                  widget.settings.language,
                  _savingLanguage,
                  context.l10n.localeName,
                )),
                initialSelection: widget.settings.language,
                enabled: !_savingLanguage,
                expandedInsets: EdgeInsets.zero,
                leadingIcon: const Icon(Icons.language),
                label: Text(context.l10n.settingsInterfaceLanguage),
                helperText: context.l10n.settingsInterfaceLanguageSubtitle,
                dropdownMenuEntries: [
                  DropdownMenuEntry(
                    value: UiLanguage.system,
                    label: context.l10n.settingsLanguageSystem,
                  ),
                  const DropdownMenuEntry(value: UiLanguage.zh, label: '简体中文'),
                  const DropdownMenuEntry(
                    value: UiLanguage.en,
                    label: 'English',
                  ),
                ],
                onSelected: (language) {
                  if (language != null) unawaited(_saveLanguage(language));
                },
              ),
            ),
            SettingsToggleRow(
              icon: Icons.vertical_align_bottom,
              title: context.l10n.settingsFollowActiveTurn,
              subtitle: context.l10n.settingsFollowActiveTurnSubtitle,
              value: widget.settings.followActiveTurn,
              onChanged: (value) =>
                  _save(widget.settings.copyWith(followActiveTurn: value)),
            ),
            SettingsToggleRow(
              icon: Icons.view_agenda_outlined,
              title: context.l10n.settingsCompactTimeline,
              subtitle: context.l10n.settingsCompactTimelineSubtitle,
              value: widget.settings.compactTimeline,
              onChanged: (value) =>
                  _save(widget.settings.copyWith(compactTimeline: value)),
            ),
            if (_error != null) SettingsInlineError(message: _error!),
          ],
        ),
        SettingsSectionPanel(
          title: context.l10n.settingsNetworkGroup,
          children: [
            WebSearchSettingsCard(
              key: const ValueKey('web_search_settings'),
              settings: widget.webSearch,
              onSave: widget.onSaveWebSearch,
            ),
            const Divider(height: 32),
            DeepSeekWebSearchSettingsCard(
              key: const ValueKey('deepseek_web_search_settings'),
              settings: widget.deepSeekWebSearch,
              onSearchChanged: widget.onDeepSeekSearchChanged,
              onFetchChanged: widget.onDeepSeekFetchChanged,
            ),
          ],
        ),
        SettingsSectionPanel(
          title: context.l10n.settingsUpdatesGroup,
          children: [const StudioUpdateSettingsRow()],
        ),
      ],
    );
  }

  Future<void> _saveLanguage(UiLanguage language) async {
    if (_savingLanguage || language == widget.settings.language) return;
    setState(() {
      _savingLanguage = true;
      _error = null;
    });
    try {
      await widget.onCommand(GeneralLanguageCommand(language));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _savingLanguage = false);
    }
  }

  Future<void> _save(GeneralSettingsView settings) async {
    try {
      setState(() => _error = null);
      if (settings.followActiveTurn != widget.settings.followActiveTurn) {
        await widget.onCommand(
          GeneralFollowActiveTurnCommand(settings.followActiveTurn),
        );
      }
      if (settings.compactTimeline != widget.settings.compactTimeline) {
        await widget.onCommand(
          GeneralCompactTimelineCommand(settings.compactTimeline),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }
}
