import 'package:flutter_driver/flutter_driver.dart';

/// Pointer drag in the target's actual native view, with observed frame samples.
///
/// The drag is a straight line from the widget centre along ([dx], [dy]); the
/// vertical case is the historical one and keeps its default [dy]-only shape.
class PointerDrag extends CommandWithTarget {
  PointerDrag(super.finder, this.dy, {this.dx = 0, super.timeout});

  PointerDrag.deserialize(super.json, super.finderFactory)
    : dy = double.parse(json['dy']!),
      dx = double.parse(json['dx'] ?? '0'),
      super.deserialize();

  final double dy;
  final double dx;

  @override
  String get kind => 'PointerDrag';

  @override
  Map<String, String> serialize() => {
    ...super.serialize(),
    'dy': '$dy',
    'dx': '$dx',
  };
}
