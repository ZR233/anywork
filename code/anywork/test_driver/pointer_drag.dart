import 'package:flutter_driver/flutter_driver.dart';

/// Touch drag in the target's actual native view, with observed frame samples.
class PointerDrag extends CommandWithTarget {
  PointerDrag(super.finder, this.dy, {super.timeout});

  PointerDrag.deserialize(super.json, super.finderFactory)
    : dy = double.parse(json['dy']!),
      super.deserialize();

  final double dy;

  @override
  String get kind => 'PointerDrag';

  @override
  Map<String, String> serialize() => {...super.serialize(), 'dy': '$dy'};
}
