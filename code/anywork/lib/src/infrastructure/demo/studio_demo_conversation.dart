part of 'studio_demo_api.dart';

// Frozen only at Demo's Plan request producer boundary. Legacy seeded requests
// can lack document identity; their completion never borrows the current Plan.
typedef _DemoPlanRequest = ({
  PendingInteraction interaction,
  String markdown,
  PlanDocumentView? document,
  int? planRevision,
});

typedef _DemoPlanDecision = ({_DemoPlanDecisionKind decision, String feedback});

UserQuestionView? _demoPlanQuestion(PendingInteraction interaction) {
  final payload = interaction.payload;
  if (interaction.kind != InteractionKind.userInput ||
      payload is! UserInputInteractionPayload ||
      payload.questions.length != 1) {
    return null;
  }
  final question = payload.questions.single;
  return question.id == agentSessionPlanConfirmationQuestionId &&
          !question.isSecret
      ? question
      : null;
}

StudioFailure _demoInvalidPlanAnswer(String message) => StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: message,
  retryable: false,
  correlationId: 'demo-plan-confirmation-answer',
);

// Mirrors plan_tool::state::confirmation_decision, at acceptance of the known
// frozen request. Presentation receives the resulting enum, never parses answers.
_DemoPlanDecision _demoPlanDecision(InteractionResolutionCommand command) {
  if (command is! UserInputResolutionCommand ||
      command.answers.length != 1 ||
      command.answers.single.questionId !=
          agentSessionPlanConfirmationQuestionId) {
    throw _demoInvalidPlanAnswer(
      'Plan confirmation answer is missing or ambiguous',
    );
  }
  final answers = command.answers.single.answers;
  final approved = answers.contains(agentSessionPlanApproveAnswer);
  final revision = answers.contains(agentSessionPlanReviseAnswer);
  if (approved && revision) {
    throw _demoInvalidPlanAnswer(
      'Plan confirmation cannot select both Approve and Revise',
    );
  }
  if (approved) {
    return (decision: _DemoPlanDecisionKind.approved, feedback: '');
  }
  final feedback = answers
      .where((answer) => answer != agentSessionPlanReviseAnswer)
      .map((answer) => answer.trim())
      .where((answer) => answer.isNotEmpty)
      .join('\n');
  if (revision || feedback.isNotEmpty) {
    return (
      decision: _DemoPlanDecisionKind.revisionRequested,
      feedback: feedback,
    );
  }
  throw _demoInvalidPlanAnswer(
    'Plan confirmation must select Approve, Revise, or provide revision feedback',
  );
}

// Private facts used by the Demo conversation script.
enum _DemoContentKind { text, thinking, tool, completed }

enum _DemoPlanDecisionKind { approved, revisionRequested }

typedef _DemoContent = ({
  _DemoContentKind kind,
  bool? contentPresent,
  ThreadTextChannel? textChannel,
  Map<String, Object?>? descriptor,
  Map<String, String> fields,
  _DemoInvocation? invocation,
});

final class _DemoInvocation {
  const _DemoInvocation({
    required this.toolCallId,
    required this.name,
    this.presentationContract,
  });
  final String toolCallId;
  final String name;
  final String? presentationContract;
  Map<String, Object?> toJson() => {
    'toolCallId': toolCallId,
    'name': name,
    'callId': null,
    'providerItemId': null,
    'workingDirectory': null,
    'taskId': null,
    'presentationContract': presentationContract,
  };
}

int _demoSeconds(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;
Map<String, Object?>? _demoOutcome(ThreadContentLifecycleView value) =>
    switch (value) {
      StreamingThreadContentView() => null,
      CompletedThreadContentView(:final completedAt) => {
        'kind': 'completed',
        'data': {'completedAt': _demoSeconds(completedAt)},
      },
      FailedThreadContentView(:final failedAt, :final error) => {
        'kind': 'failed',
        'data': {'failedAt': _demoSeconds(failedAt), 'error': error},
      },
      CancelledThreadContentView(:final cancelledAt, :final reason) => {
        'kind': 'cancelled',
        'data': {'cancelledAt': _demoSeconds(cancelledAt), 'reason': reason},
      },
    };

_DemoContent _demoText({
  required ThreadTextChannel channel,
  required String text,
  required List<ThreadAttachmentView> attachments,
  required ThreadContentLifecycleView lifecycle,
}) {
  final outcome = _demoOutcome(lifecycle);
  return (
    kind: _DemoContentKind.text,
    contentPresent: text.isNotEmpty || attachments.isNotEmpty,
    textChannel: channel,
    descriptor: outcome == null
        ? null
        : {
            'type': 'text',
            'data': {
              'channel': channel.name,
              'attachments': [
                for (final a in attachments)
                  {
                    'id': a.id,
                    'modality': a.modality.name,
                    'mediaType': a.mediaType,
                    'filename': a.filename,
                    'byteSize': a.byteSize,
                    'width': a.width,
                    'height': a.height,
                  },
              ],
              'outcome': outcome,
            },
          },
    fields: {'body': text},
    invocation: null,
  );
}

_DemoContent _demoThinking({
  required List<String> summary,
  required List<String> content,
  required ThreadContentLifecycleView lifecycle,
}) {
  final outcome = _demoOutcome(lifecycle);
  return (
    kind: _DemoContentKind.thinking,
    contentPresent: null,
    textChannel: null,
    descriptor: outcome == null
        ? null
        : {
            'type': 'thinking',
            'data': {'outcome': outcome},
          },
    fields: {
      for (var i = 0; i < summary.length; i++)
        'part.summaryText.$i': summary[i],
      for (var i = 0; i < content.length; i++)
        'part.reasoningText.$i': content[i],
    },
    invocation: null,
  );
}

Map<String, Object?> _demoToolSucceeded(DateTime at) => {
  'kind': 'succeeded',
  'completedAt': _demoSeconds(at),
  'output': {'attachments': <Object?>[], 'exitCode': null},
};

_DemoContent _demoTool({
  required _DemoInvocation invocation,
  Map<String, Object?>? outcome,
  String arguments = '',
  String? result,
}) => (
  kind: _DemoContentKind.tool,
  contentPresent: null,
  textChannel: null,
  descriptor: outcome == null
      ? null
      : {
          'type': 'tool',
          'data': {
            'invocation': invocation.toJson(),
            'state': outcome,
            'userInput': null,
            'wait': null,
          },
        },
  fields: {'tool.arguments': arguments, 'tool.result': ?result},
  invocation: invocation,
);

_DemoContent _demoTurn(StudioTurnState state, {String? inputId}) {
  final Map<String, Object?> data;
  switch (state) {
    case CompletedStudioTurnState():
      data = {
        'startedAt': state.startedAt,
        'completedAt': state.completedAt,
        'completion': state.completion.name,
      };
    case FailedStudioTurnState():
      data = {
        'startedAt': state.startedAt,
        'completedAt': state.completedAt,
        'failure': state.failure.toJson(),
      };
    case CancelledStudioTurnState():
      final cause = switch (state.cause) {
        UnspecifiedTurnCancellation() => {'kind': 'unspecified'},
        UserRequestedTurnCancellation() => {'kind': 'userRequested'},
        RuntimeShutdownTurnCancellation() => {'kind': 'runtimeShutdown'},
        AgentClosedTurnCancellation() => {'kind': 'agentClosed'},
        InterruptedTurnCancellation() => {'kind': 'interrupted'},
        RecoveryTurnCancellation() => {'kind': 'recovery'},
        CoalescedTurnCancellation(:final targetTurnId) => {
          'kind': 'coalesced',
          'data': {'target_turn_id': targetTurnId},
        },
      };
      data = {
        'startedAt': state.startedAt,
        'completedAt': state.completedAt,
        'requestedAt': state.requestedAt,
        'cause': cause,
      };
    case BudgetLimitedStudioTurnState():
      final u = state.limit.usage;
      data = {
        'startedAt': state.startedAt,
        'completedAt': state.completedAt,
        'limit': {
          'kind': state.limit.kind.name,
          'usage': {
            'modelSteps': u.modelSteps,
            'toolCalls': u.toolCalls,
            'waitCalls': u.waitCalls,
            'elapsedMs': u.elapsedMs,
          },
        },
        'rollover': switch (state.rollover) {
          RolloverNotAttempted() => {'kind': 'notAttempted'},
          RolloverSucceeded() => {'kind': 'succeeded'},
          RolloverFailed(:final error) => {
            'kind': 'failed',
            'data': {'error': error},
          },
        },
      };
    case QueuedStudioTurnState() || RunningStudioTurnState():
      throw StateError('An active Turn is not a completed message');
  }
  return (
    kind: _DemoContentKind.completed,
    contentPresent: null,
    textChannel: null,
    descriptor: {
      'type': 'turn',
      'data': {
        'inputId': inputId,
        'outcome': {'kind': state.status.name, 'data': data},
      },
    },
    fields: {},
    invocation: null,
  );
}

_DemoItem _demoPlanCompletion(
  _DemoPlanRequest request,
  _DemoPlanDecision decision,
  DateTime completedAt,
) => _DemoItem(
  id: 'demo-plan:${request.interaction.id}',
  threadId: request.interaction.threadId,
  turnId: request.interaction.turnId,
  updatedAt: completedAt,
  content: (
    kind: _DemoContentKind.completed,
    contentPresent: null,
    textChannel: null,
    descriptor: {
      'type': 'plan',
      'data': {
        'interactionId': request.interaction.id,
        'documentVersion': request.document?.version,
        'contentHash': request.document?.contentHash,
        'decision': decision.decision.name,
      },
    },
    fields: {
      'plan.document': request.markdown,
      if (decision.feedback.isNotEmpty) 'plan.feedback': decision.feedback,
    },
    invocation: null,
  ),
);

final class _DemoItem {
  _DemoItem({
    required this.id,
    required this.threadId,
    required this.turnId,
    required this.updatedAt,
    required this.content,
  });
  final String id;
  final String threadId;
  final String? turnId;
  final DateTime updatedAt;
  final _DemoContent content;
  String? textFor(String key) => content.fields[key];
}

_DemoItem _demoRevise(
  _DemoItem item, {
  DateTime? updatedAt,
  required _DemoContent content,
}) => _DemoItem(
  id: item.id,
  threadId: item.threadId,
  turnId: item.turnId,
  updatedAt: updatedAt ?? item.updatedAt,
  content: content,
);

StudioFailure _demoQueryFailure(String message) => StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: message,
  retryable: false,
  correlationId: 'demo-conversation-query',
);

StudioFailure _demoMissing() => const StudioFailure(
  code: StudioFailureCode.notFound,
  message: 'The Demo content is unavailable',
  retryable: false,
  correlationId: 'demo-content-not-found',
);

// The script is the producer of Demo facts. Its completed rows and member
// details share the same sequence and body identities across open handles.
final class _DemoHistory {
  final String epoch = newStudioCorrelationId();
  final Map<String, _DemoDisplayScript> displayScripts = {};
  final Map<String, String> displayMembership = {};
  final List<_DemoSealedBlock> displayBlocks = [];
  final Map<String, _DemoItem> completed = {};
  final Map<String, int> itemSequences = {};
  final Set<void Function(ThreadWorkspace)> changes = {};
  final Set<void Function()> retiring = {};
  LiveStatusReconnecting? reconnecting;
  int _sequence = 0;

  void changed(ThreadWorkspace workspace) {
    for (final wake in changes.toList()) {
      wake(workspace);
    }
  }

  void retire() {
    for (final stop in retiring.toList()) {
      stop();
    }
  }

  void admit(_DemoItem item) {
    if (completed.containsKey(item.id)) {
      throw StateError('Completed Demo member cannot be modified: ${item.id}');
    }
    itemSequences.putIfAbsent(item.id, () => ++_sequence);
  }

  void complete(_DemoItem item) {
    if (item.content.descriptor?['type'] == 'inference') return;
    admit(item);
    completed[item.id] = item;
  }
}

final class _DemoDetailWindowSink implements Sink<List<int>> {
  _DemoDetailWindowSink(this.offset, this.limit);

  final int offset;
  final int limit;
  final bytes = BytesBuilder();
  int totalBytes = 0;

  @override
  void add(List<int> chunk) {
    final start = (offset - totalBytes).clamp(0, chunk.length);
    final count = (limit - bytes.length).clamp(0, chunk.length - start);
    if (count > 0) bytes.add(chunk.sublist(start, start + count));
    totalBytes += chunk.length;
  }

  @override
  void close() {}
}

// Demo emits the same Serde field shapes as the native feed. Full detail is
// selected from the snapshot that supplies the window's owner and revision.
Object? _demoSessionDetail(
  SessionMetaSnapshot snapshot,
  SessionDetailKind kind, {
  required PlanRuntimeView? plan,
}) {
  final runtime = snapshot.runtime;
  return switch (kind) {
    SessionDetailKind.plan => _demoPlanDetail(plan),
    SessionDetailKind.interactions => [
      for (final interaction in snapshot.interactions)
        _demoInteractionDetail(interaction, runtime?.updatedAt ?? 0),
    ],
    SessionDetailKind.todo => _demoTodoDetail(runtime?.todo),
    SessionDetailKind.workflow => _demoWorkflowDetail(runtime?.workflow),
    SessionDetailKind.activeSkills => runtime?.activeSkills,
    SessionDetailKind.activeMcpServers => runtime?.activeMcpServers,
    SessionDetailKind.activeLspServers => runtime?.activeLspServers,
  };
}

Map<String, Object?>? _demoPlanDetail(PlanRuntimeView? plan) {
  if (plan == null) return null;
  return {
    'revision': plan.revision,
    'state': plan.state.name,
    if (plan.document case final document?)
      'document': {
        'version': document.version,
        'markdown': document.markdown,
        'contentHash': document.contentHash,
      },
    'updatedAt': _demoSeconds(plan.updatedAt),
  };
}

Map<String, Object?>? _demoTodoDetail(TimelineTodoListUpdate? todo) {
  if (todo == null) return null;
  return {
    'callId': todo.callId,
    'agentId': ?todo.agentId,
    'path': ?todo.path,
    'parentPath': ?todo.parentPath,
    'explanation': ?todo.explanation,
    'items': [
      for (final item in todo.items) {'step': item.step, 'status': item.status},
    ],
  };
}

Map<String, Object?>? _demoWorkflowDetail(WorkflowRuntimeView? workflow) {
  if (workflow == null) return null;
  return {
    'revision': workflow.revision,
    if (workflow.currentRun case final run?)
      'currentRun': {
        'lineageId': run.lineageId,
        'runId': run.runId,
        'modeId': run.modeId,
        'graphRevision': run.graphRevision,
        'graphHash': run.graphHash,
        'lifecycle': run.terminal ? 'terminal' : 'active',
        'currentStateTitle': run.currentStateTitle,
        'modeDisplayName': run.modeDisplayName,
        'modeDeleted': run.modeDeleted,
        'currentStateId': run.currentStateId,
        'visitedStateIds': run.visitedStateIds,
        'lastTransitionForced': run.lastTransitionForced,
        'startedAt': _demoSeconds(run.startedAt),
        'updatedAt': _demoSeconds(run.updatedAt),
      },
  };
}

Map<String, Object?> _demoInteractionDetail(
  PendingInteraction interaction,
  int timestamp,
) {
  final payload = switch ((interaction.kind, interaction.payload)) {
    (
      InteractionKind.userInput,
      UserInputInteractionPayload(:final questions),
    ) =>
      {
        'questions': [
          for (final question in questions)
            {
              'id': question.id,
              'header': question.header,
              'question': question.question,
              'isOther': question.isOther,
              'isSecret': question.isSecret,
              if (question.options.isNotEmpty)
                'options': [
                  for (final option in question.options)
                    {'label': option.label, 'description': option.description},
                ],
            },
        ],
      },
    (InteractionKind.toolApproval, ToolApprovalInteractionPayload approval) => {
      'request': {
        'name': approval.toolName,
        'arguments': approval.arguments,
        'workingDirectory': approval.workingDirectory.isEmpty
            ? null
            : approval.workingDirectory,
        'parentAgentId': approval.parentAgentId,
      },
    },
    _ => throw _demoQueryFailure(
      'Demo interaction requires a matching typed payload',
    ),
  };
  return {
    'interactionId': interaction.id,
    'scope': {
      'threadId': interaction.threadId,
      'turnId': interaction.turnId,
      'purpose': {'kind': 'general'},
    },
    'revision': interaction.revision,
    'content': {
      'kind': interaction.kind.name,
      'data': {
        ...payload,
        'state': {
          'kind': 'pending',
          'data': {'operationId': interaction.id},
        },
      },
    },
    'createdAt': timestamp,
    'updatedAt': timestamp,
  };
}
