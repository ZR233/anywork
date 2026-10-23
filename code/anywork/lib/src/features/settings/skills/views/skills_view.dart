import 'package:anywork_client/skills.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_pane.dart';
import '../state/skills_view_state.dart';

class SkillsView extends StatelessWidget {
  const SkillsView({required this.queryRaw, required this.rows, required this.disabledNames,
    required this.hasProject, required this.configurationKnown, required this.canEdit, required this.discovering, required this.canDiscover,
    required this.searching, required this.catalogIncomplete, required this.searchTruncated,
    required this.knownEmpty, required this.hasMore, required this.reading,
    required this.warnings, required this.errors, required this.sources,
    required this.onQuery, required this.onEnabled, required this.onDiscover,
    required this.onRefresh, required this.onMore, super.key});
  final String queryRaw;
  final List<SettingsSkillRow> rows;
  final Set<String> disabledNames;
  final bool hasProject;
  final bool configurationKnown;
  final bool canEdit;
  final bool discovering;
  final bool canDiscover;
  final bool searching;
  final bool catalogIncomplete;
  final bool searchTruncated;
  final bool knownEmpty;
  final bool hasMore;
  final bool reading;
  final List<String> warnings;
  final List<String> errors;
  final List<Widget> sources;
  final ValueChanged<String> onQuery;
  final void Function(String name, bool enabled) onEnabled;
  final VoidCallback onDiscover;
  final VoidCallback onRefresh;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => SettingsPane(title: context.l10n.settingsSkillsTitle,
    subtitle: context.l10n.settingsSkillsSubtitle,
    trailing: FilledButton.icon(key: StudioDriverKeys.skillsDiscover, onPressed: canDiscover ? onDiscover : null,
      icon: discovering ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.travel_explore),
      label: Text(discovering ? context.l10n.settingsDiscovering : context.l10n.settingsDiscover)),
    toolbar: SettingsFormField(value: queryRaw, label: context.l10n.settingsFilterSkills, onChanged: onQuery),
    child: ListView(children: [
      ...sources,
      if (searching) const LinearProgressIndicator(),
      if (catalogIncomplete || searchTruncated) Text(context.l10n.statusUsageIncompleteLabel),
      for (final warning in warnings) SelectableText(warning),
      for (final error in errors) SelectableText(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (errors.isNotEmpty) Align(alignment: Alignment.centerLeft,
        child: TextButton(onPressed: reading ? null : onRefresh, child: Text(context.l10n.runtimeFatalRetry))),
      for (final row in rows) ExpansionTile(key: PageStorageKey('skill-details-${row.name}'),
        controlAffinity: ListTileControlAffinity.leading, title: Text(row.name),
        subtitle: switch (row) {
          CatalogSettingsSkillRow(:final summary) when summary.description.isNotEmpty => Text(summary.description, maxLines: 2, overflow: TextOverflow.ellipsis),
          _ => null,
        },
        trailing: configurationKnown ? Switch(key: ValueKey('skill-enabled-${row.name}'), value: !disabledNames.contains(row.name),
          onChanged: canEdit ? (value) => onEnabled(row.name, value) : null) : const Text('—'),
        children: [Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 18),
          child: SelectableText(key: PageStorageKey('skill-description-${row.name}'), switch (row) {
            CatalogSettingsSkillRow(:final summary) => [summary.description, summary.source.name, summary.providerId,
              switch (summary.resourceBase) {
                DirectorySkillResourceBase(:final path) => path,
                UrlSkillResourceBase(:final url) => url,
                OpaqueSkillResourceBase(:final description) => description,
              }].where((value) => value.isNotEmpty).join('\n'),
            NameOnlySettingsSkillRow() => '—',
          }, style: Theme.of(context).textTheme.bodySmall)))],
      ),
      if (rows.isEmpty && !searching && (!hasProject || knownEmpty || queryRaw.trim().isNotEmpty))
        Padding(padding: const EdgeInsets.all(24), child: Column(children: [
          const Icon(Icons.extension_outlined),
          Text(hasProject ? context.l10n.settingsNoSkillsMatchFilter : context.l10n.settingsOpenProjectToDiscoverSkills),
          Text(hasProject ? context.l10n.settingsClearSearchOrDiscoverAgain : context.l10n.settingsSkillsDiscoverySources),
        ])),
      if (hasMore && queryRaw.trim().isEmpty) Align(alignment: Alignment.centerLeft,
        child: TextButton(onPressed: reading ? null : onMore, child: Text(context.l10n.settingsSshNextPage))),
    ]));
}
