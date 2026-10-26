import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/studio_l10n.dart';
import '../../workspace/view_models/workspace_view_model.dart';
import '../projections/selector_values.dart';
import '../view_models/selector_catalog_view_model.dart';
import '../views/session_status_view.dart';

class SessionStatusConnector extends ConsumerWidget {
  const SessionStatusConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceViewModelProvider).value;
    final catalog = ref.watch(selectorCatalogViewModelProvider);
    if (workspace == null) return const SizedBox.shrink();
    final metadata = workspace.selectedMetadata;
    final read = metadata?.value;
    final thread =
        metadata?.projection.sync.phase == ResourceSyncPhase.ready &&
            read is ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef> &&
            read.current.origin == metadata?.projection.stamp?.origin
        ? read.current.value
        : null;
    final selected = projectSelectedSession(
      selection: workspace.workspace.selection,
      metadata: thread,
      agents: workspace.agents.projection.sync.phase == ResourceSyncPhase.ready
          ? selectorRows(
              workspace.agents.agents,
              workspace.agents.projection.stamp?.origin,
            )
          : const [],
    );
    final frozenModel =
        selected.agent?.frozenModel ?? selected.thread?.frozenModel;
    return catalog.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, stack) => Text(error.toString()),
      data: (catalog) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SessionStatusView(
            selection: selected,
            modes: selectorModes(catalog),
            model: frozenModel == null
                ? null
                : selectedDescriptor(
                    catalog.models,
                    frozenModel.model.accountId,
                    frozenModel.model.modelId,
                  ),
          ),
          for (final error in catalog.errors.values) Text(error.message),
          if (catalog.models.projection.sync.error case final error?)
            Text(error.message),
          if (catalog.modes.projection.sync.error case final error?)
            Text(error.message),
          if (catalog.reading.isNotEmpty) const LinearProgressIndicator(),
          if (catalog.errors.isNotEmpty)
            TextButton(
              onPressed: catalog.reading.isNotEmpty
                  ? null
                  : () => unawaited(
                      ref
                          .read(selectorCatalogViewModelProvider.notifier)
                          .loadMore(),
                    ),
              child: Text(context.l10n.runtimeFatalRetry),
            ),
        ],
      ),
    );
  }
}
