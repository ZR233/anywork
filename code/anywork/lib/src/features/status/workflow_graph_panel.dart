import 'dart:async';

import 'package:anywork_client/conversation.dart'
    show CurrentQueryScope, CurrentStateFieldReader, decodeCurrentWorkflowState;
import 'package:anywork_client/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/thread_session_store.dart';
import '../conversation/acp/view_models/acp_session_view_model.dart';
import '../conversation/timeline/view_models/timeline_view_model.dart';
import 'status_view.dart';

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
    final fgColor = expanded
        ? context.colors.primary
        : context.colors.onSurfaceVariant;
    final bgColor = expanded
        ? context.colors.primaryContainer.withValues(alpha: 0.45)
        : Colors.transparent;
    final borderColor = expanded
        ? context.colors.primary.withValues(alpha: 0.55)
        : context.colors.outlineVariant.withValues(alpha: 0.65);

    final pill = Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        key: const ValueKey('workflow-status-pill'),
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        onTap: onTap,
        child: SizedBox(
          height: 26,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  terminal
                      ? Icons.check_circle_outline
                      : Icons.account_tree_outlined,
                  size: 14,
                  color: fgColor,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    stateTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: fgColor,
                      fontWeight: expanded ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.chevron_right_rounded
                        : Icons.schema_outlined,
                    size: 14,
                    color: fgColor,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      selected: expanded,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(message: tooltip, excludeFromSemantics: true, child: pill),
    );
  }
}

/// Right-side panel rendering the active runtime workflow graph vertically with
/// live current/visited/forced/final state highlights.
class WorkflowGraphPanel extends StatefulWidget {
  const WorkflowGraphPanel({
    required this.onClose,
    this.graph,
    this.run,
    this.loading = false,
    this.error,
    this.onRetry,
    this.inDrawer = false,
    super.key,
  });

  final WorkflowRuntimeGraphSnapshotView? graph;
  final WorkflowRunView? run;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback onClose;
  final bool inDrawer;

  @override
  State<WorkflowGraphPanel> createState() => _WorkflowGraphPanelState();
}

class _WorkflowGraphPanelState extends State<WorkflowGraphPanel> {
  static const double _nodeWidth = 220;
  static const double _nodeHeight = 76;

  late final NodeFlowController<_RuntimeNodeData, _RuntimeEdgeData> _controller;
  String? _graphSignature;
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
    _syncGraph(force: true);
  }

  @override
  void didUpdateWidget(covariant WorkflowGraphPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final modeChanged = oldWidget.graph?.modeId != widget.graph?.modeId;
    final graphChanged = oldWidget.graph != widget.graph;
    final runChanged = oldWidget.run != widget.run;
    if (graphChanged || runChanged) {
      _syncGraph(force: true, refit: modeChanged);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncGraph({bool force = false, bool refit = false}) {
    final graph = widget.graph;
    final run = widget.run;
    final signature = Object.hash(graph, run).toString();
    if (!force && signature == _graphSignature) return;
    _graphSignature = signature;

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
      final isInitial = graph.initialStateId == state.id;
      nodes.add(
        Node<_RuntimeNodeData>(
          id: state.id,
          type: 'runtime-workflow-stage',
          position: Offset(point.x, point.y),
          size: const Size(_nodeWidth, _nodeHeight),
          locked: true,
          data: _RuntimeNodeData(
            state: state,
            isInitial: isInitial,
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
              const Spacer(),
              Text(
                state.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
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
    final graph = widget.graph;
    final run = widget.run;
    final rawModeId = run?.modeId ?? graph?.modeId ?? '';
    final modeName = (run?.modeDisplayName.trim().isNotEmpty == true)
        ? run!.modeDisplayName.trim()
        : (graph?.modeDisplayName.trim().isNotEmpty == true)
        ? graph!.modeDisplayName.trim()
        : (rawModeId.isEmpty ? '' : context.workflowModeLabel(rawModeId));
    final currentTitle = run == null
        ? null
        : (run.currentStateTitle.trim().isNotEmpty
              ? run.currentStateTitle.trim()
              : context.workflowStateLabel(run.currentStateId));

    return Material(
      key: const ValueKey('workflow-graph-panel'),
      color: context.colors.surfaceContainer,
      shape: widget.inDrawer
          ? null
          : Border(left: BorderSide(color: context.colors.outlineVariant)),
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              dense: true,
              leading: Icon(
                Icons.account_tree_outlined,
                color: context.colors.primary,
              ),
              title: Text(
                context.l10n.workflowGraphPanelTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: (modeName.isNotEmpty || currentTitle != null)
                  ? Text(
                      [
                        if (modeName.isNotEmpty) modeName,
                        ?currentTitle,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    )
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (graph != null && graph.states.isNotEmpty)
                    IconButton(
                      tooltip: context.l10n.modeEditorFitView,
                      icon: const Icon(Icons.fit_screen_outlined, size: 18),
                      onPressed: () => _controller.fitToView(),
                    ),
                  IconButton(
                    key: const ValueKey('workflow-graph-panel-close'),
                    tooltip: context.l10n.workflowGraphPanelCloseTooltip,
                    icon: const Icon(Icons.chevron_right),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.colors.outlineVariant),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
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
    return ClipRect(
      // vyuh_node_flow still reads the SDK Material theme.
      // ignore: deprecated_member_use
      child: MaterialUiCompatibilityBridge(
        child: RepaintBoundary(
          child: NodeFlowEditor<_RuntimeNodeData, _RuntimeEdgeData>(
            controller: _controller,
            theme: theme,
            behavior: NodeFlowBehavior.inspect,
            nodeBuilder: _buildNodeContent,
            portBuilder: (context, node, port) => PortWidget<_RuntimeNodeData>(
              port: port,
              theme: theme.portTheme,
              controller: _controller,
              nodeId: node.id,
              isOutput: port.type != PortType.input,
              nodeBounds: node.getBounds(),
              isConnected: _controller.connections.any(
                (c) =>
                    (c.sourceNodeId == node.id && c.sourcePortId == port.id) ||
                    (c.targetNodeId == node.id && c.targetPortId == port.id),
              ),
            ),
          ),
        ),
      ),
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
    required this.isInitial,
    required this.isCurrent,
    required this.isVisited,
    required this.isForcedCurrent,
  });

  final WorkflowRuntimeGraphStateView state;
  final bool isInitial;
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

/// Native thread connector loading the runtime workflow graph snapshot and
/// combining it with inline or deferred live [WorkflowRunView] state.
class ThreadWorkflowGraphPanelConnector extends ConsumerStatefulWidget {
  const ThreadWorkflowGraphPanelConnector({
    required this.threadId,
    required this.onClose,
    this.inDrawer = false,
    super.key,
  });

  final String threadId;
  final VoidCallback onClose;
  final bool inDrawer;

  @override
  ConsumerState<ThreadWorkflowGraphPanelConnector> createState() =>
      _ThreadWorkflowGraphPanelConnectorState();
}

class _ThreadWorkflowGraphPanelConnectorState
    extends ConsumerState<ThreadWorkflowGraphPanelConnector> {
  CurrentStateField? _field;
  CurrentQueryScope? _scope;
  WorkflowRunView? _deferredRun;
  WorkflowRuntimeGraphSnapshotView? _graph;
  Object? _graphKey;
  bool _loadingRun = false;
  bool _loadingGraph = false;
  Object? _graphError;
  int _runEpoch = 0;
  int _graphEpoch = 0;

  WorkflowRunView? _resolveRun(
    ThreadRuntimeView? runtime,
    WorkflowRunView? inlineRun,
  ) => runtime?.deferredField('workflow') == null ? inlineRun : _deferredRun;

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(_syncDeferredRun));
    unawaited(Future<void>.microtask(_syncGraph));
  }

  @override
  void didUpdateWidget(covariant ThreadWorkflowGraphPanelConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      _graph = null;
      _graphKey = null;
      unawaited(Future<void>.microtask(_syncDeferredRun));
      unawaited(Future<void>.microtask(_syncGraph));
    }
  }

  void _retireRunScope() {
    _runEpoch++;
    final scope = _scope;
    _scope = null;
    scope?.retire();
    if (scope != null) unawaited(scope.close());
  }

  Future<void> _syncDeferredRun() async {
    if (!mounted) return;
    final runtime = ref
        .read(threadSessionStoreProvider(widget.threadId))
        .runtime;
    final field = runtime?.deferredField('workflow');
    if (field == null) {
      _retireRunScope();
      _field = null;
      _deferredRun = null;
      _loadingRun = false;
      if (mounted) setState(() {});
      return;
    }
    if (_field == field && (_loadingRun || _deferredRun != null)) return;
    _retireRunScope();
    _field = field;
    _deferredRun = null;
    final lease = ref.read(timelineSessionOwnerProvider).lease(widget.threadId);
    if (lease == null || lease.isRetired) return;
    final epoch = ++_runEpoch;
    final scope = lease.openCurrentScope(generation: lease.generation);
    _scope = scope;
    _loadingRun = true;
    if (mounted) setState(() {});
    try {
      final run = decodeCurrentWorkflowState(await scope.readStateField(field))
          .currentRun;
      if (!mounted ||
          epoch != _runEpoch ||
          field != _field ||
          lease.isRetired) {
        return;
      }
      _deferredRun = run;
      unawaited(Future<void>.microtask(_syncGraph));
    } finally {
      if (epoch == _runEpoch) {
        _loadingRun = false;
        if (identical(_scope, scope)) _scope = null;
        scope.retire();
        unawaited(scope.close());
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _syncGraph({bool force = false}) async {
    if (!mounted) return;
    final runtime = ref
        .read(threadSessionStoreProvider(widget.threadId))
        .runtime;
    final inlineRun = ref
        .read(statusBarViewProvider(widget.threadId))
        ?.workflowRun;
    final run = _resolveRun(runtime, inlineRun);
    final key = (
      widget.threadId,
      run?.modeId,
      run?.graphRevision,
      run?.graphHash,
    );
    if (!force && key == _graphKey && (_loadingGraph || _graph != null)) {
      return;
    }
    _graphKey = key;
    final epoch = ++_graphEpoch;
    _loadingGraph = true;
    _graphError = null;
    if (mounted) setState(() {});
    try {
      final graph = await ref
          .read(anyworkClientProvider)
          .getThreadWorkflowGraph(widget.threadId);
      if (!mounted || epoch != _graphEpoch) return;
      _graph = graph;
    } catch (error) {
      if (!mounted || epoch != _graphEpoch) return;
      _graphError = error;
    } finally {
      if (epoch == _graphEpoch) {
        _loadingGraph = false;
        if (mounted) setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _graphEpoch++;
    _retireRunScope();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(
      threadSessionStoreProvider(widget.threadId)
          .select((state) => state.runtime),
    );
    final inlineRun = ref.watch(
      statusBarViewProvider(widget.threadId)
          .select((value) => value?.workflowRun),
    );
    final field = runtime?.deferredField('workflow');
    if (field != null && field != _field && !_loadingRun) {
      unawaited(Future<void>.microtask(_syncDeferredRun));
    }
    final run = _resolveRun(runtime, inlineRun);
    final nextKey = (
      widget.threadId,
      run?.modeId,
      run?.graphRevision,
      run?.graphHash,
    );
    if (nextKey != _graphKey && !_loadingGraph) {
      unawaited(Future<void>.microtask(_syncGraph));
    }
    return WorkflowGraphPanel(
      graph: _graph,
      run: run,
      loading: _loadingGraph || _loadingRun,
      error: _graphError,
      onRetry: () => unawaited(_syncGraph(force: true)),
      onClose: widget.onClose,
      inDrawer: widget.inDrawer,
    );
  }
}

/// ACP thread connector reading the workflow snapshot directly from
/// [acpConversationStateProvider], falling back to `getThreadWorkflowGraph`.
class AcpWorkflowGraphPanelConnector extends ConsumerStatefulWidget {
  const AcpWorkflowGraphPanelConnector({
    required this.threadId,
    required this.onClose,
    this.inDrawer = false,
    super.key,
  });

  final String threadId;
  final VoidCallback onClose;
  final bool inDrawer;

  @override
  ConsumerState<AcpWorkflowGraphPanelConnector> createState() =>
      _AcpWorkflowGraphPanelConnectorState();
}

class _AcpWorkflowGraphPanelConnectorState
    extends ConsumerState<AcpWorkflowGraphPanelConnector> {
  WorkflowRuntimeGraphSnapshotView? _fallbackGraph;
  bool _loadingFallback = false;
  Object? _fallbackError;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(_ensureFallbackIfNeeded));
  }

  @override
  void didUpdateWidget(covariant AcpWorkflowGraphPanelConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      _fallbackGraph = null;
      _fallbackError = null;
      unawaited(Future<void>.microtask(_ensureFallbackIfNeeded));
    }
  }

  Future<void> _ensureFallbackIfNeeded({bool force = false}) async {
    if (!mounted) return;
    final workflowState = ref
        .read(acpConversationStateProvider(widget.threadId))
        .value
        ?.workflowState;
    if (workflowState?.graph != null) return;
    if (!force && (_loadingFallback || _fallbackGraph != null)) return;
    final epoch = ++_epoch;
    _loadingFallback = true;
    _fallbackError = null;
    if (mounted) setState(() {});
    try {
      final graph = await ref
          .read(anyworkClientProvider)
          .getThreadWorkflowGraph(widget.threadId);
      if (!mounted || epoch != _epoch) return;
      _fallbackGraph = graph;
    } catch (error) {
      if (!mounted || epoch != _epoch) return;
      _fallbackError = error;
    } finally {
      if (epoch == _epoch) {
        _loadingFallback = false;
        if (mounted) setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workflowState = ref.watch(
      acpConversationStateProvider(widget.threadId)
          .select((value) => value.value?.workflowState),
    );
    final graph = workflowState?.graph ?? _fallbackGraph;
    return WorkflowGraphPanel(
      graph: graph,
      run: workflowState?.run,
      loading: graph == null && _loadingFallback,
      error: graph == null ? _fallbackError : null,
      onRetry: () => unawaited(_ensureFallbackIfNeeded(force: true)),
      onClose: widget.onClose,
      inDrawer: widget.inDrawer,
    );
  }
}
