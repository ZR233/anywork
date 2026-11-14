import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/timeline_observation.dart';
import '../support/display_fixtures.dart';

const _source = ForegroundTurnChatSource(turnId: 'prepared-turn');
const _other = ForegroundTurnChatSource(turnId: 'other-turn');
const _reference = DisplayBlockRef(databaseId: 'db', blockId: 'work');

ChatAtom _tool(ChatSourceId source) => ChatAtom(
  id: 'tool-member',
  completionItemId: 'handoff-completion',
  completionSeq: 8,
  source: source,
  sourceOrder: 1,
  kind: ChatAtomKind.toolCall,
  delivery: ChatDeliveryKind.backgroundHandoff,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.transferred,
  ),
  turnId: source is ForegroundTurnChatSource ? source.turnId : null,
  contents: [],
  payload: InlinePayload(bytes: utf8.encode('private-body-must-not-be-logged')),
);

DisplayBlock _single(ChatSourceId source) => DisplayBlock(
  id: 'single',
  blockOrder: 2,
  body: SingleDisplayBlock(
    visibility: SingleVisibility.content,
    record: DisplayRecord(
      atom: _tool(source),
      contentSource: CompletedOriginal(completionId: 'handoff-completion'),
    ),
  ),
);

DisplayMemberPage _page(ChatSourceId source, {int order = 1, int? before}) =>
    DisplayMemberPage(
      block: _reference,
      revision: 1,
      sealed: true,
      before: before,
      entries: [
        DisplayMemberHead(
          memberKey: 'stable-member-key',
          memberOrder: order,
          record: DisplayRecord(
            atom: _tool(source),
            contentSource: CompletedOriginal(
              completionId: 'handoff-completion',
            ),
          ),
        ),
      ],
    );

final class _Fixture {
  _Fixture(WidgetTester tester, {int generation = 1}) {
    lease = TimelineDisplayLease(
      threadId: 'thread',
      generation: generation,
      demand: const ReadDemand(maxItems: 32, maxBytes: 256 * 1024),
      content: content,
    );
    adapter = TimelineMessageController(
      lease.controller as InMemoryChatController,
      generation: generation,
    );
    observed = TimelineObservation(tester, () => lease);
    addTearDown(() async {
      adapter.dispose();
      unawaited(lease.retire());
      await tester.pump();
      expect(lease.queryCleanupError, isNull);
      expect(lease.isReleased, isTrue);
    });
  }
  final content = _Content();
  late final TimelineDisplayLease lease;
  late final TimelineMessageController adapter;
  late final TimelineObservation observed;
  Future<void> set(List<DisplayBlock> blocks) => adapter.applyTimeline(
    displayBatch(
      blocks,
      live: LiveDisplayWindow(
        currentWorkId: null,
        revision: 1,
        readyFrontier: blocks.isEmpty ? 0 : blocks.last.blockOrder,
        executionPresent: false,
        blocks: [],
      ),
    ),
  );
}

void main() {
  testWidgets('mixed-source Work qualifies through bounded member pages', (
    tester,
  ) async {
    final f = _Fixture(tester);
    await f.set([displayWork('work', 1)]);
    f.content.scope.replyForWindow = (window) async => switch (window) {
      LatestDisplayMembers() => _page(_other, order: 2, before: 2),
      BeforeDisplayMembers(:final memberOrder) => () {
        expect(memberOrder, 2);
        return _page(_source);
      }(),
    };
    expect(f.observed.singleBlocks, isEmpty);
    expect(await f.observed.hasHistoricalSource(_source), isTrue);
    expect(f.content.scope.demands, hasLength(2));
    for (final demand in f.content.scope.demands) {
      expect(demand.maxItems, 32);
      expect(demand.maxBytes, 16384);
    }
    for (final handle in f.content.scope.handles) {
      expect(handle.closeRequested, isTrue);
      expect(handle.closed, isTrue);
    }
    expect(
      f.lease.groupDisplays,
      isEmpty,
      reason: 'Provenance must not expand UI',
    );
  });

  testWidgets('another Turn Work cannot qualify the prepared source', (
    tester,
  ) async {
    final f = _Fixture(tester);
    await f.set([displayWork('work', 1)]);
    f.content.scope.reply = Future.value(_page(_other));
    expect(await f.observed.hasHistoricalSource(_source), isFalse);
    expect(f.content.scope.handles.single.closed, isTrue);
  });

  testWidgets('live Work without history admission is not sufficient', (
    tester,
  ) async {
    final f = _Fixture(tester);
    await f.set([]);
    f.lease.live.value = LiveDisplayWindow(
      currentWorkId: null,
      revision: 2,
      readyFrontier: 0,
      executionPresent: true,
      blocks: [
        LiveDisplayBlock(
          id: 'work',
          blockOrder: 1,
          body: displayWork('work', 1).body,
          source: _source,
          state: DisplayBlockState.sealed,
        ),
      ],
    );
    expect(await f.observed.hasHistoricalSource(_source), isFalse);
    expect(f.content.opened, 0);
  });

  testWidgets('same-source historical Single still qualifies without a query', (
    tester,
  ) async {
    final f = _Fixture(tester);
    await f.set([_single(_source)]);
    expect(await f.observed.hasHistoricalSource(_source), isTrue);
    expect(f.content.opened, 0);
  });

  testWidgets('member failure propagates and its real handle closes', (
    tester,
  ) async {
    final f = _Fixture(tester);
    await f.set([displayWork('work', 1)]);
    final failure = StateError('member-query-failure');
    f.content.scope.reply = Future.value(_page(_source));
    f.content.scope.nextFailure = failure;
    await expectLater(
      f.observed.hasHistoricalSource(_source),
      throwsA(same(failure)),
    );
    expect(f.content.scope.handles.single.closeRequested, isTrue);
    expect(f.content.scope.handles.single.closed, isTrue);
  });

  testWidgets(
    'late old lease provenance cannot qualify a new same-Thread lease',
    (tester) async {
      final old = _Fixture(tester);
      final next = _Fixture(tester, generation: 2);
      await old.set([displayWork('work', 1)]);
      await next.set([displayWork('work', 1)]);
      var borrowed = old.lease;
      final observed = TimelineObservation(tester, () => borrowed);
      final reply = Completer<DisplayMemberPage>();
      old.content.scope.reply = reply.future;
      final result = observed.hasHistoricalSource(_source);
      final rejected = expectLater(result, throwsA(isA<TestFailure>()));
      await old.content.scope.entered.future;
      borrowed = next.lease;
      reply.complete(_page(_source));
      await rejected;
      expect(old.content.scope.handles.single.closed, isTrue);
    },
  );

  testWidgets('failure snapshot is metadata only and starts no read', (
    tester,
  ) async {
    final f = _Fixture(tester);
    await f.set([displayWork('work', 1), _single(_source)]);
    f.lease.live.value = LiveDisplayWindow(
      currentWorkId: null,
      revision: 9,
      readyFrontier: 2,
      executionPresent: true,
      blocks: [
        LiveDisplayBlock(
          id: 'background-live',
          blockOrder: 3,
          body: SingleDisplayBlock(
            visibility: SingleVisibility.content,
            record: DisplayRecord(
              atom: _tool(
                const BackgroundResultChatSource(messageId: 'result'),
              ),
              contentSource: const CurrentAtom(),
            ),
          ),
          source: const BackgroundResultChatSource(messageId: 'result'),
          state: DisplayBlockState.open,
        ),
      ],
    );
    final cut = timelineWaitFailureSnapshot(
      tester: tester,
      selectedThreadId: 'thread',
      submittedThreadId: 'thread',
      submittedTurnId: 'prepared-turn',
      previousTurnId: 'previous-turn',
      targetTurnId: 'prepared-turn',
      expectedOutcome: 'completed',
      lease: f.lease,
      session: const ThreadSessionState(threadId: 'thread'),
    );
    final history = cut['history'] as List;
    expect((history.first as Map)['bodyKind'], 'work');
    expect((history.first as Map)['source'], isNull);
    expect((history.last as Map)['source'], {
      'kind': 'foregroundTurn',
      'turnId': 'prepared-turn',
    });
    expect(
      ((cut['live'] as Map)['blocks'] as List).single,
      containsPair('state', 'open'),
    );
    expect(cut['mainScrollableCount'], 0);
    expect(cut['previousTurnId'], 'previous-turn');
    expect(jsonEncode(cut), isNot(contains('private-body-must-not-be-logged')));
    expect(f.content.opened, 0);
  });
}

final class _Content extends Fake implements ConversationContent {
  final scope = _Scope();
  int opened = 0;
  @override
  ConversationQueryScope openScope({required int generation}) {
    opened++;
    return scope;
  }
}

final class _Scope extends Fake implements TimelineQueryScope {
  late Future<DisplayMemberPage> reply;
  Future<DisplayMemberPage> Function(DisplayMemberWindow)? replyForWindow;
  final entered = Completer<void>();
  final demands = <ReadDemand>[];
  final handles = <_Members>[];
  bool active = true;
  bool closed = false;
  Object? nextFailure;
  @override
  bool get isActive => active;
  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) async {
    expect(reference, _reference);
    if (replyForWindow == null) expect(window, isA<LatestDisplayMembers>());
    demands.add(demand);
    final handle = _Members(replyForWindow?.call(window) ?? reply, nextFailure);
    handles.add(handle);
    if (!entered.isCompleted) entered.complete();
    return handle;
  }

  @override
  void retire() => active = false;
  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    closed = true;
    return CloseReport();
  }
}

final class _Members implements DisplayMembers {
  _Members(this.reply, this.failure);
  final Future<DisplayMemberPage> reply;
  final Object? failure;
  bool closeRequested = false;
  bool closed = false;
  @override
  Future<DisplayMemberPage?> next() async {
    if (failure case final error?) throw error;
    return await reply;
  }

  @override
  void requestClose() => closeRequested = true;
  @override
  Future<void> close() async => closed = true;
}
