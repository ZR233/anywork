import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/mcp.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../state/settings_action.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_pane.dart';
import '../state/mcp_view_state.dart';

class McpView extends StatelessWidget {
  const McpView({required this.state, required this.servers, required this.configuration,
    required this.editableIds, required this.hasMore, required this.knownEmpty, required this.errors, required this.serverErrors,
    required this.sources, required this.onRefresh, required this.onMore, required this.onResetAll,
    required this.onReset, required this.onEnabled, required this.onEndpoint, required this.onComposing,
    required this.onCommit, super.key});
  final McpViewState state;
  final List<McpServer> servers;
  final Map<String, McpConfiguration> configuration;
  final Set<String> editableIds;
  final bool hasMore;
  final bool knownEmpty;
  final List<String> errors;
  final Map<String, List<String>> serverErrors;
  final List<Widget> sources;
  final VoidCallback onRefresh;
  final VoidCallback onMore;
  final VoidCallback onResetAll;
  final ValueChanged<String> onReset;
  final void Function(String id, bool value) onEnabled;
  final void Function(String id, String raw) onEndpoint;
  final void Function(String id, bool value) onComposing;
  final void Function(String id, McpConfigField field) onCommit;

  @override
  Widget build(BuildContext context) => SettingsPane(title: context.l10n.settingsMcpTitle,
    subtitle: context.l10n.settingsMcpSubtitle,
    trailing: Wrap(spacing: 8, children: [
      TextButton.icon(key: StudioDriverKeys.mcpRefresh, onPressed: state.reading.isEmpty ? onRefresh : null,
        icon: const Icon(Icons.refresh), label: Text(context.l10n.settingsMcpRefresh)),
      TextButton.icon(key: StudioDriverKeys.mcpResetAll, onPressed: servers.isNotEmpty &&
        !(state.resetAllAction?.preventsResubmission ?? false) ? onResetAll : null,
        icon: const Icon(Icons.restart_alt), label: Text(context.l10n.settingsMcpResetAll)),
    ]), child: ListView(children: [
      ...sources,
      for (final error in errors) SelectableText(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (servers.isEmpty && knownEmpty) ListTile(leading: const Icon(Icons.hub_outlined),
        title: Text(context.l10n.settingsMcpEmptyTitle), subtitle: Text(context.l10n.settingsMcpEmptyMessage)),
      if (servers.isEmpty && !knownEmpty && state.reading.isEmpty) const Text('—'),
      for (final server in servers) _server(context, server),
      if (hasMore) TextButton.icon(onPressed: state.reading.contains(McpReadField.runtime) ? null : onMore,
        icon: const Icon(Icons.expand_more), label: Text(context.l10n.settingsSshNextPage)),
    ]));

  Widget _server(BuildContext context, McpServer server) {
    final draft = state.drafts[server.id];
    final config = configuration[server.id];
    final enabled = draft?.enabled ?? (config == null ? server.state is! DisabledMcpServerState
      : config.configuration != McpConfigurationState.disabled);
    final endpoint = draft?.endpoint ?? config?.endpoint ?? server.endpoint;
    final canEdit = editableIds.contains(server.id);
    final nativeError = switch (server.state) { UnavailableMcpServerState(:final error) => error, _ => null };
    final message = switch (server.state) {
      DisabledMcpServerState(:final message) || MissingCredentialMcpServerState(:final message) ||
      CheckingMcpServerState(:final message) => message,
      _ => null,
    };
    return Card.outlined(key: StudioDriverKeys.mcpServerRow(server.id), child: Padding(padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [const Icon(Icons.hub_outlined), const SizedBox(width: 10), Expanded(child: Text(server.id)),
          Switch(value: enabled, onChanged: canEdit ? (value) => onEnabled(server.id, value) : null),
          TextButton.icon(key: StudioDriverKeys.mcpResetServer(server.id),
            onPressed: server.state is! DisabledMcpServerState && !(state.resets[server.id]?.preventsResubmission ?? false)
              ? () => onReset(server.id) : null, icon: const Icon(Icons.sync), label: Text(context.l10n.settingsMcpReconnect)),
        ]),
        Text('${server.transport} · ${switch (server.state) {
          DisabledMcpServerState() => context.l10n.settingsStateDisabled,
          MissingCredentialMcpServerState() => context.l10n.settingsMcpStateMissingCredential,
          CheckingMcpServerState() => context.l10n.settingsStateChecking,
          AvailableMcpServerState() => context.l10n.settingsStateAvailable,
          UnavailableMcpServerState() => context.l10n.settingsStateUnavailable,
        }}'),
        if (message != null && message.isNotEmpty) Text(message),
        if (nativeError != null) SelectableText('${nativeError.message} [${nativeError.code}]',
          key: StudioDriverKeys.mcpServerError(server.id), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 10),
        SettingsFormField(key: ValueKey(('mcp-endpoint', server.id)), value: endpoint, label: context.l10n.settingsEndpoint,
          enabled: canEdit && config?.mutationPolicy != 'lockedIdentity',
          onChanged: (raw) => onEndpoint(server.id, raw), onComposing: (value) => onComposing(server.id, value),
          onCommit: () => onCommit(server.id, McpConfigField.endpoint)),
        for (final error in serverErrors[server.id] ?? <String>[]) SelectableText(error,
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
        for (final field in McpConfigField.values)
          if (draft?.actions[field]?.outcome == SettingsActionOutcome.rejected) Align(alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => onCommit(server.id, field), child: Text(context.l10n.runtimeFatalRetry))),
      ])));
  }
}
