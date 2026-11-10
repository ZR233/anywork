import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart';

enum SidebarProjectAction { pin, copyPath, close, retryRecovery }

enum SidebarThreadAction {
  pin,
  rename,
  archive,
  delete,
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
    List<String> threadIds = const [],
    this.loading = false,
    this.error,
    this.hasMore = false,
    this.hasPrevious = false,
    this.loaded = false,
  }) : threadIds = List.unmodifiable(threadIds);

  final List<String> threadIds;
  final bool loading;
  final String? error;
  final bool hasMore;
  final bool hasPrevious;
  final bool loaded;
}

/// Shell values only; project structure and thread content have separate slots.
@immutable
class SidebarData {
  SidebarData({
    required List<String> projectIds,
    this.standaloneProjectId,
    this.selectedProjectId,
    this.hasSelectedThread = false,
    Set<String> pinnedProjectIds = const {},
    this.preparing = false,
    this.preparationError,
    this.hasUpdate = false,
  }) : projectIds = List.unmodifiable(projectIds),
       pinnedProjectIds = Set.unmodifiable(pinnedProjectIds);

  final List<String> projectIds;
  final String? standaloneProjectId;
  final String? selectedProjectId;
  final bool hasSelectedThread;
  final Set<String> pinnedProjectIds;
  final bool preparing;
  final String? preparationError;
  final bool hasUpdate;
}

/// One project's independently observed structure and pagination intents.
@immutable
class SidebarProjectStructure {
  const SidebarProjectStructure({
    required this.window,
    this.pinnedWindow,
    this.recoveryIssue,
    required this.onLoadPage,
    required this.onRetry,
    required this.onFirstPage,
    required this.onRetryPinned,
  });

  final SidebarWindow window;
  final SidebarWindow? pinnedWindow;
  final StudioRecoveryIssue? recoveryIssue;
  final VoidCallback onLoadPage;
  final VoidCallback onRetry;
  final VoidCallback onFirstPage;
  final VoidCallback onRetryPinned;
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
