import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../shared/host_app_artwork.dart';
import '../../../shared/studio_badges.dart';
import '../../../shared/studio_driver_keys.dart';
import 'sidebar_models.dart';

part 'sidebar_header.dart';
part 'sidebar_rows.dart';
part 'sidebar_tiles.dart';
part 'sidebar_menus.dart';
part 'sidebar_footer.dart';
part 'sidebar_thread_status.dart';
part 'sidebar_detail_overlay.dart';

/// Production sidebar. Its State is the only owner of local interaction state.
///
/// No Client, provider, router or native plugin is reachable from this library.
class StudioSidebar extends StatefulWidget {
  const StudioSidebar({
    super.key,
    required this.data,
    required this.hostApps,
    required this.onQueryChanged,
    required this.onLoadPage,
    this.onFirstPage,
    this.onRetryPinned,
    required this.onNewSession,
    required this.onAddProject,
    required this.onSelectProject,
    required this.onNewProjectSession,
    required this.onSelectThread,
    required this.onProjectAction,
    required this.onThreadAction,
    required this.onSettings,
    this.onClose,
  });

  final SidebarData data;
  final SidebarHostApps hostApps;
  final ValueChanged<SidebarQuerySelection> onQueryChanged;
  final void Function(String workspaceId, bool more) onLoadPage;
  final ValueChanged<String>? onFirstPage;
  final ValueChanged<String>? onRetryPinned;
  final VoidCallback? onNewSession;
  final VoidCallback? onAddProject;
  final ValueChanged<StudioProject> onSelectProject;
  final ValueChanged<StudioProject> onNewProjectSession;
  final ValueChanged<StudioThread> onSelectThread;
  final void Function(StudioProject project, SidebarProjectAction action)
  onProjectAction;
  final void Function(
    StudioProject project,
    StudioThread thread,
    SidebarThreadAction action,
  )
  onThreadAction;
  final VoidCallback? onSettings;
  final VoidCallback? onClose;

  @override
  State<StudioSidebar> createState() => _StudioSidebarState();
}

class _StudioSidebarState extends State<StudioSidebar> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _projectKeys = <String, GlobalKey>{};
  final _expanded = <String>{};
  DirectoryFilter _filter = DirectoryFilter.all;
  bool _archived = false;
  bool _touchInput = false;
  Timer? _searchDebounce;

  bool get _filtered =>
      _search.text.trim().isNotEmpty ||
      _filter != DirectoryFilter.all ||
      _archived;

  @override
  void initState() {
    super.initState();
    if (widget.data.selectedProjectId case final id?) _expanded.add(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishQuery();
    });
  }

  @override
  void didUpdateWidget(StudioSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.data.selectedProjectId;
    _projectKeys.removeWhere(
      (id, _) => !widget.data.projects.any((project) => project.id == id),
    );
    _expanded.retainAll(widget.data.projects.map((project) => project.id));
    if (oldWidget.data.selectedProjectId != id && id != null) {
      _expanded.add(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.data.selectedProjectId != id) return;
        _publishQuery();
        final target = _projectKeys[id]?.currentContext;
        if (target != null) Scrollable.ensureVisible(target, alignment: .1);
      });
    }
  }

  void _publishQuery() {
    widget.onQueryChanged(
      SidebarQuerySelection(
        search: _search.text,
        filter: _filter,
        archived: _archived,
        expandedProjectIds: _expanded,
      ),
    );
  }

  void _change(VoidCallback update) {
    _searchDebounce?.cancel();
    setState(update);
    _publishQuery();
  }

  void _changeSearch() {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), _publishQuery);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final projects =
        [
          ...data.projects.where((project) {
            if (project.isStandalone) return false;
            final window = data.windows[project.id];
            final pinnedWindow = data.pinnedWindows[project.id];
            final pinsExpected = data.pinnedThreadIds.isNotEmpty;
            if (!_filtered ||
                window?.loaded != true ||
                window?.loading == true ||
                window?.error != null ||
                window!.threads.isNotEmpty ||
                (pinsExpected &&
                    (pinnedWindow?.loaded != true ||
                        pinnedWindow?.loading == true ||
                        pinnedWindow?.error != null ||
                        pinnedWindow!.threads.isNotEmpty))) {
              return true;
            }
            return !_archived &&
                _filter == DirectoryFilter.all &&
                '${project.name} ${project.path}'.toLowerCase().contains(
                  _search.text.trim().toLowerCase(),
                );
          }),
        ]..sort((a, b) {
          final pin =
              (data.pinnedProjectIds.contains(b.id) ? 1 : 0) -
              (data.pinnedProjectIds.contains(a.id) ? 1 : 0);
          return pin != 0
              ? pin
              : data.projects.indexOf(a).compareTo(data.projects.indexOf(b));
        });
    final standalone = data.projects
        .where((project) => project.isStandalone)
        .firstOrNull;
    return Listener(
      onPointerDown: (event) {
        final touch =
            event.kind == PointerDeviceKind.touch ||
            event.kind == PointerDeviceKind.stylus;
        if (touch != _touchInput) setState(() => _touchInput = touch);
      },
      onPointerHover: (_) {
        if (_touchInput) setState(() => _touchInput = false);
      },
      child: Material(
        key: StudioDriverKeys.sidebar,
        color: context.colors.surfaceContainerLow,
        child: SafeArea(
          child: Column(
            children: [
              SidebarHeader(
                searchController: _search,
                filter: _filter,
                touchMode: _touchInput,
                preparing: data.preparing,
                onNewSession: widget.onNewSession,
                onSearchChanged: (_) => _changeSearch(),
                onClearSearch: () => _change(_search.clear),
                onFilterChanged: (filter) => _change(() => _filter = filter),
              ),
              if (data.preparationError case final error?)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    context.l10n.sidebarStandalonePrepareFailed(error),
                    style: TextStyle(color: context.colors.error),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('sidebar-project-tree'),
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SidebarSectionHeading(
                        title: _archived
                            ? context.l10n.sidebarArchived
                            : context.l10n.sidebarProjects,
                        action: TextButton.icon(
                          key: StudioDriverKeys.openProject,
                          onPressed: widget.onAddProject,
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(context.l10n.sidebarAddProject),
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.onSurfaceVariant,
                            minimumSize: Size(0, _touchInput ? 44 : 30),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            visualDensity: VisualDensity.standard,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: context.text.labelMedium,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                StudioRadii.sm,
                              ),
                            ),
                          ),
                        ),
                        trailing: widget.onClose == null
                            ? null
                            : _tileIconButton(
                                key: const ValueKey('sidebar-close'),
                                tooltip: MaterialLocalizations.of(context)
                                    .closeButtonLabel,
                                icon: Icons.close,
                                minTarget: _touchInput ? 44 : 32,
                                onPressed: widget.onClose,
                              ),
                      ),
                      if (projects.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(context.l10n.sidebarNoResults),
                        ),
                      for (final project in projects) ...[
                        KeyedSubtree(
                          key: _projectKeys.putIfAbsent(
                            project.id,
                            GlobalKey.new,
                          ),
                          child: SidebarProjectRow(
                            project: project,
                            selected:
                                data.selectedProjectId == project.id &&
                                data.selectedThreadId == null,
                            expanded:
                                _filtered || _expanded.contains(project.id),
                            pinned: data.pinnedProjectIds.contains(project.id),
                            touchMode: _touchInput,
                            recoveryIssue:
                                data.projectRecoveryIssues[project.id],
                            onToggle: () => _change(() {
                              if (!_expanded.remove(project.id)) {
                                _expanded.add(project.id);
                              }
                            }),
                            onSelect: () => widget.onSelectProject(project),
                            onNewSession: () =>
                                widget.onNewProjectSession(project),
                            onAction: (action) =>
                                widget.onProjectAction(project, action),
                          ),
                        ),
                        if (_filtered || _expanded.contains(project.id))
                          _threads(project),
                        const SizedBox(height: 4),
                      ],
                      const Divider(height: 20),
                      KeyedSubtree(
                        key: StudioDriverKeys.nonProjectSessionsArea,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SidebarSectionHeading(
                              title: context.l10n.sidebarStandaloneSessions,
                              action: _tileIconButton(
                                key: const ValueKey('sidebar-new-standalone'),
                                tooltip:
                                    context.l10n.sidebarNewStandaloneSession,
                                icon: Icons.add,
                                minTarget: _touchInput ? 44 : 32,
                                onPressed: widget.onNewSession,
                              ),
                            ),
                            if (standalone != null)
                              _threads(standalone)
                            else
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  _touchInput ? 66 : 50,
                                  8,
                                  12,
                                  8,
                                ),
                                child: Text(
                                  _filtered
                                      ? context.l10n.sidebarNoResults
                                      : context.l10n.sidebarStandaloneEmpty,
                                  style: context.text.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SidebarFooter(
                archived: _archived,
                hasUpdate: data.hasUpdate,
                touchMode: _touchInput,
                onToggleArchived: () => _change(() => _archived = !_archived),
                onSettings: widget.onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _threads(StudioProject project) {
    final window = widget.data.windows[project.id] ?? SidebarWindow();
    final pinnedWindow = widget.data.pinnedWindows[project.id];
    final pinnedRows = pinnedWindow?.threads ?? const <StudioThread>[];
    final showOrdinaryEmpty =
        pinnedWindow == null ||
        (pinnedWindow.loaded && pinnedWindow.threads.isEmpty);
    // 第一列展开箭头宽度为 28px（触控 44px）：
    // 竖向引导线居中在第一列中心 x = 14px（触控 22px），
    // 会话行卡片从 x = 20px（触控 36px）起，配合 8px 左内边距使
    // 16px 前导状态槽位落在 x = 28..44px（与项目图标对齐），
    // 会话标题落在 x = 50px（与项目标题对齐）。非项目会话同样保持两列对齐。
    final guideLeft = _touchInput ? 22.0 : 14.0;
    final rowIndent = _touchInput ? 14.0 : 6.0;
    return Padding(
      padding: EdgeInsets.only(left: guideLeft),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: project.isStandalone
              ? null
              : Border(left: BorderSide(color: context.colors.outlineVariant)),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: rowIndent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final thread in pinnedRows)
                SidebarThreadRow(
                  key: ValueKey('sidebar-thread-${thread.id}'),
                  thread: thread,
                  project: project,
                  selected: widget.data.selectedThreadId == thread.id,
                  pinned: widget.data.pinnedThreadIds.contains(thread.id),
                  touchMode: _touchInput,
                  archived: _archived,
                  recoveryIssue: widget.data.threadRecoveryIssues[thread.id],
                  hostApps: widget.hostApps,
                  onSelect: () => widget.onSelectThread(thread),
                  onAction: (action) =>
                      widget.onThreadAction(project, thread, action),
                ),
              if (pinnedWindow != null)
                SidebarPageStatus(
                  workspaceId: project.id,
                  window: pinnedWindow,
                  keyPrefix: 'sidebar-pinned',
                  showEmpty: false,
                  onRetry: widget.onRetryPinned == null
                      ? null
                      : () => widget.onRetryPinned!(project.id),
                ),
              for (final thread in window.threads)
                SidebarThreadRow(
                  key: ValueKey('sidebar-thread-${thread.id}'),
                  thread: thread,
                  project: project,
                  selected: widget.data.selectedThreadId == thread.id,
                  pinned: widget.data.pinnedThreadIds.contains(thread.id),
                  touchMode: _touchInput,
                  archived: _archived,
                  recoveryIssue: widget.data.threadRecoveryIssues[thread.id],
                  hostApps: widget.hostApps,
                  onSelect: () => widget.onSelectThread(thread),
                  onAction: (action) =>
                      widget.onThreadAction(project, thread, action),
                ),
              SidebarPageStatus(
                workspaceId: project.id,
                window: window,
                filtered: _filtered,
                standalone: project.isStandalone,
                showEmpty: showOrdinaryEmpty,
                onRetry: () => widget.onLoadPage(project.id, false),
                onMore: () => widget.onLoadPage(project.id, true),
                onFirst: widget.onFirstPage == null
                    ? null
                    : () => widget.onFirstPage!(project.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
