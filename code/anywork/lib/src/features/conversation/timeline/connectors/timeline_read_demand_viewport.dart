import 'package:flutter/widgets.dart';

/// Supplies the original timeline owner with the current workspace budget.
class TimelineReadDemandViewport extends StatefulWidget {
  const TimelineReadDemandViewport({
    super.key,
    required this.ownerIdentity,
    required this.onDemand,
    required this.child,
  });
  final Object ownerIdentity;
  final ValueChanged<int> onDemand;
  final Widget child;
  @override
  State<TimelineReadDemandViewport> createState() =>
      _TimelineReadDemandViewportState();
}

class _TimelineReadDemandViewportState
    extends State<TimelineReadDemandViewport> {
  int? _items;
  Object? _owner;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.hasBoundedHeight
          ? constraints.maxHeight
          : MediaQuery.sizeOf(context).height;
      if (height.isFinite && height > 0) {
        final items = (height / 72).ceil();
        if (_items != items || !identical(_owner, widget.ownerIdentity)) {
          _items = items;
          _owner = widget.ownerIdentity;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _items == items &&
                identical(_owner, widget.ownerIdentity)) {
              widget.onDemand(items);
            }
          });
        }
      }
      return widget.child;
    },
  );
}
