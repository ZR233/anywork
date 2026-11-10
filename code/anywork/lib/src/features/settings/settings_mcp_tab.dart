import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_common.dart';
import 'settings_scope.dart';
import 'settings_views.dart';

class McpTab extends ConsumerStatefulWidget {
  const McpTab({super.key, required this.tabIndex});

  /// 本页在设置壳中的 tab 索引，用于「仅在可见时做显示观察」。
  final int tabIndex;

  @override
  ConsumerState<McpTab> createState() => _McpTabState();
}

class _McpTabState extends ConsumerState<McpTab> {
  McpScope _selectedScope = const HostMcpScope();
  List<SshServer> _sshServers = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSshServers());
  }

  Future<void> _loadSshServers() async {
    try {
      final servers = await ref
          .read(anyworkClientProvider)
          .remote
          .listSshServers();
      if (!mounted) return;
      setState(() {
        _sshServers = servers;
        if (_selectedScope case SshMcpScope(:final sshAlias)) {
          if (!servers.any((server) => server.alias == sshAlias)) {
            _selectedScope = const HostMcpScope();
          }
        }
      });
    } catch (_) {
      // SSH server list is optional for Host MCP configuration.
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(settingsVisibleTabProvider) == widget.tabIndex;
    watchSettingsScope(
      ref,
      visible: visible,
      kind: BridgeSettingsScopeKind.mcp,
    );
    final mcp = ref.watch(settingsScopedMcpViewProvider(_selectedScope));
    final entries = mcp.entries;
    final diagnostics = mcp.diagnostics;

    return SettingsPane(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsHeader(
            title: context.l10n.settingsMcpTitle,
            subtitle: context.l10n.settingsMcpSubtitle,
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_sshServers.isNotEmpty)
                  DropdownButtonHideUnderline(
                    child: DropdownButton<McpScope>(
                      key: const ValueKey<String>('mcp-scope-selector'),
                      value: _selectedScope,
                      isDense: true,
                      items: [
                        const DropdownMenuItem<McpScope>(
                          value: HostMcpScope(),
                          child: Text('Host'),
                        ),
                        for (final server in _sshServers)
                          DropdownMenuItem<McpScope>(
                            value: SshMcpScope(sshAlias: server.alias),
                            child: Text('SSH · ${server.alias}'),
                          ),
                      ],
                      onChanged: (next) {
                        if (next == null) return;
                        setState(() {
                          _selectedScope = next;
                          _error = null;
                        });
                      },
                    ),
                  ),
                TextButton.icon(
                  key: StudioDriverKeys.mcpRefresh,
                  onPressed: () => unawaited(_run(_refresh)),
                  icon: const Icon(Icons.refresh),
                  label: Text(context.l10n.settingsMcpRefresh),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey<String>('mcp-create-document'),
                  onPressed: () => unawaited(_openCreateDialog()),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('TOML'),
                ),
              ],
            ),
          ),
          if (visible)
            SettingsTopicStatus(topic: McpCatalogTopic(scope: _selectedScope)),
        ],
      ),
      children: [
        const SizedBox(height: 16),
        if (diagnostics.isNotEmpty) ...[
          SettingsGroup(
            children: [
              for (final diagnostic in diagnostics)
                SettingsResourceRow(
                  key: ValueKey<String>(
                    'mcp-diagnostic-${diagnostic.document.relativePath}',
                  ),
                  title: diagnostic.document.relativePath,
                  icon: Icons.warning_amber_outlined,
                  actions: [
                    TextButton(
                      onPressed: () => unawaited(
                        _openEditDialog(
                          diagnostic.document,
                          title: diagnostic.document.relativePath,
                        ),
                      ),
                      child: const Text('TOML'),
                    ),
                    TextButton(
                      onPressed: () =>
                          unawaited(_deleteDocumentByRef(diagnostic.document)),
                      child: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: context.colors.error,
                      ),
                    ),
                  ],
                  children: [
                    Text(
                      '${diagnostic.code}: ${diagnostic.message}',
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.error,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (entries.isNotEmpty)
          SettingsGroup(
            children: [
              for (final entry in entries)
                _McpCatalogRow(
                  entry: entry,
                  onEditToml: entry.document == null
                      ? null
                      : () => unawaited(
                          _openEditDialog(entry.document!, title: entry.id),
                        ),
                  onOverrideInSsh:
                      entry.canOverrideInSsh && entry.document == null
                      ? () => unawaited(_openOverrideDialog(entry))
                      : null,
                  onDisableInSsh: entry.canDisableInSsh
                      ? () => unawaited(_disableInSsh(entry))
                      : null,
                  onDeleteOrRestore: entry.document != null
                      ? () => unawaited(_deleteDocumentByRef(entry.document!))
                      : null,
                ),
            ],
          ),
        if (entries.isEmpty && diagnostics.isEmpty)
          SettingsEmptyMessage(
            icon: Icons.hub_outlined,
            title: context.l10n.settingsMcpEmptyTitle,
            body: context.l10n.settingsMcpEmptyMessage,
          ),
        if (_error != null) SettingsInlineError(message: _error!),
      ],
    );
  }

  Future<void> _refresh() async {
    await _loadSshServers();
    await ref
        .read(anyworkClientProvider)
        .directoryCommands
        .reloadMcpCatalog(_selectedScope);
  }

  Future<void> _run(Future<void> Function() operation) async {
    try {
      setState(() => _error = null);
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<({String id, String rawToml})>(
      context: context,
      builder: (context) => const _McpCreateTomlDialog(),
    );
    if (created == null || created.id.isEmpty || !mounted) return;
    await _run(
      () => ref
          .read(anyworkClientProvider)
          .directoryCommands
          .createMcpDocument(
            scope: _selectedScope,
            id: created.id,
            rawToml: created.rawToml,
          ),
    );
  }

  Future<void> _openOverrideDialog(McpCatalogEntry entry) async {
    final template = entry.builtIn
        ? 'id = "${entry.id}"\nkind = "builtin"\nbuiltin = "${entry.id}"\nenabled = true\n'
        : 'id = "${entry.id}"\nkind = "server"\ntransport = "${entry.transport ?? 'stdio'}"\ncommand = "${entry.endpointSummary ?? entry.id}"\n';
    final rawToml = await showDialog<String>(
      context: context,
      builder: (context) => _McpEditTomlDialog(
        title: 'Override ${entry.id}',
        initialToml: template,
        fieldKey: ValueKey<String>('mcp-override-toml-${entry.id}'),
        confirmKey: ValueKey<String>('mcp-override-confirm-${entry.id}'),
      ),
    );
    if (rawToml == null || !mounted) return;
    await _run(
      () => ref
          .read(anyworkClientProvider)
          .directoryCommands
          .createMcpDocument(
            scope: _selectedScope,
            id: entry.id,
            rawToml: rawToml,
          ),
    );
  }

  Future<void> _openEditDialog(
    McpDocumentRef document, {
    required String title,
  }) async {
    late final McpDocumentContent content;
    try {
      setState(() => _error = null);
      content = await ref
          .read(anyworkClientProvider)
          .directoryCommands
          .readMcpDocument(document);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (!mounted) return;
    final updatedToml = await showDialog<String>(
      context: context,
      builder: (context) => _McpEditTomlDialog(
        title: title,
        initialToml: content.rawToml,
        fieldKey: ValueKey<String>('mcp-edit-toml-${document.relativePath}'),
        confirmKey: ValueKey<String>(
          'mcp-edit-confirm-${document.relativePath}',
        ),
      ),
    );
    if (updatedToml == null || !mounted) return;
    await _run(
      () => ref
          .read(anyworkClientProvider)
          .directoryCommands
          .updateMcpDocument(
            document: document,
            expectedRevision: content.revision,
            rawToml: updatedToml,
          ),
    );
  }

  Future<void> _disableInSsh(McpCatalogEntry entry) async {
    final tombstoneToml = 'id = "${entry.id}"\nkind = "disabled"\n';
    final existingDoc = entry.document;
    if (existingDoc != null && existingDoc.scope == _selectedScope) {
      await _run(() async {
        final current = await ref
            .read(anyworkClientProvider)
            .directoryCommands
            .readMcpDocument(existingDoc);
        await ref
            .read(anyworkClientProvider)
            .directoryCommands
            .updateMcpDocument(
              document: existingDoc,
              expectedRevision: current.revision,
              rawToml: tombstoneToml,
            );
      });
      return;
    }
    await _run(
      () => ref
          .read(anyworkClientProvider)
          .directoryCommands
          .createMcpDocument(
            scope: _selectedScope,
            id: entry.id,
            rawToml: tombstoneToml,
          ),
    );
  }

  Future<void> _deleteDocumentByRef(McpDocumentRef document) async {
    await _run(() async {
      final current = await ref
          .read(anyworkClientProvider)
          .directoryCommands
          .readMcpDocument(document);
      await ref
          .read(anyworkClientProvider)
          .directoryCommands
          .deleteMcpDocument(
            document: document,
            expectedRevision: current.revision,
          );
    });
  }
}

class _McpCatalogRow extends StatelessWidget {
  const _McpCatalogRow({
    required this.entry,
    this.onEditToml,
    this.onOverrideInSsh,
    this.onDisableInSsh,
    this.onDeleteOrRestore,
  });

  final McpCatalogEntry entry;
  final VoidCallback? onEditToml;
  final VoidCallback? onOverrideInSsh;
  final VoidCallback? onDisableInSsh;
  final VoidCallback? onDeleteOrRestore;

  @override
  Widget build(BuildContext context) {
    final hasError =
        entry.configStatus == McpConfigStatusKind.invalidDocument ||
        entry.configStatus == McpConfigStatusKind.missingPrereq;
    return SettingsResourceRow(
      key: StudioDriverKeys.mcpServerRow(entry.id),
      title: entry.id,
      icon: Icons.hub_outlined,
      actions: [
        if (onEditToml != null)
          TextButton(
            key: ValueKey<String>('mcp-edit-${entry.id}'),
            onPressed: onEditToml,
            child: const Text('TOML'),
          ),
        if (onOverrideInSsh != null)
          TextButton(
            key: ValueKey<String>('mcp-override-${entry.id}'),
            onPressed: onOverrideInSsh,
            child: const Text('Override'),
          ),
        if (onDisableInSsh != null)
          TextButton(
            key: ValueKey<String>('mcp-disable-${entry.id}'),
            onPressed: onDisableInSsh,
            child: Text(context.l10n.settingsStateDisabled),
          ),
        if (onDeleteOrRestore != null)
          IconButton(
            key: ValueKey<String>('mcp-delete-${entry.id}'),
            tooltip: entry.canRestoreInheritance ? 'Restore Host' : 'Delete',
            onPressed: onDeleteOrRestore,
            icon: Icon(
              entry.canRestoreInheritance
                  ? Icons.restore_outlined
                  : Icons.delete_outline,
              size: 18,
            ),
          ),
      ],
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (entry.transport case final transport? when transport.isNotEmpty)
              SettingsInfoPill(icon: Icons.hub_outlined, label: transport),
            SettingsInfoPill(
              icon: Icons.circle_outlined,
              label: _mcpConfigStatusLabel(context, entry.configStatus),
            ),
            SettingsInfoPill(
              icon: Icons.layers_outlined,
              label: _mcpSourceLabel(entry.effectiveSource),
            ),
            if (entry.executionLocation case final location?)
              SettingsInfoPill(
                icon: Icons.dns_outlined,
                label: _mcpLocationLabel(location),
              ),
          ],
        ),
        if (entry.endpointSummary case final summary?
            when summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            summary,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
        if (entry.message case final message? when message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            message,
            key: StudioDriverKeys.mcpServerError(entry.id),
            style: context.text.bodySmall?.copyWith(
              color: hasError
                  ? context.colors.error
                  : context.colors.onSurfaceVariant,
            ),
          ),
        ],
        const Divider(height: 24),
      ],
    );
  }
}

String _mcpConfigStatusLabel(
  BuildContext context,
  McpConfigStatusKind status,
) => switch (status) {
  McpConfigStatusKind.enabled => context.l10n.settingsStateAvailable,
  McpConfigStatusKind.disabled ||
  McpConfigStatusKind.shadowedDisable => context.l10n.settingsStateDisabled,
  McpConfigStatusKind.missingPrereq =>
    context.l10n.settingsMcpStateMissingCredential,
  McpConfigStatusKind.invalidDocument => context.l10n.settingsStateUnavailable,
};

String _mcpSourceLabel(McpEffectiveSource source) => switch (source) {
  McpEffectiveSource.hostServer => 'host',
  McpEffectiveSource.hostBuiltin => 'builtin',
  McpEffectiveSource.inheritedHostServer => 'inherited',
  McpEffectiveSource.inheritedHostBuiltin => 'inherited builtin',
  McpEffectiveSource.sshOverrideServer => 'ssh override',
  McpEffectiveSource.sshOverrideBuiltin => 'ssh builtin',
  McpEffectiveSource.sshDisabledTombstone => 'ssh disabled',
  McpEffectiveSource.invalidFile => 'invalid',
};

String _mcpLocationLabel(McpExecutionLocation location) => switch (location) {
  HostLocalMcpExecutionLocation() => 'host-local',
  HostRemoteStreamableHttpMcpExecutionLocation() => 'host-http',
  SshRemoteMcpExecutionLocation(:final sshAlias) => 'ssh:$sshAlias',
  SshRemoteStreamableHttpMcpExecutionLocation(:final sshAlias) =>
    'ssh-http:$sshAlias',
};

class _McpCreateTomlDialog extends StatefulWidget {
  const _McpCreateTomlDialog();

  @override
  State<_McpCreateTomlDialog> createState() => _McpCreateTomlDialogState();
}

class _McpCreateTomlDialogState extends State<_McpCreateTomlDialog> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _tomlController = TextEditingController(
    text: 'id = "example"\nkind = "server"\ntransport = "stdio"\ncommand = "npx"\nargs = ["-y", "@modelcontextprotocol/server-everything"]\n',
  );

  @override
  void dispose() {
    _idController.dispose();
    _tomlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New MCP TOML'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey<String>('mcp-create-id-input'),
              controller: _idController,
              decoration: const InputDecoration(
                labelText: 'Server ID',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('mcp-create-toml-input'),
              controller: _tomlController,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'TOML',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.settingsCancel),
        ),
        FilledButton(
          key: const ValueKey<String>('mcp-create-confirm'),
          onPressed: () => Navigator.of(
            context,
          ).pop((id: _idController.text.trim(), rawToml: _tomlController.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _McpEditTomlDialog extends StatefulWidget {
  const _McpEditTomlDialog({
    required this.title,
    required this.initialToml,
    required this.fieldKey,
    required this.confirmKey,
  });

  final String title;
  final String initialToml;
  final Key fieldKey;
  final Key confirmKey;

  @override
  State<_McpEditTomlDialog> createState() => _McpEditTomlDialogState();
}

class _McpEditTomlDialogState extends State<_McpEditTomlDialog> {
  late final TextEditingController _tomlController = TextEditingController(
    text: widget.initialToml,
  );

  @override
  void dispose() {
    _tomlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: TextField(
          key: widget.fieldKey,
          controller: _tomlController,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'TOML',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.settingsCancel),
        ),
        FilledButton(
          key: widget.confirmKey,
          onPressed: () => Navigator.of(context).pop(_tomlController.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
