import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/conversation/authoring.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import 'identity_converters.dart';
import 'scalar_converters.dart';

ThreadAuthoringFrame authoringFrameFromBridge(native.BridgeAuthoringFrame value) => switch (value) {
  native.BridgeAuthoringFrame_Data(:final deliverySequence, :final event) =>
    ThreadAuthoringFrame.data(deliverySequence: exactU64(deliverySequence, 'authoring delivery sequence'), event: switch (event) {
      native.BridgeAuthoringEvent_Baseline(:final identity, :final stamp, :final value) =>
        ThreadAuthoringEvent.baseline(identity: feedIdentityFromBridge(identity), stamp: facetStampFromBridge(stamp), value: authoringBaselineFromBridge(value)),
      native.BridgeAuthoringEvent_Change(:final stamp, :final baseRevision, :final value) =>
        ThreadAuthoringEvent.change(stamp: facetStampFromBridge(stamp), baseRevision: exactU64(baseRevision, 'authoring base revision'), value: authoringChangeFromBridge(value)),
    }),
  native.BridgeAuthoringFrame_ResyncRequired(:final identity, :final reason) =>
    ThreadAuthoringFrame.resyncRequired(identity: feedIdentityFromBridge(identity), reason: resyncReasonFromBridge(reason)),
  native.BridgeAuthoringFrame_Failure(:final identity, :final error) =>
    ThreadAuthoringFrame.failure(identity: feedIdentityFromBridge(identity), error: bridgeFailure(error)),
  native.BridgeAuthoringFrame_Closed(:final identity, :final reason) =>
    ThreadAuthoringFrame.closed(identity: feedIdentityFromBridge(identity), reason: closedReasonFromBridge(reason)),
};

TodoBrief todoBriefFromBridge(native.BridgeTodoBrief value) => TodoBrief(
  reference: todoRefFromBridge(value.reference),
  itemCount: exactU64(value.itemCount, 'Todo item count'),
  hasCallId: value.hasCallId,
);

PlanDocumentRef planDocumentRefFromBridge(native.BridgePlanDocumentRef value) => PlanDocumentRef(
  version: exactU64(value.version, 'Plan document version'), contentHash: value.contentHash,
);

PlanBrief planBriefFromBridge(native.BridgePlanBrief value) => PlanBrief(
  revision: exactU64(value.revision, 'Plan revision'),
  state: planPhaseFromBridge(value.state),
  document: value.document == null ? null : planDocumentRefFromBridge(value.document!),
  updatedAt: exactI64(value.updatedAt, 'Plan updated Unix seconds'),
);

WorkflowBrief workflowBriefFromBridge(native.BridgeWorkflowBrief value) => WorkflowBrief(
  reference: workflowRefFromBridge(value.reference),
  revision: exactU64(value.revision, 'workflow revision'),
  hasCurrentRun: value.hasCurrentRun,
  lifecycle: value.lifecycle == null ? null : workflowLifecycleFromBridge(value.lifecycle!),
  modeDeleted: value.modeDeleted,
);

ThreadAuthoringBaseline authoringBaselineFromBridge(native.BridgeAuthoringBaseline value) => ThreadAuthoringBaseline(
  todo: value.todo == null ? null : todoBriefFromBridge(value.todo!),
  plan: value.plan == null ? null : planBriefFromBridge(value.plan!),
  workflow: value.workflow == null ? null : workflowBriefFromBridge(value.workflow!),
  progress: capabilityFromBridge(value.progress),
);

ThreadAuthoringChange authoringChangeFromBridge(native.BridgeAuthoringChange value) => ThreadAuthoringChange(
  todo: switch (value.todo) {
    native.BridgeTodoReplacement_Unchanged() => const TodoReplacement.unchanged(),
    native.BridgeTodoReplacement_Replace(:final value) => TodoReplacement.replace(value: value == null ? null : todoBriefFromBridge(value)),
  },
  plan: switch (value.plan) {
    native.BridgePlanReplacement_Unchanged() => const PlanReplacement.unchanged(),
    native.BridgePlanReplacement_Replace(:final value) => PlanReplacement.replace(value: value == null ? null : planBriefFromBridge(value)),
  },
  workflow: switch (value.workflow) {
    native.BridgeWorkflowReplacement_Unchanged() => const WorkflowReplacement.unchanged(),
    native.BridgeWorkflowReplacement_Replace(:final value) => WorkflowReplacement.replace(value: value == null ? null : workflowBriefFromBridge(value)),
  },
);
