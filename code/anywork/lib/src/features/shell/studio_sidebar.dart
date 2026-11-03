part of 'studio_shell.dart';

final _standalonePreparationStateProvider =
    Provider.autoDispose<({bool isPreparing, String? error})>((ref) {
      final source = ref.read(anyworkClientProvider).directoryCommands.source;
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
  const _Sidebar({super.key, required this.state, this.onNavigate});
  final SidebarView state;
  final VoidCallback? onNavigate;

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

/// Thin shell connector: commands, native capabilities, routing and errors only.
class _SidebarState extends ConsumerState<_Sidebar> {
  late AnyworkClient _client;
  late SidebarDirectoryOwner _directory;
  int _navigation = 0;

  @override
  void initState() {
    super.initState();
    _bindClient(ref.read(anyworkClientProvider));
  }

  void _bindClient(AnyworkClient client) {
    _client = client;
    late final SidebarDirectoryOwner owner;
    owner = SidebarDirectoryOwner(
      observeThreads: client.threadDirectory.observeThreads,
      onChanged: () {
        scheduleMicrotask(() {
          if (mounted && identical(_directory, owner)) setState(() {});
        });
      },
      onCloseError: (failure) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: failure.error,
            stack: failure.stackTrace,
            library: 'anywork sidebar directory',
            context: ErrorDescription(
              'closing ${failure.group.name} directory observation',
            ),
            informationCollector: () => [
              StringProperty('workspaceId', failure.workspaceId),
              DiagnosticsProperty<Object>('query', failure.query),
              DiagnosticsProperty<Object>('window', failure.window),
            ],
          ),
        );
      },
    );
    _directory = owner;
  }

  /// Drawer close/reopen retires completions from the preceding drawer scope.
  void retireNavigation() => _navigation++;

  @override
  void dispose() {
    retireNavigation();
    _directory.dispose();
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

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(anyworkClientProvider);
    final general = ref.watch(shellGeneralProvider);
    if (!identical(client, _client)) {
      final selection = _directory.selection;
      _directory.dispose();
      retireNavigation();
      _bindClient(client);
      _directory.configure(
        widget.state.projects,
        selection,
        pinnedThreadIds: general.pinnedThreadIds,
      );
    }
    final preparation = ref.watch(_standalonePreparationStateProvider);
    final directory = _directory;
    directory.configure(
      widget.state.projects,
      directory.selection,
      pinnedThreadIds: general.pinnedThreadIds,
    );
    final windows = directory.windows;
    final pinnedWindows = directory.pinnedWindows;
    final selectedThreadId = client.selection.state.selectedThreadId;
    final selectedThread = selectedThreadId == null
        ? null
        : ref
              .watch(threadMetadataStoreProvider(selectedThreadId))
              .frame
              ?.thread;
    final selectedRootThreadId = switch (selectedThread) {
      null => null,
      final thread when thread.isRoot => thread.id,
      final thread => thread.rootThreadId,
    };
    final recovery =
        ref.watch(recoveryStoreProvider).value?.values ??
        const <StudioRecoveryIssue>[];
    final threadIssues = <String, StudioRecoveryIssue>{};
    for (final window in [...pinnedWindows.values, ...windows.values]) {
      for (final thread in window.threads) {
        final issue = recoveryIssuesForTarget(
          recovery,
          workspaceId: thread.workspaceId,
          threadId: thread.id,
        ).firstOrNull;
        if (issue != null) threadIssues[thread.id] = issue;
      }
    }
    return StudioSidebar(
      data: SidebarData(
        projects: widget.state.projects,
        windows: windows,
        pinnedWindows: pinnedWindows,
        selectedProjectId: widget.state.selectedProjectId,
        selectedThreadId: selectedRootThreadId,
        pinnedProjectIds: general.pinnedProjectIds.toSet(),
        pinnedThreadIds: general.pinnedThreadIds.toSet(),
        projectRecoveryIssues: widget.state.projectRecoveryIssues,
        threadRecoveryIssues: threadIssues,
        preparing: preparation.isPreparing,
        preparationError: preparation.error,
        hasUpdate: ref.watch(
          studioUpdateControllerProvider.select((state) => state.hasUpdate),
        ),
      ),
      hostApps: SidebarHostApps(
        vsCode: ref.watch(vsCodeAvailabilityProvider).value ?? false,
        zed: ref.watch(zedAvailabilityProvider).value ?? false,
        terminal: ref.watch(terminalAvailabilityProvider).value ?? false,
        vsCodeIcon: ref.watch(hostAppIconProvider(HostAppIcon.vsCode)).value,
        zedIcon: ref.watch(hostAppIconProvider(HostAppIcon.zed)).value,
        terminalIcon: ref
            .watch(hostAppIconProvider(HostAppIcon.terminal))
            .value,
        terminalUnavailableReason: _terminalUnavailableReason(context),
      ),
      onQueryChanged: (selection) => directory.configure(
        widget.state.projects,
        selection,
        pinnedThreadIds: general.pinnedThreadIds,
      ),
      onLoadPage: (id, more) {
        if (more) {
          directory.more(id);
        } else {
          unawaited(directory.refresh(id));
        }
      },
      onFirstPage: directory.first,
      onRetryPinned: (id) => unawaited(directory.refreshPinned(id)),
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
      onSelectThread: (thread) => unawaited(
        _navigate(
          () => client.directoryCommands.selectThread(thread.id),
          () => client.selection.state.selectedThreadId == thread.id,
        ),
      ),
      onProjectAction: (project, action) => unawaited(
        _run(() async {
          switch (action) {
            case SidebarProjectAction.pin:
              await _saveSidebarPreferences(
                ref,
                general: general,
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
      onThreadAction: (project, thread, action) => unawaited(
        _run(() async {
          switch (action) {
            case SidebarThreadAction.pin:
              await _saveSidebarPreferences(
                ref,
                general: general,
                threadId: thread.id,
              );
            case SidebarThreadAction.rename:
              await _renameThreadFromSidebar(context, client, thread);
            case SidebarThreadAction.archive:
              await _archiveThreadFromSidebar(context, client, thread.id);
            case SidebarThreadAction.delete:
              await _deleteThreadFromSidebar(context, client, thread);
            case SidebarThreadAction.copyWorkspace:
              await Clipboard.setData(
                ClipboardData(text: thread.workspacePath),
              );
            case SidebarThreadAction.openVsCode:
              await _openThreadWorkspaceInVsCode(context, ref, project, thread);
            case SidebarThreadAction.openZed:
              await _openThreadWorkspaceInZed(context, ref, project, thread);
            case SidebarThreadAction.openTerminal:
              await _openThreadWorkspaceInTerminal(
                context,
                ref,
                project,
                thread,
              );
            case SidebarThreadAction.retryRecovery:
              await client.directoryCommands.retryRecovery();
            case SidebarThreadAction.restore:
              await client.directoryCommands.restoreThread(thread.id);
            case SidebarThreadAction.originalWorkspace:
              await _showArchivedWorkspace(thread, project);
          }
        }),
      ),
      onSettings: () {
        retireNavigation();
        const SettingsRoute().go(context);
      },
      onClose: widget.onNavigate,
    );
  }

  Future<void> _showArchivedWorkspace(
    StudioThread thread,
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
          Text(thread.title),
          if (project.sshAlias != null) Text(project.sshAlias!),
          const SizedBox(height: 12),
          SelectableText(
            thread.workspacePath.isEmpty
                ? context.l10n.sidebarOriginalWorkspaceUnknown
                : thread.workspacePath,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: StudioDriverKeys.copyThreadWorkspace(thread.id),
          onPressed: thread.workspacePath.isEmpty
              ? null
              : () => Clipboard.setData(
                  ClipboardData(text: thread.workspacePath),
                ),
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
  final threads = [...general.pinnedThreadIds];
  final projects = [...general.pinnedProjectIds];
  if (threadId != null && !threads.remove(threadId)) threads.add(threadId);
  if (workspaceId != null && !projects.remove(workspaceId)) {
    projects.add(workspaceId);
  }
  final commands = ref.read(anyworkClientProvider).settingsCommands;
  // A previous width can still be in flight even when this intent equals the
  // observed snapshot. Let the Client's canonical command lane order both.
  if (width != null) {
    await commands.applySettingsField(GeneralSidebarWidthCommand(width));
  }
  if (threadId != null) {
    await commands.applySettingsField(GeneralPinnedThreadIdsCommand(threads));
  }
  if (workspaceId != null) {
    await commands.applySettingsField(GeneralPinnedProjectIdsCommand(projects));
  }
}
