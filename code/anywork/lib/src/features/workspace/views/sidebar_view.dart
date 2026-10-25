import 'dart:ui' show PointerDeviceKind;

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/collection_presentation.dart';
import '../state/sidebar_view_state.dart';
import '../widgets/sidebar_rows.dart';
import '../widgets/sidebar_tile.dart';
import '../widgets/workspace_failure_notice.dart';

class SidebarView extends StatefulWidget {
  const SidebarView({
    required this.state,
    required this.hostApps,
    required this.onQuery,
    required this.onFilter,
    required this.onToggleArchived,
    required this.onToggleExpanded,
    required this.onSelectProject,
    required this.onSelectThread,
    required this.onNewThread,
    required this.onProjectAction,
    required this.onThreadAction,
    required this.onLoadMore,
    required this.onRetry,
    required this.onAddProject,
    required this.onSettings,
    required this.projectRecovery,
    required this.threadRecovery,
    required this.onMoreProjects,
    required this.onRetryProjects,
    this.onClose,
    this.selectedRootThreadId,
    this.showUpdateIndicator = false,
    super.key,
  });
  final SidebarViewState state;
  final WorkspaceHostApps hostApps;
  final String? selectedRootThreadId;
  final bool showUpdateIndicator;
  final Map<String, RecoveryIssue> projectRecovery;
  final Map<String, RecoveryIssue> threadRecovery;
  final ValueChanged<String> onQuery;
  final ValueChanged<DirectoryFilter> onFilter;
  final VoidCallback onToggleArchived;
  final ValueChanged<String> onToggleExpanded;
  final ValueChanged<String> onSelectProject;
  final ValueChanged<String> onSelectThread;
  final ValueChanged<String> onNewThread;
  final void Function(ProjectRecord, SidebarProjectAction) onProjectAction;
  final void Function(ProjectRecord, WorkspaceThreadRecord, SidebarThreadAction)
  onThreadAction;
  final ValueChanged<String> onLoadMore;
  final ValueChanged<String> onRetry;
  final VoidCallback onAddProject;
  final VoidCallback onSettings;
  final VoidCallback onMoreProjects;
  final VoidCallback onRetryProjects;

  /// 抽屉形态下关闭导航的入口；内嵌侧栏不提供该按钮。
  final VoidCallback? onClose;

  @override
  State<SidebarView> createState() => _SidebarViewState();
}

class _SidebarViewState extends State<SidebarView> {
  late final _search = TextEditingController(text: widget.state.rawQuery);
  bool _touchMode = false;

  @override
  void didUpdateWidget(SidebarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_search.text != widget.state.rawQuery) {
      _search.value = TextEditingValue(
        text: widget.state.rawQuery,
        selection: TextSelection.collapsed(
          offset: widget.state.rawQuery.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.state;
    final l10n = context.l10n;
    final general = presentReadValue(value.configuration.general);
    final source = presentReadValue(value.projects.sourceStatus);
    final sourceError = switch (source) {
      FailedProductSourceStatus(:final error) ||
      DegradedProductSourceStatus(:final error) => error,
      _ => null,
    };
    final sourceProjects = presentRows(value.projects.projects);
    final projects = [...sourceProjects]
      ..sort((a, b) {
        final pins = general?.pinnedProjectIds ?? const <String>[];
        final order =
            (pins.contains(b.id) ? 1 : 0) - (pins.contains(a.id) ? 1 : 0);
        return order != 0
            ? order
            : sourceProjects.indexOf(a).compareTo(sourceProjects.indexOf(b));
      });
    final target = _touchMode ? 44.0 : 32.0;
    return Listener(
      onPointerDown: (event) {
        final touch =
            event.kind == PointerDeviceKind.touch ||
            event.kind == PointerDeviceKind.stylus;
        if (touch != _touchMode) setState(() => _touchMode = touch);
      },
      onPointerHover: (_) {
        if (_touchMode) setState(() => _touchMode = false);
      },
      child: Material(
        key: StudioDriverKeys.sidebar,
        color: context.colors.surfaceContainer,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  key: const ValueKey('sidebar-search'),
                  controller: _search,
                  enabled: !value.sealed,
                  onChanged: widget.onQuery,
                  decoration: InputDecoration(
                    hintText: l10n.sidebarSearch,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: value.rawQuery.isEmpty
                        ? null
                        : sidebarTileIconButton(
                            tooltip: l10n.settingsCancel,
                            icon: Icons.close,
                            iconSize: 16,
                            minTarget: target,
                            onPressed: () => widget.onQuery(''),
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: context.colors.surface,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final filter in DirectoryFilter.values)
                        ChoiceChip(
                          label: Text(switch (filter) {
                            DirectoryFilter.all => l10n.sidebarAll,
                            DirectoryFilter.running => l10n.sidebarRunning,
                            DirectoryFilter.attention => l10n.sidebarAttention,
                          }),
                          selected: value.filter == filter,
                          showCheckmark: false,
                          onSelected: value.sealed
                              ? null
                              : (_) => widget.onFilter(filter),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value.archived
                            ? l10n.sidebarArchived
                            : l10n.sidebarProjects,
                        style: context.text.labelLarge,
                      ),
                    ),
                    TextButton.icon(
                      key: StudioDriverKeys.openProject,
                      onPressed: value.sealed ? null : widget.onAddProject,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.sidebarAddProject),
                    ),
                    if (widget.onClose != null)
                      sidebarTileIconButton(
                        tooltip: l10n.settingsCancel,
                        icon: Icons.close,
                        iconSize: 18,
                        minTarget: target,
                        onPressed: widget.onClose,
                      ),
                  ],
                ),
              ),
              if (value.projects.projection.sync.error case final error?)
                WorkspaceFailureNotice(failure: error),
              if (sourceError != null)
                WorkspaceSourceFailureNotice(failure: sourceError),
              if (value.projectsReadError case final error?)
                WorkspaceFailureNotice(
                  failure: error,
                  onRetry: widget.onRetryProjects,
                ),
              if (value.projectSourceReadError case final error?)
                WorkspaceFailureNotice(
                  failure: error,
                  onRetry: widget.onRetryProjects,
                ),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('sidebar-project-tree'),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (projects.isEmpty &&
                          value.projects.projects
                              is CurrentCollectionMirror<ProjectRecord> &&
                          presentWindow(value.projects.projects)
                                  ?.reference
                                  .total ==
                              0 &&
                          presentWindow(value.projects.projects)?.complete ==
                              true)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(l10n.sidebarNoResults),
                        ),
                      for (final row
                          in presentWindow(value.projects.projects)
                                  ?.rows
                                  .values ??
                              const <
                                ReadValue<ProjectRecord, ProductEntityRef>
                              >[])
                        if (row case FailedReadValue(:final error))
                          WorkspaceFailureNotice(
                            failure: error,
                            onRetry: widget.onRetryProjects,
                          ),
                      for (final project in projects)
                        if (_visibleProject(project)) ...[
                          SidebarProjectRow(
                            project: project,
                            expanded:
                                _filtered ||
                                value.expandedProjectIds.contains(project.id),
                            selected:
                                value.workspace.selection.projectId ==
                                project.id,
                            pinned:
                                general?.pinnedProjectIds.contains(
                                  project.id,
                                ) ==
                                true,
                            touchMode: _touchMode,
                            recovery: widget.projectRecovery[project.id],
                            onSelect: value.sealed
                                ? null
                                : () => widget.onSelectProject(project.id),
                            onToggleExpanded: () =>
                                widget.onToggleExpanded(project.id),
                            onNewThread: value.sealed
                                ? null
                                : () => widget.onNewThread(project.id),
                            onAction: (action) =>
                                widget.onProjectAction(project, action),
                          ),
                          if (_filtered ||
                              value.expandedProjectIds.contains(project.id))
                            ..._threadRows(project, general),
                          const SizedBox(height: 8),
                        ],
                      if (presentWindow(value.projects.projects)?.loading ==
                          true)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(36, 6, 8, 6),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (presentWindow(value.projects.projects)?.continuation
                          is OffsetCollectionContinuation)
                        Padding(
                          padding: const EdgeInsets.only(left: 36, right: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              key: const ValueKey('sidebar-more-projects'),
                              onPressed:
                                  presentWindow(value.projects.projects)
                                          ?.loading ==
                                      true
                                  ? null
                                  : widget.onMoreProjects,
                              child: Text(l10n.sidebarEarlier),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _SidebarActions(
                archived: value.archived,
                showUpdateIndicator: widget.showUpdateIndicator,
                onToggleArchived: widget.onToggleArchived,
                onSettings: widget.onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _filtered =>
      widget.state.normalizedQuery.isNotEmpty ||
      widget.state.filter != DirectoryFilter.all ||
      widget.state.archived;

  bool _visibleProject(ProjectRecord project) {
    if (!_filtered) return true;
    final directory = widget.state.pages[project.id]?.directory;
    if (directory == null ||
        directory.threads is! CurrentCollectionMirror<WorkspaceThreadRecord>) {
      return true;
    }
    final window = presentWindow(directory.threads)!;
    if (!window.complete ||
        directory.projection.header?.hasMore == true ||
        window.error != null ||
        window.loading ||
        presentRows(directory.threads).isNotEmpty) {
      return true;
    }
    return !widget.state.archived &&
        widget.state.filter == DirectoryFilter.all &&
        '${project.name} ${project.path}'.toLowerCase().contains(
          widget.state.normalizedQuery.toLowerCase(),
        );
  }

  List<Widget> _threadRows(ProjectRecord project, GeneralSettings? general) {
    final page = widget.state.pages[project.id];
    final directory = page?.directory;
    final window = directory == null ? null : presentWindow(directory.threads);
    final error =
        page?.demandError ?? window?.error ?? directory?.projection.sync.error;
    // Query owner already supplies the configured pin prefix and canonical
    // keyset order. In particular archived queries do not gain a UI pin prefix.
    final ordered = directory == null
        ? <WorkspaceThreadRecord>[]
        : presentRows(directory.threads);
    final loading = window?.loading == true;
    return [
      if (error != null)
        WorkspaceFailureNotice(
          failure: error,
          onRetry: () => widget.onRetry(project.id),
        ),
      for (final row
          in window?.rows.values ??
              const <ReadValue<WorkspaceThreadRecord, ProductEntityRef>>[])
        if (row case FailedReadValue(:final error))
          WorkspaceFailureNotice(
            failure: error,
            onRetry: () => widget.onRetry(project.id),
          ),
      for (final thread in ordered)
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: context.colors.outlineVariant),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: widget.state.archived
                  ? SidebarArchivedThreadRow(
                      thread: thread,
                      touchMode: _touchMode,
                      recovery: widget.threadRecovery[thread.id],
                      onRestore: widget.state.sealed
                          ? null
                          : () => widget.onThreadAction(
                              project,
                              thread,
                              SidebarThreadAction.restore,
                            ),
                    )
                  : SidebarThreadRow(
                      thread: thread,
                      project: project,
                      selected: thread.id == widget.selectedRootThreadId,
                      pinned:
                          general?.pinnedThreadIds.contains(thread.id) == true,
                      hostApps: widget.hostApps,
                      recovery: widget.threadRecovery[thread.id],
                      touchMode: _touchMode,
                      onSelect: widget.state.sealed
                          ? null
                          : () => widget.onSelectThread(thread.id),
                      onAction: (action) =>
                          widget.onThreadAction(project, thread, action),
                    ),
            ),
          ),
        ),
      if (loading)
        const Padding(
          padding: EdgeInsets.fromLTRB(36, 6, 8, 6),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (ordered.isEmpty && !loading && error == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(36, 8, 12, 12),
          child: Text(
            _filtered
                ? context.l10n.sidebarNoResults
                : context.l10n.sidebarEmptyProject,
            style: context.text.bodySmall,
          ),
        ),
      if (window?.continuation is CursorCollectionContinuation ||
          directory?.projection.header?.hasMore == true)
        Padding(
          padding: const EdgeInsets.only(left: 36, right: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey('sidebar-more-${project.id}'),
              onPressed: loading ? null : () => widget.onLoadMore(project.id),
              child: Text(context.l10n.sidebarEarlier),
            ),
          ),
        ),
    ];
  }
}

/// 侧栏底部导航动作：归档视图切换与设置入口。与既有侧栏一致使用
/// 44px 最小高度的整行文字按钮，选中态使用 surfaceContainerHigh 底色。
class _SidebarActions extends StatelessWidget {
  const _SidebarActions({
    required this.archived,
    required this.showUpdateIndicator,
    required this.onToggleArchived,
    required this.onSettings,
  });
  final bool archived;
  final bool showUpdateIndicator;
  final VoidCallback onToggleArchived;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Divider(height: 17),
          ),
          _SidebarActionButton(
            key: const ValueKey('sidebar-archived'),
            tooltip: archived ? l10n.sidebarProjects : l10n.sidebarArchived,
            icon: archived
                ? Icons.folder_open_outlined
                : Icons.archive_outlined,
            selected: archived,
            onPressed: onToggleArchived,
          ),
          const SizedBox(height: 4),
          _SidebarActionButton(
            key: StudioDriverKeys.settingsOpen,
            tooltip: l10n.sidebarSettings,
            icon: Icons.settings_outlined,
            showIndicator: showUpdateIndicator,
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  const _SidebarActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showIndicator = false,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool showIndicator;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 18),
        if (showIndicator)
          Positioned(
            key: const ValueKey('studio-update-indicator'),
            right: -3,
            top: -3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.statusColors.activeIndicator,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 1.5),
              ),
              child: const SizedBox.square(dimension: 8),
            ),
          ),
      ],
    );
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: selected
              ? colors.onSurface
              : colors.onSurfaceVariant,
          backgroundColor: selected ? colors.surfaceContainerHigh : null,
          minimumSize: const Size(0, 44),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          textStyle: context.text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(StudioRadii.sm),
          ),
        ),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 10),
            Expanded(child: Text(tooltip)),
          ],
        ),
      ),
    );
  }
}
