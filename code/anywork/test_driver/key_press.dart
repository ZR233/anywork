import 'package:flutter_driver/flutter_driver.dart';

enum KeyPressPhase { press, down, up }

/// Dispatches a key through Flutter's focused widget, without OS keyboard input.
///
/// A [shift] chord presses the physical shift key down around the key, which is
/// exactly what the framework's own shortcut matchers observe; the key event
/// itself still travels the real focus/shortcut path.
class KeyPress extends Command {
  KeyPress(
    this.keyId,
    this.usbHidUsage, {
    this.shift = false,
    this.phase = KeyPressPhase.press,
    super.timeout,
  });

  KeyPress.deserialize(super.json)
    : keyId = int.parse(json['keyId']!),
      usbHidUsage = int.parse(json['usbHidUsage']!),
      shift = json['shift'] == 'true',
      phase = KeyPressPhase.values.byName(json['phase']!),
      super.deserialize();

  final int keyId;
  final int usbHidUsage;
  final bool shift;
  final KeyPressPhase phase;

  @override
  String get kind => 'KeyPress';

  @override
  Map<String, String> serialize() => {
    ...super.serialize(),
    'keyId': '$keyId',
    'usbHidUsage': '$usbHidUsage',
    'phase': phase.name,
    if (shift) 'shift': 'true',
  };
}
