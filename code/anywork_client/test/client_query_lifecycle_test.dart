import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/drafts_fixture.dart';
import 'support/drafts_native_fixture.dart';

const _retryIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'native-binary',
    code: 'binaryJoinPending',
    message: 'The original binary scope still needs native cleanup.',
    retryable: true,
    correlationId: 'query-binary-retry',
  ),
  recovery: CleanupRecovery.retryClose,
);

DraftBinaryPin _pin({int length = 1}) => DraftBinaryPin(
  originalScopeId: 'query-original-binary',
  length: length,
  descriptor: const AttachmentBinaryIdentity(
    scopeId: 'query-original-binary',
    runtimeEpoch: draftRuntime,
    incarnation: 1,
    target: AttachmentBinaryTarget.thread(
      threadId: 'thread',
      attachmentId: 'attachment',
    ),
  ),
);

Future<void> _release(DraftBinaryPin pin) async {
  final call = await pin.closes.at(0);
  call.reply.complete(
    FeedCloseReport(
      feedId: pin.originalScopeId,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
}

void main() {
  test(
    'synchronous transport reentry cannot escape the query close join',
    () async {
      final fixture = await draftsFixture(clientId: 'query-reentry');
      late Future<CloseReport> closing;
      fixture.binary.onOpen = () {
        closing = fixture.repository.close(deadline: DateTime.utc(2000));
      };
      final reading = fixture.repository.readThreadAttachment(
        'thread',
        'attachment',
      );
      final opening = await fixture.binary.opens.at(0);
      final report = await closing;
      expect(
        report.unresolved.any(
          (item) => item.owner == 'attachment-binary:thread',
        ),
        isTrue,
      );
      final pin = _pin(length: 0);
      opening.reply.complete(pin);
      final terminal = await pin.reads.at(0);
      terminal.reply.complete(
        AttachmentBinaryChunk(offset: 0, bytes: Uint8List(0), nextOffset: null),
      );
      expect(await reading, isEmpty);
      await _release(pin);
      expect((await fixture.repository.retryCleanup()).complete, isTrue);
      expect(fixture.binary.opens.values, hasLength(1));
    },
  );

  test(
    'close retains admitted query and rejects new queries until actual reply',
    () async {
      final fixture = await draftsFixture(clientId: 'query-close');
      final reading = fixture.repository.readThreadAttachment(
        'thread',
        'attachment',
      );
      final opening = await fixture.binary.opens.at(0);
      final pin = _pin();
      opening.reply.complete(pin);
      final entered = await pin.reads.at(0);
      expect(fixture.budget.used(ResourceKind.pendingOperation), 1);
      final closing = fixture.repository.close(deadline: DateTime.utc(2000));
      final repeated = fixture.repository.close(deadline: DateTime.utc(2100));
      final sameClose = identical(closing, repeated);
      final report = await closing;
      expect(
        report.unresolved.any(
          (item) => item.owner == 'attachment-binary:thread',
        ),
        isTrue,
      );
      expect(fixture.budget.used(ResourceKind.pendingOperation), 1);
      await expectLater(
        Future<Uint8List>.sync(
          () => fixture.repository.readThreadAttachment('thread', 'late'),
        ),
        throwsA(
          isA<StudioFailure>().having(
            (error) => error.code,
            'sealed admission',
            StudioFailureCode.cancelled,
          ),
        ),
      );
      expect(fixture.binary.opens.values, hasLength(1));
      entered.reply.complete(
        AttachmentBinaryChunk(
          offset: 0,
          bytes: Uint8List.fromList([7]),
          nextOffset: null,
        ),
      );
      expect(await reading, [7]);
      await _release(pin);
      expect((await fixture.repository.retryCleanup()).complete, isTrue);
      // Peer Repositories own their established feeds until their own close.
      await fixture.close();
      expect(fixture.budget.usage, isEmpty);
      expect(
        sameClose,
        isTrue,
        reason: 'Repeated close must share the original close Future, not just its work',
      );
    },
  );

  test('sealed retryCleanup retains one explicit retry behind the unique unbounded close join', () async {
    final fixture = await draftsFixture(clientId: 'query-retry-join');
    final reading = fixture.repository.readThreadAttachment(
      'thread',
      'attachment',
    );
    final opening = await fixture.binary.opens.at(0);
    final pin = _pin();
    opening.reply.complete(pin);
    final entered = await pin.reads.at(0);

    // The bounded close observes genuinely entered work and returns its
    // snapshot; the original responsibility is still joining.
    expect(
      (await fixture.repository.close(deadline: DateTime.utc(2000))).complete,
      isFalse,
    );
    // An explicit retry of the same owners is not the original join and does
    // not degrade it to a bounded snapshot. The original pass still owns the
    // only native close, so the accepted retry cannot have advanced it yet.
    expect(
      (await fixture.repository.retryCleanup(deadline: DateTime.utc(2000)))
          .complete,
      isFalse,
    );
    expect(
      pin.closes.values,
      isEmpty,
      reason: 'The original pass drains the read before any native close',
    );
    // The unique unbounded close must keep joining the whole responsibility,
    // including the retry accepted while it was in flight.
    final closing = fixture.repository.close();
    entered.reply.complete(
      AttachmentBinaryChunk(
        offset: 0,
        bytes: Uint8List.fromList([7]),
        nextOffset: null,
      ),
    );
    expect(await reading, [7]);
    // The first native close really returns unresolved, so the first pass
    // cannot end the registered responsibility.
    final first = await pin.closes.at(0);
    first.reply.complete(
      FeedCloseReport(
        feedId: pin.originalScopeId,
        outcome: FeedCloseOutcome.unresolved(issues: const [_retryIssue]),
      ),
    );
    // Without a second public call the retained retry now enters exactly once
    // on the original handle.
    final retried = await pin.closes.at(1);
    expect(
      retried.retry,
      isTrue,
      reason: 'The accepted retry is one extra pass on the original handle',
    );
    retried.reply.complete(
      FeedCloseReport(
        feedId: pin.originalScopeId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    final report = await closing;
    expect(
      report.complete,
      isTrue,
      reason:
          'The unbounded close joins the real exit, not an earlier snapshot',
    );
    expect(fixture.binary.opens.values, hasLength(1));
    expect(pin.closes.values, hasLength(2));
    expect(
      fixture.budget.usage.where(
        (use) => use.owner == 'attachment-binary:thread',
      ),
      isEmpty,
      reason: 'The retried original read handle really released its permit',
    );
  });

  // The other close-identity cases here enter `close()` from an adapter open
  // callback (no join exists yet) or from hooks that only run after the join is
  // published. An in-flight binary read is drained before its native close, so
  // only releasing an already-held attachment borrow runs inside the real
  // startup window: the ledger deletes synchronously there.
  test(
    'a synchronous native removal cannot split the one published close Future',
    () async {
      final fixture = await draftsFixture(clientId: 'query-remove-reentry');
      final composer = await fixture.composer();
      await fixture.admit(composer.addLocalFiles(['/declared/reentry']), [
        draftFile('reentry'),
      ]);
      final reentered = <Future<CloseReport>>[];
      fixture.attachments.onRemove = (_) {
        fixture.attachments.onRemove = null;
        reentered.add(fixture.repository.close());
      };

      final closing = fixture.repository.close();
      // Freeze what the synchronous window really captured before anything is
      // awaited, so a late-published join cannot be described by later state.
      final captured = List<Future<CloseReport>>.of(reentered);
      final sameIdentity = [
        for (final inner in captured) identical(closing, inner),
      ];
      final repeatedSame = identical(closing, fixture.repository.close());

      // Always let the original native removal and every accepted join settle;
      // an identity verdict must never skip the real cleanup.
      (await fixture.attachments.removals.at(0)).reply.complete(true);
      final reports = await Future.wait([closing, ...captured]);

      expect(
        captured,
        isNotEmpty,
        reason: 'The native removal runs inside the close startup window',
      );
      // Reversible red check: publishing the join after it starts (move
      // `_closing = done.future;` below the `_closeJoin()` call in `_newJoin`)
      // makes this reentry observe no published join, so only this identity
      // assertion fails while every terminal assertion below still holds.
      for (final same in sameIdentity) {
        expect(
          same,
          isTrue,
          reason: 'A reentry from the real startup window joins the one published close Future',
        );
      }
      expect(
        repeatedSame,
        isTrue,
        reason: 'A repeated close keeps that same join identity',
      );
      expect(
        reports.first.complete,
        isTrue,
        reason: 'The real join still reaches its terminal state',
      );
      expect(
        fixture.attachments.removals.values,
        hasLength(1),
        reason: 'The reentry asked for no second native removal',
      );
      expect(fixture.attachments.begins.values, hasLength(1));
    },
  );
}
