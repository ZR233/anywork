import 'package:anywork_client/models.dart';
import 'package:test/test.dart';

WorkflowRuntimeGraphSnapshotView _autoWorkflowGraph() {
  const states = [
    WorkflowRuntimeGraphStateView(
      id: 'triage',
      title: '任务分流',
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'simple',
      title: '简洁处理',
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'planning',
      title: '规划',
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'editing_documents',
      title: '编辑文档',
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'working',
      title: '实现',
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'integrating',
      title: '集成',
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'reviewing',
      title: '验收',
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'completed',
      title: '已完成',
      kind: WorkflowStateKind.finalState,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'stopped',
      title: '已中止',
      kind: WorkflowStateKind.finalState,
    ),
  ];
  const edges = [
    WorkflowRuntimeGraphEdgeView(
      id: 'e1',
      sourceStateId: 'triage',
      targetStateId: 'simple',
      guard: '简单明确任务',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e2',
      sourceStateId: 'triage',
      targetStateId: 'planning',
      guard: '复杂工程任务',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e3',
      sourceStateId: 'simple',
      targetStateId: 'planning',
      guard: '复杂度超出预期，转入规划',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e4',
      sourceStateId: 'simple',
      targetStateId: 'completed',
      guard: '简单处理完成',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e5',
      sourceStateId: 'planning',
      targetStateId: 'editing_documents',
      guard: '需要修改设计文档',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e6',
      sourceStateId: 'planning',
      targetStateId: 'working',
      guard: '无需修改文档，直接施工',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e7',
      sourceStateId: 'editing_documents',
      targetStateId: 'working',
      guard: '文档更新完毕',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e8',
      sourceStateId: 'working',
      targetStateId: 'integrating',
      guard: '施工完成，进入集成',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e9',
      sourceStateId: 'integrating',
      targetStateId: 'reviewing',
      guard: '集成完毕，进入验收',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e10',
      sourceStateId: 'reviewing',
      targetStateId: 'completed',
      guard: '验收通过',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e11',
      sourceStateId: 'reviewing',
      targetStateId: 'working',
      guard: '验收返工',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'e12',
      sourceStateId: 'reviewing',
      targetStateId: 'stopped',
      guard: '终止',
    ),
  ];
  return const WorkflowRuntimeGraphSnapshotView(
    modeId: 'mode.auto',
    modeDisplayName: '自动',
    modeDeleted: false,
    initialStateId: 'triage',
    states: states,
    edges: edges,
  );
}

void main() {
  test(
    'vertical layout computes top-to-bottom depths and centers siblings',
    () {
      final graph = _autoWorkflowGraph();
      final depths = computeVerticalWorkflowDepths(graph);
      expect(depths['triage'], 0);
      expect(depths['simple'], 1);
      expect(depths['planning'], 1);
      expect(depths['editing_documents'], 2);
      expect(depths['working'], 2);
      expect(depths['integrating'], 3);
      expect(depths['reviewing'], 4);
      expect(depths['completed'], 5);
      expect(depths['stopped'], 5);

      final offsets = verticalAutoLayoutOffsets(graph);
      expect(offsets.length, 9);
      expect(offsets['triage']!.y, lessThan(offsets['simple']!.y));
      expect(offsets['simple']!.y, offsets['planning']!.y);
      expect(offsets['simple']!.x, lessThan(offsets['planning']!.x));
      expect(offsets['completed']!.y, offsets['stopped']!.y);
      expect(offsets['completed']!.y, greaterThan(offsets['reviewing']!.y));

      final finalIds = {'completed', 'stopped'};
      final reworkEdge = graph.edges.firstWhere((e) => e.id == 'e11');
      final escalationEdge = graph.edges.firstWhere((e) => e.id == 'e3');
      final terminalEdge = graph.edges.firstWhere((e) => e.id == 'e10');
      expect(isBackwardWorkflowEdge(reworkEdge, depths, finalIds), isTrue);
      expect(isBackwardWorkflowEdge(escalationEdge, depths, finalIds), isTrue);
      expect(isBackwardWorkflowEdge(terminalEdge, depths, finalIds), isFalse);
    },
  );
}
