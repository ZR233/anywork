import 'dart:ui' show PointerDeviceKind;

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/collection_presentation.dart';
import '../state/sidebar_view_state.dart';
import '../widgets/sidebar_rows.dart';
import '../widgets/workspace_failure_notice.dart';

class SidebarView extends StatefulWidget {
  const SidebarView({
    required this.state, required this.hostApps, required this.onQuery,
    required this.onFilter, required this.onToggleArchived,
    required this.onToggleExpanded, required this.onSelectProject,
    required this.onSelectThread, required this.onNewThread,
    required this.onProjectAction, required this.onThreadAction,
    required this.onLoadMore, required this.onRetry, required this.onAddProject,
    required this.onSettings, required this.projectRecovery,
    required this.threadRecovery, required this.onMoreProjects,
    required this.onRetryProjects, this.selectedRootThreadId,
    this.showUpdateIndicator = false, super.key,
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
  final void Function(ProjectRecord, WorkspaceThreadRecord, SidebarThreadAction) onThreadAction;
  final ValueChanged<String> onLoadMore;
  final ValueChanged<String> onRetry;
  final VoidCallback onAddProject;
  final VoidCallback onSettings;
  final VoidCallback onMoreProjects;
  final VoidCallback onRetryProjects;
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
      _search.value = TextEditingValue(text: widget.state.rawQuery,
        selection: TextSelection.collapsed(offset: widget.state.rawQuery.length));
    }
  }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final value = widget.state;
    final l10n = context.l10n;
    final general = presentReadValue(value.configuration.general);
    final source = presentReadValue(value.projects.sourceStatus);
    final sourceError = switch (source) {
      FailedProductSourceStatus(:final error) || DegradedProductSourceStatus(:final error) => error,
      _ => null,
    };
    final sourceProjects = presentRows(value.projects.projects);
    final projects = [...sourceProjects]..sort((a, b) {
      final pins = general?.pinnedProjectIds ?? const <String>[];
      final order = (pins.contains(b.id) ? 1 : 0) - (pins.contains(a.id) ? 1 : 0);
      return order != 0 ? order : sourceProjects.indexOf(a).compareTo(sourceProjects.indexOf(b));
    });
    return Listener(
      onPointerDown: (event) {
        final touch = event.kind == PointerDeviceKind.touch || event.kind == PointerDeviceKind.stylus;
        if (touch != _touchMode) setState(() => _touchMode = touch);
      },
      onPointerHover: (_) { if (_touchMode) setState(() => _touchMode = false); },
      child: Material(
        key: StudioDriverKeys.sidebar,
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              key: const ValueKey('sidebar-search'), controller: _search,
              enabled: !value.sealed,
              onChanged: widget.onQuery,
              decoration: InputDecoration(
                hintText: l10n.sidebarSearch, prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: value.rawQuery.isEmpty ? null : IconButton(
                  onPressed: () => widget.onQuery(''), icon: const Icon(Icons.close, size: 16)),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 8, runSpacing: 4,
              children: [for (final filter in DirectoryFilter.values) ChoiceChip(
                label: Text(switch (filter) {
                  DirectoryFilter.all => l10n.sidebarAll,
                  DirectoryFilter.running => l10n.sidebarRunning,
                  DirectoryFilter.attention => l10n.sidebarAttention,
                }),
                selected: value.filter == filter, showCheckmark: false,
                onSelected: value.sealed ? null : (_) => widget.onFilter(filter),
              )],
            )),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 16, 8), child: Row(children: [
            Expanded(child: Text(value.archived ? l10n.sidebarArchived : l10n.sidebarProjects,
              style: Theme.of(context).textTheme.labelLarge)),
            TextButton.icon(key: StudioDriverKeys.openProject,
              onPressed: value.sealed ? null : widget.onAddProject,
              icon: const Icon(Icons.add, size: 18), label: Text(l10n.sidebarAddProject)),
          ])),
          if (value.projects.projection.sync.error case final error?) WorkspaceFailureNotice(failure: error),
          if (sourceError != null) WorkspaceSourceFailureNotice(failure: sourceError),
          if (value.projectsReadError case final error?)
            WorkspaceFailureNotice(failure: error, onRetry: widget.onRetryProjects),
          if (value.projectSourceReadError case final error?)
            WorkspaceFailureNotice(failure: error, onRetry: widget.onRetryProjects),
          Expanded(child: ListView(
            key: const ValueKey('sidebar-project-tree'),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              if (projects.isEmpty && value.projects.projects is CurrentCollectionMirror<ProjectRecord> &&
                  presentWindow(value.projects.projects)?.reference.total == 0 &&
                  presentWindow(value.projects.projects)?.complete == true)
                Padding(padding: const EdgeInsets.all(16), child: Text(l10n.sidebarNoResults)),
              for (final row in presentWindow(value.projects.projects)?.rows.values ??
                  const <ReadValue<ProjectRecord, ProductEntityRef>>[])
                if (row case FailedReadValue(:final error))
                  WorkspaceFailureNotice(failure: error, onRetry: widget.onRetryProjects),
              for (final project in projects)
                if (_visibleProject(project)) ...[
                  SidebarProjectRow(
                    project: project,
                    expanded: value.expandedProjectIds.contains(project.id),
                    selected: value.workspace.selection.projectId == project.id,
                    pinned: general?.pinnedProjectIds.contains(project.id) == true,
                    touchMode: _touchMode, recovery: widget.projectRecovery[project.id],
                    onSelect: value.sealed ? null : () => widget.onSelectProject(project.id),
                    onToggleExpanded: () => widget.onToggleExpanded(project.id),
                    onNewThread: value.sealed ? null : () => widget.onNewThread(project.id),
                    onAction: (action) => widget.onProjectAction(project, action),
                  ),
                  if (value.expandedProjectIds.contains(project.id) || _filtered)
                    ..._threadRows(project, general),
                ],
              if (presentWindow(value.projects.projects)?.loading == true)
                const LinearProgressIndicator(minHeight: 2),
              if (presentWindow(value.projects.projects)?.continuation is OffsetCollectionContinuation)
                TextButton(key: const ValueKey('sidebar-more-projects'),
                  onPressed: presentWindow(value.projects.projects)?.loading == true
                      ? null : widget.onMoreProjects,
                  child: Text(l10n.sidebarEarlier)),
            ],
          )),
          const Divider(height: 17),
          ListTile(key: const ValueKey('sidebar-archived'), dense: true,
            selected: value.archived, onTap: widget.onToggleArchived,
            leading: Icon(value.archived ? Icons.folder_open_outlined : Icons.archive_outlined),
            title: Text(value.archived ? l10n.sidebarProjects : l10n.sidebarArchived)),
          ListTile(key: StudioDriverKeys.settingsOpen, dense: true,
            onTap: widget.onSettings, leading: const Icon(Icons.settings_outlined),
            title: Text(l10n.sidebarSettings),
            trailing: widget.showUpdateIndicator ? const Icon(Icons.circle, size: 8,
              key: ValueKey('studio-update-indicator')) : null),
        ])),
      ),
    );
  }

  bool get _filtered => widget.state.normalizedQuery.isNotEmpty ||
      widget.state.filter != DirectoryFilter.all || widget.state.archived;

  bool _visibleProject(ProjectRecord project) {
    if (!_filtered) return true;
    final directory = widget.state.pages[project.id]?.directory;
    if (directory == null || directory.threads is! CurrentCollectionMirror<WorkspaceThreadRecord>) return true;
    final window = presentWindow(directory.threads)!;
    if (!window.complete || directory.projection.header?.hasMore == true ||
        window.error != null || window.loading || presentRows(directory.threads).isNotEmpty) return true;
    return !widget.state.archived && widget.state.filter == DirectoryFilter.all &&
        '${project.name} ${project.path}'.toLowerCase().contains(widget.state.normalizedQuery.toLowerCase());
  }

  List<Widget> _threadRows(ProjectRecord project, GeneralSettings? general) {
    final page = widget.state.pages[project.id];
    final directory = page?.directory;
    final window = directory == null ? null : presentWindow(directory.threads);
    final error = page?.demandError ?? window?.error ?? directory?.projection.sync.error;
    // Query owner already supplies the configured pin prefix and canonical
    // keyset order. In particular archived queries do not gain a UI pin prefix.
    final ordered = directory == null ? <WorkspaceThreadRecord>[] : presentRows(directory.threads);
    return [
      if (error != null) WorkspaceFailureNotice(failure: error, onRetry: () => widget.onRetry(project.id)),
      for (final row in window?.rows.values ?? const <ReadValue<WorkspaceThreadRecord, ProductEntityRef>>[])
        if (row case FailedReadValue(:final error))
          WorkspaceFailureNotice(failure: error, onRetry: () => widget.onRetry(project.id)),
      if (window?.loading == true) const LinearProgressIndicator(minHeight: 2),
      for (final thread in ordered) SidebarThreadRow(
        thread: thread, project: project,
        selected: thread.id == widget.selectedRootThreadId,
        pinned: general?.pinnedThreadIds.contains(thread.id) == true,
        hostApps: widget.hostApps, recovery: widget.threadRecovery[thread.id],
        onSelect: widget.state.sealed ? null : () => widget.onSelectThread(thread.id),
        onAction: (action) => widget.onThreadAction(project, thread, action),
      ),
      if (window?.continuation is CursorCollectionContinuation ||
          directory?.projection.header?.hasMore == true)
        TextButton(key: ValueKey('sidebar-more-${project.id}'),
          onPressed: window?.loading == true ? null : () => widget.onLoadMore(project.id),
          child: Text(context.l10n.sidebarEarlier)),
      if (window?.complete == true && window?.reference.total == 0 &&
          directory?.projection.header?.hasMore != true && ordered.isEmpty && error == null)
        Padding(padding: const EdgeInsets.all(12), child: Text(context.l10n.sidebarEmptyProject)),
    ];
  }
}
