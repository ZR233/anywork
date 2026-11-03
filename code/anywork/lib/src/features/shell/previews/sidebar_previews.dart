import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../app/theme/material3_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../sidebar/sidebar_views.dart';
import 'sidebar_preview_fixtures.dart';

Widget _sidebarPreviewHost(Widget child, {double textScale = 1}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          size: const Size(800, 900),
        ),
        child: child,
      ),
    ),
  ),
);

Widget _wholeSidebar({required double width, double textScale = 1}) =>
    _sidebarPreviewHost(
      SizedBox(
        width: width,
        height: 900,
        child: StudioSidebar(
          data: sidebarPreviewData,
          hostApps: sidebarPreviewHostApps,
          onQueryChanged: recordSidebarPreviewIntent,
          onLoadPage: (workspaceId, more) =>
              recordSidebarPreviewIntent('load $workspaceId more=$more'),
          onNewSession: () => recordSidebarPreviewIntent('new session'),
          onAddProject: () => recordSidebarPreviewIntent('add project'),
          onSelectProject: (project) =>
              recordSidebarPreviewIntent('select project ${project.id}'),
          onNewProjectSession: (project) =>
              recordSidebarPreviewIntent('new session in ${project.id}'),
          onSelectThread: (thread) =>
              recordSidebarPreviewIntent('select thread ${thread.id}'),
          onProjectAction: (project, action) =>
              recordSidebarPreviewIntent('project ${project.id}: $action'),
          onThreadAction: (project, thread, action) =>
              recordSidebarPreviewIntent(
                'thread ${thread.id} in ${project.id}: $action',
              ),
          onSettings: () => recordSidebarPreviewIntent('settings'),
        ),
      ),
      textScale: textScale,
    );

@Preview(
  name: '侧栏 / 默认 · 336px',
  group: 'Shell · Sidebar',
  size: Size(336, 900),
)
Widget sidebarOverviewPreview() => _wholeSidebar(width: 336);

@Preview(
  name: '侧栏 / 紧凑 · 300px',
  group: 'Shell · Sidebar',
  size: Size(300, 900),
)
Widget sidebarCompactPreview() => _wholeSidebar(width: 300);

@Preview(
  name: '侧栏 / 宽松 · 440px',
  group: 'Shell · Sidebar',
  size: Size(440, 900),
)
Widget sidebarWidePreview() => _wholeSidebar(width: 440);

@Preview(name: '侧栏 / 大字号', group: 'Shell · Sidebar', size: Size(336, 900))
Widget sidebarLargeTextPreview() => _wholeSidebar(width: 336, textScale: 1.35);

@Preview(
  name: '页眉 · 搜索与新建',
  group: 'Shell · Sidebar parts',
  size: Size(336, 132),
)
Widget sidebarHeaderPreview() => _sidebarPreviewHost(const _HeaderPreview());

class _HeaderPreview extends StatefulWidget {
  const _HeaderPreview();

  @override
  State<_HeaderPreview> createState() => _HeaderPreviewState();
}

class _HeaderPreviewState extends State<_HeaderPreview> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SidebarHeader(
    searchController: _controller,
    filter: DirectoryFilter.all,
    onSearchChanged: recordSidebarPreviewIntent,
    onClearSearch: _controller.clear,
    onFilterChanged: recordSidebarPreviewIntent,
    onNewSession: () => recordSidebarPreviewIntent('new session'),
  );
}

@Preview(name: '筛选 · 三态', group: 'Shell · Sidebar parts', size: Size(336, 56))
Widget sidebarFiltersPreview() => _sidebarPreviewHost(
  Padding(
    padding: const EdgeInsets.all(12),
    child: SidebarFilters(
      selected: DirectoryFilter.running,
      onChanged: recordSidebarPreviewIntent,
    ),
  ),
);

@Preview(name: '分区标题', group: 'Shell · Sidebar parts', size: Size(336, 56))
Widget sidebarSectionHeadingPreview() => _sidebarPreviewHost(
  Padding(
    padding: const EdgeInsets.all(12),
    child: SidebarSectionHeading(
      title: '项目',
      action: IconButton(
        tooltip: '添加项目',
        onPressed: () => recordSidebarPreviewIntent('add project'),
        icon: const Icon(Icons.add),
      ),
    ),
  ),
);

@Preview(
  name: '项目行 · 展开与远端',
  group: 'Shell · Sidebar parts',
  size: Size(336, 56),
)
Widget sidebarProjectRowPreview() => _sidebarPreviewHost(
  Padding(
    padding: const EdgeInsets.all(8),
    child: SidebarProjectRow(
      project: sidebarPreviewProjects[1],
      selected: true,
      expanded: true,
      pinned: true,
      onToggle: () => recordSidebarPreviewIntent('toggle project'),
      onSelect: () => recordSidebarPreviewIntent('select project'),
      onNewSession: () => recordSidebarPreviewIntent('new project session'),
      onAction: recordSidebarPreviewIntent,
    ),
  ),
);

@Preview(
  name: '会话行 · 工作树与运行状态',
  group: 'Shell · Sidebar parts',
  size: Size(336, 56),
)
Widget sidebarThreadRowPreview() => _sidebarPreviewHost(
  Padding(
    padding: const EdgeInsets.all(8),
    child: SidebarThreadRow(
      thread: sidebarPreviewData.windows['project-local']!.threads.first,
      project: sidebarPreviewProjects.first,
      selected: true,
      pinned: true,
      hostApps: sidebarPreviewHostApps,
      onSelect: () => recordSidebarPreviewIntent('select thread'),
      onAction: recordSidebarPreviewIntent,
    ),
  ),
);

@Preview(
  name: '分页状态 · 可加载更多',
  group: 'Shell · Sidebar parts',
  size: Size(336, 84),
)
Widget sidebarPageStatusPreview() => _sidebarPreviewHost(
  SidebarPageStatus(
    workspaceId: 'project-local',
    window: SidebarWindow(
      threads: sidebarPreviewData.windows['project-local']!.threads,
      hasMore: true,
      loaded: true,
    ),
    onRetry: () => recordSidebarPreviewIntent('retry page'),
    onMore: () => recordSidebarPreviewIntent('load more'),
  ),
);

@Preview(
  name: '底栏 · 归档与设置',
  group: 'Shell · Sidebar parts',
  size: Size(336, 64),
)
Widget sidebarFooterPreview() => _sidebarPreviewHost(
  SidebarFooter(
    archived: false,
    hasUpdate: true,
    onToggleArchived: () => recordSidebarPreviewIntent('toggle archived'),
    onSettings: () => recordSidebarPreviewIntent('settings'),
  ),
);

@Preview(name: '底栏按钮 · 选中', group: 'Shell · Sidebar parts', size: Size(164, 56))
Widget sidebarFooterButtonPreview() => _sidebarPreviewHost(
  Padding(
    padding: const EdgeInsets.all(6),
    child: SidebarFooterButton(
      icon: Icons.archive_outlined,
      tooltip: '已归档',
      selected: true,
      onPressed: () => recordSidebarPreviewIntent('archived'),
    ),
  ),
);

@Preview(name: '项目菜单', group: 'Shell · Sidebar parts', size: Size(48, 48))
Widget sidebarProjectMenuPreview() => _sidebarPreviewHost(
  SidebarProjectMenu(
    menuKey: const ValueKey('sidebar-preview-project-menu'),
    pinned: false,
    onAction: recordSidebarPreviewIntent,
  ),
);

@Preview(name: '会话菜单', group: 'Shell · Sidebar parts', size: Size(48, 48))
Widget sidebarThreadMenuPreview() => _sidebarPreviewHost(
  SidebarThreadMenu(
    thread: sidebarPreviewData.windows['project-local']!.threads.first,
    canRetryRecovery: false,
    blocked: false,
    targetDescription: '/work/pure-lang-pure',
    hostApps: sidebarPreviewHostApps,
    minTarget: 32,
    onAction: recordSidebarPreviewIntent,
  ),
);
