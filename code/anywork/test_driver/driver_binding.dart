import 'dart:convert';

import 'driver_inspection.dart';

/// Driver extensions share the exact AppGraph supplied to the real root.
/// This binding owns no product state and is absent from release entrypoints.
DriverInspection? driverInspection;

String captureDriverJson() =>
    driverInspection?.snapshotJson() ??
    jsonEncode({
      // The independent native layout gate intentionally has no product graph.
      'availability': {'application': 'unbound'},
      'timeline': null,
      'timelineScroll': null,
    });
