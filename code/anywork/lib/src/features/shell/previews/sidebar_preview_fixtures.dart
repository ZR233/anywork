import 'package:anywork_client/models.dart';

import '../sidebar/sidebar_views.dart';

final DateTime _previewTime = DateTime.utc(2025, 4, 7, 14, 32);

final List<StudioProject> sidebarPreviewProjects = List.unmodifiable([
  const StudioProject(
    id: 'project-local',
    name: 'pure-lang-pure',
    path: '/work/pure-lang-pure',
  ),
  const StudioProject(
    id: 'project-ssh',
    name: 'studio-lab',
    path: '/srv/studio-lab',
    sshAlias: 'studio-lab',
  ),
  const StudioProject(
    id: 'standalone',
    name: 'Non-project sessions',
    path: '',
    kind: WorkspaceKind.standalone,
  ),
]);

SessionDirectoryRow sidebarPreviewThread({
  required String id,
  required String title,
  required String workspaceId,
  ThreadStatusView status = ThreadStatusView.idle,
  bool archived = false,
  ThreadWorkspaceMode workspaceMode = ThreadWorkspaceMode.local,
}) => SessionDirectoryRow(
  backend: NativeAgentBackendView(
    config: const NativeAgentConfigView(),
    status: status,
  ),
  sessionId: id,
  agentId: id,
  threadId: id,
  workspaceId: workspaceId,
  title: title,
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.automatic,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: _previewTime,

  archived: archived,
  workspaceMode: workspaceMode,
  workspacePath: '/work/pure-lang-pure',
);

final List<SessionDirectoryRow> _localThreads = List.unmodifiable([
  sidebarPreviewThread(
    id: 'thread-active',
    title: '实现侧栏搜索与归档交互',
    workspaceId: 'project-local',
    status: ThreadStatusView.running,
    workspaceMode: ThreadWorkspaceMode.worktree,
  ),
  sidebarPreviewThread(
    id: 'thread-queued',
    title: '验证 Linux 桌面构建入口',
    workspaceId: 'project-local',
    status: ThreadStatusView.queued,
  ),
  sidebarPreviewThread(
    id: 'thread-idle',
    title: '整理项目文档与测试记录',
    workspaceId: 'project-local',
  ),
  sidebarPreviewThread(
    id: 'thread-archived',
    title: '已归档的组件调研',
    workspaceId: 'project-local',
    archived: true,
  ),
]);

final SidebarData sidebarPreviewData = SidebarData(
  projects: sidebarPreviewProjects,
  windows: {
    'project-local': SidebarWindow(
      rows: _localThreads,
      loaded: true,
      hasMore: true,
    ),
    'project-ssh': SidebarWindow(
      rows: [
        sidebarPreviewThread(
          id: 'thread-ssh',
          title: '远端 GTK 环境检查',
          workspaceId: 'project-ssh',
          status: ThreadStatusView.waitingTool,
        ),
      ],
      loaded: true,
    ),
    'standalone': SidebarWindow(
      rows: [
        sidebarPreviewThread(
          id: 'thread-standalone',
          title: '查询济南今日天气',
          workspaceId: 'standalone',
        ),
      ],
      loaded: true,
    ),
  },
  selectedProjectId: 'project-local',
  selectedThreadId: 'thread-active',
  pinnedProjectIds: const {'project-ssh'},
  pinnedThreadIds: const {'thread-queued'},
  hasUpdate: true,
);

const SidebarHostApps sidebarPreviewHostApps = SidebarHostApps(
  vsCode: true,
  zed: true,
  terminal: true,
  terminalUnavailableReason: '预览仅展示本地 UI，不会启动外部程序。',
);

void recordSidebarPreviewIntent(Object? intent) {
  // UI-only observation for the Widget Previewer; no Client or persistence.
  // ignore: avoid_print
  print('Sidebar preview intent: $intent');
}
