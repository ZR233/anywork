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
) => _demoItem(
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

String _demoScopeKey(ChatScope scope) => jsonEncode({
  'queryClass': switch (scope.queryClass) {
    ExactChatClass(:final value) => value,
    AllChatClasses() => null,
  },
  'parentId': scope.parentId,
});
String? _demoTurnParent(String? turnId) =>
    turnId == null ? null : '4:turn$turnId';
bool _demoHasActivity(ChatScope scope) => scope.parentId == null;
ChatAtom _demoCopy(
  ChatAtom atom, {
  PayloadData? payload,
  ChatSourceState? sourceState,
  ChatAtomLifecycle? lifecycle,
  List<ChatAtomContent>? contents,
  bool frozen = false,
}) => ChatAtom(
  id: atom.id,
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
  final ChatScope scope;
}

final class _DemoChange {
  const _DemoChange(this.update);
  final ThreadWorkspaceUpdate? update;
}

final class _DemoHistory {
  final List<DisplayBlock> displayBlocks = [];
  final Map<String, _DemoDisplayScript> displayScripts = {};
  final Map<String, String> displayMembership = {};
  final Map<DisplayBlockRef, List<DisplayMemberHead>> displayHeads = {};
  final Map<String, int> displayMemberRevisions = {};
  int historyLastOrder = 0;
  int get displayHead => displayBlocks.lastOrNull?.blockOrder ?? 0;
  final String epoch = newStudioCorrelationId();
  final Map<String, ChatAtom> activeAtoms = {};
  final Map<ChatSourceId, ChatSourceState> sourceStates = {};
  final Map<ChatSourceId, int> _sourceOrders = {};
  int _facts = 0;
  ChatFactPosition _fact() =>
      ChatFactPosition(effectSeq: ++_facts, suborder: 0);
  final List<_DemoFrozen> items = [];
  final Map<String, _DemoFrozen> byId = {};
  final Map<String, Map<String, _DemoBody>> bodies = {};
  final Map<String, _DemoBody> payloads = {};
  final Map<(String, String, String), _DemoBody> currentBodies = {};
  final Map<String, List<Object?>> stateCollections = {};
  final Map<String, int> stateCollectionVersions = {};
  final Map<String, String> _stateCollectionSignatures = {};
  final Map<(String, String), int> positions = {};
  int _nextPosition = 0;
  _DemoBody? planDocument;
  int? planRevision;
  int interactionRevision = 0;
  String? _interactionSignature;
  final Set<void Function(_DemoChange)> changes = {};
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

  void changed(ThreadWorkspace workspace, {ThreadWorkspaceUpdate? update}) {
    revision++;
    prepareCurrent(workspace);
    final change = _DemoChange(update);
    for (final wake in changes.toList()) {
      wake(change);
    }
  }

  Iterable<_DemoFrozen> index(ChatScope scope) => items.where(
    (record) =>
        (scope.queryClass is AllChatClasses ||
            (record.scope.queryClass as ExactChatClass).value ==
                (scope.queryClass as ExactChatClass).value) &&
        (scope.parentId == null || record.scope.parentId == scope.parentId),
  );
  void validateScope(ChatScope scope) {
    if (scope.queryClass case ExactChatClass(:final value)) {
      if (value.isEmpty) throw _demoQueryFailure('Empty record class');
    }
  }

  bool accept(ChatAtom message, ChatScope scope) {
    validateScope(scope);
    if (message.id.isEmpty) throw _demoQueryFailure('Empty message identity');
    if (scope.queryClass is! ExactChatClass) {
      throw _demoQueryFailure('Producer must declare the record class');
    }
    final key = _demoScopeKey(scope);
    final old = byId[message.id];
    message = _demoCopy(message, frozen: true);
    if (old != null) {
      if (_demoScopeKey(old.scope) != key ||
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
    final record = _DemoFrozen(message, head + 1, scope);
    if (message.payload case InlinePayload(:final bytes)) {
      payloads[message.id] = _DemoBody()
        ..append(bytes)
        ..sealed = true;
    }
    items.add(record);
    byId[message.id] = record;
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
    final memberScope = ChatScope.conversation(
      parentId: _demoTurnParent(item.turnId),
    );
    if (!accept(message, memberScope)) return;
    updateDisplayMember(item.id);
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

final class _DemoReadSource {
  _DemoReadSource(this._api, this.threadId, this._history, this.scope)
    : h0 = _history.head,
      itemH0 = _history.head;
  final DemoStudioTransport _api;
  final _DemoHistory _history;
  final ChatScope scope;
  final int h0;
  final int itemH0;
  final String threadId;
  final Map<String, (String, int, int)> _cursors = {};
  final Set<Future<void>> _accepted = {};
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
          target: ItemPayloadTarget(itemId: message.id),
        ),
        byteLength: length,
      ),
    );
  }

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
            if (!_demoHasActivity(scope)) throw _demoMissing();
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

  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) => _read(() {
    _demoDemand(demand);
    if (!_demoHasActivity(scope) || reference.ownerId != _history.epoch) {
      throw _demoMissing();
    }
    if (reference.collection != 'interactions' ||
        reference.revision != _history.interactionRevision) {
      throw _demoStale();
    }
    final rows = _api._demoWorkspace(threadId).interactions.toList()
      ..sort(
        (a, b) => _history.positions[('interaction', a.id)]!.compareTo(
          _history.positions[('interaction', b.id)]!,
        ),
      );
    final source = <(String, int, Map<String, Object?>)>[
      for (final row in rows)
        (
          row.id,
          _history.positions[('interaction', row.id)]!,
          {
            'interactionId': row.id,
            'scope': {'threadId': row.threadId, 'turnId': row.turnId},
            'revision': row.revision,
            'kind': row.kind.name,
            'title': row.title,
            'body': row.body,
          },
        ),
    ];
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
      CurrentPayloadData payload = InlineCurrentPayload(bytes: bytes);
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
              'payload': switch (e.payload) {
                InlineCurrentPayload(:final bytes) => {
                  'kind': 'inline',
                  'bytes': bytes,
                },
                DeferredCurrentPayload(:final reference, :final byteLength) => {
                  'kind': 'deferred',
                  'reference': {
                    'ownerId': reference.ownerId,
                    'domain': reference.domain,
                    'entityId': reference.entityId,
                    'contentKey': reference.contentKey,
                    'generation': reference.generation,
                  },
                  'byteLength': byteLength,
                },
              },
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
        payload = DeferredCurrentPayload(
          reference: CurrentContentRef(
            ownerId: _history.epoch,
            domain: 'collection:${reference.collection}',
            entityId: '${row.$2}',
            contentKey: 'entry',
            generation: '${reference.revision}',
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

  void requestClose() {
    _closed = true;
  }

  Future<void> close() => _closing ??= () async {
    requestClose();
    await Future.wait(_accepted.toList());
  }();
}
