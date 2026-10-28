import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:test/test.dart';

import 'support/drafts_fixture.dart';
import 'support/drafts_native_fixture.dart';
import 'support/drafts_workspace_fixture.dart';

ArchiveThreadResult _removed(String root, [List<String>? ids]) =>
    ArchiveThreadResult(
      archivedRootId: root,
      removedThreadIds: ids ?? [root],
      nextRoot: null,
    );

void main() {
  test('factory Thread capture excludes unrelated Start route work and clears only its original Composer refs', () async {
    final fixture = await draftsFixture();
    final root = fixture.repository.composer('root')..setText('root text');
    await fixture.admit(root.addLocalFiles(['/declared/root']), [
      draftFile('root-file'),
    ]);
    final other = fixture.repository.start('other')..setText('unrelated Start');
    final route = other.prepareRoute();
    final pin = (await fixture.configuration.opened(0)).accept();
    final query = await pin.called(0); // This unrelated real read is pending.
    final capture = fixture.threadCapture('root');
    await capture.prepare(draftThread('root'));
    final confirmation = capture.afterArchived(_removed('root'));
    final remove = await fixture.attachments.removals.at(0);
    expect(remove.id, 'root-file');
    remove.reply.complete(true);
    expect(
      (await confirmation).complete,
      isTrue,
      reason: 'Thread capture does not include or await an unrelated Start',
    );
    expect(other.state.value.text, 'unrelated Start');
    expect(
      fixture.directory.threadOpens.values,
      isEmpty,
      reason: 'The supplied original root is sufficient; no execution Session or redundant root metadata open',
    );
    query.reply.complete(
      StartRouteRead.ready(
        sources: pin.originalHeader,
        query: query.query,
        intent: query.query.intent,
        route: draftNativeRoute,
        defaults: draftDefaults,
      ),
    );
    await route;
  });

  test('factory Project capture includes only its own Start while another Project route read stays pending', () async {
    final fixture = await draftsFixture();
    final own = fixture.repository.start('project')..setText('owned');
    await fixture.prepare(own);
    await fixture.admit(own.addLocalFiles(['/declared/project']), [
      draftFile('project-file'),
    ]);
    final originalOpen = await fixture.configuration.opened(0);
    final pin = originalOpen.native!;
    final nextQuery = pin.calls.length;
    final other = fixture.repository.start('other')..setText('keep other');
    final route = other.prepareRoute();
    final query = await pin.called(nextQuery);
    expect(fixture.configuration.opens, [originalOpen]);
    expect(query.reply.isCompleted, isFalse);
    final capture = fixture.projectCapture('project');
    await capture.prepare(draftProject);
    final confirmation = capture.afterArchived(draftProject);
    (await fixture.attachments.removals.at(0)).reply.complete(false);
    expect((await confirmation).complete, isTrue);
    expect(own.state.value.text, isEmpty);
    expect(other.state.value.text, 'keep other');
    expect(
      query.reply.isCompleted,
      isFalse,
      reason: 'Capturing one Project must not settle or cancel another Project route read.',
    );
    query.reply.complete(
      StartRouteRead.ready(
        sources: pin.originalHeader,
        query: query.query,
        intent: query.query.intent,
        route: draftNativeRoute,
        defaults: draftDefaults,
      ),
    );
    await route;
    await fixture.close();
    expect(pin.closeCalls, 1);
    expect(pin.retryCloseCalls, 0);
  });

  test('an accepted Project capture opens original Workspace metadata after Drafts seal and close joins read, file and native close', () async {
    final fixture = await draftsFixture();
    final composer = fixture.repository.composer('child')..setText('captured');
    await fixture.admit(composer.addLocalFiles(['/declared/capture']), [
      draftFile('captured'),
    ]);
    final capture = fixture.projectCapture('project');
    fixture.repository.seal();
    final preparing = capture.prepare(draftProject);
    final opening = await fixture.directory.threadOpens.at(0);
    expect(opening.scope, const ThreadDirectoryScope.thread(threadId: 'child'));
    final entity = Completer<ThreadDirectoryEntityRead>();
    final close = Completer<FeedCloseReport>();
    final record = draftThread('child', root: 'root');
    final material = await fixture.directory.threadBaseline(
      0,
      record,
      entityReply: entity,
      closeReply: close,
    );
    await material.entityEntered.future;
    var repositoryClosed = false;
    final repositoryClose = fixture.repository.close().then((report) {
      repositoryClosed = true;
      return report;
    });
    expect(repositoryClosed, isFalse);
    entity.complete(
      ThreadDirectoryEntityRead(
        reference: const ProductEntityRef(entry: 5, revision: 1),
        value: draftThreadRead(record),
      ),
    );
    await preparing;
    final confirmation = capture.afterArchived(draftProject);
    final remove = await fixture.attachments.removals.at(0);
    expect(remove.id, 'captured');
    await material.closeEntered.future;
    expect(repositoryClosed, isFalse);
    remove.reply.complete(true);
    expect(
      repositoryClosed,
      isFalse,
      reason:
          'File cleanup does not complete the original metadata close receipt',
    );
    close.complete(
      FeedCloseReport(
        feedId: 'draft-thread-material-100',
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await confirmation).complete, isTrue);
    expect((await repositoryClose).complete, isTrue);
    expect(fixture.conversations.repository.existingSession('child'), isNull);
    expect(fixture.conversations.facets.execution, isEmpty);
    expect(material.closes, 1);
  });

  test('an undecided Thread capture retains only possibly related records, not an unrelated Start or proven outside Composer', () async {
    final fixture = await draftsFixture();
    final root = fixture.repository.composer('root')..setText('root');
    final outside = fixture.repository.composer('outside')..setText('outside');
    final unrelated = fixture.repository.start('other')..setText('unrelated');
    await fixture.prepare(unrelated);
    await fixture.admit(root.addLocalFiles(['/declared/root']), [
      draftFile('root'),
    ]);
    await fixture.admit(outside.addLocalFiles(['/declared/outside']), [
      draftFile('outside'),
    ]);
    await fixture.admit(unrelated.addLocalFiles(['/declared/start']), [
      draftFile('start'),
    ]);
    final capture = fixture.threadCapture('root');
    await capture.prepare(draftThread('root'));
    await fixture.directory.threadOpens.at(
      0,
    ); // Outside membership is genuinely unresolved.
    final closing = fixture.repository.close();
    final unrelatedDelete = await fixture.attachments.removals.at(0);
    expect(unrelatedDelete.id, 'start');
    expect(
      fixture.attachments.removals.values.map((call) => call.id),
      isNot(contains('root')),
    );
    unrelatedDelete.reply.complete(true);
    final material = await fixture.directory.threadBaseline(
      0,
      draftThread('outside'),
    );
    await material.entityEntered.future;
    await material.closeEntered.future;
    final outsideDelete = await fixture.attachments.removals.at(1);
    expect(
      outsideDelete.id,
      'outside',
      reason: 'Original metadata, not absence from a sidebar window, proves unrelatedness',
    );
    outsideDelete.reply.complete(true);
    final awaitingDecision = await closing;
    expect(awaitingDecision.complete, isFalse);
    expect(
      awaitingDecision.unresolved.any(
        (resource) => resource.owner == 'draft-archive:root',
      ),
      isTrue,
    );
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    final confirmed = capture.afterArchived(_removed('root'));
    final rootDelete = await fixture.attachments.removals.at(2);
    expect(rootDelete.id, 'root');
    rootDelete.reply.complete(true);
    expect((await confirmed).complete, isTrue);
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(fixture.attachments.removals.values.map((call) => call.id), [
      'start',
      'outside',
      'root',
    ]);
  });

  test('overlapping capture wrappers detach independently and the final borrow joins the one original entry cleanup', () async {
    final fixture = await draftsFixture();
    final composer = fixture.repository.composer('root')..setText('original');
    await fixture.admit(composer.addLocalFiles(['/declared/shared']), [
      draftFile('shared'),
    ]);
    final first = fixture.threadCapture('root');
    final last = fixture.threadCapture('root');
    await first.prepare(draftThread('root'));
    await last.prepare(draftThread('root'));
    final native = _removed('root');
    expect(
      (await first.afterArchived(native)).complete,
      isTrue,
      reason: 'Another capture is a real remaining owner; this wrapper must not wait for a deletion that cannot start',
    );
    expect(composer.state.value.attachments, isEmpty);
    expect(fixture.attachments.removals.values, isEmpty);
    var completed = false;
    final deleting = last.afterArchived(native).then((report) {
      completed = true;
      return report;
    });
    final remove = await fixture.attachments.removals.at(0);
    expect(remove.id, 'shared');
    expect(completed, isFalse);
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    remove.reply.completeError(draftFailure);
    final failed = await deleting;
    expect(failed.complete, isFalse);
    expect(
      failed.unresolved.any(
        (resource) => resource.issues.any(
          (issue) => issue.recovery == CleanupRecovery.retryClose,
        ),
      ),
      isTrue,
    );
    final retrying = last.retryCleanup();
    final retry = await fixture.attachments.removals.at(1);
    expect(retry.id, 'shared');
    retry.reply.complete(false);
    expect((await retrying).complete, isTrue);
    expect(fixture.budget.used(ResourceKind.attachment), 0);
    expect(fixture.attachments.begins.values, hasLength(1));
    expect(
      fixture.attachments.removals.values,
      hasLength(2),
      reason: 'One failed deletion plus one explicit retry, not per-wrapper duplicate cleanup',
    );
  });

  test('metadata failure is not outside-root evidence; only authoritative removed IDs release the captured child refs', () async {
    final fixture = await draftsFixture();
    final composer = fixture.repository.composer('child')
      ..setText('keep candidate');
    await fixture.admit(composer.addLocalFiles(['/declared/candidate']), [
      draftFile('candidate'),
    ]);
    final capture = fixture.threadCapture('root');
    await capture.prepare(draftThread('root'));
    final opening = await fixture.directory.threadOpens.at(0);
    final native = opening.accept().feed;
    await native.listened.future;
    native.emit(
      ThreadDirectoryFrame.failure(
        identity: draftDirectoryIdentity(
          native.feedId,
          ProductResource.threadDirectory,
        ),
        error: draftFailure,
      ),
    );
    final closing = fixture.repository.close();
    await native.closeStarted.future;
    final unresolved = await closing;
    expect(unresolved.complete, isFalse);
    expect(
      unresolved.unresolved.any(
        (resource) => resource.owner == 'draft-archive-membership:root',
      ),
      isTrue,
    );
    expect(
      fixture.attachments.removals.values,
      isEmpty,
      reason: 'A failed original metadata source never proves that child belongs outside this root',
    );
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    final confirmation = capture.afterArchived(
      _removed('root', ['root', 'child']),
    );
    final remove = await fixture.attachments.removals.at(0);
    expect(remove.id, 'candidate');
    remove.reply.complete(true);
    expect((await confirmation).complete, isTrue);
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(fixture.conversations.repository.existingSession('child'), isNull);
  });

  test('archive selected admission stays Pending through late metadata, original result, removal and job close', () async {
    final fixture = await draftsFixture();
    final composer = fixture.repository.composer('root')..setText('original');
    final ticket = composer.addLocalFiles(['/declared/late']);
    final begin = await fixture.attachments.begins.at(
      0,
    ); // Real begin is already waiting.
    final capture = fixture.threadCapture('root');
    await capture.prepare(draftThread('root'));
    final pending = await capture.afterArchived(
      _removed('root'),
      deadline: DateTime.utc(2000),
    );
    expect(pending.complete, isFalse);
    expect(
      pending.unresolved.any(
        (resource) => resource.owner.contains(begin.id.value),
      ),
      isTrue,
    );
    final job = DraftAdmissionJob(begin.id);
    begin.reply.complete(job);
    final result = await job.reads.at(0);
    expect(fixture.attachments.removals.values, isEmpty);
    result.complete([draftFile('late')]);
    final remove = await fixture.attachments.removals.at(0);
    expect(remove.id, 'late');
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    remove.reply.complete(true);
    final nativeClose = await job.closes.at(0);
    var closed = false;
    final closing = fixture.repository.close().then((report) {
      closed = true;
      return report;
    });
    expect(closed, isFalse);
    nativeClose.reply.complete(
      FeedCloseReport(
        feedId: job.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect(await ticket.result, isA<AcknowledgedCommandResult<Unit>>());
    expect((await closing).complete, isTrue);
    expect((await capture.retryCleanup()).complete, isTrue);
    expect(fixture.attachments.begins.values, hasLength(1));
    expect(fixture.attachments.removals.values, hasLength(1));
  });

  test('Unknown submission is another concrete owner: archive can finish its borrow but cannot delete or replay it', () async {
    final fixture = await draftsFixture();
    fixture.protectUnknown = true;
    final composer = await fixture.composer(threadId: 'root');
    await fixture.admit(composer.addLocalFiles(['/declared/frozen']), [
      draftFile('frozen'),
    ]);
    composer.setText('possibly sent');
    final submission = composer.submit();
    final call = await fixture.commands.prompts.at(0);
    call.reply.completeError(
      const CommandDispatchFailure.unknownOutcome(failure: draftFailure),
    );
    expect(
      await submission.result,
      isA<UnknownOutcomeCommandResult<SubmitPromptReceipt>>(),
    );
    final capture = fixture.threadCapture('root');
    await capture.prepare(draftThread('root'));
    expect((await capture.afterArchived(_removed('root'))).complete, isTrue);
    expect(composer.state.value.attachments, isEmpty);
    expect(fixture.attachments.removals.values, isEmpty);
    expect(fixture.budget.used(ResourceKind.attachment), 1);
    expect((await fixture.repository.close()).complete, isFalse);
    expect(fixture.commands.prompts.values, hasLength(1));
    expect(fixture.attachments.removals.values, isEmpty);
  });
}
