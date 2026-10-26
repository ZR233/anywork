import 'package:anywork_client/remote.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_form_field.dart';
import '../state/remote_directory_view_state.dart';

/// Remote directory picker.
///
/// Keeps the pre-refactor frame: content width `viewport - 80` capped at 640,
/// path field and Go on one line above 420 px, a 12 px progress gap, the current
/// path row with an explicit 4 px gap, one inline failure that replaces the
/// listing, a `minHeight: 200` scroll viewport (max 42% of the window) and dense
/// rounded entries.
class RemoteDirectoryView extends StatelessWidget {
  const RemoteDirectoryView({
    required this.state,
    required this.server,
    required this.errors,
    required this.openMessages,
    required this.canTryPassword,
    required this.passwordUnavailable,
    required this.canRetryCleanup,
    required this.onPath,
    required this.onGo,
    required this.onName,
    required this.onBrowse,
    required this.onNextPage,
    required this.onRefresh,
    required this.onPassword,
    required this.onRetryCleanup,
    required this.onCancel,
    required this.onOpen,
    super.key,
  });
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
    final width = _contentWidth(context);
    final busy = state.busy;
    return AlertDialog(
      key: StudioDriverKeys.sshDirectoryDialog,
      scrollable: true,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.settingsSshChooseDirectory),
          const SizedBox(height: 4),
          Text(
            '${server.username}@${server.hostName}:${server.port}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontFamily: studioCodeFontFamily,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _pathFieldRow(context, width, busy),
            if (busy && directory != null) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  key: StudioDriverKeys.sshDirectoryUp,
                  tooltip: context.l10n.settingsSshUp,
                  onPressed: busy || directory?.parent == null
                      ? null
                      : () => onBrowse(directory!.parent!),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  key: const ValueKey('ssh-directory-refresh'),
                  tooltip: context.l10n.sidebarRetry,
                  onPressed: busy ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SelectableText(
                    directory?.path ?? '…',
                    key: directory == null
                        ? null
                        : StudioDriverKeys.sshDirectoryCurrent(directory.path),
                    style: context.text.bodyMedium?.copyWith(
                      fontFamily: studioCodeFontFamily,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            _body(context, directory, busy),
            if (directory?.nextCursor != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('ssh-directory-next-page'),
                  onPressed: busy ? null : onNextPage,
                  icon: const Icon(Icons.navigate_next),
                  label: Text(context.l10n.settingsSshNextPage),
                ),
              ),
            if (state.showProjectNameField) ...[
              const SizedBox(height: 16),
              SettingsFormField(
                key: const ValueKey('add-project-name'),
                value: state.nameRaw,
                label: context.l10n.settingsSshProjectName,
                enabled: !busy,
                maxLength: 80,
                onChanged: onName,
                prefixIcon: Icons.workspaces_outlined,
              ),
            ],
            for (final message in openMessages) SelectableText(message),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: state.opening ? null : onCancel,
          child: Text(
            state.showProjectNameField
                ? context.l10n.sidebarBack
                : context.l10n.settingsCancel,
          ),
        ),
        FilledButton.icon(
          key: StudioDriverKeys.sshOpenCurrentDirectory,
          onPressed: state.canOpen ? onOpen : null,
          icon: state.opening
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.folder_open_outlined, size: 17),
          label: Text(
            state.showProjectNameField
                ? context.l10n.sidebarAddProject
                : context.l10n.settingsSshOpenThisDirectory,
          ),
        ),
      ],
    );
  }

  /// Path field and Go stay on one line while the content is wide enough.
  Widget _pathFieldRow(BuildContext context, double width, bool busy) {
    final field = SettingsFormField(
      key: StudioDriverKeys.sshDirectoryPathInput,
      value: state.pathRaw,
      label: context.l10n.settingsSshDirectoryPathLabel,
      hint: context.l10n.settingsSshDirectoryPathHint,
      code: true,
      enabled: !busy,
      onChanged: onPath,
      onSubmitted: (_) => onGo(),
      prefixIcon: Icons.route_outlined,
    );
    final go = FilledButton.tonal(
      key: StudioDriverKeys.sshDirectoryGo,
      onPressed: busy ? null : onGo,
      child: Text(context.l10n.settingsSshGo),
    );
    if (width < 420) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: go),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        go,
      ],
    );
  }

  Widget _body(
    BuildContext context,
    RemoteDirectoryState? directory,
    bool busy,
  ) {
    final failure = _failure(context);
    if (failure != null) {
      return SettingsInlineError(
        key: StudioDriverKeys.sshDirectoryError,
        message: failure,
      );
    }
    if (directory == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (directory.entries.isEmpty) {
      return SettingsEmptyMessage(
        key: StudioDriverKeys.sshDirectoryEmpty,
        icon: Icons.folder_open_outlined,
        title: context.l10n.settingsSshDirectoryEmpty,
        body: context.l10n.settingsSshDirectoryEmptyHint,
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 200,
        maxHeight: _bodyMaxHeight(context),
      ),
      child: SingleChildScrollView(
        key: StudioDriverKeys.sshDirectoryList,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in directory.entries)
              if (entry.isDirectory && !entry.isSymlink)
                ListTile(
                  key: StudioDriverKeys.sshDirectoryEntry(entry.path),
                  dense: true,
                  leading: const Icon(Icons.folder_outlined),
                  title: Tooltip(
                    richMessage: TextSpan(
                      text: entry.path,
                      style: const TextStyle(fontFamily: studioCodeFontFamily),
                    ),
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  onTap: busy ? null : () => onBrowse(entry.path),
                ),
          ],
        ),
      ),
    );
  }

  /// One failure line: transport failures first, then path validation.
  String? _failure(BuildContext context) {
    if (errors.isNotEmpty) return errors.first;
    return switch (state.pathIssue) {
      RemotePathIssue.required => context.l10n.settingsSshPathRequired,
      RemotePathIssue.absolute => context.l10n.settingsSshPathAbsolute,
      null =>
        passwordUnavailable
            ? context.l10n.settingsSshPasswordAuthUnavailable
            : null,
    };
  }

  /// The listing viewport is capped, the dialog itself scrolls.
  double _bodyMaxHeight(BuildContext context) =>
      clampDouble(MediaQuery.sizeOf(context).height * 0.42, 150.0, 340.0);

  /// Content width follows the viewport: narrow windows shrink, wide desktops
  /// keep a bounded column.
  double _contentWidth(BuildContext context) =>
      clampDouble(MediaQuery.sizeOf(context).width - 80.0, 0.0, 640.0);
}
