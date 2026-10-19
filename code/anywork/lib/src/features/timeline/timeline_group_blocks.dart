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
        builder: (context, body) => ExpansionTile(
          controller: _expansion,
          initiallyExpanded: item.expanded,
          onExpansionChanged: item.setExpanded,
          maintainState: false,
          showTrailingIcon: false,
          minTileHeight: 28,
          dense: true,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 7, bottom: 6),
          shape: const Border(),
          collapsedShape: const Border(),
          title: _TimelineActivitySummary(
            key: StudioDriverKeys.timelineActivitySummary(item.id),
            icon: switch (item.kind) {
              TimelinePresentationKind.images => Icons.image_outlined,
              TimelinePresentationKind.recovery => Icons.sync,
              _ => Icons.psychology_alt_outlined,
            },
            label: _label(context, item),
            isIssue: item.issueCount > 0,
            active: item is TimelineRecoveryGroup
                ? (item.latest.source as StudioTimelineRecoverySource).notice ==
                      StudioTimelineRecoveryNotice.retry
                : item.activeCount > 0,
            expanded: item.expanded,
          ),
          children: [body!],
        ),
        child: item is TimelineImageReadGroup
            ? _TimelineImageGroupContents(item: item, threadId: widget.threadId)
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
      final status = item.issueCount > 0
          ? context.l10n.timelineViewImageFailed
          : item.activeCount > 0
          ? context.l10n.timelineViewImageReading
          : '';
      return [count, status].where((part) => part.isNotEmpty).join(' · ');
    }
    final title = item.thinkingCount > 0
        ? context.l10n.timelineActivityTitle
        : context.l10n.timelineToolGroupTitle;
    final detail = item.toolCount > 0
        ? switch ((item.issueCount > 0, item.runningToolCount > 0)) {
            (true, true) =>
              context.l10n.timelineToolGroupSummaryRunningWithIssues(
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
            (false, false) => context.l10n.timelineToolGroupSummary(
              item.toolCount,
            ),
          }
        : item.activeCount > 0
        ? context.l10n.timelineReasoningActive
        : context.l10n.timelineReasoningCompleted;
    return '$title · $detail';
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
    final id = item.memberIds[index];
    return ValueListenableBuilder<TimelineMessagePayload>(
      key: ValueKey(id),
      valueListenable: item.member(id),
      builder: (context, payload, _) => _TimelineMessageBlock(
        payload: payload,
        lease: lease,
        threadId: threadId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: item.structure,
    builder: (context, _, child) => DecoratedBox(
      key: const ValueKey('timeline-activity-details'),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: context.colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
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
}

class _TimelineImageGroupContents extends StatelessWidget {
  const _TimelineImageGroupContents({
    required this.item,
    required this.threadId,
  });
  final TimelineImageReadGroup item;
  final String threadId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: item,
    builder: (context, _) {
      // Flatten only this group's previews, retaining the owning call even when
      // it has no image yet. Bytes are still read by mounted thumbnails only.
      final entries = <({_ToolItem call, _ToolImageEntryRef? image})>[];
      for (final payload in item.payloads) {
        final call = _ToolItem(_entryViewOf(payload.item));
        final images = _toolImageEntries([call]);
        if (images.isEmpty) {
          entries.add((call: call, image: null));
        } else {
          for (final image in images) {
            entries.add((call: call, image: image));
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
                    if (image == null) {
                      return _TimelineImageReadStatus(item: entry.call);
                    }
                    return _ThreadToolImageThumbnail(
                      key: ValueKey(image.entryId),
                      threadId: threadId,
                      entry: image,
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
  const _TimelineImageReadStatus({required this.item});
  final _ToolItem item;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_toolTitle(context, item)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: _ToolDetails(item: item)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.timelineImageClose),
          ),
        ],
      ),
    ),
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
