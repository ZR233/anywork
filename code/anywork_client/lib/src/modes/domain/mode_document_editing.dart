import 'dart:convert';
import 'dart:math' as math;

import '../../../models.dart';

/// 编辑布局中一个节点的坐标；纯数值类型保证 SDK 不依赖 Flutter。
typedef ModeNodePoint = ({double x, double y});

const maxModeWorkflowStates = 32;

final RegExp _modeIdPattern = RegExp(r'^mode\.[a-z0-9_-]+$');
final RegExp _stateIdPattern = RegExp(r'^[a-z0-9_-]+$');

bool isValidModeId(String value) =>
    value.length <= 64 && _modeIdPattern.hasMatch(value);

bool isValidStateId(String value) =>
    value.isNotEmpty && value.length <= 64 && _stateIdPattern.hasMatch(value);

WorkflowStateKind wireStateKind(String value) =>
    value == 'final' ? WorkflowStateKind.finalState : WorkflowStateKind.atomic;

String stateKindWire(WorkflowStateKind kind) =>
    kind == WorkflowStateKind.finalState ? 'final' : 'atomic';

List<String> parseCompletionCriteria(String raw) => raw
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList(growable: false);

String completionCriteriaText(WorkflowState state) =>
    state.completionCriteria.join('\n');

ModeDocument documentWithDefinition(
  ModeDocument document,
  ModeDefinition definition,
) => ModeDocument(definition: definition, editor: document.editor);

ModeDefinition definitionWith(
  ModeDefinition definition, {
  String? id,
  String? displayName,
  String? description,
  int? order,
  String? prompt,
  WorkflowDefinition? workflow,
  bool removeWorkflow = false,
}) => ModeDefinition(
  id: id ?? definition.id,
  displayName: displayName ?? definition.displayName,
  description: description ?? definition.description,
  order: order ?? definition.order,
  prompt: prompt ?? definition.prompt,
  workflow: removeWorkflow ? null : (workflow ?? definition.workflow),
);

ModeDocument documentWithWorkflow(
  ModeDocument document,
  WorkflowDefinition? workflow,
) => documentWithDefinition(
  document,
  definitionWith(
    document.definition,
    removeWorkflow: workflow == null,
    workflow: workflow,
  ),
);

WorkflowDefinition workflowWith(
  WorkflowDefinition workflow, {
  String? title,
  String? goal,
  String? initialStateId,
  List<WorkflowState>? states,
  List<WorkflowTransition>? transitions,
}) => WorkflowDefinition(
  title: title ?? workflow.title,
  goal: goal ?? workflow.goal,
  initialStateId: initialStateId ?? workflow.initialStateId,
  states: states ?? workflow.states,
  transitions: transitions ?? workflow.transitions,
);

WorkflowState stateWith(
  WorkflowState state, {
  String? id,
  String? title,
  String? instructions,
  List<String>? completionCriteria,
  WorkflowStateKind? kind,
}) => WorkflowState(
  id: id ?? state.id,
  title: title ?? state.title,
  instructions: instructions ?? state.instructions,
  completionCriteria: completionCriteria ?? state.completionCriteria,
  kind: kind ?? state.kind,
);

WorkflowTransition transitionWith(
  WorkflowTransition transition, {
  String? sourceStateId,
  String? targetStateId,
  String? guard,
}) => WorkflowTransition(
  sourceStateId: sourceStateId ?? transition.sourceStateId,
  targetStateId: targetStateId ?? transition.targetStateId,
  guard: guard ?? transition.guard,
);

ModeDefinition duplicateDefinition(
  ModeDefinition source, {
  required String id,
  required String displayName,
}) => ModeDefinition(
  id: id,
  displayName: displayName,
  description: source.description,
  order: source.order,
  prompt: source.prompt,
  workflow: source.workflow,
);

ModeDocument replaceState(
  ModeDocument document,
  String previousId,
  WorkflowState next,
) {
  final workflow = document.definition.workflow;
  if (workflow == null) return document;
  final renamed = previousId != next.id;
  final states = [
    for (final state in workflow.states)
      if (state.id == previousId) next else state,
  ];
  final transitions = [
    for (final transition in workflow.transitions)
      renamed
          ? transitionWith(
              transition,
              sourceStateId: transition.sourceStateId == previousId
                  ? next.id
                  : transition.sourceStateId,
              targetStateId: transition.targetStateId == previousId
                  ? next.id
                  : transition.targetStateId,
            )
          : transition,
  ];
  final positions = [
    for (final position in document.editor.nodes)
      renamed && position.stateId == previousId
          ? WorkflowNodePosition(stateId: next.id, x: position.x, y: position.y)
          : position,
  ];
  final nextWorkflow = workflowWith(
    workflow,
    states: states,
    transitions: transitions,
    initialStateId: renamed && workflow.initialStateId == previousId
        ? next.id
        : workflow.initialStateId,
  );
  return ModeDocument(
    definition: definitionWith(document.definition, workflow: nextWorkflow),
    editor: ModeEditorLayout(nodes: positions),
  );
}

ModeDocument addState(
  ModeDocument document,
  WorkflowState state,
  ModeNodePoint position,
) {
  final workflow = document.definition.workflow;
  if (workflow == null) return document;
  final nextWorkflow = workflowWith(
    workflow,
    states: [...workflow.states, state],
  );
  final positions = [
    for (final existing in document.editor.nodes)
      if (existing.stateId != state.id) existing,
    WorkflowNodePosition(stateId: state.id, x: position.x, y: position.y),
  ];
  return ModeDocument(
    definition: definitionWith(document.definition, workflow: nextWorkflow),
    editor: ModeEditorLayout(nodes: positions),
  );
}

ModeDocument removeState(ModeDocument document, String stateId) {
  final workflow = document.definition.workflow;
  if (workflow == null) return document;
  final states = workflow.states
      .where((state) => state.id != stateId)
      .toList(growable: false);
  final transitions = workflow.transitions
      .where(
        (transition) =>
            transition.sourceStateId != stateId &&
            transition.targetStateId != stateId,
      )
      .toList(growable: false);
  var initialStateId = workflow.initialStateId;
  if (initialStateId == stateId) {
    final atomic = states
        .where((state) => state.kind == WorkflowStateKind.atomic)
        .map((state) => state.id)
        .toList(growable: false);
    initialStateId = atomic.isNotEmpty
        ? atomic.first
        : (states.isNotEmpty ? states.first.id : '');
  }
  final nextWorkflow = workflowWith(
    workflow,
    states: states,
    transitions: transitions,
    initialStateId: initialStateId,
  );
  final positions = document.editor.nodes
      .where((position) => position.stateId != stateId)
      .toList(growable: false);
  return ModeDocument(
    definition: definitionWith(document.definition, workflow: nextWorkflow),
    editor: ModeEditorLayout(nodes: positions),
  );
}

ModeDocument replaceTransition(
  ModeDocument document,
  WorkflowTransition previous,
  WorkflowTransition next,
) {
  final workflow = document.definition.workflow;
  if (workflow == null) return document;
  final transitions = [
    for (final transition in workflow.transitions)
      if (identical(transition, previous)) next else transition,
  ];
  return documentWithWorkflow(
    document,
    workflowWith(workflow, transitions: transitions),
  );
}

ModeDocument addTransition(
  ModeDocument document,
  WorkflowTransition transition,
) {
  final workflow = document.definition.workflow;
  if (workflow == null) return document;
  if (workflow.transitions.any(
    (existing) =>
        existing.sourceStateId == transition.sourceStateId &&
        existing.targetStateId == transition.targetStateId,
  )) {
    return document;
  }
  return documentWithWorkflow(
    document,
    workflowWith(workflow, transitions: [...workflow.transitions, transition]),
  );
}

ModeDocument removeTransition(
  ModeDocument document,
  WorkflowTransition transition,
) {
  final workflow = document.definition.workflow;
  if (workflow == null) return document;
  return documentWithWorkflow(
    document,
    workflowWith(
      workflow,
      transitions: workflow.transitions
          .where((existing) => !identical(existing, transition))
          .toList(growable: false),
    ),
  );
}

ModeDocument setNodePosition(
  ModeDocument document,
  String stateId,
  ModeNodePoint position,
) {
  final positions = <WorkflowNodePosition>[];
  var found = false;
  for (final existing in document.editor.nodes) {
    if (existing.stateId == stateId) {
      found = true;
      positions.add(
        WorkflowNodePosition(stateId: stateId, x: position.x, y: position.y),
      );
    } else {
      positions.add(existing);
    }
  }
  if (!found) {
    positions.add(
      WorkflowNodePosition(stateId: stateId, x: position.x, y: position.y),
    );
  }
  return ModeDocument(
    definition: document.definition,
    editor: ModeEditorLayout(nodes: positions),
  );
}

ModeDocument applyAutoLayout(
  ModeDocument document,
  Map<String, ModeNodePoint> positions,
) {
  final nodes = <WorkflowNodePosition>[];
  for (final state
      in document.definition.workflow?.states ?? const <WorkflowState>[]) {
    final position = positions[state.id];
    if (position == null) continue;
    nodes.add(
      WorkflowNodePosition(stateId: state.id, x: position.x, y: position.y),
    );
  }
  return ModeDocument(
    definition: document.definition,
    editor: ModeEditorLayout(nodes: nodes),
  );
}

Map<String, ModeNodePoint> autoLayoutOffsets(WorkflowDefinition workflow) {
  final outgoing = <String, List<String>>{};
  for (final transition in workflow.transitions) {
    outgoing
        .putIfAbsent(transition.sourceStateId, () => [])
        .add(transition.targetStateId);
  }
  final statesById = {for (final state in workflow.states) state.id: state};
  final depth = <String, int>{};
  if (statesById.containsKey(workflow.initialStateId)) {
    depth[workflow.initialStateId] = 0;
    final queue = <String>[workflow.initialStateId];
    var index = 0;
    while (index < queue.length) {
      final current = queue[index++];
      for (final target in outgoing[current] ?? const <String>[]) {
        if (!statesById.containsKey(target) || depth.containsKey(target)) {
          continue;
        }
        depth[target] = depth[current]! + 1;
        queue.add(target);
      }
    }
  }
  var maxDepth = 0;
  for (final value in depth.values) {
    if (value > maxDepth) maxDepth = value;
  }
  final rows = <int, int>{};
  final result = <String, ModeNodePoint>{};
  for (final state in workflow.states) {
    final column = depth[state.id] ?? (maxDepth + 1);
    if (!depth.containsKey(state.id)) {
      depth[state.id] = column;
    }
    final row = rows[column] ?? 0;
    rows[column] = row + 1;
    result[state.id] = (x: 48 + column * 288, y: 48 + row * 136);
  }
  return result;
}

Map<String, ModeNodePoint> resolvedNodePositions(ModeDocument document) {
  final workflow = document.definition.workflow;
  if (workflow == null) return const {};
  final result = autoLayoutOffsets(workflow);
  for (final position in document.editor.nodes) {
    if (!result.containsKey(position.stateId)) continue;
    if (!position.x.isFinite || !position.y.isFinite) continue;
    result[position.stateId] = (x: position.x, y: position.y);
  }
  return result;
}

ModeNodePoint nextFreePosition(ModeDocument document) {
  final positions = resolvedNodePositions(document).values;
  if (positions.isEmpty) return const (x: 48, y: 48);
  var maxX = 0.0;
  for (final position in positions) {
    if (position.x > maxX) maxX = position.x;
  }
  for (var row = 0; row < 40; row++) {
    final candidate = (x: maxX + 288, y: 48.0 + row * 136);
    final occupied = positions.any(
      (position) =>
          math.sqrt(
            (position.x - candidate.x) * (position.x - candidate.x) +
                (position.y - candidate.y) * (position.y - candidate.y),
          ) <
          120,
    );
    if (!occupied) return candidate;
  }
  return (x: maxX + 288, y: 48.0 + positions.length * 136);
}

String nextStateId(WorkflowDefinition workflow, {required bool finalState}) {
  final prefix = finalState ? 'final' : 'stage';
  var index = 1;
  while (workflow.states.any((state) => state.id == '$prefix$index')) {
    index++;
  }
  return '$prefix$index';
}

String connectionId(WorkflowTransition transition) =>
    'edge:${transition.sourceStateId}->${transition.targetStateId}';

String stateTitle(WorkflowDefinition workflow, String stateId) {
  for (final state in workflow.states) {
    if (state.id == stateId) return state.title;
  }
  return stateId;
}

String suggestedModeId(Iterable<String> existing) {
  final used = existing.toSet();
  var suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  var candidate = 'mode.custom-$suffix';
  var attempt = 1;
  while (used.contains(candidate)) {
    candidate = 'mode.custom-$suffix-$attempt';
    attempt++;
  }
  return candidate;
}

String prettyDocumentJson(ModeDocument document) =>
    const JsonEncoder.withIndent('  ').convert(document.toJson());

String documentSignature(ModeDocument document) =>
    jsonEncode(document.toJson());
