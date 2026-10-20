import 'dart:convert';

import 'package:anywork_client/studio_client.dart'
    show
        ModeDefinition,
        ModeDocument,
        ModeEditorLayout,
        WorkflowDefinition,
        WorkflowNodePosition,
        WorkflowState,
        WorkflowStateKind,
        WorkflowTransition;
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

const maxModeWorkflowStates = 32;

final _modeIdPattern = RegExp(r'^mode\.[a-z0-9_-]+$');
final _stateIdPattern = RegExp(r'^[a-z0-9_-]+$');

bool isValidModeId(String value) =>
    value.length <= 64 && _modeIdPattern.hasMatch(value);

bool isValidStateId(String value) =>
    value.isNotEmpty && value.length <= 64 && _stateIdPattern.hasMatch(value);

abstract final class ModeEditorKeys {
  static const page = ValueKey<String>('mode-editor-page');
  static const tabGraph = ValueKey<String>('mode-editor-tab-graph');
  static const tabJson = ValueKey<String>('mode-editor-tab-json');
  static const tabSettings = ValueKey<String>('mode-editor-tab-settings');
  static const tabPreview = ValueKey<String>('mode-editor-tab-preview');
  static const search = ValueKey<String>('mode-editor-search');
  static const create = ValueKey<String>('mode-editor-create');
  static const importJson = ValueKey<String>('mode-editor-import');
  static const save = ValueKey<String>('mode-editor-save');
  static const copy = ValueKey<String>('mode-editor-copy');
  static const deleteMode = ValueKey<String>('mode-editor-delete');
  static const reload = ValueKey<String>('mode-editor-reload');
  static const undo = ValueKey<String>('mode-editor-undo');
  static const redo = ValueKey<String>('mode-editor-redo');
  static const addState = ValueKey<String>('mode-editor-add-state');
  static const addFinalState = ValueKey<String>('mode-editor-add-final');
  static const addTransition = ValueKey<String>('mode-editor-add-transition');
  static const inspectorAddTransition = ValueKey<String>(
    'mode-editor-inspector-add-transition',
  );
  static const validate = ValueKey<String>('mode-editor-validate');
  static const autoLayout = ValueKey<String>('mode-editor-auto-layout');
  static const fitView = ValueKey<String>('mode-editor-fit-view');
  static const zoomIn = ValueKey<String>('mode-editor-zoom-in');
  static const zoomOut = ValueKey<String>('mode-editor-zoom-out');
  static const toggleInspector = ValueKey<String>(
    'mode-editor-toggle-inspector',
  );
  static const closeInspector = ValueKey<String>('mode-editor-close-inspector');
  static const enableWorkflow = ValueKey<String>('mode-editor-enable-workflow');
  static const removeWorkflow = ValueKey<String>('mode-editor-remove-workflow');
  static const jsonEditor = ValueKey<String>('mode-editor-json-editor');
  static const applyJson = ValueKey<String>('mode-editor-apply-json');
  static const copyJson = ValueKey<String>('mode-editor-copy-json');
  static const schema = ValueKey<String>('mode-editor-schema');
  static const previewStart = ValueKey<String>('mode-editor-preview-start');
  static const previewReset = ValueKey<String>('mode-editor-preview-reset');
  static const previewReason = ValueKey<String>('mode-editor-preview-reason');
  static const deleteState = ValueKey<String>('mode-editor-delete-state');
  static const deleteTransition = ValueKey<String>(
    'mode-editor-delete-transition',
  );
  static const renameState = ValueKey<String>('mode-editor-rename-state');
  static const initialSwitch = ValueKey<String>('mode-editor-initial-state');
  static const notice = ValueKey<String>('mode-editor-notice');

  static ValueKey<String> catalogItem(String id) =>
      ValueKey<String>('mode-editor-catalog-$id');

  static ValueKey<String> node(String id) =>
      ValueKey<String>('mode-editor-node-$id');

  static ValueKey<String> edge(String id) =>
      ValueKey<String>('mode-editor-edge-$id');

  static ValueKey<String> previewTarget(String id) =>
      ValueKey<String>('mode-editor-preview-target-$id');

  static ValueKey<String> settingsField(String field) =>
      ValueKey<String>('mode-editor-settings-$field');

  static ValueKey<String> inspectorField(String field) =>
      ValueKey<String>('mode-editor-inspector-$field');
}

enum ModeTemplateKind { minimal, none, copyCurrent }

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

WorkflowDefinition minimalWorkflow(AppLocalizations l10n) => WorkflowDefinition(
  title: l10n.modeEditorWorkflow,
  goal: l10n.modeEditorWorkflowGoalText,
  initialStateId: 'start',
  states: [
    WorkflowState(
      id: 'start',
      title: l10n.modeEditorStart,
      instructions: l10n.modeEditorStageInstructionsPlaceholder,
      completionCriteria: [l10n.modeEditorStageCriterionPlaceholder],
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowState(
      id: 'done',
      title: l10n.modeEditorDone,
      instructions: '',
      completionCriteria: const [],
      kind: WorkflowStateKind.finalState,
    ),
  ],
  transitions: [
    WorkflowTransition(
      sourceStateId: 'start',
      targetStateId: 'done',
      guard: l10n.modeEditorTransitionGuardPlaceholder,
    ),
  ],
);

ModeDefinition newModeDefinition({
  required String id,
  required String displayName,
  required int order,
  required ModeTemplateKind template,
  ModeDefinition? current,
  required AppLocalizations l10n,
}) {
  final templateWorkflow = switch (template) {
    ModeTemplateKind.minimal => minimalWorkflow(l10n),
    ModeTemplateKind.none => null,
    ModeTemplateKind.copyCurrent => current?.workflow,
  };
  return ModeDefinition(
    id: id,
    displayName: displayName,
    description: current?.description ?? '',
    order: order,
    prompt:
        current?.prompt ??
        '# $displayName\n\n${l10n.modeEditorPromptDescription}\n',
    workflow: templateWorkflow,
  );
}

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
  Offset position,
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
    WorkflowNodePosition(stateId: state.id, x: position.dx, y: position.dy),
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
  Offset position,
) {
  final positions = <WorkflowNodePosition>[];
  var found = false;
  for (final existing in document.editor.nodes) {
    if (existing.stateId == stateId) {
      found = true;
      positions.add(
        WorkflowNodePosition(stateId: stateId, x: position.dx, y: position.dy),
      );
    } else {
      positions.add(existing);
    }
  }
  if (!found) {
    positions.add(
      WorkflowNodePosition(stateId: stateId, x: position.dx, y: position.dy),
    );
  }
  return ModeDocument(
    definition: document.definition,
    editor: ModeEditorLayout(nodes: positions),
  );
}

ModeDocument applyAutoLayout(
  ModeDocument document,
  Map<String, Offset> positions,
) {
  final nodes = <WorkflowNodePosition>[];
  for (final state in document.definition.workflow?.states ?? const []) {
    final position = positions[state.id];
    if (position == null) continue;
    nodes.add(
      WorkflowNodePosition(stateId: state.id, x: position.dx, y: position.dy),
    );
  }
  return ModeDocument(
    definition: document.definition,
    editor: ModeEditorLayout(nodes: nodes),
  );
}

Map<String, Offset> autoLayoutOffsets(WorkflowDefinition workflow) {
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
  final result = <String, Offset>{};
  for (final state in workflow.states) {
    final column = depth[state.id] ?? (maxDepth + 1);
    if (!depth.containsKey(state.id)) {
      depth[state.id] = column;
    }
    final row = rows[column] ?? 0;
    rows[column] = row + 1;
    result[state.id] = Offset(48 + column * 288, 48 + row * 136);
  }
  return result;
}

Map<String, Offset> resolvedNodePositions(ModeDocument document) {
  final workflow = document.definition.workflow;
  if (workflow == null) return const {};
  final result = autoLayoutOffsets(workflow);
  for (final position in document.editor.nodes) {
    if (!result.containsKey(position.stateId)) continue;
    if (!position.x.isFinite || !position.y.isFinite) continue;
    result[position.stateId] = Offset(position.x, position.y);
  }
  return result;
}

Offset nextFreePosition(ModeDocument document) {
  final positions = resolvedNodePositions(document).values;
  if (positions.isEmpty) return const Offset(48, 48);
  var maxX = 0.0;
  for (final position in positions) {
    if (position.dx > maxX) maxX = position.dx;
  }
  for (var row = 0; row < 40; row++) {
    final candidate = Offset(maxX + 288, 48 + row * 136);
    final occupied = positions.any(
      (position) => (position - candidate).distance < 120,
    );
    if (!occupied) return candidate;
  }
  return Offset(maxX + 288, 48 + positions.length * 136);
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
