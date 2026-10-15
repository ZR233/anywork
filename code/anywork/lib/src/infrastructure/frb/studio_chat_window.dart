part of 'studio_api.dart';

class FrbChatWindow implements StudioChatWindow {
  FrbChatWindow(this._view);

  final frb_chat.BridgeChatView _view;
  bool _closed = false;
  Future<void>? _closing;

  StudioChatItem _item(frb_chat_types.BridgeChatItem item) => StudioChatItem(
    _threadItemFromFrb(item.item).copyWith(
      saved: item.saved,
      executionTerminal:
          item.lifecycle == frb_chat_types.BridgeChatLifecycle.terminal,
      bodyOmittedUnits: _frbInt(item.omittedBytes),
    ),
    saved: item.saved,
    lifecycle: item.lifecycle == frb_chat_types.BridgeChatLifecycle.terminal
        ? StudioChatLifecycle.terminal
        : StudioChatLifecycle.streaming,
  );

  StudioChatSnapshot _snapshot(frb_chat_types.BridgeChatSnapshot snapshot) {
    final next = StudioChatSnapshot(
      focusedItemId: snapshot.focus.when(
        latest: () => null,
        around: (itemId) => itemId,
      ),
      version: _frbInt(snapshot.version),
      items: List.unmodifiable(snapshot.items.map(_item)),
      hasOlder: snapshot.hasOlder,
      hasNewer: snapshot.hasNewer,
      canExtendLatest: snapshot.canExtendLatest,
    );
    // 只读内容交付计数（仅 Driver 启用时统计；不是 FRB 物理 wire 字节）。
    StudioDriverState.recordChatWindowReset(next.items.length);
    for (final entry in next.items) {
      _recordItemBody(entry.item);
    }
    return next;
  }

  StudioViewChange _change(frb_chat_types.BridgeViewChange change) {
    return switch (change) {
      frb_chat_types.BridgeViewChange_Splice(
        :final index,
        :final remove,
        :final items,
      ) =>
        StudioViewSplice(
          index: _frbInt(index),
          remove: _frbInt(remove),
          items: List.unmodifiable(items.map(_item)),
        ),
      frb_chat_types.BridgeViewChange_UpdateItem(
        :final itemId,
        :final expectedRevision,
        :final revision,
        :final omittedBytes,
        :final saved,
        :final fields,
      ) =>
        StudioViewItemUpdate(
          itemId: itemId,
          expectedRevision: _frbInt(expectedRevision),
          revision: _frbInt(revision),
          omittedUnits: _frbInt(omittedBytes),
          saved: saved,
          fields: [
            for (final update in fields)
              StudioFieldUpdateView(
                field: _contentField(update.field),
                change: _fieldChange(update.change),
              ),
          ],
        ),
    };
  }

  @override
  Future<StudioChatSnapshot> initial() async {
    if (_closed) throw StateError('Chat window is closed');
    return _snapshot(await _view.initial());
  }

  @override
  Future<StudioChatFrame?> next() async {
    if (_closed) return null;
    final update = await _view.next();
    if (_closed || update == null) return null;
    return switch (update) {
      frb_chat_types.BridgeChatUpdate_Reset(:final snapshot) => StudioChatReset(
        _snapshot(snapshot),
      ),
      frb_chat_types.BridgeChatUpdate_Patch(
        :final from,
        :final to,
        :final changes,
        :final hasNewer,
      ) =>
        _patch(from, to, changes, hasNewer),
    };
  }

  StudioChatFrame _patch(
    BigInt from,
    BigInt to,
    List<frb_chat_types.BridgeViewChange> changes,
    bool hasNewer,
  ) {
    final projected = [for (final change in changes) _change(change)];
    // 只读差量交付计数（仅 Driver 启用时统计）。
    StudioDriverState.recordChatWindowPatch(projected.length);
    for (final change in projected) {
      switch (change) {
        case StudioViewSplice(:final items):
          for (final entry in items) {
            _recordItemBody(entry.item);
          }
        case StudioViewItemUpdate(:final fields):
          for (final update in fields) {
            _recordFieldChange(update.change);
          }
      }
    }
    return StudioChatPatch(
      from: _frbInt(from),
      to: _frbInt(to),
      changes: List.unmodifiable(projected),
      hasNewer: hasNewer,
    );
  }

  /// 记录一次字段变化的正文交付字节（只读计数，仅 Driver 启用时统计）。
  void _recordFieldChange(ThreadFieldChangeView change) {
    switch (change) {
      case AppendThreadFieldChangeView(:final text) ||
          ReplaceThreadFieldChangeView(:final text):
        StudioDriverState.recordContentDelta(text);
      case UnchangedThreadFieldChangeView() || RemoveThreadFieldChangeView():
        break;
    }
  }

  /// 记录整条正文交付的 UTF-8 字节（从已解码的 domain 字段取，不序列化 JSON）。
  void _recordItemBody(ThreadItemView item) {
    switch (item.state) {
      case ThreadTextItemStateView(:final text):
        StudioDriverState.recordContentBody(text);
      case ThreadThinkingItemStateView(:final summary, :final content):
        for (final chunk in summary) {
          StudioDriverState.recordContentBody(chunk);
        }
        for (final chunk in content) {
          StudioDriverState.recordContentBody(chunk);
        }
      case ThreadToolItemStateView(:final invocation, :final lifecycle):
        StudioDriverState.recordContentBody(invocation.arguments);
        switch (lifecycle) {
          case RunningThreadToolView(:final streamedOutput) ||
              CancellingThreadToolView(:final streamedOutput):
            StudioDriverState.recordContentBody(streamedOutput);
          case SucceededThreadToolView(:final output):
            StudioDriverState.recordContentBody(output.result);
          case FailedThreadToolView(:final output):
            StudioDriverState.recordContentBody(output?.result ?? '');
          default:
            break;
        }
      default:
        break;
    }
  }

  @override
  Future<StudioChatReceipt> load(TimelineDirection direction) async {
    if (_closed) throw StateError('Chat window is closed');
    return _receipt(
      await _view.load(
        direction: switch (direction) {
          TimelineDirection.older => frb_chat_types.BridgeChatDirection.older,
          TimelineDirection.newer => frb_chat_types.BridgeChatDirection.newer,
        },
      ),
    );
  }

  @override
  Future<StudioChatReceipt> extendLatest() async {
    if (_closed) throw StateError('Chat window is closed');
    return _receipt(await _view.extendLatest());
  }

  @override
  Future<StudioChatReceipt> focus(String? itemId) async {
    if (_closed) throw StateError('Chat window is closed');
    return _receipt(
      await _view.focus(
        focus: itemId == null
            ? const frb_chat_types.BridgeChatFocus.latest()
            : frb_chat_types.BridgeChatFocus.around(itemId: itemId),
      ),
    );
  }

  @override
  Future<StudioChatReceipt> expandItem(String itemId) async {
    if (_closed) throw StateError('Chat window is closed');
    return _receipt(await _view.expand(itemId: itemId));
  }

  StudioChatReceipt _receipt(frb_chat_types.BridgeChatReceipt receipt) {
    return StudioChatReceipt(
      operationId: _frbInt(receipt.operationId),
      version: _frbInt(receipt.version),
      retained: receipt.retained,
      disposition: switch (receipt.disposition) {
        frb_chat_types.BridgeChatDisposition.applied =>
          StudioChatDisposition.applied,
        frb_chat_types.BridgeChatDisposition.noChange =>
          StudioChatDisposition.noChange,
      },
    );
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
    );
  }

  ThreadFieldChangeView _fieldChange(frb_chat_types.BridgeFieldChange change) {
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
    _view.requestClose();
  }

  @override
  Future<void> close() => _closing ??= _joinClose();

  Future<void> _joinClose() async {
    try {
      requestClose();
      await _view.close();
      _view.dispose();
    } catch (_) {
      // Preserve the opaque handle for the unresolved-resource supervisor.
      _closing = null;
      rethrow;
    }
  }
}
