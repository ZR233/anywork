import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import 'timeline_activity_row.dart';
import 'timeline_markdown.dart';

/// Pure presentation for the current activity's bounded windows and collections.
///
/// Reading, paging, eligibility and resource retirement stay in the connector.
/// This widget only arranges immutable messages and synchronous child slots.
class ConversationCurrentDetailsView extends StatelessWidget {
  const ConversationCurrentDetailsView({
    this.invalidationNotice,
    this.cleanupError,
    this.onRetryCleanup,
    this.windows = const [],
    this.completedItems,
    this.collections = const [],
    super.key,
  });

  final String? invalidationNotice;
  final Object? cleanupError;
  final VoidCallback? onRetryCleanup;
  final List<Widget> windows;
  final Widget? completedItems;
  final List<Widget> collections;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (invalidationNotice case final notice?)
          _CurrentNotice(
            key: const ValueKey('current-invalidation-notice'),
            icon: Icons.refresh_rounded,
            message: notice,
            color: colors.onSurfaceVariant,
          ),
        if (cleanupError case final error?)
          _CurrentNotice(
            key: const ValueKey('current-cleanup-error'),
            icon: Icons.error_outline_rounded,
            message: error.toString(),
            color: colors.error,
            actionLabel: '重试释放内容观察',
            onAction: onRetryCleanup,
          ),
        ...windows,
        ?completedItems,
        ...collections,
      ],
    );
  }
}

class _CurrentNotice extends StatelessWidget {
  const _CurrentNotice({
    required this.icon,
    required this.message,
    required this.color,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: context.text.bodySmall?.copyWith(
              color: color,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: context.text.labelSmall,
            ),
            child: Text(actionLabel!),
          ),
      ],
    ),
  );
}

/// A bounded current-content window. The supplied text is already accepted by
/// its owner; this view never starts a query or retains a resource handle.
class ConversationCurrentWindowView extends StatelessWidget {
  const ConversationCurrentWindowView({
    required this.id,
    required this.text,
    this.label,
    this.error,
    this.offset,
    this.end,
    this.availableThrough,
    this.onFirst,
    this.onNext,
    super.key,
  });

  final String id;
  final String text;
  final String? label;
  final Object? error;
  final int? offset;
  final int? end;
  final int? availableThrough;
  final VoidCallback? onFirst;
  final VoidCallback? onNext;

  bool get _hasRange =>
      offset != null && end != null && availableThrough != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasEarlier = _hasRange && offset! > 0;
    final hasLater = _hasRange && end! < availableThrough!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label case final label?)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                label,
                style: context.text.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ),
          if (error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                error.toString(),
                key: ValueKey('current-window-error:$id'),
                style: context.text.bodySmall?.copyWith(
                  color: colors.error,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          TimelineMarkdown(
            id: 'current:$id',
            text: text,
            style: context.text.bodySmall?.copyWith(
              color: colors.onSurface,
              fontSize: 12.5,
              height: 1.48,
            ),
            onLink: (_) {},
            isSafeLink: (_) => false,
            imageBuilder: (_, url) => Text(url),
          ),
          if (hasEarlier || hasLater)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  Text(
                    '字节 $offset–$end / $availableThrough',
                    style: context.text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  if (hasEarlier && onFirst != null)
                    TextButton(
                      onPressed: onFirst,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('第一段'),
                    ),
                  if (hasLater && end! > offset! && onNext != null)
                    TextButton(
                      onPressed: onNext,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('下一段'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Pure disclosure for a current collection page.
class ConversationCurrentCollectionView extends StatelessWidget {
  const ConversationCurrentCollectionView({
    required this.title,
    required this.onExpansionChanged,
    this.titleKey,
    this.loading = false,
    this.stale = false,
    this.error,
    this.onReload,
    this.reloadKey,
    this.entries = const [],
    this.onNextPage,
    this.nextPageKey,
    super.key,
  });

  final String title;
  final Key? titleKey;
  final bool loading;
  final bool stale;
  final Object? error;
  final ValueChanged<bool> onExpansionChanged;
  final VoidCallback? onReload;
  final Key? reloadKey;
  final List<Widget> entries;
  final VoidCallback? onNextPage;
  final Key? nextPageKey;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: TimelineActivityDisclosure(
      onExpansionChanged: onExpansionChanged,
      titleBuilder: (context, expanded) => TimelineActivityRow(
        labelKey: titleKey,
        icon: Icons.workspaces_outline,
        label: title,
        emphasized: true,
        expanded: expanded,
      ),
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (stale)
          const _CollectionMessage(
            icon: Icons.refresh_rounded,
            message: '当前集合已更新，原版本已失效',
          ),
        if (error case final error?)
          _CollectionMessage(
            icon: Icons.error_outline_rounded,
            message: error.toString(),
            error: true,
          ),
        if ((stale || error != null) && onReload != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: reloadKey,
              onPressed: onReload,
              child: const Text('重新读取当前页'),
            ),
          ),
        ...entries,
        if (onNextPage != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: nextPageKey,
              onPressed: loading ? null : onNextPage,
              child: const Text('下一页'),
            ),
          ),
      ],
    ),
  );
}

class _CollectionMessage extends StatelessWidget {
  const _CollectionMessage({
    required this.icon,
    required this.message,
    this.error = false,
  });

  final IconData icon;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? context.colors.error
        : context.colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(
                color: color,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pure current-entry disclosure. The connector decides what the body means
/// and whether opening it creates bounded read demand.
class ConversationCurrentEntryView extends StatelessWidget {
  const ConversationCurrentEntryView({
    required this.title,
    required this.child,
    this.titleKey,
    this.onExpansionChanged,
    super.key,
  });

  final String title;
  final Key? titleKey;
  final Widget child;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: TimelineActivityDisclosure(
      onExpansionChanged: onExpansionChanged,
      titleBuilder: (context, expanded) => TimelineActivityRow(
        labelKey: titleKey,
        icon: Icons.article_outlined,
        label: title,
        expanded: expanded,
      ),
      children: [child],
    ),
  );
}
