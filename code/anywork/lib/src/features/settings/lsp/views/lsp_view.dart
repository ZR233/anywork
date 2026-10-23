import 'package:anywork_client/lsp.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_pane.dart';
import '../state/lsp_view_state.dart';

class LspView extends StatelessWidget {
  const LspView({required this.catalog, required this.actions, required this.servers,
    required this.currentServerIds, required this.hasMore, required this.knownEmpty, required this.errors, required this.serverErrors,
    required this.sourceStatus, required this.onRefresh, required this.onMore, required this.onProbe,
    required this.onResetWorkspace, required this.onRepair, required this.onReset, super.key});
  final LspCatalogViewState catalog;
  final LspActionsViewState? actions;
  final List<LspServer> servers;
  final Set<String> currentServerIds;
  final bool hasMore;
  final bool knownEmpty;
  final List<String> errors;
  final Map<String, List<String>> serverErrors;
  final Widget sourceStatus;
  final VoidCallback onRefresh;
  final VoidCallback onMore;
  final VoidCallback? onProbe;
  final VoidCallback? onResetWorkspace;
  final ValueChanged<String>? onRepair;
  final ValueChanged<String>? onReset;

  bool _blocked(LspActionKind kind, [String? id]) => actions?.actions[(kind, id)]?.preventsResubmission ?? false;

  @override
  Widget build(BuildContext context) => SettingsPane(title: context.l10n.settingsLspTitle,
    subtitle: context.l10n.settingsLspSubtitle,
    trailing: Wrap(spacing: 8, runSpacing: 8, children: [
      TextButton.icon(key: StudioDriverKeys.lspRefresh, onPressed: catalog.reading.isEmpty ? onRefresh : null,
        icon: const Icon(Icons.refresh), label: Text(context.l10n.settingsLspRefresh)),
      TextButton.icon(key: StudioDriverKeys.lspProbe, onPressed: _blocked(LspActionKind.probe) ? null : onProbe,
        icon: const Icon(Icons.monitor_heart_outlined), label: Text(context.l10n.settingsLspProbe)),
      TextButton.icon(key: StudioDriverKeys.lspResetWorkspace,
        onPressed: servers.isEmpty || _blocked(LspActionKind.resetWorkspace) ? null : onResetWorkspace,
        icon: const Icon(Icons.restart_alt), label: Text(context.l10n.settingsLspResetWorkspace)),
    ]), child: ListView(children: [
      sourceStatus,
      for (final error in errors) SelectableText(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (servers.isEmpty && knownEmpty) ListTile(leading: const Icon(Icons.code_outlined),
        title: Text(context.l10n.settingsLspEmptyTitle), subtitle: Text(context.l10n.settingsLspEmptyMessage)),
      if (servers.isEmpty && !knownEmpty && catalog.reading.isEmpty) const Text('—'),
      for (final server in servers) _server(context, server),
      if (hasMore) TextButton.icon(onPressed: catalog.reading.contains(LspReadField.servers) ? null : onMore,
        icon: const Icon(Icons.expand_more), label: Text(context.l10n.settingsSshNextPage)),
    ]));

  Widget _server(BuildContext context, LspServer server) {
    final nativeError = switch (server.state) { UnavailableLspServerState(:final error) => error, _ => null };
    final informational = switch (server.state) {
      CheckingLspServerState(:final message) || DisabledLspServerState(:final message) => message,
      _ => null,
    };
    final activity = switch (server.state) { AvailableLspServerState(:final activity) => activity, _ => null };
    final activityText = switch (activity) {
      BusyLspActivity(:final title, :final message, :final percentage) ||
      IndexingLspActivity(:final title, :final message, :final percentage) => [
        if (title != null && title.isNotEmpty) title,
        if (message != null && message.isNotEmpty) message,
        if (percentage != null) context.l10n.statusLspActivityPercentage(percentage),
      ].join(' · '),
      _ => null,
    };
    final blocked = !currentServerIds.contains(server.id) || _blocked(LspActionKind.repair, server.id) || _blocked(LspActionKind.resetServer, server.id);
    return Card.outlined(child: Padding(padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [const Icon(Icons.code_outlined), const SizedBox(width: 10), Expanded(child: Text(server.displayName)),
          if (nativeError?.code == 'lspComponentMissing') TextButton.icon(key: StudioDriverKeys.lspRepairServer(server.id),
            onPressed: blocked || onRepair == null ? null : () => onRepair!(server.id),
            icon: const Icon(Icons.build_outlined), label: Text(context.l10n.settingsLspRepair)),
          TextButton.icon(key: StudioDriverKeys.lspResetServer(server.id),
            onPressed: blocked || onReset == null ? null : () => onReset!(server.id),
            icon: const Icon(Icons.restart_alt), label: Text(context.l10n.settingsLspReset)),
        ]),
        Text(switch (server.state) {
          CheckingLspServerState() => context.l10n.settingsStateChecking,
          DisabledLspServerState() => context.l10n.settingsStateDisabled,
          AvailableLspServerState() => context.l10n.settingsStateAvailable,
          UnavailableLspServerState() => context.l10n.settingsStateUnavailable,
        }),
        if (server.state case AvailableLspServerState(:final diagnosticCount)) Text(diagnosticCount.toString()),
        if (activity is BusyLspActivity || activity is IndexingLspActivity)
          Text(activity is IndexingLspActivity ? context.l10n.settingsLspActivityIndexing : context.l10n.settingsLspActivityBusy),
        if (activityText != null && activityText.isNotEmpty) Text(activityText),
        if (informational != null && informational.isNotEmpty) Text(informational),
        if (nativeError != null) SelectableText('${nativeError.message} [${nativeError.code}]',
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
        for (final error in serverErrors[server.id] ?? <String>[]) SelectableText(error,
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])));
  }
}
