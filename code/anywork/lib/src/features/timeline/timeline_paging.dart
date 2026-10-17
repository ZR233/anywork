part of 'timeline_view.dart';

extension on _TimelineViewState {
  Widget _buildChatMessageRow(Message message) {
    final row = message.metadata?['row'] as TimelineRow?;
    if (row == null) return const SizedBox.shrink();
    return _buildRow(row, body: widget.body);
  }

  /// 构建一行：行外壳、气泡、头像与状态元信息条都由应用自己的内容组件承担。
  ///
  /// 行由官方列表按稳定身份管理，投影只复用当前窗口内未变化的不可变数据。
  Widget _buildRow(TimelineRow row, {required ThreadHistoryWindow body}) {
    final block = _TimelineRowBlock(
      key: ValueKey(row.id),
      row: row,
      body: _itemBodyStates(row, body),
    );
    return KeyedSubtree(
      key: StudioDriverKeys.timelineBlock(row.id),
      child: SizedBox(
        key: _rowKeys.putIfAbsent(row.id, GlobalKey.new),
        child: _layoutItem(_anchorItemIdForRow(row), block),
      ),
    );
  }

  String _anchorItemId(String rowId, List<TimelineRow> rows) {
    final row = rows.where((row) => row.id == rowId).firstOrNull;
    return row == null ? rowId : _anchorItemIdForRow(row);
  }

  String _anchorItemIdForRow(TimelineRow row) {
    return row.entries.firstOrNull?.id ?? row.id;
  }

  /// 该行需要“回源完整正文”提示的底层条目；不需要时返回空列表。
  ///
  /// 单条行、raw 行与分组行都按 canonical item id 解析：分组行的 `row.id` 是合成身份
  /// （`activity-group:`），不能直接拿去查预览/回源状态，否则超大工具输出、
  /// 推理正文或 raw 载荷永远拿不到回源入口。
  List<_ItemBodyState> _itemBodyStates(
    TimelineRow row,
    ThreadHistoryWindow body,
  ) {
    final states = <_ItemBodyState>[];
    for (final candidate in _rowBodyCandidates(row)) {
      final state = _itemBodyState(
        candidate.id,
        candidate.label,
        body: body,
        autoComplete: candidate.isText,
      );
      if (state != null) states.add(state);
    }
    return states;
  }

  /// 单个底层条目的“回源完整正文”提示；不需要时返回 null。
  ///
  /// [autoComplete] 的正文由窗口按身份自动补齐，因此“预览态”与它自己的加载态都不产生提示：
  /// 读者既不需要点击加载，也不会看到分页/折叠入口。只有补齐失败与“尚未 durable”如实提示。
  _ItemBodyState? _itemBodyState(
    String itemId,
    String? label, {
    required ThreadHistoryWindow body,
    bool autoComplete = false,
  }) {
    final previewed = body.previewedItemIds.contains(itemId);
    final loading = body.loadingItemIds.contains(itemId);
    final error = body.itemBodyErrors[itemId];
    final pending = body.pendingItemBodyIds.contains(itemId);
    final unavailable = body.unavailableItemIds.contains(itemId);
    if (autoComplete && !pending && !unavailable && error == null) {
      return null;
    }
    if (!previewed && !loading && !pending && !unavailable && error == null) {
      return null;
    }
    return _ItemBodyState(
      itemId: itemId,
      label: label,
      isPreviewed: previewed,
      isLoading: loading,
      isPending: pending,
      isUnavailable: unavailable,
      error: error,
      onLoad: () => _dispatch(TimelineExpandBody(itemId)),
    );
  }

  String? _anchorRowId(String itemId, {List<TimelineRow>? rows}) {
    for (final row in rows ?? widget.rows) {
      if (row.id == itemId || row.entries.any((part) => part.id == itemId)) {
        return row.id;
      }
    }
    return null;
  }

  bool _needsAnchorRebase(TimelineAnchor anchor, List<TimelineRow> oldRows) {
    final oldId = _anchorRowId(anchor.itemId, rows: oldRows);
    final newId = _anchorRowId(anchor.itemId);
    final oldIndex = oldRows.indexWhere((row) => row.id == oldId);
    final newIndex = widget.rows.indexWhere((row) => row.id == newId);
    if (oldIndex != newIndex || oldId != newId) return true;
    for (var index = 0; index <= oldIndex; index++) {
      if (oldRows[index].id != widget.rows[index].id ||
          oldRows[index].renderVersion != widget.rows[index].renderVersion) {
        return true;
      }
    }
    return false;
  }

  /// 记录“最靠上的可见行”的锚点。
  ///
  /// 锚点偏移量直接使用行相对视口的真实绘制位置；保留缓存不参与可见性判断。
  TimelineAnchor? _captureAnchor({List<TimelineRow>? rows}) {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    String? id;
    double? offset;
    for (final entry in _rowKeys.entries) {
      final rect = _paintedViewportRect(entry.value.currentContext);
      if (rect == null ||
          rect.bottom <= 0 ||
          rect.top >= viewport.size.height) {
        continue;
      }
      if (offset == null || rect.top < offset) {
        id = entry.key;
        offset = rect.top;
      }
    }
    return id == null
        ? null
        : TimelineAnchor(
            _anchorItemId(id, rows ?? widget.rows),
            offset!,
            readingIntent: _readingIntent,
          );
  }

  void _schedulePrefetch() {
    final token = _correctionToken;
    if (_prefetchScheduled == token) return;
    _prefetchScheduled = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_prefetchScheduled != token) return;
      _prefetchScheduled = null;
      if (!mounted ||
          token != _correctionToken ||
          widget.isLoadingOlder ||
          widget.isLoadingNewer) {
        return;
      }
      final position = _controller.hasClients ? _controller.position : null;
      // Inspecting presentation is not permission to move the canonical window.
      if (_readingIntent == TimelineReadingIntent.inspectItem) return;
      // Use actual layout: raw item counts do not predict the height after grouping.
      final underfull = position == null
          ? widget.rows.isEmpty
          : position.maxScrollExtent - position.minScrollExtent < 1;
      if (_followingBottom && !_detachedByUser) {
        // Filling a latest viewport preserves Latest focus while prepending older items.
        if (underfull &&
            !widget.hasNewer &&
            _canLoadOlder &&
            widget.olderError == null &&
            !_olderLoadRequested) {
          _olderLoadRequested = true;
          ChatViewMetrics.prefetchLoadOlder += 1;
          _dispatch(const TimelineLoadOlder());
        }
        return;
      }
      // History reading advances only in its chosen direction, even when underfull.
      // Reversing automatically at an edge would oscillate a bounded window.
      final threshold = 1.5 * (position?.viewportDimension ?? 0);
      if (_scrollingOlder &&
          (_detachedByUser || underfull) &&
          (underfull ||
              (position?.extentBefore ?? double.infinity) < threshold) &&
          _canLoadOlder &&
          widget.olderError == null &&
          !_olderLoadRequested) {
        _olderLoadRequested = true;
        ChatViewMetrics.prefetchLoadOlder += 1;
        _dispatch(const TimelineLoadOlder());
      } else if (!_scrollingOlder &&
          (underfull ||
              (position?.extentAfter ?? double.infinity) < threshold) &&
          _canLoadNewer &&
          widget.newerError == null &&
          !_newerLoadRequested) {
        _newerLoadRequested = true;
        ChatViewMetrics.prefetchLoadNewer += 1;
        _dispatch(const TimelineLoadNewer());
      }
    });
  }

  Widget _edgeIndicator({required bool older}) {
    final error = older ? widget.olderError : widget.newerError;
    return Positioned(
      top: older ? 8 : null,
      bottom: older ? null : 8,
      left: 24,
      right: 24,
      child: Center(
        child: error == null
            ? SizedBox.square(
                key: ValueKey(
                  older ? 'timeline-history-loading' : 'timeline-newer-loading',
                ),
                dimension: 18,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Tooltip(
                message: error,
                child: TextButton.icon(
                  key: ValueKey(
                    older ? 'timeline-history-retry' : 'timeline-newer-retry',
                  ),
                  onPressed: older
                      ? () => _dispatch(const TimelineLoadOlder())
                      : () => _dispatch(const TimelineLoadNewer()),
                  icon: const Icon(Icons.refresh),
                  label: Text(context.l10n.timelineImageRetry),
                ),
              ),
      ),
    );
  }
}

typedef _RowBodyCandidate = ({String id, String? label, bool isText});
List<_RowBodyCandidate> _rowBodyCandidates(TimelineRow row) => [
  for (final part in row.entries)
    (id: part.id, label: part.tool?.name, isText: row is TimelineTextRow),
];
