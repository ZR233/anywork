import 'package:anywork/src/infrastructure/frb/studio_acp_business_mapper.dart';
import 'package:anywork/src/infrastructure/frb/studio_numeric_converters.dart';
import 'package:anywork/src/infrastructure/frb/studio_workflow_converters.dart';
import 'package:anywork/src/rust/api/studio/types/acp_business.dart' as b;
import 'package:anywork/src/rust/api/studio/types/mode_editor.dart' as me;
import 'package:anywork/src/rust/api/studio/types/thread_stream.dart' as ts;
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

ts.BridgePlanRuntimeSnapshot plan({
  BigInt? revision,
  BigInt? version,
  ts.BridgePlanPhase state = ts.BridgePlanPhase.approved,
  bool hasDocument = true,
  int updatedAt = 1700000002,
}) => ts.BridgePlanRuntimeSnapshot(
  revision: revision ?? BigInt.from(17),
  state: state,
  document: hasDocument
      ? ts.BridgePlanDocument(
          version: version ?? BigInt.from(3),
          markdown: '# Plan\n\n保留正文与换行。',
          contentHash: 'plan-hash',
        )
      : null,
  updatedAt: updatedAt,
);

ts.BridgeWorkflowRun run({
  BigInt? graphRevision,
  ts.BridgeWorkflowRunLifecycle lifecycle =
      ts.BridgeWorkflowRunLifecycle.terminal,
  int startedAt = 1700000000,
  int updatedAt = 1700000001,
  List<String> visitedStateIds = const ['start', 'finish'],
}) => ts.BridgeWorkflowRun(
  lineageId: 'lineage',
  runId: 'run',
  modeId: 'mode',
  graphRevision: graphRevision ?? BigInt.from(23),
  graphHash: 'graph-hash',
  lifecycle: lifecycle,
  currentStateId: 'finish',
  visitedStateIds: visitedStateIds,
  lastTransitionForced: true,
  startedAt: startedAt,
  updatedAt: updatedAt,
  currentStateTitle: 'Finish',
  modeDisplayName: 'Review mode',
  modeDeleted: true,
);

TypeMatcher<StudioFailure> rangeFailure(String correlationId) =>
    isA<StudioFailure>()
        .having((e) => e.code, 'code', StudioFailureCode.overloaded)
        .having((e) => e.retryable, 'retryable', false)
        .having((e) => e.correlationId, 'correlationId', correlationId);

void main() {
  for (final throughAcp in [false, true]) {
    group(throughAcp ? 'ACP workflow state' : 'shared workflow mapper', () {
      PlanRuntimeView mapPlan(ts.BridgePlanRuntimeSnapshot value) => throughAcp
          ? acpWorkflowStateFromFrb(
              b.BridgeAcpWorkflowStateSnapshot(plan: value),
            ).plan!
          : planRuntimeFromFrb(value);
      WorkflowRunView mapRun(ts.BridgeWorkflowRun value) => throughAcp
          ? acpWorkflowStateFromFrb(
              b.BridgeAcpWorkflowStateSnapshot(run: value),
            ).run!
          : workflowRunFromFrb(value);

      test('preserves every plan phase, revision and document content', () {
        const phases = {
          ts.BridgePlanPhase.drafting: PlanRuntimePhase.drafting,
          ts.BridgePlanPhase.awaitingConfirmation:
              PlanRuntimePhase.awaitingConfirmation,
          ts.BridgePlanPhase.revisionRequested:
              PlanRuntimePhase.revisionRequested,
          ts.BridgePlanPhase.approved: PlanRuntimePhase.approved,
        };
        for (final entry in phases.entries) {
          expect(
            mapPlan(plan(state: entry.key)),
            PlanRuntimeView(
              revision: 17,
              state: entry.value,
              document: const PlanDocumentView(
                version: 3,
                markdown: '# Plan\n\n保留正文与换行。',
                contentHash: 'plan-hash',
              ),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000002000),
            ),
          );
        }
        final empty = mapPlan(
          plan(revision: BigInt.zero, hasDocument: false, updatedAt: 0),
        );
        expect(empty.revision, 0);
        expect(empty.document, isNull);
        expect(empty.updatedAt.millisecondsSinceEpoch, 0);
      });

      test(
        'preserves run identity, lifecycle, timestamps and visited states',
        () {
          for (final lifecycle in ts.BridgeWorkflowRunLifecycle.values) {
            final visited = ['start', 'finish'];
            final mapped = mapRun(
              run(lifecycle: lifecycle, visitedStateIds: visited),
            );
            expect(
              (
                mapped.lineageId,
                mapped.runId,
                mapped.modeId,
                mapped.graphRevision,
                mapped.graphHash,
                mapped.currentStateId,
              ),
              ('lineage', 'run', 'mode', 23, 'graph-hash', 'finish'),
            );
            expect(
              mapped.terminal,
              lifecycle == ts.BridgeWorkflowRunLifecycle.terminal,
            );
            expect(mapped.startedAt.millisecondsSinceEpoch, 1700000000000);
            expect(mapped.updatedAt.millisecondsSinceEpoch, 1700000001000);
            expect(mapped.visitedStateIds, ['start', 'finish']);
            expect(mapped.lastTransitionForced, isTrue);
            expect(mapped.currentStateTitle, 'Finish');
            expect(mapped.modeDisplayName, 'Review mode');
            expect(mapped.modeDeleted, isTrue);
            visited.add('later');
            expect(mapped.visitedStateIds, ['start', 'finish']);
            expect(
              () => mapped.visitedStateIds.add('invalid'),
              throwsUnsupportedError,
            );
          }
        },
      );

      test(
        'preserves graph identity, state kinds, instructions and guarded edges',
        () {
          const graph = ts.BridgeWorkflowRuntimeGraphSnapshot(
            modeId: 'mode',
            modeDisplayName: 'Review mode',
            modeDeleted: true,
            initialStateId: 'start',
            states: [
              ts.BridgeWorkflowRuntimeGraphState(
                id: 'start',
                title: 'Start',
                kind: me.BridgeWorkflowStateKind.atomic,
                instructions: 'Read the plan.',
              ),
              ts.BridgeWorkflowRuntimeGraphState(
                id: 'finish',
                title: 'Finish',
                kind: me.BridgeWorkflowStateKind.finalState,
                instructions: 'Record the result.',
              ),
            ],
            edges: [
              ts.BridgeWorkflowRuntimeGraphEdge(
                id: 'next',
                sourceStateId: 'start',
                targetStateId: 'finish',
                guard: 'approved',
              ),
            ],
          );
          final mapped = throughAcp
              ? acpWorkflowStateFromFrb(
                  const b.BridgeAcpWorkflowStateSnapshot(graph: graph),
                ).graph!
              : workflowGraphFromFrb(graph);
          expect(
            mapped,
            const WorkflowRuntimeGraphSnapshotView(
              modeId: 'mode',
              modeDisplayName: 'Review mode',
              modeDeleted: true,
              initialStateId: 'start',
              states: [
                WorkflowRuntimeGraphStateView(
                  id: 'start',
                  title: 'Start',
                  kind: WorkflowStateKind.atomic,
                  instructions: 'Read the plan.',
                ),
                WorkflowRuntimeGraphStateView(
                  id: 'finish',
                  title: 'Finish',
                  kind: WorkflowStateKind.finalState,
                  instructions: 'Record the result.',
                ),
              ],
              edges: [
                WorkflowRuntimeGraphEdgeView(
                  id: 'next',
                  sourceStateId: 'start',
                  targetStateId: 'finish',
                  guard: 'approved',
                ),
              ],
            ),
          );
        },
      );

      for (final field in ['revision', 'version', 'graphRevision']) {
        test(
          'rejects negative or unrepresentable $field without truncation',
          () {
            for (final invalid in [
              -BigInt.one,
              BigInt.one << 63,
              (BigInt.one << 64) - BigInt.one,
            ]) {
              expect(
                () => switch (field) {
                  'revision' => mapPlan(plan(revision: invalid)),
                  'version' => mapPlan(plan(version: invalid)),
                  _ => mapRun(run(graphRevision: invalid)),
                },
                throwsA(
                  rangeFailure('client-timeline-range').having(
                    (e) => e.message,
                    'message',
                    'Timeline state counter cannot be represented exactly',
                  ),
                ),
                reason: '$field=$invalid',
              );
            }
          },
        );
      }

      for (final field in [
        'plan.updatedAt',
        'run.startedAt',
        'run.updatedAt',
      ]) {
        test('rejects overflowing or out-of-DateTime-range $field', () {
          for (final invalid in [
            8640000000001,
            -8640000000001,
            9223372036854775807,
            -9223372036854775808,
          ]) {
            expect(
              () => switch (field) {
                'plan.updatedAt' => mapPlan(plan(updatedAt: invalid)),
                'run.startedAt' => mapRun(run(startedAt: invalid)),
                _ => mapRun(run(updatedAt: invalid)),
              },
              throwsA(rangeFailure('client-timestamp-range')),
              reason: '$field=$invalid',
            );
          }
        });
      }
    });
  }

  test('ACP preserves missing workflow data and outer mode identity', () {
    final mapped = acpWorkflowStateFromFrb(
      const b.BridgeAcpWorkflowStateSnapshot(
        modeId: 'mode',
        modeDisplayName: 'Review',
      ),
    );
    expect(mapped.modeId, 'mode');
    expect(mapped.modeDisplayName, 'Review');
    expect(mapped.plan, isNull);
    expect(mapped.run, isNull);
    expect(mapped.graph, isNull);
  });

  test(
    'timestamp conversion accepts native int and web BigInt without wrapping',
    () {
      for (final seconds in [
        -8640000000000,
        -1,
        0,
        1700000000,
        8640000000000,
      ]) {
        final expected = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        expect(dateFromUnix(seconds), expected);
        expect(dateFromUnix(BigInt.from(seconds)), expected);
      }
      expect(
        () => dateFromUnix(BigInt.one << 64),
        throwsA(rangeFailure('client-timestamp-range')),
      );
      expect(
        () => dateFromUnix('0'),
        throwsA(
          isA<StudioFailure>()
              .having((e) => e.code, 'code', StudioFailureCode.internal)
              .having((e) => e.retryable, 'retryable', false)
              .having(
                (e) => e.correlationId,
                'correlationId',
                'client-timestamp-type',
              ),
        ),
      );
    },
  );
}
