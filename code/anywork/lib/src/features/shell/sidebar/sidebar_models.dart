import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart';

enum SidebarProjectAction { pin, copyPath, close, retryRecovery }

enum SidebarThreadAction {
  pin,
  rename,
  archive,
  copyWorkspace,
  openVsCode,
  openZed,
  openTerminal,
  retryRecovery,
  restore,
  originalWorkspace,
}

/// UI intent, not a second directory store. StudioSidebar owns these choices.
@immutable
class SidebarQuerySelection {
  SidebarQuerySelection({
    this.search = '',
    this.filter = DirectoryFilter.all,
    this.archived = false,
    Set<String> expandedProjectIds = const {},
  }) : expandedProjectIds = Set.unmodifiable(expandedProjectIds);

  final String search;
  final DirectoryFilter filter;
  final bool archived;
  final Set<String> expandedProjectIds;

  bool get filtered =>
      search.trim().isNotEmpty || filter != DirectoryFilter.all || archived;
}

@immutable
class SidebarWindow {
  SidebarWindow({
    List<StudioThread> threads = const [],
    this.loading = false,
    this.error,
    this.hasMore = false,
    this.hasPrevious = false,
    this.loaded = false,
  }) : threads = List.unmodifiable(threads);

  final List<StudioThread> threads;
  final bool loading;
  final String? error;
  final bool hasMore;
  final bool hasPrevious;
  final bool loaded;
}

/// Bounded presentation values. SDK immutable rows are shared, not mirrored.
@immutable
class SidebarData {
  SidebarData({
    required List<StudioProject> projects,
    Map<String, SidebarWindow> windows = const {},
    Map<String, SidebarWindow> pinnedWindows = const {},
    this.selectedProjectId,
    this.selectedThreadId,
    Set<String> pinnedProjectIds = const {},
    Set<String> pinnedThreadIds = const {},
    Map<String, StudioRecoveryIssue> projectRecoveryIssues = const {},
    Map<String, StudioRecoveryIssue> threadRecoveryIssues = const {},
    this.preparing = false,
    this.preparationError,
    this.hasUpdate = false,
  }) : projects = List.unmodifiable(projects),
       windows = Map.unmodifiable(windows),
       pinnedWindows = Map.unmodifiable(pinnedWindows),
       pinnedProjectIds = Set.unmodifiable(pinnedProjectIds),
       pinnedThreadIds = Set.unmodifiable(pinnedThreadIds),
       projectRecoveryIssues = Map.unmodifiable(projectRecoveryIssues),
       threadRecoveryIssues = Map.unmodifiable(threadRecoveryIssues);

  final List<StudioProject> projects;
  final Map<String, SidebarWindow> windows;
  final Map<String, SidebarWindow> pinnedWindows;
  final String? selectedProjectId;
  final String? selectedThreadId;
  final Set<String> pinnedProjectIds;
  final Set<String> pinnedThreadIds;
  final Map<String, StudioRecoveryIssue> projectRecoveryIssues;
  final Map<String, StudioRecoveryIssue> threadRecoveryIssues;
  final bool preparing;
  final String? preparationError;
  final bool hasUpdate;
}

/// Native probing belongs to the connector. Preview needs no platform channel.
@immutable
class SidebarHostApps {
  const SidebarHostApps({
    this.vsCode = false,
    this.zed = false,
    this.terminal = false,
    this.vsCodeIcon,
    this.zedIcon,
    this.terminalIcon,
    required this.terminalUnavailableReason,
  });

  final bool vsCode;
  final bool zed;
  final bool terminal;
  final Uint8List? vsCodeIcon;
  final Uint8List? zedIcon;
  final Uint8List? terminalIcon;
  final String terminalUnavailableReason;
}
