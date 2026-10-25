import 'package:anywork_client/remote.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/add_project_state.dart';
import '../widgets/workspace_failure_notice.dart';
import 'workspace_open_result_view.dart';

/// Location/connection steps only. The directory step is the Settings
/// feature's public picker and is composed by the Smart boundary separately.
class AddProjectDialogView extends StatefulWidget {
  const AddProjectDialogView({
    required this.state,
    required this.onLocation,
    required this.onSearch,
    required this.onSelectServer,
    required this.onEditServer,
    required this.onDeleteServer,
    required this.onContinue,
    required this.onReload,
    required this.onBack,
    required this.onClose,
    required this.onDismissOpenResult,
    super.key,
  });
  final AddProjectState state;
  final ValueChanged<bool> onLocation;
  final ValueChanged<String> onSearch;
  final ValueChanged<SshServerRuntimeEntry> onSelectServer;
  final ValueChanged<SshServerRuntimeEntry?> onEditServer;
  final ValueChanged<SshServerRuntimeEntry> onDeleteServer;
  final VoidCallback onContinue;
  final VoidCallback onReload;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final VoidCallback onDismissOpenResult;

  @override
  State<AddProjectDialogView> createState() => _AddProjectDialogViewState();
}

class _AddProjectDialogViewState extends State<AddProjectDialogView> {
  late final _search = TextEditingController(text: widget.state.rawSearch);

  @override
  void didUpdateWidget(AddProjectDialogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_search.text != widget.state.rawSearch) {
      _search.value = TextEditingValue(
        text: widget.state.rawSearch,
        selection: TextSelection.collapsed(
          offset: widget.state.rawSearch.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final location = state.step == AddProjectStep.location;
    final disabled = state.pending || state.sealed;
    final servers = state.filteredServers;
    return PopScope(
      canPop: !state.pending,
      child: AlertDialog(
        key: const ValueKey('add-project-dialog'),
        scrollable: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                location
                    ? context.l10n.sidebarAddProject
                    : context.l10n.sidebarRemoteProject,
              ),
            ),
            IconButton(
              tooltip: context.l10n.settingsCancel,
              onPressed: state.pending ? null : widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (location) ...[
                _location(
                  context,
                  remote: false,
                  icon: Icons.computer_outlined,
                  title: context.l10n.sidebarLocalProject,
                  subtitle: context.l10n.sidebarLocalHint,
                ),
                const SizedBox(height: 12),
                _location(
                  context,
                  remote: true,
                  icon: Icons.dns_outlined,
                  title: context.l10n.sidebarRemoteProject,
                  subtitle: context.l10n.sidebarRemoteHint,
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('add-project-connection-search'),
                        controller: _search,
                        enabled: !disabled,
                        onChanged: widget.onSearch,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, size: 18),
                          hintText: context.l10n.sidebarSearchConnections,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      key: StudioDriverKeys.addProjectNewConnection,
                      onPressed: disabled
                          ? null
                          : () => widget.onEditServer(null),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(context.l10n.sidebarNewConnection),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (servers != null && servers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.l10n.sidebarNoConnections),
                  )
                else if (servers != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final server in servers) ...[
                            _server(context, server, disabled),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
              if (state.pending && !state.picking)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (state.failure case final error?)
                WorkspaceFailureNotice(failure: error),
              if (state.action?.operation?.evidenceError case final error?)
                WorkspaceFailureNotice(failure: error),
              if (state.action?.observationError case final error?)
                WorkspaceFailureNotice(failure: error),
              if (state.passwordUnavailable)
                Text(context.l10n.settingsSshPasswordAuthUnavailable),
              if (state.connection?.state case FailedSshConnectionState(
                :final code,
                :final message,
              ))
                Text('$message\n$code'),
              if (state.opened case final result?)
                WorkspaceOpenResultView(
                  result: result,
                  onDismiss: widget.onDismissOpenResult,
                ),
              if (!location &&
                  state.connections.servers == null &&
                  !state.pending)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: state.sealed ? null : widget.onReload,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(context.l10n.sidebarRetry),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: state.pending
                ? null
                : location
                ? widget.onClose
                : widget.onBack,
            child: Text(
              location ? context.l10n.settingsCancel : context.l10n.sidebarBack,
            ),
          ),
          FilledButton.icon(
            key:
                !disabled &&
                    (location
                        ? state.remote != null
                        : state.selectedAlias != null)
                ? const ValueKey('add-project-continue-ready')
                : StudioDriverKeys.addProjectContinue,
            onPressed:
                disabled ||
                    (location
                        ? state.remote == null
                        : state.selectedAlias == null)
                ? null
                : widget.onContinue,
            icon: Icon(
              location ? Icons.arrow_forward : Icons.cable_outlined,
              size: 18,
            ),
            label: Text(
              location
                  ? context.l10n.sidebarContinue
                  : context.l10n.sidebarConnect,
            ),
          ),
        ],
      ),
    );
  }

  Widget _location(
    BuildContext context, {
    required bool remote,
    required IconData icon,
    required String title,
    required String subtitle,
  }) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: widget.state.remote == remote
            ? context.colors.primary
            : context.colors.outlineVariant,
      ),
    ),
    child: ListTile(
      key: remote
          ? StudioDriverKeys.addProjectSourceRemote
          : StudioDriverKeys.addProjectSourceLocal,
      selected: widget.state.remote == remote,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: widget.state.pending || widget.state.sealed
          ? null
          : () => widget.onLocation(remote),
    ),
  );

  Widget _server(
    BuildContext context,
    SshServerRuntimeEntry server,
    bool disabled,
  ) {
    final profile = server.profile;
    final selected = widget.state.selectedAlias == profile.alias;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected
              ? context.colors.primary
              : context.colors.outlineVariant,
        ),
      ),
      child: ListTile(
        key: StudioDriverKeys.addProjectConnectionRow(profile.alias),
        selected: selected,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              profile.alias,
              style: context.text.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (server.hasPassword)
              Text(
                context.l10n.settingsSshPasswordBadge,
                style: context.text.labelSmall,
              ),
            if (profile.identityFile?.trim().isNotEmpty == true)
              Text(
                context.l10n.settingsSshKeyBadge(profile.identityFile!),
                style: context.text.labelSmall,
              ),
          ],
        ),
        subtitle: Text(
          '${profile.username}@${profile.hostName}:${profile.port}',
          style: context.text.bodySmall?.copyWith(
            fontFamily: studioCodeFontFamily,
          ),
        ),
        trailing: server.managed
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: StudioDriverKeys.addProjectConnectionEdit(
                      profile.alias,
                    ),
                    tooltip: context.l10n.settingsSshEdit,
                    onPressed: disabled
                        ? null
                        : () => widget.onEditServer(server),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    key: StudioDriverKeys.addProjectConnectionDelete(
                      profile.alias,
                    ),
                    tooltip: context.l10n.settingsSshDelete,
                    onPressed: disabled
                        ? null
                        : () => widget.onDeleteServer(server),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              )
            : null,
        onTap: disabled ? null : () => widget.onSelectServer(server),
      ),
    );
  }
}
