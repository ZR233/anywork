import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import 'settings_common.dart';
import 'settings_update_row.dart';
import 'settings_web_search.dart';

class GeneralTab extends StatefulWidget {
  const GeneralTab({
    super.key,
    required this.settings,
    required this.webSearch,
    required this.deepSeekWebSearch,
    required this.runtimeBusy,
    required this.onCommand,
    required this.onSaveWebSearch,
    required this.onDeepSeekSearchChanged,
    required this.onDeepSeekFetchChanged,
  });

  final GeneralSettingsView settings;
  final WebSearchSettingsView webSearch;
  final DeepSeekWebSearchSettingsView deepSeekWebSearch;
  final bool runtimeBusy;
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

  @override
  Widget build(BuildContext context) {
    return SettingsPane(
      header: SettingsHeader(
        title: context.l10n.settingsGeneralTitle,
        subtitle: context.l10n.settingsGeneralSubtitle,
      ),
      children: [
        const SizedBox(height: 16),
        SettingsSectionPanel(
          title: context.l10n.settingsAppearanceGroup,
          children: [
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
          children: [StudioUpdateSettingsRow(runtimeBusy: widget.runtimeBusy)],
        ),
        if (_error != null) SettingsInlineError(message: _error!),
      ],
    );
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
