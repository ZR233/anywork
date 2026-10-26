import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/settings_navigation_state.dart';

/// Layout only. Smart supplies real panels for the actual visited tabs.
class SettingsView extends StatelessWidget {
  const SettingsView({
    required this.state,
    required this.panels,
    required this.onSelect,
    required this.onBack,
    super.key,
  });
  final SettingsNavigationState state;
  final Map<SettingsTab, Widget> panels;
  final ValueChanged<SettingsTab> onSelect;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    assert(!state.visible || panels.containsKey(state.tab));
    final body = Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in panels.entries)
          Offstage(
            key: ValueKey(entry.key),
            offstage: !state.visible || state.tab != entry.key,
            child: ExcludeFocus(
              excluding: !state.visible || state.tab != entry.key,
              child: TickerMode(
                enabled: state.visible && state.tab == entry.key,
                child: entry.value,
              ),
            ),
          ),
      ],
    );
    return KeyedSubtree(
      key: StudioDriverKeys.settingsPage,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final navigation = Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: compact
                ? SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      children: [
                        _back(context, true),
                        for (final tab in SettingsTab.values)
                          _tab(context, tab, true),
                      ],
                    ),
                  )
                : SizedBox(
                    width: StudioLayout.settingsNavigationWidth,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
                      children: [
                        _back(context, false),
                        _group(context, context.l10n.settingsModelsGroup),
                        for (final tab in [
                          SettingsTab.accounts,
                          SettingsTab.agents,
                          SettingsTab.instructions,
                          SettingsTab.modes,
                        ])
                          _tab(context, tab, false),
                        _group(context, context.l10n.settingsExtensionsGroup),
                        for (final tab in [
                          SettingsTab.skills,
                          SettingsTab.mcp,
                          SettingsTab.lsp,
                          SettingsTab.ssh,
                        ])
                          _tab(context, tab, false),
                        _group(context, context.l10n.settingsPreferencesGroup),
                        for (final tab in [
                          SettingsTab.statistics,
                          SettingsTab.security,
                          SettingsTab.general,
                          SettingsTab.bots,
                        ])
                          _tab(context, tab, false),
                      ],
                    ),
                  ),
          );
          return compact
              ? Column(
                  children: [
                    navigation,
                    Expanded(child: body),
                  ],
                )
              : Row(
                  children: [
                    navigation,
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                );
        },
      ),
    );
  }

  Widget _group(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
  Widget _back(BuildContext context, bool compact) => Tooltip(
    message: context.l10n.settingsBack,
    child: TextButton.icon(
      key: StudioDriverKeys.settingsBack,
      onPressed: state.leaving ? null : onBack,
      icon: const Icon(Icons.arrow_back, size: 16),
      label: compact
          ? const SizedBox.shrink()
          : Text(context.l10n.settingsBackToChat),
    ),
  );
  Widget _tab(BuildContext context, SettingsTab tab, bool compact) {
    final selected = state.tab == tab;
    // Keep the established Driver identity; the public enum no longer exposes
    // the old private workModes spelling as a domain/navigation alias.
    final id = tab == SettingsTab.modes ? 'workModes' : tab.name;
    return Padding(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 2)
          : const EdgeInsets.only(bottom: 3),
      child: TextButton.icon(
        key: StudioDriverKeys.settingsTab(id),
        onPressed: state.leaving ? null : () => onSelect(tab),
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          foregroundColor: selected
              ? Theme.of(context).colorScheme.onPrimaryContainer
              : Theme.of(context).colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        icon: Icon(_icon(tab), size: 18),
        label: Text(
          _label(context, tab),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  IconData _icon(SettingsTab tab) => switch (tab) {
    SettingsTab.accounts => Icons.cloud_outlined,
    SettingsTab.agents => Icons.groups_outlined,
    SettingsTab.instructions => Icons.notes_outlined,
    SettingsTab.modes => Icons.account_tree_outlined,
    SettingsTab.skills => Icons.extension_outlined,
    SettingsTab.mcp => Icons.hub_outlined,
    SettingsTab.lsp => Icons.code_outlined,
    SettingsTab.ssh => Icons.dns_outlined,
    SettingsTab.statistics => Icons.query_stats_outlined,
    SettingsTab.security => Icons.security_outlined,
    SettingsTab.general => Icons.tune_outlined,
    SettingsTab.bots => Icons.smart_toy_outlined,
  };
  String _label(BuildContext context, SettingsTab tab) => switch (tab) {
    SettingsTab.accounts => context.l10n.settingsAccountsTab,
    SettingsTab.agents => context.l10n.settingsAgentsTab,
    SettingsTab.instructions => context.l10n.settingsInstructionsTab,
    SettingsTab.modes => context.l10n.modeEditorTitle,
    SettingsTab.skills => context.l10n.settingsSkillsTab,
    SettingsTab.mcp => context.l10n.settingsMcpTab,
    SettingsTab.lsp => context.l10n.settingsLspTab,
    SettingsTab.ssh => context.l10n.settingsSshTab,
    SettingsTab.statistics => context.l10n.settingsStatisticsTab,
    SettingsTab.security => context.l10n.settingsSecurityTab,
    SettingsTab.general => context.l10n.settingsGeneralTab,
    SettingsTab.bots => context.l10n.settingsBotsTab,
  };
}
