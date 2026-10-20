part of 'timeline_view.dart';

/// Stock Chat builds one custom item; member listeners keep token updates inside that item.
class _TimelinePresentationBlock extends StatelessWidget {
  const _TimelinePresentationBlock({
    required this.message,
    required this.lease,
    required this.threadId,
    super.key,
  });
  final Message message;
  final TimelineDisplayLease lease;
  final String threadId;

  @override
  Widget build(BuildContext context) {
    final item = timelinePresentationOf(message);
    if (item == null || item.length == 0) return const SizedBox.shrink();
    if (item is TimelineSingleItem) {
      return ValueListenableBuilder<TimelineMessagePayload>(
        valueListenable: item.member(item.memberIds.single),
        builder: (context, payload, _) => _TimelineMessageBlock(
          payload: payload,
          lease: lease,
          threadId: threadId,
        ),
      );
    }
    return _TimelineGroupBlock(
      key: ValueKey(item.id),
      item: item,
      lease: lease,
      threadId: threadId,
    );
  }
}

class _TimelineGroupBlock extends StatefulWidget {
  const _TimelineGroupBlock({
    required this.item,
    required this.lease,
    required this.threadId,
    super.key,
  });
  final TimelinePresentationItem item;
  final TimelineDisplayLease lease;
  final String threadId;
  @override
  State<_TimelineGroupBlock> createState() => _TimelineGroupBlockState();
}

class _TimelineGroupBlockState extends State<_TimelineGroupBlock> {
  final ExpansibleController _expansion = ExpansibleController();

  @override
  void initState() {
    super.initState();
    widget.item.addListener(_onItemChanged);
  }

  void _onItemChanged() {
    // Only a structural merge can inherit another item's explicit expansion intent.
    if (widget.item.expanded && !_expansion.isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.item.expanded && !_expansion.isExpanded) {
          _expansion.expand();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _TimelineGroupBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.item, widget.item)) {
      oldWidget.item.removeListener(_onItemChanged);
      widget.item.addListener(_onItemChanged);
      _onItemChanged();
    }
  }

  @override
  void dispose() {
    widget.item.removeListener(_onItemChanged);
    _expansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Padding(
      key: StudioDriverKeys.timelineRow(item.id),
      padding: const EdgeInsets.only(bottom: 6),
      child: ListenableBuilder(
        listenable: item,
        builder: (context, body) => TimelineActivityTileTheme(
          child: ExpansionTile(
            controller: _expansion,
            initiallyExpanded: item.expanded,
            onExpansionChanged: item.setExpanded,
            maintainState: false,
            showTrailingIcon: false,
            minTileHeight: 28,
            dense: true,
            tilePadding: EdgeInsets.zero,
            // 活动组成员共享紧凑节奏；图片图集与重连分组保留原有内边距。
            childrenPadding: item.kind == TimelinePresentationKind.activity
                ? const EdgeInsets.only(bottom: 2)
                : const EdgeInsets.only(left: 7, bottom: 6),
            shape: const Border(),
            collapsedShape: const Border(),
            title: TimelineActivityRow(
              key: StudioDriverKeys.timelineActivitySummary(item.id),
              icon: switch (item.kind) {
                TimelinePresentationKind.images => Icons.image_outlined,
                TimelinePresentationKind.recovery => Icons.sync,
                _ =>
                  item.thinkingCount > 0
                      ? Icons.psychology_alt_outlined
                      : Icons.build_outlined,
              },
              label: _label(context, item),
              isIssue: item.issueCount > 0,
              active: item is TimelineRecoveryGroup
                  ? (item.latest.source as StudioTimelineRecoverySource)
                            .notice ==
                        StudioTimelineRecoveryNotice.retry
                  : item.activeCount > 0,
              expanded: item.expanded,
              expandable: _groupExpandable(item),
            ),
            children: [body!],
          ),
        ),
        child: item is TimelineImageReadGroup
            ? _TimelineImageGroupContents(
                item: item,
                lease: widget.lease,
                threadId: widget.threadId,
              )
            : _TimelineGroupContents(
                item: item,
                lease: widget.lease,
                threadId: widget.threadId,
              ),
      ),
    );
  }

  /// 单成员纯思考组只展示该思考已有正文：正文为空时不承诺一个空的展开区。
  bool _groupExpandable(TimelinePresentationItem item) {
    if (item.kind != TimelinePresentationKind.activity ||
        item.thinkingCount != 1 ||
        item.toolCount != 0 ||
        item.length != 1) {
      return true;
    }
    final payload = item.first;
    final state = payload.item.state;
    if (state is! ThreadThinkingItemStateView) return true;
    return state.summary.any((chunk) => chunk.trim().isNotEmpty) ||
        state.content.any((chunk) => chunk.trim().isNotEmpty) ||
        payload.details.any((detail) => detail.truncated) ||
        payload.hasOmittedBody;
  }

  String _label(BuildContext context, TimelinePresentationItem item) {
    if (item is TimelineRecoveryGroup) return item.latest.item.text;
    if (item is TimelineImageReadGroup) {
      final count = item.imageCount > 0
          ? context.l10n.timelineImagesViewed(item.imageCount)
          : '';
      final status = item.issueCount > 0
          ? context.l10n.timelineViewImageFailed
          : item.activeCount > 0
          ? context.l10n.timelineViewImageReading
          : '';
      return [count, status].where((part) => part.isNotEmpty).join(' · ');
    }
    if (item.thinkingCount > 0 && item.toolCount == 0) {
      // 纯思考组只汇总各思考成员的有效耗时，不把工具、等待或条目间隔计入。
      return _reasoningGroupLabel(context, item);
    }
    final title = item.thinkingCount > 0
        ? context.l10n.timelineActivityTitle
        : context.l10n.timelineToolGroupTitle;
    final detail = switch ((item.issueCount > 0, item.runningToolCount > 0)) {
      (true, true) => context.l10n.timelineToolGroupSummaryRunningWithIssues(
        item.toolCount,
        item.runningToolCount,
        item.issueCount,
      ),
      (true, false) => context.l10n.timelineToolGroupSummaryIssues(
        item.toolCount,
        item.issueCount,
      ),
      (false, true) => context.l10n.timelineToolGroupSummaryRunning(
        item.toolCount,
        item.runningToolCount,
      ),
      (false, false) => context.l10n.timelineToolGroupSummary(item.toolCount),
    };
    return '$title · $detail';
  }
}

/// 纯思考组的摘要：成员全部终态才汇总有效耗时，任何成员仍在进行即仍显示思考中。
///
/// 失败与取消保留各自真实状态；缺失或非法的成员时间只说明思考结束，不虚构时长。
String _reasoningGroupLabel(
  BuildContext context,
  TimelinePresentationItem item,
) {
  final l10n = context.l10n;
  var total = Duration.zero;
  var active = false;
  var failed = false;
  var cancelled = false;
  var unknown = false;
  for (final payload in item.payloads) {
    final member = payload.item;
    if (member.state is! ThreadThinkingItemStateView) continue;
    // 先聚合整组状态，再决定文案：任一成员未终态都仍显示思考中。
    active = active || !member.isTerminal;
    failed = failed || member.status == 'failed';
    if (member.status == 'cancelled') cancelled = true;
    final elapsed = _reasoningElapsed(member.createdAt, member.completedAt);
    if (elapsed == null) {
      unknown = true;
    } else {
      total += elapsed;
    }
  }
  if (active) return l10n.timelineReasoningActive;
  if (failed) return l10n.timelineReasoningFailed;
  if (cancelled) return l10n.timelineReasoningCancelled;
  if (unknown) return l10n.timelineReasoningEnded;
  return _reasoningElapsedLabel(context, total);
}

/// Only an explicit expansion constructs member widgets; a long group uses a bounded lazy list.
class _TimelineGroupContents extends StatelessWidget {
  const _TimelineGroupContents({
    required this.item,
    required this.lease,
    required this.threadId,
  });
  final TimelinePresentationItem item;
  final TimelineDisplayLease lease;
  final String threadId;

  Widget _member(BuildContext context, int index) {
    final id = item.memberIds[index];
    // 只有活动组成员共享紧凑节奏；重连分组仍按普通条目间距阅读。
    final activity = item.kind == TimelinePresentationKind.activity;
    // 单成员纯思考组：外层组摘要已承担折叠身份与展开意图，成员不再重复一行标题。
    final embeddedReasoning =
        activity &&
        item.thinkingCount == 1 &&
        item.toolCount == 0 &&
        item.length == 1;
    return ValueListenableBuilder<TimelineMessagePayload>(
      key: ValueKey(id),
      valueListenable: item.member(id),
      builder: (context, payload, _) => _TimelineMessageBlock(
        payload: payload,
        lease: lease,
        threadId: threadId,
        inActivityGroup: activity,
        embeddedReasoning: embeddedReasoning,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: item.structure,
    builder: (context, _, child) => _activityIndent(
      context,
      Padding(
        key: const ValueKey('timeline-activity-details'),
        padding: EdgeInsets.zero,
        child: item.length <= 5
            ? ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < item.length; i++) _member(context, i),
                    ],
                  ),
                ),
              )
            : SizedBox(
                height: math.min(320, MediaQuery.sizeOf(context).height * .45),
                child: Scrollbar(
                  child: ListView.builder(
                    primary: false,
                    itemCount: item.length,
                    itemBuilder: _member,
                  ),
                ),
              ),
      ),
    ),
  );

  /// 活动组成员整体缩进一档，并在组标题图标中心下方画低对比引导线表示归属。
  ///
  /// 引导线用 [DecoratedBox] 边框绘制，不占额外几何；图片图集与重连分组保持原布局。
  Widget _activityIndent(BuildContext context, Widget child) {
    if (item.kind != TimelinePresentationKind.activity) return child;
    // 引导线落在组标题图标中心，成员从整档缩进处开始。
    const half = TimelineActivityRow.groupIndent / 2;
    return Padding(
      padding: const EdgeInsets.only(left: half),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: context.colors.outlineVariant.withValues(alpha: 0.55),
              width: 1,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: half),
          child: child,
        ),
      ),
    );
  }
}

class _TimelineImageGroupContents extends StatelessWidget {
  const _TimelineImageGroupContents({
    required this.item,
    required this.lease,
    required this.threadId,
  });
  final TimelineImageReadGroup item;
  final TimelineDisplayLease lease;
  final String threadId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: item,
    builder: (context, _) {
      // Flatten only this group's previews, retaining the owning call even when
      // it has no image yet. Bytes are still read by mounted thumbnails only.
      final entries =
          <
            ({
              TimelineMessagePayload payload,
              _ToolItem call,
              _ToolImageEntryRef? image,
            })
          >[];
      for (final payload in item.payloads) {
        final call = _ToolItem(_entryViewOf(payload.item));
        final images = _toolImageEntries([call]);
        if (images.isEmpty) {
          entries.add((payload: payload, call: call, image: null));
        } else {
          for (final image in images) {
            entries.add((payload: payload, call: call, image: image));
          }
        }
      }
      if (entries.isEmpty) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = math.max(
            1,
            ((constraints.maxWidth + 8) / 128).floor(),
          );
          final rows = (entries.length / columns).ceil();
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              key: StudioDriverKeys.toolImageGallery(item.id),
              width: math.min(constraints.maxWidth, columns * 128.0 - 8),
              height: math.min(320, rows * 128.0 - 8),
              child: Scrollbar(
                child: GridView.builder(
                  primary: false,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 120,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final image = entry.image;
                    void showDetails(BuildContext context) {
                      unawaited(
                        _showImageCallDetails(
                          context,
                          payload: entry.payload,
                          lease: lease,
                          threadId: threadId,
                        ),
                      );
                    }

                    if (image == null) {
                      return _TimelineImageReadStatus(
                        item: entry.call,
                        onShowDetails: showDetails,
                      );
                    }
                    return _ThreadToolImageThumbnail(
                      key: ValueKey(image.entryId),
                      threadId: threadId,
                      entry: image,
                      onShowDetails:
                          entry.call.name != 'view_image' ||
                              entry.call.tool?.result?.trim().isNotEmpty ==
                                  true ||
                              entry.call.error?.isNotEmpty == true ||
                              entry.payload.details.any(
                                (detail) => detail.truncated,
                              )
                          ? showDetails
                          : null,
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// A call without an attachment keeps a small gallery slot. Diagnostics are
/// available on demand, without adding paths and payloads below the gallery.
class _TimelineImageReadStatus extends StatelessWidget {
  const _TimelineImageReadStatus({
    required this.item,
    required this.onShowDetails,
  });
  final _ToolItem item;
  final void Function(BuildContext) onShowDetails;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () => onShowDetails(context),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          item.error == null
              ? Icons.image_outlined
              : Icons.broken_image_outlined,
        ),
        const SizedBox(height: 8),
        Text(
          _toolTitle(context, item),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

Future<void> _showImageCallDetails(
  BuildContext context, {
  required TimelineMessagePayload payload,
  required TimelineDisplayLease lease,
  required String threadId,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(context.l10n.timelineToolOutput),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: _TimelineMessageBlock(
          payload: payload,
          lease: lease,
          threadId: threadId,
        ),
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('timeline-image-details-close'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.timelineImageClose),
      ),
    ],
  ),
);
