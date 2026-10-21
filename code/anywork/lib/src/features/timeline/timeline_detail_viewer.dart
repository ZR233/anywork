part of 'timeline_view.dart';

/// 被省略正文的显式入口。
///
/// 默认预览不因为后台补齐而自动扩大历史行：读者必须显式打开查看器，之后才在活动查询
/// scope 内逐块读取（design/26 §26.2「详情读取」、§26.5）。
///
/// 每个被截断字段恰好一行 [TimelineActivityRow]：图标表达字段类别，单行文案是该字段的领域
/// 名，紧邻的箭头表示可打开完整内容。入口不再渲染“截断预览”说明句、按钮组或多行副标题，
/// 因此活动组折叠态只有“图标列 + 单行文案 + 箭头”这一种行形态（design/19 §19.9）。
///
/// 这里同时是正文选择边界（§26.8）：详情入口行文案是界面提示，不是 canonical
/// 正文，用官方 [SelectionContainer.disabled] 把整棵子树移出外层选择域，因此跨块选择与
/// 复制不会带上它们；入口行的点击、键盘焦点与辅助语义不受选择边界影响。
class _TimelineDetailNotice extends StatelessWidget {
  const _TimelineDetailNotice({
    required this.itemId,
    required this.lease,
    required this.threadId,
    required this.details,
  });

  final String itemId;
  final TimelineDisplayLease lease;
  final String threadId;
  final List<StudioTimelineDetailRef> details;

  @override
  Widget build(BuildContext context) {
    void open(ThreadContentFieldView field) => unawaited(
      _openTimelineDetailViewer(
        context,
        lease: lease,
        itemId: itemId,
        field: field,
      ),
    );
    return SelectionContainer.disabled(
      child: Padding(
        key: StudioDriverKeys.timelineItemBodyNotice(itemId),
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final detail in details)
              Semantics(
                container: true,
                button: true,
                label: _timelineFieldLabel(context, detail.field),
                hint: context.l10n.timelineItemBodyLoad,
                onTap: () => open(detail.field),
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: StudioDriverKeys.timelineDetailOpen(
                      itemId,
                      StudioDriverKeyValues.timelineDetailField(detail.field),
                    ),
                    onTap: () => open(detail.field),
                    // 键盘可达：InkWell 自带 Focus 与 ActivateIntent（Enter/Space）→ onTap，
                    // 因此 Tab 聚焦后回车/空格即可读取完整内容。
                    canRequestFocus: true,
                    excludeFromSemantics: true,
                    child: TimelineActivityRow(
                      icon: _timelineFieldIcon(detail.field),
                      label: _timelineFieldLabel(context, detail.field),
                      expandable: true,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// typed 字段的稳定诊断身份：判别分支 + 逻辑索引，不依赖对象实例。
/// 只有省略声明、没有任何字段引用的条目：如实说明原文不可得，不提供伪造入口。
///
/// 说明行与 [_TimelineDetailNotice] 的入口行同形：一行 [TimelineActivityRow]，不可点击、
/// 不显示箭头，不用整句换行文本（design/19 §19.9）。它同样不属于 canonical 正文，
/// 因此处在同一个选择边界之外（§26.8）。
class _TimelineTruncationNotice extends StatelessWidget {
  const _TimelineTruncationNotice({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Padding(
        key: StudioDriverKeys.timelineItemBodyNotice(itemId),
        padding: const EdgeInsets.only(top: 6),
        child: TimelineActivityRow(
          icon: Icons.info_outline,
          label: context.l10n.timelineItemBodyUnavailable,
          expandable: false,
        ),
      ),
    );
  }
}

String _timelineFieldLabel(
  BuildContext context,
  ThreadContentFieldView field,
) => switch (field) {
  ThreadToolArgumentsFieldView() => context.l10n.timelineToolArguments,
  ThreadToolResultFieldView() => context.l10n.timelineToolOutput,
  ThreadToolOutputArtifactsFieldView() => context.l10n.timelineToolOutput,
  ThreadRawPayloadFieldView() => context.l10n.timelineRawRecord,
  ThreadThinkingSummaryFieldView() => context.l10n.timelineReasoningSummary,
  ThreadThinkingContentFieldView() => context.l10n.timelineReasoningContent,
  ThreadToolUserInputFieldView() => context.l10n.timelineUserInputYourAnswer,
  ThreadTextFieldView() => context.l10n.timelineItemBodyLoad,
};

/// 详情入口行的类目图标：只表达字段类别，与同组其它活动行同一图标列。
IconData _timelineFieldIcon(ThreadContentFieldView field) => switch (field) {
  ThreadToolArgumentsFieldView() => Icons.tune,
  ThreadToolResultFieldView() ||
  ThreadToolOutputArtifactsFieldView() => Icons.terminal,
  ThreadRawPayloadFieldView() => Icons.history,
  ThreadThinkingSummaryFieldView() => Icons.summarize_outlined,
  ThreadThinkingContentFieldView() => Icons.subject,
  ThreadToolUserInputFieldView() => Icons.chat_bubble_outline,
  ThreadTextFieldView() => Icons.unfold_more,
};

Future<void> _openTimelineDetailViewer(
  BuildContext context, {
  required TimelineDisplayLease lease,
  required String itemId,
  required ThreadContentFieldView field,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _TimelineDetailDialog(
      lease: lease,
      itemId: itemId,
      field: field,
      title: _timelineFieldLabel(context, field),
    ),
  );
}

/// 全文查看器：活动 scope 内逐块读取、可等待、可选择与复制。
///
/// - 每块/每次重试都从**同一仍有效 lease** 取活动 scope；不缓存 scope、不关闭共享 scope。
/// - 关闭（按钮/Escape/遮罩外的 route 退出）先停止后续块，再 await **自己已受理的那次读取**
///   真正退出，之后才 pop；SDK 的查询在底层工作退出后才完成，因此这是真实 join。
/// - lease 退役/条目缺失/revision 变化/后端 typed `staleRevision` 或 `notFound` 都是终态：
///   清空正文、累计字节与 continuation，禁用复制，要求重新打开；不会把两版正文拼在一起。
///   瞬时的 scope 失效（如换新 attempt）仍可在同一有效 lease 内重试。
class _TimelineDetailDialog extends StatefulWidget {
  const _TimelineDetailDialog({
    required this.lease,
    required this.itemId,
    required this.field,
    required this.title,
  });

  final TimelineDisplayLease lease;
  final String itemId;
  final ThreadContentFieldView field;
  final String title;

  @override
  State<_TimelineDetailDialog> createState() => _TimelineDetailDialogState();
}

class _TimelineDetailDialogState extends State<_TimelineDetailDialog> {
  final StringBuffer _body = StringBuffer();
  String? _continuation;
  int _bytes = 0;
  int? _revision;
  bool _loading = false;
  bool _done = false;
  bool _closed = false;
  bool _terminal = false;
  Object? _error;

  /// 当前已受理、尚未退出的读取；关闭必须 await 它。
  Future<void>? _inFlight;
  Future<void>? _closing;

  @override
  void initState() {
    super.initState();
    // lease 本身退役：停止读取并给终态，同时释放本查看器的正文缓存。
    unawaited(
      widget.lease.released.then((_) {
        if (!mounted || _closed || _terminal) return;
        _enterTerminal();
      }),
    );
    unawaited(_pump());
  }

  @override
  void dispose() {
    _closed = true;
    _body.clear();
    super.dispose();
  }

  /// 终态：清正文、累计字节与 continuation，禁复制；不再发新块。
  void _enterTerminal() {
    if (_terminal) return;
    setState(() {
      _terminal = true;
      _loading = false;
      _error = null;
      _body.clear();
      _bytes = 0;
      _continuation = null;
      _revision = null;
      _done = false;
    });
  }

  Future<void> _pump() async {
    if (_closed || _loading || _done || _terminal) return;
    final lease = widget.lease;
    final ref = lease.detailRef(widget.itemId, widget.field);
    if (ref == null || lease.isRetired) {
      // 条目已不在本代次、或 lease 退役：终态，不能无限 retry，也不迁往别的 Thread/代次。
      _enterTerminal();
      return;
    }
    if (_revision != null && ref.revision != _revision) {
      // 条目在读取期间推进了 revision：不能把两版正文拼在一起。
      _enterTerminal();
      return;
    }
    final scope = lease.queries;
    if (scope == null) {
      setState(() {
        _error = const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'The content connection is not ready',
          retryable: true,
          correlationId: 'timeline-detail-no-scope',
        );
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final read = scope.readDetail(
      itemId: widget.itemId,
      query: StudioTimelineDetailQuery(
        field: widget.field,
        revision: ref.revision,
        continuation: _continuation,
      ),
    );
    _inFlight = read;
    try {
      final chunk = await read;
      if (_closed || !mounted || _terminal) return;
      // 返回后、发布前再核当前有效性与 revision：刚退役或推进到别的版本都不落地。
      final current = lease.detailRef(widget.itemId, widget.field);
      if (lease.isRetired ||
          current == null ||
          (current.revision != (_revision ?? ref.revision))) {
        _enterTerminal();
        return;
      }
      setState(() {
        _revision ??= ref.revision;
        _body.write(chunk.text);
        _bytes += utf8.encode(chunk.text).length;
        _continuation = chunk.continuation;
        _done = chunk.isLast;
        _loading = false;
      });
      if (!_done) await _pump();
    } on Object catch (error) {
      if (_closed || !mounted || _terminal) return;
      if (_isDefinitiveFailure(error)) {
        // 后端明确判定该引用已确定失效（版本过期或条目已不存在）：对同一个冻结引用
        // 重试只会永远同名失败，因此进入终态；瞬时的 scope 失效仍可换新 scope 重试。
        _enterTerminal();
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    } finally {
      if (identical(_inFlight, read)) _inFlight = null;
    }
  }

  /// 能确定“这次读取的对象已确定失效、同一引用重试无意义”的 typed 失败。
  static bool _isDefinitiveFailure(Object error) =>
      error is StudioFailure &&
      (error.code == StudioFailureCode.staleRevision ||
          error.code == StudioFailureCode.notFound);

  /// 关闭：停新块 → await 自己已受理的读取 → 再离开 route。
  Future<void> _close() {
    final existing = _closing;
    if (existing != null) return existing;
    _closed = true;
    return _closing = _closeAfterInFlight();
  }

  Future<void> _closeAfterInFlight() async {
    final inFlight = _inFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } on Object {
        // 已受理读取的错误不改变“它确实退出了”这一关闭事实。
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _copy() async {
    if (!_canCopy) return;
    // 复制前再次核验：退役/终态/更高 revision 都不复制旧全文。
    final lease = widget.lease;
    final ref = lease.detailRef(widget.itemId, widget.field);
    if (lease.isRetired ||
        _terminal ||
        _closed ||
        ref == null ||
        ref.revision != _revision) {
      _enterTerminal();
      return;
    }
    await Clipboard.setData(ClipboardData(text: _body.toString()));
  }

  /// 只有完整、有效、未退役的正文才允许“复制全文”。
  bool get _canCopy =>
      _done &&
      _error == null &&
      !_terminal &&
      !_closed &&
      !widget.lease.isRetired &&
      _body.isNotEmpty;

  void _retry() {
    if (_terminal) return;
    setState(() {
      _error = null;
      _loading = false;
    });
    unawaited(_pump());
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    // 窄窗/矮窗/大字号下用视口剩余空间与官方约束的交集，不随比例缩放文字。
    final media = MediaQuery.sizeOf(context);
    final width = math.min(620.0, math.max(240.0, media.width - 96));
    final height = math.min(420.0, math.max(160.0, media.height - 200));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_close());
      },
      child: AlertDialog(
        key: StudioDriverKeys.timelineDetailDialog,
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              key: StudioDriverKeys.timelineDetailCopy,
              onPressed: _canCopy ? () => unawaited(_copy()) : null,
              icon: const Icon(Icons.copy_all_outlined, size: 18),
            ),
            IconButton(
              key: StudioDriverKeys.timelineDetailClose,
              onPressed: () => unawaited(_close()),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: width,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_terminal)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: context.colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.timelineDetailUnavailable,
                          key: StudioDriverKeys.timelineDetailTerminal,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.timelineItemBodyLoading,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              if (error != null && !_terminal)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: context.colors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error is StudioFailure
                              ? error.message
                              : error.toString(),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: context.colors.error),
                        ),
                      ),
                      TextButton(
                        key: StudioDriverKeys.timelineDetailRetry,
                        onPressed: _retry,
                        child: Text(context.l10n.timelineItemBodyRetry),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _body.toString(),
                    key: StudioDriverKeys.timelineDetailText,
                    style: context.text.bodySmall?.copyWith(
                      height: 1.5,
                      fontFamily: switch (widget.field) {
                        ThreadToolArgumentsFieldView() ||
                        ThreadToolResultFieldView() ||
                        ThreadToolOutputArtifactsFieldView() ||
                        ThreadRawPayloadFieldView() => studioCodeFontFamily,
                        _ => null,
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${_formatBytes(_bytes)} / ${_formatBytes(widget.lease.detailRef(widget.itemId, widget.field)?.totalBytes ?? 0)}',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
