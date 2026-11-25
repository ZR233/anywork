import 'package:anywork_client/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../conversation/acp/view_models/acp_session_view_model.dart';
import '../conversation/workspace/deferred_runtime_fields.dart';
import 'status_view.dart';
import 'status_bar_item.dart';

/// Clickable status bar pill displaying the active workflow mode/state and
/// toggling the vertical workflow graph side panel.
class WorkflowStatusPill extends StatelessWidget {
  const WorkflowStatusPill({
    required this.stateTitle,
    required this.modeName,
    this.deleted = false,
    this.terminal = false,
    this.expanded = false,
    this.onTap,
    super.key,
  });

  final String stateTitle;
  final String modeName;
  final bool deleted;
  final bool terminal;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tooltip =
        '$modeName · $stateTitle${deleted ? ' · ${context.l10n.modeDeletedUsingSnapshot}' : ''}';
    return StatusBarButton(
      key: const ValueKey('workflow-status-pill'),
      icon: terminal ? Icons.check_circle_outline : Icons.account_tree_outlined,
      label: stateTitle,
      tooltip: tooltip,
      selected: expanded,
      onPressed: onTap,
    );
  }
}

/// Right-side panel rendering the active runtime workflow graph vertically with
/// live current/visited/forced/final state highlights.
class WorkflowGraphPanel extends StatefulWidget {
  const WorkflowGraphPanel({
    this.graph,
    this.run,
    this.loading = false,
    this.error,
    this.onRetry,
    super.key,
  });

  final WorkflowRuntimeGraphSnapshotView? graph;
  final WorkflowRunView? run;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  State<WorkflowGraphPanel> createState() => _WorkflowGraphPanelState();
}

class _WorkflowGraphPanelState extends State<WorkflowGraphPanel> {
  static const double _nodeWidth = 220;
  static const double _nodeHeight = 76;

  late final NodeFlowController<_RuntimeNodeData, _RuntimeEdgeData> _controller;
  bool _initialFitPending = true;

  @override
  void initState() {
    super.initState();
    _controller = NodeFlowController<_RuntimeNodeData, _RuntimeEdgeData>(
      config: NodeFlowConfig(
        minZoom: 0.35,
        maxZoom: 1.8,
        showAttribution: false,
      ),
    );
    _syncGraph();
  }

  @override
  void didUpdateWidget(covariant WorkflowGraphPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final modeChanged = oldWidget.graph?.modeId != widget.graph?.modeId;
    final graphChanged = oldWidget.graph != widget.graph;
    final runChanged = oldWidget.run != widget.run;
    if (graphChanged || runChanged) {
      _syncGraph(refit: modeChanged);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncGraph({bool refit = false}) {
    final graph = widget.graph;
    final run = widget.run;
    if (graph == null || graph.states.isEmpty) {
      _controller.loadGraph(
        const NodeGraph<_RuntimeNodeData, _RuntimeEdgeData>(),
      );
      return;
    }

    final offsets = verticalAutoLayoutOffsets(
      graph,
      nodeWidth: _nodeWidth,
      nodeHeight: _nodeHeight,
    );
    final depths = computeVerticalWorkflowDepths(graph);
    final stateMap = <String, WorkflowRuntimeGraphStateView>{
      for (final s in graph.states) s.id: s,
    };
    final finalIds = {
      for (final s in graph.states)
        if (s.kind == WorkflowStateKind.finalState) s.id,
    };
    final currentId = run?.currentStateId;
    final visitedIds = {...?run?.visitedStateIds};
    final forced = run?.lastTransitionForced ?? false;

    final nodes = <Node<_RuntimeNodeData>>[];
    for (final state in graph.states) {
      final point = offsets[state.id] ?? (x: 24.0, y: 24.0);
      final isCurrent = currentId == state.id;
      final isVisited = visitedIds.contains(state.id) && !isCurrent;
      nodes.add(
        Node<_RuntimeNodeData>(
          id: state.id,
          type: 'runtime-workflow-stage',
          position: Offset(point.x, point.y),
          size: const Size(_nodeWidth, _nodeHeight),
          locked: true,
          data: _RuntimeNodeData(
            state: state,
            isCurrent: isCurrent,
            isVisited: isVisited,
            isForcedCurrent: isCurrent && forced,
          ),
          ports: [
            Port(
              id: 'top',
              name: 'top',
              position: PortPosition.top,
              offset: Offset(_nodeWidth / 2, 0),
              type: PortType.input,
              multiConnections: true,
            ),
            Port(
              id: 'bottom',
              name: 'bottom',
              position: PortPosition.bottom,
              offset: Offset(_nodeWidth / 2, 0),
              type: PortType.output,
              multiConnections: true,
            ),
            Port(
              id: 'left',
              name: 'left',
              position: PortPosition.left,
              offset: Offset(0, _nodeHeight / 2),
              type: PortType.input,
              multiConnections: true,
            ),
            Port(
              id: 'right',
              name: 'right',
              position: PortPosition.right,
              offset: Offset(0, _nodeHeight / 2),
              type: PortType.both,
              multiConnections: true,
            ),
          ],
        ),
      );
    }

    final connections = <Connection<_RuntimeEdgeData>>[];
    final seenEdgeIds = <String>{};
    for (final edge in graph.edges) {
      if (!stateMap.containsKey(edge.sourceStateId) ||
          !stateMap.containsKey(edge.targetStateId) ||
          !seenEdgeIds.add(edge.id)) {
        continue;
      }
      final srcOffset = offsets[edge.sourceStateId];
      final dstOffset = offsets[edge.targetStateId];
      final sameRowForward =
          srcOffset != null &&
          dstOffset != null &&
          (srcOffset.y - dstOffset.y).abs() < 1.0 &&
          dstOffset.x > srcOffset.x;
      final backward =
          !sameRowForward && isBackwardWorkflowEdge(edge, depths, finalIds);
      final (sourcePortId, targetPortId) = sameRowForward
          ? ('right', 'left')
          : backward
          ? ('right', 'right')
          : ('bottom', 'top');
      connections.add(
        Connection<_RuntimeEdgeData>(
          id: edge.id,
          sourceNodeId: edge.sourceStateId,
          sourcePortId: sourcePortId,
          targetNodeId: edge.targetStateId,
          targetPortId: targetPortId,
          data: _RuntimeEdgeData(
            guard: edge.guard,
            isBackward: backward,
            isCrossBranch: sameRowForward,
          ),
        ),
      );
    }

    _controller.loadGraph(
      NodeGraph<_RuntimeNodeData, _RuntimeEdgeData>(
        nodes: nodes,
        connections: connections,
      ),
    );
    if (refit || _initialFitPending) {
      _initialFitPending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.nodeCount > 0) {
          _controller.fitToView();
        }
      });
    }
  }

  NodeFlowTheme _theme(BuildContext context) {
    final base = NodeFlowTheme.light;
    return base.copyWith(
      backgroundColor: Colors.transparent,
      nodeTheme: base.nodeTheme.copyWith(
        backgroundColor: Colors.transparent,
        selectedBackgroundColor: Colors.transparent,
        highlightBackgroundColor: Colors.transparent,
        borderColor: Colors.transparent,
        selectedBorderColor: Colors.transparent,
        highlightBorderColor: Colors.transparent,
        borderWidth: 0,
        selectedBorderWidth: 0,
      ),
      connectionTheme: base.connectionTheme.copyWith(
        color: context.colors.outline,
        selectedColor: context.colors.primary,
        strokeWidth: 1.6,
      ),
      portTheme: base.portTheme.copyWith(
        size: const Size(6, 6),
        color: context.colors.outlineVariant,
        connectedColor: context.colors.outline,
        borderColor: context.colors.surface,
      ),
      gridTheme: base.gridTheme.copyWith(
        color: context.colors.outlineVariant.withValues(alpha: 0.45),
        size: 20,
        thickness: 1,
        style: GridStyles.dots,
      ),
    );
  }

  Widget _buildNodeContent(BuildContext context, Node<_RuntimeNodeData> node) {
    final data = node.data;
    final state = data.state;
    final title = state.title.trim().isEmpty
        ? context.workflowStateLabel(state.id)
        : state.title;
    final isFinal = state.kind == WorkflowStateKind.finalState;

    final borderColor = data.isCurrent
        ? context.colors.primary
        : data.isVisited
        ? context.colors.primary.withValues(alpha: 0.45)
        : context.colors.outlineVariant;
    final bgColor = data.isCurrent
        ? context.colors.primaryContainer.withValues(alpha: 0.55)
        : data.isVisited
        ? context.colors.surfaceContainerHigh
        : context.colors.surface;

    return Container(
      key: ValueKey('workflow-graph-node-${state.id}'),
      width: _nodeWidth,
      height: _nodeHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        border: Border.all(
          color: borderColor,
          width: data.isCurrent ? 2.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isFinal
                    ? Icons.flag_outlined
                    : data.isVisited
                    ? Icons.check_circle_outline
                    : data.isCurrent
                    ? Icons.radio_button_checked
                    : Icons.circle_outlined,
                size: 14,
                color: data.isCurrent || data.isVisited
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: data.isCurrent
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (data.isCurrent)
                _NodeBadge(
                  key: ValueKey('workflow-graph-current-${state.id}'),
                  label: context.l10n.workflowGraphStateCurrent,
                  background: context.colors.primary,
                  foreground: context.colors.onPrimary,
                )
              else if (data.isVisited)
                _NodeBadge(
                  label: context.l10n.workflowGraphStateVisited,
                  background: context.colors.secondaryContainer,
                  foreground: context.colors.onSecondaryContainer,
                )
              else if (isFinal)
                _NodeBadge(
                  label: context.l10n.workflowGraphStateFinal,
                  background: context.colors.surfaceContainerHighest,
                  foreground: context.colors.onSurfaceVariant,
                ),
              if (data.isForcedCurrent) ...[
                const SizedBox(width: 4),
                _NodeBadge(
                  label: context.l10n.workflowGraphStateForced,
                  background: StudioTone.warning.indicator(context),
                  foreground: context.colors.surface,
                ),
              ],
              Expanded(
                child: Text(
                  state.id,
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('workflow-graph-panel'),
      color: context.colors.surfaceContainerLowest,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.loading && widget.graph == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null && widget.graph == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.workflowGraphPanelLoadFailed,
                textAlign: TextAlign.center,
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: widget.onRetry,
                  child: Text(context.l10n.workflowGraphPanelRetry),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final graph = widget.graph;
    if (graph == null || graph.states.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            context.l10n.workflowGraphPanelEmpty,
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final theme = _theme(context);
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            // vyuh_node_flow still reads the SDK Material theme.
            // ignore: deprecated_member_use
            child: MaterialUiCompatibilityBridge(
              child: RepaintBoundary(
                child: NodeFlowEditor<_RuntimeNodeData, _RuntimeEdgeData>(
                  controller: _controller,
                  theme: theme,
                  behavior: NodeFlowBehavior.inspect,
                  nodeBuilder: _buildNodeContent,
                  portBuilder: (context, node, port) =>
                      PortWidget<_RuntimeNodeData>(
                        port: port,
                        theme: theme.portTheme,
                        controller: _controller,
                        nodeId: node.id,
                        isOutput: port.type != PortType.input,
                        nodeBounds: node.getBounds(),
                        isConnected: _controller.connections.any(
                          (c) =>
                              (c.sourceNodeId == node.id &&
                                  c.sourcePortId == port.id) ||
                              (c.targetNodeId == node.id &&
                                  c.targetPortId == port.id),
                        ),
                      ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Material(
            color: context.colors.surfaceContainerLowest.withValues(
              alpha: 0.92,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(StudioRadii.sm),
              side: BorderSide(color: context.colors.outlineVariant),
            ),
            child: IconButton(
              key: const ValueKey('workflow-graph-fit-view'),
              visualDensity: VisualDensity.compact,
              tooltip: context.l10n.modeEditorFitView,
              icon: const Icon(Icons.fit_screen_outlined, size: 18),
              onPressed: () => _controller.fitToView(),
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeBadge extends StatelessWidget {
  const _NodeBadge({
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(StudioRadii.xs),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

final class _RuntimeNodeData {
  const _RuntimeNodeData({
    required this.state,
    required this.isCurrent,
    required this.isVisited,
    required this.isForcedCurrent,
  });

  final WorkflowRuntimeGraphStateView state;
  final bool isCurrent;
  final bool isVisited;
  final bool isForcedCurrent;
}

final class _RuntimeEdgeData {
  const _RuntimeEdgeData({
    required this.guard,
    required this.isBackward,
    required this.isCrossBranch,
  });

  final String guard;
  final bool isBackward;
  final bool isCrossBranch;
}

// The RPC accepts only a thread ID. The other fields identify the requested
// graph locally, since the snapshot has no revision or hash.
typedef _WorkflowGraphRequest = ({
  String threadId,
  String? modeId,
  int? revision,
  String? hash,
});

final _workflowGraphProvider = FutureProvider.autoDispose
    .family<WorkflowRuntimeGraphSnapshotView?, _WorkflowGraphRequest>(
      (ref, request) => ref
          .watch(anyworkClientProvider)
          .getThreadWorkflowGraph(request.threadId),
      retry: (_, _) => null,
    );

/// Native thread connector combining the graph snapshot with the current run.
class ThreadWorkflowGraphPanelConnector extends ConsumerWidget {
  const ThreadWorkflowGraphPanelConnector({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inline = ref.watch(
      statusBarViewProvider(threadId).select((value) => value?.workflowRun),
    );
    final currentRun = deferredWorkflowRunProvider(threadId);
    final deferred = ref.watch(hasDeferredWorkflowProvider(threadId))
        ? ref.watch(currentRun)
        : null;
    if (deferred != null && (deferred.isLoading || deferred.hasError)) {
      return WorkflowGraphPanel(
        loading: deferred.isLoading,
        error: deferred.asError?.error,
        onRetry: () => ref.invalidate(currentRun),
      );
    }
    return _buildRpcWorkflowGraphPanel(
      ref,
      threadId,
      run: deferred == null ? inline : deferred.asData?.value,
    );
  }
}

/// ACP uses its observed graph whenever the Client has one.
class AcpWorkflowGraphPanelConnector extends ConsumerWidget {
  const AcpWorkflowGraphPanelConnector({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflow = ref.watch(
      acpConversationStateProvider(threadId)
          .select((value) => value.value?.workflowState),
    );
    if (workflow == null) return const WorkflowGraphPanel();
    if (workflow.graph case final graph?) {
      return WorkflowGraphPanel(graph: graph, run: workflow.run);
    }
    return _buildRpcWorkflowGraphPanel(
      ref,
      threadId,
      run: workflow.run,
      modeId: workflow.modeId,
    );
  }
}

WorkflowGraphPanel _buildRpcWorkflowGraphPanel(
  WidgetRef ref,
  String threadId, {
  required WorkflowRunView? run,
  String? modeId,
}) {
  final graphQuery = _workflowGraphProvider((
    threadId: threadId,
    modeId: run?.modeId ?? modeId,
    revision: run?.graphRevision,
    hash: run?.graphHash,
  ));
  final graph = ref.watch(graphQuery);
  return WorkflowGraphPanel(
    graph: graph.isLoading ? null : graph.asData?.value,
    run: run,
    loading: graph.isLoading,
    error: graph.asError?.error,
    onRetry: () => ref.invalidate(graphQuery),
  );
}
