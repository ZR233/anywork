part of 'studio_shell.dart';

final _standalonePreparationStateProvider =
    Provider.autoDispose<({bool isPreparing, String? error})>((ref) {
      final source = ref.watch(anyworkClientProvider).directoryCommands.source;
      final commandState = observeClient(
        ref,
        source,
        (_) => ref.invalidateSelf(),
      );
      return (
        isPreparing: commandState.standalonePreparationInProgress,
        error: commandState.standalonePreparationError,
      );
    });

class _Sidebar extends ConsumerStatefulWidget {
  const _Sidebar({super.key, this.onNavigate});
  final VoidCallback? onNavigate;

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

/// Thin shell connector: commands, native capabilities, routing and errors only.
class _SidebarState extends ConsumerState<_Sidebar> {
  late AnyworkClient _client;
  int _navigation = 0;

  @override
  void initState() {
    super.initState();
    _bindClient(ref.read(anyworkClientProvider));
  }

  void _bindClient(AnyworkClient client) {
    _client = client;
  }

  /// Drawer close/reopen retires completions from the preceding drawer scope.
  void retireNavigation() => _navigation++;

  @override
  void dispose() {
    retireNavigation();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    final client = _client;
    try {
      await action();
    } catch (error) {
      if (!mounted || !identical(_client, client)) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _navigate(
    Future<void> Function() action,
    bool Function() ownsTarget,
  ) async {
    final client = _client;
    final navigation = ++_navigation;
    final close = widget.onNavigate;
    try {
      await action();
      if (mounted &&
          identical(_client, client) &&
          navigation == _navigation &&
          ownsTarget()) {
        close?.call();
      }
    } catch (error) {
      if (mounted && identical(_client, client) && navigation == _navigation) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _removeThread(
    AnyworkClient client,
    SessionDirectoryRow row, {
    required bool deleting,
    VoidCallback? showActiveSessions,
  }) async {
    final commands = client.threadCommands;
    if (commands.isThreadRemovalPending(row.threadId)) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirmThreadRemoval(
      context,
      row,
      deleting: deleting,
    );
    if (confirmed != true || !mounted || !identical(_client, client)) return;
    if (commands.isThreadRemovalPending(row.threadId)) return;

    final l10n = context.l10n;
    showActiveSessions?.call();
    widget.onNavigate?.call();

    Object? failure;
    try {
      await (deleting
          ? commands.deleteThread(row.threadId)
          : commands.archiveThread(row.threadId));
    } catch (error) {
      failure = error;
    }
    if (!messenger.mounted || !identical(_client, client) || client.isClosed) {
      return;
    }
    final String message;
    if (failure == null) {
      message = deleting
          ? l10n.sidebarDeleteSessionSucceeded(row.title)
          : l10n.sidebarArchiveSessionSucceeded(row.title);
    } else {
      final reason = mounted
          ? context.recoveryIssueFailureLabel(failure)
          : failure.toString();
      message = deleting
          ? l10n.sidebarDeleteSessionResultFailed(row.title, reason)
          : l10n.sidebarArchiveSessionResultFailed(row.title, reason);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        duration: Duration(seconds: failure == null ? 5 : 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(anyworkClientProvider);
    final state = ref.watch(sidebarViewProvider);
    final pinnedProjects = ref.watch(
      shellGeneralProvider.select((general) => general.pinnedProjectIds),
    );
    if (!identical(client, _client)) {
      retireNavigation();
      _bindClient(client);
    }
    final preparation = ref.watch(_standalonePreparationStateProvider);
    final hostApps = SidebarHostApps(
      vsCode: ref.watch(vsCodeAvailabilityProvider).value ?? false,
      zed: ref.watch(zedAvailabilityProvider).value ?? false,
      terminal: ref.watch(terminalAvailabilityProvider).value ?? false,
      vsCodeIcon: ref.watch(hostAppIconProvider(HostAppIcon.vsCode)).value,
      zedIcon: ref.watch(hostAppIconProvider(HostAppIcon.zed)).value,
      terminalIcon: ref.watch(hostAppIconProvider(HostAppIcon.terminal)).value,
      terminalUnavailableReason: _terminalUnavailableReason(context),
    );
    return StudioSidebar(
      data: SidebarData(
        projectIds: state.projectIds,
        standaloneProjectId: state.standaloneProjectId,
        selectedProjectId: state.selectedProjectId,
        hasSelectedThread: ref.watch(
          shellSelectionProvider.select(
            (selection) => selection.selectedThreadId != null,
          ),
        ),
        pinnedProjectIds: pinnedProjects.toSet(),
        preparing: preparation.isPreparing,
        preparationError: preparation.error,
      ),
      onQueryChanged: (_) {},
      projectStructureBuilder: (context, projectId, selection, builder) =>
          SidebarProjectConnector(
            key: ValueKey(('sidebar-project-structure', client, projectId)),
            projectId: projectId,
            selection: selection,
            builder: builder,
          ),
      threadBuilder:
          (
            context,
            project,
            threadId,
            touchMode,
            archived,
            onSelect,
            onAction,
          ) => SidebarThreadConnector(
            threadId: threadId,
            project: project,
            touchMode: touchMode,
            archived: archived,
            hostApps: hostApps,
            onSelect: onSelect,
            onAction: onAction,
          ),
      onNewSession: () => unawaited(
        _navigate(
          client.directoryCommands.beginStandaloneThread,
          () =>
              client.selection.state.selectedThreadId == null &&
              (client.project.state.projects?.values.any(
                    (project) =>
                        project.isStandalone &&
                        project.id == client.selection.state.selectedProjectId,
                  ) ??
                  false),
        ),
      ),
      onAddProject: () {
        retireNavigation();
        unawaited(showAddProjectDialog(context));
      },
      onSelectProject: (project) => unawaited(
        _navigate(
          () => client.directoryCommands.selectProject(project.id),
          () => client.selection.state.selectedProjectId == project.id,
        ),
      ),
      onNewProjectSession: (project) => unawaited(
        _navigate(
          () =>
              client.directoryCommands.beginNewThread(workspaceId: project.id),
          () =>
              client.selection.state.selectedProjectId == project.id &&
              client.selection.state.selectedThreadId == null,
        ),
      ),
      onSelectThread: (row) => unawaited(
        _navigate(
          () => client.directoryCommands.selectThread(row.threadId),
          () => client.selection.state.selectedThreadId == row.threadId,
        ),
      ),
      onProjectAction: (project, action) => unawaited(
        _run(() async {
          switch (action) {
            case SidebarProjectAction.pin:
              await _saveSidebarPreferences(
                ref,
                general: ref.read(shellGeneralProvider),
                workspaceId: project.id,
              );
            case SidebarProjectAction.copyPath:
              await Clipboard.setData(ClipboardData(text: project.path));
            case SidebarProjectAction.close:
              final targetId = project.id;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  key: const ValueKey('archive-project-dialog'),
                  title: Text(context.l10n.sidebarArchiveProjectConfirmTitle),
                  content: Text(
                    context.l10n.sidebarArchiveProjectConfirmBody(project.name),
                  ),
                  actions: [
                    TextButton(
                      key: const ValueKey('archive-project-cancel'),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(context.l10n.settingsCancel),
                    ),
                    FilledButton(
                      key: const ValueKey('archive-project-confirm'),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(
                        context.l10n.sidebarArchiveProjectConfirmAction,
                      ),
                    ),
                  ],
                ),
              );
              if (confirmed == true && mounted && identical(_client, client)) {
                await client.directoryCommands.archiveProject(targetId);
              }
            case SidebarProjectAction.retryRecovery:
              await client.directoryCommands.retryRecovery();
          }
        }),
      ),
      onThreadAction: (project, row, action, showActiveSessions) => unawaited(
        _run(() async {
          switch (action) {
            case SidebarThreadAction.pin:
              await _saveSidebarPreferences(
                ref,
                general: ref.read(shellGeneralProvider),
                threadId: row.threadId,
              );
            case SidebarThreadAction.rename:
              await _renameThreadFromSidebar(context, client, row);
            case SidebarThreadAction.archive:
            case SidebarThreadAction.delete:
              await _removeThread(
                client,
                row,
                deleting: action == SidebarThreadAction.delete,
                showActiveSessions: showActiveSessions,
              );
            case SidebarThreadAction.copyWorkspace:
              await Clipboard.setData(ClipboardData(text: row.workspacePath));
            case SidebarThreadAction.openVsCode:
              await _openThreadWorkspaceInVsCode(context, ref, project, row);
            case SidebarThreadAction.openZed:
              await _openThreadWorkspaceInZed(context, ref, project, row);
            case SidebarThreadAction.openTerminal:
              await _openThreadWorkspaceInTerminal(context, ref, project, row);
            case SidebarThreadAction.retryRecovery:
              await client.directoryCommands.retryRecovery();
            case SidebarThreadAction.restore:
              await client.directoryCommands.restoreThread(row.threadId);
            case SidebarThreadAction.originalWorkspace:
              await _showArchivedWorkspace(row, project);
          }
        }),
      ),
      onSettings: () {
        retireNavigation();
        const SettingsRoute().go(context);
      },
      onClose: widget.onNavigate,
      footerBuilder:
          ({
            required archived,
            required onToggleArchived,
            required onSettings,
            required touchMode,
          }) => SidebarFooterConnector(
            archived: archived,
            onToggleArchived: onToggleArchived,
            onSettings: onSettings,
            touchMode: touchMode,
          ),
    );
  }

  Future<void> _showArchivedWorkspace(
    SessionDirectoryRow row,
    StudioProject project,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(context.l10n.sidebarOriginalWorkspace),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.title),
          if (project.sshAlias != null) Text(project.sshAlias!),
          const SizedBox(height: 12),
          SelectableText(
            row.workspacePath.isEmpty
                ? context.l10n.sidebarOriginalWorkspaceUnknown
                : row.workspacePath,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: StudioDriverKeys.copyThreadWorkspace(row.threadId),
          onPressed: row.workspacePath.isEmpty
              ? null
              : () => Clipboard.setData(ClipboardData(text: row.workspacePath)),
          child: Text(context.l10n.sidebarCopyPath),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    ),
  );
}

Future<void> _saveSidebarPreferences(
  WidgetRef ref, {
  required GeneralSettingsView general,
  int? width,
  String? threadId,
  String? workspaceId,
}) async {
  final commands = ref.read(anyworkClientProvider).settingsCommands;
  // A previous width can still be in flight even when this intent equals the
  // observed snapshot. Let the Client's canonical command lane order both.
  if (width != null) {
    await commands.applySettingsField(GeneralSidebarWidthCommand(width));
  }
  if (threadId != null) {
    await commands.applySettingsField(
      ThreadPinnedCommand(
        threadId,
        !general.pinnedThreadIds.contains(threadId),
      ),
    );
  }
  if (workspaceId != null) {
    await commands.applySettingsField(
      ProjectPinnedCommand(
        workspaceId,
        !general.pinnedProjectIds.contains(workspaceId),
      ),
    );
  }
}
