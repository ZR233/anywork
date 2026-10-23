import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_pane.dart';
import '../state/ssh_view_state.dart';

String sshPhaseLabel(BuildContext context, SshConnectionState? state) => state == null ? '—' :
  context.sshConnectionStateLabel(switch (state) {
    DisconnectedSshConnectionState() => 'disconnected',
    ConnectingSshConnectionState() => 'connecting',
    ReadySshConnectionState() => 'ready',
    ReconnectingSshConnectionState() => 'reconnecting',
    FailedSshConnectionState() => 'failed',
  });

class SshView extends StatelessWidget {
  const SshView({required this.state, required this.errors, required this.rowErrors,
    required this.busyAliases, required this.onAdd, required this.onReload,
    required this.onTest, required this.onReconnect, required this.onOpen, required this.onEdit,
    required this.onDelete, required this.onPassword, super.key});
  final SshViewState state;
  final List<String> errors;
  final Map<String, List<String>> rowErrors;
  final Set<String> busyAliases;
  final VoidCallback onAdd;
  final VoidCallback onReload;
  final ValueChanged<String> onTest;
  final ValueChanged<String> onReconnect;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onPassword;

  @override
  Widget build(BuildContext context) => SettingsPane(title: context.l10n.settingsSshTitle,
    subtitle: context.l10n.settingsSshSubtitle,
    trailing: FilledButton.tonalIcon(key: StudioDriverKeys.sshAddServer,
      onPressed: state.editor == null ? onAdd : null, icon: const Icon(Icons.add, size: 18),
      label: Text(context.l10n.settingsSshAdd)),
    toolbar: Align(alignment: Alignment.centerLeft, child: TextButton.icon(
      onPressed: state.reloadAction?.preventsResubmission == true ? null : onReload,
      icon: const Icon(Icons.refresh), label: Text(context.l10n.sidebarRetry))),
    child: ListView(children: [
      if (state.reloadAction?.pending == true) const LinearProgressIndicator(),
      for (final error in errors) _error(context, error),
      if (state.source.servers == null) const Center(child: Text('—'))
      else if (state.source.servers!.isEmpty) Padding(padding: const EdgeInsets.all(24),
        child: Column(children: [Text(context.l10n.settingsSshEmpty), Text(context.l10n.settingsSshManagedByCore)]))
      else for (final entry in state.source.servers!) _row(context, entry),
    ]));

  Widget _row(BuildContext context, SshServerRuntimeEntry entry) {
    final profile = entry.profile;
    final alias = profile.alias;
    final connection = state.source.connections[alias]?.state;
    final action = state.actions[alias];
    final busy = busyAliases.contains(alias);
    final authentication = action?.action.error?.details;
    return Card(child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12, runSpacing: 8, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(alias, style: Theme.of(context).textTheme.titleMedium),
              Text('${profile.username}@${profile.hostName}:${profile.port}'),
            ]),
            Text(sshPhaseLabel(context, connection), key: connection is ReadySshConnectionState ? StudioDriverKeys.sshReady(alias) : null),
          ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (entry.hasPassword) Chip(label: Text(context.l10n.settingsSshPasswordBadge)),
          if (profile.identityFile case final identity?) Chip(label: Text(context.l10n.settingsSshKeyBadge(identity))),
          if (!entry.managed) Chip(label: Text(context.l10n.settingsSshReadOnlyEntry)),
          if (connection case ReadySshConnectionState(:final helperVersion, :final architecture))
            Text('$architecture · ${context.l10n.settingsSshRemoteHelper} $helperVersion'),
          if (connection case ReconnectingSshConnectionState(:final attempt, :final delaySeconds))
            Text('$attempt · ${delaySeconds}s'),
        ]),
        Wrap(spacing: 8, runSpacing: 4, children: [
          TextButton.icon(key: StudioDriverKeys.sshTest(alias), onPressed: busy ? null : () => onTest(alias),
            icon: const Icon(Icons.cable_outlined, size: 17), label: Text(context.l10n.settingsSshTest)),
          TextButton.icon(key: StudioDriverKeys.sshOpen(alias), onPressed: busy ? null : () => onOpen(alias),
            icon: const Icon(Icons.folder_open_outlined, size: 17), label: Text(context.l10n.settingsSshOpenProject)),
          IconButton(key: StudioDriverKeys.sshReconnect(alias), onPressed: busy ? null : () => onReconnect(alias),
            tooltip: '${context.l10n.settingsSshReconnect} — ${context.l10n.settingsSshReconnectHint}', icon: const Icon(Icons.refresh, size: 18)),
          if (entry.managed) ...[
            IconButton(key: StudioDriverKeys.sshEdit(alias), onPressed: busy ? null : () => onEdit(alias),
              tooltip: context.l10n.settingsSshEdit, icon: const Icon(Icons.edit_outlined, size: 18)),
            IconButton(key: StudioDriverKeys.sshDelete(alias), onPressed: busy ? null : () => onDelete(alias),
              tooltip: context.l10n.settingsSshDelete, icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error)),
          ],
          if (authentication is SshAuthenticationFailureDetails && authentication.passwordOffered == null)
            TextButton(onPressed: busy ? null : () => onPassword(alias), child: Text(context.l10n.settingsSshAuthPromptTitle)),
        ]),
        if (action?.action.pending == true) const LinearProgressIndicator(),
        if (authentication is SshAuthenticationFailureDetails && authentication.passwordOffered == false)
          _error(context, context.l10n.settingsSshPasswordAuthUnavailable),
        if (connection case FailedSshConnectionState(:final code, :final message)) _error(context, '$message [$code]'),
        for (final error in rowErrors[alias] ?? <String>[]) _error(context, error),
      ])));
  }
  Widget _error(BuildContext context, String error) => SelectableText(error,
    style: TextStyle(color: Theme.of(context).colorScheme.error));
}
