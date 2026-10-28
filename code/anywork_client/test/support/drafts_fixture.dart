import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:test/test.dart';

import 'configuration_start_fixture.dart';
import 'conversation_fixture.dart';
import 'drafts_native_fixture.dart';
import 'drafts_workspace_fixture.dart';
import 'profile_recovery_port.dart';
import 'timeline_transport.dart';

const draftRuntime = 'draft-native-runtime';
const draftDigest =
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const draftOtherDigest =
    'sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
const draftNativeRoute = ModelSelection(
  model: AccountModelKey(accountId: 'start-account', modelId: 'native-model'),
  effort: 'native-effort',
);
const draftDefaults = DelegationSettings(
  mode: DelegationMode.automatic,
  preference: DelegationPreference.economy,
);
const draftFailure = StudioFailure(
  code: StudioFailureCode.storage,
  message: 'Original scripted boundary failed',
  retryable: true,
  correlationId: 'drafts-native-failure',
);

AttachmentMetadata draftFile(String id) => AttachmentMetadata(
  id: id,
  modality: AttachmentModality.file,
  mediaType: 'application/octet-stream',
  filename: '$id.bin',
  byteSize: 3,
);
WorkspaceThreadRecord draftThread(
  String id, {
  String projectId = 'project',
  String? root,
}) => fixtureThread(id, parentThreadId: root).copyWith(projectId: projectId);

ThreadFacetStamp draftFacet(
  ThreadFacet facet,
  int revision, {
  int incarnation = 1,
}) => ThreadFacetStamp(
  runtimeEpoch: draftRuntime,
  incarnation: incarnation,
  facet: facet,
  revision: revision,
);
ThreadFeedIdentity draftFeed(
  String feedId,
  ThreadFacet facet,
  ThreadObservationMode mode,
) => ThreadFeedIdentity(
  feedId: feedId,
  runtimeEpoch: draftRuntime,
  incarnation: 1,
  facet: facet,
  mode: mode,
);

ThreadExecutionBaseline draftExecution({
  int? durable,
  TurnBrief? active,
  TurnBrief? terminal,
  ThreadStatus status = ThreadStatus.idle,
}) => ThreadExecutionBaseline(
  status: status,
  activeTurn: active,
  recentTerminalTurn: terminal,
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

/// Real repositories/selection/Session/operations. Only external native frames,
/// read material, command results and platform staging are scripted.
final class DraftsFixture {
  DraftsFixture({
    ResourceBudget? budget,
    String clientId = 'conversation-test',
    OperationRecorder Function(OperationRecorder original)? decorateOperations,
    Future<String?> Function(Uint8List)? stageImage,
    Future<void> Function(String)? cleanupImage,
  }) : budget = budget ?? ResourceBudget() {
    configuration = ConfigurationStartFixture(budget: this.budget);
    conversations = ConversationFixture(
      budget: this.budget,
      clientId: clientId,
    );
    recovery = createRecoveryRepository(
      port: recoveryPort,
      budget: this.budget,
      operations: conversations.operations,
    );
    final workspaceAssembly = createWorkspaceRepository(
      port: directory,
      budget: this.budget,
      operations: conversations.operations,
      recovery: recovery.state,
      archiveCapture: conversations.archive,
    );
    workspace = workspaceAssembly.repository;
    final drafts = createDraftsRepository(
      configuration: configuration.repository,
      workspace: workspace,
      submissionSelection: workspaceAssembly.submissionSelection,
      conversations: conversations.repository,
      conversationDemand: conversations.demand,
      conversationCommands: commands,
      attachments: attachments,
      creations: creations,
      binary: binary,
      budget: this.budget,
      operations:
          decorateOperations?.call(conversations.operations) ??
          conversations.operations,
      clipboardImageStager: stageImage,
      clipboardImageCleanup: cleanupImage,
    );
    repository = drafts.repository;
    archive = drafts.archive;
  }
  final ResourceBudget budget;
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
  late final WorkspaceArchiveCapturePort archive;
  final captures = <WorkspaceArchiveCapture>[];

  /// How many UI Timeline connections the last selected Session already owned.
  int timelineOpens = 0;

  /// The real native Timeline connections the Session already accepted.
  List<TestTimelineConnection> timelineNatives = const [];

  /// Page/detail reads those accepted connections had at the ready barrier.
  List<({int pages, int details})> timelineReads = const [];

  /// Current page/detail reads of the very same accepted connections.
  List<({int pages, int details})> get timelineReadsNow => [
    for (final native in timelineNatives)
      (
        pages: native.pageRequests.length,
        details: native.detailRequests.length,
      ),
  ];
  bool protectUnknown = false;
  StudioFailure? retainedExecutionFailure;
  int _admissions = 0;
  int _routeCalls = 0;
  int _executionRevision = 1;
  FacetOpen<ThreadExecutionFrame>? execution;
  FacetOpen<ThreadConfigurationFrame>? threadConfiguration;

  Future<void> establish() async {
    await configuration.establish(startSources());
    await recoveryPort.establish(recovery);
    // WorkspaceAccess gates every command on the original Recovery source
    // status, so this explicit demand is part of establishing access, not
    // another ad-hoc read policy.
    await recovery.loadSourceStatus();
    final reading = workspace.loadProjectsPage();
    await directory.projectsBaseline();
    await reading;
  }

  Future<ComposerDraft> composer({
    String threadId = 'thread',
    int routeRevision = 8,
    int? durable,
  }) async {
    final index = conversations.facets.execution.length;
    conversations.select(threadId);
    execution = await conversations.facets.executionOpened(index);
    threadConfiguration = await conversations.facets.configurationOpened(index);
    await emitExecution(draftExecution(durable: durable));
    await emitRoute(routeRevision);
    // The selected Session owns exactly one real UI Timeline connection. The
    // fixture owns that native side, so it answers that open once the context
    // demand is established instead of leaving a production join pending.
    conversations.acceptPendingTimelineOpens();
    timelineOpens = conversations.timeline.requests.length;
    final natives = <TestTimelineConnection>[];
    for (final request in conversations.timeline.requests) {
      if (!request.result.isCompleted) continue;
      final connection = await request.result.future;
      // Every connection this fixture accepted must be the monitored native
      // fake: an unexpected type would silently drop it from the read evidence.
      expect(
        connection,
        isA<TestTimelineConnection>(),
        reason: 'The fixture monitors every accepted Session Timeline native',
      );
      natives.add(connection as TestTimelineConnection);
    }
    timelineNatives = natives;
    // Baseline taken right after the execution/configuration feeds are
    // acknowledged and the fixture answers the pending Timeline open. No
    // automatic page or detail read happens here, so a later increment can only
    // come from borrowing that accepted scope.
    timelineReads = timelineReadsNow;
    return repository.composer(threadId);
  }

  Future<void> emitExecution(ThreadExecutionBaseline value) async {
    final sequence = await sendExecution(value);
    await execution!.feed.acknowledged(sequence);
  }

  /// Send one declared native delivery without inventing an ACK on failure.
  /// Callers may wait for the actual port/read boundary before observing ACK.
  Future<int> sendExecution(ThreadExecutionBaseline value) async {
    final opening = execution!;
    final feed = opening.feed;
    await feed.listened.future;
    final revision = _executionRevision++;
    if (revision == 1) {
      feed.emit(
        ThreadExecutionFrame.data(
          deliverySequence: revision,
          event: ThreadExecutionEvent.baseline(
            identity: draftFeed(
              feed.feedId,
              ThreadFacet.execution,
              opening.mode,
            ),
            stamp: draftFacet(ThreadFacet.execution, revision),
            value: value,
          ),
        ),
      );
    } else {
      feed.emit(
        ThreadExecutionFrame.data(
          deliverySequence: revision,
          event: ThreadExecutionEvent.change(
            stamp: draftFacet(ThreadFacet.execution, revision),
            baseRevision: revision - 1,
            value: ThreadExecutionChange(
              status: value.status,
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
    }
    return revision;
  }

  int _configurationDelivery = 0;
  Future<void> emitRoute(int routeRevision) async {
    final opening = threadConfiguration!;
    final feed = opening.feed;
    await feed.listened.future;
    final revision = ++_configurationDelivery;
    final value = ThreadConfigurationValue(
      details: ThreadConfigurationReadRef(entry: 12, revision: revision),
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
    );
    feed.emit(
      ThreadConfigurationFrame.data(
        deliverySequence: revision,
        event: revision == 1
            ? ThreadConfigurationEvent.baseline(
                identity: draftFeed(
                  feed.feedId,
                  ThreadFacet.configuration,
                  opening.mode,
                ),
                stamp: draftFacet(ThreadFacet.configuration, revision),
                value: value,
              )
            : ThreadConfigurationEvent.replace(
                stamp: draftFacet(ThreadFacet.configuration, revision),
                value: value,
              ),
      ),
    );
    await feed.acknowledged(revision);
  }

  Future<void> selectStart([String projectId = 'project']) async {
    final result = await workspace.beginNewThread(projectId).result;
    expect(result, isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>());
    expect(
      workspace.state.value.selection,
      WorkspaceSelection(
        projectId: projectId,
        threadId: null,
        needsOpen: false,
      ),
    );
  }

  /// A single declared native result; no selection/default policy. Explicit
  /// selections supply both their exact query and native normalized intent.
  Future<void> prepare(
    StartDraft handle, {
    ModelSelection route = draftNativeRoute,
    DelegationSettings defaults = draftDefaults,
    StartRouteQuery? expectedQuery,
    StartRouteIntent? resultIntent,
  }) async {
    final reading = handle.prepareRoute();
    final opening = await configuration.opened(0);
    final pin = opening.native ?? opening.accept();
    final call = await pin.called(_routeCalls++);
    expect(call.query, expectedQuery ?? isA<ResolveStartRouteQuery>());
    call.reply.complete(
      StartRouteRead.ready(
        sources: opening.sources,
        query: call.query,
        intent: resultIntent ?? call.query.intent,
        route: route,
        defaults: defaults,
      ),
    );
    await reading;
  }

  Future<DraftAdmissionJob> admit(
    OperationTicket<Unit> ticket,
    List<AttachmentMetadata> values,
  ) async {
    final begin = await attachments.begins.at(_admissions++);
    expect(begin.id, ticket.id);
    final job = DraftAdmissionJob(begin.id);
    begin.reply.complete(job);
    (await job.reads.at(0)).complete(values);
    final closing = await job.closes.at(0);
    closing.reply.complete(
      FeedCloseReport(
        feedId: job.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect(await ticket.result, isA<AcknowledgedCommandResult<Unit>>());
    return job;
  }

  SubmitPromptReceipt receipt(DraftPromptCall call, {int sequence = 7}) =>
      SubmitPromptReceipt(
        threadId: call.threadId,
        inputId: call.input.inputId,
        cursor: sequence,
        requestDigest: draftDigest,
      );

  WorkspaceThreadArchiveCapture threadCapture(String threadId) {
    final capture = archive.captureThread(
      threadId,
      frozenSelection: workspace.state.value,
    );
    captures.add(capture);
    return capture;
  }

  WorkspaceProjectArchiveCapture projectCapture(String projectId) {
    final capture = archive.captureProject(
      projectId,
      frozenSelection: workspace.state.value,
    );
    captures.add(capture);
    return capture;
  }

  Future<void> close() async {
    // Tests settle their actual native work first. No teardown dispatch/result
    // policy fabricates success; unknown paths assert retained responsibilities.
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    try {
      final report = await repository.close(deadline: deadline);
      if (protectUnknown) {
        expect(report.complete, isFalse);
      } else {
        expect(report.unresolved, isEmpty);
      }
    } finally {
      directory.native.acceptPendingOpens();
      conversations.acceptPendingTimelineOpens();
      // Join every peer before checking the intentional failed-handoff report;
      // an assertion failure must not skip cleanup of the independent peers.
      final reports = await Future.wait([
        configuration.repository.close(deadline: deadline),
        configuration.owner.models.close(deadline: deadline),
        workspace.close(deadline: deadline),
        recovery.close(deadline: deadline),
        conversations.repository.close(deadline: deadline),
      ]);
      expect(reports.take(4).expand((item) => item.unresolved), isEmpty);
      final conversationReport = reports.last;
      final expectedFailure = retainedExecutionFailure;
      if (expectedFailure == null) {
        expect(conversationReport.unresolved, isEmpty);
      } else {
        expect(conversationReport.unresolved, isNotEmpty);
        for (final resource in conversationReport.unresolved) {
          expect(resource.owner, startsWith('execution:'));
          for (final issue in resource.issues) {
            expect(issue.diagnostic.code, expectedFailure.code.name);
            expect(
              issue.diagnostic.correlationId,
              expectedFailure.correlationId,
            );
            expect(issue.recovery, CleanupRecovery.terminal);
          }
        }
      }
    }
    if (!protectUnknown && retainedExecutionFailure == null)
      expect(budget.usage, isEmpty);
  }
}

Future<DraftsFixture> draftsFixture({
  String clientId = 'conversation-test',
  OperationRecorder Function(OperationRecorder original)? decorateOperations,
  Future<String?> Function(Uint8List)? stageImage,
  Future<void> Function(String)? cleanupImage,
}) async {
  final fixture = DraftsFixture(
    clientId: clientId,
    decorateOperations: decorateOperations,
    stageImage: stageImage,
    cleanupImage: cleanupImage,
  );
  addTearDown(fixture.close);
  await fixture.establish();
  return fixture;
}

Future<void> emitCreatedBaseline(
  DraftCreatedSource source, {
  int? durable,
}) async {
  await source.feed.listened.future;
  source.feed.emit(
    ThreadExecutionFrame.data(
      deliverySequence: 1,
      event: ThreadExecutionEvent.baseline(
        identity: draftFeed(
          source.feed.feedId,
          ThreadFacet.execution,
          ThreadObservationMode.live,
        ),
        stamp: draftFacet(ThreadFacet.execution, 1),
        value: draftExecution(durable: durable),
      ),
    ),
  );
  await source.feed.acknowledged(1);
}
