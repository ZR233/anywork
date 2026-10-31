import 'dart:convert';

import 'package:anywork/src/features/conversation/composer/connectors/composer_dock_connector.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_driver/flutter_driver.dart' hide find;
import 'package:flutter_test/flutter_test.dart';

import 'scrollbar_drag.dart';

class ScrollbarDragCommandExtension extends CommandExtension {
  @override
  String get commandKind => 'ScrollbarDrag';

  @override
  Command deserialize(
    Map<String, String> params,
    DeserializeFinderFactory finderFactory,
    DeserializeCommandFactory commandFactory,
  ) => ScrollbarDrag.deserialize(params, finderFactory);

  @override
  Future<Result> call(
    Command command,
    WidgetController prober,
    CreateFinderFactory finderFactory,
    CommandHandlerFactory handlerFactory,
  ) async {
    final drag = command as ScrollbarDrag;
    final target = finderFactory.createFinder(drag.finder);
    final scrollbarWidgets = find.byWidgetPredicate(
      (widget) => widget is RawScrollbar,
    );
    final descendants = find.descendant(of: target, matching: scrollbarWidgets);
    final scrollbars = descendants.evaluate().isNotEmpty
        ? descendants
        : find.ancestor(of: target, matching: scrollbarWidgets);
    final paintFinder = find
        .descendant(
          of: scrollbars.first,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.foregroundPainter is ScrollbarPainter,
          ),
        )
        .first;
    // A desktop user first moves the mouse over the scrollbar. Drive that
    // standard hover path to reveal the SDK thumb, including at an extent where
    // a wheel request would have no effect. Do not move ScrollPosition directly.
    Offset trackCenter() {
      final painter =
          prober.widget<CustomPaint>(paintFinder).foregroundPainter!
              as ScrollbarPainter;
      final box = paintFinder.evaluate().single.renderObject! as RenderBox;
      final padding = painter.padding.resolve(painter.textDirection);
      return box.localToGlobal(
        Offset(
          box.size.width -
              painter.thickness / 2 -
              painter.crossAxisMargin -
              padding.right,
          box.size.height / 2,
        ),
      );
    }

    // Use the painter's public hit test, at the interior of its actual track.
    // In particular, do not assume that a fixed x lies inside a six-pixel thumb.
    List<Offset> interactiveThumbHits() {
      final painter =
          prober.widget<CustomPaint>(paintFinder).foregroundPainter!
              as ScrollbarPainter;
      final box = paintFinder.evaluate().single.renderObject! as RenderBox;
      final x = box.globalToLocal(trackCenter()).dx;
      return [
        for (double y = 0; y < box.size.height; y += 2)
          if (painter.hitTestOnlyThumbInteractive(
            Offset(x, y),
            PointerDeviceKind.mouse,
          ))
            box.localToGlobal(Offset(x, y)),
      ];
    }

    final samples = <Object?>[];
    List<Map<String, Object?>> geometry(Finder finder) => [
      for (final element in finder.evaluate())
        if (element.renderObject case final RenderBox box when box.hasSize)
          {
            'widget': element.widget.runtimeType.toString(),
            'top': box.localToGlobal(Offset.zero).dy,
            'left': box.localToGlobal(Offset.zero).dx,
            'width': box.size.width,
            'height': box.size.height,
            if (element.widget case final ConstrainedBox constrained)
              'constraints': constrained.constraints.toString(),
          },
    ];
    num? previousViewport;
    var recordFollowingFrame = false;
    void sample() {
      final snapshot =
          jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
      final scroll = snapshot['timelineScroll'] as Map<String, dynamic>;
      final viewport = scroll['viewportDimension'] as num?;
      final viewportChanged = viewport != previousViewport;
      final recordGeometry = viewportChanged || recordFollowingFrame;
      previousViewport = viewport;
      recordFollowingFrame = viewportChanged;
      // Keep the actual scroll samples and input path unchanged. These public
      // layout bounds identify which sibling changes the viewport during a drag.
      // Only inspect the tree at a change and its following frame so steady
      // samples retain the original observation cost.
      samples.add({
        ...scroll,
        if (recordGeometry)
          'geometry': {
            'scrollbar': geometry(paintFinder),
            'timeline': geometry(find.byKey(StudioDriverKeys.timeline)),
            'returnLive': geometry(
              find.byKey(StudioDriverKeys.timelineReturnLive),
            ),
            'connectionNotice': geometry(
              find.byKey(StudioDriverKeys.timelineConnectionNotice),
            ),
            'loadingOlder': geometry(
              find.byKey(StudioDriverKeys.timelineLoadingOlder),
            ),
            'retryOlder': geometry(
              find.byKey(StudioDriverKeys.timelineRetryOlder),
            ),
            'footer': geometry(
              find.byKey(StudioDriverKeys.workspaceFooterScroll),
            ),
            'activity': geometry(
              find.byKey(const ValueKey('conversation-activity')),
            ),
            'response': geometry(
              find.byKey(
                const ValueKey('conversation-activity-response-stream'),
              ),
            ),
            'composerDock': geometry(find.byType(ComposerDockConnector)),
            'composerInput': geometry(
              find.byKey(StudioDriverKeys.composerInput),
            ),
            'statusBar': geometry(find.byType(ThreadStatusBar)),
            'workspaceBody': geometry(find.byType(StudioWorkspaceBody)),
            'workspacePane': geometry(find.byType(AgentWorkspacePane)),
          },
      });
    }

    final gesture = await prober.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: trackCenter());
    var pressed = false;
    try {
      await gesture.moveTo(trackCenter());
      final wait = Stopwatch()..start();
      var hits = interactiveThumbHits();
      while (hits.isEmpty && wait.elapsed < const Duration(seconds: 2)) {
        SchedulerBinding.instance.scheduleFrame();
        await SchedulerBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 16));
        hits = interactiveThumbHits();
      }
      if (hits.isEmpty) throw StateError('No painted timeline scrollbar thumb');
      final start = hits[hits.length ~/ 2];
      await gesture.moveTo(start);
      sample();
      await gesture.down(start);
      pressed = true;
      for (var step = 1; step <= 24; step++) {
        await gesture.moveTo(start + Offset(0, drag.dy * step / 24));
        SchedulerBinding.instance.scheduleFrame();
        await SchedulerBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 16));
        sample();
      }
    } finally {
      if (pressed) await gesture.up();
      await gesture.removePointer();
    }
    return _DragResult(samples);
  }
}

class _DragResult extends Result {
  const _DragResult(this.samples);
  final List<Object?> samples;

  @override
  Map<String, dynamic> toJson() => {'samples': samples};
}
