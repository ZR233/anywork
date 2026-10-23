import 'package:anywork_client/modes.dart';
import 'package:flutter/material.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/mode_editor_state.dart';
import '../workflow_layout.dart';

class WorkflowCanvas extends StatefulWidget {
  const WorkflowCanvas({required this.document, required this.readOnly,
    required this.selection, required this.inspectorOpen, required this.onEdit,
    required this.onSelection, required this.onAddState, required this.onAddFinal,
    required this.onAddTransition, required this.onConfirmRemoveState,
    required this.onCreateTransition, required this.onValidate, required this.onEnable,
    required this.onInspector, required this.l10n, super.key});
  final AppLocalizations l10n;
  final ModeDocument document;
  final bool readOnly;
  final ModeEditorSelection selection;
  final bool inspectorOpen;
  final ValueChanged<ModeEdit> onEdit;
  final ValueChanged<ModeEditorSelection> onSelection;
  final VoidCallback onAddState;
  final VoidCallback onAddFinal;
  final VoidCallback onAddTransition;
  final Future<bool> Function(String id) onConfirmRemoveState;
  final void Function(String source, String target) onCreateTransition;
  final VoidCallback onValidate;
  final VoidCallback onEnable;
  final VoidCallback onInspector;
  @override
  State<WorkflowCanvas> createState() => _WorkflowCanvasState();
}

class _WorkflowCanvasState extends State<WorkflowCanvas> {
  late final _controller = NodeFlowController<WorkflowState, Object?>(
    config: NodeFlowConfig(minZoom: 0.35, maxZoom: 1.8, showAttribution: false));
  bool _projecting = false;
  String? _projectedModeId;

  @override
  void initState() { super.initState(); _project(); }
  @override
  void didUpdateWidget(covariant WorkflowCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document || oldWidget.selection != widget.selection ||
        oldWidget.readOnly != widget.readOnly || oldWidget.l10n != widget.l10n) _project();
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _project() {
    final workflow = widget.document.definition.workflow;
    final modeChanged = _projectedModeId != widget.document.definition.id.id;
    final hadNodes = _controller.nodeCount > 0;
    _projectedModeId = widget.document.definition.id.id;
    final positions = {for (final position in resolvedWorkflowLayout(widget.document)) position.stateId: position};
    _projecting = true;
    try {
      _controller.loadGraph(NodeGraph<WorkflowState, Object?>(
        viewport: _controller.viewport,
        nodes: [for (final state in workflow?.states ?? const <WorkflowState>[])
          Node<WorkflowState>(id: state.id, type: 'workflow-state',
            position: Offset(positions[state.id]!.x, positions[state.id]!.y),
            size: const Size(208, 92), data: state, locked: widget.readOnly,
            ports: [
              Port(id: 'in', name: widget.l10n.modeEditorPortIn, position: PortPosition.left, offset: const Offset(0, 46),
                type: PortType.input, multiConnections: true),
              if (state.kind == WorkflowStateKind.atomic)
                Port(id: 'out', name: widget.l10n.modeEditorPortOut, position: PortPosition.right, offset: const Offset(0, 46),
                  type: PortType.output, multiConnections: true),
            ]),
        ],
        connections: [for (final edge in workflow?.transitions ?? const <WorkflowTransition>[])
          if (positions.containsKey(edge.sourceStateId) && positions.containsKey(edge.targetStateId) &&
              workflow!.states.any((state) => state.id == edge.sourceStateId && state.kind == WorkflowStateKind.atomic))
            Connection<Object?>(id: workflowEdgeId(edge.sourceStateId, edge.targetStateId),
              sourceNodeId: edge.sourceStateId, sourcePortId: 'out',
              targetNodeId: edge.targetStateId, targetPortId: 'in', data: edge.guard,
              label: ConnectionLabel(text: edge.guard, id: 'label:${workflowEdgeId(edge.sourceStateId, edge.targetStateId)}', offset: -24)),
        ],
      ));
      _controller.setBehavior(widget.readOnly ? NodeFlowBehavior.inspect : NodeFlowBehavior.design);
    } finally { _projecting = false; }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final previousFocus = FocusManager.instance.primaryFocus;
      _projecting = true;
      try {
        switch (widget.selection) {
          case ModeNodeSelection(:final stateId):
            if (_controller.getNode(stateId) != null) _controller.selectNode(stateId);
          case ModeEdgeSelection(:final sourceStateId, :final targetStateId):
            final id = workflowEdgeId(sourceStateId, targetStateId);
            if (_controller.getConnection(id) != null) _controller.selectConnection(id);
          case NoModeSelection(): _controller.clearSelection();
        }
      } finally {
        _projecting = false;
        if (previousFocus != null && previousFocus != _controller.canvasFocusNode &&
            previousFocus.context != null && previousFocus.canRequestFocus) previousFocus.requestFocus();
      }
      if ((modeChanged || !hadNodes) && _controller.nodeCount > 0) _controller.fitToView();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final workflow = widget.document.definition.workflow;
    final editable = !widget.readOnly && workflow != null;
    final colors = Theme.of(context).colorScheme;
    final base = NodeFlowTheme.light;
    final theme = base.copyWith(backgroundColor: Colors.transparent,
      nodeTheme: base.nodeTheme.copyWith(backgroundColor: colors.surface,
        selectedBackgroundColor: colors.surfaceContainerHigh, highlightBackgroundColor: colors.surfaceContainer,
        borderColor: colors.outlineVariant, selectedBorderColor: colors.primary,
        highlightBorderColor: colors.primary, borderRadius: BorderRadius.circular(8),
        titleStyle: Theme.of(context).textTheme.titleSmall ?? const TextStyle(fontSize: 14),
        contentStyle: Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12)),
      gridTheme: base.gridTheme.copyWith(color: colors.outlineVariant, size: 18, thickness: 1, style: GridStyles.dots));
    return Column(children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        OutlinedButton(key: const ValueKey('mode-editor-add-state'), onPressed: editable ? widget.onAddState : null, child: Text(l10n.modeEditorStageAction)),
        OutlinedButton(key: const ValueKey('mode-editor-add-final'), onPressed: editable ? widget.onAddFinal : null, child: Text(l10n.modeEditorFinalLabel)),
        OutlinedButton(key: const ValueKey('mode-editor-add-transition'), onPressed: editable ? widget.onAddTransition : null, child: Text(l10n.modeEditorTransitionAction)),
        OutlinedButton(key: const ValueKey('mode-editor-validate'), onPressed: widget.onValidate, child: Text(l10n.modeEditorValidate)),
        OutlinedButton(key: const ValueKey('mode-editor-auto-layout'), onPressed: editable
          ? () => widget.onEdit(ModeEdit.nodePositions(workflowAutoLayout(workflow!))) : null, child: Text(l10n.modeEditorAutoLayout)),
        IconButton(key: const ValueKey('mode-editor-zoom-out'), onPressed: () => _controller.zoomBy(-0.15), tooltip: l10n.modeEditorZoomOut, icon: const Icon(Icons.remove)),
        IconButton(key: const ValueKey('mode-editor-zoom-in'), onPressed: () => _controller.zoomBy(0.15), tooltip: l10n.modeEditorZoomIn, icon: const Icon(Icons.add)),
        IconButton(key: const ValueKey('mode-editor-fit-view'), onPressed: _controller.fitToView, tooltip: l10n.modeEditorFitView, icon: const Icon(Icons.fit_screen)),
        IconButton(key: const ValueKey('mode-editor-toggle-inspector'), onPressed: widget.onInspector,
          tooltip: l10n.modeEditorFlowInspector, isSelected: widget.inspectorOpen, icon: const Icon(Icons.tune)),
      ]),
      const Divider(),
      Expanded(child: workflow == null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l10n.modeEditorNoWorkflow),
        if (!widget.readOnly) FilledButton(key: const ValueKey('mode-editor-enable-workflow'),
          onPressed: widget.onEnable, child: Text(l10n.modeEditorEnableWorkflow)),
      ])) : ClipRect(child: NodeFlowEditor<WorkflowState, Object?>(
        controller: _controller, theme: theme,
        behavior: widget.readOnly ? NodeFlowBehavior.inspect : NodeFlowBehavior.design,
        nodeBuilder: (context, node) => Padding(key: ValueKey('mode-editor-node-${node.id}'),
          padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(node.data.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(node.id, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (workflow.initialStateId == node.id) Text(l10n.modeEditorInitialBadge),
          ])),
        portBuilder: (context, node, port) => PortWidget<WorkflowState>(
          key: ValueKey('mode-editor-port-${node.id}-${port.id}'), port: port,
          theme: theme.portTheme, controller: _controller, nodeId: node.id,
          isOutput: port.type == PortType.output, nodeBounds: node.getBounds(),
          isConnected: _controller.connections.any((edge) =>
            edge.sourceNodeId == node.id && edge.sourcePortId == port.id ||
            edge.targetNodeId == node.id && edge.targetPortId == port.id)),
        labelBuilder: (context, connection, label, position, onTap) => GestureDetector(
          key: ValueKey('mode-editor-edge-${connection.id}'), onTap: onTap,
          child: Tooltip(message: label.text, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220),
            child: Text(label.text, maxLines: 1, overflow: TextOverflow.ellipsis)))),
        events: NodeFlowEvents<WorkflowState, Object?>(
          node: NodeEvents<WorkflowState>(
            onCreated: (node) {
              final known = widget.document.definition.workflow?.states.any((state) => state.id == node.id) ?? false;
              if (!_projecting && !known) {
                _controller.removeNode(node.id);
              }
            },
            onDragStop: (node) {
              if (widget.readOnly || _projecting) return;
              final position = node.position.value;
              final previous = widget.document.editor.nodes.where((old) => old.stateId == node.id).firstOrNull;
              if (previous != null && (Offset(previous.x, previous.y) - position).distance < 0.5) return;
              widget.onEdit(ModeEdit.nodePositions([
                for (final old in widget.document.editor.nodes) if (old.stateId != node.id) old,
                WorkflowNodePosition(stateId: node.id, x: position.dx, y: position.dy),
              ]));
            },
            onBeforeDelete: (node) => widget.onConfirmRemoveState(node.id),
            onDeleted: (node) { if (!_projecting) widget.onEdit(ModeEdit.removeState(node.id)); },
          ),
          connection: ConnectionEvents<WorkflowState, Object?>(
            onCreated: (edge) {
              if (_projecting || widget.readOnly) return;
              widget.onCreateTransition(edge.sourceNodeId, edge.targetNodeId);
              WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _project(); });
            },
            onDeleted: (edge) { if (!_projecting) widget.onEdit(ModeEdit.removeTransition(edge.sourceNodeId, edge.targetNodeId)); },
            onBeforeComplete: (completion) => workflow.transitions.any((edge) =>
              edge.sourceStateId == completion.sourceNode.id && edge.targetStateId == completion.targetNode.id)
                ? ConnectionValidationResult.deny(reason: l10n.modeEditorDuplicateTransition, showMessage: true)
                : ConnectionValidationResult.allow(),
            onBeforeDelete: (_) async => true,
          ),
          onSelectionChange: (selection) {
            if (_projecting) return;
            if (selection.nodes.isNotEmpty) widget.onSelection(ModeEditorSelection.node(stateId: selection.nodes.first.id));
            else if (selection.connections.isNotEmpty) {
              final edge = selection.connections.first;
              widget.onSelection(ModeEditorSelection.edge(sourceStateId: edge.sourceNodeId, targetStateId: edge.targetNodeId));
            } else widget.onSelection(const ModeEditorSelection.none());
          },
        ),
      ))),
    ]);
  }
}
