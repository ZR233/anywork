import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_common.dart';

enum SshServerOperation { test, reconnect, open, edit, delete }

class SshServerRow extends StatelessWidget {
  const SshServerRow({
    super.key,
    required this.server,
    required this.connection,
    required this.operation,
    this.error,
    required this.onTest,
    required this.onReconnect,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final SshServer server;
  final SshConnectionView? connection;
  final SshServerOperation? operation;
  final String? error;
  final VoidCallback onTest;
  final VoidCallback onReconnect;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ready = connection?.state == 'ready';
    final busy = operation != null;
    final hasIdentity =
        server.identityFile != null && server.identityFile!.trim().isNotEmpty;
    final errorMessage = error ?? connection?.errorMessage;

    return SettingsResourceRow(
      title: server.alias,
      subtitle: '${server.username}@${server.hostName}:${server.port}',
      icon: Icons.dns_outlined,
      status: _ConnectionChip(
        key: ready ? StudioDriverKeys.sshReady(server.alias) : null,
        connection: connection,
      ),
      actions: [
        TextButton.icon(
          key: StudioDriverKeys.sshTest(server.alias),
          onPressed: busy ? null : onTest,
          icon: operation == SshServerOperation.test
              ? const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cable_outlined, size: 17),
          label: Text(context.l10n.settingsSshTest),
        ),
        TextButton.icon(
          key: StudioDriverKeys.sshOpen(server.alias),
          onPressed: busy ? null : onOpen,
          icon: const Icon(Icons.folder_open_outlined, size: 17),
          label: Text(context.l10n.settingsSshOpenProject),
        ),
        IconButton(
          key: StudioDriverKeys.sshReconnect(server.alias),
          tooltip:
              '${context.l10n.settingsSshReconnect} — ${context.l10n.settingsSshReconnectHint}',
          onPressed: busy ? null : onReconnect,
          icon: operation == SshServerOperation.reconnect
              ? const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          visualDensity: VisualDensity.compact,
        ),
        if (server.managed) ...[
          IconButton(
            key: StudioDriverKeys.sshEdit(server.alias),
            tooltip: context.l10n.settingsSshEdit,
            onPressed: busy ? null : onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            key: StudioDriverKeys.sshDelete(server.alias),
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
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (server.hasPassword)
              SettingsMiniMeta(
                icon: Icons.password_outlined,
                label: context.l10n.settingsSshPasswordBadge,
              ),
            if (hasIdentity)
              SettingsMiniMeta(
                icon: Icons.vpn_key_outlined,
                label: context.l10n.settingsSshKeyBadge(server.identityFile!),
              ),
            if (ready)
              SettingsMiniMeta(
                icon: Icons.memory_outlined,
                label:
                    '${connection!.architecture} · ${context.l10n.settingsSshRemoteHelper} ${connection!.helperVersion}',
              )
            else
              Text(
                context.l10n.settingsSshManagedByCore,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            if (!server.managed)
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
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({super.key, required this.connection});

  final SshConnectionView? connection;

  @override
  Widget build(BuildContext context) {
    final state = connection?.state ?? 'disconnected';
    final ready = state == 'ready';
    return SettingsMiniMeta(
      icon: ready ? Icons.check_circle_outline : Icons.circle_outlined,
      label: context.sshConnectionStateLabel(state),
    );
  }
}
