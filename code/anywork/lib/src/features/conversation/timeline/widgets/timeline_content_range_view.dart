import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../shared/studio_driver_keys.dart';
import 'timeline_activity_row.dart';

/// The enclosing semantic disclosure is already the user's read intent.
/// Mounted bodies therefore do not require a second click. A declared summary
/// uses the same bounded read, but remains a single line in its member header.
class TimelineBodyReadIntent extends InheritedWidget {
  const TimelineBodyReadIntent({
    required super.child,
    this.summary = false,
    super.key,
  });
  final bool summary;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TimelineBodyReadIntent>() !=
      null;
  static bool summaryOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TimelineBodyReadIntent>()
          ?.summary ??
      false;
  @override
  bool updateShouldNotify(TimelineBodyReadIntent oldWidget) =>
      summary != oldWidget.summary;
}

/// Pure presentation for one already-admitted bounded content window.
///
/// The connector owns reads, eligibility, request generations, diagnostics and
/// Clipboard IO. This widget only renders immutable accepted values and invokes
/// synchronous actions.
class TimelineContentRangeView extends StatelessWidget {
  const TimelineContentRangeView({
    super.key,
    required this.itemId,
    required this.contentKey,
    required this.label,
    this.initiallyExpanded = false,
    this.disclosed = false,
    required this.loading,
    required this.active,
    required this.canRead,
    required this.onExpansionChanged,
    required this.onNext,
    required this.onCopy,
    required this.witness,
    this.window,
    this.error,
  });

  final String itemId;
  final String contentKey;
  final String label;
  final bool initiallyExpanded;
  final bool disclosed;
  final bool loading;
  final bool active;
  final bool canRead;
  final ContentWindow? window;
  final Object? error;
  final ValueChanged<bool> onExpansionChanged;
  final VoidCallback? onNext;
  final VoidCallback? onCopy;
  final Widget Function(String text, Widget child) witness;

  @override
  Widget build(BuildContext context) {
    final window = this.window;
    final end = window == null ? 0 : window.offset + window.bytes.length;
    final text = window == null
        ? ''
        : utf8.decode(window.bytes, allowMalformed: true);
    final hasNext =
        window != null &&
        window.bytes.isNotEmpty &&
        end < window.availableThrough;
    final contents = <Widget>[
      if (loading) const LinearProgressIndicator(minHeight: 1),
      if (error != null)
        Text(
          error.toString(),
          style: context.text.bodySmall?.copyWith(color: context.colors.error),
        ),
      if (window != null) ...[
        if (!disclosed || hasNext || window.offset > 0)
          Text(
            '字节 ${window.offset}–$end / ${window.availableThrough}',
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 4),
        // A bounded window may end inside a UTF-8 code point. This is
        // a raw byte-range viewer, not a business payload decoder.
        witness(
          text,
          Text(
            text,
            key: StudioDriverKeys.timelineContentWindow(itemId, contentKey),
            softWrap: true,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            TextButton(
              key: StudioDriverKeys.timelineContentCopyWindow(
                itemId,
                contentKey,
              ),
              onPressed: active && !loading ? onCopy : null,
              child: const Text('复制当前段'),
            ),
            if (hasNext)
              TextButton(
                key: StudioDriverKeys.timelineContentNextWindow(
                  itemId,
                  contentKey,
                ),
                onPressed: active && !loading ? onNext : null,
                child: const Text('下一段'),
              ),
          ],
        ),
      ],
    ];
    return TimelineActivityTileTheme(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (disclosed)
            ...contents
          else
            TimelineActivityDisclosure(
              key: StudioDriverKeys.timelineContentOpen(itemId, contentKey),
              initiallyExpanded: initiallyExpanded,
              enabled: !loading && active && canRead,
              onExpansionChanged: onExpansionChanged,
              titleBuilder: (context, expanded) => TimelineActivityRow(
                icon: Icons.article_outlined,
                label: label,
                active: loading,
                expanded: expanded,
              ),
              children: contents,
            ),
          if (!canRead)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: TimelineActivityRow.contentIndent,
                bottom: 4,
              ),
              child: Text(
                '内容读取尚未就绪',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
