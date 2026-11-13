import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

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
    required this.onQueryChanged,
    required this.projectStructureBuilder,
    required this.threadBuilder,
    required this.onNewSession,
    required this.onAddProject,
    required this.onSelectProject,
    required this.onNewProjectSession,
    required this.onSelectThread,
    required this.onProjectAction,
    required this.onThreadAction,
    required this.onSettings,
    this.onClose,
    this.footerBuilder,
  });

  final SidebarData data;
  final ValueChanged<SidebarQuerySelection> onQueryChanged;
  final Widget Function(
    BuildContext context,
    String projectId,
    SidebarQuerySelection selection,
    Widget Function(StudioProject project, SidebarProjectStructure structure)
    builder,
  )
  projectStructureBuilder;
  final Widget Function(
    BuildContext context,
    StudioProject project,
    String threadId,
    bool touchMode,
    bool archived,
    ValueChanged<SessionDirectoryRow> onSelect,
    void Function(SessionDirectoryRow row, SidebarThreadAction action) onAction,
  )
  threadBuilder;
  final VoidCallback? onNewSession;
  final VoidCallback? onAddProject;
  final ValueChanged<StudioProject> onSelectProject;
  final ValueChanged<StudioProject> onNewProjectSession;
  final ValueChanged<SessionDirectoryRow> onSelectThread;
  final void Function(StudioProject project, SidebarProjectAction action)
  onProjectAction;
  final void Function(
    StudioProject project,
    SessionDirectoryRow row,
    SidebarThreadAction action,
  )
  onThreadAction;
  final VoidCallback? onSettings;
  final VoidCallback? onClose;
  final Widget Function({
    required bool archived,
    required VoidCallback onToggleArchived,
    required VoidCallback? onSettings,
    required bool touchMode,
  })?
  footerBuilder;

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
  String _querySearch = '';

  bool get _filtered =>
      _querySearch.trim().isNotEmpty ||
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
    _projectKeys.removeWhere((id, _) => !widget.data.projectIds.contains(id));
    _expanded.retainAll(widget.data.projectIds);
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
    setState(() {
      update();
      _querySearch = _search.text;
    });
    _publishQuery();
  }

  void _changeSearch() {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _querySearch = _search.text);
      _publishQuery();
    });
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
          for (final id in data.projectIds)
            if (id != data.standaloneProjectId) id,
        ]..sort((a, b) {
          final pin =
              (data.pinnedProjectIds.contains(b) ? 1 : 0) -
              (data.pinnedProjectIds.contains(a) ? 1 : 0);
          return pin != 0
              ? pin
              : data.projectIds
                    .indexOf(a)
                    .compareTo(data.projectIds.indexOf(b));
        });
    final standalone = data.standaloneProjectId;
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
                      for (final projectId in projects)
                        _projectStructure(projectId, (project, structure) {
                          if (!_showProject(project, structure)) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              KeyedSubtree(
                                key: _projectKeys.putIfAbsent(
                                  project.id,
                                  GlobalKey.new,
                                ),
                                child: SidebarProjectRow(
                                  project: project,
                                  selected:
                                      data.selectedProjectId == project.id &&
                                      !data.hasSelectedThread,
                                  expanded:
                                      _filtered ||
                                      _expanded.contains(project.id),
                                  pinned: data.pinnedProjectIds.contains(
                                    project.id,
                                  ),
                                  touchMode: _touchInput,
                                  recoveryIssue: structure.recoveryIssue,
                                  onToggle: () => _change(() {
                                    if (!_expanded.remove(project.id)) {
                                      _expanded.add(project.id);
                                    }
                                  }),
                                  onSelect: () =>
                                      widget.onSelectProject(project),
                                  onNewSession: () =>
                                      widget.onNewProjectSession(project),
                                  onAction: (action) =>
                                      widget.onProjectAction(project, action),
                                ),
                              ),
                              if (_filtered || _expanded.contains(project.id))
                                _threads(project, structure),
                              const SizedBox(height: 4),
                            ],
                          );
                        }),
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
                              _projectStructure(
                                standalone,
                                (project, structure) =>
                                    _threads(project, structure),
                              )
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
              widget.footerBuilder?.call(
                    archived: _archived,
                    onToggleArchived: () =>
                        _change(() => _archived = !_archived),
                    onSettings: widget.onSettings,
                    touchMode: _touchInput,
                  ) ??
                  SidebarFooter(
                    archived: _archived,
                    touchMode: _touchInput,
                    onToggleArchived: () =>
                        _change(() => _archived = !_archived),
                    onSettings: widget.onSettings,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _projectStructure(
    String projectId,
    Widget Function(StudioProject, SidebarProjectStructure) builder,
  ) => widget.projectStructureBuilder(
    context,
    projectId,
    SidebarQuerySelection(
      search: _querySearch,
      filter: _filter,
      archived: _archived,
      expandedProjectIds: _expanded,
    ),
    builder,
  );

  bool _showProject(StudioProject project, SidebarProjectStructure structure) {
    final window = structure.window;
    final pinned = structure.pinnedWindow;
    if (!_filtered ||
        !window.loaded ||
        window.loading ||
        window.error != null ||
        window.threadIds.isNotEmpty ||
        (pinned != null &&
            (!pinned.loaded ||
                pinned.loading ||
                pinned.error != null ||
                pinned.threadIds.isNotEmpty))) {
      return true;
    }
    return !_archived &&
        _filter == DirectoryFilter.all &&
        '${project.name} ${project.path}'.toLowerCase().contains(
          _querySearch.trim().toLowerCase(),
        );
  }

  Widget _threads(StudioProject project, SidebarProjectStructure structure) {
    final window = structure.window;
    final pinnedWindow = structure.pinnedWindow;
    final pinnedIds = pinnedWindow?.threadIds ?? const <String>[];
    final showOrdinaryEmpty =
        pinnedWindow == null ||
        (pinnedWindow.loaded && pinnedWindow.threadIds.isEmpty);
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
              for (final threadId in pinnedIds)
                KeyedSubtree(
                  key: ValueKey('sidebar-thread-$threadId'),
                  child: widget.threadBuilder(
                    context,
                    project,
                    threadId,
                    _touchInput,
                    _archived,
                    widget.onSelectThread,
                    (row, action) =>
                        widget.onThreadAction(project, row, action),
                  ),
                ),
              if (pinnedWindow != null)
                SidebarPageStatus(
                  workspaceId: project.id,
                  window: pinnedWindow,
                  keyPrefix: 'sidebar-pinned',
                  showEmpty: false,
                  onRetry: structure.onRetryPinned,
                ),
              for (final threadId in window.threadIds)
                KeyedSubtree(
                  key: ValueKey('sidebar-thread-$threadId'),
                  child: widget.threadBuilder(
                    context,
                    project,
                    threadId,
                    _touchInput,
                    _archived,
                    widget.onSelectThread,
                    (row, action) =>
                        widget.onThreadAction(project, row, action),
                  ),
                ),
              SidebarPageStatus(
                workspaceId: project.id,
                window: window,
                filtered: _filtered,
                standalone: project.isStandalone,
                showEmpty: showOrdinaryEmpty,
                onRetry: structure.onRetry,
                onMore: structure.onLoadPage,
                onFirst: structure.onFirstPage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
