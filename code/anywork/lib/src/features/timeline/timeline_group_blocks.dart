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
    // 展示工具的图片卡片独立占一行：不套可折叠活动组，也不产生组摘要。
    if (item is TimelineImageCardGroup) {
      return ValueListenableBuilder<TimelineMessagePayload>(
        valueListenable: item.member(item.memberIds.first),
        builder: (context, payload, _) =>
            _TimelineImageCardBlock(payload: payload),
      );
    }
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
    if (item is TimelineActivityGroup) {
      return TimelineLiveActivityGroupBlock(
        key: ValueKey(item.id),
        group: item,
        onOpenDetail: (itemId, field) => unawaited(
          _openTimelineDetailViewer(
            context,
            lease: lease,
            itemId: itemId,
            field: field,
          ),
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
                TimelinePresentationKind.activity ||
                TimelinePresentationKind.imageCard ||
                TimelinePresentationKind.single => null,
              },
              label: _label(context, item),
              isIssue:
                  item.kind != TimelinePresentationKind.activity &&
                  item.issueCount > 0,
              active: item is TimelineRecoveryGroup
                  ? (item.latest.source as StudioTimelineRecoverySource)
                            .notice ==
                        StudioTimelineRecoveryNotice.retry
                  : item.activeCount > 0,
              expanded: item.expanded,
              expandable: timelineGroupExpandable(item),
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

  String _label(BuildContext context, TimelinePresentationItem item) {
    if (item is TimelineRecoveryGroup) return item.latest.item.text;
    if (item is TimelineImageReadGroup) {
      final count = item.imageCount > 0
          ? context.l10n.timelineImagesViewed(item.imageCount)
          : '';
      // 停止判定消费与问题计数同一份 typed item.status（不解析原因文本），
      // 只看 O(1) 的最新成员：混合组里失败与进行中优先，成功数量保留。
      final stopped =
          item.issueCount == 0 &&
          item.activeCount == 0 &&
          const {'cancelled', 'interrupted'}.contains(item.latest.item.status);
      final status = item.issueCount > 0
          ? context.l10n.timelineViewImageFailed
          : item.activeCount > 0
          ? context.l10n.timelineViewImageReading
          : stopped
          ? context.l10n.timelineViewImageStopped
          : '';
      return [count, status].where((part) => part.isNotEmpty).join(' · ');
    }
    return timelineActivityGroupLabel(context, item);
  }
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
    final id = item.visibleMemberIds[index];
    final paired = item.pairedToolId(id);
    // 技能行接管原调用：这里只构建一条技能行，原调用的详情仍从它的展开区读取。
    if (item.payload(id)?.item.skill != null) {
      return TimelineSkillActivity(
        key: ValueKey('timeline-skill-activity-$id'),
        skill: item.member(id),
        tool: paired == null ? null : item.member(paired),
        onOpenDetail: (itemId, field) => unawaited(
          _openTimelineDetailViewer(
            context,
            lease: lease,
            itemId: itemId,
            field: field,
          ),
        ),
      );
    }
    // 只有活动组成员共享紧凑节奏；重连分组仍按普通条目间距阅读。
    final activity = item.kind == TimelinePresentationKind.activity;
    return ValueListenableBuilder<TimelineMessagePayload>(
      key: ValueKey(id),
      valueListenable: item.member(id),
      builder: (context, payload, _) => _TimelineMessageBlock(
        payload: payload,
        lease: lease,
        threadId: threadId,
        inActivityGroup: activity,
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
        // 短组按成员自然高度铺开：`ConstrainedBox(maxHeight: 320)` 只是上限，不是固定高度，
        // 因此 10 条以内的紧凑成员不会在引导线下留出空白。超过 10 条仍用有界惰性列表，
        // 长详情也仍在该 320 上限内滚动。
        child: item.visibleMemberIds.length <= 10
            ? ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < item.visibleMemberIds.length; i++)
                        _member(context, i),
                    ],
                  ),
                ),
              )
            : SizedBox(
                height: math.min(320, MediaQuery.sizeOf(context).height * .45),
                child: Scrollbar(
                  child: ListView.builder(
                    primary: false,
                    itemCount: item.visibleMemberIds.length,
                    itemBuilder: _member,
                  ),
                ),
              ),
      ),
    ),
  );

  /// 活动组成员整体缩进一档，并在左侧画低对比引导线表示归属。
  Widget _activityIndent(BuildContext context, Widget child) {
    if (item.kind != TimelinePresentationKind.activity) return child;
    return timelineActivityIndent(context, child);
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
              TimelineToolItem call,
              _ToolImageEntryRef? image,
            })
          >[];
      for (final payload in item.payloads) {
        final call = TimelineToolItem(timelineEntryViewOf(payload.item));
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
  final TimelineToolItem item;
  final void Function(BuildContext) onShowDetails;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () => onShowDetails(context),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(switch (item.status) {
          'failed' || 'denied' => Icons.broken_image_outlined,
          // 取消与中断是正常控制结果：中性停止图标，不用失败图形。
          'cancelled' || 'interrupted' => Icons.stop_circle_outlined,
          _ => Icons.image_outlined,
        }),
        const SizedBox(height: 8),
        Text(
          timelineToolTitle(context, item),
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
