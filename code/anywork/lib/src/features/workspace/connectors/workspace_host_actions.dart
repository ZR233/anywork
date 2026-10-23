import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/studio_l10n.dart';
import '../../../platform/error_log.dart';
import '../../../platform/host_app_icons.dart';
import '../../../platform/terminal_launcher.dart';
import '../../../platform/vscode_launcher.dart';
import '../../../platform/zed_launcher.dart';
import '../widgets/sidebar_rows.dart';
import '../widgets/workspace_failure_notice.dart';
import '../widgets/workspace_host_menu.dart';
import '../view_models/workspace_view_model.dart';

WorkspaceHostApps watchWorkspaceHostApps(WidgetRef ref) {
  ImageProvider? icon(HostAppIcon app) {
    final bytes = ref.watch(hostAppIconProvider(app)).asData?.value;
    return bytes == null ? null : MemoryImage(bytes);
  }
  return WorkspaceHostApps(
    vsCode: ref.watch(vsCodeAvailabilityProvider).asData?.value == true,
    zed: ref.watch(zedAvailabilityProvider).asData?.value == true,
    terminal: ref.watch(terminalAvailabilityProvider).asData?.value == true,
    vsCodeImage: icon(HostAppIcon.vsCode), zedImage: icon(HostAppIcon.zed),
    terminalImage: icon(HostAppIcon.terminal),
  );
}

/// Capture the original target and host callbacks before any SSH lookup. A
/// missing server stays a visible error; never fall back to a local directory.
Future<void> openWorkspaceInHost(BuildContext context, WidgetRef ref,
    ProjectRecord project, WorkspaceThreadRecord thread, WorkspaceHostAction action) async {
  final alias = project.sshAlias;
  final path = thread.workspacePath;
  final l10n = context.l10n;
  final hasRemoteHost = ref.read(workspaceViewModelProvider.notifier).hasRemoteHost;
  final vsCode = ref.read(vsCodeLauncherProvider);
  final zed = ref.read(zedLauncherProvider);
  final terminal = ref.read(terminalLauncherProvider);
  final failureLabel = switch (action) {
    WorkspaceHostAction.vsCode => l10n.sessionVsCodeOpenFailed,
    WorkspaceHostAction.zed => l10n.sessionZedOpenFailed,
    WorkspaceHostAction.terminal => l10n.sessionTerminalOpenFailed,
  };
  try {
    if (alias != null) {
      final exists = await hasRemoteHost(alias);
      if (!context.mounted) return;
      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.sessionOpenServerMissing)));
        return;
      }
    }
    if (!context.mounted) return;
    switch (action) {
      case WorkspaceHostAction.vsCode:
        await vsCode(alias == null ? buildLocalVsCodeFolderUri(path)
            : buildRemoteVsCodeFolderUri(alias: alias, remotePath: path));
      case WorkspaceHostAction.zed:
        await zed(alias == null ? LocalZedWorkspaceTarget(directory: path)
            : RemoteSshZedWorkspaceTarget(alias: alias, remotePath: path));
      case WorkspaceHostAction.terminal:
        await terminal(alias == null ? LocalHostTerminalTarget(directory: path)
            : RemoteSshTerminalTarget(alias: alias, remotePath: path));
    }
  } on StudioFailure catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: WorkspaceFailureNotice(failure: error)));
  } catch (error, stack) {
    recordDartError(error, stack, stage: 'workspace-host-launch');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureLabel)));
  }
}
