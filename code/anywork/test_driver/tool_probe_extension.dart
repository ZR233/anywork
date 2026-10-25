import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_driver/flutter_driver.dart' hide find;
import 'package:flutter_test/flutter_test.dart';

import 'tool_probe.dart';
import 'driver_binding.dart';

class ToolProbeExtension extends CommandExtension {
  static const _mouseDevice = 901;
  int? _mouseViewId;

  @override
  String get commandKind => 'ToolProbe';
  @override
  Command deserialize(
    Map<String, String> params,
    DeserializeFinderFactory finderFactory,
    DeserializeCommandFactory commandFactory,
  ) => ToolProbe.deserialize(params, finderFactory);
  @override
  Future<Result> call(
    Command command,
    WidgetController prober,
    CreateFinderFactory finderFactory,
    CommandHandlerFactory handlerFactory,
  ) async {
    final probe = command as ToolProbe;
    final target = probe.finder is ByValueKey
        ? find.byKey(
            ValueKey<String>((probe.finder as ByValueKey).keyValue as String),
            skipOffstage: false,
          )
        : finderFactory.createFinder(probe.finder);
    if (probe.action == 'observe' && target.evaluate().isEmpty) {
      return _ProbeResult([
        {'mounted': false},
      ]);
    }
    Map<String, Object?> sample() {
      final element = target.evaluate().single;
      final box = element.renderObject! as RenderBox;
      final widget = element.widget;
      final offset = box.localToGlobal(Offset.zero);
      final nested = find.descendant(
        of: target,
        matching: find.byType(Scrollable),
      );
      // stock `ExpansionTile` 不显式传 controller 时会自建 controller 并交给公开的
      // `Expansible`（`ExpansionTile.build` 返回 `Expansible(controller: …)`）。
      // 状态只能从那个公开 widget 的 required `controller.isExpanded` 读取：不读
      // 私有 State、不加生产 controller/test hook。`null` 不是“没有状态”。
      bool? expanded;
      if (widget is ExpansionTile) {
        final expansibles = find
            .descendant(
              of: target,
              // `_DescendantFinderMixin` 用 matching 自己的 `skipOffstage` 全树求值，
              // 外层参数不会透传给它。惰性列表里尚未进入视口的行处在 offstage 子树，
              // 因此 matching 也必须显式包含 offstage，否则会误判“没有 Expansible”。
              matching: find.byType(Expansible, skipOffstage: false),
              skipOffstage: false,
            )
            .evaluate();
        if (expansibles.isEmpty) {
          final descendants = find
              .descendant(
                of: target,
                matching: find.byElementPredicate((_) => true),
                skipOffstage: false,
              )
              .evaluate()
              .take(100)
              .map((element) => element.widget.runtimeType.toString())
              .toList(growable: false);
          throw StateError(
            'ExpansionTile target exposes no public Expansible descendant: '
            '$target; descendants=$descendants',
          );
        }
        expanded =
            (expansibles.first.widget as Expansible).controller.isExpanded;
      }
      final production = jsonDecode(captureDriverJson());
      final scroll = production is Map ? production['timelineScroll'] : null;
      final timeline = production is Map ? production['timeline'] : null;
      Element? presentation;
      element.visitAncestorElements((ancestor) {
        final key = ancestor.widget.key;
        if (key is ValueKey<String> && key.value.startsWith('timeline-row-')) {
          presentation = ancestor;
        }
        return true;
      });
      final presentationBox = presentation?.renderObject;
      return {
        'top': offset.dy,
        'left': offset.dx,
        'width': box.size.width,
        'height': box.size.height,
        if (presentationBox is RenderBox)
          'presentationGeometry': {
            'top': presentationBox.localToGlobal(Offset.zero).dy,
            'height': presentationBox.size.height,
          },
        'expanded': ?expanded,
        'scroll': scroll,
        // 展示模式来自同一次只读快照，供宿主断言“同 Thread/gen/History”。
        'mode': timeline is Map ? timeline['mode'] : null,
        'nested': [
          for (final e in nested.evaluate())
            if (e is StatefulElement && e.state is ScrollableState)
              {
                'axis': (e.state as ScrollableState).position.axis.name,
                'pixels': (e.state as ScrollableState).position.pixels,
                'max': (e.state as ScrollableState).position.maxScrollExtent,
              },
        ],
      };
    }

    final samples = <Object?>[sample()];
    final box = target.evaluate().single.renderObject! as RenderBox;
    final top = box.localToGlobal(Offset.zero);
    if (probe.action == 'hover') {
      final viewId = View.of(target.evaluate().single).viewId;
      final center = top + box.size.center(Offset.zero);
      if (_mouseViewId != viewId) {
        _removeMouse();
        GestureBinding.instance.handlePointerEvent(
          PointerAddedEvent(
            device: _mouseDevice,
            kind: PointerDeviceKind.mouse,
            position: center,
            viewId: viewId,
          ),
        );
        _mouseViewId = viewId;
      }
      GestureBinding.instance.handlePointerEvent(
        PointerHoverEvent(
          device: _mouseDevice,
          kind: PointerDeviceKind.mouse,
          position: center,
          viewId: viewId,
        ),
      );
    } else if (probe.action == 'leaveHover') {
      _removeMouse();
    } else if (probe.action == 'tap') {
      // Header, not the center of the whole expanded tile.
      await prober.tapAt(top + Offset(30, 20));
    } else if (probe.action == 'wheelOutside') {
      GestureBinding.instance.handlePointerEvent(
        PointerScrollEvent(
          position: top + Offset(4, box.size.height / 2),
          scrollDelta: Offset(0, probe.dy),
          kind: PointerDeviceKind.mouse,
        ),
      );
    } else if (probe.action == 'wheelInner') {
      final scrollables = find.descendant(
        of: target,
        matching: find.byType(Scrollable),
      );
      final candidates = scrollables
          .evaluate()
          .whereType<StatefulElement>()
          .where(
            (e) =>
                (e.state as ScrollableState).position.axis == Axis.vertical &&
                (e.state as ScrollableState).position.maxScrollExtent > 0 &&
                !_visibleInViewports(e.renderObject! as RenderBox).isEmpty,
          );
      if (candidates.isEmpty) {
        throw StateError('No vertically scrollable tool payload');
      }
      final inner = candidates.last.renderObject! as RenderBox;
      final visible = _visibleInViewports(inner);
      if (visible.isEmpty) {
        throw StateError('Tool payload is outside the viewport');
      }
      GestureBinding.instance.handlePointerEvent(
        PointerScrollEvent(
          position: visible.center,
          scrollDelta: Offset(0, probe.dy),
          kind: PointerDeviceKind.mouse,
        ),
      );
    } else if (probe.action != 'observe') {
      throw ArgumentError.value(probe.action, 'action');
    }
    for (var i = 0; i < (probe.action == 'tap' ? 24 : 2); i++) {
      SchedulerBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      samples.add(sample());
    }
    return _ProbeResult(samples);
  }

  void _removeMouse() {
    final viewId = _mouseViewId;
    if (viewId == null) return;
    GestureBinding.instance.handlePointerEvent(
      PointerRemovedEvent(
        device: _mouseDevice,
        kind: PointerDeviceKind.mouse,
        viewId: viewId,
      ),
    );
    _mouseViewId = null;
  }
}

/// Intersect every enclosing standard viewport, including the bounded activity list.
Rect _visibleInViewports(RenderBox box) {
  var visible = box.localToGlobal(Offset.zero) & box.size;
  RenderObject? ancestor = box.parent;
  while (ancestor != null) {
    if (ancestor is RenderBox && ancestor is RenderAbstractViewport) {
      visible = visible.intersect(
        ancestor.localToGlobal(Offset.zero) & ancestor.size,
      );
    }
    ancestor = ancestor.parent;
  }
  return visible;
}

class _ProbeResult extends Result {
  _ProbeResult(this.samples);
  final List<Object?> samples;
  @override
  Map<String, dynamic> toJson() => {'samples': samples};
}
