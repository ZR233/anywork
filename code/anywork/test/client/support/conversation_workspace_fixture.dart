import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/profile_recovery_port.dart';
import '../../../../anywork_client/test/support/workspace_port_fixture.dart';

/// The actual Workspace/Recovery owners for otherwise narrow Conversation
/// assemblies. This is deliberately not an empty AgentDirectory substitute.
final class ConversationWorkspaceFixture {
  ConversationWorkspaceFixture({
    required ResourceBudget budget,
    required OperationRecorder operations,
    required WorkspaceArchiveCapturePort archive,
  }) {
    recovery = createRecoveryRepository(
      port: recoveryPort,
      budget: budget,
      operations: operations,
    );
    workspace = createWorkspaceRepository(
      port: port,
      budget: budget,
      operations: operations,
      recovery: recovery.state,
      archiveCapture: archive,
    ).repository;
  }

  final port = ScriptedWorkspacePort();
  final recoveryPort = ProfileRecoveryPort();
  late final RecoveryRepository recovery;
  late final WorkspaceRepository workspace;

  Future<void> close() async {
    port.releasePending();
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final reports = await Future.wait([
      workspace.close(deadline: deadline),
      recovery.close(deadline: deadline),
    ]);
    expectSync([for (final report in reports) ...report.unresolved], isEmpty);
  }
}
