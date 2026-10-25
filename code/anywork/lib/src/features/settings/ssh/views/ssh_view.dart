import 'package:anywork_client/remote.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_pane.dart';
import '../state/ssh_view_state.dart';
import '../widgets/ssh_server_row.dart';
import '../widgets/ssh_view_support.dart';

/// Connection-state copy for callers that only have a state value.
String sshPhaseLabel(BuildContext context, SshConnectionState? state) =>
    sshConnectionStateText(context, state);

/// SSH servers page.
///
/// Restores the pre-refactor page chrome: tonal add button in the header, a
/// 16 px gap before the body, one inline failure block, a progress line while
/// the first read is pending, the shared empty message and hairline-separated
/// rows. A manual reload entry exists only while a failure is on screen.
class SshView extends StatelessWidget {
  const SshView({
    required this.state,
    required this.errors,
    required this.rowErrors,
    required this.busyAliases,
    required this.onAdd,
    required this.onReload,
    required this.onTest,
    required this.onReconnect,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onPassword,
    super.key,
  });
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
  Widget build(BuildContext context) {
    final servers = state.source.servers;
    return SettingsPane.scrolling(
      title: context.l10n.settingsSshTitle,
      subtitle: context.l10n.settingsSshSubtitle,
      trailing: FilledButton.tonalIcon(
        key: StudioDriverKeys.sshAddServer,
        onPressed: state.editor == null ? onAdd : null,
        icon: const Icon(Icons.add, size: 18),
        label: Text(context.l10n.settingsSshAdd),
      ),
      children: [
        const SizedBox(height: 16),
        for (final error in errors) ...[
          SettingsInlineError(message: error),
          const SizedBox(height: 12),
        ],
        if (servers == null)
          const LinearProgressIndicator()
        else if (servers.isEmpty)
          SettingsEmptyMessage(
            icon: Icons.dns_outlined,
            title: context.l10n.settingsSshEmpty,
            body: context.l10n.settingsSshManagedByCore,
          )
        else
          for (var index = 0; index < servers.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            SshServerRow(
              entry: servers[index],
              connection:
                  state.source.connections[servers[index].profile.alias]?.state,
              rowAction: state.actions[servers[index].profile.alias],
              busy: busyAliases.contains(servers[index].profile.alias),
              errors: rowErrors[servers[index].profile.alias] ?? const [],
              onTest: () => onTest(servers[index].profile.alias),
              onReconnect: () => onReconnect(servers[index].profile.alias),
              onOpen: () => onOpen(servers[index].profile.alias),
              onEdit: () => onEdit(servers[index].profile.alias),
              onDelete: () => onDelete(servers[index].profile.alias),
              onPassword: () => onPassword(servers[index].profile.alias),
            ),
          ],
      ],
    );
  }
}
