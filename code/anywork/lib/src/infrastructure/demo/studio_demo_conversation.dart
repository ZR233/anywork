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

// Demo script facts are private. Only the frozen UTF-8 envelope crosses the port.
enum _DemoContentKind { text, thinking, tool, completed }

enum _DemoPlanDecisionKind { approved, revisionRequested }

typedef _DemoContent = ({
  _DemoContentKind kind,
  MainPresentation mainPresentation,
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
    mainPresentation: MainPresentation.single,
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
    mainPresentation: MainPresentation.foregroundWork,
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
  mainPresentation: MainPresentation.foregroundWork,
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
      final f = state.failure;
      data = {
        'startedAt': state.startedAt,
        'completedAt': state.completedAt,
        'failure': {
          'category': f.category,
          'providerKind': f.providerKind,
          'code': f.code,
          'httpStatus': f.httpStatus,
          'message': f.message,
          'retryable': f.retryable,
          'retryAfterMs': f.retryAfterMs,
        },
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
    mainPresentation: MainPresentation.single,
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
) => _demoItem(
  id: 'demo-plan:${request.interaction.id}',
  threadId: request.interaction.threadId,
  turnId: request.interaction.turnId,
  updatedAt: completedAt,
  content: (
    kind: _DemoContentKind.completed,
    mainPresentation: MainPresentation.single,
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

_DemoItem _demoItem({
  required String id,
  required String threadId,
  required String? turnId,
  required DateTime updatedAt,
  required _DemoContent content,
}) => _DemoItem(
  id: id,
  threadId: threadId,
  turnId: turnId,
  updatedAt: updatedAt,
  content: content,
);
_DemoItem _demoRevise(
  _DemoItem item, {
  DateTime? updatedAt,
  required _DemoContent content,
}) => _demoItem(
  id: item.id,
  threadId: item.threadId,
  turnId: item.turnId,
  updatedAt: updatedAt ?? item.updatedAt,
  content: content,
);

const _demoMaxBytes = 256 * 1024;
const _demoInlineBodyBytes = 4096;
StudioFailure _demoQueryFailure(String message) => StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: message,
  retryable: false,
  correlationId: 'demo-chat-query',
);
StudioFailure _demoStale() => const StudioFailure(
  code: StudioFailureCode.staleRevision,
  message: 'The Demo current revision has retired',
  retryable: false,
  correlationId: 'demo-stale-content',
  detailsJson: '{"reason":"staleContent"}',
);
StudioFailure _demoMissing() => const StudioFailure(
  code: StudioFailureCode.notFound,
  message: 'The Demo content is unavailable',
  retryable: false,
  correlationId: 'demo-content-not-found',
);
void _demoDemand(ReadDemand d) {
  if (d.maxItems < 1 ||
      d.maxItems > 4096 ||
      d.maxBytes < 1 ||
      d.maxBytes > _demoMaxBytes) {
    throw _demoQueryFailure(
      'InvalidDemand: items must be 1..4096 and bytes 1..262144',
    );
  }
}

String _demoScopeKey(ChatScope scope) => switch (scope) {
  MainChatScope() => 'main',
  RunChatScope(:final reference) =>
    'run:${reference.databaseId}:${reference.indexVersion}:${reference.startSeq}',
  ChildrenChatScope(:final parentId) => 'children:$parentId',
};
ChatAtom _demoCopy(
  ChatAtom atom, {
  PayloadData? payload,
  int? completionSeq,
  ChatSourceState? sourceState,
  ChatAtomLifecycle? lifecycle,
  List<ChatAtomContent>? contents,
  bool frozen = false,
}) => ChatAtom(
  id: atom.id,
  completionItemId: atom.completionItemId,
  completionSeq: completionSeq ?? atom.completionSeq,
  source: atom.source,
  sourceOrder: atom.sourceOrder,
  kind: atom.kind,
  sourceState: frozen ? null : sourceState ?? atom.sourceState,
  delivery: atom.delivery,
  lifecycle: lifecycle ?? atom.lifecycle,
  turnId: atom.turnId,
  attemptId: atom.attemptId,
  tool: atom.tool,
  wait: atom.wait,
  textChannel: atom.textChannel,
  contentPresent: atom.contentPresent,
  startedAt: atom.startedAt,
  finishedAt: atom.finishedAt,
  contents: contents ?? atom.contents,
  payload: payload ?? atom.payload,
);
int _demoEncoded(Object? value) => utf8.encode(jsonEncode(value)).length;

// Chunked authoritative bytes: range reads visit only intersecting chunks, never
// concatenate a body before slicing. Append keeps generation; replacement changes it.
final class _DemoBody {
  final List<Uint8List> _chunks = [];
  final List<int> _ends = [];
  int length = 0;
  int generation = 1;
  bool sealed = false;
  _DemoBody frozen() => _DemoBody()
    .._chunks.addAll(_chunks)
    .._ends.addAll(_ends)
    ..length = length
    ..generation = generation
    ..sealed = true;
  void append(List<int> bytes) {
    if (sealed) throw StateError('Cannot append sealed Demo content');
    for (var start = 0; start < bytes.length; start += 4096) {
      final end = (start + 4096).clamp(0, bytes.length);
      final chunk = Uint8List.fromList(bytes.sublist(start, end));
      _chunks.add(chunk);
      length += chunk.length;
      _ends.add(length);
    }
  }

  Uint8List range(int offset, int maxBytes) {
    if (offset < 0 || maxBytes < 1 || maxBytes > _demoMaxBytes) {
      throw _demoQueryFailure('Invalid content range');
    }
    if (offset > length) {
      throw _demoQueryFailure('Content offset exceeds length');
    }
    final end = (offset + maxBytes).clamp(0, length);
    if (offset >= end) return Uint8List(0);
    final out = Uint8List(end - offset);
    var low = 0, high = _ends.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_ends[mid] <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (var i = low; i < _chunks.length; i++) {
      final start = i == 0 ? 0 : _ends[i - 1];
      if (start >= end) break;
      final from = (offset - start).clamp(0, _chunks[i].length);
      final through = (end - start).clamp(0, _chunks[i].length);
      out.setRange(
        start + from - offset,
        start + through - offset,
        _chunks[i],
        from,
      );
    }
    return out;
  }

  void update(String text) {
    final bytes = utf8.encode(text);
    var prefix = bytes.length >= length;
    var pos = 0;
    for (final chunk in _chunks) {
      if (!prefix) break;
      for (var i = 0; i < chunk.length; i++) {
        if (bytes[pos + i] != chunk[i]) {
          prefix = false;
          break;
        }
      }
      pos += chunk.length;
    }
    if (!prefix) {
      if (sealed) throw StateError('Cannot replace sealed Demo content');
      generation++;
      _chunks.clear();
      _ends.clear();
      length = 0;
    }
    if (bytes.length > length) append(bytes.sublist(length));
  }
}

final class _DemoFrozen {
  const _DemoFrozen(this.message, this.order, this.scope);
  final ChatAtom message;
  final int order;
  final String scope;
}

final class _DemoHistory {
  final List<DisplayBlock> displayBlocks = [];
  final Map<String, _DemoDisplayScript> displayScripts = {};
  final Map<String, String> displayMembership = {};
  final Map<DisplayBlockRef, List<DisplayMemberHead>> displayHeads = {};
  final Map<String, int> displayMemberRevisions = {};
  LiveDisplayWindow? displayLiveSeed;
  int displayRevision = 0;
  bool displayExecutionPresent = false;
  int get displayHead => displayBlocks.lastOrNull?.historyPos ?? 0;
  // Original completion consumers retain their own ordered envelopes and Run
  // fixtures. GUI display positions and grouping are declared separately above.
  final List<CompletedEntry> displayItems = [];
  final Map<String, CompletedEntry> completed = {};
  final String epoch = newStudioCorrelationId();
  final Map<String, ChatAtom> activeAtoms = {};
  final Map<ChatSourceId, ChatSourceState> sourceStates = {};
  final Map<ChatSourceId, int> _sourceOrders = {};
  int _facts = 0;
  ChatFactPosition _fact() =>
      ChatFactPosition(effectSeq: ++_facts, suborder: 0);
  List<CompletedEntry> entries(Iterable<ChatAtom> atoms) => [
    for (final atom in atoms)
      CompletedEntry(
        recordId: atom.completionItemId ?? atom.id,
        completionSeq: atom.completionSeq!,
        run:
            completed[atom.completionItemId ?? atom.id]?.run ??
            CompletionRunPosition(startSeq: atom.completionSeq!, ordinal: 1),
        mainPresentation:
            completed[atom.completionItemId ?? atom.id]?.mainPresentation ??
            MainPresentation.single,
        atom: atom,
      ),
  ];
  final List<_DemoFrozen> items = [];
  final Map<String, _DemoFrozen> byId = {};
  final Map<String, List<_DemoFrozen>> _indices = {};
  final Map<String, Map<String, _DemoBody>> bodies = {};
  final Map<String, _DemoBody> payloads = {};
  final Map<(String, String, String), _DemoBody> currentBodies = {};
  final Map<(String, String), int> positions = {};
  int _nextPosition = 0;
  _DemoBody? planDocument;
  int? planRevision;
  int interactionRevision = 0;
  String? _interactionSignature;
  final Set<void Function()> changes = {};
  int revision = 0;
  int get head => items.lastOrNull?.order ?? 0;
  void prepareCurrent(ThreadWorkspace workspace) {
    final plan = workspace.runtime.plan;
    if (plan?.document == null) {
      planDocument = null;
    } else if (planRevision != plan!.revision) {
      planDocument = _DemoBody()
        ..update(plan.document!.markdown)
        ..sealed = true;
    }
    planRevision = plan?.revision;
    final signature = jsonEncode([
      for (final value in workspace.interactions)
        [value.id, value.revision, value.title, value.body],
    ]);
    if (signature != _interactionSignature) {
      _interactionSignature = signature;
      interactionRevision++;
      currentBodies.clear();
    }
    for (final interaction in workspace.interactions) {
      positions.putIfAbsent((
        'interaction',
        interaction.id,
      ), () => _nextPosition++);
    }
  }

  void changed(ThreadWorkspace workspace) {
    revision++;
    final executionPresent = workspace.runtime.execution != null;
    if (displayExecutionPresent != executionPresent) {
      displayExecutionPresent = executionPresent;
      displayRevision++;
    }
    prepareCurrent(workspace);
    for (final wake in changes.toList()) {
      wake();
    }
  }

  List<_DemoFrozen> index(ChatScope scope) =>
      _indices[_demoScopeKey(scope)] ?? const [];
  void validateScope(ChatScope scope) {
    if (scope case RunChatScope(:final reference)) {
      if (reference.databaseId != epoch || reference.indexVersion != 1) {
        throw _demoStale();
      }
      if (!completed.values.any(
        (entry) => entry.run?.startSeq == reference.startSeq,
      )) {
        throw _demoMissing();
      }
    }
  }

  // Script fixtures explicitly choose their class and singleton Run. Demo does
  // not implement Native's grouping/classification algorithm.
  CompletedEntry displayFixture(_DemoItem fixture, ChatAtom atom) =>
      CompletedEntry(
        recordId: atom.completionItemId!,
        completionSeq: atom.completionSeq!,
        run: CompletionRunPosition(startSeq: atom.completionSeq!, ordinal: 1),
        mainPresentation: fixture.content.mainPresentation,
        atom: atom,
      );

  bool accept(ChatAtom message, ChatScope scope) {
    validateScope(scope);
    if (message.id.isEmpty) throw _demoQueryFailure('Empty message identity');
    final key = _demoScopeKey(scope);
    final old = byId[message.id];
    message = _demoCopy(
      message,
      completionSeq: old?.order ?? head + 1,
      frozen: true,
    );
    if (old != null) {
      if (old.scope != key ||
          jsonEncode(chatAtomToJson(old.message)) !=
              jsonEncode(chatAtomToJson(message))) {
        throw const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'A completed Demo message cannot be changed',
          retryable: false,
          correlationId: 'demo-completion-conflict',
        );
      }
      return false;
    }
    final record = _DemoFrozen(message, head + 1, key);
    if (message.payload case InlinePayload(:final bytes)) {
      payloads[message.completionItemId ?? message.id] = _DemoBody()
        ..append(bytes)
        ..sealed = true;
    }
    items.add(record);
    byId[message.id] = record;
    (_indices[key] ??= []).add(record);
    return true;
  }

  bool acceptDisplay(CompletedEntry entry) {
    if (completed.containsKey(entry.recordId) ||
        entry.completionSeq <= (displayItems.lastOrNull?.completionSeq ?? 0)) {
      throw _demoQueryFailure('Duplicate or unordered completion fixture');
    }
    completed[entry.recordId] = entry;
    final atom = entry.atom;
    if (!byId.containsKey(atom.id)) {
      final record = _DemoFrozen(atom, entry.completionSeq, 'main');
      items.add(record);
      byId[atom.id] = record;
    }
    if (atom.payload case InlinePayload(:final bytes)) {
      payloads[entry.recordId] = _DemoBody()
        ..append(bytes)
        ..sealed = true;
    }
    if (entry.mainPresentation != MainPresentation.hidden) {
      displayItems.add(entry);
    }
    return true;
  }

  void sync(_DemoItem item) {
    if (item.content.descriptor?['type'] == 'inference') return;
    if (!byId.containsKey(item.id)) {
      final previous = activeAtoms[item.id];
      final source =
          previous?.source ??
          (item.content.textChannel == ThreadTextChannel.user
              ? InputChatSource(inputId: item.id)
              : item.turnId == null ||
                    item.content.descriptor?['type'] == 'turn'
              ? ReceiptChatSource(receiptId: item.id)
              : ForegroundTurnChatSource(turnId: item.turnId!));
      sourceStates.putIfAbsent(
        source,
        () => ChatSourceState(
          source: source,
          lifecycle: const ActiveChatSource(),
          started: _fact(),
          ended: null,
        ),
      );
      final kind = switch (item.content.kind) {
        _DemoContentKind.text =>
          item.content.textChannel == ThreadTextChannel.user
              ? ChatAtomKind.input
              : ChatAtomKind.text,
        _DemoContentKind.thinking => ChatAtomKind.reasoning,
        _DemoContentKind.tool => ChatAtomKind.toolCall,
        _DemoContentKind.completed =>
          switch (item.content.descriptor?['type']) {
            'turn' => ChatAtomKind.turnReceipt,
            'plan' => ChatAtomKind.plan,
            'contextCompaction' => ChatAtomKind.compaction,
            _ => ChatAtomKind.receipt,
          },
      };
      activeAtoms[item.id] = ChatAtom(
        id: item.id,
        source: source,
        sourceOrder:
            previous?.sourceOrder ??
            (_sourceOrders.update(
              source,
              (value) => value + 1,
              ifAbsent: () => 1,
            )),
        kind: kind,
        delivery: source is ForegroundTurnChatSource
            ? ChatDeliveryKind.foreground
            : ChatDeliveryKind.independent,
        lifecycle:
            previous?.lifecycle ??
            ActiveChatAtom(started: _fact(), status: ChatActiveStatus.running),
        turnId: item.turnId,
        startedAt: previous?.startedAt ?? _demoSeconds(item.updatedAt),
        textChannel: item.content.textChannel,
        contentPresent: item.content.contentPresent,
        tool: item.content.invocation == null
            ? null
            : ChatToolIdentity(
                callId: item.content.invocation!.toolCallId,
                name: item.content.invocation!.name,
              ),
        contents: [
          for (final field in item.content.fields.keys)
            ChatAtomContent(
              role: kind == ChatAtomKind.toolCall
                  ? field == 'tool.arguments'
                        ? ChatContentRole.toolArguments
                        : ChatContentRole.toolOutput
                  : kind == ChatAtomKind.reasoning
                  ? ChatContentRole.reasoningSummary
                  : ChatContentRole.body,
              reference: ContentRef(
                databaseId: epoch,
                target: BodyContentTarget(
                  owner: ItemContentOwner(itemId: item.id),
                  key: field,
                ),
              ),
            ),
        ],
      );
    }
    positions.putIfAbsent(('member', item.id), () => _nextPosition++);
    final contents = bodies.putIfAbsent(item.id, () => {});
    for (final entry in item.content.fields.entries) {
      (contents[entry.key] ??= _DemoBody()).update(entry.value);
    }
    updateDisplayMember(item.id);
  }

  void complete(_DemoItem item) {
    final descriptor = item.content.descriptor!;
    final type = descriptor['type'] as String;
    final data = Map<String, Object?>.of(
      descriptor['data'] as Map<String, Object?>,
    );
    if (type == 'inference') {
      return; // Execution diagnostics are not Chat steps.
    }
    sync(item);
    final contents = bodies[item.id]!;
    final frozen = byId[item.id]?.message;
    final active = activeAtoms.remove(item.id) ?? frozen!;
    final rawOutcome = data['outcome'] ?? data['state'];
    final result = rawOutcome is Map ? rawOutcome['kind'] : null;
    final outcome = switch (result) {
      'failed' => ChatTerminalOutcome.failed,
      'cancelled' || 'interrupted' => ChatTerminalOutcome.cancelled,
      _ => ChatTerminalOutcome.completed,
    };
    final message = ChatAtom(
      id: item.id,
      completionItemId: item.id,
      completionSeq: frozen?.completionSeq ?? head + 1,
      source: active.source,
      sourceOrder: active.sourceOrder,
      kind: active.kind,
      delivery: active.delivery,
      lifecycle:
          frozen?.lifecycle ??
          TerminalChatAtom(
            started: (active.lifecycle as ActiveChatAtom).started,
            ended: _fact(),
            outcome: outcome,
          ),
      turnId: active.turnId,
      tool: active.tool,
      textChannel: active.textChannel,
      contentPresent: active.contentPresent,
      startedAt: active.startedAt,
      finishedAt: _demoSeconds(item.updatedAt),
      contents: active.contents,
      payload: InlinePayload(
        bytes: utf8.encode(
          jsonEncode({
            'contract': 'anywork.chat/1',
            'type': type,
            'data': data,
            if (item.turnId != null) 'turnId': item.turnId,
            'sealedAt': _demoSeconds(item.updatedAt),
            'bodies': [
              for (final entry in contents.entries)
                {
                  'key': entry.key,
                  'byteLength': entry.value.length,
                  if (entry.value.length <= _demoInlineBodyBytes)
                    'inline': entry.value.range(0, _demoInlineBodyBytes)
                  else
                    'reference': contentRefToJson(
                      ContentRef(
                        databaseId: epoch,
                        target: BodyContentTarget(
                          owner: ItemContentOwner(itemId: item.id),
                          key: entry.key,
                        ),
                      ),
                    ),
                },
            ],
          }),
        ),
      ),
    );
    final memberScope = ChildrenChatScope(parentId: item.turnId ?? item.id);
    if (!accept(message, memberScope)) return;
    final display = displayFixture(item, message);
    completed[display.recordId] = display;
    updateDisplayMember(item.id);
    if (message.contentPresent != false) displayItems.add(display);
    final ended = <ChatSourceId>[
      if (active.source is! ForegroundTurnChatSource) active.source,
      if (type == 'turn' && item.turnId != null)
        ForegroundTurnChatSource(turnId: item.turnId!),
    ];
    for (final source in ended) {
      final previous = sourceStates[source];
      if (previous != null) {
        sourceStates[source] = ChatSourceState(
          source: source,
          lifecycle: EndedChatSource(outcome: outcome),
          started: previous.started,
          ended: _fact(),
        );
      }
    }
    for (final body in contents.values) {
      body.sealed = true;
    }
  }
}

// All cursors are issued by this original reader and bind its fixed initial cut.
// Tokens are opaque to callers; retaining only issued boundaries is not history caching.
final class _DemoReader implements ConversationReader {
  _DemoReader(this._api, this.threadId, this._history, this.scope)
    : h0 = _history.head,
      itemH0 = _history.head;
  final DemoStudioTransport _api;
  final _DemoHistory _history;
  final ChatScope scope;
  final int h0;
  final int itemH0;
  @override
  final String threadId;
  final Map<String, (String, int, int)> _cursors = {};
  final Set<Future<void>> _accepted = {};
  final Set<_DemoContentWatch> _watches = {};
  final Set<_DemoDisplayMembers> _displayReads = {};
  bool _closed = false;
  Future<void>? _closing;
  String cursor(String kind, int revision, int boundary) {
    final token = 'demo:${newStudioCorrelationId()}';
    _cursors[token] = (kind, revision, boundary);
    return token;
  }

  int boundary(String token, String kind, int revision) {
    final c = _cursors[token];
    if (c == null || c.$1 != kind || c.$2 != revision) {
      throw _demoQueryFailure('Invalid original read cursor');
    }
    return c.$3;
  }

  Future<T> _read<T>(T Function() query) {
    if (_closed || _api._runtimeExiting) {
      return Future.error(_conversationClosedFailure);
    }
    final result = Future<T>.microtask(query);
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _accepted.add(settled);
    unawaited(settled.then((_) => _accepted.remove(settled)));
    return result;
  }

  ChatAtom fit(ChatAtom message, int budget) {
    if (message.payload == null) return message;
    if (message.payload is DeferredPayload) return message;
    if (_demoEncoded(chatAtomToJson(message)) <= budget) return message;
    final length = switch (message.payload!) {
      InlinePayload(:final bytes) => bytes.length,
      DeferredPayload(:final byteLength) => byteLength,
    };
    return _demoCopy(
      message,
      payload: DeferredPayload(
        reference: ContentRef(
          databaseId: _history.epoch,
          target: ItemPayloadTarget(
            itemId: message.completionItemId ?? message.id,
          ),
        ),
        byteLength: length,
      ),
    );
  }

  CompletedEntry fitEntry(
    CompletedEntry entry,
    int budget, {
    bool main = false,
  }) {
    final atom = fit(
      entry.atom,
      main && entry.mainPresentation != MainPresentation.single ? 0 : budget,
    );
    return CompletedEntry(
      recordId: entry.recordId,
      completionSeq: entry.completionSeq,
      run: entry.run,
      mainPresentation: entry.mainPresentation,
      atom: atom,
    );
  }

  List<CompletedEntry> source() {
    if (scope is MainChatScope) return _history.displayItems;
    if (scope case RunChatScope(:final reference)) {
      return [
        for (final entry in _history.completed.values)
          if (entry.run?.startSeq == reference.startSeq) entry,
      ];
    }
    return _history.entries(
      _history.index(scope).map((record) => record.message),
    );
  }

  ChatBatch page(ReadDemand demand, {String? before}) {
    _history.validateScope(scope);
    _demoDemand(demand);
    final end = before == null ? h0 + 1 : boundary(before, 'history', h0);
    final records = source();
    final selected = <CompletedEntry>[];
    String? next;
    for (var i = records.length - 1; i >= 0; i--) {
      final entry = records[i];
      if (entry.completionSeq >= end) continue;
      final candidate = fitEntry(entry, 0, main: scope is MainChatScope);
      final token = i == 0
          ? null
          : cursor('history', h0, entry.run?.startSeq ?? entry.completionSeq);
      final trial = ChatBatch(
        placement: before == null ? ChatPlacement.set : ChatPlacement.prepend,
        entries: [candidate, ...selected],
        before: token,
        throughSeq: h0,
      );
      if (_demoBatchBytes(trial) > demand.maxBytes) {
        if (selected.isEmpty) {
          throw _demoQueryFailure(
            'InvalidDemand: completion envelope does not fit',
          );
        }
        break;
      }
      selected.insert(0, candidate);
      next = token;
      if (selected.length == demand.maxItems) break;
    }
    return ChatBatch(
      placement: before == null ? ChatPlacement.set : ChatPlacement.prepend,
      entries: selected,
      before: next,
      throughSeq: h0,
    );
  }

  @override
  Future<ThreadBusinessRefs> readBusinessRefs() =>
      _read(() => _api._snapshotOf(_api._demoWorkspace(threadId)).businessRefs);

  @override
  Future<CompletedEntry> readCompleted({
    required String recordId,
    required ReadDemand demand,
  }) => _read(() {
    _demoDemand(demand);
    final entry = _history.completed[recordId];
    if (entry == null) throw _demoMissing();
    return fitEntry(entry, demand.maxBytes);
  });

  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) => _read(() => page(demand, before: before));
  // Scope selects chat members, not the lifetime of already issued Item refs.
  // A Main current tool ref remains readable after sealing into Children.
  bool _ownsItem(String id) =>
      _history.byId.containsKey(id) ||
      _history.payloads.containsKey(id) ||
      _api._pendingItems[threadId]?.containsKey(id) == true;

  Map<String, _DemoBody> _itemBodies(String id) {
    if (!_ownsItem(id)) throw _demoMissing();
    return _history.bodies[id] ?? const {};
  }

  @override
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  }) => _read(() {
    _demoDemand(demand);
    final bodies = _itemBodies(itemId);
    final entries = bodies.entries.toList();
    final start = continuation == null
        ? 0
        : boundary(continuation, 'manifest:$itemId', 0);
    final out = <ContentManifestEntry>[];
    String? next;
    if (_demoEncoded({'entries': [], 'continuation': null}) > demand.maxBytes) {
      throw _demoQueryFailure('InvalidDemand: manifest envelope does not fit');
    }
    var at = start;
    for (; at < entries.length && out.length < demand.maxItems; at++) {
      final entry = entries[at];
      final ref = ContentRef(
        databaseId: _history.epoch,
        target: BodyContentTarget(
          owner: ItemContentOwner(itemId: itemId),
          key: entry.key,
        ),
      );
      final payload = utf8.encode(
        jsonEncode({
          'key': entry.key,
          'byteLength': entry.value.length,
          'generation': '${entry.value.generation}',
          'mediaType': 'text/plain; charset=utf-8',
        }),
      );
      final candidate = ContentManifestEntry(
        key: entry.key,
        payload: payload,
        reference: ref,
      );
      final token = cursor('manifest:$itemId', 0, at + 1);
      final bytes = _demoEncoded({
        'entries': [
          for (final e in [...out, candidate])
            {
              'key': e.key,
              'payload': e.payload,
              'reference': contentRefToJson(e.reference),
            },
        ],
        'continuation': token,
      });
      if (bytes > demand.maxBytes) {
        if (out.isEmpty) {
          throw _demoQueryFailure('InvalidDemand: manifest entry does not fit');
        }
        break;
      }
      out.add(candidate);
      next = token;
    }
    return ContentManifestPage(
      entries: out,
      continuation: at < entries.length ? next : null,
    );
  });
  _DemoBody _body(ContentRef reference) {
    if (reference.databaseId != _history.epoch) {
      throw _demoQueryFailure('Wrong Demo database');
    }
    switch (reference.target) {
      case ItemPayloadTarget(:final itemId):
        if (!_ownsItem(itemId)) throw _demoMissing();
        return _history.payloads[itemId] ?? (throw _demoMissing());
      case BodyContentTarget(:final owner, :final key):
        switch (owner) {
          case DisplayObservationContentOwner(:final blockId, :final memberKey):
            return _history.bodies[jsonEncode([
                  'display-observation',
                  blockId,
                  memberKey,
                ])]?[key] ??
                (throw _demoMissing());
          case ItemContentOwner(:final itemId):
            return _itemBodies(itemId)[key] ?? (throw _demoMissing());
          case CurrentContentOwner(:final domain, :final id, :final revision):
            if (scope is! MainChatScope) throw _demoMissing();
            final workspace = _api._demoWorkspace(threadId);
            if (domain == 'plan' && id == threadId) {
              final plan = workspace.runtime.plan;
              if (plan == null || plan.revision != revision) throw _demoStale();
              if (key != 'plan.document' || plan.document == null) {
                throw _demoMissing();
              }
              // Owner data is prepared at publication, not materialized by a range read.
              return _history.planDocument ?? (throw _demoMissing());
            }
            if (domain != 'interactions' ||
                revision != _history.interactionRevision) {
              throw _demoStale();
            }
            return _history.currentBodies[(domain, id, key)] ??
                (throw _demoMissing());
        }
    }
  }

  ContentWindow _window(ContentRef reference, ContentRange range) {
    final body = _body(reference);
    final bytes = body.range(range.offset, range.maxBytes);
    return ContentWindow(
      offset: range.offset,
      bytes: bytes,
      generation: '${body.generation}',
      availableThrough: body.length,
      sealed: body.sealed,
    );
  }

  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) => _read(() => _window(reference, range));
  @override
  ConversationContentWatch watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    if (_closed || _api._runtimeExiting) throw _conversationClosedFailure;
    if (_watches.length >= 64) {
      throw _demoQueryFailure('Demo content watch limit exceeded');
    }
    final watch = _DemoContentWatch(this, reference, range);
    _watches.add(watch);
    return watch;
  }

  @override
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) => _read(() {
    _demoDemand(demand);
    if (scope is! MainChatScope || reference.databaseId != _history.epoch) {
      throw _demoMissing();
    }
    if (reference.collection != 'interactions' ||
        reference.revision != _history.interactionRevision) {
      throw _demoStale();
    }
    final source = _collection(reference.collection);
    final start = continuation == null
        ? 0
        : boundary(continuation, reference.collection, reference.revision);
    final out = <CurrentCollectionEntry>[];
    if (_demoEncoded({
          'revision': reference.revision,
          'entries': [],
          'continuation': null,
        }) >
        demand.maxBytes) {
      throw _demoQueryFailure(
        'InvalidDemand: collection envelope does not fit',
      );
    }
    var more = false;
    String? next;
    for (final row in source) {
      final index = row.$2;
      if (index < start) continue;
      if (out.length == demand.maxItems) {
        more = true;
        break;
      }
      final bytes = utf8.encode(jsonEncode(row.$3));
      PayloadData payload = InlinePayload(bytes: bytes);
      CurrentCollectionEntry candidate = CurrentCollectionEntry(
        id: row.$1,
        position: index,
        payload: payload,
      );
      final token = cursor(reference.collection, reference.revision, index + 1);
      int encoded() => _demoEncoded({
        'revision': reference.revision,
        'entries': [
          for (final e in [...out, candidate])
            {
              'id': e.id,
              'position': e.position,
              'payload': chatPayloadToJson(e.payload),
            },
        ],
        'continuation': token,
      });
      if (encoded() > demand.maxBytes) {
        final key = (reference.collection, row.$1, 'payload');
        _history.currentBodies.putIfAbsent(
          key,
          () => _DemoBody()..append(bytes),
        );
        payload = DeferredPayload(
          reference: ContentRef(
            databaseId: _history.epoch,
            target: BodyContentTarget(
              owner: CurrentContentOwner(
                domain: reference.collection,
                id: row.$1,
                revision: reference.revision,
              ),
              key: 'payload',
            ),
          ),
          byteLength: bytes.length,
        );
        candidate = CurrentCollectionEntry(
          id: row.$1,
          position: index,
          payload: payload,
        );
        if (encoded() > demand.maxBytes) {
          if (out.isEmpty) {
            throw _demoQueryFailure(
              'InvalidDemand: current entry does not fit',
            );
          }
          more = true;
          break;
        }
      }
      out.add(candidate);
      next = token;
    }
    // An exact-sized page may carry a cursor to one empty EOF page.
    return CurrentCollectionPage(
      revision: reference.revision,
      entries: out,
      continuation: more ? next : null,
    );
  });
  Iterable<(String, int, Map<String, Object?>)> _collection(String name) sync* {
    if (name != 'interactions') throw _demoMissing();
    final ordered = _api._demoWorkspace(threadId).interactions.toList()
      ..sort(
        (a, b) => _history.positions[('interaction', a.id)]!.compareTo(
          _history.positions[('interaction', b.id)]!,
        ),
      );
    for (final value in ordered) {
      yield (
        value.id,
        _history.positions[('interaction', value.id)]!,
        {
          'interactionId': value.id,
          'scope': {'threadId': value.threadId, 'turnId': value.turnId},
          'revision': value.revision,
          'content': {
            'kind': value.kind.name,
            'data': {
              ...switch (value.payload) {
                UserInputInteractionPayload(:final questions) => {
                  'questions': [
                    for (final question in questions)
                      {
                        'id': question.id,
                        'header': question.header,
                        'question': question.question,
                        'isOther': question.isOther,
                        'isSecret': question.isSecret,
                        'options': [
                          for (final option in question.options)
                            {
                              'label': option.label,
                              'description': option.description,
                            },
                        ],
                      },
                  ],
                },
                ToolApprovalInteractionPayload(
                  :final toolName,
                  :final arguments,
                  :final workingDirectory,
                  :final parentAgentId,
                ) =>
                  {
                    'request': {
                      'name': toolName,
                      'arguments': arguments,
                      'workingDirectory': workingDirectory,
                      'parentAgentId': parentAgentId,
                    },
                  },
                UnknownInteractionPayload() => throw _demoQueryFailure(
                  'Unknown interaction content',
                ),
              },
              'state': {
                'kind': 'pending',
                'data': {'operationId': value.id},
              },
            },
          },
          'createdAt': 0,
          'updatedAt': value.revision,
        },
      );
    }
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    for (final watch in _watches.toList()) {
      watch.requestClose();
    }
    for (final members in _displayReads.toList()) {
      members.requestClose();
    }
  }

  @override
  Future<void> close() {
    requestClose();
    return _closing ??= () async {
      // A failed watch must not prevent the other owned operations from joining.
      await Future.wait([
        ..._accepted,
        for (final watch in _watches.toList()) watch.close(),
        for (final members in _displayReads.toList()) members.close(),
      ]);
      _cursors.clear();
      _api._ownedHistoryReaders.remove(this);
    }().whenComplete(() => _closing = null);
  }
}

final class _DemoContentWatch implements ConversationContentWatch {
  _DemoContentWatch(this.reader, this.reference, this.range);
  final _DemoReader reader;
  final ContentRef reference;
  final ContentRange range;
  bool _dirty = true, _scheduled = false, _stopped = false, _paused = false;
  String? _last;
  Future<void>? _delivery;
  Future<void>? _closing;
  bool _joined = false;
  late final StreamController<ContentWindow> _controller = StreamController(
    sync: true,
    onListen: () {
      if (_stopped || reader._closed) return;
      reader._history.changes.add(wake);
      wake();
    },
    onPause: () {
      _paused = true;
    },
    onResume: () {
      _paused = false;
      wake();
    },
    // Stream cancellation only stops delivery. The original watch remains
    // registered until its explicit handle successfully joins.
    onCancel: requestClose,
  );
  @override
  Stream<ContentWindow> get windows => _controller.stream;
  void wake() {
    _dirty = true;
    if (_paused || _stopped || _scheduled || !_controller.hasListener) return;
    _scheduled = true;
    _delivery = Future<void>.microtask(() {
      _scheduled = false;
      if (_paused || _stopped || !_dirty) return;
      _dirty = false;
      try {
        final window = reader._window(reference, range);
        final stamp =
            '${window.generation}:${window.availableThrough}:${window.sealed}';
        if (stamp != _last) {
          _last = stamp;
          _controller.add(window);
        }
        if (window.sealed) requestClose();
      } catch (error, stack) {
        _controller.addError(error, stack);
        requestClose();
      }
    });
  }

  @override
  void requestClose() {
    if (_stopped) return;
    _stopped = true;
    reader._history.changes.remove(wake);
    unawaited(_controller.close());
  }

  @override
  Future<void> close() {
    requestClose();
    if (_joined) return Future.value();
    return _closing ??= () async {
      await _delivery;
      _joined = true;
      reader._watches.remove(this);
    }().whenComplete(() => _closing = null);
  }
}

int _demoBatchBytes(ChatBatch batch) => _demoEncoded({
  'placement': batch.placement.name,
  'entries': batch.entries.map(completedEntryToJson).toList(),
  'before': batch.before,
  'fromSeq': batch.fromSeq,
  'throughSeq': batch.throughSeq,
});

class _DemoConversationFeed implements ConversationFeed {
  _DemoConversationFeed(
    this._api,
    this.threadId,
    this._history,
    ChatScope scope,
    this._demand, {
    this.timeline = false,
  }) : subscriptionId = 'demo:${newStudioCorrelationId()}',
       reader = _DemoReader(_api, threadId, _history, scope) {
    _demoDemand(_demand);
    if (timeline) {
      _initialTimeline = reader.timelinePage(_demand, initial: true);
    } else {
      _initial = reader.page(_demand);
    }
    _completed = reader.h0;
    _currentRevision = _history.revision;
    // No await separates source registration and capture. Failed preparation
    // has not admitted an owned resource; events.listen never creates the cut.
    _api._ownedHistoryReaders.add(reader);
    (_api._conversationFeeds[threadId] ??= {}).add(this);
  }
  final DemoStudioTransport _api;
  final _DemoHistory _history;
  final ReadDemand _demand;
  final bool timeline;
  TimelineBatch? _initialTimeline;
  // One bounded (Pt, live_t) cut owns this catch-up, including a separate live
  // frame when the last immutable prefix consumes the byte budget.
  LiveDisplayWindow? _displayTarget;
  int _displayThrough = 0, _displayRevision = -1;
  @override
  final String threadId;
  @override
  final String subscriptionId;
  @override
  final _DemoReader reader;
  ChatBatch? _initial;
  late int _completed, _currentRevision;
  int _sent = 0, _acked = 0, _phase = 0;
  bool _started = false,
      _claimed = false,
      _closed = false,
      _ended = false,
      _pendingCurrent = false;
  Future<void>? _closing;
  late final StreamController<ConversationFrame> _controller = StreamController(
    onListen: () {
      _started = true;
      _flush();
    },
    onCancel: () {
      if (!_ended) {
        requestClose();
        return close();
      }
    },
  );
  @override
  Stream<ConversationFrame> get events {
    if (_closed) throw _conversationClosedFailure;
    if (_claimed) {
      throw _demoQueryFailure('Conversation events already have a consumer');
    }
    _claimed = true;
    return _controller.stream;
  }

  void _send(ConversationEvent event, {bool terminal = false}) {
    if (!_started || _ended) return;
    if (!terminal) _sent++;
    _controller.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: _sent,
        event: event,
      ),
    );
    if (terminal) {
      _ended = true;
      _unregister();
      unawaited(_controller.close());
    }
  }

  ActivitySnapshot _activity() => ActivitySnapshot(
    revision: _history.revision,
    completedThrough: _completed,
    executionPresent: _api._demoWorkspace(threadId).runtime.execution != null,
    entries: [
      for (final atom in _history.activeAtoms.values)
        ActivityEntry(
          identity: atom.tool != null
              ? ForegroundToolActivityIdentity(callId: atom.tool!.callId)
              : ModelPartActivityIdentity(atomId: atom.id),
          atom: atom,
        ),
    ],
  );

  void _flush() {
    if (_closed || _ended || !_started || _sent != _acked) return;
    try {
      if (_phase == 0) {
        _phase = 1;
        if (timeline) {
          final batch = _initialTimeline!;
          _displayThrough = batch.throughPos;
          _displayRevision = batch.live!.revision;
          _send(ConversationTimelineEvent(batch: batch));
          _initialTimeline = null;
        } else {
          _send(ConversationChatEvent(batch: _initial!));
        }
        _initial = null;
        return;
      }
      if (!timeline && _phase == 1 && reader.scope is MainChatScope) {
        _phase = 2;
        _send(ConversationActivityEvent(snapshot: _activity()));
        return;
      }
      _phase = 2;
      if (timeline) {
        if (_displayTarget != null ||
            _displayThrough < _history.displayHead ||
            _displayRevision != _history.displayRevision) {
          final target = _displayTarget ??= reader.timelineTarget(_demand);
          final batch = reader.timelineAppend(_demand, _displayThrough, target);
          _displayThrough = batch.throughPos;
          if (batch.live != null) {
            _displayRevision = batch.live!.revision;
            _displayTarget = null;
          }
          _send(ConversationTimelineEvent(batch: batch));
        }
        return;
      }
      final head = _history.head;
      if (_completed < head) {
        final selected = <CompletedEntry>[];
        var through = _completed;
        for (final entry in reader.source()) {
          if (entry.completionSeq <= _completed || entry.completionSeq > head) {
            continue;
          }
          final candidate = reader.fitEntry(
            entry,
            0,
            main: reader.scope is MainChatScope,
          );
          final trial = ChatBatch(
            placement: ChatPlacement.append,
            entries: [...selected, candidate],
            fromSeq: _completed,
            throughSeq: entry.completionSeq,
          );
          if (selected.length == _demand.maxItems ||
              _demoBatchBytes(trial) > _demand.maxBytes) {
            if (selected.isEmpty) {
              throw _demoQueryFailure(
                'InvalidDemand: completion envelope does not fit',
              );
            }
            break;
          }
          selected.add(candidate);
          through = entry.completionSeq;
        }
        // Filtering can advance the global checked prefix with no visible entry.
        if (selected.length < _demand.maxItems) through = head;
        final from = _completed;
        _completed = through;
        _send(
          ConversationChatEvent(
            batch: ChatBatch(
              placement: ChatPlacement.append,
              entries: selected,
              fromSeq: from,
              throughSeq: through,
            ),
          ),
        );
        return;
      }
      if (reader.scope is MainChatScope &&
          (_pendingCurrent || _currentRevision != _history.revision)) {
        _pendingCurrent = false;
        _currentRevision = _history.revision;
        _send(ConversationActivityEvent(snapshot: _activity()));
      }
    } catch (error) {
      _send(
        ConversationFailureEvent(
          failure: _studioFailure(error) as StudioFailure,
        ),
        terminal: true,
      );
    }
  }

  void _contentChanged() {
    if (_closed || _ended) return;
    _pendingCurrent = true;
    _flush();
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    if (_closed) throw _conversationClosedFailure;
    if (deliverySequence < 0 || deliverySequence > _sent) {
      throw _demoQueryFailure('ACK exceeds sent sequence');
    }
    if (deliverySequence <= _acked) return;
    _acked = deliverySequence;
    _flush();
  }

  void _unregister() {
    _api._conversationFeeds[threadId]?.remove(this);
    if (_api._conversationFeeds[threadId]?.isEmpty ?? false) {
      _api._conversationFeeds.remove(threadId);
    }
  }

  @override
  void requestClose() {
    if (_closed) return;
    reader.requestClose();
    _send(const ConversationClosedEvent(), terminal: true);
    _closed = true;
    _initial = null;
    _initialTimeline = null;
    _displayTarget = null;
    _unregister();
    if (!_ended) {
      _ended = true;
      unawaited(_controller.close());
    }
  }

  @override
  Future<void> close() {
    requestClose();
    return _closing ??= () async {
      await reader.close();
      _api._ownedConversationFeeds.remove(this);
    }().whenComplete(() => _closing = null);
  }
}

/// The independent Demo state subscription. It carries only State, Failure and
/// Closed frames with its own identity, sequence and ACK budget; content never
/// flows here and state never flows through the content feed.
final class _DemoConversationStateFeed implements ConversationStateFeed {
  _DemoConversationStateFeed(this._api, this.threadId)
    : subscriptionId = 'demo-state:${newStudioCorrelationId()}' {
    _initialState = ConversationStateEvent(
      frame: ThreadSnapshotFrame(
        schemaVersion: threadSchemaVersion,
        completedHistoryVersion: 1,
        workspace: _api._snapshotOf(_api._demoWorkspace(threadId)),
      ),
    );
    // No await separates source registration and capture. Failed preparation
    // has not admitted an owned resource; events.listen never creates the cut.
    _api._ownedConversationStateFeeds.add(this);
    (_api._conversationStateFeeds[threadId] ??= {}).add(this);
  }

  final DemoStudioTransport _api;
  @override
  final String threadId;
  @override
  final String subscriptionId;
  ConversationStateEvent? _initialState;
  int _sent = 0, _acked = 0;
  bool _started = false,
      _claimed = false,
      _closed = false,
      _ended = false,
      _pending = false;
  Future<void>? _closing;
  late final StreamController<ConversationFrame> _controller = StreamController(
    onListen: () {
      _started = true;
      _flush();
    },
    onCancel: () {
      if (!_ended) {
        requestClose();
        return close();
      }
    },
  );

  @override
  Stream<ConversationFrame> get events {
    if (_closed) throw _conversationClosedFailure;
    if (_claimed) {
      throw _demoQueryFailure('Conversation state events already consumed');
    }
    _claimed = true;
    return _controller.stream;
  }

  void _send(ConversationEvent event, {bool terminal = false}) {
    if (!_started || _ended) return;
    if (!terminal) _sent++;
    _controller.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: _sent,
        event: event,
      ),
    );
    if (terminal) {
      _ended = true;
      _unregister();
      unawaited(_controller.close());
    }
  }

  // State changes coalesce into one snapshot per delivery credit, captured at
  // the flush cut; the SDK gate keeps snapshot application monotonic.
  void _flush() {
    if (_closed || _ended || !_started || _sent != _acked) return;
    try {
      if (_initialState != null) {
        final initial = _initialState!;
        _initialState = null;
        _send(initial);
        return;
      }
      if (_pending) {
        _pending = false;
        _send(
          ConversationStateEvent(
            frame: ThreadSnapshotFrame(
              schemaVersion: threadSchemaVersion,
              completedHistoryVersion: 1,
              workspace: _api._snapshotOf(_api._demoWorkspace(threadId)),
            ),
          ),
        );
      }
    } catch (error) {
      _send(
        ConversationFailureEvent(
          failure: _studioFailure(error) as StudioFailure,
        ),
        terminal: true,
      );
    }
  }

  void _stateChanged() {
    if (_closed || _ended) return;
    _pending = true;
    _flush();
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    if (_closed) throw _conversationClosedFailure;
    if (deliverySequence < 0 || deliverySequence > _sent) {
      throw _demoQueryFailure('ACK exceeds sent state sequence');
    }
    if (deliverySequence <= _acked) return;
    _acked = deliverySequence;
    _flush();
  }

  void _unregister() {
    _api._conversationStateFeeds[threadId]?.remove(this);
    if (_api._conversationStateFeeds[threadId]?.isEmpty ?? false) {
      _api._conversationStateFeeds.remove(threadId);
    }
  }

  @override
  void requestClose() {
    if (_closed) return;
    _send(const ConversationClosedEvent(), terminal: true);
    _closed = true;
    _initialState = null;
    _unregister();
    if (!_ended) {
      _ended = true;
      unawaited(_controller.close());
    }
  }

  @override
  Future<void> close() {
    requestClose();
    return _closing ??= () async {
      _api._ownedConversationStateFeeds.remove(this);
    }().whenComplete(() => _closing = null);
  }
}
