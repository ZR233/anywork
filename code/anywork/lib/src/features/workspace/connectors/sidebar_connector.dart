import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/overlays/confirmation_view.dart';
import '../state/collection_presentation.dart';
import '../state/workspace_view_state.dart';
import '../view_models/sidebar_view_model.dart';
import '../view_models/workspace_diagnostics_view_model.dart';
import '../view_models/workspace_view_model.dart';
import '../views/sidebar_view.dart';
import '../widgets/sidebar_rows.dart';
import '../widgets/workspace_failure_notice.dart';
import '../widgets/workspace_host_menu.dart';
import 'workspace_host_actions.dart';
import 'workspace_name_dialog.dart';

/// Smart boundary: native dialogs/clipboard/host launchers stay here; business
/// intents go to VMs. No native or domain handle reaches a View.
class SidebarConnector extends ConsumerWidget {
  const SidebarConnector({required this.onAddProject, this.onNavigate, super.key});
  final VoidCallback onAddProject;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sidebar = ref.watch(sidebarViewModelProvider);
    final workspace = ref.watch(workspaceViewModelProvider).asData?.value;
    final diagnostics = ref.watch(workspaceDiagnosticsViewModelProvider).asData?.value;
    final vm = ref.read(sidebarViewModelProvider.notifier);
    final workspaceVM = ref.read(workspaceViewModelProvider.notifier);
    final apps = watchWorkspaceHostApps(ref);
    void navigated() {
      if (!context.mounted) return;
      final scaffold = Scaffold.maybeOf(context);
      if (scaffold?.isDrawerOpen == true) scaffold!.closeDrawer();
      onNavigate?.call();
    }
    final selected = presentReadValue(workspace?.selectedMetadata?.value);
    final issues = diagnostics == null ? const [] : presentRows(diagnostics.recovery.issues);
    return sidebar.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return WorkspaceFailureNotice(failure: error,
          onRetry: () => ref.invalidate(sidebarViewModelProvider));
      },
      data: (value) => Column(children: [
        for (final action in workspace?.actions.values ?? const <WorkspaceActionPresentation>[])
          if (action.admissionError ?? action.operation?.error case final error?)
            WorkspaceFailureNotice(failure: error),
        for (final action in workspace?.actions.values ?? const <WorkspaceActionPresentation>[])
          if (action.operation?.evidenceError case final error?)
            WorkspaceFailureNotice(failure: error),
        for (final action in workspace?.actions.values ?? const <WorkspaceActionPresentation>[])
          if (action.observationError case final error?) WorkspaceFailureNotice(failure: error),
        for (final write in value.writes.values)
          if (write.admissionError ?? write.operation?.error case final error?)
            WorkspaceFailureNotice(failure: error),
        for (final write in value.writes.values)
          if (write.operation?.evidenceError case final error?)
            WorkspaceFailureNotice(failure: error),
        for (final write in value.writes.values)
          if (write.observationError case final error?) WorkspaceFailureNotice(failure: error),
        Expanded(child: SidebarView(
          state: value, hostApps: apps, selectedRootThreadId: selected?.rootThreadId,
          showUpdateIndicator: value.hasUpdate,
          projectRecovery: {for (final issue in issues)
            if (issue.projectId != null && issue.threadId == null) issue.projectId!: issue},
          threadRecovery: {for (final issue in issues)
            if (issue.threadId != null) issue.threadId!: issue},
          onQuery: vm.changeQuery, onFilter: vm.changeFilter,
          onToggleArchived: vm.toggleArchived, onToggleExpanded: vm.toggleExpanded,
          onSelectProject: (id) => unawaited(workspaceVM.selectProject(id).then((_) => navigated())),
          onSelectThread: (id) => unawaited(workspaceVM.selectThread(id).then((_) => navigated())),
          onNewThread: (id) => unawaited(workspaceVM.beginNewThread(id).then((_) => navigated())),
          onLoadMore: (id) => unawaited(vm.loadMore(id)),
          onRetry: (id) => unawaited(vm.retry(id)),
          onAddProject: onAddProject,
          onMoreProjects: () => unawaited(vm.loadProjectsPage()),
          onRetryProjects: () => unawaited(vm.loadProjectsPage()),
          onSettings: () => workspaceVM.navigate(WorkspaceNavigationDestination.settings),
          onProjectAction: (project, action) => unawaited(_projectAction(context, ref, project, action)),
          onThreadAction: (project, thread, action) => unawaited(_threadAction(context, ref, project, thread, action)),
        )),
      ]),
    );
  }

  Future<void> _projectAction(BuildContext context, WidgetRef ref,
      ProjectRecord project, SidebarProjectAction action) async {
    final workspace = ref.read(workspaceViewModelProvider.notifier);
    switch (action) {
      case SidebarProjectAction.pin:
        await ref.read(sidebarViewModelProvider.notifier).toggleProjectPin(project.id);
      case SidebarProjectAction.copyPath:
        await Clipboard.setData(ClipboardData(text: project.path));
      case SidebarProjectAction.archive:
        final confirmed = await _confirmArchive(context, project: true);
        if (confirmed == true) await workspace.archiveProject(project.id);
    }
  }

  Future<void> _threadAction(BuildContext context, WidgetRef ref, ProjectRecord project,
      WorkspaceThreadRecord thread, SidebarThreadAction action) async {
    final workspace = ref.read(workspaceViewModelProvider.notifier);
    switch (action) {
      case SidebarThreadAction.pin:
        await ref.read(sidebarViewModelProvider.notifier).toggleThreadPin(thread.id);
      case SidebarThreadAction.rename:
        final serial = workspace.editThreadName(thread);
        await showDialog<void>(context: context, builder: (_) => WorkspaceNameDialog(serial: serial));
        // Barrier/Escape is an explicit editing end, not a save operation.
        workspace.cancelNameEditor(serial);
      case SidebarThreadAction.archive:
        final confirmed = await _confirmArchive(context);
        if (confirmed == true) await workspace.archiveThread(thread.id);
      case SidebarThreadAction.restore:
        await workspace.restoreThread(thread.id);
      case SidebarThreadAction.retryRecovery:
        await ref.read(workspaceDiagnosticsViewModelProvider.notifier).retryRecovery();
      case SidebarThreadAction.copyPath:
        await Clipboard.setData(ClipboardData(text: thread.workspacePath));
      case SidebarThreadAction.vsCode || SidebarThreadAction.zed || SidebarThreadAction.terminal:
        await openWorkspaceInHost(context, ref, project, thread, switch (action) {
          SidebarThreadAction.vsCode => WorkspaceHostAction.vsCode,
          SidebarThreadAction.zed => WorkspaceHostAction.zed,
          _ => WorkspaceHostAction.terminal,
        });
    }
  }

  Future<bool?> _confirmArchive(BuildContext context, {bool project = false}) => showDialog<bool>(
    context: context,
    builder: (context) => ConfirmationView(
      title: project ? context.l10n.sidebarCloseProject : context.l10n.sidebarArchiveSessionConfirmTitle,
      body: context.l10n.sidebarArchiveSessionConfirmBody,
      confirmLabel: context.l10n.sidebarArchiveSessionConfirmAction,
      cancelLabel: context.l10n.settingsCancel, destructive: true,
      confirmKey: StudioDriverKeys.archiveThreadConfirm,
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
    ),
  );
}
