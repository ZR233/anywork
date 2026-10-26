import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/ssh_view_state.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_readouts.dart';
import 'ssh_view_support.dart';

/// One SSH server entry.
///
/// Geometry is the pre-refactor resource row: 18 px vertical padding, a 20 px
/// identity icon with a 12 px gap, `titleSmall`/w600 alias over a `bodySmall`
/// target line, controls that move under the identity below 650 px, a 12 px gap
/// to the meta wrap and an 8 px gap to the single inline failure.
class SshServerRow extends StatelessWidget {
  const SshServerRow({
    required this.entry,
    required this.connection,
    required this.rowAction,
    required this.busy,
    required this.errors,
    required this.onTest,
    required this.onReconnect,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onPassword,
    super.key,
  });

  final SshServerRuntimeEntry entry;
  final SshConnectionState? connection;
  final SshRowAction? rowAction;
  final bool busy;
  final List<String> errors;
  final VoidCallback onTest;
  final VoidCallback onReconnect;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPassword;

  @override
  Widget build(BuildContext context) {
    final profile = entry.profile;
    final alias = profile.alias;
    final ready = connection is ReadySshConnectionState;
    final identityFile = profile.identityFile;
    final hasIdentity = identityFile != null && identityFile.trim().isNotEmpty;
    final target = '${profile.username}@${profile.hostName}:${profile.port}';
    final authentication = rowAction?.action.error?.details;
    final failure = switch (connection) {
      FailedSshConnectionState(:final code, :final message) =>
        '$message [$code]',
      _ => null,
    };
    final errorMessage = errors.isNotEmpty
        ? errors.first
        : authentication is SshAuthenticationFailureDetails &&
              authentication.passwordOffered == false
        ? context.l10n.settingsSshPasswordAuthUnavailable
        : failure;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 650;
              final identityBlock = Row(
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 20,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alias,
                          style: context.text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          target,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final controls = Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: wide ? WrapAlignment.end : WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ConnectionChip(
                    key: ready ? StudioDriverKeys.sshReady(alias) : null,
                    connection: connection,
                  ),
                  TextButton.icon(
                    key: StudioDriverKeys.sshTest(alias),
                    onPressed: busy ? null : onTest,
                    icon: rowAction?.kind == SshRowOperation.test
                        ? const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cable_outlined, size: 17),
                    label: Text(context.l10n.settingsSshTest),
                  ),
                  TextButton.icon(
                    key: StudioDriverKeys.sshOpen(alias),
                    onPressed: busy ? null : onOpen,
                    icon: const Icon(Icons.folder_open_outlined, size: 17),
                    label: Text(context.l10n.settingsSshOpenProject),
                  ),
                  IconButton(
                    key: StudioDriverKeys.sshReconnect(alias),
                    tooltip:
                        '${context.l10n.settingsSshReconnect} — ${context.l10n.settingsSshReconnectHint}',
                    onPressed: busy ? null : onReconnect,
                    icon: rowAction?.kind == SshRowOperation.reconnect
                        ? const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (entry.managed) ...[
                    IconButton(
                      key: StudioDriverKeys.sshEdit(alias),
                      tooltip: context.l10n.settingsSshEdit,
                      onPressed: busy ? null : onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      key: StudioDriverKeys.sshDelete(alias),
                      tooltip: context.l10n.settingsSshDelete,
                      onPressed: busy ? null : onDelete,
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: busy ? null : context.colors.error,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              );
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identityBlock,
                    const SizedBox(height: 10),
                    controls,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: identityBlock),
                  const SizedBox(width: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.62,
                    ),
                    child: controls,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (entry.hasPassword)
                SettingsMiniMeta(
                  icon: Icons.password_outlined,
                  label: context.l10n.settingsSshPasswordBadge,
                ),
              if (hasIdentity)
                SettingsMiniMeta(
                  icon: Icons.vpn_key_outlined,
                  label: context.l10n.settingsSshKeyBadge(identityFile),
                ),
              if (connection case ReadySshConnectionState(
                :final helperVersion,
                :final architecture,
              ))
                SettingsMiniMeta(
                  icon: Icons.memory_outlined,
                  label:
                      '$architecture · ${context.l10n.settingsSshRemoteHelper} $helperVersion',
                )
              else
                Text(
                  context.l10n.settingsSshManagedByCore,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              if (!entry.managed)
                SettingsMiniMeta(
                  icon: Icons.lock_outline,
                  label: context.l10n.settingsSshReadOnlyEntry,
                ),
            ],
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            SettingsInlineError(message: errorMessage),
          ],
        ],
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({super.key, required this.connection});

  final SshConnectionState? connection;

  @override
  Widget build(BuildContext context) {
    final ready = connection is ReadySshConnectionState;
    return SettingsMiniMeta(
      icon: ready ? Icons.check_circle_outline : Icons.circle_outlined,
      label: sshConnectionStateText(context, connection),
    );
  }
}
