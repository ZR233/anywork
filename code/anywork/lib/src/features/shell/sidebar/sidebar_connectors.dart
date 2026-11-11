import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../presentation/providers/client_provider.dart';
import '../../../presentation/providers/thread_directory_store.dart';
import '../shell_view.dart';
import 'sidebar_directory_owner.dart';
import 'sidebar_views.dart';

void _refreshObservation(Future<void> refresh, String identity) {
  unawaited(
    refresh.catchError((Object error, StackTrace stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'sidebar observation',
          context: ErrorDescription('refreshing $identity'),
        ),
      );
    }),
  );
}

/// This boundary owns one project's structural demands, never row content.
class SidebarProjectConnector extends ConsumerStatefulWidget {
  const SidebarProjectConnector({
    super.key,
    required this.projectId,
    required this.selection,
    required this.builder,
  });

  final String projectId;
  final SidebarQuerySelection selection;
  final Widget Function(
    StudioProject project,
    SidebarProjectStructure structure,
  )
  builder;

  @override
  ConsumerState<SidebarProjectConnector> createState() =>
      _SidebarProjectConnectorState();
}

class _SidebarProjectConnectorState
    extends ConsumerState<SidebarProjectConnector> {
  AnyworkClient? _client;
  SidebarDirectoryOwner? _owner;

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(anyworkClientProvider);
    if (!identical(client, _client)) {
      _owner?.dispose();
      _client = client;
      _owner = SidebarDirectoryOwner(
        observeThreads: client.threadDirectory.observeThreads,
        onCloseError: (failure) => FlutterError.reportError(
          FlutterErrorDetails(
            exception: failure.error,
            stack: failure.stackTrace,
            library: 'sidebar project structure',
            context: ErrorDescription(
              'releasing ${failure.workspaceId}/${failure.group.name} '
              '${failure.query}/${failure.window}',
            ),
          ),
        ),
      );
    }
    final project = ref.watch(sidebarProjectViewProvider(widget.projectId));
    if (project == null) {
      _owner!.configure(const [], widget.selection);
      return const SizedBox.shrink();
    }
    final owner = _owner!;
    owner.configure(
      [project],
      widget.selection,
      pinnedThreadIds: ref.watch(
        shellGeneralProvider.select((general) => general.pinnedThreadIds),
      ),
    );
    final recoveryIssue = ref.watch(sidebarRecoveryIssueProvider(project.id));
    return ListenableBuilder(
      listenable: owner,
      builder: (context, _) {
        final id = project.id;
        return widget.builder(
          project,
          SidebarProjectStructure(
            window: owner.windows[id] ?? SidebarWindow(),
            pinnedWindow: owner.pinnedWindows[id],
            recoveryIssue: recoveryIssue,
            onLoadPage: () => owner.more(id),
            onRetry: () =>
                _refreshObservation(owner.refresh(id), 'project $id'),
            onFirstPage: () => owner.first(id),
            onRetryPinned: () => _refreshObservation(
              owner.refreshPinned(id),
              'pinned project $id',
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _owner?.dispose();
    super.dispose();
  }
}

/// Stable thread identity is the only source of this row's content.
class SidebarThreadConnector extends ConsumerWidget {
  const SidebarThreadConnector({
    super.key,
    required this.threadId,
    required this.project,
    required this.hostApps,
    required this.onSelect,
    required this.onAction,
    this.touchMode = false,
    this.archived = false,
  });

  final String threadId;
  final StudioProject project;
  final SidebarHostApps hostApps;
  final ValueChanged<SessionDirectoryRow> onSelect;
  final void Function(SessionDirectoryRow row, SidebarThreadAction action)
  onAction;
  final bool touchMode;
  final bool archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sidebarThreadViewProvider(threadId));
    return SidebarThreadContent(
      threadId: threadId,
      row: view.metadata.frame?.row,
      loading: view.metadata.isLoading,
      loaded: view.metadata.frame != null,
      error: view.metadata.error?.toString(),
      onRetry: () => _refreshObservation(
        ref.read(threadMetadataDemandProvider(threadId)).refresh(),
        'thread $threadId',
      ),
      rowBuilder: (row) => SidebarThreadRow(
        row: row,
        project: project,
        selected: view.selected,
        pinned: view.pinned,
        recoveryIssue: view.recoveryIssue,
        hostApps: hostApps,
        touchMode: touchMode,
        archived: archived,
        onSelect: () => onSelect(row),
        onAction: (action) => onAction(row, action),
      ),
    );
  }
}
