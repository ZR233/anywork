import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../state/content_reference_identity.dart';
import 'timeline_activity_row.dart';

/// Completed bounded reads handed off by this row's original metadata reader.
class TimelineInitialBodyReads extends InheritedWidget {
  const TimelineInitialBodyReads({
    super.key,
    required this.results,
    required super.child,
  });
  final Map<Object, AsyncSnapshot<ContentWindow>> results;

  static AsyncSnapshot<ContentWindow>? read(
    BuildContext context,
    HistoryEventBodyRef reference,
  ) => context
      .getInheritedWidgetOfExactType<TimelineInitialBodyReads>()
      ?.results[historyBodyIdentity(reference)];

  @override
  bool updateShouldNotify(TimelineInitialBodyReads oldWidget) =>
      !identical(results, oldWidget.results);
}

/// A presentation owner's stable read epoch; this grants no query permission.
class TimelineBodyReadQualification extends InheritedWidget {
  const TimelineBodyReadQualification({
    required this.value,
    required super.child,
    super.key,
  });

  final Object value;

  static Object? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TimelineBodyReadQualification>()
      ?.value;

  @override
  bool updateShouldNotify(TimelineBodyReadQualification oldWidget) =>
      !identical(value, oldWidget.value);
}

/// The enclosing semantic disclosure is already the user's read intent.
/// Mounted bodies therefore do not require a second click. A declared summary
/// uses the same bounded read, but remains a single line in its member header.
class TimelineBodyReadIntent extends InheritedWidget {
  const TimelineBodyReadIntent({
    required super.child,
    this.summary = false,
    this.scrollable = false,
    this.bodyBuilder,
    this.onRead,
    super.key,
  });
  final bool summary;
  final bool scrollable;
  final Widget Function(String text)? bodyBuilder;
  final ValueChanged<ContentWindow>? onRead;
  static ValueChanged<ContentWindow>? onReadOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TimelineBodyReadIntent>()
      ?.onRead;
  static Widget Function(String text)? bodyBuilderOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TimelineBodyReadIntent>()
          ?.bodyBuilder;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TimelineBodyReadIntent>() !=
      null;
  static bool summaryOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TimelineBodyReadIntent>()
          ?.summary ??
      false;
  static bool scrollableOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TimelineBodyReadIntent>()
          ?.scrollable ??
      false;
  @override
  bool updateShouldNotify(TimelineBodyReadIntent oldWidget) =>
      summary != oldWidget.summary ||
      scrollable != oldWidget.scrollable ||
      onRead != oldWidget.onRead ||
      bodyBuilder != oldWidget.bodyBuilder;
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
    this.bodyBuilder,
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
  final Widget Function(String text)? bodyBuilder;
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
    final showRange = !disclosed || hasNext || (window?.offset ?? 0) > 0;
    final contents = <Widget>[
      if (loading) const LinearProgressIndicator(minHeight: 1),
      if (error != null)
        Text(
          error.toString(),
          style: context.text.bodySmall?.copyWith(color: context.colors.error),
        ),
      if (window != null) ...[
        if (showRange)
          Text(
            '字节 ${window.offset}–$end / ${window.availableThrough}',
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 4),
        // Decode only this admitted window; never accumulate the full body.
        witness(
          text,
          bodyBuilder == null
              ? Text(
                  text,
                  key: StudioDriverKeys.timelineContentWindow(
                    itemId,
                    contentKey,
                  ),
                  softWrap: true,
                )
              : KeyedSubtree(
                  key: StudioDriverKeys.timelineContentWindow(
                    itemId,
                    contentKey,
                  ),
                  child: bodyBuilder!(text),
                ),
        ),
        if (bodyBuilder == null || showRange) ...[
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
