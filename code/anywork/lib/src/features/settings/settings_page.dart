import 'package:anywork_client/studio_client.dart'
    show DeepSeekWebFetchEnabledCommand, DeepSeekWebSearchEnabledCommand;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/studio_tokens.dart';
import '../../presentation/providers/client_provider.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/studio_badges.dart';
import 'settings_agents_tab.dart';
import 'settings_general_tab.dart';
import 'settings_instructions_tab.dart';
import 'settings_lsp_tab.dart';
import 'settings_mcp_tab.dart';
import 'mode_editor/mode_editor_dialogs.dart';
import 'mode_editor/mode_editor_page.dart';
import 'settings_account_tab.dart';
import 'settings_scope.dart';
import 'settings_security_tab.dart';
import 'settings_skills_tab.dart';
import 'settings_ssh_tab.dart';
import 'settings_statistics_tab.dart';
import 'settings_views.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const _SettingsPageShell();
}

/// Owns the tab controller independently from the reactive settings projection.
/// A model/account save refreshes canonical content without recreating the
/// navigation controller or restarting the whole settings page animation.
class _SettingsPageShell extends StatelessWidget {
  const _SettingsPageShell();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _settingsTabs.length,
      child: const _SettingsPageBody(),
    );
  }
}

class _SettingsPageBody extends ConsumerWidget {
  const _SettingsPageBody();

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
        child: _SettingsTabVisibilitySync(child: const _SettingsScaffold()),
      ),
    );
  }
}

/// 把设置壳的 [DefaultTabController] 当前索引同步到 [settingsVisibleTabProvider]。
///
/// 设置壳保活已访问过的 tab；可见性只决定各数据页的显示观察，不接线 topic lease。
/// account 写入延到微任务，避免在 build/通知阶段直接改 account。
class _SettingsTabVisibilitySync extends ConsumerStatefulWidget {
  const _SettingsTabVisibilitySync({required this.child});

  final Widget child;

  @override
  ConsumerState<_SettingsTabVisibilitySync> createState() =>
      _SettingsTabVisibilitySyncState();
}

class _SettingsTabVisibilitySyncState
    extends ConsumerState<_SettingsTabVisibilitySync> {
  TabController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.of(context);
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_sync);
    _controller = controller;
    controller.addListener(_sync);
    _sync();
  }

  void _sync() {
    final controller = _controller;
    if (controller == null) return;
    final index = controller.index;
    Future<void>.microtask(() {
      if (!mounted) return;
      ref.read(settingsVisibleTabProvider.notifier).select(index);
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Each settings tab subscribes to the smallest projection it can render.
/// The retained settings shell therefore survives catalog/config events and a
/// model click only rebuilds the account tab that displays that catalog.
class _ProvidersSettingsTab extends StatelessWidget {
  const _ProvidersSettingsTab();

  @override
  Widget build(BuildContext context) {
    return AccountsTab(tabIndex: _SettingsTab.accounts.index);
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
  _SettingsTabInfo(Icons.cloud_outlined, _SettingsTab.accounts),
  _SettingsTabInfo(Icons.notes_outlined, _SettingsTab.instructions),
  _SettingsTabInfo(Icons.account_tree_outlined, _SettingsTab.workModes),
  _SettingsTabInfo(Icons.extension_outlined, _SettingsTab.skills),
  _SettingsTabInfo(Icons.groups_outlined, _SettingsTab.agents),
  _SettingsTabInfo(Icons.hub_outlined, _SettingsTab.mcp),
  _SettingsTabInfo(Icons.code_outlined, _SettingsTab.lsp),
  _SettingsTabInfo(Icons.dns_outlined, _SettingsTab.ssh),
  _SettingsTabInfo(Icons.query_stats_outlined, _SettingsTab.statistics),
  _SettingsTabInfo(Icons.security_outlined, _SettingsTab.security),
  _SettingsTabInfo(Icons.tune_outlined, _SettingsTab.general),
];

class _SettingsTabInfo {
  const _SettingsTabInfo(this.icon, this.tab);

  final IconData icon;
  final _SettingsTab tab;

  String label(BuildContext context) {
    return switch (tab) {
      _SettingsTab.accounts => context.l10n.settingsAccountsTab,
      _SettingsTab.instructions => context.l10n.settingsInstructionsTab,
      _SettingsTab.workModes => context.l10n.modeEditorTitle,
      _SettingsTab.skills => context.l10n.settingsSkillsTab,
      _SettingsTab.agents => context.l10n.settingsAgentsTab,
      _SettingsTab.mcp => context.l10n.settingsMcpTab,
      _SettingsTab.lsp => context.l10n.settingsLspTab,
      _SettingsTab.ssh => context.l10n.settingsSshTab,
      _SettingsTab.statistics => context.l10n.settingsStatisticsTab,
      _SettingsTab.security => context.l10n.settingsSecurityTab,
      _SettingsTab.general => context.l10n.settingsGeneralTab,
    };
  }
}

enum _SettingsTab {
  accounts,
  instructions,
  workModes,
  skills,
  agents,
  mcp,
  lsp,
  ssh,
  statistics,
  security,
  general,
}

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold();

  @override
  Widget build(BuildContext context) {
    final views = [
      const _ProvidersSettingsTab(),
      const _InstructionsSettingsTab(),
      ModeEditorTab(tabIndex: _SettingsTab.workModes.index),
      SkillsTab(tabIndex: _SettingsTab.skills.index),
      AgentsTab(tabIndex: _SettingsTab.agents.index),
      McpTab(tabIndex: _SettingsTab.mcp.index),
      LspTab(tabIndex: _SettingsTab.lsp.index),
      const SshTab(),
      StatisticsTab(tabIndex: _SettingsTab.statistics.index),
      const SecurityTab(),
      const _GeneralSettingsTab(),
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
            _SettingsNav(compact: compact),
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
  const _SettingsNav({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = DefaultTabController.of(context);
    Future<void> select(int index) async {
      if (index == controller.index) return;
      if (controller.index == _SettingsTab.workModes.index &&
          !await confirmLeaveModeEditor(context, ref)) {
        return;
      }
      if (!context.mounted) return;
      controller.animateTo(index);
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selected = controller.index;
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
                for (final index in [8, 9, 10]) navItems[index],
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
          onTap: () async {
            if (!await confirmLeaveModeEditor(context, ref)) return;
            if (context.mounted && context.canPop()) context.pop();
          },
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
