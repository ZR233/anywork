import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

Iterable<ReadText> activityHeaderTexts(ActivityReadHeader value) sync* {
  yield value.threadId; yield value.identity; yield value.turnId; yield value.summary;
  if (value.inputId != null) yield value.inputId!;
  if (value.attemptId != null) yield value.attemptId!;
  final tool = value.latestStarted;
  if (tool != null) {
    yield tool.callId; yield tool.name; yield tool.summary;
    if (tool.taskId != null) yield tool.taskId!;
  }
}

Iterable<ReadText> activityToolTexts(IndexedActivityToolReadItem value) sync* {
  yield value.callId; yield value.name; yield value.summary;
  if (value.taskId != null) yield value.taskId!;
}

Iterable<ReadText> configurationHeaderTexts(ThreadConfigurationReadHeader value) sync* {
  final route = value.route;
  if (route == null) return;
  yield route.accountId; yield route.modelId;
  if (route.effort != null) yield route.effort!;
  if (route.unavailableReason != null) yield route.unavailableReason!;
}

Iterable<ReadText> workflowHeaderTexts(WorkflowReadHeader value) sync* {
  final run = value.currentRun;
  if (run == null) return;
  yield run.lineageId; yield run.runId; yield run.modeId; yield run.graphHash;
  yield run.currentStateId; yield run.currentStateTitle; yield run.modeDisplayName;
}

Iterable<ReadText> turnHeaderTexts(TurnReadHeader value) sync* {
  yield value.id; yield value.threadId;
  if (value.inputId != null) yield value.inputId!;
  switch (value.state) {
    case CancelledTurnRead(cause: CoalescedTurnReadCancellation(:final targetTurnId)):
      yield targetTurnId;
    case FailedTurnRead(:final failure):
      if (failure.code != null) yield failure.code!;
      yield failure.message;
    case BudgetLimitedTurnRead(rollover: TurnReadRolloverFailed(:final error)):
      yield error;
    case QueuedTurnRead() || RunningTurnRead() || CompletedTurnRead() ||
        CancelledTurnRead() || BudgetLimitedTurnRead(): break;
  }
}
