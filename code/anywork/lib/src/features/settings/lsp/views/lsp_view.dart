import 'package:anywork_client/lsp.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/badges/studio_badges.dart';
import '../../widgets/settings_feedback.dart';
import '../../accounts/widgets/auto_page_loader.dart';
import '../../widgets/settings_resource_row.dart';
import '../../widgets/settings_layout.dart';
import '../../widgets/settings_pane.dart';
import '../state/lsp_view_state.dart';

class LspView extends StatelessWidget {
  const LspView({
    required this.catalog,
    required this.actions,
    required this.servers,
    required this.currentServerIds,
    required this.hasMore,
    required this.errors,
    required this.serverErrors,
    required this.onRefresh,
    required this.onMore,
    required this.onProbe,
    required this.onResetWorkspace,
    required this.onRepair,
    required this.onReset,
    super.key,
  });
  final LspCatalogViewState catalog;
  final LspActionsViewState? actions;
  final List<LspServer> servers;
  final Set<String> currentServerIds;
  final bool hasMore;
  final List<String> errors;
  final Map<String, List<String>> serverErrors;
  final VoidCallback onRefresh;
  final VoidCallback onMore;
  final VoidCallback? onProbe;
  final VoidCallback? onResetWorkspace;
  final ValueChanged<String>? onRepair;
  final ValueChanged<String>? onReset;

  bool _blocked(LspActionKind kind, [String? id]) =>
      actions?.actions[(kind, id)]?.preventsResubmission ?? false;

  @override
  Widget build(BuildContext context) => AutoPageLoader(
    hasMore: hasMore,
    loading: catalog.reading.contains(LspReadField.servers),
    blocked: catalog.readIssues.containsKey(LspReadField.servers),
    requestedCount: servers.length,
    onLoadMore: onMore,
    child: SettingsPane.scrolling(
      title: context.l10n.settingsLspTitle,
      subtitle: context.l10n.settingsLspSubtitle,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton.icon(
            key: StudioDriverKeys.lspRefresh,
            onPressed: catalog.reading.isEmpty ? onRefresh : null,
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.settingsLspRefresh),
          ),
          TextButton.icon(
            key: StudioDriverKeys.lspProbe,
            onPressed: _blocked(LspActionKind.probe) ? null : onProbe,
            icon: const Icon(Icons.monitor_heart_outlined),
            label: Text(context.l10n.settingsLspProbe),
          ),
          TextButton.icon(
            key: StudioDriverKeys.lspResetWorkspace,
            onPressed: servers.isEmpty || _blocked(LspActionKind.resetWorkspace)
                ? null
                : onResetWorkspace,
            icon: const Icon(Icons.restart_alt),
            label: Text(context.l10n.settingsLspResetWorkspace),
          ),
        ],
      ),
      children: [
        const SizedBox(height: 16),
        if (servers.isNotEmpty)
          SettingsGroup(
            children: [
              for (final server in servers)
                _LspServerRow(
                  server: server,
                  errors: serverErrors[server.id] ?? const [],
                  onRepair: onRepair == null
                      ? null
                      : () => onRepair!(server.id),
                  onReset: onReset == null ? null : () => onReset!(server.id),
                  repairBlocked:
                      !currentServerIds.contains(server.id) ||
                      _blocked(LspActionKind.repair, server.id),
                  resetBlocked:
                      !currentServerIds.contains(server.id) ||
                      _blocked(LspActionKind.resetServer, server.id),
                ),
            ],
          )
        else
          SettingsEmptyMessage(
            icon: Icons.code_outlined,
            title: context.l10n.settingsLspEmptyTitle,
            body: context.l10n.settingsLspEmptyMessage,
          ),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          SettingsInlineError(message: errors.join('\n')),
        ],
      ],
    ),
  );
}

/// LSP server row: identity with repair/reset actions, then availability,
/// diagnostic and activity pills, the activity detail and failure text.
class _LspServerRow extends StatelessWidget {
  const _LspServerRow({
    required this.server,
    required this.errors,
    required this.onRepair,
    required this.onReset,
    required this.repairBlocked,
    required this.resetBlocked,
  });

  final LspServer server;
  final List<String> errors;
  final VoidCallback? onRepair;
  final VoidCallback? onReset;
  final bool repairBlocked;
  final bool resetBlocked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final nativeError = switch (server.state) {
      UnavailableLspServerState(:final error) => error,
      _ => null,
    };
    final informational = switch (server.state) {
      CheckingLspServerState(:final message) ||
      DisabledLspServerState(:final message) => message,
      _ => null,
    };
    final activity = switch (server.state) {
      AvailableLspServerState(:final activity) => activity,
      _ => null,
    };
    final activityText = switch (activity) {
      BusyLspActivity(:final title, :final message, :final percentage) ||
      IndexingLspActivity(:final title, :final message, :final percentage) => [
        if (title != null && title.isNotEmpty) title,
        if (message != null && message.isNotEmpty) message,
        if (percentage != null)
          context.l10n.statusLspActivityPercentage(percentage),
      ].join(' · '),
      _ => null,
    };
    final repair = nativeError?.code == 'lspComponentMissing' ? onRepair : null;
    return SettingsResourceRow(
      title: server.displayName,
      icon: Icons.code_outlined,
      actions: [
        if (repair != null)
          TextButton.icon(
            key: StudioDriverKeys.lspRepairServer(server.id),
            onPressed: repairBlocked ? null : repair,
            icon: const Icon(Icons.build_outlined),
            label: Text(context.l10n.settingsLspRepair),
          ),
        const SizedBox(width: 8),
        TextButton.icon(
          key: StudioDriverKeys.lspResetServer(server.id),
          onPressed: resetBlocked ? null : onReset,
          icon: const Icon(Icons.restart_alt),
          label: Text(context.l10n.settingsLspReset),
        ),
      ],
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            StudioCompactChip(
              icon: Icons.circle_outlined,
              maxWidth: 220,
              label: _availabilityLabel(context, server.state),
            ),
            if (server.state case AvailableLspServerState(
              :final diagnosticCount,
            ))
              StudioCompactChip(
                icon: Icons.rule_outlined,
                maxWidth: 220,
                label: diagnosticCount.toString(),
              ),
            if (activity != null)
              StudioCompactChip(
                maxWidth: 220,
                icon: activity is IndexingLspActivity
                    ? Icons.manage_search_outlined
                    : Icons.sync_outlined,
                label: activity is IndexingLspActivity
                    ? context.l10n.settingsLspActivityIndexing
                    : context.l10n.settingsLspActivityBusy,
              ),
          ],
        ),
        if (activityText != null && activityText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(activityText, style: text.bodySmall),
        ],
        if (informational != null && informational.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(informational, style: text.bodySmall),
        ],
        if (nativeError != null) ...[
          const SizedBox(height: 8),
          SelectableText(
            nativeError.message,
            style: text.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        for (final error in errors)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(
              error,
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        const Divider(height: 24),
      ],
    );
  }
}

String _availabilityLabel(BuildContext context, LspServerState state) =>
    switch (state) {
      CheckingLspServerState() => context.l10n.settingsStateChecking,
      DisabledLspServerState() => context.l10n.settingsStateDisabled,
      AvailableLspServerState() => context.l10n.settingsStateAvailable,
      UnavailableLspServerState() => context.l10n.settingsStateUnavailable,
    };
