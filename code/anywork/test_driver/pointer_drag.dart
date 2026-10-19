import 'package:flutter_driver/flutter_driver.dart';

enum PointerDragKind { touch, mouse }

/// Pointer drag in the target's actual native view, with observed frame samples.
///
/// The drag follows a straight line from the widget centre along ([dx], [dy]).
/// [pointerKind] selects native mouse or touch events.
class PointerDrag extends CommandWithTarget {
  PointerDrag(
    super.finder,
    this.dy, {
    this.dx = 0,
    this.pointerKind = PointerDragKind.touch,
    super.timeout,
  });

  PointerDrag.deserialize(super.json, super.finderFactory)
    : dy = double.parse(json['dy']!),
      dx = double.parse(json['dx'] ?? '0'),
      pointerKind = PointerDragKind.values.byName(
        json['pointerKind'] ?? 'touch',
      ),
      super.deserialize();

  final double dy;
  final double dx;
  final PointerDragKind pointerKind;

  @override
  String get kind => 'PointerDrag';

  @override
  Map<String, String> serialize() => {
    ...super.serialize(),
    'dy': '$dy',
    'dx': '$dx',
    'pointerKind': pointerKind.name,
  };
}
