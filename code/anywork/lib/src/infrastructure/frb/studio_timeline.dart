part of 'studio_api.dart';

/// 一条时间线内容连接的 FRB 薄适配。
///
/// 它只做机械转换：BigInt/typed DTO → domain 投影、关闭顺序与句柄所有权。它不保存基线、
/// 不应用差量、不猜测错误分类（design/26 §26.6、§26.8）。所有 wire u64 在转成 Dart 非负
/// int 前做精确往返校验：本平台无法精确表示的有效值明确报 `overloaded`，绝不静默截断。
class FrbTimelineConnection implements StudioTimelineConnection {
  FrbTimelineConnection(this._timeline);

  final frb_chat.BridgeTimeline _timeline;
  bool _closed = false;
  Future<void>? _closing;

  @override
  Future<StudioTimelineBaseline> initial() async {
    if (_closed) throw _timelineClosedFailure;
    return FrbStudioTransport._bridgeCall(() async {
      final baseline = await _timeline.initial();
      if (_closed) throw _timelineClosedFailure;
      return _baseline(baseline);
    });
  }

  @override
  Future<StudioTimelineUpdate?> next() async {
    if (_closed) throw _timelineClosedFailure;
    return FrbStudioTransport._bridgeCall(() async {
      final update = await _timeline.next();
      // 在途关闭同样是 typed Cancelled：null 只表示**未关闭连接**的真实 EOF。
      if (_closed) throw _timelineClosedFailure;
      if (update == null) return null;
      return _update(update);
    });
  }

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) async {
    if (_closed) throw _timelineClosedFailure;
    return FrbStudioTransport._bridgeCall(() async {
      final page = await _timeline.page(before: before, limit: limit);
      if (_closed) throw _timelineClosedFailure;
      return StudioTimelinePage(
        items: List.unmodifiable(page.items.map(_item)),
        before: page.before,
        hasOlder: page.hasOlder,
      );
    });
  }

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) async {
    if (_closed) throw _timelineClosedFailure;
    return FrbStudioTransport._bridgeCall(() async {
      final chunk = await _timeline.readDetail(
        itemId: itemId,
        query: frb_chat_types.BridgeTimelineDetailQuery(
          field: _contentFieldToFrb(query.field),
          revision: BigInt.from(query.revision),
          continuation: query.continuation,
          maxBytes: query.maxBytes,
        ),
      );
      if (_closed) throw _timelineClosedFailure;
      return StudioTimelineDetailChunk(
        itemId: chunk.itemId,
        field: _contentField(chunk.field),
        revision: _exactTimelineInt(chunk.revision, 'detail revision'),
        text: chunk.text,
        totalBytes: _exactTimelineInt(chunk.totalBytes, 'detail total bytes'),
        continuation: chunk.continuation,
      );
    });
  }

  StudioTimelineBaseline _baseline(
    frb_chat_types.BridgeTimelineBaseline value,
  ) {
    return StudioTimelineBaseline(
      subscriptionId: value.subscriptionId,
      version: _exactTimelineInt(value.version, 'subscription version'),
      items: List.unmodifiable(value.items.map(_item)),
      before: value.before,
      hasOlder: value.hasOlder,
    );
  }

  StudioTimelineUpdate _update(frb_chat_types.BridgeTimelineUpdate value) {
    return switch (value) {
      frb_chat_types.BridgeTimelineUpdate_Patch(
        :final subscriptionId,
        :final from,
        :final to,
        :final changes,
        :final priority,
      ) =>
        StudioTimelinePatch(
          subscriptionId: subscriptionId,
          from: _exactTimelineInt(from, 'patch from'),
          to: _exactTimelineInt(to, 'patch to'),
          changes: List.unmodifiable(changes.map(_change)),
          priority: priority == frb_chat_types.BridgeTimelinePriority.immediate
              ? StudioTimelinePriority.immediate
              : StudioTimelinePriority.coalesced,
        ),
      frb_chat_types.BridgeTimelineUpdate_Resync(
        :final subscriptionId,
        :final reason,
        :final baseline,
      ) =>
        StudioTimelineResync(
          subscriptionId: subscriptionId,
          reason: reason == frb_chat_types.BridgeTimelineResyncReason.lagging
              ? StudioTimelineResyncReason.lagging
              : StudioTimelineResyncReason.unavailable,
          baseline: _baseline(baseline),
        ),
    };
  }

  StudioTimelineChange _change(frb_chat_types.BridgeTimelineChange value) {
    return switch (value) {
      frb_chat_types.BridgeTimelineChange_Add(:final item) => StudioTimelineAdd(
        _item(item),
      ),
      frb_chat_types.BridgeTimelineChange_UpdateItem(
        :final itemId,
        :final expectedRevision,
        :final revision,
        :final omittedBytes,
        :final saved,
        :final lifecycle,
        :final itemShell,
        :final fields,
      ) =>
        StudioTimelineUpdateItem(
          itemId: itemId,
          expectedRevision: _exactTimelineInt(
            expectedRevision,
            'item expected revision',
          ),
          revision: _exactTimelineInt(revision, 'item revision'),
          omittedBytes: _exactTimelineInt(omittedBytes, 'item omitted bytes'),
          saved: saved,
          lifecycle: _lifecycle(lifecycle),
          itemShell: itemShell == null
              ? null
              : _threadItemFromFrb(itemShell, exactNumbers: true),
          fields: List.unmodifiable(fields.map(_fieldUpdate)),
        ),
      frb_chat_types.BridgeTimelineChange_Remove(:final itemId) =>
        StudioTimelineRemove(itemId),
    };
  }

  StudioFieldUpdateView _fieldUpdate(
    frb_chat_types.BridgeTimelineFieldUpdate value,
  ) {
    return StudioFieldUpdateView(
      field: _contentField(value.field),
      change: _fieldChange(value.change),
      totalBytes: _exactTimelineInt(value.totalBytes, 'field total bytes'),
      previewBytes: _exactTimelineInt(
        value.previewBytes,
        'field preview bytes',
      ),
    );
  }

  StudioTimelineItem _item(frb_chat_types.BridgeTimelineItem value) {
    final lifecycle = _lifecycle(value.lifecycle);
    return StudioTimelineItem(
      source: switch (value.source) {
        frb_chat_types.BridgeTimelineItemSource_Content() =>
          const StudioTimelineContentSource(),
        frb_chat_types.BridgeTimelineItemSource_ModelRecovery(
          :final attemptId,
          :final notice,
        ) =>
          StudioTimelineRecoverySource(
            attemptId: attemptId,
            notice: switch (notice) {
              frb_chat_types.BridgeTimelineRecoveryNotice.retry =>
                StudioTimelineRecoveryNotice.retry,
              frb_chat_types.BridgeTimelineRecoveryNotice.result =>
                StudioTimelineRecoveryNotice.result,
            },
          ),
      },
      // 预览条目同样携带执行终态/保存水位/省略量：终态身份必须拒绝迟到流式正文，
      // 保存水位仍与终态独立（design/26 §26.7）。
      item: _threadItemFromFrb(value.item, exactNumbers: true).copyWith(
        saved: value.saved,
        executionTerminal: lifecycle == StudioTimelineLifecycle.terminal,
        bodyOmittedUnits: _exactTimelineInt(
          value.omittedBytes,
          'item omitted bytes',
        ),
      ),
      saved: value.saved,
      lifecycle: lifecycle,
      omittedBytes: _exactTimelineInt(value.omittedBytes, 'item omitted bytes'),
      details: List.unmodifiable(value.details.map(_detailRef)),
    );
  }

  StudioTimelineDetailRef _detailRef(
    frb_chat_types.BridgeTimelineDetailRef value,
  ) {
    return StudioTimelineDetailRef(
      field: _contentField(value.field),
      revision: _exactTimelineInt(value.revision, 'detail revision'),
      totalBytes: _exactTimelineInt(value.totalBytes, 'detail total bytes'),
      previewBytes: _exactTimelineInt(
        value.previewBytes,
        'detail preview bytes',
      ),
    );
  }

  StudioTimelineLifecycle _lifecycle(
    frb_chat_types.BridgeTimelineLifecycle value,
  ) {
    return value == frb_chat_types.BridgeTimelineLifecycle.terminal
        ? StudioTimelineLifecycle.terminal
        : StudioTimelineLifecycle.streaming;
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

  /// 只请求取消；真正的 join 与释放由 [close] 负责。
  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    try {
      _timeline.requestClose();
    } catch (_) {
      // 真实 join 仍然执行；request 失败不能被当成已关闭。
    }
  }

  @override
  Future<void> close() => _closing ??= _joinClose();

  Future<void> _joinClose() async {
    try {
      requestClose();
      await _timeline.close();
      _timeline.dispose();
    } catch (error, stackTrace) {
      // 保留 opaque 句柄供 unresolved-resource 监督者继续等待。
      _closing = null;
      // 关闭失败同样只以 typed 失败穿越边界；同步 cancel 与 join 顺序不变。
      Error.throwWithStackTrace(_studioFailure(error), stackTrace);
    }
  }
}

const StudioFailure _timelineClosedFailure = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The timeline connection is closed',
  retryable: false,
  correlationId: 'client-timeline-closed',
);

/// 把 wire u64 精确转成 Dart 非负 int。
///
/// `BigInt.toInt()` 在 Web 上钳制、在 native 上按平台宽度截断，两者都会静默破坏身份/版本。
/// 这里用往返比较拒绝不可精确表示的值；错误消息保持脱敏（不回显原始数值）。
int _exactTimelineInt(BigInt value, String what) {
  final converted = value.toInt();
  if (BigInt.from(converted) != value) {
    throw StudioFailure(
      code: StudioFailureCode.overloaded,
      message: 'Timeline $what cannot be represented exactly on this platform',
      retryable: false,
      correlationId: 'client-timeline-range',
    );
  }
  return converted;
}
