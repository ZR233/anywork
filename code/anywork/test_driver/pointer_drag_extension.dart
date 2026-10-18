import 'dart:convert';
import 'dart:math' as math;

import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pointer_drag.dart';

class PointerDragCommandExtension extends CommandExtension {
  @override
  String get commandKind => 'PointerDrag';

  @override
  Command deserialize(
    Map<String, String> params,
    DeserializeFinderFactory finderFactory,
    DeserializeCommandFactory commandFactory,
  ) => PointerDrag.deserialize(params, finderFactory);

  @override
  Future<Result> call(
    Command command,
    WidgetController prober,
    CreateFinderFactory finderFactory,
    CommandHandlerFactory handlerFactory,
  ) async {
    final drag = command as PointerDrag;
    final finder = finderFactory.createFinder(drag.finder);
    final object = finder.evaluate().single.renderObject! as RenderBox;
    RenderObject root = object;
    while (root.parent != null) {
      root = root.parent!;
    }
    if (root is! RenderView) throw StateError('Drag target has no render view');
    final start = object.localToGlobal(object.size.center(Offset.zero));
    final hit = HitTestResult();
    root.hitTest(hit, position: start);
    if (!hit.path.any(
      (entry) => isRenderObjectAncestorOfTarget(object, entry.target),
    )) {
      throw StateError('Drag target is covered at its center');
    }
    final samples = <Object?>[];
    void sample(String phase) {
      samples.add({
        'phase': phase,
        'scroll': jsonDecode(
          StudioDriverState.snapshotJson(),
        )['timelineScroll'],
      });
    }

    sample('beforeDown');
    final gesture = await prober.startGesture(start, view: root.flutterView);
    try {
      // Cross touch slop before waiting for a costly streamed-body layout.
      // The following frame still exercises layout between DragStart and the
      // first update; no scroll position or product reading intent is written.
      final total = Offset(drag.dx, drag.dy);
      if (total.distance == 0) {
        throw StateError('Drag distance must not be zero');
      }
      final unit = total / total.distance;
      final slop = math.min(total.distance, kTouchSlop + 1);
      Offset at(double travelled) =>
          start + unit * travelled.clamp(0.0, total.distance);
      await gesture.moveTo(at(slop), view: root.flutterView);
      await _frame();
      sample('afterStart');
      for (var step = 1; step <= 8; step++) {
        final travelled = slop + (total.distance - slop) * step / 8;
        await gesture.moveTo(at(travelled), view: root.flutterView);
        await _frame();
        sample('move$step');
      }
    } finally {
      await gesture.up(view: root.flutterView);
      await gesture.removePointer();
    }
    await _frame();
    sample('afterUp');
    return _PointerDragResult(samples);
  }
}

Future<void> _frame() {
  final binding = SchedulerBinding.instance;
  binding.scheduleFrame();
  return binding.endOfFrame;
}

class _PointerDragResult extends Result {
  const _PointerDragResult(this.samples);
  final List<Object?> samples;

  @override
  Map<String, dynamic> toJson() => {'samples': samples};
}
