import 'package:flutter_driver/flutter_driver.dart';

/// Moves a real test mouse over a widget without pressing a button.
class PointerHover extends CommandWithTarget {
  PointerHover(super.finder, {super.timeout});
  PointerHover.deserialize(super.json, super.finderFactory)
    : super.deserialize();

  @override
  String get kind => 'PointerHover';
}
