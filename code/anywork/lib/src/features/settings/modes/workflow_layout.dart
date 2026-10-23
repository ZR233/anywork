import 'package:anywork_client/modes.dart';

/// Existing editor layout policy, independent of semantic graph ownership.
/// Persisted coordinates override the deterministic display-only fallback.
List<WorkflowNodePosition> workflowAutoLayout(WorkflowDefinition workflow) {
  final outgoing = <String, List<String>>{};
  for (final edge in workflow.transitions) {
    outgoing.putIfAbsent(edge.sourceStateId, () => []).add(edge.targetStateId);
  }
  final ids = workflow.states.map((state) => state.id).toSet();
  final depth = <String, int>{};
  if (ids.contains(workflow.initialStateId)) {
    depth[workflow.initialStateId] = 0;
    final queue = [workflow.initialStateId];
    for (var index = 0; index < queue.length; index++) {
      final source = queue[index];
      for (final target in outgoing[source] ?? const <String>[]) {
        if (!ids.contains(target) || depth.containsKey(target)) continue;
        depth[target] = depth[source]! + 1;
        queue.add(target);
      }
    }
  }
  final maxDepth = depth.values.fold(0, (previous, value) => value > previous ? value : previous);
  final rows = <int, int>{};
  return [for (final state in workflow.states) (() {
    final column = depth[state.id] ?? maxDepth + 1;
    final row = rows[column] ?? 0;
    rows[column] = row + 1;
    return WorkflowNodePosition(stateId: state.id, x: 48.0 + column * 288, y: 48.0 + row * 136);
  })()];
}

List<WorkflowNodePosition> resolvedWorkflowLayout(ModeDocument document) {
  final workflow = document.definition.workflow;
  if (workflow == null) return [];
  final saved = {for (final position in document.editor.nodes)
    if (position.x.isFinite && position.y.isFinite) position.stateId: position};
  return [for (final fallback in workflowAutoLayout(workflow)) saved[fallback.stateId] ?? fallback];
}

WorkflowNodePosition nextWorkflowPosition(ModeDocument document, String stateId) {
  final positions = resolvedWorkflowLayout(document);
  final maxX = positions.fold(0.0, (previous, node) => node.x > previous ? node.x : previous);
  final x = positions.isEmpty ? 48.0 : maxX + 288;
  return WorkflowNodePosition(stateId: stateId, x: x, y: 48);
}

String workflowEdgeId(String source, String target) => 'edge:$source->$target';
