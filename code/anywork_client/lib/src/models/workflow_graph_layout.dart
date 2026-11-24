import 'dart:collection';
import 'dart:math' as math;

import 'package:anywork_client/src/modes/domain/mode_editor_models.dart'
    show WorkflowStateKind;
import 'package:anywork_client/src/models/runtime_models.dart';

/// Computes 0-based vertical topological depths for atomic states and places
/// terminal (`finalState`) nodes on the bottom layer (`maxAtomicDepth + 1`).
Map<String, int> computeVerticalWorkflowDepths(
  WorkflowRuntimeGraphSnapshotView graph,
) {
  final stateMap = <String, WorkflowRuntimeGraphStateView>{
    for (final s in graph.states) s.id: s,
  };
  final atomicAdj = <String, List<String>>{};
  for (final s in graph.states) {
    if (s.kind == WorkflowStateKind.atomic) {
      atomicAdj[s.id] = <String>[];
    }
  }
  for (final e in graph.edges) {
    final src = stateMap[e.sourceStateId];
    final dst = stateMap[e.targetStateId];
    if (src != null &&
        dst != null &&
        src.kind == WorkflowStateKind.atomic &&
        dst.kind == WorkflowStateKind.atomic) {
      atomicAdj[src.id]!.add(dst.id);
    }
  }

  final depths = <String, int>{};
  final queue = Queue<String>();
  if (stateMap[graph.initialStateId]?.kind == WorkflowStateKind.atomic) {
    depths[graph.initialStateId] = 0;
    queue.add(graph.initialStateId);
  }
  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    final nextDepth = depths[current]! + 1;
    for (final next in atomicAdj[current] ?? const <String>[]) {
      if (!depths.containsKey(next)) {
        depths[next] = nextDepth;
        queue.add(next);
      }
    }
  }

  var maxAtomicDepth = depths.values.fold<int>(-1, math.max);
  for (final s in graph.states) {
    if (s.kind == WorkflowStateKind.atomic && !depths.containsKey(s.id)) {
      maxAtomicDepth += 1;
      depths[s.id] = maxAtomicDepth;
    }
  }
  final terminalDepth = maxAtomicDepth < 0 ? 0 : maxAtomicDepth + 1;
  for (final s in graph.states) {
    if (s.kind == WorkflowStateKind.finalState) {
      depths[s.id] = terminalDepth;
    }
  }
  return depths;
}

/// Returns `true` when [edge] targets an atomic node at the same or earlier
/// topological depth (cross-branch or rework jump rather than downward flow).
bool isBackwardWorkflowEdge(
  WorkflowRuntimeGraphEdgeView edge,
  Map<String, int> depths,
  Set<String> finalStateIds,
) {
  if (finalStateIds.contains(edge.targetStateId)) {
    return false;
  }
  final sourceDepth = depths[edge.sourceStateId];
  final targetDepth = depths[edge.targetStateId];
  if (sourceDepth == null || targetDepth == null) {
    return false;
  }
  return targetDepth <= sourceDepth;
}

/// Computes pure top-to-bottom canvas coordinates for a runtime workflow graph,
/// centering sibling branches horizontally within each topological row.
Map<String, ({double x, double y})> verticalAutoLayoutOffsets(
  WorkflowRuntimeGraphSnapshotView graph, {
  double nodeWidth = 220,
  double horizontalGap = 24,
  double verticalGap = 56,
  double nodeHeight = 76,
  double paddingX = 24,
  double paddingY = 24,
}) {
  if (graph.states.isEmpty) {
    return const {};
  }
  final depths = computeVerticalWorkflowDepths(graph);
  final layers = <int, List<String>>{};
  for (final state in graph.states) {
    final depth = depths[state.id] ?? 0;
    layers.putIfAbsent(depth, () => <String>[]).add(state.id);
  }
  final sortedLayers = layers.keys.toList()..sort();
  var maxColumns = 1;
  for (final ids in layers.values) {
    if (ids.length > maxColumns) maxColumns = ids.length;
  }
  final totalWidth =
      maxColumns * nodeWidth + math.max(0, maxColumns - 1) * horizontalGap;

  final positions = <String, ({double x, double y})>{};
  for (final depth in sortedLayers) {
    final ids = layers[depth]!;
    final rowWidth =
        ids.length * nodeWidth + math.max(0, ids.length - 1) * horizontalGap;
    final startX = paddingX + (totalWidth - rowWidth) / 2;
    final y = paddingY + depth * (nodeHeight + verticalGap);
    for (var col = 0; col < ids.length; col += 1) {
      positions[ids[col]] = (
        x: startX + col * (nodeWidth + horizontalGap),
        y: y,
      );
    }
  }
  return positions;
}
