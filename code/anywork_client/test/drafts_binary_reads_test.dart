import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/drafts_fixture.dart';
import 'support/drafts_native_fixture.dart';

Iterable<ResourceUsage> _binaryUsage(DraftsFixture fixture) =>
    fixture.budget.usage.where(
      (usage) =>
          usage.kind == ResourceKind.readModel &&
          usage.owner.startsWith('attachment-binary:'),
    );

void main() {
  test('synchronous native-open reentry cannot cancel an already accepted attachment result or escape its close join', () async {
    final fixture = await draftsFixture();
    late Future<CloseReport> closing;
    fixture.binary.onOpen = () {
      closing = fixture.repository.close(deadline: DateTime.utc(2000));
    };
    final reading = fixture.repository.readThreadAttachment(
      'thread',
      'reentrant-file',
    );
    final opening = await fixture.binary.opens.at(0);
    final pending = await closing;
    expect(pending.complete, isFalse);
    final pin = DraftBinaryPin(
      originalScopeId: 'reentrant-accepted-read',
      length: 1,
      descriptor: const AttachmentBinaryIdentity(
        scopeId: 'reentrant-accepted-read',
        runtimeEpoch: draftRuntime,
        incarnation: 1,
        target: AttachmentBinaryTarget.thread(
          threadId: 'thread',
          attachmentId: 'reentrant-file',
        ),
      ),
    );
    opening.reply.complete(pin);
    final call = await pin.reads.at(0);
    call.reply.complete(
      AttachmentBinaryChunk(
        offset: 0,
        bytes: Uint8List.fromList([7]),
        nextOffset: null,
      ),
    );
    expect(await reading, [7]);
    final close = await pin.closes.at(0);
    expect(_binaryUsage(fixture), hasLength(1));
    close.reply.complete(
      FeedCloseReport(
        feedId: pin.originalScopeId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(_binaryUsage(fixture), isEmpty);
    expect(fixture.binary.opens.values, hasLength(1));
  });

  test('a late original attachment open drains all accepted chunks after seal before requesting native close', () async {
    final fixture = await draftsFixture();
    final reading = fixture.repository.readThreadAttachment(
      'thread',
      'late-file',
    );
    final opening = await fixture.binary.opens.at(0);
    final pending = await fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(pending.complete, isFalse);
    final pin = DraftBinaryPin(
      originalScopeId: 'late-accepted-read',
      length: 2,
      descriptor: const AttachmentBinaryIdentity(
        scopeId: 'late-accepted-read',
        runtimeEpoch: draftRuntime,
        incarnation: 1,
        target: AttachmentBinaryTarget.thread(
          threadId: 'thread',
          attachmentId: 'late-file',
        ),
      ),
    );
    opening.reply.complete(pin);
    final first = await pin.reads.at(0);
    expect(
      pin.requests,
      0,
      reason: 'The admitted whole read still owns native query admission',
    );
    first.reply.complete(
      AttachmentBinaryChunk(
        offset: 0,
        bytes: Uint8List.fromList([7]),
        nextOffset: 1,
      ),
    );
    final second = await pin.reads.at(1);
    expect((second.offset, second.maxBytes), (1, 65536));
    expect(pin.requests, 0);
    second.reply.complete(
      AttachmentBinaryChunk(
        offset: 1,
        bytes: Uint8List.fromList([8]),
        nextOffset: null,
      ),
    );
    expect(await reading, [7, 8]);
    final close = await pin.closes.at(0);
    expect(pin.requests, greaterThan(0));
    expect(_binaryUsage(fixture), hasLength(1));
    close.reply.complete(
      FeedCloseReport(
        feedId: pin.originalScopeId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(_binaryUsage(fixture), isEmpty);
    expect(fixture.binary.opens.values, hasLength(1));
    expect(pin.closes.values, hasLength(1));
  });

  test('an accepted attachment read returns its original bytes after close seals new admission and retains the native join', () async {
    final fixture = await draftsFixture();
    final reading = fixture.repository.readThreadAttachment('thread', 'file');
    final opening = await fixture.binary.opens.at(0);
    final pin = DraftBinaryPin(
      originalScopeId: 'accepted-read',
      length: 1,
      descriptor: const AttachmentBinaryIdentity(
        scopeId: 'accepted-read',
        runtimeEpoch: draftRuntime,
        incarnation: 1,
        target: AttachmentBinaryTarget.thread(
          threadId: 'thread',
          attachmentId: 'file',
        ),
      ),
    );
    opening.reply.complete(pin);
    final entered = await pin.reads.at(0);
    final closing = await fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(closing.complete, isFalse);
    expect(_binaryUsage(fixture), hasLength(1));
    await expectLater(
      Future<Uint8List>.sync(
        () => fixture.repository.readThreadAttachment('thread', 'late'),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
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
    final close = await pin.closes.at(0);
    expect(
      _binaryUsage(fixture),
      hasLength(1),
      reason: 'Returning bytes does not prove original native Clean',
    );
    close.reply.complete(
      FeedCloseReport(
        feedId: pin.originalScopeId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(_binaryUsage(fixture), isEmpty);
    expect(pin.reads.values, hasLength(1));
    expect(pin.closes.values, hasLength(1));
  });

  test('public Thread attachment read assembles only contiguous bounded native chunks and joins original close', () async {
    final fixture = await draftsFixture();
    final reading = fixture.repository.readThreadAttachment('thread', 'file');
    final opening = await fixture.binary.opens.at(0);
    expect(
      (opening.threadId, opening.attachmentId, opening.draftId),
      ('thread', 'file', null),
    );
    const identity = AttachmentBinaryIdentity(
      scopeId: 'original-binary',
      runtimeEpoch: draftRuntime,
      incarnation: 1,
      target: AttachmentBinaryTarget.thread(
        threadId: 'thread',
        attachmentId: 'file',
      ),
    );
    final pin = DraftBinaryPin(
      originalScopeId: identity.scopeId,
      descriptor: identity,
      length: 3,
    );
    opening.reply.complete(pin);
    final first = await pin.reads.at(0);
    expect((first.offset, first.maxBytes), (0, 65536));
    first.reply.complete(
      AttachmentBinaryChunk(
        offset: 0,
        bytes: Uint8List.fromList([1]),
        nextOffset: 1,
      ),
    );
    final next = await pin.reads.at(1);
    expect((next.offset, next.maxBytes), (1, 65536));
    next.reply.complete(
      AttachmentBinaryChunk(
        offset: 1,
        bytes: Uint8List.fromList([2, 3]),
        nextOffset: null,
      ),
    );
    expect(await reading, [1, 2, 3]);
    final close = await pin.closes.at(0);
    expect(_binaryUsage(fixture), hasLength(1));
    close.reply.complete(
      FeedCloseReport(
        feedId: 'original-binary',
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await fixture.repository.close()).complete, isTrue);
    expect(_binaryUsage(fixture), isEmpty);
    expect(pin.reads.values, hasLength(2));
    expect(fixture.binary.opens.values, hasLength(1));
  });

  test('descriptor conversion failure remains a read error but independent original scopeId authorizes real Clean release', () async {
    final fixture = await draftsFixture();
    final reading = fixture.repository.readDraftAttachment('draft-file');
    final failed = expectLater(reading, throwsA(same(draftFailure)));
    final opening = await fixture.binary.opens.at(0);
    final pin = DraftBinaryPin(
      originalScopeId: 'descriptor-failed-scope',
      length: 3,
      descriptor: const AttachmentBinaryIdentity(
        scopeId: 'descriptor-failed-scope',
        runtimeEpoch: draftRuntime,
        incarnation: 1,
        target: AttachmentBinaryTarget.draft(draftId: 'draft-file'),
      ),
    )..descriptorFailure = draftFailure;
    opening.reply.complete(pin);
    await failed;
    final closing = await pin.closes.at(0);
    expect(pin.reads.values, isEmpty);
    expect(_binaryUsage(fixture), hasLength(1));
    closing.reply.complete(
      FeedCloseReport(
        feedId: 'descriptor-failed-scope',
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await fixture.repository.close()).complete, isTrue);
    expect(_binaryUsage(fixture), isEmpty);
    expect(
      pin.descriptorFailure,
      same(draftFailure),
      reason: 'Cleanup does not need the invalid full descriptor to become readable',
    );
    expect(pin.closes.values, hasLength(1));
  });

  test('missing raw scope identity cannot be inferred from a Clean report; retryClose recovers the same handle', () async {
    final fixture = await draftsFixture();
    final reading = fixture.repository.readDraftAttachment('draft-file');
    final failed = expectLater(reading, throwsA(same(draftFailure)));
    final opening = await fixture.binary.opens.at(0);
    final pin = DraftBinaryPin(
      originalScopeId: 'recoverable-original',
      length: 3,
      descriptor: const AttachmentBinaryIdentity(
        scopeId: 'recoverable-original',
        runtimeEpoch: draftRuntime,
        incarnation: 1,
        target: AttachmentBinaryTarget.draft(draftId: 'draft-file'),
      ),
    )..scopeFailure = draftFailure;
    opening.reply.complete(pin);
    await failed;
    final first = await pin.closes.at(0);
    first.reply.complete(
      FeedCloseReport(
        feedId: 'recoverable-original',
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    final unresolved = await fixture.repository.close();
    expect(unresolved.complete, isFalse);
    expect(
      unresolved.unresolved.any(
        (resource) => resource.owner == 'attachment-binary:draft',
      ),
      isTrue,
    );
    expect(_binaryUsage(fixture).single.phase, ResourcePhase.unresolved);
    pin.scopeFailure = null; // The original raw native getter is now available.
    final retrying = fixture.repository.retryCleanup();
    final retry = await pin.closes.at(1);
    expect(retry.retry, isTrue);
    retry.reply.complete(
      FeedCloseReport(
        feedId: 'recoverable-original',
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await retrying).complete, isTrue);
    expect(_binaryUsage(fixture), isEmpty);
    expect(fixture.binary.opens.values, hasLength(1));
    expect(pin.reads.values, isEmpty);
    expect(first.retry, isFalse);
  });
}
