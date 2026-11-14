import 'dart:async';

import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';
import '../support/mapped_conversation_feed.dart';
import '../support/recording_demo_transport.dart';

const _thread = 'thread-main';
const _one = ReadDemand(maxItems: 1, maxBytes: 65536);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('summary-only Demo updates replay Status and preserve the original older cursor', () async {
    final api = await _open();
    final work = DisplayBlockRef(
      databaseId: api.conversationDatabaseId(_thread),
      blockId: 'status-work',
    );
    final older = LiveDisplayBlock(
      id: 'status-text',
      blockOrder: 4,
      body: SingleDisplayBlock(
        visibility: SingleVisibility.content,
        record: DisplayRecord(
          atom: chatAtomMessage('status-text'),
          contentSource: const CurrentAtom(),
        ),
      ),
      state: DisplayBlockState.open,
    );
    final timing = displayTiming();
    TailSnapshot live(String summary) => TailSnapshot(
      revision: 1,
      layoutRevision: 1,
      readyFrontier: 3,
      executionPresent: true,
      currentWorkId: work.blockId,
      blocks: [
        older,
        LiveDisplayBlock(
          id: work.blockId,
          blockOrder: 5,
          body: WorkDisplayBlock(timing: timing, members: work),
          state: DisplayBlockState.open,
          thinkingSummary: summary,
        ),
      ],
    );
    api.seedDisplayBlocks(
      threadId: _thread,
      blocks: [],
      live: live('first summary'),
    );
    final reader = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: _one,
    );
    addTearDown(reader.close);
    final first = await reader.next(after: reader.metadata.initialCursor);
    final tail = (first.tail as ReplaceTail).snapshot;
    expect(tail.blocks.single.id, work.blockId);
    expect(tail.older, isNotNull);
    api.seedDisplayBlocks(
      threadId: _thread,
      blocks: [],
      live: live('second summary'),
    );
    final status = await reader.next(after: first.next);
    expect(status.history.blocks, isEmpty);
    final update = status.tail as TailStatus;
    expect(update.baseLayoutRevision, tail.layoutRevision);
    expect(update.currentWorkId, work.blockId);
    expect(update.thinkingSummary, 'second summary');
    expect(await reader.next(after: first.next), same(status));
    final page = await reader.loadLiveOlder(before: tail.older!, demand: _one);
    expect(page.layoutRevision, tail.layoutRevision);
    expect(page.currentWorkId, work.blockId);
    expect(page.blocks.single.id, older.id);
  });

  test('Demo GUI starts with Timeline Set; completion originals keep their own positions', () async {
    final api = await _open();
    final state = await api.openConversationStateFeed(_thread);
    final states = StreamIterator(state.events);
    addTearDown(states.cancel);
    await _nextState(states, 1);
    final feed = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: chatDemand,
    );
    expect(feed.metadata.readerId, isNot(state.subscriptionId));
    final events = _CursorPeer(feed);
    addTearDown(events.cancel);
    // State still owns its credit; Timeline Set and queries do not wait for it.
    final batch = await _nextTimeline(events, 1);
    expect(batch.placement, ChatPlacement.set);
    expect(batch.blocks.map((b) => b.blockOrder), [1, 2, 3]);
    expect(batch.throughOrder, 3);
    expect(batch.live!.readyFrontier, 3);
    expect(batch.live!.blocks, isEmpty);
    final work = batch.blocks[1].body as WorkDisplayBlock;
    expect(work.timing.finishedAt, isNotNull);
    final members = await feed.openDisplayMembers(
      reference: work.members,
      window: const LatestDisplayMembers(),
      demand: chatDemand,
    );
    final page = (await members.next())!;
    expect(page.entries.map((h) => h.memberKey), [
      'turn-demo:reasoning',
      'turn-demo:tool',
    ]);
    expect(page.sealed, isTrue);
    expect(await members.next(), isNull);
    final finalOriginal = await feed.reader.readCompleted(
      recordId: 'turn-demo:final',
      demand: chatDemand,
    );
    expect(finalOriginal.completionSeq, 4);
    expect(batch.blocks.last.blockOrder, 3);
    await members.close();
    await feed.close();
    await state.close();
  });

  test('completion seed does not synthesize display; explicit P and member pagination are independent of H', () async {
    final api = await _open();
    final entry = chatMessage('original-100', completionSeq: 100);
    api.seedTimelineItems(_thread, [entry]);
    var feed = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: chatDemand,
    );
    var events = _CursorPeer(feed);
    expect((await _nextTimeline(events, 1)).throughOrder, 3);
    await feed.close();
    await events.cancel();

    final ref = DisplayBlockRef(
      databaseId: api.conversationDatabaseId(_thread),
      blockId: 'explicit-work',
    );
    api.seedDisplayBlocks(
      threadId: _thread,
      blocks: [
        DisplayBlock(
          id: ref.blockId,
          blockOrder: 4,
          body: WorkDisplayBlock(timing: displayTiming(), members: ref),
        ),
        displaySingle(entry, blockOrder: 5),
      ],
      members: {
        ref: [
          for (var i = 1; i <= 3; i++)
            DisplayMemberHead(
              memberKey: 'member-$i',
              memberOrder: i,
              record: DisplayRecord(
                atom: chatAtomMessage('member-$i'),
                contentSource: const CurrentAtom(),
              ),
            ),
        ],
      },
    );
    feed = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: _one,
    );
    events = _CursorPeer(feed);
    addTearDown(events.cancel);
    final batch = await _nextTimeline(events, 1);
    expect(batch.blocks.single.blockOrder, 5);
    expect(batch.throughOrder, 5);
    // No ACK of Set: all three query paths are independent of producer credit.
    final older = await feed.loadTimelineOlder(
      before: batch.before!,
      demand: _one,
    );
    expect(older.presentationVersion, presentationVersion);
    expect(older.blocks.single.id, ref.blockId);
    expect(older.ceiling, 5);
    final oldest = await feed.loadTimelineOlder(
      before: older.before!,
      demand: chatDemand,
    );
    expect(oldest.blocks.map((b) => b.blockOrder), [1, 2, 3]);
    expect(oldest.before, isNull);
    expect(
      (await feed.reader.readCompleted(
        recordId: entry.recordId,
        demand: chatDemand,
      )).completionSeq,
      100,
    );
    final latest = await feed.openDisplayMembers(
      reference: ref,
      window: const LatestDisplayMembers(),
      demand: _one,
    );
    final page = (await latest.next())!;
    expect(page.entries.single.memberOrder, 3);
    expect(page.before, 3);
    expect(await latest.next(), isNull);
    final earlier = await feed.openDisplayMembers(
      reference: ref,
      window: BeforeDisplayMembers(memberOrder: page.before!),
      demand: chatDemand,
    );
    final earlierPage = (await earlier.next())!;
    expect(earlierPage.entries.map((h) => h.memberOrder), [1, 2]);
    expect(earlierPage.before, isNull);
    expect(await earlier.next(), isNull);
    await feed.close();
  });

  test('explicit live windows are bounded and their cursors belong to the original reader/revision', () async {
    final api = await _open();
    api.seedDisplayBlocks(
      threadId: _thread,
      blocks: [],
      live: TailSnapshot(
        currentWorkId: null,
        revision: 1,
        layoutRevision: 1,
        readyFrontier: 3,
        executionPresent: false,
        blocks: [
          for (var i = 1; i <= 3; i++)
            LiveDisplayBlock(
              id: 'live-$i',
              blockOrder: 3 + i,
              body: SingleDisplayBlock(
                visibility: SingleVisibility.content,
                record: DisplayRecord(
                  atom: chatAtomMessage('live-$i'),
                  contentSource: const CurrentAtom(),
                ),
              ),
              state: DisplayBlockState.open,
            ),
        ],
      ),
    );
    final feed = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: _one,
    );
    final events = _CursorPeer(feed);
    addTearDown(events.cancel);
    final live = (await _nextTimeline(events, 1)).live!;
    expect(live.blocks.single.id, 'live-3');
    final older = await feed.loadLiveOlder(before: live.older!, demand: _one);
    expect(older.blocks.single.id, 'live-2');
    final oldest = await feed.loadLiveOlder(before: older.older!, demand: _one);
    expect(oldest.blocks.single.id, 'live-1');
    expect(oldest.older, isNull);
    final other = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: chatDemand,
    );
    await expectLater(
      other.loadLiveOlder(before: live.older!, demand: chatDemand),
      throwsA(isA<StudioFailure>()),
    );
    api.seedDisplayBlocks(
      threadId: _thread,
      blocks: [],
      live: TailSnapshot(
        currentWorkId: null,
        revision: 2,
        layoutRevision: 2,
        readyFrontier: 3,
        executionPresent: false,
        blocks: [],
      ),
    );
    await expectLater(
      feed.loadLiveOlder(before: live.older!, demand: chatDemand),
      throwsA(isA<StudioFailure>()),
    );
    await other.close();
    await feed.close();
  });

  test('script members complete in the same live Work; body explicitly hands off and seals Single', () async {
    final api = await _open();
    final state = await api.openConversationStateFeed(_thread);
    final states = StreamIterator(state.events);
    addTearDown(states.cancel);
    final workspace = await _nextState(states, 1);
    final feed = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: chatDemand,
    );
    expect(feed.metadata.readerId, isNot(state.subscriptionId));
    final started = Completer<void>();
    final startedTurn = Completer<String>();
    final finished = Completer<void>();
    final batches = <ViewUpdate>[];
    final originalBeforeSeal = Completer<CompletedEntry>();
    String? turnId;
    var timelineSequence = 0;
    final cursor = _CursorPeer(feed);
    final observing = () async {
      while (!finished.isCompleted) {
        final batch = await cursor.next();
        timelineSequence++;
        expect(
          batch.placement,
          timelineSequence == 1 ? ChatPlacement.set : ChatPlacement.append,
        );
        if (batch.placement != ChatPlacement.set) {
          turnId = await startedTurn.future;
        }
        batches.add(batch);
        for (final live in batch.live?.blocks ?? <LiveDisplayBlock>[]) {
          if (live.body case WorkDisplayBlock(:final members)
              when turnId != null &&
                  live.id == '$turnId:work' &&
                  !live.hasUnfinishedMembers) {
            final reader = await feed.openDisplayMembers(
              reference: members,
              window: const LatestDisplayMembers(),
              demand: chatDemand,
            );
            final page = await reader.next();
            await reader.close();
            final completedReasoning =
                page?.entries.any(
                  (member) =>
                      member.record.atom.id == '$turnId:reasoning' &&
                      member.record.contentSource is CompletedOriginal,
                ) ??
                false;
            if (completedReasoning && !originalBeforeSeal.isCompleted) {
              originalBeforeSeal.complete(
                await feed.reader.readCompleted(
                  recordId: '$turnId:reasoning',
                  demand: chatDemand,
                ),
              );
            }
          }
        }
        if (turnId != null &&
            batch.blocks.any((b) => b.id == '$turnId:final')) {
          if (!finished.isCompleted) finished.complete();
        }
        if (!started.isCompleted) started.complete();
      }
    }();
    addTearDown(() async {
      await feed.close();
      await observing;
    });
    await started.future;
    await state.acknowledge(states.current.deliverySequence);
    await api.submitPrompt(
      _thread,
      const StudioPromptInput(
        inputId: 'prompt-story',
        text: 'inspect',
        attachmentDraftIds: [],
      ),
      expectedModelRouteRevision: workspace.modelRoute!.revision,
    );
    var stateSequence = 1;
    String? activeTurnId;
    while (activeTurnId == null) {
      final current = await _nextState(states, ++stateSequence);
      activeTurnId = current.activeTurn?.turnId;
      await state.acknowledge(states.current.deliverySequence);
    }
    turnId = activeTurnId;
    startedTurn.complete(activeTurnId);
    await finished.future.timeout(const Duration(seconds: 5));
    expect((await originalBeforeSeal.future).recordId, '$turnId:reasoning');
    final workId = '$turnId:work';
    final snapshots = [
      for (final b in batches) ...?b.live?.blocks.where((b) => b.id == workId),
    ];
    expect(snapshots.any((b) => b.hasUnfinishedMembers), isTrue);
    expect(snapshots.any((b) => !b.hasUnfinishedMembers), isTrue);
    final handoff = batches.firstWhere(
      (b) => b.blocks.any((b) => b.id == workId),
    );
    expect(handoff.live!.blocks.any((b) => b.id == workId), isFalse);
    expect(handoff.live!.blocks.any((b) => b.id == '$turnId:final'), isTrue);
    final sealedWork =
        handoff.blocks.firstWhere((b) => b.id == workId).body
            as WorkDisplayBlock;
    expect(sealedWork.timing.finishedAt, isNotNull);
    final members = await feed.openDisplayMembers(
      reference: sealedWork.members,
      window: const LatestDisplayMembers(),
      demand: chatDemand,
    );
    final page = (await members.next())!;
    expect(page.entries.map((m) => m.memberKey), [
      '$turnId:reasoning',
      '$turnId:tool',
    ]);
    expect(
      page.entries.every((m) => m.record.contentSource is CompletedOriginal),
      isTrue,
    );
    expect(await members.next(), isNull);
    final finalBatch = batches.firstWhere(
      (b) => b.blocks.any((b) => b.id == '$turnId:final'),
    );
    expect(
      finalBatch.live!.blocks.any((b) => b.id == '$turnId:final'),
      isFalse,
    );
    await feed.close();
    await state.close();
  });

  test('actual stop seals the scripted Work as cancelled without forging member success', () async {
    final api = await _open(_SlowStoryDemo());
    final state = await api.openConversationStateFeed(_thread);
    final states = StreamIterator(state.events);
    addTearDown(states.cancel);
    final workspace = await _nextState(states, 1);
    final feed = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: chatDemand,
    );
    expect(feed.metadata.readerId, isNot(state.subscriptionId));
    final events = _CursorPeer(feed);
    addTearDown(events.cancel);
    await _nextTimeline(events, 1);

    await state.acknowledge(states.current.deliverySequence);
    await api.submitPrompt(
      _thread,
      const StudioPromptInput(
        inputId: 'cancel-story',
        text: 'cancel',
        attachmentDraftIds: [],
      ),
      expectedModelRouteRevision: workspace.modelRoute!.revision,
    );
    String? executionId;
    var stateSequence = 1;
    while (executionId == null) {
      final current = await _nextState(states, ++stateSequence);
      executionId = current.runtime.execution?.id;
      await state.acknowledge(states.current.deliverySequence);
    }
    LiveDisplayBlock? work;
    var timelineSequence = 1;
    while (work == null) {
      final batch = await _nextTimeline(events, ++timelineSequence);
      work = batch.live?.blocks
          .where((b) => b.body is WorkDisplayBlock)
          .firstOrNull;
      if (work != null) break;
    }
    final body = work.body as WorkDisplayBlock;
    final members = await feed.openDisplayMembers(
      reference: body.members,
      window: const LatestDisplayMembers(),
      demand: chatDemand,
    );
    final active = (await members.next())!;
    expect(active.sealed, isFalse);
    expect(active.entries.single.record.atom.lifecycle, isA<ActiveChatAtom>());
    final next = members.next();
    await api.stopThread(
      _thread,
      executionId,
      operationId: const OperationId('stop-story'),
    );
    final cancelled = (await next)!;
    expect(cancelled.sealed, isTrue);
    expect(
      (cancelled.entries.single.record.atom.lifecycle as TerminalChatAtom)
          .outcome,
      ChatTerminalOutcome.cancelled,
    );
    expect(
      cancelled.entries.single.record.contentSource,
      isNot(isA<CompletedOriginal>()),
    );
    expect(await members.next(), isNull);
    await expectLater(
      feed.reader.readCompleted(
        recordId: active.entries.single.memberKey,
        demand: chatDemand,
      ),
      throwsA(isA<StudioFailure>()),
    );

    DisplayBlock? sealed;
    while (sealed == null) {
      final batch = await _nextTimeline(events, ++timelineSequence);
      sealed = batch.blocks.where((b) => b.id == work!.id).firstOrNull;
      if (sealed != null) {
        expect(batch.live!.blocks, isEmpty);
        break;
      }
    }
    final stoppedMembers = await feed.openDisplayMembers(
      reference: (sealed.body as WorkDisplayBlock).members,
      window: const LatestDisplayMembers(),
      demand: chatDemand,
    );
    final stoppedPage = (await stoppedMembers.next())!;
    expect(
      (stoppedPage.entries.single.record.atom.lifecycle as TerminalChatAtom)
          .outcome,
      ChatTerminalOutcome.cancelled,
    );
    await stoppedMembers.close();
    await feed.close();
    await state.close();
  });

  test('partial append keeps live unchanged until the matching sealed prefix arrives', () async {
    final api = await _open();
    api.seedDisplayBlocks(
      threadId: _thread,
      blocks: [],
      live: TailSnapshot(
        currentWorkId: null,
        revision: 1,
        layoutRevision: 1,
        readyFrontier: 3,
        executionPresent: true,
        blocks: [
          for (var i = 1; i <= 2; i++)
            LiveDisplayBlock(
              id: 'handoff-$i',
              blockOrder: 3 + i,
              body: SingleDisplayBlock(
                visibility: SingleVisibility.content,
                record: DisplayRecord(
                  atom: chatAtomMessage('handoff-$i'),
                  contentSource: const CurrentAtom(),
                ),
              ),
              state: DisplayBlockState.sealed,
            ),
        ],
      ),
    );
    final feed = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: _one,
    );
    final events = _CursorPeer(feed);
    addTearDown(events.cancel);
    final initial = await _nextTimeline(events, 1);
    expect(initial.live!.blocks.single.id, 'handoff-2');
    api.seedDisplayBlocks(
      threadId: _thread,
      blocks: [
        for (var i = 1; i <= 2; i++)
          displaySingle(chatMessage('handoff-$i'), blockOrder: 3 + i),
      ],
      live: TailSnapshot(
        currentWorkId: null,
        revision: 2,
        layoutRevision: 2,
        readyFrontier: 5,
        executionPresent: false,
        blocks: [],
      ),
    );

    final first = await _nextTimeline(events, 2);
    expect(first.fromOrder, 3);
    expect(first.throughOrder, 4);
    expect(first.blocks.single.id, 'handoff-1');
    expect(first.live, isNull);

    final second = await _nextTimeline(events, 3);
    expect(second.fromOrder, 4);
    expect(second.throughOrder, 5);
    expect(second.blocks.single.id, 'handoff-2');
    expect(second.live!.blocks, isEmpty);
    await feed.close();
  });

  test(
    'regression: append finishes its captured target before newer display cuts',
    () async {
      final api = await _open();
      final feed = await api.openTimelineReader(
        _thread,
        presentationVersion: presentationVersion,
        readerProtocolVersion: timelineReaderProtocolVersion,
        demand: _one,
      );
      final events = _CursorPeer(feed);
      addTearDown(events.cancel);
      expect((await _nextTimeline(events, 1)).throughOrder, 3);

      TailSnapshot live(int through, String id) => TailSnapshot(
        currentWorkId: null,
        revision: through,
        layoutRevision: through,
        readyFrontier: through,
        executionPresent: true,
        blocks: [
          LiveDisplayBlock(
            id: id,
            blockOrder: through + 1,
            body: SingleDisplayBlock(
              visibility: SingleVisibility.content,
              record: DisplayRecord(
                atom: chatAtomMessage(id),
                contentSource: const CurrentAtom(),
              ),
            ),
            state: DisplayBlockState.open,
          ),
        ],
      );
      api.seedDisplayBlocks(
        threadId: _thread,
        blocks: [
          displaySingle(chatMessage('fixed-4'), blockOrder: 4),
          displaySingle(chatMessage('fixed-5'), blockOrder: 5),
        ],
        live: live(5, 'live-at-five'),
      );

      final first = await _nextTimeline(events, 2);
      expect(first.fromOrder, 3);
      expect(first.throughOrder, 4);
      expect(first.live, isNull);

      api.seedDisplayBlocks(
        threadId: _thread,
        blocks: [displaySingle(chatMessage('newer-6'), blockOrder: 6)],
        live: live(6, 'live-at-six'),
      );

      final target = await _nextTimeline(events, 3);
      expect(target.fromOrder, 4);
      expect(target.throughOrder, 5);
      expect(target.blocks.single.id, 'fixed-5');
      expect(target.live, isNull, reason: 'one head fills the response budget');
      final fixedTail = await _nextTimeline(events, 4);
      expect(fixedTail.blocks, isEmpty);
      expect(fixedTail.throughOrder, 5);
      expect(fixedTail.live!.blocks.single.id, 'live-at-five');
      final newer = await _nextTimeline(events, 5);
      expect(newer.fromOrder, 5);
      expect(newer.throughOrder, 6);
      expect(newer.blocks.single.id, 'newer-6');
      expect(newer.live, isNull);
      final newTail = await _nextTimeline(events, 6);
      expect(newTail.live!.readyFrontier, 6);
      expect(newTail.live!.blocks.single.id, 'live-at-six');
      expect(newTail.live!.revision, greaterThan(fixedTail.live!.revision));
      await feed.close();
    },
  );

  test(
    'regression: sealing unchanged Work members wakes the final page then EOF',
    () async {
      final api = await _open();
      final ref = DisplayBlockRef(
        databaseId: api.conversationDatabaseId(_thread),
        blockId: 'seal-unchanged-work',
      );
      final body = WorkDisplayBlock(timing: displayTiming(), members: ref);
      final member = DisplayMemberHead(
        memberKey: 'already-terminal',
        memberOrder: 1,
        record: DisplayRecord(
          atom: chatAtomMessage('already-terminal'),
          contentSource: const CurrentAtom(),
        ),
      );
      api.seedDisplayBlocks(
        threadId: _thread,
        blocks: [],
        live: TailSnapshot(
          currentWorkId: null,
          revision: 1,
          layoutRevision: 1,
          readyFrontier: 3,
          executionPresent: false,
          blocks: [
            LiveDisplayBlock(
              id: ref.blockId,
              blockOrder: 4,
              body: body,
              state: DisplayBlockState.sealed,
            ),
          ],
        ),
        members: {
          ref: [member],
        },
      );
      final feed = await api.openTimelineReader(
        _thread,
        presentationVersion: presentationVersion,
        readerProtocolVersion: timelineReaderProtocolVersion,
        demand: chatDemand,
      );
      final members = await feed.openDisplayMembers(
        reference: ref,
        window: const LatestDisplayMembers(),
        demand: chatDemand,
      );
      final initial = (await members.next())!;
      expect(initial.sealed, isFalse);
      final waiting = members.next();
      api.seedDisplayBlocks(
        threadId: _thread,
        blocks: [DisplayBlock(id: ref.blockId, blockOrder: 4, body: body)],
        live: TailSnapshot(
          currentWorkId: null,
          revision: 2,
          layoutRevision: 2,
          readyFrontier: 4,
          executionPresent: false,
          blocks: [],
        ),
      );
      final sealed = (await waiting.timeout(const Duration(seconds: 1)))!;
      expect(sealed.revision, greaterThan(initial.revision));
      expect(sealed.sealed, isTrue);
      expect(sealed.entries.single.memberKey, member.memberKey);
      expect(
        sealed.entries.single.record.atom.lifecycle,
        isA<TerminalChatAtom>(),
      );
      expect(await members.next(), isNull);
      final fresh = await feed.openDisplayMembers(
        reference: ref,
        window: const LatestDisplayMembers(),
        demand: chatDemand,
      );
      final freshPage = (await fresh.next())!;
      expect(freshPage.revision, sealed.revision);
      expect(freshPage.sealed, isTrue);
      expect(
        freshPage.entries.single.memberKey,
        sealed.entries.single.memberKey,
      );
      expect(await fresh.next(), isNull);
      await feed.close();
    },
  );

  test('regression: conflicting display identity rejects the whole fixture install atomically', () async {
    for (final conflict in [
      'work-to-single',
      'single-to-work',
      'different-single-member',
      'different-work-member',
    ]) {
      final api = await _open();
      final ref = DisplayBlockRef(
        databaseId: api.conversationDatabaseId(_thread),
        blockId: 'stable-$conflict',
      );
      final work = WorkDisplayBlock(timing: displayTiming(), members: ref);
      final single = SingleDisplayBlock(
        visibility: SingleVisibility.content,
        record: DisplayRecord(
          atom: chatAtomMessage('stable-member'),
          contentSource: const CurrentAtom(),
        ),
      );
      final DisplayBlockBody original =
          conflict == 'work-to-single' || conflict == 'different-work-member'
          ? work
          : single;
      final DisplayBlockBody replacement = switch (conflict) {
        'work-to-single' => single,
        'single-to-work' => work,
        'different-work-member' => work,
        _ => SingleDisplayBlock(
          visibility: SingleVisibility.content,
          record: DisplayRecord(
            atom: chatAtomMessage('other-member'),
            contentSource: const CurrentAtom(),
          ),
        ),
      };
      final head = DisplayMemberHead(
        memberKey: 'stable-member',
        memberOrder: 1,
        record: DisplayRecord(
          atom: chatAtomMessage('stable-member'),
          contentSource: const CurrentAtom(),
        ),
      );
      api.seedDisplayBlocks(
        threadId: _thread,
        blocks: [],
        live: TailSnapshot(
          currentWorkId: null,
          revision: 1,
          layoutRevision: 1,
          readyFrontier: 3,
          executionPresent: false,
          blocks: [
            LiveDisplayBlock(
              id: ref.blockId,
              blockOrder: 4,
              body: original,
              state: DisplayBlockState.sealed,
            ),
          ],
        ),
        members: original is WorkDisplayBlock
            ? {
                ref: [head],
              }
            : null,
      );
      final feed = await api.openTimelineReader(
        _thread,
        presentationVersion: presentationVersion,
        readerProtocolVersion: timelineReaderProtocolVersion,
        demand: chatDemand,
      );
      final events = _CursorPeer(feed);
      addTearDown(events.cancel);
      final before = await _nextTimeline(events, 1);
      DisplayMembers? memberRead;
      DisplayMemberPage? initialPage;
      if (original is WorkDisplayBlock) {
        memberRead = await feed.openDisplayMembers(
          reference: ref,
          window: const LatestDisplayMembers(),
          demand: chatDemand,
        );
        initialPage = await memberRead.next();
      }

      expect(
        () => api.seedDisplayBlocks(
          threadId: _thread,
          blocks: [
            displaySingle(
              chatMessage('must-not-install-$conflict'),
              blockOrder: 4,
            ),
            DisplayBlock(id: ref.blockId, blockOrder: 5, body: replacement),
          ],
          live: TailSnapshot(
            currentWorkId: null,
            revision: 2,
            layoutRevision: 2,
            readyFrontier: 5,
            executionPresent: false,
            blocks: [],
          ),
          members: original is WorkDisplayBlock
              ? {
                  ref: [
                    DisplayMemberHead(
                      memberKey: 'replacement',
                      memberOrder: 1,
                      record: DisplayRecord(
                        atom: chatAtomMessage('replacement'),
                        contentSource: const CurrentAtom(),
                      ),
                    ),
                  ],
                }
              : null,
        ),
        throwsA(isA<StudioFailure>()),
        reason: conflict,
      );

      final afterFeed = await api.openTimelineReader(
        _thread,
        presentationVersion: presentationVersion,
        readerProtocolVersion: timelineReaderProtocolVersion,
        demand: chatDemand,
      );
      final afterEvents = _CursorPeer(afterFeed);
      addTearDown(afterEvents.cancel);
      final after = await _nextTimeline(afterEvents, 1);
      expect(after.throughOrder, before.throughOrder, reason: conflict);
      expect(after.blocks.map((b) => b.id), before.blocks.map((b) => b.id));
      expect(after.live!.revision, before.live!.revision);
      expect(after.live!.blocks.single.id, ref.blockId);
      expect(after.live!.blocks.single.body.runtimeType, original.runtimeType);
      if (original is SingleDisplayBlock) {
        final preserved = after.live!.blocks.single.body as SingleDisplayBlock;
        expect(preserved.record.atom.id, original.record.atom.id);
      }
      if (memberRead != null) {
        final fresh = await afterFeed.openDisplayMembers(
          reference: ref,
          window: const LatestDisplayMembers(),
          demand: chatDemand,
        );
        final preserved = (await fresh.next())!;
        expect(preserved.revision, initialPage!.revision);
        expect(preserved.sealed, isFalse);
        expect(preserved.entries.single.memberKey, head.memberKey);
        expect(preserved.entries.single.record.atom.id, head.record.atom.id);
      }
      // A valid retry still owns the next position after the rejected prefix.
      api.seedDisplayBlocks(
        threadId: _thread,
        blocks: [DisplayBlock(id: ref.blockId, blockOrder: 4, body: original)],
        live: TailSnapshot(
          currentWorkId: null,
          revision: 2,
          layoutRevision: 2,
          readyFrontier: 4,
          executionPresent: false,
          blocks: [],
        ),
      );

      final valid = await _nextTimeline(afterEvents, 2);
      expect(valid.fromOrder, 3);
      expect(valid.throughOrder, 4);
      expect(valid.blocks.single.id, ref.blockId);
      await afterFeed.close();
      await feed.close();
    }
  });

  test(
    'late Timeline factory is joined by the existing runtime owner registry',
    () async {
      final api = await _open();
      final entered = Completer<TimelineReader>();
      final release = Completer<TimelineReader>();
      api.timelineReaderFactory = (_, connection) {
        entered.complete(connection);
        return release.future;
      };
      final opening = api.openTimelineReader(
        _thread,
        presentationVersion: presentationVersion,
        readerProtocolVersion: timelineReaderProtocolVersion,
        demand: chatDemand,
      );
      final rejected = expectLater(opening, throwsA(isA<StudioFailure>()));
      final connection = await entered.future;
      final closing = api.cancelDartSubscriptions(budgetMs: 1000);
      release.complete(connection);
      await rejected;
      expect(await closing, isEmpty);
      await expectLater(
        connection.reader.readBusinessRefs(),
        throwsA(isA<StudioFailure>()),
      );
    },
  );

  test('member next ignores unrelated state; close wakes pending reads and drains owned resources without ACK', () async {
    final api = await _open();
    final ref = DisplayBlockRef(
      databaseId: api.conversationDatabaseId(_thread),
      blockId: 'waiting-work',
    );
    api.seedDisplayBlocks(
      threadId: _thread,
      blocks: [],
      live: TailSnapshot(
        currentWorkId: ref.blockId,
        revision: 1,
        layoutRevision: 1,
        readyFrontier: 3,
        executionPresent: false,
        blocks: [
          LiveDisplayBlock(
            id: ref.blockId,
            blockOrder: 4,
            body: WorkDisplayBlock(timing: displayTiming(), members: ref),
            state: DisplayBlockState.open,
          ),
        ],
      ),
      members: {
        ref: [
          DisplayMemberHead(
            memberKey: 'waiting-member',
            memberOrder: 1,
            record: DisplayRecord(
              atom: chatAtomMessage('waiting-member'),
              contentSource: const CurrentAtom(),
            ),
          ),
        ],
      },
    );
    final feed = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: chatDemand,
    );
    final events = _CursorPeer(feed);
    addTearDown(events.cancel);
    await _nextTimeline(events, 1); // Own Timeline Set credit; never ACK it.
    final members = await feed.openDisplayMembers(
      reference: ref,
      window: const LatestDisplayMembers(),
      demand: chatDemand,
    );
    expect((await members.next())!.sealed, isFalse);
    var woke = false;
    final waiting = members.next().then((page) {
      woke = true;
      return page;
    });
    api.seedConversationState(
      _thread,
      const ThreadActivityUpdate(activity: null),
    );
    await feed.reader.readBusinessRefs();
    expect(woke, isFalse);
    expect(await api.cancelDartSubscriptions(budgetMs: 1000), isEmpty);
    expect(await waiting, isNull);
    await expectLater(events.next(), throwsA(isA<StudioFailure>()));
    await expectLater(
      feed.reader.readBusinessRefs(),
      throwsA(isA<StudioFailure>()),
    );
  });

  test('recording and mapped readers retain queries independently from response confirmation', () async {
    final api = RecordingDemoTransport();
    await api.readBootstrap();
    addTearDown(
      () async =>
          expect(await api.cancelDartSubscriptions(budgetMs: 1000), isEmpty),
    );
    api.timelineReaderFactory = (_, feed) async => MappedTimelineReader(feed);
    final feed = await api.openTimelineReader(
      _thread,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: chatDemand,
    ) as RecordingTimelineReader;
    expect(api.timelineReaders.single, same(feed));
    final gate = Completer<void>();
    feed.initialGate = gate;
    final events = _CursorPeer(feed);
    addTearDown(events.cancel);
    var delivered = false;
    final initial = _nextTimeline(events, 1).then((batch) {
      delivered = true;
      return batch;
    });
    await feed.initialEntered.future;
    expect(delivered, isFalse);
    expect(feed.acceptedCursors, isEmpty);
    expect(feed.deliveredFrames, 0);
    gate.complete();
    final batch = await initial;
    expect(feed.deliveredFrames, 1);
    expect(feed.acceptedCursors, isEmpty);
    final work =
        batch.blocks.firstWhere((b) => b.body is WorkDisplayBlock).body
            as WorkDisplayBlock;
    final members = await feed.openDisplayMembers(
      reference: work.members,
      window: const LatestDisplayMembers(),
      demand: chatDemand,
    );
    expect((await members.next())!.sealed, isTrue);
    expect(feed.detailCalls, 1);
    expect(feed.acceptedCursors, isEmpty);

    expect(feed.acceptedCursors, isEmpty);
    await feed.close();
    expect(feed.joined.isCompleted, isTrue);
  });
}

final class _CursorPeer {
  _CursorPeer(this.reader) : after = reader.metadata.initialCursor;
  final TimelineReader reader;
  ViewCursor after;
  int count = 0;
  Future<ViewUpdate> next() async {
    final update = await reader.next(after: after);
    expect(update.after, after);
    expect(update.next, isNot(after));
    expect(update.presentationVersion, presentationVersion);
    expect(update.readerProtocolVersion, timelineReaderProtocolVersion);
    expect(
      update.history.placement,
      count++ == 0 ? HistoryPlacement.set : HistoryPlacement.append,
    );
    after = update.next;
    return update;
  }

  Future<void> cancel() => reader.close();
}

Future<ViewUpdate> _nextTimeline(_CursorPeer reader, int sequence) async {
  expect(reader.count + 1, sequence);
  return reader.next();
}

Future<ThreadWorkspace> _nextState(
  StreamIterator<ConversationFrame> events,
  int sequence,
) async {
  expect(await events.moveNext(), isTrue);
  final frame = events.current;
  expect(frame.threadId, _thread);
  expect(frame.deliverySequence, sequence);
  expect(frame.event, isA<ConversationStateEvent>());
  final state = (frame.event as ConversationStateEvent).frame;
  expect(state, isA<ThreadSnapshotFrame>());
  return (state as ThreadSnapshotFrame).workspace;
}

Future<_FastDemo> _open([_FastDemo? transport]) async {
  final api = transport ?? _FastDemo();
  await api.readBootstrap();
  addTearDown(
    () async =>
        expect(await api.cancelDartSubscriptions(budgetMs: 1000), isEmpty),
  );
  return api;
}

class _FastDemo extends DemoStudioTransport {
  @override
  Duration get promptStartDelay => const Duration(milliseconds: 2);
  @override
  Duration get promptActivityDelay => const Duration(milliseconds: 2);
  @override
  Duration get promptToolDelay => const Duration(milliseconds: 2);
}

class _SlowStoryDemo extends _FastDemo {
  @override
  Duration get promptActivityDelay => const Duration(days: 1);
}
