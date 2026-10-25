import 'dart:async';

import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/studio_l10n.dart';
import '../../../platform/studio_platform.dart';
import '../state/collection_presentation.dart';
import '../state/workspace_header_state.dart';
import '../state/workspace_view_state.dart';
import '../view_models/workspace_header_view_model.dart';
import '../view_models/workspace_view_model.dart';
import '../views/workspace_header_view.dart';
import '../widgets/workspace_agent_menu.dart';
import '../widgets/workspace_cost_chip.dart';
import '../widgets/workspace_failure_notice.dart';
import '../widgets/workspace_host_menu.dart';
import 'workspace_host_actions.dart';

class WorkspaceHeaderConnector extends ConsumerWidget {
  const WorkspaceHeaderConnector({required this.workspace, super.key});
  final WorkspaceViewState workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidate = workspace.workspace.selection.needsOpen
        ? null
        : presentReadValue(workspace.selectedMetadata?.value);
    final selected = candidate?.id == workspace.workspace.selection.threadId
        ? candidate
        : null;
    final rootId = selected?.rootThreadId;
    final selectedRoot = selected?.isRoot == true && selected?.id == rootId
        ? selected
        : null;
    if (rootId == null) {
      return WorkspaceHeaderView(
        project: workspace.selectedProject,
        root: null,
      );
    }
    final provider = workspaceHeaderViewModelProvider(rootId);
    final value = ref.watch(provider);
    return value.when(
      loading: () => WorkspaceHeaderView(
        project: workspace.selectedProject,
        root: selectedRoot,
        actions: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return WorkspaceHeaderView(
          project: workspace.selectedProject,
          root: selectedRoot,
          notice: WorkspaceFailureNotice(
            failure: error,
            onRetry: () => ref.invalidate(provider),
          ),
        );
      },
      data: (header) => _header(context, ref, rootId, header),
    );
  }

  Widget _header(
    BuildContext context,
    WidgetRef ref,
    String rootId,
    WorkspaceHeaderState header,
  ) {
    final provider = workspaceHeaderViewModelProvider(rootId);
    final vm = ref.read(provider.notifier);
    Future<void> retryRoot() {
      if (!context.mounted || !identical(ref.read(provider.notifier), vm)) {
        return Future<void>.value();
      }
      final current = ref.read(provider).asData?.value;
      final active = ref
          .read(workspaceViewModelProvider)
          .asData
          ?.value
          .workspace;
      if (!identical(current?.root, header.root) ||
          active == null ||
          active.sealed ||
          active.selectionGeneration !=
              workspace.workspace.selectionGeneration ||
          active.selection != workspace.workspace.selection) {
        return Future<void>.value();
      }
      // The original family VM retains/captures this root's concrete borrow
      // and binding lifetime; never retry another root through a stale notice.
      return vm.retryRoot();
    }

    final candidate = presentReadValue(header.root.value);
    // Preserve only this root's last-known material, never a child or another
    // currently selected Thread when this original metadata demand fails.
    final root = candidate?.id == rootId && candidate?.isRoot == true
        ? candidate
        : null;
    final project = workspace.selectedProject;
    final window = presentWindow(header.agents.agents);
    final current =
        header.agents.agents is CurrentCollectionMirror<AgentDirectoryEntry> &&
        header.agents.projection.sync.phase == ResourceSyncPhase.ready &&
        header.agents.projection.header?.source.brief is ReadyObservedBrief;
    final complete = current && window?.complete == true;
    final apps = watchWorkspaceHostApps(ref);
    final source = presentReadValue(header.agents.sourceStatus);
    final sourceError = switch (source) {
      FailedProductSourceStatus(:final error) ||
      DegradedProductSourceStatus(:final error) => error,
      _ => null,
    };
    final rootErrors = <StudioFailure>{
      ?header.root.projection.sync.error,
      if (header.root.value case FailedReadValue(:final error)) error,
      ?header.root.readError,
    };
    final costError = switch (header.costs.cost) {
      FailedReadValue(:final error) => error,
      _ => header.costs.projection.sync.error,
    };
    final cost = presentReadValue<SessionCost?, SessionCostsReadRef>(
      header.costs.cost,
    );
    // Baseline header shows its action strip only for a Thread that actually
    // has directory entries; an empty directory keeps the heading alone.
    final threadAgents = presentRows(header.agents.agents)
        .where((agent) => agent.rootThreadId == rootId)
        .toList();
    return WorkspaceHeaderView(
      project: project,
      root: root,
      actions: threadAgents.isEmpty
          ? null
          : OverflowBar(
              spacing: 8,
              overflowSpacing: 4,
              overflowAlignment: OverflowBarAlignment.start,
              children: [
                WorkspaceAgentMenu(
                  agents: threadAgents,
                  complete: complete,
                  loading:
                      window?.loading == true ||
                      header.reading.contains('agents'),
                  current: current,
                  enabled: !workspace.workspace.sealed,
                  selectedThreadId: workspace.workspace.selection.threadId,
                  onSelect: (id) => unawaited(
                    ref
                        .read(workspaceViewModelProvider.notifier)
                        .selectAgentThread(id),
                  ),
                  onLoadMore: () => unawaited(vm.loadAgents()),
                ),
                WorkspaceCostChip(cost: cost),
                if (project != null && root != null)
                  WorkspaceHostMenu(
                    apps: apps,
                    targetDescription: project.sshAlias == null
                        ? root.workspacePath
                        : '${project.sshAlias}:${root.workspacePath}',
                    terminalUnavailable: isWindowsPlatform
                        ? context.l10n.sessionTerminalUnavailableWindows
                        : isLinuxPlatform
                        ? context.l10n.sessionTerminalUnavailableLinux
                        : context.l10n.sessionTerminalUnavailableGeneric,
                    onOpen: (action) => unawaited(
                      openWorkspaceInHost(context, ref, project, root, action),
                    ),
                  ),
              ],
            ),
      notice: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final error in rootErrors)
            WorkspaceFailureNotice(
              failure: error,
              onRetry: workspace.workspace.sealed
                  ? null
                  : () => unawaited(retryRoot()),
            ),
          if (costError != null)
            WorkspaceFailureNotice(
              failure: costError,
              onRetry: () => unawaited(vm.loadCosts()),
            ),
          if (header.agents.projection.sync.error case final error?)
            WorkspaceFailureNotice(
              failure: error,
              onRetry: () => unawaited(vm.loadAgents()),
            ),
          if (window?.error case final error?)
            WorkspaceFailureNotice(
              failure: error,
              onRetry: () => unawaited(vm.loadAgents()),
            ),
          for (final row
              in window?.rows.values ??
                  const <ReadValue<AgentDirectoryEntry, ProductEntityRef>>[])
            if (row case FailedReadValue(:final error))
              WorkspaceFailureNotice(
                failure: error,
                onRetry: () => unawaited(vm.loadAgents()),
              ),
          if (sourceError != null)
            WorkspaceSourceFailureNotice(failure: sourceError),
          for (final entry in header.readErrors.entries)
            WorkspaceFailureNotice(
              failure: entry.value,
              onRetry: entry.key == 'root' && workspace.workspace.sealed
                  ? null
                  : () => unawaited(switch (entry.key) {
                      'costs' => vm.loadCosts(),
                      'root' => retryRoot(),
                      'agent-source' => vm.loadAgentSource(),
                      _ => vm.loadAgents(),
                    }),
            ),
        ],
      ),
    );
  }
}
