import 'dart:async';

import 'package:flutter/widgets.dart';

/// Smart lifecycle binding for an actually mounted detail overlay, not a query
/// in View.build or a MouseRegion that loses demand when entering the popup.
class ReadDemandMount extends StatefulWidget {
  const ReadDemandMount({required this.identity, required this.begin,
    required this.child, super.key});
  final Object identity;
  final void Function() Function() begin;
  final Widget child;
  @override
  State<ReadDemandMount> createState() => _ReadDemandMountState();
}
class _ReadDemandMountState extends State<ReadDemandMount> {
  void Function()? _end;
  int _generation = 0;
  @override
  void initState() { super.initState(); _attach(); }
  void _attach() {
    final generation = ++_generation;
    scheduleMicrotask(() {
      if (mounted && _generation == generation) _end = widget.begin();
    });
  }
  @override
  void didUpdateWidget(covariant ReadDemandMount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      final end = _end; _end = null;
      scheduleMicrotask(() => end?.call());
      _attach();
    }
  }
  @override
  void dispose() {
    _generation++;
    final end = _end; _end = null;
    scheduleMicrotask(() => end?.call());
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => widget.child;
}
