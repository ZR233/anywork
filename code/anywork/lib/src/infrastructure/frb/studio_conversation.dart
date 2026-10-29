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

  @override
  Future<ConversationPage> page({String? before, int? limit}) async {
    if (_admissionsClosed) throw _conversationClosedFailure;
    if (limit != null && (limit < 1 || limit > 100)) {
      throw _conversationQueryFailure;
    }
    return FrbStudioTransport._bridgeCall(() async {
      final page = await _native.page(before: before, limit: limit);
      if (_admissionsClosed) throw _conversationClosedFailure;
      return ConversationPage(
        items: List.unmodifiable(page.items.map(_item)),
        before: page.before,
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
    _validateConversationUnsigned(query.revision);
    _validateConversationField(query.field);
    if (query.maxBytes case final size? when size < 4 || size > 256 * 1024) {
      throw _conversationQueryFailure;
    }
    return FrbStudioTransport._bridgeCall(() async {
      final chunk = await _native.readDetail(
        itemId: itemId,
        query: frb_chat_types.BridgeTimelineDetailQuery(
          field: _contentFieldToFrb(query.field),
          revision: BigInt.from(query.revision),
          continuation: query.continuation,
          maxBytes: query.maxBytes,
        ),
      );
      if (_admissionsClosed) throw _conversationClosedFailure;
      return ConversationDetailChunk(
        itemId: chunk.itemId,
        field: _contentField(chunk.field),
        revision: _exactTimelineInt(chunk.revision, 'detail revision'),
        text: chunk.text,
        totalBytes: _exactTimelineInt(chunk.totalBytes, 'detail total bytes'),
        continuation: chunk.continuation,
      );
    });
  }

  ConversationBaseline _baseline(frb_chat_types.BridgeTimelineBaseline value) {
    return ConversationBaseline(
      subscriptionId: value.subscriptionId,
      version: _exactTimelineInt(value.version, 'subscription version'),
      items: List.unmodifiable(value.items.map(_item)),
      before: value.before,
      hasOlder: value.hasOlder,
    );
  }

  ConversationUpdate _update(frb_chat_types.BridgeTimelineUpdate value) {
    return switch (value) {
      frb_chat_types.BridgeTimelineUpdate_Patch(
        :final subscriptionId,
        :final from,
        :final to,
        :final changes,
        :final priority,
      ) =>
        ConversationPatch(
          subscriptionId: subscriptionId,
          from: _exactTimelineInt(from, 'patch from'),
          to: _exactTimelineInt(to, 'patch to'),
          changes: List.unmodifiable(changes.map(_change)),
          priority: switch (priority) {
            frb_chat_types.BridgeTimelinePriority.immediate =>
              ConversationPriority.immediate,
            frb_chat_types.BridgeTimelinePriority.coalesced =>
              ConversationPriority.coalesced,
          },
        ),
      frb_chat_types.BridgeTimelineUpdate_Resync(
        :final subscriptionId,
        :final reason,
        :final baseline,
      ) =>
        ConversationResync(
          subscriptionId: subscriptionId,
          reason: switch (reason) {
            frb_chat_types.BridgeTimelineResyncReason.lagging =>
              ConversationResyncReason.lagging,
            frb_chat_types.BridgeTimelineResyncReason.unavailable =>
              ConversationResyncReason.unavailable,
          },
          baseline: _baseline(baseline),
        ),
    };
  }

  ConversationChange _change(frb_chat_types.BridgeTimelineChange value) {
    return switch (value) {
      frb_chat_types.BridgeTimelineChange_Add(:final item) => ConversationAdd(
        _item(item),
      ),
      frb_chat_types.BridgeTimelineChange_UpdateItem(
        :final itemId,
        :final expectedRevision,
        :final revision,
        :final saved,
        :final lifecycle,
        :final header,
        :final descriptor,
        :final fields,
      ) =>
        ConversationUpdateItem(
          itemId: itemId,
          expectedRevision: _exactTimelineInt(
            expectedRevision,
            'item expected revision',
          ),
          revision: _exactTimelineInt(revision, 'item revision'),
          saved: saved,
          lifecycle: _lifecycle(lifecycle),
          header: header == null ? null : _header(header),
          descriptor: descriptor == null
              ? null
              : _descriptorFromFrb(descriptor),
          fields: List.unmodifiable(fields.map(_fieldUpdate)),
        ),
      frb_chat_types.BridgeTimelineChange_Remove(:final itemId) =>
        ConversationRemove(itemId),
    };
  }

  ConversationFieldUpdate _fieldUpdate(
    frb_chat_types.BridgeTimelineFieldUpdate value,
  ) {
    return ConversationFieldUpdate(
      field: _contentField(value.field),
      change: _fieldChange(value.change),
      totalBytes: _exactTimelineInt(value.totalBytes, 'field total bytes'),
      previewBytes: _exactTimelineInt(
        value.previewBytes,
        'field preview bytes',
      ),
    );
  }

  ConversationItem _item(frb_chat_types.BridgeTimelineItem value) {
    final lifecycle = _lifecycle(value.lifecycle);
    return ConversationItem(
      source: switch (value.source) {
        frb_chat_types.BridgeTimelineItemSource_Content() =>
          const ConversationContentSource(),
        frb_chat_types.BridgeTimelineItemSource_ModelRecovery(
          :final attemptId,
          :final notice,
        ) =>
          ConversationRecoverySource(
            attemptId: attemptId,
            notice: switch (notice) {
              frb_chat_types.BridgeTimelineRecoveryNotice.retry =>
                ConversationRecoveryNotice.retry,
              frb_chat_types.BridgeTimelineRecoveryNotice.result =>
                ConversationRecoveryNotice.result,
            },
          ),
      },
      header: _header(value.header),
      revision: _exactTimelineInt(value.revision, 'item revision'),
      descriptor: _descriptorFromFrb(value.descriptor),
      saved: value.saved,
      lifecycle: lifecycle,
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

  ConversationItemHeader _header(
    frb_descriptor.BridgeTimelineItemHeader value,
  ) => ConversationItemHeader(
    id: value.id,
    threadId: value.threadId,
    turnId: value.turnId,
    ordinal: _exactTimelineInt(value.ordinal, 'item ordinal'),
    createdAt: _dateFromUnix(value.createdAt),
    updatedAt: _dateFromUnix(value.updatedAt),
  );

  ConversationLifecycle _lifecycle(
    frb_chat_types.BridgeTimelineLifecycle value,
  ) {
    return switch (value) {
      frb_chat_types.BridgeTimelineLifecycle.terminal =>
        ConversationLifecycle.terminal,
      frb_chat_types.BridgeTimelineLifecycle.streaming =>
        ConversationLifecycle.streaming,
    };
  }

  ThreadContentFieldView _contentField(
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
    );
  }

  frb_chat_types.BridgeContentField _contentFieldToFrb(
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
    };
  }

  ThreadFieldChangeView _fieldChange(
    frb_chat_types.BridgeTimelineFieldChange change,
  ) {
    return change.when(
      unchanged: () => const UnchangedThreadFieldChangeView(),
      append: (text) => AppendThreadFieldChangeView(text),
      replace: (text) => ReplaceThreadFieldChangeView(text),
      remove: () => const RemoveThreadFieldChangeView(),
    );
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
