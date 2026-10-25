import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'execution_values.dart';

part 'activity_read_values.freezed.dart';

enum ThreadActivityArgumentsKind { commandLine, opaque, streaming, unavailable }

enum ThreadActivityToolState { running, awaitingApproval, cancelling, finished }

enum ThreadWaitState {
  waiting,
  ready,
  timedOut,
  elapsed,
  cancelled,
  failed,
  interrupted,
}

enum ThreadWaitTargetStatus {
  running,
  succeeded,
  failed,
  cancelled,
  interrupted,
}

@freezed
sealed class WaitReadIntent with _$WaitReadIntent {
  const factory WaitReadIntent.events({
    required int targetCount,
    required int timeoutMs,
  }) = EventsWaitReadIntent;
  const factory WaitReadIntent.timer({required int durationMs}) =
      TimerWaitReadIntent;
}

@freezed
abstract class WaitReadValue with _$WaitReadValue {
  const factory WaitReadValue({
    required WaitReadIntent intent,
    required ThreadWaitState state,
    required bool? messagesReady,
  }) = _WaitReadValue;
}

@Freezed(toStringOverride: false)
abstract class WaitTargetReadItem with _$WaitTargetReadItem {
  const factory WaitTargetReadItem({
    required int index,
    required ReadText taskId,
    required ReadText? toolName,
    required ReadText? summary,
    required bool summaryTruncated,
    required ThreadWaitTargetStatus? status,
  }) = _WaitTargetReadItem;
}

@Freezed(toStringOverride: false)
final class WaitTargetPage with _$WaitTargetPage {
  WaitTargetPage({
    required this.scope,
    required this.offset,
    required this.total,
    required List<WaitTargetReadItem> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final ReadScopeIdentity scope;
  final int offset;
  final int total;
  final List<WaitTargetReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
abstract class ActivityToolReadItem with _$ActivityToolReadItem {
  const factory ActivityToolReadItem({
    required ReadText callId,
    required ReadText? taskId,
    required ReadText name,
    required ReadText summary,
    required ThreadActivityArgumentsKind arguments,
    required ThreadActivityToolState state,
    required int? ordinal,
    required int? startedAt,
    required WaitReadValue? wait,
  }) = _ActivityToolReadItem;
}

/// The tools list owns an index; latestStarted deliberately has no such index.
@Freezed(toStringOverride: false)
abstract class IndexedActivityToolReadItem with _$IndexedActivityToolReadItem {
  const factory IndexedActivityToolReadItem({
    required int index,
    required ReadText callId,
    required ReadText? taskId,
    required ReadText name,
    required ReadText summary,
    required ThreadActivityArgumentsKind arguments,
    required ThreadActivityToolState state,
    required int? ordinal,
    required int? startedAt,
    required WaitReadValue? wait,
  }) = _IndexedActivityToolReadItem;
}

@Freezed(toStringOverride: false)
final class ActivityToolPage with _$ActivityToolPage {
  ActivityToolPage({
    required this.scope,
    required this.offset,
    required this.total,
    required List<IndexedActivityToolReadItem> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final ReadScopeIdentity scope;
  final int offset;
  final int total;
  final List<IndexedActivityToolReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
abstract class ActivityReadHeader with _$ActivityReadHeader {
  const factory ActivityReadHeader({
    required ReadScopeIdentity scope,
    required ReadText threadId,
    required ReadText identity,
    required ReadText turnId,
    required int revision,
    required ReadText? inputId,
    required ReadText? attemptId,
    required ThreadActivityKind kind,
    required ReadText summary,
    required bool summaryTruncated,
    required int count,
    required int background,
    required int activeCount,
    required ActivityToolReadItem? latestStarted,
  }) = _ActivityReadHeader;
}
