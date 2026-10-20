import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'key_press.dart';

class KeyPressCommandExtension extends CommandExtension {
  @override
  String get commandKind => 'KeyPress';

  @override
  Command deserialize(
    Map<String, String> params,
    DeserializeFinderFactory finderFactory,
    DeserializeCommandFactory commandFactory,
  ) => KeyPress.deserialize(params);

  @override
  Future<Result> call(
    Command command,
    WidgetController prober,
    CreateFinderFactory finderFactory,
    CommandHandlerFactory handlerFactory,
  ) async {
    final press = command as KeyPress;
    // Profile builds strip debug names, so the simulator cannot infer the
    // physical key from LogicalKeyboardKey.debugName.
    if (press.shift && press.phase != KeyPressPhase.up) {
      await prober.sendKeyDownEvent(
        LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft,
      );
    }
    try {
      final key = LogicalKeyboardKey(press.keyId);
      final physical = PhysicalKeyboardKey(press.usbHidUsage);
      switch (press.phase) {
        case KeyPressPhase.press:
          await prober.sendKeyEvent(key, physicalKey: physical);
        case KeyPressPhase.down:
          await prober.sendKeyDownEvent(key, physicalKey: physical);
        case KeyPressPhase.up:
          await prober.sendKeyUpEvent(key, physicalKey: physical);
      }
    } finally {
      if (press.shift && press.phase != KeyPressPhase.down) {
        await prober.sendKeyUpEvent(
          LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
        );
      }
    }
    return Result.empty;
  }
}
