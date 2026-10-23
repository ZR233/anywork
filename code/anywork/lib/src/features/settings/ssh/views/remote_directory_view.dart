import 'package:anywork_client/remote.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_typography.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_form_field.dart';
import '../state/remote_directory_view_state.dart';

class RemoteDirectoryView extends StatelessWidget {
  const RemoteDirectoryView({required this.state, required this.server, required this.errors,
    required this.openMessages, required this.canTryPassword, required this.passwordUnavailable,
    required this.canRetryCleanup, required this.onPath, required this.onGo, required this.onName,
    required this.onBrowse, required this.onNextPage, required this.onRefresh,
    required this.onPassword, required this.onRetryCleanup, required this.onCancel, required this.onOpen, super.key});
  final RemoteDirectoryViewState state;
  final SshServerProfile server;
  final List<String> errors;
  final List<String> openMessages;
  final bool canTryPassword;
  final bool passwordUnavailable;
  final bool canRetryCleanup;
  final ValueChanged<String> onPath;
  final ValueChanged<String> onName;
  final VoidCallback onGo;
  final ValueChanged<String> onBrowse;
  final VoidCallback onNextPage;
  final VoidCallback onRefresh;
  final VoidCallback onPassword;
  final VoidCallback onRetryCleanup;
  final VoidCallback onCancel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final directory = state.directory;
    final width = (MediaQuery.sizeOf(context).width - 96).clamp(160.0, 640.0);
    return AlertDialog(key: StudioDriverKeys.sshDirectoryDialog, scrollable: true,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.settingsSshChooseDirectory),
        Text('${server.username}@${server.hostName}:${server.port}', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: studioCodeFontFamily)),
      ]),
      content: SizedBox(width: width, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min, children: [
          SettingsFormField(key: StudioDriverKeys.sshDirectoryPathInput, value: state.pathRaw,
            label: context.l10n.settingsSshDirectoryPathLabel, hint: context.l10n.settingsSshDirectoryPathHint,
            code: true, enabled: !state.busy, onChanged: onPath, onSubmitted: (_) => onGo(),
            error: switch (state.pathIssue) {
              RemotePathIssue.required => context.l10n.settingsSshPathRequired,
              RemotePathIssue.absolute => context.l10n.settingsSshPathAbsolute,
              null => null,
            }),
          Align(alignment: Alignment.centerRight, child: FilledButton.tonal(key: StudioDriverKeys.sshDirectoryGo,
            onPressed: state.busy ? null : onGo, child: Text(context.l10n.settingsSshGo))),
          if (state.busy) const LinearProgressIndicator(),
          Row(children: [
            IconButton(key: StudioDriverKeys.sshDirectoryUp, tooltip: context.l10n.settingsSshUp,
              onPressed: state.busy || directory?.parent == null ? null : () => onBrowse(directory!.parent!),
              icon: const Icon(Icons.arrow_upward)),
            IconButton(key: const ValueKey('ssh-directory-refresh'), tooltip: context.l10n.sidebarRetry,
              onPressed: state.busy ? null : onRefresh, icon: const Icon(Icons.refresh)),
            Expanded(child: SelectableText(directory?.path ?? '…',
              key: directory == null ? null : StudioDriverKeys.sshDirectoryCurrent(directory.path),
              style: const TextStyle(fontFamily: studioCodeFontFamily))),
          ]),
          const Divider(),
          for (var i = 0; i < errors.length; i++) SelectableText(errors[i],
            key: i == 0 ? StudioDriverKeys.sshDirectoryError : null,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (passwordUnavailable) Text(context.l10n.settingsSshPasswordAuthUnavailable),
          if (canTryPassword) Align(alignment: Alignment.centerLeft, child: TextButton(
            onPressed: state.busy ? null : onPassword, child: Text(context.l10n.settingsSshAuthPromptTitle))),
          if (directory == null && !state.busy && errors.isEmpty) const Center(child: Text('—')),
          if (directory != null && directory.entries.isEmpty && !state.browsing && state.error == null)
            Padding(key: StudioDriverKeys.sshDirectoryEmpty, padding: const EdgeInsets.all(24),
              child: Column(children: [Text(context.l10n.settingsSshDirectoryEmpty), Text(context.l10n.settingsSshDirectoryEmptyHint)])),
          if (directory != null) ConstrainedBox(constraints: BoxConstraints(maxHeight: (MediaQuery.sizeOf(context).height * .38).clamp(120.0, 360.0)),
            child: SingleChildScrollView(key: StudioDriverKeys.sshDirectoryList,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final entry in directory.entries) if (entry.isDirectory && !entry.isSymlink)
                  ListTile(key: StudioDriverKeys.sshDirectoryEntry(entry.path), dense: true,
                    leading: const Icon(Icons.folder_outlined), title: Tooltip(message: entry.path,
                      child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    onTap: state.busy ? null : () => onBrowse(entry.path)),
              ]))),
          if (directory?.nextCursor != null) Align(alignment: Alignment.centerRight,
            child: TextButton.icon(key: const ValueKey('ssh-directory-next-page'),
              onPressed: state.busy ? null : onNextPage, icon: const Icon(Icons.navigate_next),
              label: Text(context.l10n.settingsSshNextPage))),
          if (state.showProjectNameField) Padding(padding: const EdgeInsets.only(top: 16),
            child: SettingsFormField(key: const ValueKey('add-project-name'), value: state.nameRaw,
              label: context.l10n.settingsSshProjectName, enabled: !state.busy, maxLength: 80,
              onChanged: onName)),
          for (final message in openMessages) SelectableText(message),
          if (canRetryCleanup) TextButton(onPressed: onRetryCleanup, child: Text(context.l10n.runtimeFatalRetry)),
        ])),
      actions: [
        TextButton(onPressed: state.opening ? null : onCancel, child: Text(context.l10n.settingsCancel)),
        FilledButton.icon(key: StudioDriverKeys.sshOpenCurrentDirectory, onPressed: state.canOpen ? onOpen : null,
          icon: state.opening ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.folder_open_outlined, size: 17), label: Text(state.showProjectNameField
              ? context.l10n.sidebarAddProject : context.l10n.settingsSshOpenThisDirectory)),
      ]);
  }
}
