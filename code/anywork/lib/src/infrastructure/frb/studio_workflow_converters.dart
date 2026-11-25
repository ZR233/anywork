import 'package:anywork_client/models.dart' as models;

import '../../rust/api/studio/types/mode_editor.dart' as me;
import '../../rust/api/studio/types/thread_stream.dart' as ts;
import 'studio_numeric_converters.dart';

models.WorkflowRunView workflowRunFromFrb(ts.BridgeWorkflowRun run) {
  return models.WorkflowRunView(
    lineageId: run.lineageId,
    runId: run.runId,
    modeId: run.modeId,
    graphRevision: exactTimelineInt(run.graphRevision, 'state counter'),
    graphHash: run.graphHash,
    currentStateId: run.currentStateId,
    terminal: run.lifecycle == ts.BridgeWorkflowRunLifecycle.terminal,
    startedAt: dateFromUnix(run.startedAt),
    updatedAt: dateFromUnix(run.updatedAt),
    visitedStateIds: List<String>.unmodifiable(run.visitedStateIds),
    lastTransitionForced: run.lastTransitionForced,
    currentStateTitle: run.currentStateTitle,
    modeDisplayName: run.modeDisplayName,
    modeDeleted: run.modeDeleted,
  );
}

models.WorkflowRuntimeGraphSnapshotView workflowGraphFromFrb(
  ts.BridgeWorkflowRuntimeGraphSnapshot graph,
) {
  return models.WorkflowRuntimeGraphSnapshotView(
    modeId: graph.modeId,
    modeDisplayName: graph.modeDisplayName,
    modeDeleted: graph.modeDeleted,
    initialStateId: graph.initialStateId,
    states: [
      for (final s in graph.states)
        models.WorkflowRuntimeGraphStateView(
          id: s.id,
          title: s.title,
          kind: switch (s.kind) {
            me.BridgeWorkflowStateKind.atomic =>
              models.WorkflowStateKind.atomic,
            me.BridgeWorkflowStateKind.finalState =>
              models.WorkflowStateKind.finalState,
          },
          instructions: s.instructions,
        ),
    ],
    edges: [
      for (final e in graph.edges)
        models.WorkflowRuntimeGraphEdgeView(
          id: e.id,
          sourceStateId: e.sourceStateId,
          targetStateId: e.targetStateId,
          guard: e.guard,
        ),
    ],
  );
}

models.PlanRuntimeView planRuntimeFromFrb(ts.BridgePlanRuntimeSnapshot value) {
  final document = value.document;
  return models.PlanRuntimeView(
    revision: exactTimelineInt(value.revision, 'state counter'),
    state: switch (value.state) {
      ts.BridgePlanPhase.drafting => models.PlanRuntimePhase.drafting,
      ts.BridgePlanPhase.awaitingConfirmation =>
        models.PlanRuntimePhase.awaitingConfirmation,
      ts.BridgePlanPhase.revisionRequested =>
        models.PlanRuntimePhase.revisionRequested,
      ts.BridgePlanPhase.approved => models.PlanRuntimePhase.approved,
    },
    document: document == null
        ? null
        : models.PlanDocumentView(
            version: exactTimelineInt(document.version, 'state counter'),
            markdown: document.markdown,
            contentHash: document.contentHash,
          ),
    updatedAt: dateFromUnix(value.updatedAt),
  );
}
