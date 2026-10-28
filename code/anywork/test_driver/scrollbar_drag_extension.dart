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
    final paint = prober.widget<CustomPaint>(paintFinder);
    final painter = paint.foregroundPainter! as ScrollbarPainter;
    final box = paintFinder.evaluate().single.renderObject! as RenderBox;
    final samples = <Object?>[];
    void sample() {
      samples.add(
        jsonDecode(StudioDriverState.snapshotJson())['timelineScroll'],
      );
    }

    final gesture = await prober.createGesture(kind: PointerDeviceKind.mouse);
    final hover = box.localToGlobal(
      Offset(box.size.width - 6, box.size.height / 2),
    );
    var pressed = false;
    await gesture.addPointer(location: hover);
    try {
      // RawScrollbar deliberately rejects a transparent thumb. Real hover
      // starts its own fade-in; do not change visibility or painter state.
      await gesture.moveTo(hover);
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      final hits = <Offset>[];
      while (hits.isEmpty) {
        // Ask the SDK which pixels actually belong to its interactive thumb.
        for (double y = 0; y < box.size.height; y += 2) {
          final point = box.localToGlobal(Offset(box.size.width - 6, y));
          if (painter.hitTestOnlyThumbInteractive(
            box.globalToLocal(point),
            PointerDeviceKind.mouse,
          )) {
            hits.add(point);
          }
        }
        if (hits.isNotEmpty) break;
        if (!DateTime.now().isBefore(deadline)) {
          throw StateError('No painted timeline scrollbar thumb after hover');
        }
        SchedulerBinding.instance.scheduleFrame();
        await SchedulerBinding.instance.endOfFrame;
      }
      final start = hits[hits.length ~/ 2];
      sample();
      await gesture.moveTo(start);
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
      try {
        if (pressed) await gesture.up();
      } finally {
        await gesture.removePointer();
      }
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
