import 'package:anywork_client/studio_client.dart'
    show DeepSeekWebFetchEnabledCommand, DeepSeekWebSearchEnabledCommand;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_tokens.dart';
import '../../app/routing/app_route.dart';
import '../../presentation/providers/client_provider.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/studio_badges.dart';
import 'settings_agents_tab.dart';
import 'settings_general_tab.dart';
import 'settings_instructions_tab.dart';
import 'settings_lsp_tab.dart';
import 'settings_mcp_tab.dart';
import 'mode_editor/mode_editor_page.dart';
import 'accounts/connectors/accounts_connector.dart';
import 'settings_scope.dart';
import 'settings_section.dart';
import 'settings_security_tab.dart';
import 'settings_skills_tab.dart';
import 'settings_ssh_tab.dart';
import 'statistics/statistics.dart';
import 'settings_views.dart';
import 'settings_bots_tab.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    this.section = SettingsSection.accounts,
    this.accountChild,
    this.routeVisible = true,
    super.key,
  });

  final SettingsSection section;
  final Widget? accountChild;
  final bool routeVisible;

  @override
  Widget build(BuildContext context) => _SettingsPageShell(
    section: section,
    accountChild: accountChild,
    routeVisible: routeVisible,
  );
}

/// Owns the tab controller independently from the reactive settings projection.
/// A model/account save refreshes canonical content without recreating the
/// navigation controller or restarting the whole settings page animation.
class _SettingsPageShell extends StatelessWidget {
  const _SettingsPageShell({
    required this.section,
    required this.routeVisible,
    this.accountChild,
  });

  final SettingsSection section;
  final Widget? accountChild;
  final bool routeVisible;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _settingsTabs.length,
      initialIndex: section.index,
      child: _SettingsPageBody(
        section: section,
        accountChild: accountChild,
        routeVisible: routeVisible,
      ),
    );
  }
}

class _SettingsPageBody extends ConsumerWidget {
  const _SettingsPageBody({
    required this.section,
    required this.routeVisible,
    this.accountChild,
  });

  final SettingsSection section;
  final Widget? accountChild;
  final bool routeVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 页面只观察 Client 的公共 topic 镜像；首个 canonical 到达前显示占位。
    final readiness = ref.watch(settingsPageReadinessProvider);
    if (!readiness.ready) {
      // 仅在首帧尚无任何 canonical 设置视图时占位。
      return Scaffold(
        body: Center(
          child: readiness.error == null
              ? const CircularProgressIndicator()
              : Text(readiness.error!),
        ),
      );
    }
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: KeyedSubtree(
        key: StudioDriverKeys.settingsPage,
        child: _SettingsRouteVisibilitySync(
          section: section,
          routeVisible: routeVisible,
          child: _SettingsScaffold(
            section: section,
            accountChild: accountChild,
            routeVisible: routeVisible,
          ),
        ),
      ),
    );
  }
}

/// Derives display visibility from the committed route section.
///
/// 设置壳保活已访问过的 tab；可见性只决定各数据页的显示观察，不接线 topic lease。
/// account 写入延到微任务，避免在 build/通知阶段直接改 account。
class _SettingsRouteVisibilitySync extends ConsumerStatefulWidget {
  const _SettingsRouteVisibilitySync({
    required this.section,
    required this.routeVisible,
    required this.child,
  });

  final SettingsSection section;
  final bool routeVisible;
  final Widget child;

  @override
  ConsumerState<_SettingsRouteVisibilitySync> createState() =>
      _SettingsRouteVisibilitySyncState();
}

class _SettingsRouteVisibilitySyncState
    extends ConsumerState<_SettingsRouteVisibilitySync> {
  TabController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.of(context);
    if (!identical(controller, _controller)) _controller = controller;
  }

  @override
  void initState() {
    super.initState();
    _syncRouteSection();
  }

  @override
  void didUpdateWidget(covariant _SettingsRouteVisibilitySync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section ||
        oldWidget.routeVisible != widget.routeVisible) {
      _syncRouteSection();
      _syncControllerToRoute();
    }
  }

  void _syncRouteSection() {
    if (!widget.routeVisible) return;
    final index = widget.section.index;
    Future<void>.microtask(() {
      if (!mounted) return;
      ref.read(settingsVisibleTabProvider.notifier).select(index);
    });
  }

  void _syncControllerToRoute() {
    if (!widget.routeVisible) return;
    final controller = _controller;
    final section = widget.section;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.routeVisible || widget.section != section) return;
      if (controller != null && controller.index != section.index) {
        controller.animateTo(section.index);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Each settings tab subscribes to the smallest projection it can render.
/// The retained settings shell therefore survives catalog/config events and a
/// model click only rebuilds the account tab that displays that catalog.
class _ProvidersSettingsTab extends ConsumerWidget {
  const _ProvidersSettingsTab({required this.routeVisible, this.accountChild});

  final bool routeVisible;
  final Widget? accountChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (accountChild case final child?) return child;
    return AccountsConnector(
      visible:
          routeVisible &&
          ref.watch(settingsVisibleTabProvider) ==
              SettingsSection.accounts.index,
    );
  }
}

class _InstructionsSettingsTab extends ConsumerWidget {
  const _InstructionsSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(settingsInstructionsViewProvider);
    final commands = ref.read(anyworkClientProvider).settingsCommands;
    return InstructionsTab(
      settings: view.settings,
      onCommand: (command) async {
        await commands.applySettingsField(command);
      },
    );
  }
}

class _GeneralSettingsTab extends ConsumerWidget {
  const _GeneralSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(settingsGeneralViewProvider);
    final commands = ref.read(anyworkClientProvider).settingsCommands;
    return GeneralTab(
      settings: view.settings,
      webSearch: view.webSearch,
      deepSeekWebSearch: view.deepSeekWebSearch,
      onCommand: (command) async {
        await commands.applySettingsField(command);
      },
      onSaveWebSearch: (changes) async {
        var confirmed = view.webSearch;
        for (final change in changes) {
          confirmed = (await commands.applySettingsField(change)).webSearch;
        }
        return confirmed;
      },
      onDeepSeekSearchChanged: (enabled) async {
        await commands.applySettingsField(
          DeepSeekWebSearchEnabledCommand(enabled),
        );
      },
      onDeepSeekFetchChanged: (enabled) async {
        await commands.applySettingsField(
          DeepSeekWebFetchEnabledCommand(enabled),
        );
      },
    );
  }
}

const _settingsTabs = [
  _SettingsTabInfo(Icons.cloud_outlined, SettingsSection.accounts),
  _SettingsTabInfo(Icons.notes_outlined, SettingsSection.instructions),
  _SettingsTabInfo(Icons.account_tree_outlined, SettingsSection.workModes),
  _SettingsTabInfo(Icons.extension_outlined, SettingsSection.skills),
  _SettingsTabInfo(Icons.groups_outlined, SettingsSection.agents),
  _SettingsTabInfo(Icons.hub_outlined, SettingsSection.mcp),
  _SettingsTabInfo(Icons.code_outlined, SettingsSection.lsp),
  _SettingsTabInfo(Icons.dns_outlined, SettingsSection.ssh),
  _SettingsTabInfo(Icons.query_stats_outlined, SettingsSection.statistics),
  _SettingsTabInfo(Icons.security_outlined, SettingsSection.security),
  _SettingsTabInfo(Icons.tune_outlined, SettingsSection.general),
  _SettingsTabInfo(Icons.smart_toy_outlined, SettingsSection.bots),
];

class _SettingsTabInfo {
  const _SettingsTabInfo(this.icon, this.tab);

  final IconData icon;
  final SettingsSection tab;

  String label(BuildContext context) {
    return switch (tab) {
      SettingsSection.accounts => context.l10n.settingsAccountsTab,
      SettingsSection.instructions => context.l10n.settingsInstructionsTab,
      SettingsSection.workModes => context.l10n.modeEditorTitle,
      SettingsSection.skills => context.l10n.settingsSkillsTab,
      SettingsSection.agents => context.l10n.settingsAgentsTab,
      SettingsSection.mcp => context.l10n.settingsMcpTab,
      SettingsSection.lsp => context.l10n.settingsLspTab,
      SettingsSection.ssh => context.l10n.settingsSshTab,
      SettingsSection.statistics => context.l10n.settingsStatisticsTab,
      SettingsSection.security => context.l10n.settingsSecurityTab,
      SettingsSection.general => context.l10n.settingsGeneralTab,
      SettingsSection.bots => context.l10n.settingsBotsTab,
    };
  }
}

class _SettingsScaffold extends ConsumerWidget {
  const _SettingsScaffold({
    required this.section,
    required this.routeVisible,
    this.accountChild,
  });

  final SettingsSection section;
  final Widget? accountChild;
  final bool routeVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleTab = routeVisible ? section.index : -1;
    final views = [
      _ProvidersSettingsTab(
        routeVisible: routeVisible,
        accountChild: accountChild,
      ),
      const _InstructionsSettingsTab(),
      ModeEditorTab(tabIndex: SettingsSection.workModes.index),
      SkillsTab(tabIndex: SettingsSection.skills.index),
      AgentsTab(tabIndex: SettingsSection.agents.index),
      McpTab(tabIndex: SettingsSection.mcp.index),
      LspTab(tabIndex: SettingsSection.lsp.index),
      const SshTab(),
      StatisticsConnector(
        visible: visibleTab == SettingsSection.statistics.index,
      ),
      const SecurityTab(),
      const _GeneralSettingsTab(),
      BotsTab(tabIndex: SettingsSection.bots.index),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        // 宽窄只切换**同一个 Flex 的方向**：导航、分隔、TabBarView 的槽位与类型都
        // 不变，所以跨越 820 断点时内容子树（及其 State：未保存草稿、滚动、焦点）
        // 不会被重建。此前 compact/wide 各自 new 一份 TabBarView，会销毁
        // AccountsTab 的编辑现场，与“设置页保留输入”的约定相反。
        return Flex(
          direction: compact ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingsNav(compact: compact, section: section),
            _SettingsNavDivider(
              direction: compact ? Axis.vertical : Axis.horizontal,
            ),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final view in views) _RetainedSettingsTab(child: view),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 导航与内容之间的 1px 分隔。
///
/// 保持**同一个 widget 类型与槽位**，只按当前 Flex 轴切换尺寸（横向布局是左侧竖线，
/// 纵向布局是底部横线）。用两种不同 widget 替换同一槽位会连同内容子树一起重建。
class _SettingsNavDivider extends StatelessWidget {
  const _SettingsNavDivider({required this.direction});

  final Axis direction;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.outlineVariant;
    return direction == Axis.vertical
        // 紧凑模式的导航自带底部描边：这里只保留 1px 槽位，不叠加第二条线。
        ? const SizedBox(height: 1)
        : SizedBox(width: 1, child: ColoredBox(color: color));
  }
}

class _SettingsNav extends ConsumerWidget {
  const _SettingsNav({required this.compact, required this.section});

  final bool compact;
  final SettingsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = DefaultTabController.of(context);
    void select(int index) {
      if (index == section.index) return;
      SettingsRoute(section: SettingsSection.values[index]).go(context);
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selected = section.index;
        final navItems = [
          for (var index = 0; index < _settingsTabs.length; index++)
            _SettingsNavItem(
              tab: _settingsTabs[index],
              selected: selected == index,
              compact: compact,
              onTap: () => select(index),
            ),
        ];
        if (compact) {
          return Material(
            color: context.colors.surfaceContainer,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.colors.outlineVariant),
                ),
              ),
              child: SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  children: [
                    _SettingsBackTile(compact: true),
                    const SizedBox(width: 8),
                    ...navItems,
                  ],
                ),
              ),
            ),
          );
        }
        return Material(
          color: context.colors.surfaceContainer,
          child: SizedBox(
            width: StudioLayout.settingsNavigationWidth,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
              children: [
                const _SettingsBackTile(compact: false),
                _SettingsNavGroupLabel(context.l10n.settingsModelsGroup),
                for (final index in [0, 4, 1, 2]) navItems[index],
                _SettingsNavGroupLabel(context.l10n.settingsExtensionsGroup),
                for (final index in [3, 5, 6, 7]) navItems[index],
                _SettingsNavGroupLabel(context.l10n.settingsPreferencesGroup),
                for (final index in [8, 9, 10, 11]) navItems[index],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsBackTile extends ConsumerWidget {
  const _SettingsBackTile({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(
          Icons.arrow_back,
          size: 16,
          color: context.colors.onSurfaceVariant,
        ),
        if (!compact) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.settingsBackToChat,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
    return Tooltip(
      message: context.l10n.settingsBack,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        child: InkWell(
          key: StudioDriverKeys.settingsBack,
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          onTap: () => const StudioRoute().go(context),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 10,
              vertical: compact ? 9 : 8,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _SettingsNavGroupLabel extends StatelessWidget {
  const _SettingsNavGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({
    required this.tab,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _SettingsTabInfo tab;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? context.colors.onPrimaryContainer
        : context.colors.onSurfaceVariant;
    final label = tab.label(context);
    return Padding(
      padding: EdgeInsets.only(right: compact ? 8 : 0, bottom: compact ? 0 : 6),
      child: Material(
        color: selected
            ? context.colors.surfaceContainerHigh
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadii.sm),
        ),
        child: StudioSelectionMarker(
          selected: selected,
          child: InkWell(
            key: StudioDriverKeys.settingsTab(tab.tab.name),
            borderRadius: BorderRadius.circular(StudioRadii.sm),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 10,
                vertical: compact ? 8 : 10,
              ),
              child: Row(
                mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  Icon(tab.icon, size: 18, color: foreground),
                  const SizedBox(width: 10),
                  if (compact)
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelMedium?.copyWith(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keep an already visited settings page alive so changing tabs does not discard
/// editor text, search results or scroll position. Unvisited tabs remain lazy.
class _RetainedSettingsTab extends StatefulWidget {
  const _RetainedSettingsTab({required this.child});
  final Widget child;
  @override
  State<_RetainedSettingsTab> createState() => _RetainedSettingsTabState();
}

class _RetainedSettingsTabState extends State<_RetainedSettingsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
