import 'package:anywork/src/app/composition/workspace_conversation_binding.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../../anywork_client/test/support/profile_recovery_port.dart';
import '../../../../anywork_client/test/support/thread_metadata_fixture.dart';
import '../../../../anywork_client/test/support/timeline_transport.dart';
import '../../../../anywork_client/test/support/workspace_port_fixture.dart';

typedef SelectionDelivery = ({
  String? threadId,
  bool needsOpen,
  int selectionGeneration,
});

SelectionDelivery selectionDelivery(WorkspaceState value) => (
  threadId: value.selection.threadId,
  needsOpen: value.selection.needsOpen,
  selectionGeneration: value.selectionGeneration,
);

/// Records only the actual boundary arguments and observer admission evidence,
/// then forwards every capability unchanged to the real Conversation demand.
/// No current selection, retry, reducer or alternate source is implemented.
final class RecordingConversationDemand implements ConversationDemand {
  RecordingConversationDemand(this.delegate, this.observerCount);
  final ConversationDemand delegate;
  final int Function() observerCount;
  final calls = <SelectionDelivery>[];
  final observerCounts = <int>[];
  @override
  void select({
    required String? threadId,
    required bool needsOpen,
    required int selectionGeneration,
  }) {
    calls.add((
      threadId: threadId,
      needsOpen: needsOpen,
      selectionGeneration: selectionGeneration,
    ));
    observerCounts.add(observerCount());
    delegate.select(
      threadId: threadId,
      needsOpen: needsOpen,
      selectionGeneration: selectionGeneration,
    );
  }

  @override
  Future<CloseReport> retire(String threadId, {DateTime? deadline}) =>
      delegate.retire(threadId, deadline: deadline);
  @override
  void retrySelected(String threadId) => delegate.retrySelected(threadId);
  @override
  SubmissionExecutionLease retainForSubmission(
    ConversationSession session, {
    required ThreadFacetStamp expectedOrigin,
  }) => delegate.retainForSubmission(session, expectedOrigin: expectedOrigin);
  @override
  SubmissionExecutionLease retainForCreatedInput(
    ConversationSession session, {
    required SubmitPromptReceipt receipt,
    required CreatedInputExecutionSource source,
  }) =>
      delegate.retainForCreatedInput(session, receipt: receipt, source: source);
}

/// A narrow real public component assembly, not a partial AppGraph claiming
/// full Drafts/archive support. All owners share the caller's budget/registry.
/// The real Conversation archive leaf satisfies Workspace construction; this
/// selection/Bootstrap journey never invokes archive or needs a Drafts leaf.
final class BootstrapWorkspaceFixture {
  BootstrapWorkspaceFixture({
    required ResourceBudget budget,
    required OperationRecorder operations,
  }) {
    final conversationAssembly = createConversationRepository(
      port: facets,
      context: context,
      commands: const UnscriptedConversationCommands(),
      timeline: timeline,
      budget: budget,
      operations: operations,
      agentDirectory: () => workspace.agents,
    );
    conversation = conversationAssembly.repository;
    recovery = createRecoveryRepository(
      port: recoveryPort,
      budget: budget,
      operations: operations,
    );
    final workspaceAssembly = createWorkspaceRepository(
      port: port,
      budget: budget,
      operations: operations,
      recovery: recovery.state,
      archiveCapture: conversationAssembly.archive,
    );
    workspace = workspaceAssembly.repository;
    demand = RecordingConversationDemand(
      conversationAssembly.demand,
      () => workspace.state.observerCount,
    );
    binding = WorkspaceConversationBinding(
      workspace: workspace,
      demand: demand,
    );
  }
  final port = ScriptedWorkspacePort();
  final recoveryPort = ProfileRecoveryPort();
  final context = FixtureConversationContext();
  final facets = FixtureConversationPort();
  final timeline = TimelineOpenQueue();
  late final ConversationRepository conversation;
  late final RecoveryRepository recovery;
  late final WorkspaceRepository workspace;
  late final RecordingConversationDemand demand;
  late final WorkspaceConversationBinding binding;

  void seal() {
    binding.seal();
    workspace.seal();
    conversation.seal();
    recovery.seal();
  }

  Future<CloseReport> close() async {
    seal();
    port.releasePending();
    for (final owner
        in context.metadataOwners.whereType<ScriptedThreadMetadata>()) {
      owner.releasePending();
    }
    for (final opening in timeline.requests) {
      if (!opening.result.isCompleted) {
        opening.result.complete(TestTimelineConnection(initial: baseline(1)));
      }
      final native = await opening.result.future;
      if (native is TestTimelineConnection &&
          native.closeGate?.isCompleted == false) {
        native.closeGate!.complete();
      }
    }
    final reports = await Future.wait([
      binding.close(),
      workspace.close(),
      conversation.close(),
      recovery.close(),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}
