part of 'studio_api.dart';

/// Mechanical typed transport only. The SDK owns continuity, reduction and ACK.
final class FrbConversationFeed implements ConversationFeed {
  FrbConversationFeed(this._native)
    : threadId = _native.threadId(),
      subscriptionId = _native.subscriptionId();

  final frb_chat.BridgeConversationFeed _native;
  @override
  final String threadId;
  @override
  final String subscriptionId;
  _DartSubscription? _registration;
  bool get _admissionsClosed =>
      _closed || (_registration?.cancelRequested ?? false);
  bool _closed = false;
  bool _listened = false;
  bool _disposed = false;
  Future<void>? _closing;
  Future<void>? _nativeClosing;
  StreamSubscription<frb_chat_types.BridgeConversationFrame>? _subscription;
  late final StreamController<ConversationFrame> _controller = StreamController(
    onListen: _listen,
    onCancel: () {
      // Synchronous native cancellation, including idle/credit waits.
      requestClose();
      return close();
    },
  );

  @override
  Stream<ConversationFrame> get events {
    if (_admissionsClosed) throw _conversationClosedFailure;
    if (_listened) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'Conversation events already have a consumer',
        retryable: false,
        correlationId: 'client-conversation-consumer',
      );
    }
    _listened = true;
    return _controller.stream;
  }

  void _listen() {
    if (_admissionsClosed) {
      unawaited(_controller.close());
      return;
    }
    try {
      _subscription = _native.events().listen(
        (value) {
          if (_admissionsClosed) return;
          try {
            _controller.add(
              ConversationFrame(
                threadId: value.threadId,
                subscriptionId: value.subscriptionId,
                deliverySequence: _exactTimelineInt(
                  value.deliverySequence,
                  'delivery sequence',
                ),
                event: switch (value.event) {
                  frb_chat_types.BridgeConversationEvent_State(:final update) =>
                    ConversationStateEvent(
                      frame: _threadStreamFrameFromFrb(update),
                    ),
                  frb_chat_types.BridgeConversationEvent_ContentBaseline(
                    :final baseline,
                  ) =>
                    ConversationBaselineEvent(baseline: _baseline(baseline)),
                  frb_chat_types.BridgeConversationEvent_ContentUpdate(
                    :final update,
                  ) =>
                    ConversationUpdateEvent(update: _update(update)),
                  frb_chat_types.BridgeConversationEvent_ActivityContent(
                    :final frame,
                    :final completed,
                  ) =>
                    ConversationActivityContentEvent(
                      frame: _activityContentFromFrb(frame),
                      completed: completed == null ? null : _update(completed),
                    ),
                  frb_chat_types.BridgeConversationEvent_Failure(
                    :final error,
                  ) =>
                    ConversationFailureEvent(
                      failure: _studioFailure(error) as StudioFailure,
                    ),
                  frb_chat_types.BridgeConversationEvent_Closed() =>
                    const ConversationClosedEvent(),
                },
              ),
            );
          } catch (error, stack) {
            _conversionFailed(error, stack);
          }
        },
        onError: _conversionFailed,
        onDone: () {
          unawaited(_controller.close());
        },
      );
    } catch (error, stack) {
      _conversionFailed(error, stack);
    }
  }

  void _conversionFailed(Object error, StackTrace stack) {
    if (_closed) return;
    requestClose();
    _controller.addError(_studioFailure(error), stack);
    // Keep native owner and retry responsibility; never auto-ACK a failed conversion.
    unawaited(_controller.close());
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    if (_admissionsClosed) throw _conversationClosedFailure;
    _validateConversationUnsigned(deliverySequence);
    await FrbStudioTransport._bridgeCall(() async {
      _native.acknowledge(
        subscriptionId: subscriptionId,
        deliverySequence: BigInt.from(deliverySequence),
      );
    });
  }

  ConversationBaseline _baseline(frb_chat_types.BridgeTimelineBaseline value) {
    return ConversationBaseline(
      subscriptionId: value.subscriptionId,
      timelineEpoch: value.timelineEpoch,
      items: List.unmodifiable(value.items.map(_item)),
      before: value.before == null
          ? null
          : ConversationQueryCursor(value.before!),
      hasOlder: value.hasOlder,
      completedCursor: ConversationCompletionCursor(
        timelineEpoch: value.completedCursor.timelineEpoch,
        appendSeq: _exactTimelineInt(
          value.completedCursor.appendSeq,
          'completed sequence',
        ),
      ),
    );
  }

  ConversationUpdate _update(frb_chat_types.BridgeTimelineUpdate value) {
    return switch (value) {
      frb_chat_types.BridgeTimelineUpdate_Batch(
        :final subscriptionId,
        :final timelineEpoch,
        :final fromSeq,
        :final throughSeq,
        :final items,
      ) =>
        ConversationBatch(
          subscriptionId: subscriptionId,
          timelineEpoch: timelineEpoch,
          fromSeq: _exactTimelineInt(fromSeq, 'batch from'),
          throughSeq: _exactTimelineInt(throughSeq, 'batch through'),
          items: List.unmodifiable(items.map(_item)),
        ),
      frb_chat_types.BridgeTimelineUpdate_Reset(:final baseline) =>
        ConversationReset(_baseline(baseline)),
    };
  }

  static ConversationItem _item(frb_chat_types.BridgeTimelineItem value) {
    return ConversationItem(
      source: switch (value.source) {
        frb_chat_types.BridgeTimelineItemSource_Content() =>
          const ConversationContentSource(),
        frb_chat_types.BridgeTimelineItemSource_ModelRecovery(:final notice) =>
          ConversationRecoverySource(switch (notice) {
            frb_chat_types.BridgeTimelineRecoveryNotice.retry =>
              ConversationRecoveryNotice.retry,
            frb_chat_types.BridgeTimelineRecoveryNotice.result =>
              ConversationRecoveryNotice.result,
          }),
      },
      header: _header(value.header),
      descriptor: _descriptorFromFrb(value.descriptor),
      fields: List.unmodifiable(
        value.fields.map(
          (field) => ConversationFieldPreview(
            field: _contentField(field.field),
            text: field.text,
            totalBytes: _exactTimelineInt(
              field.totalBytes,
              'field total bytes',
            ),
          ),
        ),
      ),
    );
  }

  static ConversationItemHeader _header(
    frb_descriptor.BridgeTimelineItemHeader value,
  ) => ConversationItemHeader(
    id: value.id,
    threadId: value.threadId,
    turnId: value.turnId,
    appendSeq: _exactTimelineInt(value.appendSeq, 'append sequence'),
    sourceEffectSeq: _exactNullableTimelineInt(
      value.sourceEffectSeq,
      'source effect sequence',
    ),
    sealedAt: value.sealedAt == null
        ? null
        : _exactSignedTimelineInt(value.sealedAt!),
  );

  static ThreadContentFieldView _contentField(
    frb_chat_types.BridgeContentField field,
  ) {
    return field.when(
      text: () => const ThreadTextFieldView(),
      thinkingSummary: (chunkIndex) =>
          ThreadThinkingSummaryFieldView(chunkIndex),
      thinkingContent: (chunkIndex) =>
          ThreadThinkingContentFieldView(chunkIndex),
      toolArguments: () => const ThreadToolArgumentsFieldView(),
      toolResult: () => const ThreadToolResultFieldView(),
      toolOutputArtifacts: () => const ThreadToolOutputArtifactsFieldView(),
      toolUserInput: (questionIndex, part) => ThreadToolUserInputFieldView(
        questionIndex: questionIndex,
        part: part.when(
          header: () => const ThreadUserInputHeaderFieldPartView(),
          question: () => const ThreadUserInputQuestionFieldPartView(),
          answer: (answerIndex) =>
              ThreadUserInputAnswerFieldPartView(answerIndex),
          optionLabel: (optionIndex) =>
              ThreadUserInputOptionLabelFieldPartView(optionIndex),
          optionDescription: (optionIndex) =>
              ThreadUserInputOptionDescriptionFieldPartView(optionIndex),
        ),
      ),
      rawPayload: (payloadIndex) => ThreadRawPayloadFieldView(payloadIndex),
      planDocument: () => const ThreadPlanDocumentFieldView(),
      planFeedback: () => const ThreadPlanFeedbackFieldView(),
    );
  }

  static frb_chat_types.BridgeContentField _contentFieldToFrb(
    ThreadContentFieldView field,
  ) {
    return switch (field) {
      ThreadTextFieldView() => const frb_chat_types.BridgeContentField.text(),
      ThreadThinkingSummaryFieldView(:final chunkIndex) =>
        frb_chat_types.BridgeContentField.thinkingSummary(
          chunkIndex: chunkIndex,
        ),
      ThreadThinkingContentFieldView(:final chunkIndex) =>
        frb_chat_types.BridgeContentField.thinkingContent(
          chunkIndex: chunkIndex,
        ),
      ThreadToolArgumentsFieldView() =>
        const frb_chat_types.BridgeContentField.toolArguments(),
      ThreadToolResultFieldView() =>
        const frb_chat_types.BridgeContentField.toolResult(),
      ThreadToolOutputArtifactsFieldView() =>
        const frb_chat_types.BridgeContentField.toolOutputArtifacts(),
      ThreadToolUserInputFieldView(:final questionIndex, :final part) =>
        frb_chat_types.BridgeContentField.toolUserInput(
          questionIndex: questionIndex,
          part_: switch (part) {
            ThreadUserInputHeaderFieldPartView() =>
              const frb_chat_types.BridgeThreadUserInputFieldPart.header(),
            ThreadUserInputQuestionFieldPartView() =>
              const frb_chat_types.BridgeThreadUserInputFieldPart.question(),
            ThreadUserInputAnswerFieldPartView(:final answerIndex) =>
              frb_chat_types.BridgeThreadUserInputFieldPart.answer(
                answerIndex: answerIndex,
              ),
            ThreadUserInputOptionLabelFieldPartView(:final optionIndex) =>
              frb_chat_types.BridgeThreadUserInputFieldPart.optionLabel(
                optionIndex: optionIndex,
              ),
            ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex) =>
              frb_chat_types.BridgeThreadUserInputFieldPart.optionDescription(
                optionIndex: optionIndex,
              ),
          },
        ),
      ThreadRawPayloadFieldView(:final payloadIndex) =>
        frb_chat_types.BridgeContentField.rawPayload(
          payloadIndex: payloadIndex,
        ),
      ThreadPlanDocumentFieldView() =>
        const frb_chat_types.BridgeContentField.planDocument(),
      ThreadPlanFeedbackFieldView() =>
        const frb_chat_types.BridgeContentField.planFeedback(),
    };
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    try {
      _native.requestClose();
    } catch (_) {
      /* close retains typed failure responsibility */
    }
  }

  @override
  Future<void> close() {
    requestClose();
    final existing = _closing;
    if (existing != null) return existing;
    final work = _joinClose();
    _closing = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_closing, work)) _closing = null;
        },
      ),
    );
    return work;
  }

  Future<void> _joinClose() async {
    try {
      final registration = _registration;
      if (registration == null) {
        await _releaseNative();
      } else {
        await registration.beginCancel();
      }
    } catch (error, stack) {
      Error.throwWithStackTrace(_studioFailure(error), stack);
    }
  }

  Future<void> _releaseNative() {
    requestClose();
    final existing = _nativeClosing;
    if (existing != null) return existing;
    final work = _joinNative();
    _nativeClosing = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_nativeClosing, work)) _nativeClosing = null;
        },
      ),
    );
    return work;
  }

  Future<void> _joinNative() async {
    try {
      await _native.close();
      // Native close is joined BEFORE cancelling the held native stream. No cycle with
      // the public controller's onCancel, which awaits this same native join.
      await _subscription?.cancel();
      _subscription = null;
      if (!_disposed) {
        _native.dispose();
        _disposed = true;
      }
      if (_listened) unawaited(_controller.close());
    } catch (error, stack) {
      Error.throwWithStackTrace(_studioFailure(error), stack);
    }
  }
}

/// Native history reader retains the Session until its in-flight reads join.
final class FrbConversationHistoryReader implements ConversationHistoryReader {
  FrbConversationHistoryReader(this._native)
    : threadId = _native.threadId(),
      timelineEpoch = _native.timelineEpoch();

  final frb_history_reader.BridgeTimelineReader _native;
  @override
  final String threadId;
  @override
  final String timelineEpoch;
  _DartSubscription? _registration;
  bool _closed = false;
  bool _disposed = false;
  Future<void>? _closing;
  Future<void>? _nativeClosing;

  bool get _admissionsClosed =>
      _closed || (_registration?.cancelRequested ?? false);

  @override
  Future<ConversationPage> page({
    ConversationQueryCursor? before,
    int? limit,
  }) async {
    if (_admissionsClosed) throw _conversationClosedFailure;
    if (limit != null && (limit < 1 || limit > 100)) {
      throw _conversationQueryFailure;
    }
    return FrbStudioTransport._bridgeCall(() async {
      final page = await _native.page(before: before?.token, limit: limit);
      return ConversationPage(
        threadId: threadId,
        timelineEpoch: page.timelineEpoch,
        items: page.items.map(FrbConversationFeed._item).toList(),
        before: page.before == null
            ? null
            : ConversationQueryCursor(page.before!),
        hasOlder: page.hasOlder,
      );
    });
  }

  @override
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) async {
    if (_admissionsClosed) throw _conversationClosedFailure;
    _validateConversationField(query.field);
    if (query.maxBytes case final size? when size < 4 || size > 256 * 1024) {
      throw _conversationQueryFailure;
    }
    return FrbStudioTransport._bridgeCall(() async {
      final chunk = await _native.readDetail(
        itemId: itemId,
        query: frb_chat_types.BridgeTimelineDetailQuery(
          timelineEpoch: query.timelineEpoch,
          field: FrbConversationFeed._contentFieldToFrb(query.field),
          continuation: query.continuation?.token,
          maxBytes: query.maxBytes,
        ),
      );
      return ConversationDetailChunk(
        threadId: threadId,
        timelineEpoch: chunk.timelineEpoch,
        itemId: chunk.itemId,
        field: FrbConversationFeed._contentField(chunk.field),
        text: chunk.text,
        totalBytes: _exactTimelineInt(chunk.totalBytes, 'detail total bytes'),
        continuation: chunk.continuation == null
            ? null
            : ConversationQueryCursor(chunk.continuation!),
      );
    });
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    try {
      _native.requestClose();
    } catch (_) {
      // Registry retains the native handle until close succeeds.
    }
  }

  @override
  Future<void> close() {
    requestClose();
    final existing = _closing;
    if (existing != null) return existing;
    final work = _joinClose();
    _closing = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_closing, work)) _closing = null;
        },
      ),
    );
    return work;
  }

  Future<void> _joinClose() async {
    try {
      final registration = _registration;
      if (registration == null) {
        await _releaseNative();
      } else {
        await registration.beginCancel();
      }
    } catch (error, stack) {
      Error.throwWithStackTrace(_studioFailure(error), stack);
    }
  }

  Future<void> _releaseNative() {
    requestClose();
    final existing = _nativeClosing;
    if (existing != null) return existing;
    final work = _joinNative();
    _nativeClosing = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_nativeClosing, work)) _nativeClosing = null;
        },
      ),
    );
    return work;
  }

  Future<void> _joinNative() async {
    try {
      await _native.close();
      if (!_disposed) {
        _native.dispose();
        _disposed = true;
      }
    } catch (error, stack) {
      Error.throwWithStackTrace(_studioFailure(error), stack);
    }
  }
}

ActivityContentFrame _activityContentFromFrb(
  frb_activity.BridgeActivityContentFrame value,
) => value.when(
  begin:
      (
        generation,
        baseRevision,
        revision,
        activity,
        reasoning,
        response,
        tools,
        totalBytes,
      ) => ActivityBegin(
        generation: generation,
        baseRevision: _exactNullableTimelineInt(
          baseRevision,
          'activity base revision',
        ),
        revision: _exactTimelineInt(revision, 'activity revision'),
        activity: activity == null ? null : _threadActivityFromFrb(activity),
        reasoning: reasoning.map(_activityPartFromFrb).toList(),
        response: response.map(_activityPartFromFrb).toList(),
        tools: tools
            .map(
              (tool) => ActivityToolMetadata(
                callId: tool.callId,
                taskId: tool.taskId,
                name: tool.name,
                state: _activityToolStateFromFrb(tool.state),
                startedAt: tool.startedAt == null
                    ? null
                    : _exactSignedTimelineInt(tool.startedAt!),
                sourceOrder: _exactNullableTimelineInt(
                  tool.sourceOrder,
                  'activity source order',
                ),
                argumentsBytes: _exactNullableTimelineInt(
                  tool.argumentsBytes,
                  'activity arguments bytes',
                ),
                outputBytes: _exactNullableTimelineInt(
                  tool.outputBytes,
                  'activity output bytes',
                ),
                outputParts: [
                  for (final part in tool.outputParts)
                    ActivityToolOutputMetadata(
                      partId: part.partId,
                      totalBytes: _exactTimelineInt(
                        part.totalBytes,
                        'activity output part bytes',
                      ),
                    ),
                ],
                wait: tool.wait == null ? null : _waitFromFrb(tool.wait!),
              ),
            )
            .toList(),
        totalBytes: _exactTimelineInt(totalBytes, 'activity total bytes'),
      ),
  text: (generation, revision, operations) => ActivityText(
    generation: generation,
    revision: _exactTimelineInt(revision, 'activity revision'),
    operations: operations.map(_activityOperationFromFrb).toList(),
  ),
  commit: (generation, revision) => ActivityCommit(
    generation: generation,
    revision: _exactTimelineInt(revision, 'activity revision'),
  ),
);

ActivityPartMetadata _activityPartFromFrb(
  frb_activity.BridgeActivityPartMetadata value,
) => ActivityPartMetadata(
  itemId: value.itemId,
  complete: value.complete,
  totalBytes: _exactTimelineInt(value.totalBytes, 'activity part bytes'),
);

ActivityRegion _activityRegionFromFrb(
  frb_activity.BridgeActivityTextRegion value,
) => value.when(
  reasoning: (id) => ActivityRegion(ActivityRegionKind.reasoning, id),
  response: (id) => ActivityRegion(ActivityRegionKind.response, id),
  toolArguments: (id) => ActivityRegion(ActivityRegionKind.toolArguments, id),
  toolOutput: (callId, partId) =>
      ActivityRegion.toolOutput(callId: callId, partId: partId),
);

ActivityTextOperation _activityOperationFromFrb(
  frb_activity.BridgeActivityTextOperation value,
) => value.when(
  append: (region, text) =>
      ActivityAppend(_activityRegionFromFrb(region), text),
  replace: (region, text) =>
      ActivityReplace(_activityRegionFromFrb(region), text),
  remove: (region) => ActivityRemove(_activityRegionFromFrb(region)),
);

const _conversationClosedFailure = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The conversation feed is closed',
  retryable: false,
  correlationId: 'client-conversation-closed',
);
const _conversationQueryFailure = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The conversation query is invalid',
  retryable: false,
  correlationId: 'client-conversation-query',
);
void _validateConversationUnsigned(int value) {
  if (value < 0 || BigInt.from(value) > (BigInt.one << 64) - BigInt.one) {
    throw _conversationQueryFailure;
  }
}

void _validateConversationField(ThreadContentFieldView field) {
  void index(int value) {
    if (value < 0 || value > 0xffffffff) throw _conversationQueryFailure;
  }

  switch (field) {
    case ThreadTextFieldView() ||
        ThreadPlanDocumentFieldView() ||
        ThreadPlanFeedbackFieldView() ||
        ThreadToolArgumentsFieldView() ||
        ThreadToolResultFieldView() ||
        ThreadToolOutputArtifactsFieldView():
      break;
    case ThreadThinkingSummaryFieldView(:final chunkIndex) ||
        ThreadThinkingContentFieldView(:final chunkIndex):
      index(chunkIndex);
    case ThreadRawPayloadFieldView(:final payloadIndex):
      index(payloadIndex);
    case ThreadToolUserInputFieldView(:final questionIndex, :final part):
      index(questionIndex);
      switch (part) {
        case ThreadUserInputHeaderFieldPartView() ||
            ThreadUserInputQuestionFieldPartView():
          break;
        case ThreadUserInputAnswerFieldPartView(:final answerIndex):
          index(answerIndex);
        case ThreadUserInputOptionLabelFieldPartView(:final optionIndex) ||
            ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex):
          index(optionIndex);
      }
  }
}

int _exactTimelineInt(BigInt value, String what) {
  final result = value.toInt();
  if (value.isNegative || result < 0 || BigInt.from(result) != value) {
    throw StudioFailure(
      code: StudioFailureCode.overloaded,
      message: 'Conversation $what cannot be represented exactly',
      retryable: false,
      correlationId: 'client-conversation-range',
    );
  }
  return result;
}

int? _exactNullableTimelineInt(BigInt? value, String what) =>
    value == null ? null : _exactTimelineInt(value, what);

int _exactSignedTimelineInt(Object value) {
  final integer = switch (value) {
    final BigInt n => n,
    final int n => BigInt.from(n),
    _ => throw const StudioFailure(
      code: StudioFailureCode.internal,
      message: 'Conversation timestamp is not an integer',
      retryable: false,
      correlationId: 'client-conversation-integer-type',
    ),
  };
  final converted = integer.toInt();
  if (BigInt.from(converted) != integer) {
    throw const StudioFailure(
      code: StudioFailureCode.overloaded,
      message: 'Conversation timestamp cannot be represented exactly',
      retryable: false,
      correlationId: 'client-conversation-range',
    );
  }
  return converted;
}

int? _exactNullableSignedTimelineInt(Object? value) =>
    value == null ? null : _exactSignedTimelineInt(value);
