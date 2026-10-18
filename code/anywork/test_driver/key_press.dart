import 'package:flutter_driver/flutter_driver.dart';

/// Dispatches a key through Flutter's focused widget, without OS keyboard input.
///
/// A [shift] chord presses the physical shift key down around the key, which is
/// exactly what the framework's own shortcut matchers observe; the key event
/// itself still travels the real focus/shortcut path.
class KeyPress extends Command {
  KeyPress(this.keyId, this.usbHidUsage, {this.shift = false, super.timeout});

  KeyPress.deserialize(super.json)
    : keyId = int.parse(json['keyId']!),
      usbHidUsage = int.parse(json['usbHidUsage']!),
      shift = json['shift'] == 'true',
      super.deserialize();

  final int keyId;
  final int usbHidUsage;
  final bool shift;

  @override
  String get kind => 'KeyPress';

  @override
  Map<String, String> serialize() => {
    ...super.serialize(),
    'keyId': '$keyId',
    'usbHidUsage': '$usbHidUsage',
    if (shift) 'shift': 'true',
  };
}
