import 'package:anywork_client/conversation_ports.dart'
    show ConversationCommandPort;
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import 'conversation_fixture.dart';
import 'drafts_workspace_fixture.dart';
import 'profile_recovery_port.dart';
import 'thread_metadata_fixture.dart';
import 'timeline_transport.dart';

/// Real selection, operations, Recovery and Conversation owners. Only native
/// directory materials and facet/Timeline transports are supplied by fixtures.
final class WorkspaceSelectionFixture {
  WorkspaceSelectionFixture({ConversationCommandPort? commands}) {
    conversations = ConversationFixture(
      budget: budget,
      commands: commands,
      agentDirectory: () => workspace.agents,
    );
    recovery = createRecoveryRepository(
      port: recoveryPort,
      budget: budget,
      operations: conversations.operations,
    );
    workspace = createWorkspaceRepository(
      port: directory,
      budget: budget,
      operations: conversations.operations,
      recovery: recovery.state,
      archiveCapture: conversations.archive,
    ).repository;
  }

  final budget = ResourceBudget();
  final directory = DraftWorkspacePort();
  final recoveryPort = ProfileRecoveryPort();
  late final ConversationFixture conversations;
  late final RecoveryRepository recovery;
  late final WorkspaceRepository workspace;

  Future<void> establishAccess() async {
    await recoveryPort.establish(recovery);
    await recovery.loadSourceStatus();
  }

  Future<CloseReport> close() async {
    workspace.seal();
    conversations.repository.seal();
    recovery.seal();
    directory.native.releasePending();
    for (final material in directory.materials.values) {
      final entity = material.entityReply;
      if (entity != null && !entity.isCompleted)
        entity.complete(
          ThreadDirectoryEntityRead(
            reference: const ProductEntityRef(entry: 5, revision: 1),
            value: draftThreadRead(material.record),
          ),
        );
      final closing = material.closeReply;
      if (closing != null && !closing.isCompleted)
        closing.complete(
          FeedCloseReport(
            feedId: 'selection-material-cleanup',
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
    }
    for (final owner
        in conversations.context.metadataOwners
            .whereType<ScriptedThreadMetadata>()) {
      owner.releasePending();
    }
    for (final opening in conversations.timeline.requests) {
      if (!opening.result.isCompleted)
        opening.result.complete(TestTimelineConnection(initial: baseline(1)));
    }
    final reports = await Future.wait([
      workspace.close(),
      conversations.repository.close(),
      recovery.close(),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}
