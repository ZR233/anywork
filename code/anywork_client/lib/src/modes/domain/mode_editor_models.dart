import '../../models/collection_equality.dart';
import '../../models/command_receipts.dart';
import 'mode_catalog_models.dart';

const Object _unsetModeEditorValue = Object();

Map<String, dynamic>? _jsonMap(Object? value) =>
    value is Map<Object?, Object?> ? Map<String, dynamic>.from(value) : null;

List<Object?> _jsonList(Object? value) =>
    value is List<Object?> ? value : const [];

/// Execution metadata authored by the Mode editor.
final class ModeDefinition {
  const ModeDefinition({
    required this.id,
    required this.displayName,
    required this.description,
    required this.order,
    required this.prompt,
    this.workflow,
  });

  factory ModeDefinition.fromJson(Map<String, dynamic> json) {
    final workflow = _jsonMap(json['workflow']);
    return ModeDefinition(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      order: (json['order'] as num?)?.toInt() ?? 0,
      prompt: json['prompt'] as String? ?? '',
      workflow: workflow == null ? null : WorkflowDefinition.fromJson(workflow),
    );
  }

  final String id;
  final String displayName;
  final String description;
  final int order;
  final String prompt;
  final WorkflowDefinition? workflow;

  /// [clearWorkflow] is the explicit way to remove an existing graph.
  ModeDefinition copyWith({
    String? id,
    String? displayName,
    String? description,
    int? order,
    String? prompt,
    Object? workflow = _unsetModeEditorValue,
    bool clearWorkflow = false,
  }) {
    return ModeDefinition(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      order: order ?? this.order,
      prompt: prompt ?? this.prompt,
      workflow: clearWorkflow
          ? null
          : identical(workflow, _unsetModeEditorValue)
          ? this.workflow
          : workflow as WorkflowDefinition?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'description': description,
    'order': order,
    'prompt': prompt,
    'workflow': workflow?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ModeDefinition &&
      id == other.id &&
      displayName == other.displayName &&
      description == other.description &&
      order == other.order &&
      prompt == other.prompt &&
      workflow == other.workflow;

  @override
  int get hashCode =>
      Object.hash(id, displayName, description, order, prompt, workflow);
}

/// File JSON keeps the six definition fields flat and adds the editor layout.
final class ModeDocument {
  const ModeDocument({
    required this.definition,
    this.editor = const ModeEditorLayout(),
  });

  factory ModeDocument.fromJson(Map<String, dynamic> json) {
    final editor = _jsonMap(json['editor']);
    return ModeDocument(
      definition: ModeDefinition.fromJson(json),
      editor: editor == null
          ? const ModeEditorLayout()
          : ModeEditorLayout.fromJson(editor),
    );
  }

  final ModeDefinition definition;
  final ModeEditorLayout editor;

  ModeDocument copyWith({
    ModeDefinition? definition,
    ModeEditorLayout? editor,
  }) => ModeDocument(
    definition: definition ?? this.definition,
    editor: editor ?? this.editor,
  );

  Map<String, dynamic> toJson() => {
    ...definition.toJson(),
    'editor': editor.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ModeDocument &&
      definition == other.definition &&
      editor == other.editor;

  @override
  int get hashCode => Object.hash(definition, editor);
}

final class ModeEditorLayout {
  const ModeEditorLayout({this.nodes = const []});

  factory ModeEditorLayout.fromJson(Map<String, dynamic> json) {
    final nodes = json['nodes'];
    return ModeEditorLayout(
      nodes: [
        for (final node in _jsonList(nodes))
          if (_jsonMap(node) case final position?)
            WorkflowNodePosition.fromJson(position),
      ],
    );
  }

  final List<WorkflowNodePosition> nodes;

  ModeEditorLayout copyWith({List<WorkflowNodePosition>? nodes}) =>
      ModeEditorLayout(nodes: nodes ?? this.nodes);

  Map<String, dynamic> toJson() => {
    'nodes': [for (final node in nodes) node.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is ModeEditorLayout && listEquals(nodes, other.nodes);

  @override
  int get hashCode => Object.hashAll(nodes);
}

final class WorkflowNodePosition {
  const WorkflowNodePosition({
    required this.stateId,
    required this.x,
    required this.y,
  });

  factory WorkflowNodePosition.fromJson(Map<String, dynamic> json) =>
      WorkflowNodePosition(
        stateId: json['stateId'] as String? ?? '',
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
      );

  final String stateId;
  final double x;
  final double y;

  WorkflowNodePosition copyWith({String? stateId, double? x, double? y}) =>
      WorkflowNodePosition(
        stateId: stateId ?? this.stateId,
        x: x ?? this.x,
        y: y ?? this.y,
      );

  Map<String, dynamic> toJson() => {'stateId': stateId, 'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      other is WorkflowNodePosition &&
      stateId == other.stateId &&
      x == other.x &&
      y == other.y;

  @override
  int get hashCode => Object.hash(stateId, x, y);
}

final class WorkflowDefinition {
  const WorkflowDefinition({
    required this.title,
    required this.goal,
    required this.initialStateId,
    this.states = const [],
    this.transitions = const [],
  });

  factory WorkflowDefinition.fromJson(Map<String, dynamic> json) =>
      WorkflowDefinition(
        title: json['title'] as String? ?? '',
        goal: json['goal'] as String? ?? '',
        initialStateId: json['initialStateId'] as String? ?? '',
        states: [
          for (final state in _jsonList(json['states']))
            if (_jsonMap(state) case final value?)
              WorkflowState.fromJson(value),
        ],
        transitions: [
          for (final transition in _jsonList(json['transitions']))
            if (_jsonMap(transition) case final value?)
              WorkflowTransition.fromJson(value),
        ],
      );

  final String title;
  final String goal;
  final String initialStateId;
  final List<WorkflowState> states;
  final List<WorkflowTransition> transitions;

  WorkflowDefinition copyWith({
    String? title,
    String? goal,
    String? initialStateId,
    List<WorkflowState>? states,
    List<WorkflowTransition>? transitions,
  }) => WorkflowDefinition(
    title: title ?? this.title,
    goal: goal ?? this.goal,
    initialStateId: initialStateId ?? this.initialStateId,
    states: states ?? this.states,
    transitions: transitions ?? this.transitions,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'goal': goal,
    'initialStateId': initialStateId,
    'states': [for (final state in states) state.toJson()],
    'transitions': [for (final transition in transitions) transition.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is WorkflowDefinition &&
      title == other.title &&
      goal == other.goal &&
      initialStateId == other.initialStateId &&
      listEquals(states, other.states) &&
      listEquals(transitions, other.transitions);

  @override
  int get hashCode => Object.hash(
    title,
    goal,
    initialStateId,
    Object.hashAll(states),
    Object.hashAll(transitions),
  );
}

enum WorkflowStateKind {
  atomic,
  finalState;

  static WorkflowStateKind fromWire(String? value) =>
      value == 'final' ? finalState : atomic;

  String get wire => this == finalState ? 'final' : 'atomic';
}

final class WorkflowState {
  const WorkflowState({
    required this.id,
    required this.title,
    required this.instructions,
    this.completionCriteria = const [],
    required this.kind,
  });

  factory WorkflowState.fromJson(Map<String, dynamic> json) => WorkflowState(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    instructions: json['instructions'] as String? ?? '',
    completionCriteria: [
      for (final criterion in _jsonList(json['completionCriteria']))
        criterion.toString(),
    ],
    kind: WorkflowStateKind.fromWire(json['kind'] as String?),
  );

  final String id;
  final String title;
  final String instructions;
  final List<String> completionCriteria;
  final WorkflowStateKind kind;

  WorkflowState copyWith({
    String? id,
    String? title,
    String? instructions,
    List<String>? completionCriteria,
    WorkflowStateKind? kind,
  }) => WorkflowState(
    id: id ?? this.id,
    title: title ?? this.title,
    instructions: instructions ?? this.instructions,
    completionCriteria: completionCriteria ?? this.completionCriteria,
    kind: kind ?? this.kind,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'instructions': instructions,
    'completionCriteria': completionCriteria,
    'kind': kind.wire,
  };

  @override
  bool operator ==(Object other) =>
      other is WorkflowState &&
      id == other.id &&
      title == other.title &&
      instructions == other.instructions &&
      listEquals(completionCriteria, other.completionCriteria) &&
      kind == other.kind;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    instructions,
    Object.hashAll(completionCriteria),
    kind,
  );
}

final class WorkflowTransition {
  const WorkflowTransition({
    required this.sourceStateId,
    required this.targetStateId,
    required this.guard,
  });

  factory WorkflowTransition.fromJson(Map<String, dynamic> json) =>
      WorkflowTransition(
        sourceStateId: json['sourceStateId'] as String? ?? '',
        targetStateId: json['targetStateId'] as String? ?? '',
        guard: json['guard'] as String? ?? '',
      );

  final String sourceStateId;
  final String targetStateId;
  final String guard;

  WorkflowTransition copyWith({
    String? sourceStateId,
    String? targetStateId,
    String? guard,
  }) => WorkflowTransition(
    sourceStateId: sourceStateId ?? this.sourceStateId,
    targetStateId: targetStateId ?? this.targetStateId,
    guard: guard ?? this.guard,
  );

  Map<String, dynamic> toJson() => {
    'sourceStateId': sourceStateId,
    'targetStateId': targetStateId,
    'guard': guard,
  };

  @override
  bool operator ==(Object other) =>
      other is WorkflowTransition &&
      sourceStateId == other.sourceStateId &&
      targetStateId == other.targetStateId &&
      guard == other.guard;

  @override
  int get hashCode => Object.hash(sourceStateId, targetStateId, guard);
}

final class ModeDefinitionSnapshot {
  const ModeDefinitionSnapshot({
    required this.revision,
    required this.document,
    required this.readOnly,
  });

  factory ModeDefinitionSnapshot.fromJson(Map<String, dynamic> json) =>
      ModeDefinitionSnapshot(
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        document: ModeDocument.fromJson(_jsonMap(json['document']) ?? const {}),
        readOnly: json['readOnly'] as bool? ?? false,
      );

  final int revision;
  final ModeDocument document;
  final bool readOnly;

  ModeDefinitionSnapshot copyWith({
    int? revision,
    ModeDocument? document,
    bool? readOnly,
  }) => ModeDefinitionSnapshot(
    revision: revision ?? this.revision,
    document: document ?? this.document,
    readOnly: readOnly ?? this.readOnly,
  );

  Map<String, dynamic> toJson() => {
    'revision': revision,
    'document': document.toJson(),
    'readOnly': readOnly,
  };
}

final class ModeValidationIssue {
  const ModeValidationIssue({
    required this.code,
    required this.path,
    required this.message,
  });

  factory ModeValidationIssue.fromJson(Map<String, dynamic> json) =>
      ModeValidationIssue(
        code: json['code'] as String? ?? '',
        path: json['path'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );

  final String code;
  final String path;
  final String message;

  ModeValidationIssue copyWith({String? code, String? path, String? message}) =>
      ModeValidationIssue(
        code: code ?? this.code,
        path: path ?? this.path,
        message: message ?? this.message,
      );

  Map<String, dynamic> toJson() => {
    'code': code,
    'path': path,
    'message': message,
  };
}

final class ModeValidationResult {
  const ModeValidationResult({this.document, this.issues = const []});

  factory ModeValidationResult.fromJson(Map<String, dynamic> json) {
    final document = _jsonMap(json['document']);
    return ModeValidationResult(
      document: document == null ? null : ModeDocument.fromJson(document),
      issues: [
        for (final issue in _jsonList(json['issues']))
          if (_jsonMap(issue) case final value?)
            ModeValidationIssue.fromJson(value),
      ],
    );
  }

  final ModeDocument? document;
  final List<ModeValidationIssue> issues;

  ModeValidationResult copyWith({
    Object? document = _unsetModeEditorValue,
    List<ModeValidationIssue>? issues,
  }) => ModeValidationResult(
    document: identical(document, _unsetModeEditorValue)
        ? this.document
        : document as ModeDocument?,
    issues: issues ?? this.issues,
  );

  Map<String, dynamic> toJson() => {
    'document': document?.toJson(),
    'issues': [for (final issue in issues) issue.toJson()],
  };
}

final class WorkflowPreviewRequest {
  const WorkflowPreviewRequest({
    required this.document,
    this.path = const [],
    this.targetStateId,
    required this.reason,
  });

  factory WorkflowPreviewRequest.fromJson(Map<String, dynamic> json) =>
      WorkflowPreviewRequest(
        document: ModeDocument.fromJson(_jsonMap(json['document']) ?? const {}),
        path: [
          for (final stateId in _jsonList(json['path'])) stateId.toString(),
        ],
        targetStateId: json['targetStateId'] as String?,
        reason: json['reason'] as String? ?? '',
      );

  final ModeDocument document;
  final List<String> path;
  final String? targetStateId;
  final String reason;

  WorkflowPreviewRequest copyWith({
    ModeDocument? document,
    List<String>? path,
    Object? targetStateId = _unsetModeEditorValue,
    String? reason,
  }) => WorkflowPreviewRequest(
    document: document ?? this.document,
    path: path ?? this.path,
    targetStateId: identical(targetStateId, _unsetModeEditorValue)
        ? this.targetStateId
        : targetStateId as String?,
    reason: reason ?? this.reason,
  );

  Map<String, dynamic> toJson() => {
    'document': document.toJson(),
    'path': path,
    'targetStateId': targetStateId,
    'reason': reason,
  };
}

final class WorkflowPreviewSnapshot {
  const WorkflowPreviewSnapshot({
    required this.accepted,
    required this.message,
    this.currentState,
    this.transitions = const [],
    this.path = const [],
    required this.terminal,
  });

  factory WorkflowPreviewSnapshot.fromJson(Map<String, dynamic> json) {
    final currentState = _jsonMap(json['currentState']);
    return WorkflowPreviewSnapshot(
      accepted: json['accepted'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      currentState: currentState == null
          ? null
          : WorkflowState.fromJson(currentState),
      transitions: [
        for (final transition in _jsonList(json['transitions']))
          if (_jsonMap(transition) case final value?)
            WorkflowTransition.fromJson(value),
      ],
      path: [for (final stateId in _jsonList(json['path'])) stateId.toString()],
      terminal: json['terminal'] as bool? ?? false,
    );
  }

  final bool accepted;
  final String message;
  final WorkflowState? currentState;
  final List<WorkflowTransition> transitions;
  final List<String> path;
  final bool terminal;

  WorkflowPreviewSnapshot copyWith({
    bool? accepted,
    String? message,
    Object? currentState = _unsetModeEditorValue,
    List<WorkflowTransition>? transitions,
    List<String>? path,
    bool? terminal,
  }) => WorkflowPreviewSnapshot(
    accepted: accepted ?? this.accepted,
    message: message ?? this.message,
    currentState: identical(currentState, _unsetModeEditorValue)
        ? this.currentState
        : currentState as WorkflowState?,
    transitions: transitions ?? this.transitions,
    path: path ?? this.path,
    terminal: terminal ?? this.terminal,
  );

  Map<String, dynamic> toJson() => {
    'accepted': accepted,
    'message': message,
    'currentState': currentState?.toJson(),
    'transitions': [for (final transition in transitions) transition.toJson()],
    'path': path,
    'terminal': terminal,
  };
}

final class ModeDefinitionCommandReply {
  const ModeDefinitionCommandReply({
    required this.catalog,
    this.definition,
    required this.receipt,
  });

  final ThreadModeCatalogView catalog;
  final ModeDefinitionSnapshot? definition;
  final StudioCommandReceipt receipt;
}
