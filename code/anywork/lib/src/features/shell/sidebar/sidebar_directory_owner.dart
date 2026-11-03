import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import 'sidebar_models.dart';

typedef SidebarThreadsObserve =
    DirectoryObservation<ThreadDirectoryFrame> Function(
      DirectoryQuery query,
      DirectoryWindow window,
    );

enum SidebarDirectoryGroup { ordinary, pinned }

/// Identity retained when retiring one exact directory demand fails.
final class SidebarDirectoryCloseFailure {
  const SidebarDirectoryCloseFailure({
    required this.workspaceId,
    required this.group,
    required this.query,
    required this.window,
    required this.error,
    required this.stackTrace,
  });

  final String workspaceId;
  final SidebarDirectoryGroup group;
  final DirectoryQuery query;
  final DirectoryWindow window;
  final Object error;
  final StackTrace stackTrace;
}

/// Owns only the directory resources demanded by the mounted sidebar.
///
/// Frames are projected whole. This owner never merges pages, derives query
/// membership, sorts domain rows, or interprets metadata changes.
final class SidebarDirectoryOwner {
  SidebarDirectoryOwner({
    required this.observeThreads,
    required this.onChanged,
    this.onCloseError,
  });

  final SidebarThreadsObserve observeThreads;
  final void Function() onChanged;
  final void Function(SidebarDirectoryCloseFailure failure)? onCloseError;
  final _ordinaryEntries = <String, _SidebarDirectoryEntry>{};
  final _pinnedEntries = <String, _SidebarDirectoryEntry>{};
  SidebarQuerySelection _selection = SidebarQuerySelection();
  bool _disposed = false;

  SidebarQuerySelection get selection => _selection;

  void configure(
    List<StudioProject> projects,
    SidebarQuerySelection selection, {
    Iterable<String> pinnedThreadIds = const [],
  }) {
    if (_disposed) return;
    _selection = selection;
    final pinnedIds = List<String>.of(pinnedThreadIds);
    final projectIds = {for (final project in projects) project.id};
    final visibleIds = {
      for (final project in projects)
        if (project.isStandalone ||
            selection.filtered ||
            selection.expandedProjectIds.contains(project.id))
          project.id,
    };
    var changed = false;
    for (final id in _ordinaryEntries.keys.toList()) {
      if (!projectIds.contains(id) || !visibleIds.contains(id)) {
        _releaseDirectory(
          id,
          SidebarDirectoryGroup.ordinary,
          _ordinaryEntries.remove(id)!,
        );
        changed = true;
      }
    }
    for (final id in _pinnedEntries.keys.toList()) {
      if (pinnedIds.isEmpty ||
          !projectIds.contains(id) ||
          !visibleIds.contains(id)) {
        _releaseDirectory(
          id,
          SidebarDirectoryGroup.pinned,
          _pinnedEntries.remove(id)!,
        );
        changed = true;
      }
    }
    for (final id in visibleIds) {
      final ordinaryQuery = DirectoryQuery.withThreadIds(
        workspaceId: id,
        search: selection.search,
        filter: selection.filter,
        archived: selection.archived,
        excludedThreadIds: pinnedIds,
      );
      final ordinary = _ordinaryEntries[id];
      if (ordinary == null || ordinary.query != ordinaryQuery) {
        _replaceDirectory(
          _ordinaryEntries,
          id,
          SidebarDirectoryGroup.ordinary,
          ordinaryQuery,
          DirectoryWindow(),
        );
        changed = true;
      }
      if (pinnedIds.isEmpty) continue;
      final pinnedQuery = DirectoryQuery.withThreadIds(
        workspaceId: id,
        search: selection.search,
        filter: selection.filter,
        archived: selection.archived,
        threadIds: pinnedIds,
      );
      final pinned = _pinnedEntries[id];
      if (pinned == null || pinned.query != pinnedQuery) {
        _replaceDirectory(
          _pinnedEntries,
          id,
          SidebarDirectoryGroup.pinned,
          pinnedQuery,
          DirectoryWindow(limit: DirectoryQuery.maxIdFilterItems),
        );
        changed = true;
      }
    }
    if (changed) _publish();
  }

  Map<String, SidebarWindow> get windows => {
    for (final entry in _ordinaryEntries.entries)
      entry.key: _window(entry.value),
  };

  Map<String, SidebarWindow> get pinnedWindows => {
    for (final entry in _pinnedEntries.entries)
      entry.key: _window(entry.value, paged: false),
  };

  Future<void> refresh(String workspaceId) async {
    final entry = _ordinaryEntries[workspaceId];
    if (entry != null) await entry.resource.refresh();
  }

  Future<void> refreshPinned(String workspaceId) async {
    final entry = _pinnedEntries[workspaceId];
    if (entry != null) await entry.resource.refresh();
  }

  void more(String workspaceId) {
    final current = _ordinaryEntries[workspaceId];
    if (current == null) return;
    final window = current.window;
    DirectoryWindow? next;
    if (window.limit < DirectoryWindow.maxLimit) {
      final expanded = window.limit + 20;
      next = DirectoryWindow(
        before: window.before,
        limit: expanded > DirectoryWindow.maxLimit
            ? DirectoryWindow.maxLimit
            : expanded,
      );
    } else if (current.resource.state.value.frame?.nextCursor
        case final cursor?) {
      next = DirectoryWindow(before: cursor);
    }
    if (next == null || next == window) return;
    _replaceDirectory(
      _ordinaryEntries,
      workspaceId,
      SidebarDirectoryGroup.ordinary,
      current.query,
      next,
    );
    _publish();
  }

  void first(String workspaceId) {
    final current = _ordinaryEntries[workspaceId];
    if (current == null || current.window.before == null) return;
    _replaceDirectory(
      _ordinaryEntries,
      workspaceId,
      SidebarDirectoryGroup.ordinary,
      current.query,
      DirectoryWindow(),
    );
    _publish();
  }

  SidebarWindow _window(_SidebarDirectoryEntry entry, {bool paged = true}) {
    final state = entry.resource.state.value;
    final frame = state.frame;
    return SidebarWindow(
      rows: frame?.rows ?? const [],
      loading: state.isLoading,
      error: state.error?.toString(),
      hasMore: paged && frame?.nextCursor != null,
      hasPrevious: paged && entry.window.before != null,
      loaded: frame != null,
    );
  }

  void _replaceDirectory(
    Map<String, _SidebarDirectoryEntry> entries,
    String workspaceId,
    SidebarDirectoryGroup group,
    DirectoryQuery query,
    DirectoryWindow window,
  ) {
    final previous = entries.remove(workspaceId);
    if (previous != null) _releaseDirectory(workspaceId, group, previous);
    final resource = observeThreads(query, window);
    final entry = _SidebarDirectoryEntry(
      query: query,
      window: window,
      resource: resource,
    );
    entries[workspaceId] = entry;
    entry.subscription = resource.state.watch((_) {
      if (!_disposed && identical(entries[workspaceId], entry)) _publish();
    });
  }

  void _releaseDirectory(
    String workspaceId,
    SidebarDirectoryGroup group,
    _SidebarDirectoryEntry entry,
  ) {
    entry.subscription?.cancel();
    unawaited(
      entry.resource.release().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        final failure = SidebarDirectoryCloseFailure(
          workspaceId: workspaceId,
          group: group,
          query: entry.query,
          window: entry.window,
          error: error,
          stackTrace: stackTrace,
        );
        final reporter = onCloseError;
        if (reporter != null) {
          reporter(failure);
        } else {
          Zone.current.handleUncaughtError(error, stackTrace);
        }
      }),
    );
  }

  void _publish() {
    if (!_disposed) onChanged();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _ordinaryEntries.entries) {
      _releaseDirectory(entry.key, SidebarDirectoryGroup.ordinary, entry.value);
    }
    for (final entry in _pinnedEntries.entries) {
      _releaseDirectory(entry.key, SidebarDirectoryGroup.pinned, entry.value);
    }
    _ordinaryEntries.clear();
    _pinnedEntries.clear();
  }
}

final class _SidebarDirectoryEntry {
  _SidebarDirectoryEntry({
    required this.query,
    required this.window,
    required this.resource,
  });

  final DirectoryQuery query;
  final DirectoryWindow window;
  final DirectoryObservation<ThreadDirectoryFrame> resource;
  Observation? subscription;
}
