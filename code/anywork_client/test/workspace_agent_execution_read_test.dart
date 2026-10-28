import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:test/test.dart';

import 'support/workspace_agent_fixture.dart';

void main() {
  test('preparing execution identity and scheduling facts cross the actual AgentDirectory read/materialization owner', () async {
    final fixture = WorkspaceAgentFixture();
    addTearDown(() async {
      await fixture.close();
    });
    await fixture.establish();
    final mirror =
        fixture.workspace.agents.value.agents
            as CurrentCollectionMirror<AgentDirectoryEntry>;
    final root =
        (mirror.window.rows[3]
                as ReadyReadValue<AgentDirectoryEntry, ProductEntityRef>)
            .current
            .value;
    final child =
        (mirror.window.rows[4]
                as ReadyReadValue<AgentDirectoryEntry, ProductEntityRef>)
            .current
            .value;
    expect(root.execution, agentPreparingExecution);
    expect(root.execution!.turnId, isNull);
    expect((root.canStop, root.awaitingScheduling), (true, false));
    expect(
      (child.execution, child.canStop, child.awaitingScheduling),
      (null, false, true),
    );
    expect(fixture.pins, hasLength(1));
    expect(
      fixture.selection.conversations.repository.existingSession('root'),
      isNull,
    );
    expect(fixture.selection.conversations.facets.execution, isEmpty);
    expect((await fixture.close()).complete, isTrue);
    expect(fixture.pins.single.closed, isTrue);
    expect(fixture.budget.usage, isEmpty);
  });
}
