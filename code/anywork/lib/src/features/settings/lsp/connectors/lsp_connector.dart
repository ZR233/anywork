import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';
import '../../view_models/collection_values.dart';
import '../state/lsp_view_state.dart';
import '../view_models/lsp_catalog_view_model.dart';
import '../view_models/lsp_view_model.dart';
import '../views/lsp_view.dart';

class LspConnector extends ConsumerWidget {
  const LspConnector({required this.projectId, super.key});
  final String? projectId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(lspCatalogViewModelProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
          return Column(
            children: [
              SelectableText(settingsFailureText(error)),
              TextButton(
                onPressed: () => ref.invalidate(lspCatalogViewModelProvider),
                child: Text(context.l10n.runtimeFatalRetry),
              ),
            ],
          );
        },
        data: (state) {
          final vm = ref.read(lspCatalogViewModelProvider.notifier);
          final id = projectId;
          final actions = id == null
              ? null
              : ref.watch(lspViewModelProvider(id));
          final actionFailure = actions?.asError;
          if (actionFailure != null && actionFailure.error is! StudioFailure) {
            Error.throwWithStackTrace(
              actionFailure.error,
              actionFailure.stackTrace,
            );
          }
          final actionVm = id != null && actions?.asData != null
              ? ref.read(lspViewModelProvider(id).notifier)
              : null;
          final servers = displayCollectionRows(state.source.servers);
          return LspView(
            catalog: state,
            actions: actions?.asData?.value,
            servers: servers,
            currentServerIds: {
              for (final server in servers)
                if (currentCollectionRow(
                      state.source.servers,
                      state.source.projection.stamp?.origin,
                      (item) => item.id == server.id,
                    ) !=
                    null)
                  server.id,
            },
            hasMore: !collectionComplete(
              state.source.servers,
              state.source.projection.stamp?.origin,
            ),
            errors: [
              for (final issue in state.readIssues.values)
                settingsFailureText(issue),
              if (state.source.projection.sync.error case final issue?)
                settingsFailureText(issue),
              if (displayCollection(state.source.servers)?.error
                  case final issue?)
                settingsFailureText(issue),
              if (actionFailure?.error case StudioFailure issue)
                settingsFailureText(issue),
              for (final kind in [
                LspActionKind.probe,
                LspActionKind.resetWorkspace,
              ])
                ..._errors(actions?.asData?.value.actions[(kind, null)]),
            ],
            serverErrors: {
              for (final server in servers)
                server.id: [
                  for (final kind in [
                    LspActionKind.repair,
                    LspActionKind.resetServer,
                  ])
                    ..._errors(
                      actions?.asData?.value.actions[(kind, server.id)],
                    ),
                ],
            },
            onRefresh: () => unawaited(vm.refresh()),
            onMore: () => unawaited(vm.loadMore()),
            onProbe: actionVm == null
                ? null
                : () => unawaited(actionVm.probe()),
            onResetWorkspace: actionVm == null
                ? null
                : () => unawaited(actionVm.resetWorkspace()),
            onRepair: actionVm == null
                ? null
                : (serverId) => unawaited(actionVm.repair(serverId)),
            onReset: actionVm == null
                ? null
                : (serverId) => unawaited(actionVm.resetServer(serverId)),
          );
        },
      );

  List<String> _errors(SettingsAction? action) => [
    if (action?.error case final error?) settingsFailureText(error),
    if (action?.observationError case final error?) settingsFailureText(error),
    if (action?.operation?.evidenceError case final error?)
      settingsFailureText(error),
  ];
}
