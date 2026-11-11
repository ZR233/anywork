import 'dart:async';
import 'dart:math' as math;

import 'package:anywork_client/studio_client.dart'
    show DomainSyncPhase, DomainSyncStatus;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'started_items_state.dart';
import 'status_view.dart';

/// Official menu owns focus, Escape dismissal and viewport positioning. Only
/// the menu content observes services; progress never rebuilds its trigger.
class StartedItemsEntry extends StatefulWidget {
  const StartedItemsEntry({required this.threadId, super.key});
  final String threadId;

  @override
  State<StartedItemsEntry> createState() => _StartedItemsEntryState();
}

class _StartedItemsEntryState extends State<StartedItemsEntry> {
  final _controller = MenuController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _controller,
    childFocusNode: _focusNode,
    menuChildren: [
      SizedBox(
        width: math.max(
          0,
          math.min(440, MediaQuery.sizeOf(context).width - 48),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(0, MediaQuery.sizeOf(context).height - 96),
          ),
          child: SingleChildScrollView(
            controller: _scrollController,
            primary: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: StartedItemsConnector(threadId: widget.threadId),
          ),
        ),
      ),
    ],
    builder: (context, controller, child) => IconButton(
      key: StudioDriverKeys.statusStartedItems,
      focusNode: _focusNode,
      tooltip: context.l10n.statusCapabilitiesTitle,
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.tune_outlined, size: 18),
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
    ),
  );
}

class StartedItemsConnector extends ConsumerWidget {
  const StartedItemsConnector({required this.threadId, super.key});
  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(startedItemsViewModelProvider(threadId));
    final commands = ref.read(startedItemsViewModelProvider(threadId).notifier);
    return state.when(
      data: (value) => StartedItemsPanel(
        state: value,
        onReconnectMcp: (id) => unawaited(commands.reconnectMcp(id)),
        onReconnectLsp: (id) => unawaited(commands.reconnectLsp(id)),
      ),
      loading: () => _EmptyRow(label: context.l10n.settingsStateChecking),
      error: (error, stack) => Tooltip(
        message: error.toString(),
        child: _ServiceRow(
          icon: Icons.error_outline,
          name: context.l10n.statusCapabilitiesTitle,
          status: StartedServiceStatus.failed,
        ),
      ),
    );
  }
}

/// No providers, commands or resource ownership below this boundary.
class StartedItemsPanel extends StatelessWidget {
  const StartedItemsPanel({
    required this.state,
    required this.onReconnectMcp,
    required this.onReconnectLsp,
    super.key,
  });

  final StartedItemsState state;
  final void Function(String? id) onReconnectMcp;
  final void Function(String id) onReconnectLsp;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          context.l10n.statusCapabilitiesTitle,
          style: context.text.titleSmall,
        ),
      ),
      if (state.skills.isNotEmpty) ...[
        _GroupHeading(title: context.l10n.statusSkillsSection),
        for (final skill in state.skills)
          _ServiceRow(
            key: StudioDriverKeys.statusActiveSkill(skill),
            icon: Icons.extension_outlined,
            name: skill,
          ),
      ],
      _GroupHeading(
        title: context.l10n.statusMcpSection,
        sync: state.mcpSync,
        action: _ReconnectButton(
          key: StudioDriverKeys.mcpResetAll,
          pending: state.pending.contains('mcp'),
          error: state.errors['mcp'],
          onPressed:
              state.pending.any((key) => key == 'mcp' || key.startsWith('mcp:'))
              ? null
              : () => onReconnectMcp(null),
        ),
      ),
      if (state.mcp.isEmpty && state.mcpSync.isReady)
        _EmptyRow(label: context.l10n.settingsMcpEmptyTitle),
      for (final server in state.mcp)
        _ServiceRow(
          key: StudioDriverKeys.mcpServerRow(server.id),
          icon: Icons.hub_outlined,
          name: server.name,
          status: server.status,
          diagnostic: state.errors['mcp:${server.id}'] ?? server.diagnostic,
          action: _ReconnectButton(
            key: StudioDriverKeys.mcpResetServer(server.id),
            pending: state.pending.contains('mcp:${server.id}'),
            error: state.errors['mcp:${server.id}'],
            onPressed:
                state.pending.contains('mcp') ||
                    state.pending.contains('mcp:${server.id}')
                ? null
                : () => onReconnectMcp(server.id),
          ),
        ),
      _GroupHeading(title: context.l10n.statusLspSection, sync: state.lspSync),
      if (state.lsp.isEmpty && state.lspSync.isReady)
        _EmptyRow(label: context.l10n.settingsLspEmptyTitle),
      for (final server in state.lsp)
        _ServiceRow(
          key: StudioDriverKeys.statusLspServer(server.id),
          icon: Icons.terminal_outlined,
          name: server.name,
          status: server.status,
          percentage: server.percentage,
          diagnostic: state.errors['lsp:${server.id}'] ?? server.diagnostic,
          action: server.canReconnect
              ? _ReconnectButton(
                  key: StudioDriverKeys.lspResetServer(server.id),
                  pending: state.pending.contains('lsp:${server.id}'),
                  error: state.errors['lsp:${server.id}'],
                  onPressed: state.pending.contains('lsp:${server.id}')
                      ? null
                      : () => onReconnectLsp(server.id),
                )
              : null,
        ),
    ],
  );
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.title, this.action, this.sync});
  final String title;
  final Widget? action;
  final DomainSyncStatus? sync;

  @override
  Widget build(BuildContext context) {
    final sync = this.sync;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium,
            ),
          ),
          if (sync != null && !sync.isReady)
            Tooltip(
              message: sync.errorMessage ?? _syncLabel(context, sync.phase),
              child: Icon(
                sync.phase == DomainSyncPhase.failed
                    ? Icons.error_outline
                    : Icons.sync,
                size: 14,
                color: sync.phase == DomainSyncPhase.failed
                    ? context.colors.error
                    : context.colors.onSurfaceVariant,
                semanticLabel: _syncLabel(context, sync.phase),
              ),
            ),
          ?action,
        ],
      ),
    );
  }
}

String _syncLabel(BuildContext context, DomainSyncPhase phase) =>
    switch (phase) {
      DomainSyncPhase.failed => context.l10n.settingsLspPhaseFailed,
      DomainSyncPhase.ready => context.l10n.settingsLspPhaseReady,
      _ => context.l10n.settingsStateChecking,
    };

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    ),
  );
}

class _ReconnectButton extends StatelessWidget {
  const _ReconnectButton({
    required this.pending,
    required this.onPressed,
    this.error,
    super.key,
  });
  final bool pending;
  final String? error;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: error == null
        ? context.l10n.settingsMcpReconnect
        : '${context.l10n.settingsLspPhaseFailed}: $error',
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
    onPressed: onPressed,
    icon: pending
        ? const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          )
        : Icon(
            error == null ? Icons.refresh : Icons.error_outline,
            size: 16,
            color: error == null ? null : context.colors.error,
          ),
  );
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.icon,
    required this.name,
    this.status,
    this.percentage,
    this.diagnostic,
    this.action,
    super.key,
  });
  final IconData icon;
  final String name;
  final StartedServiceStatus? status;
  final int? percentage;
  final String? diagnostic;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final tone = switch (status) {
      StartedServiceStatus.ready => StudioTone.success,
      StartedServiceStatus.failed ||
      StartedServiceStatus.unsupported => StudioTone.error,
      StartedServiceStatus.checking ||
      StartedServiceStatus.loading ||
      StartedServiceStatus.probing ||
      StartedServiceStatus.starting ||
      StartedServiceStatus.initializing ||
      StartedServiceStatus.connecting ||
      StartedServiceStatus.stopping ||
      StartedServiceStatus.indexing ||
      StartedServiceStatus.busy => StudioTone.warning,
      _ => StudioTone.neutral,
    };
    final label = status == null ? '' : _statusLabel(context, status);
    final progress = percentage;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: 15, color: tone.indicator(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: name,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Tooltip(
                message: diagnostic?.isNotEmpty == true ? diagnostic! : label,
                child: Text(
                  '$label${progress == null ? '' : ' ${context.l10n.statusLspActivityPercentage(progress)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: tone.indicator(context),
                  ),
                ),
              ),
            ),
          ],
          ?action,
        ],
      ),
    );
  }
}

String _statusLabel(BuildContext context, StartedServiceStatus status) =>
    switch (status) {
      StartedServiceStatus.checking => context.l10n.settingsStateChecking,
      StartedServiceStatus.loading => context.l10n.settingsLspPhaseLoading,
      StartedServiceStatus.probing => context.l10n.settingsLspPhaseProbing,
      StartedServiceStatus.starting => context.l10n.settingsLspPhaseStarting,
      StartedServiceStatus.initializing =>
        context.l10n.settingsLspPhaseInitializing,
      StartedServiceStatus.connecting => context.l10n.statusServiceConnecting,
      StartedServiceStatus.stopping => context.l10n.statusServiceStopping,
      StartedServiceStatus.indexing => context.l10n.statusLspIndexing,
      StartedServiceStatus.busy => context.l10n.statusLspBusy,
      StartedServiceStatus.ready => context.l10n.settingsLspPhaseReady,
      StartedServiceStatus.failed => context.l10n.settingsLspPhaseFailed,
      StartedServiceStatus.disabled => context.l10n.settingsStateDisabled,
      StartedServiceStatus.unsupported => context.l10n.statusServiceUnsupported,
    };
