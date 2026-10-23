import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../resources.dart';
import 'timeline_models.dart';

part 'conversation_timeline.freezed.dart';

enum TimelineConnectionPhase { idle, opening, ready, reconnecting, failed, closed }

@Freezed(toStringOverride: false)
abstract class TimelineConnectionState with _$TimelineConnectionState {
  const factory TimelineConnectionState({required String threadId,
    required TimelineConnectionPhase phase, AttemptId? attemptId,
    ViewStamp? lastStamp, StudioFailure? error, @Default(false) bool retryExhausted}) = _TimelineConnectionState;
}

typedef TimelineFrameConsumer = FutureOr<void> Function(StudioTimelineFrame frame);

abstract interface class TimelineConsumerLease {
  bool get isClosed;
  void requestClose();
  Future<void> close();
}

abstract interface class ConversationTimeline {
  ReadonlyLatestValue<TimelineConnectionState> get state;
  TimelineLifecycleRead get lifecycle;
  Future<StudioTimelineBaselineFrame> get ready;
  TimelineConsumerLease attachConsumer(TimelineFrameConsumer consume);
  StudioTimelineQueryScope? openScope({required int generation});
  void refresh();
}

/// A runtime read-only borrow of the original Timeline's registered attempts.
abstract interface class TimelineLifecycleRead {
  int get ownedAttemptCount;
  Future<CloseReport> observeRetired({required DateTime deadline});
}

abstract interface class StudioTimelineQueryScope {
  int get generation;
  AttemptId get attemptId;
  String get threadId;
  int get pendingQueries;
  bool get isActive;
  Future<StudioTimelinePage> page({String? before, int? limit});
  Future<StudioTimelineDetailChunk> readDetail({required String itemId,
    required StudioTimelineDetailQuery query});
  void retire();
  Future<CloseReport> close({DateTime? deadline});
}

const timelinePageDefaultLimit = 32;
const timelinePageMaxLimit = 100;
const timelineDetailMinBytes = 4;
const timelineDetailMaxBytes = 256 * 1024;
