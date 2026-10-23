import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart' show CloseReport;

import 'canvas_binding.dart';

/// Independent Smart-layer borrowing surface for one concrete display. It has
/// no Session, canonical writer, shared query close, retire or dispose power.
abstract interface class TimelineDisplayBinding {
  String get threadId;
  int get generation;
  bool get retired;
  /// Actual calls in all scopes already registered to this original display.
  /// Reading this count never opens or replaces a scope.
  int get pendingQueries;
  /// Physical stock Controller operationsStream completion, not retirement.
  bool get isReleased;
  /// Observe only: never starts retirement, cleanup, retries or new queries.
  /// Deadline bounds this observation; original work and its issues remain owned.
  Future<CloseReport> observeRelease({required DateTime deadline});
  int? get appliedVersion;
  TimelineCanvasBinding get canvas;
  StudioTimelineDetailRef? detailFor(String itemId, ThreadContentFieldView field);
  Future<StudioTimelineDetailChunk> readDetail({required String itemId,
    required StudioTimelineDetailQuery query});
  void addRetireListener(void Function() listener);
  void removeRetireListener(void Function() listener);
}
