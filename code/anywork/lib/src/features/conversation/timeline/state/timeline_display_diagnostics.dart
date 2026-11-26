import 'package:anywork_client/models.dart';

/// Synchronous borrow of an expanded work group and the members it displays.
abstract interface class TimelineGroupDisplay {
  String get unitId;
  bool get isCurrent;
  bool get loading;
  Object? get error;
  TimelineWorkGroup? get group;
  Iterable<WorkGroupMember> get members;
}

/// Actual content layout measured on the selection owner's monotonic clock.
final class TimelineContentLayout {
  const TimelineContentLayout({
    required this.selectionId,
    required this.generation,
    required this.itemId,
    required this.selectionStartedMicros,
    required this.layoutCompletedMicros,
  });

  final int selectionId;
  final int generation;
  final String itemId;
  final int selectionStartedMicros;
  final int layoutCompletedMicros;
  int get elapsedMicros => layoutCompletedMicros - selectionStartedMicros;
}
