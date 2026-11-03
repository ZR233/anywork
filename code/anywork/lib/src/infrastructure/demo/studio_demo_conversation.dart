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
  ChildrenChatScope(:final parentId) => 'children:$parentId',
};
ChatAtom _demoCopy(
  ChatAtom atom, {
  PayloadData? payload,
  int? completionSeq,
  ChatSourceState? sourceState,
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
  lifecycle: atom.lifecycle,
  turnId: atom.turnId,
  attemptId: atom.attemptId,
  tool: atom.tool,
  textChannel: atom.textChannel,
  startedAt: atom.startedAt,
  finishedAt: atom.finishedAt,
  contents: atom.contents,
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
  final Map<String, ChatAtom> activeAtoms = {};
  final Map<ChatSourceId, ChatSourceState> sourceStates = {};
  final Map<ChatSourceId, int> _sourceOrders = {};
  int _facts = 0;
  ChatFactPosition _fact() =>
      ChatFactPosition(effectSeq: ++_facts, suborder: 0);
  List<ChatEntry> entries(
    Iterable<ChatAtom> atoms, {
    Map<ChatSourceId, ChatSourceState>? states,
  }) {
    final cut = states ?? sourceStates;
    return [
      for (final atom in atoms)
        ChatAtomEntry(_demoCopy(atom, sourceState: cut[atom.source])),
    ];
  }

  final String epoch = 'demo-chat:${newStudioCorrelationId()}';
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
  final Set<void Function()> changes = {};
  int revision = 0;
  int get head => items.length;
  void prepareCurrent(ThreadWorkspace workspace) {
    final plan = workspace.runtime.plan;
    if (plan?.document == null) {
      planDocument = null;
    } else if (planRevision != plan!.revision) {
      planDocument = _DemoBody()..update(plan.document!.markdown);
    }
    planRevision = plan?.revision;
    for (final interaction in workspace.interactions) {
      positions.putIfAbsent((
        'interaction',
        interaction.id,
      ), () => _nextPosition++);
    }
  }

  void changed(ThreadWorkspace workspace) {
    revision++;
    currentBodies.clear();
    prepareCurrent(workspace);
    for (final wake in changes.toList()) {
      wake();
    }
  }

  List<_DemoFrozen> index(ChatScope scope) =>
      _indices[_demoScopeKey(scope)] ?? const [];
  bool accept(ChatAtom message, ChatScope scope) {
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
      payloads[message.id] = _DemoBody()
        ..append(bytes)
        ..sealed = true;
    }
    items.add(record);
    byId[message.id] = record;
    (_indices[key] ??= []).add(record);
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
    if (!accept(message, const MainChatScope())) return;
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
  _DemoReader(
    this._api,
    this.threadId,
    this._history,
    this.scope,
    this._currentItems,
  ) : h0 = _history.head,
      _sourceCut = Map.of(_history.sourceStates);
  final int _currentItems;
  final DemoStudioTransport _api;
  final _DemoHistory _history;
  final ChatScope scope;
  final int h0;
  final Map<ChatSourceId, ChatSourceState> _sourceCut;
  final Map<String, (int, Map<ChatSourceId, ChatSourceState>)> _windowCursors =
      {};
  @override
  final String threadId;
  final Map<String, (String, int, int)> _cursors = {};
  final Set<Future<void>> _accepted = {};
  final Set<_DemoContentWatch> _watches = {};
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

  ChatBatch page(
    ReadDemand demand, {
    String? before,
    CurrentProjection? current,
    int? completionSeq,
    bool inclusive = false,
  }) {
    _demoDemand(demand);
    if (completionSeq != null &&
        (completionSeq <= 0 || completionSeq > _history.head)) {
      throw _demoQueryFailure('Invalid observed completion position');
    }
    final window = completionSeq == null
        ? null
        : before == null
        ? (
            _history.head,
            Map<ChatSourceId, ChatSourceState>.of(_history.sourceStates),
          )
        : _windowCursors[before];
    if (completionSeq != null && before != null && window == null) {
      throw _demoQueryFailure('Unknown original ordinary window cursor');
    }
    final cut = window?.$1 ?? h0;
    final states = window?.$2 ?? _sourceCut;
    final kind = completionSeq == null
        ? 'history'
        : 'window:${inclusive ? 'inclusive' : 'exclusive'}:$completionSeq';
    final end = before == null
        ? completionSeq ?? h0
        : boundary(before, kind, cut);
    final source = _history.index(scope);
    var low = 0, high = source.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (source[mid].order < end ||
          before == null &&
              (completionSeq == null || inclusive) &&
              source[mid].order == end) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final selected = <ChatAtom>[];
    String? next;
    for (var i = low - 1; i >= 0 && selected.length < demand.maxItems; i--) {
      final candidate = fit(source[i].message, demand.maxBytes);
      final staged = [candidate, ...selected];
      final token = cursor(kind, cut, source[i].order);
      if (window != null) _windowCursors[token] = window;
      final trial = ChatBatch(
        placement: before == null && completionSeq == null
            ? ChatPlacement.set
            : ChatPlacement.prepend,
        entries: _history.entries(staged, states: states),
        before: token,
        current: current,
      );
      if (_demoBatchBytes(trial) > demand.maxBytes) {
        // Try deferring even a medium payload when the remaining page is smaller.
        final compact = fit(source[i].message, 0);
        final smaller = ChatBatch(
          placement: trial.placement,
          entries: _history.entries([compact, ...selected], states: states),
          before: token,
          current: current,
        );
        if (_demoBatchBytes(smaller) > demand.maxBytes) {
          if (selected.isEmpty) {
            throw _demoQueryFailure('InvalidDemand: envelope does not fit');
          }
          break;
        }
        selected.insert(0, compact);
      } else {
        selected.insert(0, candidate);
      }
      next = token;
      if (i == 0) next = null;
    }
    final batch = ChatBatch(
      placement: before == null && completionSeq == null
          ? ChatPlacement.set
          : ChatPlacement.prepend,
      entries: _history.entries(selected, states: states),
      before: next,
      current: current,
    );
    if (_demoBatchBytes(batch) > demand.maxBytes) {
      throw _demoQueryFailure('InvalidDemand: current envelope does not fit');
    }
    return batch;
  }

  @override
  Future<ChatBatch> readBefore({
    required int completionSeq,
    String? before,
    required ReadDemand demand,
  }) => _read(() => page(demand, before: before, completionSeq: completionSeq));

  @override
  Future<ChatBatch> readAt({
    required int completionSeq,
    String? before,
    required ReadDemand demand,
  }) => _read(
    () => page(
      demand,
      before: before,
      completionSeq: completionSeq,
      inclusive: true,
    ),
  );

  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) => _read(() => page(demand, before: before));
  // Scope selects chat members, not the lifetime of already issued Item refs.
  // A Main current tool ref remains readable after sealing into Children.
  bool _ownsItem(String id) =>
      _history.byId.containsKey(id) ||
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
            if (revision != _history.revision) throw _demoStale();
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
    if (reference.revision != _history.revision) throw _demoStale();
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
    if (name == 'members' || name == 'tools') {
      for (final item in _api._pendingItemsOf(threadId)) {
        if (name == 'tools' && item.content.kind != _DemoContentKind.tool) {
          continue;
        }
        yield (
          item.id,
          _history.positions[('member', item.id)]!,
          {
            'id': item.id,
            'kind': item.content.kind.name,
            if (item.content.invocation != null)
              'invocation': item.content.invocation!.toJson(),
            'bodies': [
              for (final e
                  in (_history.bodies[item.id] ?? const <String, _DemoBody>{})
                      .entries)
                {
                  'key': e.key,
                  'byteLength': e.value.length,
                  'reference': contentRefToJson(
                    ContentRef(
                      databaseId: _history.epoch,
                      target: BodyContentTarget(
                        owner: ItemContentOwner(itemId: item.id),
                        key: e.key,
                      ),
                    ),
                  ),
                },
            ],
          },
        );
      }
    } else if (name == 'interactions') {
      final ordered = _api._demoWorkspace(threadId).interactions.toList()
        ..sort(
          (a, b) => _history.positions[('interaction', a.id)]!.compareTo(
            _history.positions[('interaction', b.id)]!,
          ),
        );
      for (final i in ordered) {
        yield (
          i.id,
          _history.positions[('interaction', i.id)]!,
          {'id': i.id, 'revision': i.revision, 'kind': i.kind.name},
        );
      }
    } else {
      throw _demoMissing();
    }
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    for (final watch in _watches.toList()) {
      watch.requestClose();
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

Map<String, Object?> _demoCurrentJson(CurrentProjection c) => {
  'sources': c.sources.map(chatSourceStateToJson).toList(),
  'atoms': c.atoms.map(chatAtomToJson).toList(),
  'sourceEffectSeq': c.sourceEffectSeq,
  'logicalStatus': c.logicalStatus.name,
  'executionPresent': c.executionPresent,
  'active': c.active == null
      ? null
      : {
          'id': c.active!.id,
          'kind': c.active!.kind.name,
          'summary': c.active!.summary,
          'thinkingSummary': c.active!.thinkingSummary,
          'thinkingSeconds': c.active!.thinkingSeconds,
          'toolCount': c.active!.toolCount,
          'backgroundToolCount': c.active!.backgroundToolCount,
          'latestTool': c.active!.latestTool == null
              ? null
              : {
                  'callId': c.active!.latestTool!.callId,
                  'name': c.active!.latestTool!.name,
                  'state': c.active!.latestTool!.state.name,
                },
        },
  'activeTurn': c.activeTurn == null
      ? null
      : {'id': c.activeTurn!.id, 'phase': c.activeTurn!.phase.name},
  'plan': c.plan == null
      ? null
      : {
          'revision': c.plan!.revision,
          'phase': c.plan!.phase.name,
          'document': c.plan!.document == null
              ? null
              : contentRefToJson(c.plan!.document!),
        },
  'interactions': c.interactions == null
      ? null
      : _demoCollectionJson(c.interactions!),
  'previews': [
    for (final p in c.previews)
      {
        'id': p.id,
        'role': p.role.name,
        'textChannel': p.textChannel?.name,
        'text': p.text,
        'reference': contentRefToJson(p.reference),
      },
  ],
  'collections': [for (final r in c.collections) _demoCollectionJson(r)],
};
Map<String, Object?> _demoCollectionJson(CurrentCollectionRef r) => {
  'databaseId': r.databaseId,
  'collection': r.collection,
  'revision': r.revision,
};
int _demoBatchBytes(ChatBatch batch) => _demoEncoded({
  'placement': batch.placement.name,
  'entries': batch.entries.map(chatEntryToJson).toList(),
  'before': batch.before,
  'current': batch.current == null ? null : _demoCurrentJson(batch.current!),
});

CurrentProjection _demoCurrent(_DemoReader reader, int budget) {
  final api = reader._api, history = reader._history;
  final workspace = api._demoWorkspace(reader.threadId);
  final activity = workspace.activity,
      turn = workspace.activeTurn,
      plan = workspace.runtime.plan;
  history.prepareCurrent(workspace);
  final collections = <CurrentCollectionRef>[];
  CurrentCollectionRef collection(String name) {
    final ref = CurrentCollectionRef(
      databaseId: history.epoch,
      collection: name,
      revision: history.revision,
    );
    collections.add(ref);
    return ref;
  }

  if (api._pendingItemsOf(reader.threadId).isNotEmpty) collection('members');
  if (api
      ._pendingItemsOf(reader.threadId)
      .any((i) => i.content.kind == _DemoContentKind.tool)) {
    collection('tools');
  }
  final interactions = workspace.interactions.isEmpty
      ? null
      : collection('interactions');
  ContentRef? document;
  if (plan?.document != null) {
    document = ContentRef(
      databaseId: history.epoch,
      target: BodyContentTarget(
        owner: CurrentContentOwner(
          domain: 'plan',
          id: reader.threadId,
          revision: plan!.revision,
        ),
        key: 'plan.document',
      ),
    );
  }
  final previews = <CurrentContentPreview>[];
  final pending = api._pendingItemsOf(reader.threadId);
  // Only a bounded tail preview is pushed; complete member/tool lists are paged.
  final last = pending.lastOrNull;
  if (last != null) {
    final entry = history.bodies[last.id]?.entries.lastOrNull;
    if (entry != null) {
      final bytes = entry.value.range(0, (budget ~/ 16).clamp(1, 256));
      var end = bytes.length;
      while (end > 0) {
        try {
          utf8.decode(bytes.sublist(0, end));
          break;
        } on FormatException {
          end--;
        }
      }
      previews.add(
        CurrentContentPreview(
          id: last.id,
          textChannel: last.content.kind == _DemoContentKind.text
              ? last.content.textChannel
              : null,
          role: switch (last.content.kind) {
            _DemoContentKind.thinking => CurrentContentRole.reasoning,
            _DemoContentKind.tool =>
              entry.key == 'tool.arguments'
                  ? CurrentContentRole.toolArguments
                  : CurrentContentRole.toolOutput,
            _ => CurrentContentRole.response,
          },
          text: utf8.decode(bytes.sublist(0, end)),
          reference: ContentRef(
            databaseId: history.epoch,
            target: BodyContentTarget(
              owner: ItemContentOwner(itemId: last.id),
              key: entry.key,
            ),
          ),
        ),
      );
    }
  }
  return CurrentProjection(
    sourceEffectSeq: history.revision,
    logicalStatus: workspace.thread.status,
    executionPresent: workspace.runtime.execution != null,
    sources: [
      for (final source
          in history.activeAtoms.values.map((atom) => atom.source).toSet())
        history.sourceStates[source]!,
    ],
    atoms: history.activeAtoms.values.take(reader._currentItems).toList(),
    active: activity == null
        ? null
        : CurrentActivityHead(
            id: activity.identity,
            kind: activity.kind,
            summary: _capDemoText(activity.summary, 128),
            thinkingSummary: activity.thinkingSummary == null
                ? null
                : _capDemoText(activity.thinkingSummary!, 128),
            thinkingSeconds: activity.thinkingSeconds,
            toolCount: activity.tools.count,
            backgroundToolCount: activity.tools.background,
            latestTool: activity.tools.latestStarted == null
                ? null
                : CurrentToolHead(
                    callId: activity.tools.latestStarted!.callId,
                    name: _capDemoText(activity.tools.latestStarted!.name, 128),
                    state: activity.tools.latestStarted!.state,
                  ),
          ),
    activeTurn: turn == null
        ? null
        : CurrentTurnHead(
            id: turn.turnId,
            phase: turn.state.activity ?? StudioTurnActivity.preparing,
          ),
    plan: plan == null
        ? null
        : CurrentPlanHead(
            revision: plan.revision,
            phase: plan.state,
            document: document,
          ),
    interactions: interactions,
    previews: previews,
    collections: collections,
  );
}

String _capDemoText(String text, int maxBytes) {
  // Only bounded heads use this helper. Body range reads use the chunk owner.
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in text.runes) {
    final s = String.fromCharCode(rune);
    final n = utf8.encode(s).length;
    if (bytes + n > maxBytes) break;
    out.write(s);
    bytes += n;
  }
  return out.toString();
}

final class _DemoConversationFeed implements ConversationFeed {
  _DemoConversationFeed(
    this._api,
    this.threadId,
    this._history,
    ChatScope scope,
    this._demand,
  ) : subscriptionId = 'demo:${newStudioCorrelationId()}',
      reader = _DemoReader(_api, threadId, _history, scope, _demand.maxItems) {
    _demoDemand(_demand);
    _initial = reader.page(
      _demand,
      current: scope is MainChatScope
          ? _demoCurrent(reader, _demand.maxBytes)
          : null,
    );
    _completed = reader.h0;
    _currentRevision = _history.revision;
    _initialState = ConversationStateEvent(
      frame: ThreadSnapshotFrame(
        workspace: _api._snapshotOf(_api._demoWorkspace(threadId)),
      ),
    );
    // No await separates source registration and capture. Failed preparation
    // has not admitted an owned resource; events.listen never creates the cut.
    _api._ownedHistoryReaders.add(reader);
    (_api._conversationFeeds[threadId] ??= {}).add(this);
  }
  final DemoStudioTransport _api;
  final _DemoHistory _history;
  final ReadDemand _demand;
  @override
  final String threadId;
  @override
  final String subscriptionId;
  @override
  final _DemoReader reader;
  ChatBatch? _initial;
  ConversationStateEvent? _initialState;
  late int _completed, _currentRevision;
  int _sent = 0, _acked = 0, _phase = 0;
  bool _started = false,
      _claimed = false,
      _closed = false,
      _ended = false,
      _pendingState = false,
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

  void _flush() {
    if (_closed || _ended || !_started || _sent != _acked) return;
    try {
      if (_phase == 0) {
        _phase = 1;
        _send(_initialState!);
        _initialState = null;
        return;
      }
      if (_phase == 1) {
        _phase = 2;
        _send(ConversationChatEvent(batch: _initial!));
        _initial = null;
        return;
      }
      if (_pendingState) {
        _pendingState = false;
        _send(
          ConversationStateEvent(
            frame: ThreadSnapshotFrame(
              workspace: _api._snapshotOf(_api._demoWorkspace(threadId)),
            ),
          ),
        );
        return;
      }
      final source = _history.index(reader.scope);
      var low = 0, high = source.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (source[mid].order <= _completed) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      final messages = <ChatAtom>[];
      var through = _completed;
      CurrentProjection? current;
      final head = _history.head;
      // Do not let current retire a member before its completion is delivered.
      for (
        var i = low;
        i < source.length && messages.length < _demand.maxItems;
        i++
      ) {
        var message = reader.fit(source[i].message, _demand.maxBytes);
        final trial = ChatBatch(
          placement: ChatPlacement.append,
          entries: _history.entries([...messages, message]),
        );
        if (_demoBatchBytes(trial) > _demand.maxBytes) {
          message = reader.fit(source[i].message, 0);
          if (_demoBatchBytes(
                ChatBatch(
                  placement: ChatPlacement.append,
                  entries: _history.entries([...messages, message]),
                ),
              ) >
              _demand.maxBytes) {
            if (messages.isEmpty) {
              throw _demoQueryFailure(
                'InvalidDemand: message envelope does not fit',
              );
            }
            break;
          }
        }
        messages.add(message);
        through = source[i].order;
      }
      var caughtUp = low + messages.length == source.length;
      if (caughtUp &&
          reader.scope is MainChatScope &&
          (_pendingCurrent || _currentRevision != _history.revision)) {
        current = _demoCurrent(reader, _demand.maxBytes);
        if (_demoBatchBytes(
              ChatBatch(
                placement: ChatPlacement.append,
                entries: _history.entries(messages),
                current: current,
              ),
            ) >
            _demand.maxBytes) {
          // Compact the final handoff, never detach current from the completion
          // that retires its members. Earlier prefixes may omit current.
          for (var i = 0; i < messages.length; i++) {
            messages[i] = reader.fit(messages[i], 0);
          }
          if (_demoBatchBytes(
                ChatBatch(
                  placement: ChatPlacement.append,
                  entries: _history.entries(messages),
                  current: current,
                ),
              ) >
              _demand.maxBytes) {
            if (messages.length < 2) {
              throw _demoQueryFailure(
                'InvalidDemand: completion/current handoff does not fit',
              );
            }
            messages.removeLast();
            through = source[low + messages.length - 1].order;
            caughtUp = false;
            current = null;
          }
        }
      }
      if (messages.isEmpty && current == null) {
        if (caughtUp) _completed = head;
        return;
      }
      if (current != null) {
        _pendingCurrent = false;
        _currentRevision = _history.revision;
      }
      _completed = caughtUp ? head : through;
      _send(
        ConversationChatEvent(
          batch: ChatBatch(
            placement: ChatPlacement.append,
            entries: _history.entries(messages),
            current: current,
          ),
        ),
      );
    } catch (error) {
      // Producer termination does not retire the independent read lease.
      _send(
        ConversationFailureEvent(
          failure: _studioFailure(error) as StudioFailure,
        ),
        terminal: true,
      );
    }
  }

  void _stateChanged(ThreadStreamFrame frame) {
    if (_closed || _ended) return;
    _pendingState = true;
    _pendingCurrent = true;
    _flush();
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
      await reader.close();
      _api._ownedConversationFeeds.remove(this);
    }().whenComplete(() => _closing = null);
  }
}
