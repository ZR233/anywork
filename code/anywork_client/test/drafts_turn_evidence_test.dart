import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:test/test.dart';

import 'support/drafts_fixture.dart';
import 'support/drafts_native_fixture.dart';

const _running = TurnBriefState.running(
  startedAt: 1,
  phase: TurnPhase.thinking,
);
const _runningRead = TurnReadState.running(
  startedAt: 1,
  phase: TurnPhase.thinking,
);
const _retryIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'turn-native',
    code: 'joinPending',
    message: 'The original native Turn scope still needs cleanup.',
    retryable: true,
    correlationId: 'turn-original-close',
  ),
  recovery: CleanupRecovery.retryClose,
);
const _headerFailure = StudioFailure(
  code: StudioFailureCode.protocol,
  message: 'Original Turn header could not be read.',
  retryable: false,
  correlationId: 'turn-header-original',
);
const _sourceFailure = StudioFailure(
  code: StudioFailureCode.protocol,
  message: 'The original Execution source failed.',
  retryable: false,
  correlationId: 'retry-original-source',
);
const _notificationFailure = StudioFailure(
  code: StudioFailureCode.storage,
  message: 'The original evidence notification threw.',
  retryable: true,
  correlationId: 'retry-evidence-notification',
);
const _historyFailure = StudioFailure(
  code: StudioFailureCode.storage,
  message: 'The original history read failed.',
  retryable: false,
  correlationId: 'retry-original-history',
);
const _cancelFailure = StudioFailure(
  code: StudioFailureCode.storage,
  message: 'Cancellation failed before its side effect.',
  retryable: true,
  correlationId: 'retry-operation-watch',
);
const _partialCancelFailure = StudioFailure(
  code: StudioFailureCode.storage,
  message: 'Cancellation threw after the real watch ended.',
  retryable: true,
  correlationId: 'retry-operation-watch-partial',
);
const _terminalIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'native-execution',
    code: 'protocol',
    message: 'The original native Execution join failed.',
    retryable: false,
    correlationId: 'retry-original-source',
  ),
  recovery: CleanupRecovery.terminal,
);

/// The public operations port still uses the real Registry for every value,
/// result, observation and settlement. Only synchronous environmental throws
/// around evidence delivery and a real returned watch's cancellation are added.
final class _OperationBoundary implements OperationRecorder {
  _OperationBoundary(this.original);
  final OperationRecorder original;
  final watches = <_CancelBoundary>[];
  void Function(StudioFailure)? afterEvidence;
  @override
  Operations get observations => original.observations;
  @override
  OperationWriter<T> begin<T>({
    required String target,
    DraftStamp? draft,
    OperationId? operationId,
    bool requireIdentityObservation = false,
  }) => _BoundaryWriter(
    original.begin<T>(
      target: target,
      draft: draft,
      operationId: operationId,
      requireIdentityObservation: requireIdentityObservation,
    ),
    this,
  );
  @override
  void observe(ObservationStamp stamp) => original.observe(stamp);
  @override
  void seal() => original.seal();

  _CancelBoundary record(Observation original) {
    final watch = _CancelBoundary(original);
    watches.add(watch);
    return watch;
  }
}

final class _BoundaryWriter<T> implements OperationWriter<T> {
  _BoundaryWriter(this.original, this.boundary);
  final OperationWriter<T> original;
  final _OperationBoundary boundary;
  @override
  late final OperationTicket<T> ticket = _BoundaryTicket(
    original.ticket,
    boundary,
  );
  @override
  void accepted(T value, CommitReceipt receipt) =>
      original.accepted(value, receipt);
  @override
  void acknowledged(T value) => original.acknowledged(value);
  @override
  void identityObserved() => original.identityObserved();
  @override
  void effective() => original.effective();
  @override
  void durable() => original.durable();
  @override
  void evidenceFailed(StudioFailure error) {
    original.evidenceFailed(error);
    boundary.afterEvidence?.call(error);
  }

  @override
  void rejected(StudioFailure error) => original.rejected(error);
  @override
  void unknownOutcome(StudioFailure error) => original.unknownOutcome(error);
  @override
  void synchronizationFailed(
    StudioFailure error, {
    T? value,
    CommitReceipt? receipt,
  }) => original.synchronizationFailed(error, value: value, receipt: receipt);
  @override
  void acknowledgedSynchronizationFailed(StudioFailure error, {T? value}) =>
      original.acknowledgedSynchronizationFailed(error, value: value);
}

final class _BoundaryTicket<T> implements OperationTicket<T> {
  _BoundaryTicket(this.original, this.boundary);
  final OperationTicket<T> original;
  final _OperationBoundary boundary;
  @override
  OperationId get id => original.id;
  @override
  Future<CommandResult<T>> get result => original.result;
  @override
  late final ReadonlyLatestValue<OperationState> state = _BoundaryState(
    original.state,
    boundary,
  );
}

final class _BoundaryState implements ReadonlyLatestValue<OperationState> {
  _BoundaryState(this.original, this.boundary);
  final ReadonlyLatestValue<OperationState> original;
  final _OperationBoundary boundary;
  @override
  OperationState get value => original.value;
  @override
  int get observerCount => original.observerCount;
  @override
  Observation watch(
    void Function(OperationState) listener, {
    bool fireImmediately = false,
  }) => boundary.record(
    original.watch(listener, fireImmediately: fireImmediately),
  );
  @override
  LatestWatch<OperationState> watchLatest(
    void Function(OperationState) listener,
  ) {
    final watch = original.watchLatest(listener);
    return LatestWatch(
      value: watch.value,
      observation: boundary.record(watch.observation),
    );
  }

  @override
  Future<OperationState> waitFor(bool Function(OperationState) predicate) =>
      original.waitFor(predicate);
}

final class _CancelBoundary implements Observation {
  _CancelBoundary(this.original);
  final Observation original;
  void Function()? beforeCancel;
  void Function()? afterCancel;
  int cancelCalls = 0;
  @override
  bool get isCancelled => original.isCancelled;
  @override
  bool get isPaused => original.isPaused;
  @override
  void pause() => original.pause();
  @override
  void resume() => original.resume();
  @override
  void cancel() {
    cancelCalls++;
    beforeCancel?.call();
    original.cancel();
    afterCancel?.call();
  }
}

Iterable<FeedCloseIssue> _issues(CloseReport report) =>
    report.unresolved.expand((item) => item.issues);
Iterable<ResourceUsage> _inputUsage(DraftsFixture fixture, OperationId id) =>
    fixture.budget.usage.where(
      (usage) => usage.owner == 'input-evidence:${id.value}',
    );

FeedCloseIssue _cleanupIssue(String stage, StudioFailure failure) =>
    FeedCloseIssue(
      diagnostic: StudioShutdownIssue(
        stage: stage,
        code: failure.code.name,
        message: failure.message,
        retryable: failure.retryable,
        correlationId: failure.correlationId,
      ),
      recovery: CleanupRecovery.retryClose,
    );

TurnBrief _turn(int entry, {TurnBriefState state = _running}) => TurnBrief(
  reference: TurnReadRef(entry: entry, revision: 1),
  revision: 1,
  updatedAt: entry,
  state: state,
);

/// Records only actual native calls. No lease, evidence matcher or ACK policy.
final class _TurnBoundary {
  _TurnBoundary(DraftsFixture fixture) {
    fixture.conversations.facets.turnOpen = (thread, reference, origin) {
      final call = DraftTurnOpen(thread, reference, origin);
      calls.add(call);
      return call.reply.future;
    };
  }
  final calls = DraftCalls<DraftTurnOpen>();

  Future<DraftTurnPin> accept(
    int index, {
    required ReadText? inputId,
    TurnReadState state = _runningRead,
    Completer<TurnReadHeader>? headerReply,
    bool manualClose = false,
    bool scriptText = false,
  }) async {
    final call = await calls.at(index);
    final header = TurnReadHeader(
      scope: ReadScopeIdentity(
        scopeId: 'native-turn-$index',
        runtimeEpoch: call.origin.runtimeEpoch,
        incarnation: call.origin.incarnation,
        sourceRevision: call.reference.revision,
      ),
      inputId: inputId,
      id: ReadText.inline(text: 'turn-${call.reference.entry}'),
      threadId: ReadText.inline(text: call.threadId),
      revision: call.reference.revision,
      updatedAt: 1,
      state: state,
    );
    final pin = DraftTurnPin(
      header,
      headerReply: headerReply,
      manualClose: manualClose,
      scriptText: scriptText,
    );
    call.reply.complete(pin);
    return pin;
  }
}

Future<
  ({
    ComposerDraft composer,
    OperationTicket<SubmitPromptReceipt> ticket,
    DraftPromptCall call,
  })
>
_dispatch(DraftsFixture fixture, {bool holdHistory = false}) async {
  final composer = await fixture.composer();
  composer.setText('original input');
  final ticket = composer.submit();
  final call = await fixture.commands.prompts.at(0);
  call.reply.complete(fixture.receipt(call));
  final history = await fixture.commands.acceptances.at(0);
  expect((history.threadId, history.inputId), ('thread', ticket.id.value));
  if (!holdHistory) history.reply.complete(null);
  expect(
    await ticket.result,
    isA<AcknowledgedCommandResult<SubmitPromptReceipt>>(),
  );
  return (composer: composer, ticket: ticket, call: call);
}

Iterable<ResourceUsage> _turnUsage(DraftsFixture fixture) =>
    fixture.budget.usage.where(
      (usage) =>
          usage.kind == ResourceKind.readModel &&
          usage.owner == 'thread-read:thread',
    );

void _noReplayOrTimeline(DraftsFixture fixture) {
  expect(fixture.commands.prompts.values, hasLength(1));
  expect(fixture.conversations.timeline.requests, isEmpty);
}

Future<void> _createdOnly({
  required bool emptyFirst,
  bool ordinaryReady = false,
}) async {
  final fixture = await draftsFixture();
  final native = _TurnBoundary(fixture);
  await fixture.selectStart();
  final start = fixture.repository.start('project')..setText('created input');
  await fixture.prepare(start);
  final ticket = start.submit();
  final begin = await fixture.creations.begins.at(0);
  final job = DraftCreationJob(
    begin.id,
    'project',
    begin.request.input.inputId,
  );
  begin.reply.complete(job);
  final nativeResult = await job.reads.at(0);
  ConversationSession? ordinarySession;
  if (ordinaryReady) {
    // An ordinary, already-ready UI attempt has the same real Thread and
    // incarnation and a native matching input header. It is not this source.
    await fixture.composer(threadId: 'created');
    ordinarySession = fixture.conversations.repository.existingSession(
      'created',
    )!;
    await fixture.emitExecution(
      draftExecution(status: ThreadStatus.running, active: _turn(90)),
    );
    final uiReading = ordinarySession.openTurn(
      _turn(90).reference,
      origin: ordinarySession.execution.value.stamp!,
    );
    final uiPin = await native.accept(
      0,
      inputId: ReadText.inline(text: begin.request.input.inputId),
    );
    final uiScope = await uiReading;
    expect(
      (await uiScope.header()).inputId,
      ReadText.inline(text: begin.request.input.inputId),
    );
    expect((await uiScope.close()).complete, isTrue);
    expect(uiPin.entered.isCompleted, isTrue);
    expect(ordinarySession.execution.value.sync.phase, FacetSyncPhase.ready);
    expect(ordinarySession.execution.value.stamp?.runtimeEpoch, draftRuntime);
    expect(ordinarySession.execution.value.stamp?.incarnation, 1);
    expect(fixture.execution!.feed.acknowledgements, [1, 2]);
    expect(ticket.state.value.observed, isFalse);
  }
  final metadataBefore = List.of(
    fixture.conversations.context.metadataRequests,
  );
  final recoveryBefore = List.of(
    fixture.conversations.context.recoveryRequests,
  );
  if (!ordinaryReady) {
    expect(metadataBefore, isEmpty);
    expect(recoveryBefore, isEmpty);
  }
  final turnIndex = ordinaryReady ? 1 : 0;
  nativeResult.complete(
    StartNewThreadResult(
      thread: draftThread('created').copyWith(frozenModel: draftNativeRoute),
      receipt: SubmitPromptReceipt(
        threadId: 'created',
        inputId: begin.request.input.inputId,
        cursor: 7,
        requestDigest: draftDigest,
      ),
    ),
  );
  final source = DraftCreatedSource('created', begin.request.input.inputId);
  (await job.sourceCalls.at(0)).complete(source);
  Completer<TurnReadHeader>? createdHeader;
  DraftTurnPin? createdPin;
  addTearDown(() async {
    // Only cleanup of this scenario's already-known native result and gates.
    // Seal first, so late handles cannot become substitute observation proof.
    final closing = fixture.repository.close();
    final pendingOpens = List.of(native.calls.values);
    for (var index = 0; index < pendingOpens.length; index++) {
      if (!pendingOpens[index].reply.isCompleted) {
        await native.accept(
          index,
          inputId: ReadText.inline(text: begin.request.input.inputId),
        );
      }
    }
    final pending = createdHeader;
    final original = createdPin;
    if (pending != null && original != null && !pending.isCompleted)
      pending.complete(original.value);
    for (final query in fixture.commands.acceptances.values) {
      if (!query.reply.isCompleted) query.reply.complete(null);
    }
    final nativeClose = await job.closes.at(0);
    if (!nativeClose.reply.isCompleted)
      nativeClose.reply.complete(
        FeedCloseReport(
          feedId: job.id.value,
          outcome: const FeedCloseOutcome.clean(),
        ),
      );
    expect((await closing).complete, isTrue);
  });
  if (ordinaryReady) {
    await Future.any<void>([
      source.opened.future,
      ticket.result.then<void>(
        (_) => fail(
          'The old ordinary UI baseline cannot complete this created-source observation',
        ),
      ),
    ]);
  }
  await source.feed.listened.future;
  expect(ticket.state.value.acknowledged, isFalse);
  expect(ticket.state.value.observed, isFalse);
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
        value: emptyFirst
            ? draftExecution()
            : draftExecution(status: ThreadStatus.running, active: _turn(1)),
      ),
    ),
  );
  if (emptyFirst) {
    await source.feed.acknowledged(1);
    expect(native.calls.values, hasLength(turnIndex));
    expect(
      await ticket.result,
      isA<AcknowledgedCommandResult<StartNewThreadResult>>(),
    );
    (await fixture.commands.acceptances.at(0)).reply.complete(null);
    expect(ticket.state.value.observed, isFalse);
    source.feed.emit(
      ThreadExecutionFrame.data(
        deliverySequence: 2,
        event: ThreadExecutionEvent.change(
          stamp: draftFacet(ThreadFacet.execution, 2),
          baseRevision: 1,
          value: ThreadExecutionChange(
            status: ThreadStatus.running,
            turns: TurnsReplacement(
              activeTurn: _turn(1),
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
  final opening = await native.calls.at(turnIndex);
  expect(opening.threadId, 'created');
  expect(opening.reference, _turn(1).reference);
  expect(opening.origin, draftFacet(ThreadFacet.execution, emptyFirst ? 2 : 1));
  final header = Completer<TurnReadHeader>();
  createdHeader = header;
  final pin = await native.accept(
    turnIndex,
    inputId: ReadText.inline(text: begin.request.input.inputId),
    headerReply: header,
  );
  createdPin = pin;
  await pin.entered.future;
  expect(
    source.feed.acknowledgements,
    emptyFirst ? [1] : isEmpty,
    reason: 'A real first-baseline/change header is pending; ready cannot be awaited in a cycle before binding',
  );
  if (!emptyFirst) expect(ticket.state.value.acknowledged, isFalse);
  expect(source.opens, 1);
  expect(
    fixture.conversations.facets.execution,
    ordinaryReady ? hasLength(1) : isEmpty,
  );
  expect(fixture.conversations.context.metadataRequests, metadataBefore);
  expect(fixture.conversations.context.recoveryRequests, recoveryBefore);
  if (ordinaryReady) {
    expect(fixture.execution!.feed.closeStarted.isCompleted, isTrue);
    expect(fixture.execution!.feed.acknowledgements, [1, 2]);
    expect(
      source.runtimeEpoch,
      ordinarySession!.execution.value.stamp?.runtimeEpoch,
    );
    expect(source.incarnation, 1);
  }
  expect(fixture.conversations.timeline.requests, isEmpty);
  header.complete(pin.value);
  await source.feed.acknowledged(emptyFirst ? 2 : 1);
  expect(
    await ticket.result,
    isA<AcknowledgedCommandResult<StartNewThreadResult>>(),
  );
  if (!emptyFirst)
    (await fixture.commands.acceptances.at(0)).reply.complete(null);
  expect(ticket.state.value.observed, isTrue);
  expect(ticket.state.value.effective, isTrue);
  expect(ticket.state.value.durable, isFalse);
  expect(pin.texts.values, isEmpty);
  expect(native.calls.values, hasLength(turnIndex + 1));
  final session = fixture.conversations.repository.existingSession('created')!;
  if (ordinaryReady) {
    expect(
      session,
      same(ordinarySession),
      reason: 'Changing the actual source must not manufacture a replacement Session',
    );
    fixture.conversations.deselect();
  }
  expect(
    () => session.openTurn(opening.reference, origin: opening.origin),
    throwsA(
      isA<StudioFailure>().having(
        (failure) => failure.code,
        'code',
        StudioFailureCode.cancelled,
      ),
    ),
    reason: 'The submission capability must not create a hidden UI demand',
  );
  final closing = fixture.repository.close();
  (await job.closes.at(0)).reply.complete(
    FeedCloseReport(
      feedId: job.id.value,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
  expect((await closing).complete, isTrue);
  expect(source.opens, 1);
  expect(fixture.creations.begins.values, hasLength(1));
  expect(
    fixture.conversations.facets.execution,
    ordinaryReady ? hasLength(1) : isEmpty,
  );
  expect(fixture.conversations.context.metadataRequests, metadataBefore);
}

void main() {
  test('submission and UI share eight scopes, but UI archive cannot close a pre-ACK operation header read', () async {
    final fixture = await draftsFixture();
    final native = _TurnBoundary(fixture);
    final composer = await fixture.composer();
    final session = fixture.conversations.repository.existingSession('thread')!;
    await fixture.emitExecution(
      draftExecution(status: ThreadStatus.running, active: _turn(1)),
    );
    final uiScopes = <TurnReadScope>[];
    final uiPins = <DraftTurnPin>[];
    Future<CloseReport>? archiveClosing;
    Completer<TurnReadHeader>? submissionHeader;
    DraftTurnPin? submissionPin;
    addTearDown(() async {
      final original = submissionPin;
      final header = submissionHeader;
      if (original != null && header != null && !header.isCompleted)
        header.complete(original.value);
      final closing = [for (final scope in uiScopes) scope.close()];
      for (final pin in uiPins.where((pin) => pin.manualClose)) {
        final call = await pin.closes.at(0);
        if (!call.reply.isCompleted)
          call.reply.complete(
            FeedCloseReport(
              feedId: pin.value.scope.scopeId,
              outcome: const FeedCloseOutcome.clean(),
            ),
          );
      }
      for (final report in await Future.wait(closing)) {
        expect(report.complete, isTrue);
      }
      if (archiveClosing case final pending?)
        expect((await pending).complete, isTrue);
    });
    for (var index = 0; index < 7; index++) {
      final reading = session.openTurn(
        _turn(1).reference,
        origin: session.execution.value.stamp!,
      );
      final pin = await native.accept(
        index,
        inputId: const ReadText.inline(text: 'unrelated-ui-input'),
        manualClose: index == 0,
      );
      uiPins.add(pin);
      final scope = await reading;
      await scope.header();
      await pin.entered.future;
      uiScopes.add(scope);
    }
    expect(_turnUsage(fixture), hasLength(7));
    await fixture.emitExecution(draftExecution());
    composer.setText('operation survives UI');
    final ticket = composer.submit();
    final call = await fixture.commands.prompts.at(0);
    call.reply.complete(fixture.receipt(call));
    (await fixture.commands.acceptances.at(0)).reply.complete(null);
    await ticket.result;
    final sequence = await fixture.sendExecution(
      draftExecution(status: ThreadStatus.running, active: _turn(8)),
    );
    final gate = Completer<TurnReadHeader>();
    submissionHeader = gate;
    final pin = await native.accept(
      7,
      inputId: ReadText.inline(text: ticket.id.value),
      headerReply: gate,
    );
    submissionPin = pin;
    await pin.entered.future; // Actual operation query is waiting, not a future negative check.
    expect(_turnUsage(fixture), hasLength(8));
    expect(fixture.execution!.feed.acknowledgements, isNot(contains(sequence)));
    expect(
      () => session.openTurn(
        _turn(8).reference,
        origin: session.execution.value.stamp!,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.overloaded,
        ),
      ),
    );
    expect(
      native.calls.values,
      hasLength(8),
      reason: 'There is one shared scope map, not another submission pool',
    );
    final capture = fixture.conversations.archive.captureThread(
      'thread',
      frozenSelection: fixture.workspace.state.value,
    );
    await capture.prepare(draftThread('thread'));
    var archiveCompleted = false;
    final archiving = capture
        .afterArchived(
          ArchiveThreadResult(
            archivedRootId: 'thread',
            removedThreadIds: ['thread'],
            nextRoot: null,
          ),
        )
        .then((report) {
          archiveCompleted = true;
          return report;
        });
    archiveClosing = archiving;
    final originalUiClose = await uiPins.first.closes.at(
      0,
    ); // Actual native close has entered its wait.
    expect(
      archiveCompleted,
      isFalse,
      reason: 'UI retirement must join its original native close, not fire and forget',
    );
    expect(
      (await uiScopes.first.close(deadline: DateTime.utc(2000))).complete,
      isFalse,
    );
    expect(
      _turnUsage(fixture).length,
      greaterThanOrEqualTo(2),
      reason: 'Both the waiting original UI scope and operation scope retain their permits',
    );
    expect(pin.requests, 0);
    expect(fixture.execution!.feed.acknowledgements, isNot(contains(sequence)));
    expect(ticket.state.value.observed, isFalse);
    originalUiClose.reply.complete(
      FeedCloseReport(
        feedId: uiPins.first.value.scope.scopeId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await archiving).complete, isTrue);
    expect(fixture.conversations.repository.active.value, isNull);
    expect(_turnUsage(fixture), hasLength(1));
    expect(
      pin.requests,
      0,
      reason: 'Archive retires UI scopes only; the original operation still owns this query',
    );
    expect(
      () => session.openTurn(
        _turn(8).reference,
        origin: session.execution.value.stamp!,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    gate.complete(pin.value);
    await fixture.execution!.feed.acknowledged(sequence);
    expect(ticket.state.value.observed, isTrue);
    expect(ticket.state.value.effective, isTrue);
    expect(ticket.state.value.durable, isFalse);
    expect(fixture.execution!.feed.requestCloseCalls, 0);
    _noReplayOrTimeline(fixture);
  });

  test(
    'created-source-only first running baseline binds before ready and before ACK without activating UI',
    () => _createdOnly(emptyFirst: false),
  );
  test(
    'created-source-only empty baseline initializes the consumer and a later running change binds without UI',
    () => _createdOnly(emptyFirst: true),
  );
  test(
    'an ordinary ready UI baseline with matching Thread, incarnation and input cannot substitute for the actual created source',
    () => _createdOnly(emptyFirst: false, ordinaryReady: true),
  );

  test('a known creation automatically joins failed first-baseline observer construction and releases work before explicit cleanup', () async {
    final fixture = await draftsFixture();
    final native = _TurnBoundary(fixture);
    await fixture.selectStart();
    final start = fixture.repository.start('project')
      ..setText('confirmed creation');
    await fixture.prepare(start);
    final ticket = start.submit();
    final begin = await fixture.creations.begins.at(0);
    final job = DraftCreationJob(
      begin.id,
      'project',
      begin.request.input.inputId,
    );
    begin.reply.complete(job);
    final value = StartNewThreadResult(
      thread: draftThread('created').copyWith(frozenModel: draftNativeRoute),
      receipt: SubmitPromptReceipt(
        threadId: 'created',
        inputId: begin.request.input.inputId,
        cursor: 7,
        requestDigest: draftDigest,
      ),
    );
    (await job.reads.at(0)).complete(value);
    final source = DraftCreatedSource('created', begin.request.input.inputId);
    (await job.sourceCalls.at(0)).complete(
      source,
    ); // Native result has already been consumed before this boundary.
    await source.feed.listened.future;
    final pressure = <ResourcePermit>[];
    addTearDown(() async {
      for (final permit in pressure) {
        permit.release();
      }
      // Failure cleanup only: unblock our own native close gates, then join.
      // The assertions below prove automatic cleanup before this close runs.
      final closing = fixture.repository.close();
      await job.closes.at(0);
      for (final call in job.closes.values) {
        if (!call.reply.isCompleted)
          call.reply.complete(
            FeedCloseReport(
              feedId: job.id.value,
              outcome: const FeedCloseOutcome.clean(),
            ),
          );
      }
      expect((await closing).complete, isTrue);
    });
    late final AcknowledgedSyncFailedCommandResult<StartNewThreadResult>
    business;
    try {
      final capacity = fixture.budget.capacities[ResourceKind.observer]!;
      while (fixture.budget.used(ResourceKind.observer) < capacity) {
        pressure.add(
          fixture.budget.acquire(
            ResourceKind.observer,
            owner: 'test-first-baseline-observer-pressure',
          ),
        );
      }
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
            value: draftExecution(),
          ),
        ),
      );
      final result = await ticket.result; // No observer-consuming waitFor while the real budget is exhausted.
      expect(
        result,
        isA<AcknowledgedSyncFailedCommandResult<StartNewThreadResult>>(),
      );
      business =
          result as AcknowledgedSyncFailedCommandResult<StartNewThreadResult>;
      fixture.retainedExecutionFailure = business.error;
      expect(business.value, value);
      expect(business.error.code, StudioFailureCode.overloaded);
      expect(ticket.state.value.acknowledged, isTrue);
      expect(ticket.state.value.observed, isFalse);
      expect(ticket.state.value.durable, isFalse);
    } finally {
      for (final permit in pressure) {
        permit.release();
      }
    }
    // This is the defect-sensitive barrier: no Repository.close/retryCleanup
    // has run. Background observer cleanup alone must not leave work retained.
    final automaticClose = await job.closes.at(0);
    expect(automaticClose.retry, isFalse);
    expect(
      ticket.state.observerCount,
      greaterThan(0),
      reason: 'The work still owns its watch while native close is pending',
    );
    expect(native.calls.values, isEmpty);
    expect(fixture.commands.acceptances.values, isEmpty);
    final released = Completer<void>();
    final watch = fixture.budget.watchAvailability(ResourceKind.observer, () {
      if (ticket.state.observerCount == 0 && !released.isCompleted)
        released.complete();
    });
    addTearDown(watch.cancel);
    automaticClose.reply.complete(
      FeedCloseReport(
        feedId: job.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    await released.future;
    expect(ticket.state.observerCount, 0);
    expect(job.progressSource.observerCount, 0);
    // Only after the actual work-watch release do we inspect public cleanup;
    // this call cannot be what unblocks the defect-sensitive release above.
    final settled = await fixture.repository.retryCleanup();
    expect(
      settled.unresolved.where(
        (resource) => resource.owner.contains(ticket.id.value),
      ),
      isEmpty,
    );
    expect(
      settled.unresolved
          .expand((resource) => resource.issues)
          .any((issue) => issue.diagnostic.code == 'inputEvidenceRetained'),
      isFalse,
    );
    expect(
      await ticket.result,
      business,
      reason: 'Cleanup cannot revoke or rewrite the known creation and its synchronization failure',
    );
    start.setText('still editable without Repository.close');
    expect(start.state.value.text, 'still editable without Repository.close');
    expect(fixture.creations.begins.values, hasLength(1));
    expect(fixture.creations.finds.values, isEmpty);
    expect(job.reads.values, hasLength(1));
    expect(job.sourceCalls.values, hasLength(1));
    expect(job.closes.values, hasLength(1));
    expect(source.opens, 1);
    expect(fixture.conversations.timeline.requests, isEmpty);
  });

  test('deferred UTF-8 input identity is exact and bounded; a matching started failure never loads its error body', () async {
    final fixture = await draftsFixture(clientId: ' 原e\u0301输入 ');
    final native = _TurnBoundary(fixture);
    final action = await _dispatch(fixture);
    final inputId = action.ticket.id.value;
    final bytes = utf8.encode(inputId).length;
    final wrongLengthSequence = await fixture.sendExecution(
      draftExecution(status: ThreadStatus.running, active: _turn(1)),
    );
    final wrongLength = await native.accept(
      0,
      inputId: ReadText.deferred(fieldId: 41, utf8Bytes: bytes + 1),
    );
    await fixture.execution!.feed.acknowledged(wrongLengthSequence);
    expect(
      wrongLength.texts.values,
      isEmpty,
      reason: 'Different original byte length proves another input without reading text',
    );
    expect(action.ticket.state.value.observed, isFalse);
    final mismatchSequence = await fixture.sendExecution(
      draftExecution(status: ThreadStatus.running, active: _turn(2)),
    );
    final mismatch = await native.accept(
      1,
      inputId: ReadText.deferred(fieldId: 42, utf8Bytes: bytes),
      scriptText: true,
    );
    final wrongText = await mismatch.texts.at(0);
    expect((wrongText.fieldId, wrongText.offset), (42, 0));
    expect(wrongText.maxBytes, inInclusiveRange(4, 262144));
    wrongText.reply.complete(
      TextChunk(
        fieldId: 42,
        offset: 0,
        text: inputId.replaceFirst(' ', '\t'),
        nextOffset: null,
      ),
    );
    await fixture.execution!.feed.acknowledged(mismatchSequence);
    expect(action.ticket.state.value.observed, isFalse);
    expect(action.ticket.state.value.effective, isFalse);
    const failedBrief = TurnBriefState.failed(
      startedAt: 1,
      completedAt: 2,
      category: TurnFailureCategory.internal,
      providerKind: null,
      httpStatus: null,
      retry: RetryDisposition.permanent(),
    );
    final fact = _turn(3, state: failedBrief);
    final matchingSequence = await fixture.sendExecution(
      draftExecution(
        status: ThreadStatus.faulted,
        active: fact,
        terminal: fact,
      ),
    ); // Same original ref in both slots must be read once.
    final matching = await native.accept(
      2,
      inputId: ReadText.deferred(fieldId: 43, utf8Bytes: bytes),
      scriptText: true,
      state: const TurnReadState.failed(
        startedAt: 1,
        completedAt: 2,
        failure: TurnFailureRead(
          category: TurnFailureCategory.internal,
          providerKind: null,
          code: null,
          httpStatus: null,
          message: ReadText.deferred(fieldId: 61, utf8Bytes: 100000),
          retry: RetryDisposition.permanent(),
        ),
      ),
    );
    final first = await matching.texts.at(0);
    expect((first.fieldId, first.offset), (43, 0));
    first.reply.complete(
      const TextChunk(fieldId: 43, offset: 0, text: ' 原', nextOffset: 4),
    );
    final rest = await matching.texts.at(1);
    expect(
      (rest.fieldId, rest.offset),
      (43, 4),
      reason: 'Offsets count original UTF-8 bytes, not code points or normalized characters',
    );
    rest.reply.complete(
      TextChunk(
        fieldId: 43,
        offset: 4,
        text: inputId.substring(2),
        nextOffset: null,
      ),
    );
    await Future.any<void>([
      fixture.execution!.feed.acknowledged(matchingSequence),
      matching.texts.at(2).then<void>((extra) {
        fixture.retainedExecutionFailure = _headerFailure;
        extra.reply.completeError(_headerFailure);
        fail(
          'Only the original inputId bytes may be read; unexpected extra field ${extra.fieldId}',
        );
      }),
    ]);
    expect(action.ticket.state.value.observed, isTrue);
    expect(action.ticket.state.value.effective, isTrue);
    expect(action.ticket.state.value.durable, isFalse);
    expect(
      native.calls.values,
      hasLength(3),
      reason: 'Duplicate active/recent ref is one bounded original read',
    );
    expect(matching.texts.values.map((call) => call.fieldId), [43, 43]);
    expect(matching.texts.values.any((call) => call.fieldId == 61), isFalse);
    _noReplayOrTimeline(fixture);
  });

  for (final lateOpen in [true, false]) {
    test(
      'history durability cannot release a ${lateOpen ? 'late original open' : 'waiting original header'} before close joins it; cleanup retries the same handle',
      () async {
        final fixture = await draftsFixture();
        final native = _TurnBoundary(fixture);
        final action = await _dispatch(fixture, holdHistory: true);
        final sequence = await fixture.sendExecution(
          draftExecution(status: ThreadStatus.running, active: _turn(1)),
        );
        await native.calls.at(
          0,
        ); // External open has actually entered in both variants.
        final gate = Completer<TurnReadHeader>();
        DraftTurnPin? pin;
        if (!lateOpen) {
          pin = await native.accept(
            0,
            inputId: ReadText.inline(text: action.ticket.id.value),
            headerReply: gate,
            manualClose: true,
          );
          await pin.entered.future;
        }
        expect(_turnUsage(fixture), hasLength(1));
        expect(
          fixture.execution!.feed.acknowledgements,
          isNot(contains(sequence)),
        );
        final history = fixture.commands.acceptances.values.single;
        history.reply.complete(
          const InputAcceptanceEvidence(
            acceptedSequence: 7,
            requestDigest: draftDigest,
            disposition: PersistedInputDisposition.consumed,
          ),
        );
        await action.ticket.state.waitFor((state) => state.durable);
        expect(
          _turnUsage(fixture),
          hasLength(1),
          reason:
              'Durable evidence does not finish an already-admitted Turn query',
        );
        var completed = false;
        final closing = fixture.repository.close().then((report) {
          completed = true;
          return report;
        });
        final snapshot = await fixture.repository.close(
          deadline: DateTime.utc(2000),
        );
        expect(
          snapshot.complete,
          isFalse,
          reason: 'The deadline only observes actual entered work; the original unbounded close is still joining it',
        );
        expect(completed, isFalse);
        final originalPin =
            pin ??
            await native.accept(
              0,
              inputId: ReadText.inline(text: action.ticket.id.value),
              manualClose: true,
            );
        final nativeClose = await originalPin.closes.at(0);
        expect(_turnUsage(fixture), hasLength(1));
        nativeClose.reply.complete(
          FeedCloseReport(
            feedId: originalPin.value.scope.scopeId,
            outcome: FeedCloseOutcome.unresolved(issues: [_retryIssue]),
          ),
        );
        if (!lateOpen) gate.complete(originalPin.value);
        final unresolved = await closing;
        expect(unresolved.complete, isFalse);
        expect(
          unresolved.unresolved.expand((item) => item.issues),
          contains(_retryIssue),
        );
        expect(_turnUsage(fixture).single.phase, ResourcePhase.unresolved);
        expect(originalPin.headerCalls, lateOpen ? 0 : greaterThan(0));
        final released = Completer<void>();
        final watch = fixture.budget.watchAvailability(
          ResourceKind.readModel,
          () {
            if (fixture.budget.usage.every(
                  (usage) => usage.owner != 'drafts-repository',
                ) &&
                !released.isCompleted)
              released.complete();
          },
        );
        addTearDown(watch.cancel);
        final retrying = fixture.repository.retryCleanup();
        final retry = await originalPin.closes.at(1);
        expect(retry.retry, isTrue);
        retry.reply.complete(
          FeedCloseReport(
            feedId: originalPin.value.scope.scopeId,
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
        await released
            .future; // Real permit release, not a sleep or a second fake join.
        await retrying;
        expect((await fixture.repository.retryCleanup()).complete, isTrue);
        expect(_turnUsage(fixture), isEmpty);
        expect(native.calls.values, hasLength(1));
        expect(action.ticket.state.value.durable, isTrue);
        _noReplayOrTimeline(fixture);
      },
    );
  }

  test('a native Turn header failure is not ACKed, preserves its typed diagnostic and never resubmits Unknown input', () async {
    final fixture = await draftsFixture();
    fixture.protectUnknown = true;
    fixture.retainedExecutionFailure = _headerFailure;
    final native = _TurnBoundary(fixture);
    final composer = await fixture.composer();
    composer.setText('possibly dispatched');
    final ticket = composer.submit();
    final prompt = await fixture.commands.prompts.at(0);
    final sequence = await fixture.sendExecution(
      draftExecution(status: ThreadStatus.running, active: _turn(1)),
    );
    final gate = Completer<TurnReadHeader>();
    final pin = await native.accept(
      0,
      inputId: ReadText.inline(text: ticket.id.value),
      headerReply: gate,
    );
    await pin.entered.future;
    gate.completeError(_headerFailure);
    await ticket.state.waitFor(
      (state) => state.evidenceError == _headerFailure,
    );
    await fixture.execution!.feed.closeStarted.future;
    expect(ticket.state.value.evidenceError, same(_headerFailure));
    expect(fixture.execution!.feed.acknowledgements, isNot(contains(sequence)));
    expect(ticket.state.value.observed, isFalse);
    prompt.reply.completeError(
      const CommandDispatchFailure.unknownOutcome(failure: _headerFailure),
    );
    final original = await ticket.result;
    expect(original, isA<UnknownOutcomeCommandResult<SubmitPromptReceipt>>());
    expect(
      (original as UnknownOutcomeCommandResult<SubmitPromptReceipt>).error,
      same(_headerFailure),
    );
    expect((await fixture.repository.close()).complete, isFalse);
    expect((await fixture.repository.retryCleanup()).complete, isFalse);
    expect(await ticket.result, original);
    expect(native.calls.values, hasLength(1));
    expect(pin.texts.values, isEmpty);
    _noReplayOrTimeline(fixture);
  });

  test('a replacement execution attempt cannot lend its baseline or a late old header to the original input owner', () async {
    final fixture = await draftsFixture();
    final native = _TurnBoundary(fixture);
    final action = await _dispatch(fixture);
    final session = fixture.conversations.repository.existingSession('thread')!;
    final sequence = await fixture.sendExecution(
      draftExecution(status: ThreadStatus.running, active: _turn(1)),
    );
    final gate = Completer<TurnReadHeader>();
    final old = await native.accept(
      0,
      inputId: ReadText.inline(text: action.ticket.id.value),
      headerReply: gate,
    );
    await old.entered.future;
    final originalFeed = fixture.execution!.feed;
    expect(originalFeed.acknowledgements, isNot(contains(sequence)));
    await session.retry(
      ThreadFacet.execution,
    ); // Explicit source attempt replacement, never a replay of submit.
    final replacement = await fixture.conversations.facets.executionOpened(1);
    await replacement.feed.listened.future;
    replacement.feed.emit(
      ThreadExecutionFrame.data(
        deliverySequence: 1,
        event: ThreadExecutionEvent.baseline(
          identity: draftFeed(
            replacement.feed.feedId,
            ThreadFacet.execution,
            replacement.mode,
          ),
          stamp: draftFacet(ThreadFacet.execution, 1),
          value: draftExecution(status: ThreadStatus.running, active: _turn(1)),
        ),
      ),
    );
    await replacement.feed.acknowledged(1);
    expect(
      native.calls.values,
      hasLength(1),
      reason: 'The invalidated old submission lease cannot read from the new attempt',
    );
    expect(action.ticket.state.value.observed, isFalse);
    expect(action.ticket.state.value.effective, isFalse);
    final failure = action.ticket.state.value.evidenceError;
    expect(failure?.code, StudioFailureCode.superseded);
    final released = Completer<void>();
    final watch = fixture.budget.watchAvailability(ResourceKind.readModel, () {
      if (_turnUsage(fixture).isEmpty && !released.isCompleted)
        released.complete();
    });
    addTearDown(watch.cancel);
    gate.complete(old.value);
    await released.future;
    expect(
      action.ticket.state.value.observed,
      isFalse,
      reason: 'A matching but retired-attempt late header is not current input evidence',
    );
    expect(action.ticket.state.value.evidenceError, failure);
    expect(originalFeed.acknowledgements, isNot(contains(sequence)));
    expect(
      fixture.conversations.repository.existingSession('thread'),
      same(session),
    );
    expect(fixture.conversations.facets.execution, hasLength(2));
    _noReplayOrTimeline(fixture);
  });

  test('a throwing evidence notification keeps its original result and retries after reentrant close without clearing a native terminal issue', () async {
    late _OperationBoundary boundary;
    final fixture = await draftsFixture(
      decorateOperations: (original) => boundary = _OperationBoundary(original),
    );
    final action = await _dispatch(fixture);
    final business = await action.ticket.result;
    final notifications = <StudioFailure>[];
    final entered = Completer<void>();
    Future<CloseReport>? firstClose;
    Future<CloseReport>? reentrantRetry;
    addTearDown(() async {
      boundary.afterEvidence = null;
      await fixture.repository.retryCleanup();
    });
    boundary.afterEvidence = (failure) {
      notifications.add(failure);
      if (notifications.length != 1) return;
      // Both public calls enter while the original Session callback is running.
      // Neither may turn this same pass's new notification failure into a loop.
      firstClose = fixture.repository.close();
      reentrantRetry = fixture.repository.retryCleanup();
      entered.complete();
      throw _notificationFailure;
    };
    final originalFeed = fixture.execution!.feed;
    fixture.retainedExecutionFailure = _sourceFailure;
    originalFeed.outcome = FeedCloseOutcome.unresolved(
      issues: [_terminalIssue],
    );
    originalFeed.emit(
      ThreadExecutionFrame.failure(
        identity: draftFeed(
          originalFeed.feedId,
          ThreadFacet.execution,
          fixture.execution!.mode,
        ),
        error: _sourceFailure,
      ),
    );
    await entered.future;
    final unresolved = await firstClose!;
    final notificationIssue = _cleanupIssue(
      'submissionEvidenceFailure',
      _notificationFailure,
    );
    expect(_issues(unresolved), contains(notificationIssue));
    expect(_issues(await reentrantRetry!), contains(notificationIssue));
    expect(
      notifications,
      hasLength(1),
      reason: 'A reentrant retry joins the initial failed notification pass',
    );
    expect(notifications.single, same(_sourceFailure));
    expect(_inputUsage(fixture, action.ticket.id), hasLength(1));
    expect(
      boundary.watches.every((watch) => !watch.isCancelled),
      isTrue,
      reason: 'An unresolved Session notification still owns the real operation watches',
    );
    expect(action.ticket.state.value.evidenceError, same(_sourceFailure));
    expect(await action.ticket.result, same(business));

    final recovered = await fixture.repository.retryCleanup();
    expect(
      recovered.complete,
      isTrue,
      reason: 'Successful re-notification clears its RetryClose item and permits the original evidence/work to release',
    );
    expect(notifications, hasLength(2));
    expect(
      notifications.every((failure) => identical(failure, _sourceFailure)),
      isTrue,
    );
    expect(_inputUsage(fixture, action.ticket.id), isEmpty);
    expect(
      fixture.budget.usage.any((usage) => usage.owner == 'drafts-repository'),
      isFalse,
    );
    expect(
      boundary.watches.map((watch) => (watch.isCancelled, watch.cancelCalls)),
      [(true, 1), (true, 1)],
    );
    expect(
      fixture.conversations.operations.observations
          .lookup(action.ticket.id)!
          .state
          .value,
      action.ticket.state.value,
      reason: 'The real Registry remains the only canonical operation state',
    );
    expect(action.ticket.state.value.evidenceError, same(_sourceFailure));
    expect(await action.ticket.result, same(business));
    expect(
      _issues(unresolved),
      contains(notificationIssue),
      reason: 'Recovery does not rewrite the first captured failure report',
    );
    expect((await fixture.repository.close()).complete, isTrue);
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(
      notifications,
      hasLength(2),
      reason: 'An already successful callback is not notified again',
    );

    // This is an independently scripted *real native close* result, not the
    // notification error. Recovering the latter cannot manufacture native Clean.
    await originalFeed.closeStarted.future;
    final conversationClose = await fixture.conversations.repository.close();
    expect(_issues(conversationClose), contains(_terminalIssue));
    final conversationRetry = await fixture.conversations.repository
        .retryCleanup();
    expect(_issues(conversationRetry), contains(_terminalIssue));
    expect(originalFeed.closeCalls, 1);
    expect(
      originalFeed.retryCloseCalls,
      0,
      reason: 'A terminal-only native issue is not a RetryClose obligation',
    );
    expect(await action.ticket.result, same(business));
    _noReplayOrTimeline(fixture);
  });

  test('the real public submission lease joins reentrant retry before the first failure becomes retryable', () async {
    final fixture = await draftsFixture();
    await fixture.composer();
    final session = fixture.conversations.repository.existingSession('thread')!;
    final origin = session.execution.value.stamp!;
    final lease = fixture.conversations.demand.retainForSubmission(
      session,
      expectedOrigin: origin,
    );
    expect(await lease.ready, origin);
    final notifications = <StudioFailure>[];
    final rounds = <Future<CloseReport>>[];
    final entered = Completer<void>();
    addTearDown(() async {
      lease.release();
      await lease.closeTurnReads(retry: true);
      await Future.wait(rounds);
    });
    lease.bindExecutionTurns(
      consume: (original, stamp, turns) async {},
      onFailure: (failure) {
        notifications.add(failure);
        // This is the actual factory-returned composition lease, not a fake
        // observer/lease or a replacement for a Drafts submission in the test above.
        rounds.add(lease.closeTurnReads(retry: true));
        rounds.add(lease.closeTurnReads(retry: true));
        lease.release();
        if (notifications.length == 1) {
          entered.complete();
          throw _notificationFailure;
        }
      },
    );
    final originalFeed = fixture.execution!.feed;
    originalFeed.emit(
      ThreadExecutionFrame.failure(
        identity: draftFeed(
          originalFeed.feedId,
          ThreadFacet.execution,
          fixture.execution!.mode,
        ),
        error: _sourceFailure,
      ),
    );
    await entered.future;
    final first = await Future.wait(List.of(rounds));
    final issue = _cleanupIssue(
      'submissionEvidenceFailure',
      _notificationFailure,
    );
    expect(first, hasLength(2));
    expect(first.every((report) => _issues(report).contains(issue)), isTrue);
    expect(
      notifications,
      hasLength(1),
      reason:
          'The new failure was not present when either reentrant retry entered',
    );
    expect(_issues(await lease.closeTurnReads()), contains(issue));
    expect(
      notifications,
      hasLength(1),
      reason: 'Ordinary close is not an explicit retry of a failed callback',
    );

    expect((await lease.closeTurnReads(retry: true)).complete, isTrue);
    expect(notifications, hasLength(2));
    expect(
      notifications.every((failure) => identical(failure, _sourceFailure)),
      isTrue,
    );
    expect(
      (await Future.wait(rounds)).skip(2).every((report) => report.complete),
      isTrue,
    );
    expect(
      await lease.ready,
      origin,
      reason:
          'The original ready result is not rewritten by failure or cleanup',
    );
    expect(
      (await fixture.conversations.repository.close()).complete,
      isTrue,
      reason: 'The real Session can join only after its originally retained lease has actually released',
    );
    expect((await lease.closeTurnReads(retry: true)).complete, isTrue);
    expect(notifications, hasLength(2));
    expect(fixture.commands.prompts.values, isEmpty);
  });

  test('a failed operation-watch cancel waits for real history and explicit retries recognize a partial cancellation before releasing evidence', () async {
    late _OperationBoundary boundary;
    final fixture = await draftsFixture(
      decorateOperations: (original) => boundary = _OperationBoundary(original),
    );
    final action = await _dispatch(fixture, holdHistory: true);
    final business = await action.ticket.result;
    final history = fixture
        .commands
        .acceptances
        .values
        .single; // The real query is already waiting at the port.
    final session = fixture.conversations.repository.existingSession('thread')!;
    expect(boundary.watches, hasLength(2));
    final workWatch = boundary.watches.first;
    final evidenceWatch = boundary.watches.last;
    final reentrant = <Future<CloseReport>>[];
    addTearDown(() async {
      evidenceWatch.beforeCancel = null;
      evidenceWatch.afterCancel = null;
      if (!history.reply.isCompleted)
        history.reply.completeError(_historyFailure);
      await fixture.repository.retryCleanup();
      await Future.wait(reentrant);
    });
    evidenceWatch.beforeCancel = () {
      if (evidenceWatch.cancelCalls != 1) return;
      reentrant.add(fixture.repository.retryCleanup());
      throw _cancelFailure;
    };
    evidenceWatch.afterCancel = () {
      if (evidenceWatch.cancelCalls != 2) return;
      reentrant.add(fixture.repository.retryCleanup());
      throw _partialCancelFailure;
    };

    var closed = false;
    final closing = fixture.repository.close().then((report) {
      closed = true;
      return report;
    });
    expect(
      session.execution.observerCount,
      0,
      reason: 'The real execution watch has already cancelled successfully',
    );
    expect(
      evidenceWatch.cancelCalls,
      0,
      reason:
          'Operation-watch release cannot overtake the entered history query',
    );
    expect(_inputUsage(fixture, action.ticket.id), hasLength(1));
    expect(closed, isFalse);
    history.reply.completeError(_historyFailure);
    final first = await closing;
    final firstIssue = _cleanupIssue(
      'inputIdentityOperationWatch',
      _cancelFailure,
    );
    expect(_issues(first), contains(firstIssue));
    expect(_issues(await reentrant.single), contains(firstIssue));
    expect(
      evidenceWatch.cancelCalls,
      1,
      reason: 'Ordinary close/reentry does not keep retrying its new failure',
    );
    expect(evidenceWatch.isCancelled, isFalse);
    expect(action.ticket.state.observerCount, 2);
    expect(workWatch.isCancelled, isFalse);
    expect(
      _inputUsage(fixture, action.ticket.id).single.phase,
      ResourcePhase.unresolved,
    );
    expect(action.ticket.state.value.evidenceError, same(_historyFailure));
    expect(await action.ticket.result, same(business));

    final partial = await fixture.repository.retryCleanup();
    final partialIssue = _cleanupIssue(
      'inputIdentityOperationWatch',
      _partialCancelFailure,
    );
    expect(_issues(partial), contains(partialIssue));
    expect(_issues(await reentrant.last), contains(partialIssue));
    expect(
      evidenceWatch.cancelCalls,
      2,
      reason:
          'This explicit pass attempts the previously failed stage only once',
    );
    expect(
      evidenceWatch.isCancelled,
      isTrue,
      reason:
          'The actual Registry watch cancelled before the environment threw',
    );
    expect(action.ticket.state.observerCount, 1);
    expect(workWatch.isCancelled, isFalse);
    expect(
      _inputUsage(fixture, action.ticket.id).single.phase,
      ResourcePhase.unresolved,
      reason: 'A partial side effect is not yet a successfully completed cleanup stage',
    );
    expect(action.ticket.state.value.evidenceError, same(_historyFailure));
    expect(await action.ticket.result, same(business));

    final released = Completer<void>();
    final releaseWatch = fixture.budget.watchAvailability(
      ResourceKind.readModel,
      () {
        if (fixture.budget.usage.every(
              (usage) => usage.owner != 'drafts-repository',
            ) &&
            !released.isCompleted)
          released.complete();
      },
    );
    addTearDown(releaseWatch.cancel);
    final retrying = fixture.repository.retryCleanup();
    await released.future; // Actual repository permit release follows evidence/work settlement.
    expect((await retrying).complete, isTrue);
    expect(
      evidenceWatch.cancelCalls,
      2,
      reason: 'isCancelled prevents repeating the already-realized cancellation side effect',
    );
    expect(workWatch.cancelCalls, 1);
    expect(workWatch.isCancelled, isTrue);
    expect(action.ticket.state.observerCount, 0);
    expect(session.execution.observerCount, 0);
    expect(_inputUsage(fixture, action.ticket.id), isEmpty);
    expect(_issues(first), contains(firstIssue));
    expect(_issues(partial), contains(partialIssue));
    expect(action.ticket.state.value.evidenceError, same(_historyFailure));
    expect(await action.ticket.result, same(business));
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect((workWatch.cancelCalls, evidenceWatch.cancelCalls), (1, 2));
    expect(fixture.commands.acceptances.values, hasLength(1));
    _noReplayOrTimeline(fixture);
  });
}
