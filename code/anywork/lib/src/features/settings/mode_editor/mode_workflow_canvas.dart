import 'package:anywork_client/studio_client.dart'
    show ModeDocument, WorkflowDefinition, WorkflowState, WorkflowStateKind;
import 'package:flutter/material.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'mode_editor_support.dart';

/// Native workflow canvas backed by the vyuh node flow free core.
///
/// The Client-owned [ModeDocument] stays the single business fact. The
/// controller is only a projection: document edits rebuild the graph while
/// retaining viewport and single selection.
class ModeWorkflowCanvas extends StatefulWidget {
  const ModeWorkflowCanvas({
    super.key,
    required this.document,
    required this.readOnly,
    required this.l10n,
    required this.onDocumentChanged,
    required this.onSelectNode,
    required this.onSelectEdge,
    required this.onAddState,
    required this.onAddFinalState,
    required this.onAddTransition,
    required this.onConfirmRemoveState,
    required this.onRemoveState,
    required this.onRemoveTransition,
    required this.onCreateTransition,
    required this.onAutoLayout,
    required this.onValidate,
    required this.onEnableWorkflow,
    required this.inspectorOpen,
    required this.onToggleInspector,
    this.selectedNodeId,
    this.selectedConnectionId,
  });

  final ModeDocument document;
  final bool readOnly;
  final AppLocalizations l10n;
  final ValueChanged<ModeDocument> onDocumentChanged;
  final ValueChanged<String?> onSelectNode;
  final ValueChanged<String?> onSelectEdge;
  final VoidCallback onAddState;
  final VoidCallback onAddFinalState;
  final VoidCallback onAddTransition;
  final Future<bool> Function(String stateId) onConfirmRemoveState;
  final ValueChanged<String> onRemoveState;
  final void Function(String sourceStateId, String targetStateId)
  onRemoveTransition;
  final void Function(String sourceStateId, String targetStateId)
  onCreateTransition;
  final VoidCallback onAutoLayout;
  final VoidCallback onValidate;
  final VoidCallback onEnableWorkflow;
  final bool inspectorOpen;
  final VoidCallback onToggleInspector;
  final String? selectedNodeId;
  final String? selectedConnectionId;

  @override
  State<ModeWorkflowCanvas> createState() => _ModeWorkflowCanvasState();
}

class _ModeWorkflowCanvasState extends State<ModeWorkflowCanvas> {
  // PortWidget creates an untyped, empty connection before the Client adds its
  // guard. Object? matches that component contract; execution data stays typed
  // in ModeDocument and the canvas stores only a display string here.
  late final NodeFlowController<_WorkflowNodeData, Object?> _controller;
  String? _signature;
  bool _syncingSelection = false;

  WorkflowDefinition? get _workflow => widget.document.definition.workflow;

  @override
  void initState() {
    super.initState();
    _controller = NodeFlowController<_WorkflowNodeData, Object?>(
      config: NodeFlowConfig(
        minZoom: 0.35,
        maxZoom: 1.8,
        showAttribution: false,
      ),
    );
    _controller.setBehavior(
      widget.readOnly ? NodeFlowBehavior.inspect : NodeFlowBehavior.design,
    );
    _syncGraph(force: true, modeChanged: true);
  }

  @override
  void didUpdateWidget(covariant ModeWorkflowCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final modeChanged =
        oldWidget.document.definition.id != widget.document.definition.id;
    final workflowPresenceChanged =
        (oldWidget.document.definition.workflow == null) !=
        (widget.document.definition.workflow == null);
    _syncGraph(force: workflowPresenceChanged, modeChanged: modeChanged);
    if (oldWidget.selectedNodeId != widget.selectedNodeId ||
        oldWidget.selectedConnectionId != widget.selectedConnectionId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncSelection());
    }
    if (oldWidget.readOnly != widget.readOnly) {
      _controller.setBehavior(
        widget.readOnly ? NodeFlowBehavior.inspect : NodeFlowBehavior.design,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncGraph({bool force = false, bool modeChanged = false}) {
    final workflow = _workflow;
    final controller = _controller;
    final signature = documentSignature(widget.document);
    if (!force && signature == _signature) return;
    if (workflow == null) {
      _syncingSelection = true;
      try {
        controller.loadGraph(const NodeGraph<_WorkflowNodeData, Object?>());
      } finally {
        _syncingSelection = false;
      }
      _signature = signature;
      return;
    }
    final hadNodes = controller.nodeCount > 0;
    final viewport = controller.viewport;
    // loadGraph clears selection synchronously. That projection update must
    // never emit a new user selection or rebuild the parent during its build.
    _syncingSelection = true;
    try {
      controller.loadGraph(
        NodeGraph<_WorkflowNodeData, Object?>(
          nodes: _buildNodes(widget.document),
          connections: _buildConnections(widget.document),
          viewport: viewport,
        ),
      );
    } finally {
      _syncingSelection = false;
    }
    _signature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSelection());
    if ((modeChanged || !hadNodes) && controller.nodeCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.fitToView();
      });
    }
  }

  void _syncSelection() {
    if (!mounted) return;
    final previousFocus = FocusManager.instance.primaryFocus;
    var changedSelection = false;
    _syncingSelection = true;
    try {
      final nodeId = widget.selectedNodeId;
      final edgeId = widget.selectedConnectionId;
      if (nodeId != null && _controller.getNode(nodeId) != null) {
        if (!_controller.selectedNodeIds.contains(nodeId)) {
          changedSelection = true;
          _controller.selectNode(nodeId);
        }
      } else if (edgeId != null && _controller.getConnection(edgeId) != null) {
        if (!_controller.selectedConnectionIds.contains(edgeId)) {
          changedSelection = true;
          _controller.selectConnection(edgeId);
        }
      } else {
        _controller.clearSelection();
      }
    } finally {
      _syncingSelection = false;
      // Controller selection requests canvas focus. A projection refresh must
      // keep the user's cursor in the property field they are editing.
      if (changedSelection &&
          previousFocus != null &&
          previousFocus != _controller.canvasFocusNode &&
          previousFocus.context != null &&
          previousFocus.canRequestFocus) {
        previousFocus.requestFocus();
      }
    }
  }

  List<Node<_WorkflowNodeData>> _buildNodes(ModeDocument document) {
    final workflow = document.definition.workflow;
    if (workflow == null) return const [];
    final positions = resolvedNodePositions(document);
    final seen = <String>{};
    final nodes = <Node<_WorkflowNodeData>>[];
    for (final state in workflow.states) {
      if (!seen.add(state.id)) continue;
      final position = positions[state.id] ?? const Offset(48, 48);
      nodes.add(_buildNode(state, position, workflow));
    }
    return nodes;
  }

  Node<_WorkflowNodeData> _buildNode(
    WorkflowState state,
    Offset position,
    WorkflowDefinition workflow,
  ) {
    final atomic = state.kind == WorkflowStateKind.atomic;
    return Node<_WorkflowNodeData>(
      id: state.id,
      type: 'workflow-state',
      position: position,
      size: const Size(208, 92),
      data: _WorkflowNodeData(
        state: state,
        initial: workflow.initialStateId == state.id,
      ),
      locked: widget.readOnly,
      ports: [
        Port(
          id: 'in',
          name: widget.l10n.modeEditorPortIn,
          position: PortPosition.left,
          offset: const Offset(0, 46),
          type: PortType.input,
          multiConnections: true,
        ),
        if (atomic)
          Port(
            id: 'out',
            name: widget.l10n.modeEditorPortOut,
            position: PortPosition.right,
            offset: const Offset(0, 46),
            type: PortType.output,
            multiConnections: true,
          ),
      ],
    );
  }

  List<Connection<Object?>> _buildConnections(ModeDocument document) {
    final workflow = document.definition.workflow;
    if (workflow == null) return const [];
    final stateIds = workflow.states.map((state) => state.id).toSet();
    final atomicIds = workflow.states
        .where((state) => state.kind == WorkflowStateKind.atomic)
        .map((state) => state.id)
        .toSet();
    final seen = <String>{};
    final connections = <Connection<Object?>>[];
    for (final transition in workflow.transitions) {
      if (!stateIds.contains(transition.sourceStateId) ||
          !stateIds.contains(transition.targetStateId) ||
          !atomicIds.contains(transition.sourceStateId)) {
        continue;
      }
      final id = connectionId(transition);
      if (!seen.add(id)) continue;
      connections.add(
        Connection<Object?>(
          id: id,
          sourceNodeId: transition.sourceStateId,
          sourcePortId: 'out',
          targetNodeId: transition.targetStateId,
          targetPortId: 'in',
          data: transition.guard,
          label: ConnectionLabel(
            text: _edgeLabel(transition.guard),
            id: 'label:$id',
            offset: -24,
          ),
        ),
      );
    }
    return connections;
  }

  String _edgeLabel(String guard) {
    final trimmed = guard.trim();
    if (trimmed.isEmpty) return widget.l10n.modeEditorGuardRequiredShort;
    if (trimmed.length <= 34) return trimmed;
    return '${trimmed.substring(0, 34)}…';
  }

  void _onNodeMoved(Node<_WorkflowNodeData> node) {
    if (widget.readOnly) return;
    final workflow = _workflow;
    if (workflow == null) return;
    final position = node.position.value;
    Offset? existing;
    for (final entry in widget.document.editor.nodes) {
      if (entry.stateId == node.id) {
        existing = Offset(entry.x, entry.y);
        break;
      }
    }
    if (existing != null && (existing - position).distance < 0.5) return;
    widget.onDocumentChanged(
      setNodePosition(widget.document, node.id, position),
    );
  }

  void _onConnectionCreated(Connection<Object?> connection) {
    final workflow = _workflow;
    if (workflow == null) return;
    final source = connection.sourceNodeId;
    final target = connection.targetNodeId;
    if (workflow.transitions.any(
      (transition) =>
          transition.sourceStateId == source &&
          transition.targetStateId == target,
    )) {
      return;
    }
    widget.onCreateTransition(source, target);
  }

  void _onConnectionDeleted(Connection<Object?> connection) {
    widget.onRemoveTransition(connection.sourceNodeId, connection.targetNodeId);
  }

  ConnectionValidationResult _validateConnection(
    ConnectionCompleteContext<_WorkflowNodeData> context,
  ) {
    final workflow = _workflow;
    if (workflow == null) {
      return ConnectionValidationResult.deny();
    }
    final source = context.sourceNode.id;
    final target = context.targetNode.id;
    final duplicate = workflow.transitions.any(
      (transition) =>
          transition.sourceStateId == source &&
          transition.targetStateId == target,
    );
    if (duplicate) {
      return ConnectionValidationResult.deny(
        reason: widget.l10n.modeEditorDuplicateTransition,
        showMessage: true,
      );
    }
    return ConnectionValidationResult.allow();
  }

  NodeFlowTheme _theme(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? NodeFlowTheme.dark
        : NodeFlowTheme.light;
    return base.copyWith(
      backgroundColor: Colors.transparent,
      nodeTheme: base.nodeTheme.copyWith(
        backgroundColor: context.colors.surface,
        selectedBackgroundColor: context.colors.surfaceContainerHigh,
        highlightBackgroundColor: context.colors.surfaceContainer,
        borderColor: context.colors.outlineVariant,
        selectedBorderColor: context.colors.primary,
        highlightBorderColor: context.colors.primary.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        borderWidth: 1,
        selectedBorderWidth: 2,
        titleStyle:
            context.text.titleSmall?.copyWith(
              color: context.colors.onSurface,
              fontWeight: FontWeight.w600,
            ) ??
            const TextStyle(fontSize: 14),
        contentStyle:
            context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ) ??
            const TextStyle(fontSize: 12),
      ),
      gridTheme: base.gridTheme.copyWith(
        color: context.colors.outlineVariant,
        size: 18,
        thickness: 1,
        style: GridStyles.dots,
      ),
    );
  }

  Widget _buildNodeContent(BuildContext context, Node<_WorkflowNodeData> node) {
    final data = node.data;
    final finalState = data.state.kind == WorkflowStateKind.finalState;
    return Container(
      key: ModeEditorKeys.node(data.state.id),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: Colors.transparent,
      child: Row(
        children: [
          Icon(
            finalState ? Icons.flag_outlined : Icons.account_tree_outlined,
            size: 17,
            color: finalState
                ? context.colors.onSurfaceVariant
                : context.colors.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.state.title.isEmpty
                            ? data.state.id
                            : data.state.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(
                          color: context.colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (data.initial)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.primaryContainer,
                          borderRadius: BorderRadius.circular(StudioRadii.pill),
                        ),
                        child: Text(
                          widget.l10n.modeEditorInitialBadge,
                          style: context.text.labelSmall?.copyWith(
                            color: context.colors.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  data.state.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(
    BuildContext context,
    Connection<Object?> connection,
    ConnectionLabel label,
    Rect position,
    VoidCallback? onTap,
  ) {
    // The library owns label placement. Returning another Positioned here
    // breaks its UnboundedStack parent-data contract.
    return Tooltip(
      message: connection.data as String? ?? label.text,
      child: GestureDetector(
        key: ModeEditorKeys.edge(connection.id),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerHigh,
            border: Border.all(color: context.colors.outlineVariant),
            borderRadius: BorderRadius.circular(StudioRadii.xs),
          ),
          child: Text(
            label.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final l10n = widget.l10n;
    final editable = !widget.readOnly && _workflow != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            key: ModeEditorKeys.addState,
            onPressed: editable ? widget.onAddState : null,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.modeEditorStageAction),
          ),
          OutlinedButton.icon(
            key: ModeEditorKeys.addFinalState,
            onPressed: editable ? widget.onAddFinalState : null,
            icon: const Icon(Icons.flag_outlined, size: 16),
            label: Text(l10n.modeEditorFinalLabel),
          ),
          OutlinedButton.icon(
            key: ModeEditorKeys.addTransition,
            onPressed: editable ? widget.onAddTransition : null,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(l10n.modeEditorTransitionAction),
          ),
          OutlinedButton.icon(
            key: ModeEditorKeys.validate,
            onPressed: _workflow == null ? null : widget.onValidate,
            icon: const Icon(Icons.fact_check_outlined, size: 16),
            label: Text(l10n.modeEditorValidate),
          ),
          OutlinedButton.icon(
            key: ModeEditorKeys.autoLayout,
            onPressed: editable ? widget.onAutoLayout : null,
            icon: const Icon(Icons.auto_awesome_mosaic_outlined, size: 16),
            label: Text(l10n.modeEditorAutoLayout),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: ModeEditorKeys.zoomOut,
            tooltip: l10n.modeEditorZoomOut,
            onPressed: () => _controller.zoomBy(-0.15),
            icon: const Icon(Icons.remove, size: 18),
          ),
          IconButton(
            key: ModeEditorKeys.zoomIn,
            tooltip: l10n.modeEditorZoomIn,
            onPressed: () => _controller.zoomBy(0.15),
            icon: const Icon(Icons.add, size: 18),
          ),
          IconButton(
            key: ModeEditorKeys.fitView,
            tooltip: l10n.modeEditorFitView,
            onPressed: () => _controller.fitToView(),
            icon: const Icon(Icons.fit_screen_outlined, size: 18),
          ),
          IconButton(
            key: ModeEditorKeys.toggleInspector,
            tooltip: l10n.modeEditorFlowInspector,
            isSelected: widget.inspectorOpen,
            onPressed: widget.onToggleInspector,
            icon: const Icon(Icons.tune, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final l10n = widget.l10n;
    return ColoredBox(
      color: context.colors.surfaceContainerLowest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 34,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.modeEditorNoWorkflow,
                  style: context.text.titleMedium?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.readOnly
                      ? l10n.modeEditorNoWorkflowReadOnlyHint
                      : l10n.modeEditorNoWorkflowEnableHint,
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                if (!widget.readOnly) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: ModeEditorKeys.enableWorkflow,
                    onPressed: widget.onEnableWorkflow,
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: Text(l10n.modeEditorEnableWorkflow),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final workflow = _workflow;
    return ColoredBox(
      color: context.colors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(context),
          Divider(height: 1, color: context.colors.outlineVariant),
          Expanded(
            child: workflow == null
                ? _emptyState(context)
                : ClipRect(
                    child: RepaintBoundary(
                      child: NodeFlowEditor<_WorkflowNodeData, Object?>(
                        controller: controller,
                        theme: _theme(context),
                        behavior: widget.readOnly
                            ? NodeFlowBehavior.inspect
                            : NodeFlowBehavior.design,
                        nodeBuilder: _buildNodeContent,
                        portBuilder: (context, node, port) =>
                            PortWidget<_WorkflowNodeData>(
                              key: ValueKey(
                                'mode-editor-port-${node.id}-${port.id}',
                              ),
                              port: port,
                              theme: _theme(context).portTheme,
                              controller: controller,
                              nodeId: node.id,
                              isOutput: port.type == PortType.output,
                              nodeBounds: node.getBounds(),
                              isConnected: controller.connections.any(
                                (connection) =>
                                    connection.sourceNodeId == node.id &&
                                        connection.sourcePortId == port.id ||
                                    connection.targetNodeId == node.id &&
                                        connection.targetPortId == port.id,
                              ),
                            ),
                        labelBuilder: _buildLabel,
                        events: NodeFlowEvents<_WorkflowNodeData, Object?>(
                          node: NodeEvents<_WorkflowNodeData>(
                            onCreated: (node) {
                              final workflow = _workflow;
                              final known =
                                  workflow != null &&
                                  workflow.states.any(
                                    (state) => state.id == node.id,
                                  );
                              if (!known) _controller.removeNode(node.id);
                            },
                            onDragStop: _onNodeMoved,
                            onBeforeDelete: (node) =>
                                widget.onConfirmRemoveState(node.id),
                            onDeleted: (node) => widget.onRemoveState(node.id),
                          ),
                          connection:
                              ConnectionEvents<_WorkflowNodeData, Object?>(
                                onCreated: _onConnectionCreated,
                                onDeleted: _onConnectionDeleted,
                                onBeforeComplete: _validateConnection,
                                onBeforeDelete: (_) async => true,
                              ),
                          onSelectionChange: (selection) {
                            if (_syncingSelection) return;
                            if (selection.nodes.isNotEmpty) {
                              widget.onSelectEdge(null);
                              widget.onSelectNode(selection.nodes.first.id);
                            } else if (selection.connections.isNotEmpty) {
                              widget.onSelectNode(null);
                              widget.onSelectEdge(
                                selection.connections.first.id,
                              );
                            } else {
                              widget.onSelectNode(null);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

final class _WorkflowNodeData {
  const _WorkflowNodeData({required this.state, required this.initial});

  final WorkflowState state;
  final bool initial;

  @override
  bool operator ==(Object other) =>
      other is _WorkflowNodeData &&
      other.initial == initial &&
      other.state.id == state.id &&
      other.state.title == state.title &&
      other.state.instructions == state.instructions &&
      other.state.kind == state.kind &&
      _sameCriteria(other.state.completionCriteria, state.completionCriteria);

  @override
  int get hashCode => Object.hash(
    state.id,
    state.title,
    state.instructions,
    state.kind,
    Object.hashAll(state.completionCriteria),
    initial,
  );

  static bool _sameCriteria(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
