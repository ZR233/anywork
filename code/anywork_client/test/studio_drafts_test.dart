import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:test/test.dart';

import 'support/configuration_start_fixture.dart';
import 'support/drafts_fixture.dart';
import 'support/drafts_native_fixture.dart';

Future<void> _acknowledge(
  DraftsFixture fixture,
  OperationTicket<SubmitPromptReceipt> ticket,
  DraftPromptCall call, {
  InputAcceptanceEvidence? evidence,
}) async {
  final index = fixture.commands.acceptances.values.length;
  call.reply.complete(fixture.receipt(call));
  final read = await fixture.commands.acceptances.at(index);
  expect((read.threadId, read.inputId), (call.threadId, call.input.inputId));
  read.reply.complete(evidence);
  expect(
    await ticket.result,
    isA<AcknowledgedCommandResult<SubmitPromptReceipt>>(),
  );
  if (evidence != null) await ticket.state.waitFor((state) => state.durable);
}

Future<DraftCreationJob> _acceptedCreation(
  DraftsFixture fixture,
  OperationTicket<StartNewThreadResult> ticket, {
  String threadId = 'created',
  WorkspaceThreadRecord? nativeThread,
}) async {
  final begin = await fixture.creations.begins.at(0);
  expect(begin.id, ticket.id);
  final job = DraftCreationJob(
    begin.id,
    begin.request.projectId,
    begin.request.input.inputId,
  );
  begin.reply.complete(job);
  final result = StartNewThreadResult(
    thread:
        nativeThread ??
        draftThread(threadId, projectId: begin.request.projectId).copyWith(
          delegationPreference: DelegationPreference.economy,
          frozenModel: draftNativeRoute,
        ),
    receipt: SubmitPromptReceipt(
      threadId: threadId,
      inputId: begin.request.input.inputId,
      cursor: 7,
      requestDigest: draftDigest,
    ),
  );
  final evidenceIndex = fixture.commands.acceptances.values.length;
  (await job.reads.at(0)).complete(result);
  final source = DraftCreatedSource(threadId, begin.request.input.inputId);
  (await job.sourceCalls.at(0)).complete(source);
  await emitCreatedBaseline(source);
  final evidence = await fixture.commands.acceptances.at(evidenceIndex);
  evidence.reply.complete(
    const InputAcceptanceEvidence(
      acceptedSequence: 7,
      requestDigest: draftDigest,
      disposition: PersistedInputDisposition.consumed,
    ),
  );
  expect(
    await ticket.result,
    isA<AcknowledgedCommandResult<StartNewThreadResult>>(),
  );
  await ticket.state.waitFor((state) => state.durable);
  final closing = await job.closes.at(0);
  closing.reply.complete(
    FeedCloseReport(
      feedId: job.id.value,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
  return job;
}

void main() {
  test('public factory and borrowed handles do not open IO, Sessions or native commands', () async {
    final fixture = DraftsFixture();
    addTearDown(fixture.close);
    fixture.repository.composer('thread');
    fixture.repository.start('project');
    expect(fixture.configuration.owner.port.feeds, isEmpty);
    expect(fixture.directory.projectOpens.values, isEmpty);
    expect(fixture.directory.threadOpens.values, isEmpty);
    expect(fixture.conversations.repository.existingSession('thread'), isNull);
    expect(fixture.conversations.facets.execution, isEmpty);
    expect(fixture.attachments.begins.values, isEmpty);
    expect(fixture.creations.begins.values, isEmpty);
    expect(fixture.commands.prompts.values, isEmpty);
  });

  test('Composer freezes the original incarnation, route and refs before preparation; old ACK preserves newer edits', () async {
    final fixture = await draftsFixture();
    final composer = await fixture.composer();
    await fixture.admit(composer.addLocalFiles(['/declared/original']), [
      draftFile('original'),
    ]);
    composer.setText(' revision 8 ');
    final entered = Completer<void>();
    final preparation = Completer<void>();
    final ticket = composer.submit(
      preparePresentation: () {
        entered.complete();
        return preparation.future;
      },
    );
    await entered.future;
    expect(fixture.commands.prompts.values, isEmpty);
    composer.setText('revision 9');
    await fixture.admit(
      composer.addRemoteUrl('https://attachment.invalid/new'),
      [draftFile('new')],
    );
    final newer = composer.state.value;
    await fixture.emitRoute(99);
    fixture.conversations.select(
      'other-thread',
    ); // Evidence retains the concrete original Session.
    preparation.complete();
    final call = await fixture.commands.prompts.at(0);
    expect(call.threadId, 'thread');
    expect(call.input.inputId, ticket.id.value);
    expect(call.input.text, 'revision 8');
    expect(call.input.attachmentDraftIds, ['original']);
    expect(call.routeRevision, 8);
    await _acknowledge(fixture, ticket, call);
    expect(composer.state.value.text, newer.text);
    expect(composer.state.value.stamp, newer.stamp);
    expect(composer.state.value.attachments, newer.attachments);
    expect(ticket.state.value.observed, isFalse);
    expect(ticket.state.value.effective, isFalse);
    expect(ticket.state.value.durable, isFalse);
    expect(fixture.attachments.removals.values, isEmpty);
    // New draft still owns both files. Explicit discard, not old ACK, deletes.
    final discard = composer.discard();
    for (var index = 0; index < 2; index++) {
      final remove = await fixture.attachments.removals.at(index);
      expect(['original', 'new'], contains(remove.id));
      remove.reply.complete(
        false,
      ); // Already absent is also successful cleanup.
    }
    expect(await discard.result, isA<AcknowledgedCommandResult<Unit>>());
    expect(
      fixture.attachments.removals.values.map((call) => call.id),
      unorderedEquals(['original', 'new']),
    );
  });

  test('Start submit requires an explicitly materialized compatible route and freezes all fields without Settings writes', () async {
    final fixture = await draftsFixture();
    await fixture.selectStart();
    fixture.repository.setStartModel(
      ThreadModeId.task,
      'start-account',
      'native-model',
    );
    fixture.repository.setStartEffort(ThreadModeId.task, 'raw effort');
    final start = fixture.repository.start('project');
    start.setMode(ThreadModeId.task);
    start.setWorkspaceMode(ThreadWorkspaceMode.worktree);
    start.setDelegationMode(DelegationMode.profile);
    start.setDelegationPreference(DelegationPreference.fast);
    start.setText(' frozen creation ');
    await fixture.admit(start.addLocalFiles(['/declared/start']), [
      draftFile('start-file'),
    ]);
    final rejected = start.submit();
    expect(
      await rejected.result,
      isA<RejectedCommandResult<StartNewThreadResult>>(),
    );
    expect(fixture.creations.begins.values, isEmpty);
    expect(start.state.value.text, ' frozen creation ');
    const route = ModelSelection(
      model: AccountModelKey(
        accountId: 'start-account',
        modelId: 'native-model',
      ),
      effort: 'raw effort',
    );
    await fixture.prepare(start, route: route);
    final ready =
        start.state.value.routePreparation as ReadyStartRoutePreparation;
    expect(ready.result.sources, startSources());
    final ticket = start.submit();
    final begin = await fixture.creations.begins.at(0);
    final request = begin.request;
    expect(request.projectId, 'project');
    expect(request.input.text, 'frozen creation');
    expect(request.input.inputId, ticket.id.value);
    expect(request.input.attachmentDraftIds, ['start-file']);
    expect(request.mode, ThreadModeId.task);
    expect(request.route, route);
    expect(request.workspaceMode, ThreadWorkspaceMode.worktree);
    expect(request.delegationMode, DelegationMode.profile);
    expect(request.delegationPreference, DelegationPreference.fast);
    start.setText('newer text');
    start.setWorkspaceMode(ThreadWorkspaceMode.local);
    start.setDelegationMode(null);
    start.setDelegationPreference(null);
    fixture.repository.start('other').setText('other project');
    await fixture.configuration.owner.port.publishPair(
      startSources(pairRevision: 8, catalogRevision: 41),
    );
    await _acceptedCreation(
      fixture,
      ticket,
      nativeThread: draftThread('created').copyWith(
        mode: ThreadModeId.task,
        workspaceMode: ThreadWorkspaceMode.worktree,
        delegationMode: DelegationMode.profile,
        delegationPreference: DelegationPreference.fast,
        frozenModel: route,
      ),
    );
    expect(
      fixture.creations.begins.values,
      hasLength(1),
      reason: 'Source replacement must not substitute or redispatch the already-frozen creation',
    );
    expect(start.state.value.text, 'newer text');
    expect(start.state.value.attachments, [draftFile('start-file')]);
    expect(fixture.repository.start('other').state.value.text, 'other project');
    expect(fixture.workspace.state.value.selection.threadId, 'created');
    expect(fixture.configuration.owner.port.saves, isEmpty);
    expect(fixture.configuration.owner.port.enabledChanges, isEmpty);
    expect(fixture.configuration.owner.port.billingChanges, isEmpty);
    expect(
      fixture.configuration.owner.operations.observations.records.value,
      isEmpty,
      reason: 'Start editing/preparation/creation must not issue any Configuration command, including rejected narrow fields',
    );
    final discard = start.discard();
    (await fixture.attachments.removals.at(0)).reply.complete(true);
    await discard.result;
  });

  test('A to B to A navigation is a newer real selection intent, not permission for old creation to navigate', () async {
    final fixture = await draftsFixture();
    await fixture.selectStart();
    final start = fixture.repository.start('project')..setText('create');
    await fixture.prepare(start);
    final ticket = start.submit();
    final begin = await fixture.creations.begins.at(0);
    expect(start.state.value.delegationModeOverride, isNull);
    expect(start.state.value.delegationPreferenceOverride, isNull);
    expect(begin.request.delegationMode, draftDefaults.mode);
    expect(begin.request.delegationPreference, draftDefaults.preference);
    final originalGeneration =
        fixture.workspace.state.value.selectionGeneration;
    await fixture.selectStart('other');
    await fixture.selectStart('project');
    final current = fixture.workspace.state.value;
    expect(current.selectionGeneration, greaterThan(originalGeneration));
    await _acceptedCreation(fixture, ticket);
    expect(fixture.workspace.state.value, current);
    expect(start.state.value.text, isEmpty);
    expect(fixture.creations.begins.values, hasLength(1));
  });

  test('a replaced Rust-issued pair invalidates ready Start material instead of submitting after an awaited resolver', () async {
    final fixture = await draftsFixture();
    await fixture.selectStart();
    final start = fixture.repository.start('project')
      ..setText('keep raw draft');
    await fixture.prepare(start);
    final replacement = startSources(pairRevision: 8, catalogRevision: 41);
    await fixture.configuration.owner.port.publishPair(replacement);
    expect(
      start.state.value.routePreparation,
      isA<UnreadStartRoutePreparation>(),
    );
    final rejected = start.submit();
    expect(
      await rejected.result,
      isA<RejectedCommandResult<StartNewThreadResult>>(),
    );
    expect(fixture.creations.begins.values, isEmpty);
    expect(
      fixture.configuration.opens,
      hasLength(1),
      reason: 'submit never starts an asynchronous resolver',
    );
    expect(start.state.value.text, 'keep raw draft');
    final preparing = start.prepareRoute();
    final pin = (await fixture.configuration.opened(1)).accept();
    final query = await pin.called(0);
    query.reply.complete(
      StartRouteRead.ready(
        sources: replacement,
        query: query.query,
        intent: query.query.intent,
        route: draftNativeRoute,
        defaults: draftDefaults,
      ),
    );
    await preparing;
    final current = start.submit();
    final begin = await fixture.creations.begins.at(0);
    begin.reply.completeError(
      const CommandDispatchFailure.rejected(failure: draftFailure),
    );
    expect(
      await current.result,
      isA<RejectedCommandResult<StartNewThreadResult>>(),
    );
    expect(
      fixture.creations.finds.values,
      isEmpty,
      reason: 'Explicitly rejected begin issued no creation handle',
    );
  });

  test('a late native model suggestion cannot overwrite newer raw effort intent or authorize a stale Start submit', () async {
    final fixture = await draftsFixture();
    final start = fixture.repository.start('project')..setText('raw draft');
    fixture.repository.setStartModel(
      ThreadModeId.simple,
      'start-account',
      'native-model',
    );
    final original = start.prepareRoute();
    final superseded = expectLater(
      original,
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.superseded,
        ),
      ),
    );
    final pin = (await fixture.configuration.opened(0)).accept();
    final suggestion = await pin.called(0);
    expect(suggestion.query, isA<SelectModelStartRouteQuery>());
    fixture.repository.setStartEffort(
      ThreadModeId.simple,
      ' newer raw effort ',
    );
    final nativeIntent = suggestion.query.intent.copyWith(
      model: draftNativeRoute.model,
      effort: 'native-effort',
    );
    suggestion.reply.complete(
      StartRouteRead.ready(
        sources: pin.originalHeader,
        query: suggestion.query,
        intent: nativeIntent,
        route: draftNativeRoute,
        defaults: draftDefaults,
      ),
    );
    await superseded;
    expect(
      fixture.repository.startRoutes.value.efforts[ThreadModeId.simple.id],
      ' newer raw effort ',
    );
    expect(
      start.state.value.routePreparation,
      isA<UnreadStartRoutePreparation>(),
    );
    final current = start.prepareRoute();
    final resolve = await pin.called(1);
    expect(resolve.query, isA<ResolveStartRouteQuery>());
    expect(resolve.query.intent.effort, ' newer raw effort ');
    resolve.reply.complete(
      StartRouteRead.ready(
        sources: pin.originalHeader,
        query: resolve.query,
        intent: resolve.query.intent,
        route: draftNativeRoute.copyWith(effort: ' newer raw effort '),
        defaults: draftDefaults,
      ),
    );
    await current;
    expect(
      (start.state.value.routePreparation as ReadyStartRoutePreparation)
          .result
          .intent
          .effort,
      ' newer raw effort ',
    );
    expect(fixture.configuration.owner.port.saves, isEmpty);
    expect(fixture.creations.begins.values, isEmpty);
  });

  test('a known creation preparation rejection retains its stage and newer draft; late progress cannot revive it', () async {
    final fixture = await draftsFixture();
    await fixture.selectStart();
    final start = fixture.repository.start('project')..setText('original');
    await fixture.admit(start.addLocalFiles(['/declared/preparation']), [
      draftFile('preparation'),
    ]);
    await fixture.prepare(start);
    final ticket = start.submit();
    final begin = await fixture.creations.begins.at(0);
    final job = DraftCreationJob(
      begin.id,
      begin.request.projectId,
      begin.request.input.inputId,
    );
    begin.reply.complete(job);
    final result = await job.reads.at(0);
    final progress = ThreadPreparationProgress(
      projectId: 'project',
      inputId: begin.request.input.inputId,
      stage: ThreadPreparationStage.creatingWorktree,
      workspacePath: '/declared/tree',
      branch: 'declared-branch',
    );
    job.progressSource.publish(progress);
    start.setText('newer');
    result.completeError(
      const CommandDispatchFailure.rejected(failure: draftFailure),
    );
    expect(
      await ticket.result,
      isA<RejectedCommandResult<StartNewThreadResult>>(),
    );
    final closing = await job.closes.at(0);
    final failed = start.state.value;
    expect(failed.preparation?.phase, NewThreadPreparationPhase.failed);
    expect(failed.preparation?.progress, progress);
    expect(failed.preparation?.failure, draftFailure);
    job.progressSource.publish(
      progress.copyWith(stage: ThreadPreparationStage.submittingPrompt),
    );
    expect(start.state.value, failed);
    closing.reply.complete(
      FeedCloseReport(
        feedId: job.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect(failed.text, 'newer');
    expect(failed.attachments, [draftFile('preparation')]);
    final discard = start.discard();
    (await fixture.attachments.removals.at(0)).reply.complete(true);
    await discard.result;
  });

  test('ending progress is not a creation result; a lost result stays Unknown and recovers only the original job', () async {
    final fixture = await draftsFixture();
    await fixture.selectStart();
    final start = fixture.repository.start('project')..setText('keep');
    await fixture.prepare(start);
    final ticket = start.submit();
    final begin = await fixture.creations.begins.at(0);
    final job = DraftCreationJob(
      begin.id,
      'project',
      begin.request.input.inputId,
    );
    begin.reply.complete(job);
    final result = await job.reads.at(0);
    job.progressSource.close();
    expect(ticket.state.value.isPending, isTrue);
    expect(start.state.value.submission, isA<SubmittingDraft>());
    result.completeError(
      const CommandDispatchFailure.unknownOutcome(failure: draftFailure),
    );
    expect(
      await ticket.result,
      isA<UnknownOutcomeCommandResult<StartNewThreadResult>>(),
    );
    expect(start.state.value.submission, isA<UnknownDraftSubmission>());
    expect(fixture.creations.begins.values, hasLength(1));
    final closing = fixture.repository.close();
    final recovered = await job.reads.at(1);
    expect(
      fixture.creations.finds.values,
      isEmpty,
      reason: 'The original concrete handle is still known',
    );
    recovered.completeError(
      const CommandDispatchFailure.rejected(failure: draftFailure),
    );
    final close = await job.closes.at(0);
    close.reply.complete(
      FeedCloseReport(
        feedId: job.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await closing).complete, isTrue);
    expect(fixture.creations.begins.values, hasLength(1));
    expect(
      await ticket.result,
      isA<UnknownOutcomeCommandResult<StartNewThreadResult>>(),
      reason: 'Later original outcome evidence does not rewrite the first result Future',
    );
  });

  test('an ordinary creation result transport error is Unknown, not an invented typed rejection', () async {
    final fixture = await draftsFixture();
    await fixture.selectStart();
    final start = fixture.repository.start('project')..setText('keep');
    await fixture.prepare(start);
    final ticket = start.submit();
    final begin = await fixture.creations.begins.at(0);
    final job = DraftCreationJob(
      begin.id,
      'project',
      begin.request.input.inputId,
    );
    begin.reply.complete(job);
    (await job.reads.at(0)).completeError(draftFailure);
    expect(
      await ticket.result,
      isA<UnknownOutcomeCommandResult<StartNewThreadResult>>(),
    );
    expect(start.state.value.text, 'keep');
    final closing = fixture.repository.close();
    (await job.reads.at(1)).completeError(
      const CommandDispatchFailure.rejected(failure: draftFailure),
    );
    (await job.closes.at(0)).reply.complete(
      FeedCloseReport(
        feedId: job.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await closing).complete, isTrue);
    expect(fixture.creations.begins.values, hasLength(1));
  });

  test('close joins a late native creation result and close receipt without revoking known success or publishing late progress', () async {
    final fixture = await draftsFixture();
    await fixture.selectStart();
    final start = fixture.repository.start('project')..setText('create');
    await fixture.prepare(start);
    final ticket = start.submit();
    final begin = await fixture.creations.begins.at(0);
    final job = DraftCreationJob(
      begin.id,
      'project',
      begin.request.input.inputId,
    );
    begin.reply.complete(job);
    final result = await job.reads.at(0);
    var closed = false;
    final closing = fixture.repository.close().then((report) {
      closed = true;
      return report;
    });
    final display = start.state.value;
    job.progressSource.publish(
      ThreadPreparationProgress(
        projectId: 'project',
        inputId: begin.request.input.inputId,
        stage: ThreadPreparationStage.initializingSession,
        workspacePath: null,
        branch: null,
      ),
    );
    expect(start.state.value, display);
    expect(closed, isFalse);
    final native = StartNewThreadResult(
      thread: draftThread('late'),
      receipt: SubmitPromptReceipt(
        threadId: 'late',
        inputId: begin.request.input.inputId,
        cursor: 7,
        requestDigest: draftDigest,
      ),
    );
    result.complete(native);
    final business = await ticket.result;
    expect(
      business,
      isA<AcknowledgedSyncFailedCommandResult<StartNewThreadResult>>(),
    );
    expect(
      (business as AcknowledgedSyncFailedCommandResult<StartNewThreadResult>)
          .value,
      native,
    );
    final nativeClose = await job.closes.at(0);
    expect(
      closed,
      isFalse,
      reason:
          'Result success is independent of native worker/cleanup completion',
    );
    expect(
      job.sourceCalls.values,
      isEmpty,
      reason: 'Seal must not open a new created execution source',
    );
    nativeClose.reply.complete(
      FeedCloseReport(
        feedId: job.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await closing).complete, isTrue);
    expect(await ticket.result, business);
  });

  test('durable requires this input sequence and digest, not storage watermark or arbitrary completed Turn', () async {
    final fixture = await draftsFixture();
    final composer = await fixture.composer(durable: 99);
    composer.setText('input');
    final ticket = composer.submit();
    final call = await fixture.commands.prompts.at(0);
    // The selected Session owns its one UI Timeline connection; durable evidence
    // reads the original history input instead of another UI Timeline read.
    final timelineOpens = fixture.conversations.timeline.requests.length;
    call.reply.complete(fixture.receipt(call));
    final first = await fixture.commands.acceptances.at(0);
    expect((first.threadId, first.inputId), ('thread', ticket.id.value));
    first.reply.complete(null);
    expect(
      await ticket.result,
      isA<AcknowledgedCommandResult<SubmitPromptReceipt>>(),
    );
    expect(ticket.state.value.durable, isFalse);
    final unrelated = DraftTurnPin(
      const TurnReadHeader(
        scope: ReadScopeIdentity(
          scopeId: 'unrelated-terminal',
          runtimeEpoch: draftRuntime,
          incarnation: 1,
          sourceRevision: 1,
        ),
        inputId: ReadText.inline(text: 'unrelated-input'),
        id: ReadText.inline(text: 'unrelated-turn'),
        threadId: ReadText.inline(text: 'thread'),
        revision: 1,
        updatedAt: 1,
        state: TurnReadState.completed(
          startedAt: 1,
          completedAt: 2,
          completion: TurnCompletion.normal,
        ),
      ),
    );
    fixture.conversations.facets.turnOpen = (_, __, ___) async => unrelated;
    await fixture.emitExecution(
      draftExecution(
        durable: 100,
        terminal: const TurnBrief(
          reference: TurnReadRef(entry: 90, revision: 1),
          revision: 1,
          updatedAt: 1,
          state: TurnBriefState.completed(
            startedAt: 1,
            completedAt: 2,
            completion: TurnCompletion.normal,
          ),
        ),
      ),
    );
    final wrongSequence = await fixture.commands.acceptances.at(1);
    wrongSequence.reply.complete(
      const InputAcceptanceEvidence(
        acceptedSequence: 6,
        requestDigest: draftDigest,
        disposition: PersistedInputDisposition.consumed,
      ),
    );
    await ticket.state.waitFor((state) => state.evidenceError != null);
    expect(ticket.state.value.durable, isFalse);
    await fixture.emitExecution(draftExecution(durable: 101));
    final wrongDigest = await fixture.commands.acceptances.at(2);
    wrongDigest.reply.complete(
      const InputAcceptanceEvidence(
        acceptedSequence: 7,
        requestDigest: draftOtherDigest,
        disposition: PersistedInputDisposition.consumed,
      ),
    );
    // The next actual storage publication is the retry cue, not a polling loop.
    await fixture.emitExecution(draftExecution(durable: 102));
    final correct = await fixture.commands.acceptances.at(3);
    correct.reply.complete(
      const InputAcceptanceEvidence(
        acceptedSequence: 7,
        requestDigest: draftDigest,
        disposition: PersistedInputDisposition.consumed,
      ),
    );
    await ticket.state.waitFor((state) => state.durable);
    expect(ticket.state.value.observed, isTrue);
    expect(ticket.state.value.effective, isTrue);
    expect(fixture.commands.prompts.values, hasLength(1));
    expect(
      fixture.conversations.timeline.requests,
      hasLength(timelineOpens),
      reason: 'Submission evidence never opens or consumes another UI read',
    );
  });

  test('a receipt arriving after the current saved baseline still queries its original input; discarded is durable but not effective', () async {
    final fixture = await draftsFixture();
    final composer = await fixture.composer();
    composer.setText('original');
    final ticket = composer.submit();
    final call = await fixture.commands.prompts.at(0);
    await fixture.emitExecution(draftExecution(durable: 500));
    expect(
      fixture.commands.acceptances.values,
      isEmpty,
      reason: 'A watermark alone has no native receipt identity',
    );
    call.reply.complete(fixture.receipt(call));
    final read = await fixture.commands.acceptances.at(0);
    expect(read.inputId, ticket.id.value);
    read.reply.complete(
      const InputAcceptanceEvidence(
        acceptedSequence: 7,
        requestDigest: draftDigest,
        disposition: PersistedInputDisposition.discarded,
      ),
    );
    await ticket.result;
    await ticket.state.waitFor((state) => state.durable);
    expect(ticket.state.value.observed, isTrue);
    expect(ticket.state.value.effective, isFalse);
    expect(fixture.commands.acceptances.values, hasLength(1));
  });

  test('original queued and running Turn identities advance observed and effective independently of durable', () async {
    final fixture = await draftsFixture();
    final composer = await fixture.composer();
    composer.setText('identity');
    final ticket = composer.submit();
    final call = await fixture.commands.prompts.at(0);
    // The selected Session owns its one UI Timeline connection; Turn evidence
    // reads the original execution source instead of another UI Timeline read.
    final timelineOpens = fixture.conversations.timeline.requests.length;
    await _acknowledge(fixture, ticket, call);
    final headers = <int, TurnReadHeader>{};
    final pins = <DraftTurnPin>[];
    fixture.conversations.facets.turnOpen = (thread, reference, origin) async {
      expect(thread, 'thread');
      expect(origin.runtimeEpoch, draftRuntime);
      expect(origin.incarnation, 1);
      final pin = DraftTurnPin(headers[reference.entry]!);
      pins.add(pin);
      return pin;
    };
    Future<void> materialize(
      int entry,
      String inputId, {
      required bool running,
    }) async {
      final reference = TurnReadRef(entry: entry, revision: 1);
      headers[entry] = TurnReadHeader(
        scope: ReadScopeIdentity(
          scopeId: 'turn-$entry',
          runtimeEpoch: draftRuntime,
          incarnation: 1,
          sourceRevision: 1,
        ),
        inputId: ReadText.inline(text: inputId),
        id: ReadText.inline(text: 'turn-$entry'),
        threadId: const ReadText.inline(text: 'thread'),
        revision: 1,
        updatedAt: entry,
        state: running
            ? const TurnReadState.running(
                startedAt: 1,
                phase: TurnPhase.thinking,
              )
            : const TurnReadState.queued(queuedAt: 1),
      );
      await fixture.emitExecution(
        draftExecution(
          status: running ? ThreadStatus.running : ThreadStatus.queued,
          active: TurnBrief(
            reference: reference,
            revision: 1,
            updatedAt: entry,
            state: running
                ? const TurnBriefState.running(
                    startedAt: 1,
                    phase: TurnPhase.thinking,
                  )
                : const TurnBriefState.queued(queuedAt: 1),
          ),
        ),
      );
      expect(
        pins.last.headerCalls,
        greaterThan(0),
        reason: 'The real submit owner, not UI code, reads the original header before ACK',
      );
    }

    await materialize(1, 'another-input', running: true);
    expect(ticket.state.value.observed, isFalse);
    expect(ticket.state.value.effective, isFalse);
    await fixture.emitExecution(draftExecution(status: ThreadStatus.queued));
    expect(
      ticket.state.value.observed,
      isFalse,
      reason: 'ThreadStatus.queued alone contains no input identity',
    );
    expect(ticket.state.value.effective, isFalse);
    expect(pins, hasLength(1));
    await materialize(2, ticket.id.value, running: false);
    // Frozen §16 SDK contract: queued proves identity only, not native Pending
    // support or durability. There is no UI read or private observer settlement.
    expect(ticket.state.value.observed, isTrue);
    expect(ticket.state.value.effective, isFalse);
    expect(ticket.state.value.durable, isFalse);
    await materialize(3, ticket.id.value, running: true);
    expect(ticket.state.value.effective, isTrue);
    expect(ticket.state.value.durable, isFalse);
    expect(pins, hasLength(3));
    expect(pins.every((pin) => pin.texts.values.isEmpty), isTrue);
    expect(fixture.commands.prompts.values, hasLength(1));
    expect(
      fixture.conversations.timeline.requests,
      hasLength(timelineOpens),
      reason: 'Submission evidence never opens or consumes a UI Timeline read',
    );
  });

  test('observer admission failure is a known non-dispatch and preserves draft refs and text', () async {
    final fixture = await draftsFixture();
    final composer = await fixture.composer();
    await fixture.admit(composer.addLocalFiles(['/declared/budget']), [
      draftFile('budget'),
    ]);
    composer.setText('usable');
    final permits = <ResourcePermit>[];
    final capacity = fixture.budget.capacities[ResourceKind.observer]!;
    while (fixture.budget.used(ResourceKind.observer) < capacity - 1) {
      permits.add(
        fixture.budget.acquire(
          ResourceKind.observer,
          owner: 'test-owned-observer',
        ),
      );
    }
    // Keep the action's own work watch admissible; evidence needs more watches.
    final ticket = composer.submit();
    expect(
      await ticket.result,
      isA<RejectedCommandResult<SubmitPromptReceipt>>(),
    );
    for (final permit in permits) {
      permit.release();
    }
    expect(fixture.commands.prompts.values, isEmpty);
    expect(composer.state.value.text, 'usable');
    expect(composer.state.value.attachments, [draftFile('budget')]);
    final discard = composer.discard();
    (await fixture.attachments.removals.at(0)).reply.complete(true);
    await discard.result;
  });

  test('a waiting preparation does not replace its frozen route with a newer route and rejected dispatch keeps input', () async {
    final fixture = await draftsFixture();
    final composer = await fixture.composer(routeRevision: 8);
    composer.setText('queued');
    final entered = Completer<void>();
    final barrier = Completer<void>();
    final ticket = composer.submit(
      preparePresentation: () {
        entered.complete();
        return barrier.future;
      },
    );
    await entered.future;
    await fixture.emitRoute(9);
    composer.setText('newer');
    barrier.complete();
    final call = await fixture.commands.prompts.at(0);
    expect(call.routeRevision, 8);
    expect(call.input.text, 'queued');
    call.reply.completeError(
      const CommandDispatchFailure.rejected(failure: draftFailure),
    );
    expect(
      await ticket.result,
      isA<RejectedCommandResult<SubmitPromptReceipt>>(),
    );
    expect(composer.state.value.text, 'newer');
    expect(fixture.commands.prompts.values, hasLength(1));
  });

  test('presentation preparation runs after freeze and before backend, and known preparation failure remains retryable', () async {
    final fixture = await draftsFixture();
    final composer = await fixture.composer();
    composer.setText('original');
    final entered = Completer<void>();
    final gate = Completer<void>();
    final ticket = composer.submit(
      preparePresentation: () {
        entered.complete();
        return gate.future;
      },
    );
    await entered.future;
    composer.setText('newer');
    expect(fixture.commands.prompts.values, isEmpty);
    gate.completeError(draftFailure);
    expect(
      await ticket.result,
      isA<RejectedCommandResult<SubmitPromptReceipt>>(),
    );
    expect(composer.state.value.text, 'newer');
    expect(fixture.commands.prompts.values, isEmpty);
    final retry = composer.submit();
    final call = await fixture.commands.prompts.at(0);
    expect(call.input.text, 'newer');
    await _acknowledge(fixture, retry, call);
  });

  test('Unknown Composer keeps frozen attachment ownership after newer draft discard and never replays', () async {
    final fixture = await draftsFixture();
    fixture.protectUnknown = true;
    final composer = await fixture.composer();
    await fixture.admit(composer.addLocalFiles(['/declared/unknown']), [
      draftFile('unknown'),
    ]);
    composer.setText('possibly accepted');
    final ticket = composer.submit();
    final call = await fixture.commands.prompts.at(0);
    call.reply.completeError(
      const CommandDispatchFailure.unknownOutcome(failure: draftFailure),
    );
    expect(
      await ticket.result,
      isA<UnknownOutcomeCommandResult<SubmitPromptReceipt>>(),
    );
    composer.setText('new draft');
    await composer.discard().result;
    expect(fixture.attachments.removals.values, isEmpty);
    final closed = await fixture.repository.close();
    expect(closed.complete, isFalse);
    expect(
      closed.unresolved.any(
        (resource) => resource.owner.contains(ticket.id.value),
      ),
      isTrue,
    );
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    expect(fixture.commands.prompts.values, hasLength(1));
    expect(fixture.commands.acceptances.values, isEmpty);
    expect((await fixture.repository.retryCleanup()).complete, isFalse);
    expect(fixture.commands.prompts.values, hasLength(1));
    expect(fixture.attachments.removals.values, isEmpty);
  });

  test('a receipt for a different native input cannot clear this Composer or authorize an identity evidence read', () async {
    final fixture = await draftsFixture();
    fixture.protectUnknown = true;
    final composer = await fixture.composer();
    composer.setText('original input');
    final ticket = composer.submit();
    final call = await fixture.commands.prompts.at(0);
    call.reply.complete(
      const SubmitPromptReceipt(
        threadId: 'other-thread',
        inputId: 'other-input',
        cursor: 7,
        requestDigest: draftDigest,
      ),
    );
    final result = await ticket.result;
    expect(result, isA<UnknownOutcomeCommandResult<SubmitPromptReceipt>>());
    expect(
      (result as UnknownOutcomeCommandResult<SubmitPromptReceipt>).error.code,
      StudioFailureCode.protocol,
    );
    expect(composer.state.value.text, 'original input');
    expect(composer.state.value.submission, isA<UnknownDraftSubmission>());
    expect(fixture.commands.acceptances.values, isEmpty);
    expect((await fixture.repository.close()).complete, isFalse);
    expect(fixture.commands.prompts.values, hasLength(1));
  });

  test('attachment cleanup exception holds its original entry and budget; false means absent on the explicit retry', () async {
    final fixture = await draftsFixture();
    final composer = fixture.repository.composer('thread');
    await fixture.admit(composer.addLocalFiles(['/declared/cleanup']), [
      draftFile('cleanup'),
    ]);
    final removal = composer.removeAttachment('cleanup');
    (await fixture.attachments.removals.at(0)).reply
        .completeError(draftFailure);
    expect(
      await removal.result,
      isA<AcknowledgedSyncFailedCommandResult<Unit>>(),
    );
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    expect(composer.state.value.cleanupIssues, isNotEmpty);
    final closed = await fixture.repository.close();
    expect(closed.complete, isFalse);
    final retrying = fixture.repository.retryCleanup();
    final retry = await fixture.attachments.removals.at(1);
    expect(retry.id, 'cleanup');
    retry.reply.complete(false);
    expect((await retrying).complete, isTrue);
    expect(fixture.budget.used(ResourceKind.attachment), 0);
    expect(fixture.attachments.begins.values, hasLength(1));
    expect(
      () => composer.addLocalFiles(['/must/not/reopen']),
      throwsA(isA<StudioFailure>()),
    );
    expect(fixture.attachments.removals.values, hasLength(2));
  });

  test('lost attachment begin plus find null retains Unknown; close only finds and joins the original job', () async {
    final fixture = await draftsFixture();
    final composer = fixture.repository.composer('thread');
    final ticket = composer.addLocalFiles(['/declared/lost-begin']);
    final begin = await fixture.attachments.begins.at(0);
    begin.reply.completeError(draftFailure);
    final original = await ticket.result;
    expect(original, isA<UnknownOutcomeCommandResult<Unit>>());
    final probing = fixture.repository.retryCleanup();
    final miss = await fixture.attachments.finds.at(0);
    expect(miss.id, ticket.id);
    miss.reply.complete(null);
    expect((await probing).complete, isFalse);
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    expect(fixture.attachments.begins.values, hasLength(1));
    final closing = fixture.repository.close();
    final found = await fixture.attachments.finds.at(1);
    final job = DraftAdmissionJob(ticket.id);
    found.reply.complete(job);
    (await job.reads.at(0)).completeError(
      const CommandDispatchFailure.rejected(failure: draftFailure),
    );
    final close = await job.closes.at(0);
    close.reply.complete(
      FeedCloseReport(
        feedId: job.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await closing).complete, isTrue);
    expect(await ticket.result, original);
    expect(
      fixture.attachments.removals.values,
      isEmpty,
      reason: 'No native metadata was ever admitted',
    );
    expect(fixture.attachments.begins.values, hasLength(1));
  });

  test('seal preserves an already-dispatched original submission until late acceptance settles its refs', () async {
    final fixture = await draftsFixture();
    final composer = await fixture.composer();
    await fixture.admit(composer.addLocalFiles(['/declared/sealed']), [
      draftFile('sealed'),
    ]);
    composer.setText('sent');
    final ticket = composer.submit();
    final call = await fixture.commands.prompts.at(0);
    fixture.repository.seal();
    expect(fixture.attachments.removals.values, isEmpty);
    call.reply.complete(fixture.receipt(call));
    final cleanup = await fixture.attachments.removals.at(0);
    expect(cleanup.id, 'sealed');
    cleanup.reply.complete(true);
    final result = await ticket.result;
    expect(
      result,
      isA<AcknowledgedSyncFailedCommandResult<SubmitPromptReceipt>>(),
    );
    expect(
      fixture.attachments.removals.values,
      hasLength(1),
      reason: 'Only the accepted operation releasing its last ref permits original file cleanup',
    );
    expect(fixture.commands.prompts.values, hasLength(1));
  });

  test('close joins late clipboard staging and its real cleanup even with no published cleanup issue yet', () async {
    final entered = Completer<void>();
    final staged = Completer<String?>();
    final cleaning = DraftCalls<({String path, Completer<void> reply})>();
    final fixture = await draftsFixture(
      stageImage: (_) {
        entered.complete();
        return staged.future;
      },
      cleanupImage: (path) {
        final call = (path: path, reply: Completer<void>());
        cleaning.add(call);
        return call.reply.future;
      },
    );
    final composer = fixture.repository.composer('thread');
    final ticket = composer.addClipboardImage(Uint8List.fromList([1, 2, 3]));
    await entered.future;
    expect(composer.state.value.cleanupIssues, isEmpty);
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    final pending = await fixture.repository.retryCleanup(
      deadline: DateTime.utc(2000),
    );
    expect(pending.complete, isFalse);
    expect(
      pending.unresolved.any(
        (resource) =>
            resource.owner.startsWith('draft-attachment:') &&
            resource.issues.any(
              (issue) => issue.diagnostic.code == 'draftWorkPending',
            ),
      ),
      isTrue,
      reason: 'A still-entered staging Future is a real obligation even before any cleanup failure map has an entry',
    );
    var closed = false;
    final closing = fixture.repository.close().then((report) {
      closed = true;
      return report;
    });
    staged.complete('/declared/staged');
    final cleanup = await cleaning.at(0);
    expect(cleanup.path, '/declared/staged');
    expect(closed, isFalse);
    expect(
      fixture.attachments.begins.values,
      isEmpty,
      reason: 'Late staging after seal cannot begin native admission',
    );
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    cleanup.reply.complete();
    expect(await ticket.result, isA<RejectedCommandResult<Unit>>());
    expect((await closing).complete, isTrue);
    expect(fixture.budget.used(ResourceKind.attachment), 0);
  });

  test('clipboard cleanup failure owns staging separately from the native attachment and retries the same path', () async {
    final cleaning = DraftCalls<({String path, Completer<void> reply})>();
    var stages = 0;
    final fixture = await draftsFixture(
      stageImage: (_) async {
        stages++;
        return '/declared/clipboard';
      },
      cleanupImage: (path) {
        final call = (path: path, reply: Completer<void>());
        cleaning.add(call);
        return call.reply.future;
      },
    );
    final composer = fixture.repository.composer('thread');
    final ticket = composer.addClipboardImage(Uint8List.fromList([4, 5, 6]));
    final begin = await fixture.attachments.begins.at(0);
    final job = DraftAdmissionJob(begin.id);
    begin.reply.complete(job);
    (await job.reads.at(0)).complete([draftFile('clipboard')]);
    final first = await cleaning.at(0);
    first.reply.completeError(draftFailure);
    final close = await job.closes.at(0);
    close.reply.complete(
      FeedCloseReport(
        feedId: job.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect(
      await ticket.result,
      isA<AcknowledgedSyncFailedCommandResult<Unit>>(),
    );
    expect(fixture.budget.used(ResourceKind.attachment), 2);
    final closing = fixture.repository.close();
    (await fixture.attachments.removals.at(0)).reply.complete(true);
    expect((await closing).complete, isFalse);
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    final retrying = fixture.repository.retryCleanup();
    final retry = await cleaning.at(1);
    expect(retry.path, first.path);
    retry.reply.complete();
    expect((await retrying).complete, isTrue);
    expect(stages, 1);
    expect(fixture.attachments.begins.values, hasLength(1));
    expect(fixture.attachments.removals.values, hasLength(1));
    expect(job.closes.values, hasLength(1));
    expect(
      () => composer.addClipboardImage(Uint8List.fromList([7])),
      throwsA(isA<StudioFailure>()),
    );
    expect(
      stages,
      1,
      reason:
          'A closed owner cannot reopen platform staging during cleanup retry',
    );
  });
}
