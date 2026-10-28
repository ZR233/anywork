import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/configuration_start_fixture.dart';
import '../../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../../anywork_client/test/support/drafts_native_fixture.dart';
import '../../../../anywork_client/test/support/drafts_workspace_fixture.dart';
import '../../../../anywork_client/test/support/profile_recovery_port.dart';

/// Flutter's package does not depend on package:test. Reuse the SDK's native
/// port fixtures, but assemble the real domain owners here with flutter_test.
/// This is only composition and declared native material, not another reducer,
/// attachment cache, draft implementation or legacy Client facade.
final class TimelineDraftsEnvironment {
  TimelineDraftsEnvironment({String clientId = 'timeline-drafts'}) {
    configuration = ConfigurationStartFixture(budget: budget);
    conversations = ConversationFixture(budget: budget, clientId: clientId);
    recovery = createRecoveryRepository(
      port: recoveryPort,
      budget: budget,
      operations: conversations.operations,
    );
    final workspaceAssembly = createWorkspaceRepository(
      port: directory,
      budget: budget,
      operations: conversations.operations,
      recovery: recovery.state,
      archiveCapture: conversations.archive,
    );
    workspace = workspaceAssembly.repository;
    repository = createDraftsRepository(
      configuration: configuration.repository,
      workspace: workspace,
      submissionSelection: workspaceAssembly.submissionSelection,
      conversations: conversations.repository,
      conversationDemand: conversations.demand,
      conversationCommands: commands,
      attachments: attachments,
      creations: creations,
      binary: binary,
      budget: budget,
      operations: conversations.operations,
    ).repository;
  }

  final budget = ResourceBudget();
  final recoveryPort = ProfileRecoveryPort();
  final directory = DraftWorkspacePort();
  final attachments = DraftAdmissionPort();
  final commands = DraftCommands();
  final creations = DraftCreationPort();
  final binary = DraftBinaryPort();
  late final ConfigurationStartFixture configuration;
  late final ConversationFixture conversations;
  late final RecoveryRepository recovery;
  late final WorkspaceRepository workspace;
  late final DraftsRepository repository;
  FacetOpen<ThreadExecutionFrame>? execution;
  int _executionRevision = 0;

  Future<void> establish() async {
    await configuration.establish(startSources());
    await recoveryPort.establish(recovery);
    final reading = workspace.loadProjectsPage();
    await directory.projectsBaseline();
    await reading;
  }

  Future<ComposerDraft> composer({
    String threadId = 'thread',
    int routeRevision = 8,
  }) async {
    final index = conversations.facets.execution.length;
    conversations.select(threadId);
    execution = await conversations.facets.executionOpened(index);
    final configuration = await conversations.facets.configurationOpened(index);
    await emitExecution(draftExecution());
    final feed = configuration.feed;
    await feed.listened.future;
    feed.emit(
      ThreadConfigurationFrame.data(
        deliverySequence: 1,
        event: ThreadConfigurationEvent.baseline(
          identity: draftFeed(
            feed.feedId,
            ThreadFacet.configuration,
            configuration.mode,
          ),
          stamp: draftFacet(ThreadFacet.configuration, 1),
          value: ThreadConfigurationValue(
            details: const ThreadConfigurationReadRef(entry: 12, revision: 1),
            sources: const ConfigProjectionStamp(
              settingsRevision: 1,
              modelCatalogRevision: 1,
              closing: false,
            ),
            modeRevision: 1,
            modeBindingRevision: null,
            modelRoute: ModelRouteBrief(
              revision: routeRevision,
              available: true,
              hasUnavailableReason: false,
            ),
            activeSkillCount: 0,
            activeMcp: ThreadCapabilitySupport.unsupported,
            activeLsp: ThreadCapabilitySupport.unsupported,
            mcpHealth: ThreadCapabilitySupport.unsupported,
          ),
        ),
      ),
    );
    await feed.acknowledged(1);
    return repository.composer(threadId);
  }

  Future<void> emitExecution(ThreadExecutionBaseline value) async {
    final opening = execution!;
    final feed = opening.feed;
    await feed.listened.future;
    final revision = ++_executionRevision;
    feed.emit(
      ThreadExecutionFrame.data(
        deliverySequence: revision,
        event: revision == 1
            ? ThreadExecutionEvent.baseline(
                identity: draftFeed(
                  feed.feedId,
                  ThreadFacet.execution,
                  opening.mode,
                ),
                stamp: draftFacet(ThreadFacet.execution, revision),
                value: value,
              )
            : ThreadExecutionEvent.change(
                stamp: draftFacet(ThreadFacet.execution, revision),
                baseRevision: revision - 1,
                value: ThreadExecutionChange(
                  status: value.status,
                  execution: ExecutionReplacement.replace(
                    value: value.execution,
                  ),
                  continuation: ContinuationReplacement.replace(
                    value: value.continuation,
                  ),
                  turns: TurnsReplacement(
                    activeTurn: value.activeTurn,
                    recentTerminalTurn: value.recentTerminalTurn,
                  ),
                  interactions: null,
                  activity: ActivityReplacement.replace(value: value.activity),
                  storage: StorageReplacement.replace(value: value.storage),
                ),
              ),
      ),
    );
    await feed.acknowledged(revision);
  }

  SubmitPromptReceipt receipt(DraftPromptCall call) => SubmitPromptReceipt(
    threadId: call.threadId,
    inputId: call.input.inputId,
    cursor: 7,
    requestDigest: 'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  );

  Future<void> close() async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final draftReport = await repository.close(deadline: deadline);
    directory.native.acceptPendingOpens();
    final peers = await Future.wait([
      workspace.close(deadline: deadline),
      recovery.close(deadline: deadline),
      configuration.repository.close(deadline: deadline),
      conversations.repository.close(deadline: deadline),
    ]);
    expect(draftReport.unresolved, isEmpty);
    expect([for (final report in peers) ...report.unresolved], isEmpty);
    expect(budget.usage, isEmpty);
  }
}

Future<TimelineDraftsEnvironment> openTimelineDraftsEnvironment() async {
  final environment = TimelineDraftsEnvironment();
  addTearDown(environment.close);
  await environment.establish();
  return environment;
}

ThreadFacetStamp draftFacet(ThreadFacet facet, int revision) =>
    ThreadFacetStamp(
      runtimeEpoch: 'timeline-native-runtime',
      incarnation: 1,
      facet: facet,
      revision: revision,
    );

ThreadFeedIdentity draftFeed(
  String id,
  ThreadFacet facet,
  ThreadObservationMode mode,
) => ThreadFeedIdentity(
  feedId: id,
  runtimeEpoch: 'timeline-native-runtime',
  incarnation: 1,
  facet: facet,
  mode: mode,
);

ThreadExecutionBaseline draftExecution({
  int? durable,
  AgentExecution? execution,
  ContinuationView? continuation,
  TurnBrief? active,
  ThreadStatus status = ThreadStatus.idle,
}) => ThreadExecutionBaseline(
  status: status,
  execution: execution,
  continuation: continuation,
  activeTurn: active,
  recentTerminalTurn: null,
  interactions: const InteractionIndexHeader(
    reference: InteractionIndexRef(entry: 10, revision: 1),
    total: 0,
    pending: 0,
  ),
  activity: null,
  storage: durable == null
      ? null
      : StorageBrief(
          reference: StorageReadRef(entry: 11, revision: durable),
          fault: null,
          faultGeneration: 0,
          acceptedSequence: durable,
          durableSequence: durable,
          execution: ThreadStorageExecution.running,
          pressurePaused: false,
          resumeRequired: false,
          canResume: false,
          hasLastError: false,
        ),
);
