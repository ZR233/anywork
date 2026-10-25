import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_form_layout.dart';
import '../../widgets/settings_layout.dart';
import '../../widgets/settings_pane.dart';
import '../state/skills_view_state.dart';

/// Skills page.
///
/// Restores the pre-refactor structure: discover action in the header, the
/// filter field as the toolbar, a 16 px + 14 px opening rhythm, one
/// hairline-separated group of expansion tiles, then the empty state and inline
/// failures. Read state itself is not rendered as a standing block.
class SkillsView extends StatelessWidget {
  const SkillsView({
    required this.queryRaw,
    required this.rows,
    required this.disabledNames,
    required this.hasProject,
    required this.configurationKnown,
    required this.canEdit,
    required this.discovering,
    required this.canDiscover,
    required this.catalogIncomplete,
    required this.searchTruncated,
    required this.knownEmpty,
    required this.hasMore,
    required this.reading,
    required this.warnings,
    required this.errors,
    required this.onQuery,
    required this.onEnabled,
    required this.onDiscover,
    required this.onRefresh,
    required this.onMore,
    super.key,
  });
  final String queryRaw;
  final List<SettingsSkillRow> rows;
  final Set<String> disabledNames;
  final bool hasProject;
  final bool configurationKnown;
  final bool canEdit;
  final bool discovering;
  final bool canDiscover;
  final bool catalogIncomplete;
  final bool searchTruncated;
  final bool knownEmpty;
  final bool hasMore;
  final bool reading;
  final List<String> warnings;
  final List<String> errors;
  final ValueChanged<String> onQuery;
  final void Function(String name, bool enabled) onEnabled;
  final VoidCallback onDiscover;
  final VoidCallback onRefresh;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final filter = queryRaw.trim();
    return SettingsPane.scrolling(
      title: context.l10n.settingsSkillsTitle,
      subtitle: context.l10n.settingsSkillsSubtitle,
      trailing: FilledButton.icon(
        key: StudioDriverKeys.skillsDiscover,
        onPressed: canDiscover ? onDiscover : null,
        icon: discovering
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.travel_explore),
        label: Text(
          discovering
              ? context.l10n.settingsDiscovering
              : context.l10n.settingsDiscover,
        ),
      ),
      toolbar: SettingsSearchField(
        hintText: context.l10n.settingsFilterSkills,
        onChanged: onQuery,
      ),
      children: [
        const SizedBox(height: 16),
        const SizedBox(height: 14),
        if (catalogIncomplete || searchTruncated)
          Text(context.l10n.statusUsageIncompleteLabel),
        if (rows.isNotEmpty)
          SettingsGroup(
            children: [
              for (final row in rows)
                ExpansionTile(
                  key: PageStorageKey('skill-details-${row.name}'),
                  controlAffinity: ListTileControlAffinity.leading,
                  tilePadding: EdgeInsets.zero,
                  title: Text(row.name, style: context.text.titleSmall),
                  // The switch is the only enable indicator; the subtitle carries the
                  // description so the two never say the same thing twice.
                  subtitle: switch (row) {
                    CatalogSettingsSkillRow(:final summary)
                        when summary.description.isNotEmpty =>
                      Text(
                        summary.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    _ => null,
                  },
                  trailing: configurationKnown
                      ? Switch(
                          key: ValueKey('skill-enabled-${row.name}'),
                          value: !disabledNames.contains(row.name),
                          onChanged: canEdit
                              ? (value) => onEnabled(row.name, value)
                              : null,
                        )
                      : const Text('—'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: SelectableText(
                          key: PageStorageKey('skill-description-${row.name}'),
                          switch (row) {
                            CatalogSettingsSkillRow(:final summary) => [
                              summary.description,
                              summary.source.name,
                            ].where((value) => value.isNotEmpty).join('\n'),
                            NameOnlySettingsSkillRow() => '',
                          },
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        if (rows.isEmpty &&
            (!hasProject || knownEmpty || filter.isNotEmpty)) ...[
          const SizedBox(height: 12),
          SettingsEmptyMessage(
            icon: Icons.extension_outlined,
            title: hasProject
                ? context.l10n.settingsNoSkillsMatchFilter
                : context.l10n.settingsOpenProjectToDiscoverSkills,
            body: hasProject
                ? context.l10n.settingsClearSearchOrDiscoverAgain
                : context.l10n.settingsSkillsDiscoverySources,
          ),
        ],
        for (final warning in warnings) ...[
          const SizedBox(height: 12),
          SelectableText(
            warning,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
        for (final error in errors) ...[
          const SizedBox(height: 12),
          SettingsInlineError(message: error),
        ],
      ],
    );
  }
}
