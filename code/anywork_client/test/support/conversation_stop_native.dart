import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/workspace.dart';
import 'package:anywork_client/drafts.dart'
    show InputAcceptanceEvidence, StudioPromptInput, SubmitPromptReceipt;
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'conversation_fixture.dart';
import 'drafts_native_fixture.dart'
    show DraftCalls, DraftTurnOpen, DraftTurnPin;
import 'timeline_transport.dart';

const stopRuntime = 'stop-native-runtime';
const stopCleanupCancelled = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'Release this test\'s original native boundary during teardown.',
  retryable: false,
  correlationId: 'stop-test-cleanup',
);

TurnBrief stopTurn(int entry, {int revision = 1}) => TurnBrief(
  reference: TurnReadRef(entry: entry, revision: revision),
  revision: revision,
  updatedAt: revision,
  state: const TurnBriefState.running(startedAt: 1, phase: TurnPhase.thinking),
);

CommitReceipt stopReceipt(
  OperationId id, {
  CommitDisposition disposition = CommitDisposition.applied,
}) => CommitReceipt(
  operationId: id,
  disposition: disposition,
  targets: const [],
  effect: EffectPoint.immediate,
  requiresIdentityObservation: true,
  effective: false,
  durable: false,
);

AgentExecution stopExecutionValue(
  int entry, {
  AgentExecutionPhase phase = AgentExecutionPhase.running,
  String? turnId,
}) => AgentExecution(id: 'execution-$entry', phase: phase, turnId: turnId);

final class StopInterrupt {
  StopInterrupt(this.threadId, this.executionId, this.operationId);
  final String threadId;
  final String executionId;
  final OperationId operationId;
  final reply = Completer<StopExecutionReply>();
}

/// Only the native dispatch boundary. No receipt classification, retry,
/// observation barrier or Stop state is computed by this port.
final class StopCommands extends UnscriptedConversationCommands {
  final interrupts = DraftCalls<StopInterrupt>();
  @override
  Future<StopExecutionReply> stopExecution(
    String threadId,
    String executionId, {
    required OperationId operationId,
  }) {
    final call = StopInterrupt(threadId, executionId, operationId);
    interrupts.add(call);
    return call.reply.future;
  }

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) => throw UnsupportedError('A Stop scenario must not submit input');
  @override
  Future<InputAcceptanceEvidence?> readInputAcceptance(
    String threadId,
    String inputId,
  ) => throw UnsupportedError(
    'A Stop scenario must not read submitted-input history',
  );
}

/// One explicitly declared native source. Advancing frame sequence numbers is
/// mechanical; the test supplies the authoritative active/status facts.
final class StopSource {
  StopSource(this.session, this.opening, this.incarnation);
  final ConversationSession session;
  final FacetOpen<ThreadExecutionFrame> opening;
  final int incarnation;
  int revision = 0;
  ThreadFacetStamp get stamp => ThreadFacetStamp(
    runtimeEpoch: stopRuntime,
    incarnation: incarnation,
    facet: ThreadFacet.execution,
    revision: revision,
  );
  ThreadFeedIdentity get identity => ThreadFeedIdentity(
    feedId: opening.feed.feedId,
    runtimeEpoch: stopRuntime,
    incarnation: incarnation,
    facet: ThreadFacet.execution,
    mode: opening.mode,
  );

  int send({
    required TurnBrief? active,
    required ThreadStatus status,
    AgentExecution? execution,
  }) {
    final previous = revision++;
    if (previous == 0) {
      opening.feed.emit(
        ThreadExecutionFrame.data(
          deliverySequence: revision,
          event: ThreadExecutionEvent.baseline(
            identity: identity,
            stamp: stamp,
            value: ThreadExecutionBaseline(
              status: status,
              execution: execution,
              activeTurn: active,
              recentTerminalTurn: null,
              interactions: const InteractionIndexHeader(
                reference: InteractionIndexRef(entry: 10, revision: 1),
                total: 0,
                pending: 0,
              ),
              activity: null,
              storage: null,
            ),
          ),
        ),
      );
    } else {
      opening.feed.emit(
        ThreadExecutionFrame.data(
          deliverySequence: revision,
          event: ThreadExecutionEvent.change(
            stamp: stamp,
            baseRevision: previous,
            value: ThreadExecutionChange(
              status: status,
              execution: ExecutionReplacement.replace(value: execution),
              turns: TurnsReplacement(
                activeTurn: active,
                recentTerminalTurn: null,
              ),
              interactions: null,
              activity: const ActivityReplacement.unchanged(),
              storage: const StorageReplacement.unchanged(),
            ),
          ),
        ),
      );
    }
    return revision;
  }

  Future<void> deliver({
    required TurnBrief? active,
    required ThreadStatus status,
    AgentExecution? execution,
  }) async {
    final sequence = send(active: active, status: status, execution: execution);
    await opening.feed.acknowledged(sequence);
  }
}

final class StopFixture {
  StopFixture() {
    owner = ConversationFixture(commands: commands);
    owner.facets.turnOpen = (threadId, reference, origin) {
      final call = DraftTurnOpen(threadId, reference, origin);
      reads.add(call);
      return call.reply.future;
    };
  }
  final commands = StopCommands();
  late final ConversationFixture owner;
  final reads = DraftCalls<DraftTurnOpen>();
  final pins = <DraftTurnPin>[];
  final retainedOperations =
      <({OperationTicket<Unit> ticket, OperationFailurePhase phase})>[];
  ResourceBudget get budget => owner.budget;

  Future<StopSource> select({
    String threadId = 'thread',
    int incarnation = 1,
    TurnBrief? active,
  }) async {
    final index = owner.facets.execution.length;
    final timelineIndex = owner.timeline.requests.length;
    final session = owner.select(threadId);
    final opening = await owner.facets.executionOpened(index);
    // UI selection opens Timeline even though Stop only borrows Execution.
    // Supply that actual native handle so ordinary Session close can join it;
    // leaving its open Future unanswered would test a permanent late-open wait.
    final timeline = await owner.timeline.opened(timelineIndex);
    timeline.result.complete(
      TestTimelineConnection(
        initial: baseline(1, subscriptionId: 'stop-timeline-$timelineIndex'),
      ),
    );
    await opening.feed.listened.future;
    final source = StopSource(session, opening, incarnation);
    await source.deliver(
      active: active ?? stopTurn(7),
      execution: stopExecutionValue(7),
      status: ThreadStatus.running,
    );
    return source;
  }

  Future<DraftTurnPin> acceptRead(
    int index, {
    ReadText? threadId,
    ReadText? turnId,
    Completer<TurnReadHeader>? headerReply,
    bool manualClose = false,
    bool scriptText = false,
  }) async {
    final call = await reads.at(index);
    final header = TurnReadHeader(
      scope: ReadScopeIdentity(
        scopeId: 'stop-native-read-$index',
        runtimeEpoch: call.origin.runtimeEpoch,
        incarnation: call.origin.incarnation,
        sourceRevision: call.reference.revision,
      ),
      id: turnId ?? const ReadText.inline(text: 'native-original-turn'),
      threadId: threadId ?? ReadText.inline(text: call.threadId),
      revision: call.reference.revision,
      updatedAt: 1,
      inputId: null,
      state: const TurnReadState.running(
        startedAt: 1,
        phase: TurnPhase.thinking,
      ),
    );
    final pin = DraftTurnPin(
      header,
      headerReply: headerReply,
      manualClose: manualClose,
      scriptText: scriptText,
    );
    pins.add(pin);
    call.reply.complete(pin);
    return pin;
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    // Assertion-failure cleanup of actual entered boundaries only. These errors
    // do not count as a scenario's business success or authorize another send.
    deadline ??= DateTime.now().add(const Duration(seconds: 3));
    final closing = owner.repository.close(deadline: deadline);
    for (final opening in owner.timeline.requests) {
      if (!opening.result.isCompleted)
        opening.result.complete(
          TestTimelineConnection(
            initial: baseline(
              1,
              subscriptionId:
                  'stop-late-${owner.timeline.requests.indexOf(opening)}',
            ),
          ),
        );
    }
    for (final read in reads.values) {
      if (!read.reply.isCompleted)
        read.reply.completeError(stopCleanupCancelled);
    }
    for (final pin in pins) {
      final header = pin.headerReply;
      if (header != null && !header.isCompleted)
        header.completeError(stopCleanupCancelled);
      for (final text in pin.texts.values) {
        if (!text.reply.isCompleted)
          text.reply.completeError(stopCleanupCancelled);
      }
      for (final call in pin.closes.values) {
        if (!call.reply.isCompleted)
          call.reply.complete(
            FeedCloseReport(
              feedId: pin.value.scope.scopeId,
              outcome: const FeedCloseOutcome.clean(),
            ),
          );
      }
    }
    for (final call in commands.interrupts.values) {
      if (!call.reply.isCompleted)
        call.reply.completeError(stopCleanupCancelled);
    }
    return await closing;
  }
}
