import 'package:freezed_annotation/freezed_annotation.dart';

import 'configuration_values.dart';
import 'thread_identity.dart';

part 'authoring_values.freezed.dart';

enum PlanPhase { drafting, awaitingConfirmation, revisionRequested, approved }

enum WorkflowLifecycle { active, terminal }

enum TodoItemStatus { pending, inProgress, completed }

@freezed
abstract class TodoBrief with _$TodoBrief {
  const factory TodoBrief({
    required TodoReadRef reference,
    required int itemCount,
    required bool hasCallId,
  }) = _TodoBrief;
}

@freezed
abstract class PlanDocumentRef with _$PlanDocumentRef {
  const factory PlanDocumentRef({
    required int version,
    required String contentHash,
  }) = _PlanDocumentRef;
}

@freezed
abstract class PlanBrief with _$PlanBrief {
  const factory PlanBrief({
    required int revision,
    required PlanPhase state,
    required PlanDocumentRef? document,
    required int updatedAt,
  }) = _PlanBrief;
}

@freezed
abstract class WorkflowBrief with _$WorkflowBrief {
  const factory WorkflowBrief({
    required WorkflowReadRef reference,
    required int revision,
    required bool hasCurrentRun,
    required WorkflowLifecycle? lifecycle,
    required bool? modeDeleted,
  }) = _WorkflowBrief;
}

@freezed
abstract class ThreadAuthoringBaseline with _$ThreadAuthoringBaseline {
  const factory ThreadAuthoringBaseline({
    required TodoBrief? todo,
    required PlanBrief? plan,
    required WorkflowBrief? workflow,
    required ThreadCapabilitySupport progress,
  }) = _ThreadAuthoringBaseline;
}

@freezed
sealed class TodoReplacement with _$TodoReplacement {
  const factory TodoReplacement.unchanged() = UnchangedTodo;
  const factory TodoReplacement.replace({required TodoBrief? value}) =
      ReplacedTodo;
}

@freezed
sealed class PlanReplacement with _$PlanReplacement {
  const factory PlanReplacement.unchanged() = UnchangedPlan;
  const factory PlanReplacement.replace({required PlanBrief? value}) =
      ReplacedPlan;
}

@freezed
sealed class WorkflowReplacement with _$WorkflowReplacement {
  const factory WorkflowReplacement.unchanged() = UnchangedWorkflow;
  const factory WorkflowReplacement.replace({required WorkflowBrief? value}) =
      ReplacedWorkflow;
}

@freezed
abstract class ThreadAuthoringChange with _$ThreadAuthoringChange {
  const factory ThreadAuthoringChange({
    required TodoReplacement todo,
    required PlanReplacement plan,
    required WorkflowReplacement workflow,
  }) = _ThreadAuthoringChange;
}
