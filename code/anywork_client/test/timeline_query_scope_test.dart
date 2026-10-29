import 'dart:async';

import 'package:anywork_client/src/conversation/data/conversation_read_scope.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  late TestConversationTransport transport;
  late ResourceBudget budget;
  late ConversationReadScope scope;
  setUp(() {
    transport = TestConversationTransport();
    budget = ResourceBudget();
    scope = ConversationReadScope(
      threadId: 'thread',
      timelineEpoch: 'epoch',
      generation: 7,
      transport: transport,
      budget: budget,
    );
  });

  test('invalid page and detail arguments never reach transport', () async {
    var calls = 0;
    transport.onPage = (_, __, ___) {
      calls++;
      throw StateError('unexpected');
    };
    transport.onDetail = (_, __, ___) {
      calls++;
      throw StateError('unexpected');
    };
    await expectLater(scope.page(limit: 0), throwsArgumentError);
    await expectLater(scope.page(limit: 101), throwsArgumentError);
    await expectLater(
      scope.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          timelineEpoch: 'wrong',
          field: ThreadTextFieldView(),
        ),
      ),
      throwsA(isA<ConversationContinuityError>()),
    );
    await expectLater(
      scope.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          timelineEpoch: 'epoch',
          field: ThreadTextFieldView(),
          maxBytes: 3,
        ),
      ),
      throwsArgumentError,
    );
    expect(calls, 0);
    expect(transport.opens, isEmpty);
    expect((await scope.close()).complete, isTrue);
  });

  test('empty detail chunk cannot claim a continuation', () async {
    transport.onDetail = (thread, item, query) async => ConversationDetailChunk(
      threadId: thread,
      timelineEpoch: 'epoch',
      itemId: item,
      field: query.field,
      text: '',
      totalBytes: 1,
      continuation: const ConversationQueryCursor('next'),
    );
    await expectLater(
      scope.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          timelineEpoch: 'epoch',
          field: ThreadTextFieldView(),
        ),
      ),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect((await scope.close()).complete, isTrue);
  });

  test(
    'page descriptors remain frozen and detail keeps the same field identity',
    () async {
      final source = [
        const ConversationRawPayloadDescriptor(format: 'json', version: 1),
      ];
      final descriptor = ConversationRawDescriptor(
        origin: ThreadRawItemOrigin.stored,
        payloads: source,
        notice: 'notice',
        recordedAt: DateTime.utc(2026),
      );
      final item = ConversationItem(
        header: const ConversationItemHeader(
          id: 'raw',
          threadId: 'thread',
          appendSeq: 1,
        ),
        source: const ConversationContentSource(),
        descriptor: descriptor,
        fields: const [
          ConversationFieldPreview(
            field: ThreadRawPayloadFieldView(0),
            text: 'a',
            totalBytes: 2,
          ),
        ],
      );
      transport.onPage = (thread, _, __) async => ConversationPage(
        threadId: thread,
        timelineEpoch: 'epoch',
        items: [item],
        before: null,
        hasOlder: false,
      );
      transport.onDetail = (thread, id, query) async => ConversationDetailChunk(
        threadId: thread,
        timelineEpoch: 'epoch',
        itemId: id,
        field: query.field,
        text: 'ab',
        totalBytes: 2,
      );
      final page = await scope.page();
      source.clear();
      final raw = page.items.single.descriptor as ConversationRawDescriptor;
      expect(raw.payloads.single.format, 'json');
      expect(() => raw.payloads.clear(), throwsUnsupportedError);
      expect(() => page.items.clear(), throwsUnsupportedError);
      expect(() => page.items.single.fields.clear(), throwsUnsupportedError);
      final detail = await scope.readDetail(
        itemId: 'raw',
        query: const ConversationDetailQuery(
          timelineEpoch: 'epoch',
          field: ThreadRawPayloadFieldView(0),
        ),
      );
      expect(detail.field, const ThreadRawPayloadFieldView(0));
      expect(detail.text, 'ab');
      expect((await scope.close()).complete, isTrue);
    },
  );

  test(
    'cold scope retains one reader across page and detail after feed closes',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open();
      final query = fixture.session().content.openScope(
        timelineEpoch: 'epoch',
        generation: 42,
      );
      fixture.transport.onPage = (thread, _, __) async => ConversationPage(
        threadId: thread,
        timelineEpoch: 'epoch',
        items: [],
        before: null,
        hasOlder: false,
      );
      fixture.transport.onDetail = (thread, item, q) async =>
          ConversationDetailChunk(
            threadId: thread,
            timelineEpoch: 'epoch',
            itemId: item,
            field: q.field,
            text: 'hello',
            totalBytes: 5,
          );
      await query.page();
      expect(fixture.transport.readers, hasLength(1));
      final reader = fixture.transport.readers.single;
      fixture.repository.setVisibleThread(null);
      await feed.closeCompleted.future;
      expect(reader.requested, isFalse);
      final detail = await query.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          timelineEpoch: 'epoch',
          field: ThreadTextFieldView(),
        ),
      );
      expect(detail.text, 'hello');
      expect(fixture.transport.readers.single, same(reader));
      expect((await query.close()).complete, isTrue);
      expect(reader.closeCalls, 1);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test(
    'retire while opening retains and closes the late reader before join',
    () async {
      final opened = Completer<ConversationHistoryReader>();
      transport.onOpenReader = (_) => opened.future;
      final query = scope.page();
      final rejected = expectLater(
        query,
        throwsA(isA<StaleConversationScope>()),
      );
      final first = await scope.close(deadline: DateTime.now());
      expect(first.complete, isFalse);
      final reader = TestHistoryReader(transport, 'thread')
        ..closeGate = Completer<void>();
      opened.complete(reader);
      await rejected;
      final second = await scope.close(deadline: DateTime.now());
      expect(second.complete, isFalse);
      expect(reader.requested, isTrue);
      expect(reader.closeCalls, 1);
      expect(budget.used(ResourceKind.pendingOperation), 1);
      reader.closeGate!.complete();
      expect((await scope.close()).complete, isTrue);
      expect(reader.closeCalls, 1);
      expect(budget.used(ResourceKind.pendingOperation), 0);
    },
  );

  test('reader close failure retains ownership until explicit retry', () async {
    transport.onPage = (thread, _, __) async => ConversationPage(
      threadId: thread,
      timelineEpoch: 'epoch',
      items: [],
      before: null,
      hasOlder: false,
    );
    await scope.page();
    final reader = transport.readers.single
      ..closeFailure = StateError('native close failed');
    expect((await scope.close()).complete, isFalse);
    expect(budget.used(ResourceKind.pendingOperation), 1);
    reader.closeFailure = null;
    expect((await scope.close()).complete, isTrue);
    expect(reader.closeCalls, 2);
    expect(budget.used(ResourceKind.pendingOperation), 0);
  });

  test(
    'reader identity mismatch is rejected and the same handle is closed',
    () async {
      final reader = TestHistoryReader(
        transport,
        'thread',
        timelineEpoch: 'other',
      );
      transport.onOpenReader = (_) async => reader;
      await expectLater(
        scope.page(),
        throwsA(isA<ConversationContinuityError>()),
      );
      expect(reader.requested, isTrue);
      expect((await scope.close()).complete, isTrue);
      expect(reader.closeCalls, 1);
      expect(budget.used(ResourceKind.pendingOperation), 0);
    },
  );

  test(
    'opaque page cursor and detail continuation preserve identity and UTF-8',
    () async {
      const before = ConversationQueryCursor('tlp2.opaque');
      const continuation = ConversationQueryCursor('tld2.opaque');
      transport.onPage = (thread, cursor, limit) async {
        expect((thread, cursor, limit), ('thread', before, 32));
        return ConversationPage(
          threadId: thread,
          timelineEpoch: 'epoch',
          items: [timelineItem(3, body: '你好')],
          before: null,
          hasOlder: false,
        );
      };
      transport.onDetail = (thread, item, query) async {
        expect(
          (thread, item, query.timelineEpoch, query.continuation),
          ('thread', 'item', 'epoch', continuation),
        );
        return ConversationDetailChunk(
          threadId: thread,
          timelineEpoch: 'epoch',
          itemId: item,
          field: query.field,
          text: '你好',
          totalBytes: 6,
        );
      };
      final page = await scope.page(before: before);
      expect(
        page.items.single.fieldFor(const ThreadTextFieldView())!.text,
        '你好',
      );
      final detail = await scope.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          timelineEpoch: 'epoch',
          field: ThreadTextFieldView(),
          continuation: continuation,
        ),
      );
      expect(detail.text, '你好');
      expect(detail.isLast, isTrue);
      expect(transport.opens, isEmpty);
      expect((await scope.close()).complete, isTrue);
    },
  );

  test(
    'retired scope rejects late reply and retains permit until actual join',
    () async {
      final native = Completer<ConversationPage>();
      transport.onPage = (_, __, ___) => native.future;
      final result = scope.page();
      final rejected = expectLater(
        result,
        throwsA(isA<StaleConversationScope>()),
      );
      expect(scope.pendingQueries, 1);
      expect(budget.used(ResourceKind.pendingOperation), 2);
      final report = await scope.close(deadline: DateTime.now());
      expect(report.complete, isFalse);
      expect(
        budget.used(ResourceKind.pendingOperation),
        greaterThanOrEqualTo(1),
      );
      native.complete(
        ConversationPage(
          threadId: 'thread',
          timelineEpoch: 'epoch',
          items: [],
          before: null,
          hasOlder: false,
        ),
      );
      await rejected;
      expect((await scope.close()).complete, isTrue);
      expect(budget.used(ResourceKind.pendingOperation), 0);
      expect(transport.opens, isEmpty);
    },
  );

  test('query errors propagate and epoch or continuation mismatch fails explicitly', () async {
    final failure = StateError('native failure');
    transport.onPage = (_, __, ___) => Future.error(failure);
    await expectLater(scope.page(), throwsA(same(failure)));
    transport.onPage = (_, __, ___) async => ConversationPage(
      threadId: 'thread',
      timelineEpoch: 'new',
      items: [],
      before: null,
      hasOlder: false,
    );
    await expectLater(
      scope.page(),
      throwsA(isA<ConversationContinuityError>()),
    );
    const token = ConversationQueryCursor('same');
    transport.onDetail = (thread, item, query) async => ConversationDetailChunk(
      threadId: thread,
      timelineEpoch: 'epoch',
      itemId: item,
      field: query.field,
      text: 'a',
      totalBytes: 1,
      continuation: token,
    );
    await expectLater(
      scope.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          timelineEpoch: 'epoch',
          field: ThreadTextFieldView(),
          continuation: token,
        ),
      ),
      throwsA(isA<ConversationContinuityError>()),
    );
    expect((await scope.close()).complete, isTrue);
  });

  test(
    'a pending independent page does not block feed delivery or lose its join',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open();
      final session = fixture.session();
      final pending = Completer<ConversationPage>();
      fixture.transport.onPage = (_, __, ___) => pending.future;
      final query = session.content.openScope(
        timelineEpoch: 'epoch',
        generation: 9,
      );
      final reply = query.page();
      final lateReply = expectLater(
        reply,
        throwsA(isA<StaleConversationScope>()),
      );
      await feed.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            workspace: ThreadWorkspace(
              thread: StudioThread(
                id: 'thread',
                projectId: 'project',
                title: 'Thread',
                mode: ThreadModeId.simple,
                delegationMode: DelegationMode.profile,
                delegationPreference: DelegationPreference.balanced,
                updatedAt: DateTime.utc(2026),
                workspacePath: '/project',
              ),
              revision: 1,
              interactions: const [],
              runtime: const ThreadRuntimeView(
                modelId: 'model',
                contextTokens: 0,
                contextWindow: 1,
                totalTokens: 0,
                costLabel: '',
                activeSkills: [],
                activeMcpServers: [],
                activeLspServers: [],
              ),
            ),
          ),
        ),
      );
      expect(feed.acknowledgements, [1, 2]);
      final first = await query.close(deadline: DateTime.now());
      expect(first.complete, isFalse);
      pending.complete(
        ConversationPage(
          threadId: 'thread',
          timelineEpoch: 'epoch',
          items: [],
          before: null,
          hasOlder: false,
        ),
      );
      await lateReply;
      expect((await query.close()).complete, isTrue);
      expect((await fixture.close()).complete, isTrue);
    },
  );
}
