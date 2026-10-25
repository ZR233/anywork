import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/drafts_fixture.dart';
import 'support/drafts_native_fixture.dart';

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
}
