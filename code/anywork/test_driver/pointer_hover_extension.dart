import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pointer_hover.dart';

class PointerHoverCommandExtension extends CommandExtension {
  TestGesture? _mouse;

  @override
  String get commandKind => 'PointerHover';

  @override
  Command deserialize(
    Map<String, String> params,
    DeserializeFinderFactory finderFactory,
    DeserializeCommandFactory commandFactory,
  ) => PointerHover.deserialize(params, finderFactory);

  @override
  Future<Result> call(
    Command command,
    WidgetController prober,
    CreateFinderFactory finderFactory,
    CommandHandlerFactory handlerFactory,
  ) async {
    final finder = finderFactory.createFinder((command as PointerHover).finder);
    final element = finder.evaluate().single;
    final box = element.renderObject! as RenderBox;
    final position = box.localToGlobal(box.size.center(Offset.zero));
    final view = View.of(element);
    var mouse = _mouse;
    if (mouse == null) {
      mouse = await prober.createGesture(kind: PointerDeviceKind.mouse);
      _mouse = mouse;
      await mouse.addPointer(location: position);
    }
    await mouse.moveTo(position, view: view);
    return Result.empty;
  }
}
