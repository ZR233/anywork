import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/mcp.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/badges/studio_badges.dart';
import '../../state/settings_action.dart';
import '../../widgets/settings_feedback.dart';
import '../../accounts/widgets/auto_page_loader.dart';
import '../../widgets/settings_resource_row.dart';
import '../../widgets/settings_layout.dart';
import '../../widgets/settings_pane.dart';
import '../state/mcp_view_state.dart';

class McpView extends StatelessWidget {
  const McpView({
    required this.state,
    required this.servers,
    required this.configuration,
    required this.editableIds,
    required this.hasMore,
    required this.errors,
    required this.serverErrors,
    required this.onRefresh,
    required this.onMore,
    required this.onResetAll,
    required this.onReset,
    required this.onEnabled,
    required this.onEndpoint,
    required this.onComposing,
    required this.onCommit,
    super.key,
  });
  final McpViewState state;
  final List<McpServer> servers;
  final Map<String, McpConfiguration> configuration;
  final Set<String> editableIds;
  final bool hasMore;
  final List<String> errors;
  final Map<String, List<String>> serverErrors;
  final VoidCallback onRefresh;
  final VoidCallback onMore;
  final VoidCallback onResetAll;
  final ValueChanged<String> onReset;
  final void Function(String id, bool value) onEnabled;
  final void Function(String id, String raw) onEndpoint;
  final void Function(String id, bool value) onComposing;
  final void Function(String id, McpConfigField field) onCommit;

  @override
  Widget build(BuildContext context) => AutoPageLoader(
    hasMore: hasMore,
    loading: state.reading.contains(McpReadField.runtime),
    blocked: state.readIssues.containsKey(McpReadField.runtime),
    requestedCount: servers.length,
    onLoadMore: onMore,
    child: SettingsPane.scrolling(
      title: context.l10n.settingsMcpTitle,
      subtitle: context.l10n.settingsMcpSubtitle,
      trailing: Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            key: StudioDriverKeys.mcpRefresh,
            onPressed: state.reading.isEmpty ? onRefresh : null,
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.settingsMcpRefresh),
          ),
          TextButton.icon(
            key: StudioDriverKeys.mcpResetAll,
            onPressed:
                servers.isNotEmpty &&
                    !(state.resetAllAction?.preventsResubmission ?? false)
                ? onResetAll
                : null,
            icon: const Icon(Icons.restart_alt),
            label: Text(context.l10n.settingsMcpResetAll),
          ),
        ],
      ),
      children: [
        const SizedBox(height: 16),
        if (servers.isNotEmpty)
          SettingsGroup(
            children: [
              for (final server in servers)
                _McpServerRow(
                  server: server,
                  state: state,
                  configuration: configuration[server.id],
                  canEdit: editableIds.contains(server.id),
                  errors: serverErrors[server.id] ?? const [],
                  onReset: () => onReset(server.id),
                  onEnabled: (value) => onEnabled(server.id, value),
                  onEndpoint: (raw) => onEndpoint(server.id, raw),
                  onComposing: (value) => onComposing(server.id, value),
                  onCommit: (field) => onCommit(server.id, field),
                ),
            ],
          ),
        if (servers.isEmpty) const SizedBox(height: 8),
        if (servers.isEmpty)
          SettingsEmptyMessage(
            icon: Icons.hub_outlined,
            title: context.l10n.settingsMcpEmptyTitle,
            body: context.l10n.settingsMcpEmptyMessage,
          ),
        if (errors.isNotEmpty) SettingsInlineError(message: errors.join('\n')),
      ],
    ),
  );
}

/// MCP server row: identity with the enable switch and reconnect action, then
/// transport/availability pills, the failure message and the endpoint field.
class _McpServerRow extends StatelessWidget {
  const _McpServerRow({
    required this.server,
    required this.state,
    required this.configuration,
    required this.canEdit,
    required this.errors,
    required this.onReset,
    required this.onEnabled,
    required this.onEndpoint,
    required this.onComposing,
    required this.onCommit,
  });

  final McpServer server;
  final McpViewState state;
  final McpConfiguration? configuration;
  final bool canEdit;
  final List<String> errors;
  final VoidCallback onReset;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<String> onEndpoint;
  final ValueChanged<bool> onComposing;
  final ValueChanged<McpConfigField> onCommit;

  @override
  Widget build(BuildContext context) {
    final draft = state.drafts[server.id];
    final config = configuration;
    final enabled =
        draft?.enabled ??
        (config == null
            ? server.state is! DisabledMcpServerState
            : config.configuration != McpConfigurationState.disabled);
    final endpoint = draft?.endpoint ?? config?.endpoint ?? server.endpoint;
    final locked = config?.mutationPolicy == 'lockedIdentity';
    final nativeError = switch (server.state) {
      UnavailableMcpServerState(:final error) => error,
      _ => null,
    };
    return SettingsResourceRow(
      key: StudioDriverKeys.mcpServerRow(server.id),
      title: server.id,
      icon: Icons.hub_outlined,
      actions: [
        Switch(value: enabled, onChanged: canEdit ? onEnabled : null),
        const SizedBox(width: 8),
        TextButton.icon(
          key: StudioDriverKeys.mcpResetServer(server.id),
          onPressed:
              server.state is! DisabledMcpServerState &&
                  !(state.resets[server.id]?.preventsResubmission ?? false)
              ? onReset
              : null,
          icon: const Icon(Icons.sync),
          label: Text(context.l10n.settingsMcpReconnect),
        ),
      ],
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            StudioCompactChip(
              icon: Icons.hub_outlined,
              maxWidth: 220,
              label: server.transport,
            ),
            StudioCompactChip(
              icon: Icons.circle_outlined,
              maxWidth: 220,
              label: _availabilityLabel(context, server.state),
            ),
          ],
        ),
        if (nativeError != null) ...[
          const SizedBox(height: 8),
          Text(
            nativeError.message,
            key: StudioDriverKeys.mcpServerError(server.id),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 9),
        _McpEndpointField(
          key: ValueKey(('${server.id}:$endpoint:${config?.mutationPolicy}')),
          value: endpoint,
          enabled: canEdit && !locked,
          readOnly: locked,
          onChanged: onEndpoint,
          onComposing: onComposing,
          onCommit: () => onCommit(McpConfigField.endpoint),
        ),
        for (final error in errors)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(
              error,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        for (final field in McpConfigField.values)
          if (draft?.actions[field]?.outcome == SettingsActionOutcome.rejected)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onCommit(field),
                child: Text(context.l10n.runtimeFatalRetry),
              ),
            ),
        const Divider(height: 24),
      ],
    );
  }
}

/// Endpoint field keeps the pre-refactor dense decoration while retaining the
/// view model's composing/commit contract (IME composition and blur commits).
class _McpEndpointField extends StatefulWidget {
  const _McpEndpointField({
    required this.value,
    required this.enabled,
    required this.readOnly,
    required this.onChanged,
    required this.onComposing,
    required this.onCommit,
    super.key,
  });

  final String value;
  final bool enabled;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onComposing;
  final VoidCallback onCommit;

  @override
  State<_McpEndpointField> createState() => _McpEndpointFieldState();
}

class _McpEndpointFieldState extends State<_McpEndpointField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  bool _composing = false;
  bool _applyingValue = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_compositionChanged);
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant _McpEndpointField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value || _controller.text == widget.value) {
      return;
    }
    final selection = _controller.selection;
    _applyingValue = true;
    try {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection(
          baseOffset: selection.baseOffset.clamp(0, widget.value.length),
          extentOffset: selection.extentOffset.clamp(0, widget.value.length),
        ),
      );
    } finally {
      _applyingValue = false;
    }
  }

  void _compositionChanged() {
    final range = _controller.value.composing;
    final composing = range.isValid && !range.isCollapsed;
    if (composing == _composing) return;
    _composing = composing;
    if (_applyingValue) return;
    widget.onComposing(composing);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) widget.onCommit();
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _controller.removeListener(_compositionChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: _focus,
    enabled: widget.enabled,
    readOnly: widget.readOnly,
    decoration: InputDecoration(
      labelText: context.l10n.settingsEndpoint,
      isDense: true,
    ),
    onChanged: widget.onChanged,
    onEditingComplete: widget.onCommit,
  );
}

String _availabilityLabel(BuildContext context, McpServerState state) =>
    switch (state) {
      DisabledMcpServerState() => context.l10n.settingsStateDisabled,
      MissingCredentialMcpServerState() =>
        context.l10n.settingsMcpStateMissingCredential,
      CheckingMcpServerState() => context.l10n.settingsStateChecking,
      AvailableMcpServerState() => context.l10n.settingsStateAvailable,
      UnavailableMcpServerState() => context.l10n.settingsStateUnavailable,
    };
