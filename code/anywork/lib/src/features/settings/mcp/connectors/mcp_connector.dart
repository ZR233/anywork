import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/overlays/confirmation_view.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';
import '../../widgets/settings_source_status_view.dart';
import '../state/mcp_view_state.dart';
import '../view_models/mcp_view_model.dart';
import '../views/mcp_view.dart';

class McpConnector extends ConsumerWidget {
  const McpConnector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(mcpViewModelProvider).when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, stack) {
      if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
      return Column(children: [SelectableText(settingsFailureText(error)),
        TextButton(onPressed: () => ref.invalidate(mcpViewModelProvider), child: Text(context.l10n.runtimeFatalRetry))]);
    },
    data: (state) {
      final vm = ref.read(mcpViewModelProvider.notifier);
      final config = displayReadValue(state.configurationSource.mcpConfigurations) ?? [];
      final configCurrent = isCurrentRead(state.configurationSource.mcpConfigurations,
        state.configurationSource.projection.header?.reference, state.configurationSource.projection.stamp?.origin);
      final servers = displayCollectionRows(state.source.servers);
      return McpView(state: state, servers: servers, configuration: {for (final value in config) value.id: value},
        editableIds: {if (configCurrent) for (final value in config) value.id},
        hasMore: !collectionComplete(state.source.servers, state.source.projection.stamp?.origin),
        knownEmpty: servers.isEmpty && collectionComplete(state.source.servers, state.source.projection.stamp?.origin),
        errors: [
          for (final error in state.readIssues.values) settingsFailureText(error),
          if (state.source.projection.sync.error case final error?) settingsFailureText(error),
          if (state.configurationSource.projection.sync.error case final error?) settingsFailureText(error),
          if (displayCollection(state.source.servers)?.error case final error?) settingsFailureText(error),
          ..._errors(state.resetAllAction),
        ],
        serverErrors: {for (final server in servers) server.id: [
          ..._errors(state.resets[server.id]),
          for (final action in state.drafts[server.id]?.actions.values ?? <SettingsAction>[]) ..._errors(action),
        ]},
        sources: [
          SettingsSourceStatusView(title: context.l10n.settingsMcpTitle, brief: state.source.projection.header?.source.brief,
            read: state.source.sourceStatus, origin: state.source.projection.stamp?.origin,
            reference: state.source.projection.header?.source.status,
            readError: _failure(state.readIssues[McpReadField.runtimeStatus]), onRetry: () => unawaited(vm.refresh())),
          SettingsSourceStatusView(title: context.l10n.settingsAccountConnectionTitle,
            brief: state.configurationSource.projection.header?.source.brief, read: state.configurationSource.sourceStatus,
            origin: state.configurationSource.projection.stamp?.origin, reference: state.configurationSource.projection.header?.source.status,
            readError: _failure(state.readIssues[McpReadField.configurationStatus]), onRetry: () => unawaited(vm.refresh())),
        ],
        onRefresh: () => unawaited(vm.refresh()), onMore: () => unawaited(vm.loadMore()),
        onResetAll: () => unawaited(_resetAll(context, vm)), onReset: (id) => unawaited(vm.resetServer(id)),
        onEnabled: vm.setEnabled, onEndpoint: vm.setEndpoint, onComposing: vm.setComposing, onCommit: vm.commit);
    });

  String? _failure(StudioFailure? error) => error == null ? null : settingsFailureText(error);
  List<String> _errors(SettingsAction? action) => [
    if (action?.error case final error?) settingsFailureText(error),
    if (action?.observationError case final error?) settingsFailureText(error),
    if (action?.operation?.evidenceError case final error?) settingsFailureText(error),
  ];
  Future<void> _resetAll(BuildContext context, McpViewModel vm) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => ConfirmationView(
      title: context.l10n.settingsMcpResetConfirmTitle, body: context.l10n.settingsMcpResetConfirmBody,
      confirmLabel: context.l10n.settingsMcpResetConfirmAction, cancelLabel: context.l10n.settingsCancel,
      confirmKey: StudioDriverKeys.mcpResetAllConfirm, onConfirm: () => Navigator.pop(context, true),
      onCancel: () => Navigator.pop(context, false)));
    if (confirmed == true && context.mounted) await vm.resetAll();
  }
}
