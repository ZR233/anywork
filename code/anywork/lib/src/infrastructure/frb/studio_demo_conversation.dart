part of 'studio_api.dart';

// Frozen only at Demo's Plan request producer boundary. Legacy seeded requests
// can lack document identity; their completion never borrows the current Plan.
typedef _DemoPlanRequest = ({
  PendingInteraction interaction,
  String markdown,
  PlanDocumentView? document,
  int? planRevision,
});

typedef _DemoPlanDecision = ({
  ConversationPlanDecision decision,
  String feedback,
});

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
    return (decision: ConversationPlanDecision.approved, feedback: '');
  }
  final feedback = answers
      .where((answer) => answer != agentSessionPlanReviseAnswer)
      .map((answer) => answer.trim())
      .where((answer) => answer.isNotEmpty)
      .join('\n');
  if (revision || feedback.isNotEmpty) {
    return (
      decision: ConversationPlanDecision.revisionRequested,
      feedback: feedback,
    );
  }
  throw _demoInvalidPlanAnswer(
    'Plan confirmation must select Approve, Revise, or provide revision feedback',
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
    descriptor: ConversationPlanDescriptor(
      interactionId: request.interaction.id,
      documentVersion: request.document?.version,
      contentHash: request.document?.contentHash,
      decision: decision.decision,
    ),
    fields: {
      const ThreadPlanDocumentFieldView(): request.markdown,
      if (decision.feedback.isNotEmpty)
        const ThreadPlanFeedbackFieldView(): decision.feedback,
    },
    invocation: null,
  ),
);

// These are Demo's private script facts, never public timeline items. A null
// descriptor means that the member has not reached its own reliable completion.
enum _DemoContentKind { text, thinking, tool, completed }

typedef _DemoContent = ({
  _DemoContentKind kind,
  ConversationDescriptor? descriptor,
  Map<ThreadContentFieldView, String> fields,
  ConversationToolInvocation? invocation,
});

ConversationContentOutcome? _demoOutcome(ThreadContentLifecycleView value) =>
    switch (value) {
      StreamingThreadContentView() => null,
      CompletedThreadContentView() => ConversationContentCompleted(value),
      FailedThreadContentView() => ConversationContentFailed(value),
      CancelledThreadContentView() => ConversationContentCancelled(value),
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
    descriptor: outcome == null
        ? null
        : ConversationTextDescriptor(
            channel: channel,
            attachments: attachments,
            outcome: outcome,
          ),
    fields: {const ThreadTextFieldView(): text},
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
    descriptor: outcome == null
        ? null
        : ConversationThinkingDescriptor(outcome: outcome),
    fields: {
      for (var i = 0; i < summary.length; i++)
        ThreadThinkingSummaryFieldView(i): summary[i],
      for (var i = 0; i < content.length; i++)
        ThreadThinkingContentFieldView(i): content[i],
    },
    invocation: null,
  );
}

_DemoContent _demoTool({
  required ConversationToolInvocation invocation,
  ConversationToolState? outcome,
  String arguments = '',
  String? result,
}) => (
  kind: _DemoContentKind.tool,
  descriptor: outcome == null
      ? null
      : ConversationToolDescriptor(invocation: invocation, state: outcome),
  fields: {
    const ThreadToolArgumentsFieldView(): arguments,
    const ThreadToolResultFieldView(): ?result,
  },
  invocation: invocation,
);

_DemoContent _demoTurn(StudioTurnState state, {String? inputId}) => (
  kind: _DemoContentKind.completed,
  descriptor: ConversationTurnDescriptor(
    inputId: inputId,
    outcome: switch (state) {
      CompletedStudioTurnState() => ConversationTurnCompleted(state),
      FailedStudioTurnState() => ConversationTurnFailed(state),
      CancelledStudioTurnState() => ConversationTurnCancelled(state),
      BudgetLimitedStudioTurnState() => ConversationTurnBudgetLimited(state),
      QueuedStudioTurnState() || RunningStudioTurnState() => throw StateError(
        'An active Turn is not a completed conversation item',
      ),
    },
  ),
  fields: {},
  invocation: null,
);

final class _DemoItem {
  _DemoItem({
    required this.id,
    required this.threadId,
    required this.turnId,
    required this.updatedAt,
    required this.content,
  }) {
    final result = content.fields[const ThreadToolResultFieldView()];
    if (content.kind == _DemoContentKind.tool && result != null) {
      outputParts = [
        if (result.isNotEmpty)
          ThreadActivityToolOutputPart(partId: '$id:output:0', text: result),
      ];
    }
  }
  final String id;
  final String threadId;
  final String? turnId;
  final DateTime updatedAt;
  final _DemoContent content;
  // null means no output observation; [] means an observed empty output.
  List<ThreadActivityToolOutputPart>? outputParts;
  String? textFor(ThreadContentFieldView field) => content.fields[field];
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
}) {
  final next = _demoItem(
    id: item.id,
    threadId: item.threadId,
    turnId: item.turnId,
    updatedAt: updatedAt ?? item.updatedAt,
    content: content,
  );
  if (content.kind == _DemoContentKind.tool &&
      content.descriptor == null &&
      next.outputParts == null) {
    next.outputParts = item.outputParts == null
        ? null
        : List.of(item.outputParts!);
  }
  return next;
}

const _demoItemPreviewLimitBytes = 256 * 1024;
const _demoPageLimitBytes = 2 * 1024 * 1024;
const _demoBodyPreviewBytes = 32 * 1024;
const _demoToolPreviewBytes = 4 * 1024;
const _demoActivityTextBytes = 64 * 1024;

/// Full completed facts live here once. Preview delivery and query scopes both
/// read this same epoch; neither owns a mutable public timeline.
final class _DemoHistory {
  _DemoHistory() : epoch = 'demo-history:${newStudioCorrelationId()}';
  final String epoch;
  final List<ConversationItem> items = [];
  final Map<String, ConversationItem> byId = {};
  int get head => items.length;

  bool accept(
    ConversationItem candidate,
    bool Function(Object?, Object?) sameFacts,
  ) {
    if (candidate.id.isEmpty ||
        candidate.header.threadId.isEmpty ||
        candidate.fields.map((f) => f.field).toSet().length !=
            candidate.fields.length ||
        candidate.fields.any((f) => f.totalBytes != f.previewBytes)) {
      throw _conversationQueryFailure;
    }
    final previous = byId[candidate.id];
    if (previous != null) {
      if (!sameFacts(_demoItemFacts(previous), _demoItemFacts(candidate))) {
        throw const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'A completed Demo item cannot be changed',
          retryable: false,
          correlationId: 'demo-completion-conflict',
        );
      }
      return false;
    }
    // Allocate only at canonical insertion, independently of script/effect order.
    final item = ConversationItem(
      header: ConversationItemHeader(
        id: candidate.id,
        threadId: candidate.header.threadId,
        turnId: candidate.header.turnId,
        appendSeq: head + 1,
        sourceEffectSeq: candidate.header.sourceEffectSeq,
        sealedAt: candidate.header.sealedAt,
      ),
      descriptor: candidate.descriptor,
      source: candidate.source,
      fields: _demoPublicFields(candidate),
    );
    _demoPreview(
      item,
    ); // Reject inadmissible structure before assigning sequence.
    items.add(item);
    byId[item.id] = item;
    return true;
  }
}

final class _DemoConversationFeed implements ConversationFeed {
  _DemoConversationFeed(this._api, this.threadId, this._history, this._resume)
    : subscriptionId = 'demo-${newStudioCorrelationId()}';
  final DemoStudioTransport _api;
  final _DemoHistory _history;
  final ConversationCompletionCursor? _resume;
  @override
  final String threadId;
  @override
  final String subscriptionId;
  int _sent = 0;
  int _acked = 0;
  int _completedSeq = 0;
  int _activityRevision = 0;
  bool _initialized = false;
  bool _pendingState = true;
  bool _pendingActivity = true;
  bool _closed = false;
  bool _claimed = false;
  bool _started = false;
  bool _terminal = false;
  Future<void>? _closing;
  Iterator<ConversationEvent>? _activityDelivery;
  late final StreamController<ConversationFrame> _controller = StreamController(
    onListen: _start,
    onCancel: () {
      requestClose();
      return close();
    },
  );
  bool get _credit => _sent - _acked < 2;

  @override
  Stream<ConversationFrame> get events {
    if (_closed) throw _conversationClosedFailure;
    if (_claimed) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'Conversation events already have a consumer',
        retryable: false,
        correlationId: 'demo-conversation-consumer',
      );
    }
    _claimed = true;
    return _controller.stream;
  }

  void _start() {
    if (_closed || _api._runtimeExiting) {
      requestClose();
      unawaited(_controller.close());
      return;
    }
    _started = true;
    (_api._conversationFeeds[threadId] ??= {}).add(this);
    _flush();
  }

  void _send(ConversationEvent event, {bool terminal = false}) {
    if (!_started || _terminal) return;
    if (!terminal && !_credit) {
      throw StateError('Demo delivery credit exhausted');
    }
    _sent++;
    _controller.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: _sent,
        event: event,
      ),
    );
    if (terminal) _terminal = true;
  }

  void _flush() {
    if (_closed || !_started) return;
    try {
      while (_credit && !_closed) {
        // A staged activity publication must reach Commit before another Begin.
        final delivery = _activityDelivery;
        if (delivery != null) {
          if (delivery.moveNext()) {
            _send(delivery.current);
          } else {
            _activityDelivery = null;
          }
          continue;
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
          continue;
        }
        if (!_initialized) {
          _initialized = true;
          final resume = _resume;
          if (resume != null && resume.timelineEpoch == _history.epoch) {
            if (resume.appendSeq < 0 || resume.appendSeq > _history.head) {
              throw _conversationQueryFailure;
            }
            _completedSeq = resume.appendSeq;
          } else {
            final baseline = _baseline();
            _completedSeq = baseline.completedCursor.appendSeq;
            _send(
              resume == null
                  ? ConversationBaselineEvent(baseline: baseline)
                  : ConversationUpdateEvent(
                      update: ConversationReset(baseline),
                    ),
            );
            continue;
          }
        }
        if (_completedSeq < _history.head || _pendingActivity) {
          final batch = _nextBatch();
          // Catch up from the oldest debt. Never replace the missing prefix by head.
          if (batch != null && batch.throughSeq < _history.head) {
            _completedSeq = batch.throughSeq;
            _send(ConversationUpdateEvent(update: batch));
            continue;
          }
          _pendingActivity = false;
          _activityDelivery = _activityEvents(batch).iterator;
          continue;
        }
        break;
      }
    } catch (error) {
      _send(
        ConversationFailureEvent(
          failure: _studioFailure(error) as StudioFailure,
        ),
        terminal: true,
      );
      requestClose();
    }
  }

  ConversationBaseline _baseline() {
    final page = _demoPage(_history, threadId);
    return ConversationBaseline(
      subscriptionId: subscriptionId,
      timelineEpoch: _history.epoch,
      items: page.items,
      before: page.before,
      hasOlder: page.hasOlder,
      completedCursor: ConversationCompletionCursor(
        timelineEpoch: _history.epoch,
        appendSeq: _history.head,
      ),
    );
  }

  ConversationBatch? _nextBatch() {
    if (_completedSeq == _history.head) return null;
    final items = <ConversationItem>[];
    var bytes = 128;
    for (
      var i = _completedSeq;
      i < _history.items.length && items.length < conversationPageDefaultLimit;
      i++
    ) {
      final preview = _demoPreview(_history.items[i]);
      if (items.isNotEmpty && bytes + preview.bytes > _demoPageLimitBytes) {
        break;
      }
      bytes += preview.bytes;
      items.add(preview.item);
    }
    return ConversationBatch(
      subscriptionId: subscriptionId,
      timelineEpoch: _history.epoch,
      fromSeq: _completedSeq,
      throughSeq: items.last.header.appendSeq,
      items: items,
    );
  }

  /// Capture one coherent live/completed boundary. The iterator holds only this
  /// bounded transaction and emits text blocks on credit; it is not an event queue.
  Iterable<ConversationEvent> _activityEvents(ConversationBatch? batch) sync* {
    final revision = ++_activityRevision;
    final generation = subscriptionId;
    final activity = _api._demoWorkspace(threadId).activity;
    final pending = _api._pendingItemsOf(threadId).toList(growable: false);
    final reasoning = <ActivityPartMetadata>[];
    final response = <ActivityPartMetadata>[];
    final tools = <ActivityToolMetadata>[];
    final regions = <(ActivityRegion, String)>[];
    var totalBytes = 0;
    void add(ActivityRegion region, String text) {
      totalBytes += utf8.encode(text).length;
      regions.add((region, text));
    }

    for (final item in pending) {
      switch (item.content.kind) {
        case _DemoContentKind.thinking:
          // Preserve original segments; summary is only the small activity label.
          for (final field in item.content.fields.entries) {
            if (field.key case ThreadThinkingContentFieldView(
              :final chunkIndex,
            )) {
              final id = '${item.id}:$chunkIndex';
              reasoning.add(
                ActivityPartMetadata(
                  itemId: id,
                  complete: false,
                  totalBytes: utf8.encode(field.value).length,
                ),
              );
              add(
                ActivityRegion(ActivityRegionKind.reasoning, id),
                field.value,
              );
            }
          }
        case _DemoContentKind.text:
          final text = item.textFor(const ThreadTextFieldView()) ?? '';
          response.add(
            ActivityPartMetadata(
              itemId: item.id,
              complete: false,
              totalBytes: utf8.encode(text).length,
            ),
          );
          add(ActivityRegion(ActivityRegionKind.response, item.id), text);
        case _DemoContentKind.tool:
          final invocation = item.content.invocation!;
          final arguments = item.textFor(const ThreadToolArgumentsFieldView());
          final parts = item.outputParts;
          tools.add(
            ActivityToolMetadata(
              callId: invocation.toolCallId,
              name: invocation.name,
              taskId: invocation.taskId,
              state: ThreadActivityToolState.running,
              argumentsBytes: arguments == null
                  ? null
                  : utf8.encode(arguments).length,
              outputBytes: parts?.fold<int>(
                0,
                (n, p) => n + utf8.encode(p.text).length,
              ),
              outputParts: [
                for (final part
                    in parts ?? const <ThreadActivityToolOutputPart>[])
                  ActivityToolOutputMetadata(
                    partId: part.partId,
                    totalBytes: utf8.encode(part.text).length,
                  ),
              ],
            ),
          );
          if (arguments != null) {
            add(
              ActivityRegion(
                ActivityRegionKind.toolArguments,
                invocation.toolCallId,
              ),
              arguments,
            );
          }
          for (final part in parts ?? const <ThreadActivityToolOutputPart>[]) {
            add(
              ActivityRegion.toolOutput(
                callId: invocation.toolCallId,
                partId: part.partId,
              ),
              part.text,
            );
          }
        case _DemoContentKind.completed:
          throw StateError('Completed item remained active');
      }
    }
    yield ConversationActivityContentEvent(
      frame: ActivityBegin(
        generation: generation,
        revision: revision,
        baseRevision: null,
        activity: activity,
        reasoning: reasoning,
        response: response,
        tools: tools,
        totalBytes: totalBytes,
      ),
    );
    for (final (region, text) in regions) {
      final bytes = utf8.encode(text);
      var start = 0;
      // Empty observed regions need an explicit replace as well.
      var first = true;
      do {
        var end = start + _demoActivityTextBytes;
        if (end > bytes.length) end = bytes.length;
        while (end < bytes.length &&
            end > start &&
            (bytes[end] & 0xc0) == 0x80) {
          end--;
        }
        final block = utf8.decode(bytes.sublist(start, end));
        yield ConversationActivityContentEvent(
          frame: ActivityText(
            generation: generation,
            revision: revision,
            operations: [
              first
                  ? ActivityReplace(region, block)
                  : ActivityAppend(region, block),
            ],
          ),
        );
        start = end;
        first = false;
      } while (start < bytes.length);
    }
    // Completion acceptance precedes live publication in the SDK Commit path.
    yield ConversationActivityContentEvent(
      frame: ActivityCommit(generation: generation, revision: revision),
      completed: batch,
    );
    if (batch != null) _completedSeq = batch.throughSeq;
  }

  void _stateChanged(ThreadStreamFrame frame) {
    if (_closed) return;
    if (frame case ThreadNotificationFrame(update: ThreadActivityUpdate())) {
      _pendingActivity = true;
    } else {
      _pendingState = true;
    }
    _flush();
  }

  void _contentChanged() {
    if (_closed) return;
    _pendingActivity = true;
    _flush();
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    if (_closed) throw _conversationClosedFailure;
    if (deliverySequence < 0 || deliverySequence > _sent) {
      throw _conversationQueryFailure;
    }
    if (deliverySequence <= _acked) return;
    _acked = deliverySequence;
    _flush();
  }

  @override
  void requestClose() {
    if (_closed) return;
    if (_credit) _send(const ConversationClosedEvent(), terminal: true);
    _closed = true;
    _activityDelivery = null;
    _api._conversationFeeds[threadId]?.remove(this);
    if (_api._conversationFeeds[threadId]?.isEmpty ?? false) {
      _api._conversationFeeds.remove(threadId);
    }
    if (_claimed) unawaited(_controller.close());
  }

  @override
  Future<void> close() => _closing ??= Future<void>.sync(() {
    requestClose();
    // No asynchronous producer task survives this boundary. A paused consumer's
    // stream.done is not the producer's termination signal.
    _api._ownedConversationFeeds.remove(this);
  });
}

final class _DemoHistoryReader implements ConversationHistoryReader {
  _DemoHistoryReader(this._api, this.threadId, this._history);
  final DemoStudioTransport _api;
  final _DemoHistory _history;
  @override
  final String threadId;
  @override
  String get timelineEpoch => _history.epoch;
  bool _closed = false;
  final Set<Future<void>> _accepted = {};
  Future<void>? _closing;

  Future<T> _read<T>(T Function() query) {
    if (_closed || _api._runtimeExiting) {
      return Future.error(_conversationClosedFailure);
    }
    // Synchronous admission and registration; close cannot race past accepted work.
    final result = Future<T>.microtask(query);
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _accepted.add(settled);
    unawaited(settled.then((_) => _accepted.remove(settled)));
    return result;
  }

  @override
  Future<ConversationPage> page({
    ConversationQueryCursor? before,
    int? limit,
  }) =>
      _read(() => _demoPage(_history, threadId, before: before, limit: limit));

  @override
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) => _read(() {
    if (query.timelineEpoch != timelineEpoch) throw _conversationQueryFailure;
    _validateConversationField(query.field);
    final maxBytes = query.maxBytes ?? 64 * 1024;
    if (maxBytes < conversationDetailMinBytes ||
        maxBytes > conversationDetailMaxBytes) {
      throw _conversationQueryFailure;
    }
    final item = _history.byId[itemId];
    final field = item?.fieldFor(query.field);
    if (item == null || field == null) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'The completed Demo field is unavailable',
        retryable: false,
        correlationId: 'demo-history-detail-not-found',
      );
    }
    final bytes = utf8.encode(field.text);
    var start = 0;
    if (query.continuation case final cursor?) {
      final data = _demoDecodeCursor(cursor);
      if (data.length != 6 ||
          data[0] != 'detail' ||
          data[1] != threadId ||
          data[2] != timelineEpoch ||
          data[3] != itemId ||
          !_api._sameDemoFacts(data[4], _demoFieldToken(query.field)) ||
          data[5] is! int) {
        throw _conversationQueryFailure;
      }
      start = data[5] as int;
      if (start < 0 ||
          start > bytes.length ||
          (start < bytes.length && (bytes[start] & 0xc0) == 0x80)) {
        throw _conversationQueryFailure;
      }
    }
    var end = start + maxBytes;
    if (end > bytes.length) end = bytes.length;
    while (end < bytes.length && end > start && (bytes[end] & 0xc0) == 0x80) {
      end--;
    }
    return ConversationDetailChunk(
      threadId: threadId,
      timelineEpoch: timelineEpoch,
      itemId: itemId,
      field: query.field,
      text: utf8.decode(bytes.sublist(start, end)),
      totalBytes: bytes.length,
      continuation: end == bytes.length
          ? null
          : _demoCursor([
              'detail',
              threadId,
              timelineEpoch,
              itemId,
              _demoFieldToken(query.field),
              end,
            ]),
    );
  });

  @override
  void requestClose() {
    _closed = true;
  }

  @override
  Future<void> close() {
    requestClose();
    return _closing ??= () async {
      await Future.wait(_accepted.toList());
      _api._ownedHistoryReaders.remove(this);
    }();
  }
}

ConversationPage _demoPage(
  _DemoHistory history,
  String threadId, {
  ConversationQueryCursor? before,
  int? limit,
}) {
  final size = limit ?? conversationPageDefaultLimit;
  if (size < 1 || size > conversationPageMaxLimit) {
    throw _conversationQueryFailure;
  }
  var boundary = history.head + 1;
  if (before != null) {
    final data = _demoDecodeCursor(before);
    if (data.length != 4 ||
        data[0] != 'page' ||
        data[1] != threadId ||
        data[2] != history.epoch ||
        data[3] is! int) {
      throw _conversationQueryFailure;
    }
    boundary = data[3] as int;
    if (boundary < 1 || boundary > history.head + 1) {
      throw _conversationQueryFailure;
    }
  }
  final staged = <ConversationItem>[];
  var bytes = 128;
  for (var i = boundary - 2; i >= 0 && staged.length < size; i--) {
    final preview = _demoPreview(history.items[i]);
    if (staged.isNotEmpty && bytes + preview.bytes > _demoPageLimitBytes) break;
    staged.add(preview.item);
    bytes += preview.bytes;
  }
  final items = staged.reversed.toList(growable: false);
  final oldest = items.firstOrNull?.header.appendSeq;
  final hasOlder = oldest != null && oldest > 1;
  return ConversationPage(
    threadId: threadId,
    timelineEpoch: history.epoch,
    items: items,
    before: hasOlder
        ? _demoCursor(['page', threadId, history.epoch, oldest])
        : null,
    hasOlder: hasOlder,
  );
}

ConversationQueryCursor _demoCursor(List<Object?> data) =>
    ConversationQueryCursor(
      'dc3.${base64Url.encode(utf8.encode(jsonEncode(data)))}',
    );

List<Object?> _demoDecodeCursor(ConversationQueryCursor cursor) {
  try {
    if (!cursor.token.startsWith('dc3.')) throw _conversationQueryFailure;
    final data = jsonDecode(
      utf8.decode(base64Url.decode(cursor.token.substring(4))),
    );
    if (data is! List<Object?>) throw _conversationQueryFailure;
    return data;
  } catch (_) {
    throw _conversationQueryFailure;
  }
}

Object _demoFieldToken(ThreadContentFieldView field) => switch (field) {
  ThreadTextFieldView() => ['text'],
  ThreadThinkingSummaryFieldView(:final chunkIndex) => ['summary', chunkIndex],
  ThreadThinkingContentFieldView(:final chunkIndex) => [
    'reasoning',
    chunkIndex,
  ],
  ThreadToolArgumentsFieldView() => ['arguments'],
  ThreadToolResultFieldView() => ['result'],
  ThreadToolOutputArtifactsFieldView() => ['artifacts'],
  ThreadPlanDocumentFieldView() => ['plan'],
  ThreadPlanFeedbackFieldView() => ['feedback'],
  ThreadRawPayloadFieldView(:final payloadIndex) => ['raw', payloadIndex],
  ThreadToolUserInputFieldView(:final questionIndex, :final part) => [
    'input',
    questionIndex,
    switch (part) {
      ThreadUserInputHeaderFieldPartView() => ['header'],
      ThreadUserInputQuestionFieldPartView() => ['question'],
      ThreadUserInputAnswerFieldPartView(:final answerIndex) => [
        'answer',
        answerIndex,
      ],
      ThreadUserInputOptionLabelFieldPartView(:final optionIndex) => [
        'label',
        optionIndex,
      ],
      ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex) => [
        'description',
        optionIndex,
      ],
    },
  ],
};

List<ConversationFieldPreview> _demoPublicFields(ConversationItem item) {
  final descriptor = item.descriptor;
  if (descriptor is! ConversationToolDescriptor ||
      descriptor.userInput == null) {
    return item.fields;
  }
  final input = descriptor.userInput!;
  final hidden = <int>{};
  for (var i = 0; i < input.questions.length; i++) {
    final q = input.questions[i];
    if (q.isSecret ||
        (input.state is ConversationUserInputResolved &&
            (input.state as ConversationUserInputResolved).answers.any(
              (a) => a.questionId == q.id && a.redacted,
            ))) {
      hidden.add(i);
    }
  }
  return item.fields
      .where((field) {
        if (field.field case ThreadToolUserInputFieldView(
          :final questionIndex,
        )) {
          return questionIndex >= 0 &&
              questionIndex < input.questions.length &&
              !hidden.contains(questionIndex);
        }
        // Tool argument/result bodies can contain the complete submitted answer map.
        return hidden.isEmpty ||
            (field.field is! ThreadToolArgumentsFieldView &&
                field.field is! ThreadToolResultFieldView &&
                field.field is! ThreadToolOutputArtifactsFieldView);
      })
      .toList(growable: false);
}

({ConversationItem item, int bytes}) _demoPreview(ConversationItem full) {
  final structure = _demoStructureBytes(full);
  if (structure > _demoItemPreviewLimitBytes) throw _timelineBudgetExceeded();
  var remaining = _demoItemPreviewLimitBytes - structure;
  if (remaining > _demoBodyPreviewBytes) remaining = _demoBodyPreviewBytes;
  final fields = <ConversationFieldPreview>[];
  var kept = 0;
  for (final field in full.fields) {
    var budget = remaining;
    if ((field.field is ThreadToolArgumentsFieldView ||
            field.field is ThreadToolResultFieldView) &&
        budget > _demoToolPreviewBytes) {
      budget = _demoToolPreviewBytes;
    }
    final text = _capDemoText(field.text, budget);
    final bytes = utf8.encode(text).length;
    remaining -= bytes;
    kept += bytes;
    fields.add(
      ConversationFieldPreview(
        field: field.field,
        text: text,
        totalBytes: field.totalBytes,
      ),
    );
  }
  return (
    item: ConversationItem(
      header: full.header,
      descriptor: full.descriptor,
      source: full.source,
      fields: fields,
    ),
    bytes: structure + kept,
  );
}

String _capDemoText(String value, int budget) {
  final bytes = utf8.encode(value);
  if (bytes.length <= budget) return value;
  var end = budget;
  while (end > 0 && (bytes[end] & 0xc0) == 0x80) {
    end--;
  }
  return utf8.decode(bytes.sublist(0, end));
}

StudioFailure _timelineBudgetExceeded() => const StudioFailure(
  code: StudioFailureCode.overloaded,
  message: 'The conversation item cannot fit the preview budget',
  retryable: false,
  correlationId: 'demo-conversation-budget',
);

// Typed facts support value-idempotent canonical insertion, including descriptor
// payloads. No descriptor is compared by identity or converted through raw JSON.
Object _demoItemFacts(ConversationItem item) => [
  item.id,
  item.header.threadId,
  item.header.turnId,
  item.header.sourceEffectSeq,
  item.header.sealedAt,
  switch (item.source) {
    ConversationContentSource() => 'content',
    ConversationRecoverySource(:final notice) => notice,
  },
  _demoDescriptorFacts(item.descriptor),
  {
    for (final field in _demoPublicFields(item))
      field.field: [field.text, field.totalBytes],
  },
];

Object _demoAttachmentFacts(ThreadAttachmentView a) => [
  a.id,
  a.modality,
  a.mediaType,
  a.filename,
  a.byteSize,
  a.width,
  a.height,
];

Object _demoContentOutcomeFacts(ConversationContentOutcome o) => switch (o) {
  ConversationContentCompleted(:final value) => [
    'completed',
    value.completedAt,
  ],
  ConversationContentFailed(:final value) => [
    'failed',
    value.failedAt,
    value.error,
  ],
  ConversationContentCancelled(:final value) => [
    'cancelled',
    value.cancelledAt,
    value.reason,
  ],
};

Object? _demoOutputFacts(ConversationToolOutputDescriptor? output) =>
    output == null
    ? null
    : [output.exitCode, output.attachments.map(_demoAttachmentFacts).toList()];

Object _demoDescriptorFacts(ConversationDescriptor d) => switch (d) {
  ConversationTextDescriptor(
    :final channel,
    :final attachments,
    :final outcome,
  ) =>
    [
      'text',
      channel,
      attachments.map(_demoAttachmentFacts).toList(),
      _demoContentOutcomeFacts(outcome),
    ],
  ConversationThinkingDescriptor(:final outcome) => [
    'thinking',
    _demoContentOutcomeFacts(outcome),
  ],
  ConversationPlanDescriptor(
    :final interactionId,
    :final documentVersion,
    :final contentHash,
    :final decision,
  ) =>
    ['plan', interactionId, documentVersion, contentHash, decision],
  ConversationRawDescriptor(
    :final origin,
    :final payloads,
    :final notice,
    :final recordedAt,
  ) =>
    [
      'raw',
      origin,
      payloads.map((p) => [p.format, p.version]).toList(),
      notice,
      recordedAt,
    ],
  ConversationToolDescriptor(
    :final invocation,
    :final state,
    :final userInput,
    :final wait,
  ) =>
    [
      'tool',
      invocation.toolCallId,
      invocation.callId,
      invocation.providerItemId,
      invocation.name,
      invocation.workingDirectory,
      invocation.taskId,
      switch (state) {
        ConversationToolBackgroundStarted(:final startedAt) => [
          'background',
          startedAt,
        ],
        ConversationToolInterrupted(:final interruptedAt, :final reason) => [
          'interrupted',
          interruptedAt,
          reason,
        ],
        ConversationToolSucceeded(:final completedAt, :final output) => [
          'succeeded',
          completedAt,
          _demoOutputFacts(output),
        ],
        ConversationToolFailed(
          :final failedAt,
          :final failure,
          :final output,
        ) =>
          [
            'failed',
            failedAt,
            failure.kind,
            failure.message,
            _demoOutputFacts(output),
          ],
        ConversationToolDenied(:final deniedAt, :final reason) => [
          'denied',
          deniedAt,
          reason,
        ],
        ConversationToolCancelled(:final cancelledAt, :final reason) => [
          'cancelled',
          cancelledAt,
          reason,
        ],
      },
      if (userInput != null)
        [
          userInput.interactionId,
          userInput.questions
              .map((q) => [q.id, q.isOther, q.isSecret, q.optionCount])
              .toList(),
          switch (userInput.state) {
            ConversationUserInputCancelled() => 'cancelled',
            ConversationUserInputResolved(:final answers) =>
              answers
                  .map((a) => [a.questionId, a.answerCount, a.redacted])
                  .toList(),
          },
        ]
      else
        null,
      if (wait != null)
        [
          wait.state,
          wait.messagesReady,
          switch (wait.intent) {
            ThreadWaitTimerIntentView(:final durationMs) => [
              'timer',
              durationMs,
            ],
            ThreadWaitEventsIntentView(:final targets, :final timeoutMs) => [
              'events',
              timeoutMs,
              targets
                  .map(
                    (t) => [
                      t.taskId,
                      t.toolName,
                      t.summary,
                      t.summaryTruncated,
                      t.status,
                    ],
                  )
                  .toList(),
            ],
          },
        ]
      else
        null,
    ],
  ConversationAgentDescriptor(:final identity, :final outcome) => [
    'agent',
    identity.id,
    identity.path,
    identity.parentPath,
    identity.role,
    identity.task,
    identity.depth,
    switch (outcome) {
      ConversationAgentSucceeded(:final value) => [
        'succeeded',
        value.completedAt,
        value.summary,
      ],
      ConversationAgentDenied(:final value) => [
        'denied',
        value.deniedAt,
        value.reason,
      ],
      ConversationAgentCancelled(:final value) => [
        'cancelled',
        value.cancelledAt,
        value.reason,
      ],
      ConversationAgentFailed(:final value) => [
        'failed',
        value.failedAt,
        value.error,
      ],
    },
  ],
  ConversationTurnDescriptor(:final inputId, :final outcome) => [
    'turn',
    inputId,
    switch (outcome) {
      ConversationTurnCompleted(:final value) => [
        'completed',
        value.startedAt,
        value.completedAt,
        value.completion,
      ],
      ConversationTurnFailed(:final value) => [
        'failed',
        value.startedAt,
        value.completedAt,
        value.failure.category,
        value.failure.providerKind,
        value.failure.code,
        value.failure.httpStatus,
        value.failure.message,
        value.failure.retryable,
        value.failure.retryAfterMs,
      ],
      ConversationTurnCancelled(:final value) => [
        'cancelled',
        value.startedAt,
        value.requestedAt,
        value.completedAt,
        switch (value.cause) {
          UnspecifiedTurnCancellation() => ['unspecified'],
          UserRequestedTurnCancellation() => ['user'],
          RuntimeShutdownTurnCancellation() => ['shutdown'],
          AgentClosedTurnCancellation() => ['closed'],
          InterruptedTurnCancellation() => ['interrupted'],
          RecoveryTurnCancellation() => ['recovery'],
          CoalescedTurnCancellation(:final targetTurnId) => [
            'coalesced',
            targetTurnId,
          ],
        },
      ],
      ConversationTurnBudgetLimited(:final value) => [
        'budget',
        value.startedAt,
        value.completedAt,
        value.limit.kind,
        value.limit.usage.modelSteps,
        value.limit.usage.toolCalls,
        value.limit.usage.waitCalls,
        value.limit.usage.elapsedMs,
        switch (value.rollover) {
          RolloverNotAttempted() => ['notAttempted'],
          RolloverSucceeded() => ['succeeded'],
          RolloverFailed(:final error) => ['failed', error],
        },
      ],
    },
  ],
  ConversationInferenceDescriptor(
    :final inferenceId,
    :final model,
    :final outcome,
  ) =>
    [
      'inference',
      inferenceId,
      model,
      switch (outcome) {
        ConversationInferenceCompleted(:final value) => [
          'completed',
          value.completedAt,
          value.usage.promptTokens,
          value.usage.completionTokens,
          value.usage.cachedPromptTokens,
          value.usage.totalTokens,
        ],
        ConversationInferenceFailed(:final value) => [
          'failed',
          value.failedAt,
          value.error,
        ],
        ConversationInferenceCancelled(:final value) => [
          'cancelled',
          value.cancelledAt,
          value.reason,
        ],
      },
    ],
  ConversationSkillDescriptor(:final value) => [
    'skill',
    value.name,
    value.source,
    value.providerId,
    value.resourceBase.kind,
    value.resourceBase.value,
    value.cause.kind,
    value.cause.id,
    value.activatedAt,
  ],
  ConversationFileDescriptor(:final value) => [
    'file',
    value.path,
    value.mediaType,
    value.completedAt,
  ],
  ConversationContextCompactionDescriptor(:final value) => [
    'compaction',
    value.beforeTokens,
    value.afterTokens,
    value.compactedAt,
  ],
};

// Conservative estimate for this typed representation. Fields have their own
// fixed per-entry cost; full bodies are separately previewed or read in chunks.
int _demoStructureBytes(ConversationItem item) {
  int facts(Object? value) {
    if (value == null) return 8;
    if (value is String) return 16 + utf8.encode(value).length;
    if (value is List) return 32 + value.fold<int>(0, (n, v) => n + facts(v));
    return 128;
  }

  return 512 +
      utf8.encode(item.id).length +
      utf8.encode(item.header.threadId).length +
      utf8.encode(item.header.turnId ?? '').length +
      facts(_demoDescriptorFacts(item.descriptor)) +
      item.fields.length * 96;
}
