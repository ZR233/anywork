import 'dart:convert';

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
    void sample() {
      samples.add(
        jsonDecode(StudioDriverState.snapshotJson())['timelineScroll'],
      );
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
