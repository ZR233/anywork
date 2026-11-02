import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_children_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/src/conversation/data/conversation_repository_impl.dart';
import 'package:anywork_client/src/lifecycle/resource_budget.dart';
import 'package:anywork_client/src/studio/stores/thread_directory_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart'
    show Chat, ChatAnimatedListReversed;
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart';
import '../support/pump_client_future.dart';

void main() {
  testWidgets(
    'Children display diagnostics borrow the real controller and actual admitted operations without IO',
    (tester) async {
      final transport = _Transport();
      final repository = ConversationRepositoryImpl(
        transport: transport,
        directory: ThreadDirectoryStore(),
        budget: ResourceBudget(),
        onRevision: (_, _) {},
      );
      final recorded = _RecordingRepository(repository);
      final displays = <TimelineChildrenDisplay>{};
      var registrations = 0;
      var unregistrations = 0;
      var parentActive = true;
      VoidCallback register(TimelineChildrenDisplay display) {
        registrations++;
        displays.add(display);
        return () {
          unregistrations++;
          displays.remove(display);
        };
      }

      Widget host() => MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TimelineChildrenConnector(
            repository: recorded,
            threadId: 'thread',
            parentId: 'opaque-parent',
            registerDisplay: register,
            isParentActive: () => parentActive,
          ),
        ),
      );
      final page = Completer<ChatBatch>();
      var loads = 0;
      transport.feed.reader.onOlder = (before, _) {
        loads++;
        expect(before, 'before');
        return page.future;
      };
      await tester.pumpWidget(host());
      await tester.pump();
      expect(displays, isEmpty);
      transport.feed.send(
        ConversationChatEvent(batch: chatSet(before: 'before')),
      );
      await tester.pump();
      await tester.pump();
      final display = displays.single;
      final initialGeneration = display.generation;
      final controller = tester.widget<Chat>(find.byType(Chat)).chatController;
      expect(
        identical(display.messages.single, controller.messages.single),
        isTrue,
      );
      expect(
        (
          display.parentId,
          display.ready,
          display.appliedSets,
          display.appliedPrepends,
          display.appliedAppends,
        ),
        ('opaque-parent', true, 1, 0, 0),
      );
      expect(display.olderCursor, 'before');
      final operations = <String>[];
      var retireDuringSet = false;
      final observer = controller.operationsStream.listen((op) {
        operations.add(op.type.name);
        if (retireDuringSet && op.type.name == 'set') {
          retireDuringSet = false;
          recorded.contents.single.refresh();
        }
      });
      final older = tester
          .widget<ChatAnimatedListReversed>(
            find.byType(ChatAnimatedListReversed),
          )
          .onEndReached!();
      expect(display.loadingOlder, isTrue);
      final ioBefore = (transport.feeds.length, loads);
      for (var i = 0; i < 5; i++) {
        expect(display.isCurrent, isTrue);
        expect(display.messages.map((m) => m.id), ['item']);
        expect(display.error, isNull);
      }
      expect((transport.feeds.length, loads), ioBefore);
      transport.feed.send(
        ConversationChatEvent(
          batch: ChatBatch(
            placement: ChatPlacement.append,
            messages: [chatMessage(id: 'append')],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(display.appliedAppends, 1);
      page.complete(
        ChatBatch(
          placement: ChatPlacement.prepend,
          messages: [chatMessage(id: 'older')],
        ),
      );
      await pumpClientFuture(tester, older, 'diagnostic page applied');
      await tester.pump();
      expect(display.messages.map((m) => m.id), ['older', 'item', 'append']);
      expect(display.messages.toList(), controller.messages);
      expect(
        (display.appliedSets, display.appliedPrepends, display.appliedAppends),
        (1, 1, 1),
      );
      expect(operations, ['insertAll', 'insertAll']);
      expect(display.loadingOlder, isFalse);
      expect(display.olderCursor, isNull);
      recorded.contents.single.refresh();
      expect(
        displays,
        isEmpty,
        reason: 'Attempt retirement synchronously revokes the borrow',
      );
      await pumpClientUntil(
        tester,
        () => transport.feeds.length == 2,
        'diagnostic replacement feed',
      );
      retireDuringSet = true;
      transport.feeds.last.send(
        ConversationChatEvent(
          batch: chatSet(messages: [chatMessage(id: 'retired-during-Set')]),
        ),
      );
      await tester.pump();
      await pumpClientUntil(
        tester,
        () => transport.feeds.length == 3,
        'Set await replacement feed',
      );
      expect(retireDuringSet, isFalse);
      expect(displays, isEmpty);
      expect(
        (display.appliedSets, display.appliedPrepends, display.appliedAppends),
        (0, 0, 0),
        reason: 'An old adapter success cannot increment the replacement generation',
      );
      transport.feeds.last.send(
        ConversationChatEvent(
          batch: chatSet(
            messages: [chatMessage(id: 'replacement', body: '旧 Children 正文')],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(displays.single, same(display));
      expect(display.generation, greaterThan(initialGeneration));
      expect(
        (display.appliedSets, display.appliedPrepends, display.appliedAppends),
        (1, 0, 0),
      );
      expect(display.messages.single.id, 'replacement');
      expect(find.text('旧 Children 正文'), findsOneWidget);
      final generationBeforeSet = display.generation;
      transport.feeds.last.send(
        ConversationChatEvent(
          batch: chatSet(
            messages: [chatMessage(id: 'replacement', body: '新 Children 正文')],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('旧 Children 正文'), findsNothing);
      expect(find.text('新 Children 正文'), findsOneWidget);
      expect(display.generation, greaterThan(generationBeforeSet));
      expect(
        (display.appliedSets, display.appliedPrepends, display.appliedAppends),
        (1, 0, 0),
      );
      expect(
        identical(display.messages.single, controller.messages.single),
        isTrue,
      );
      parentActive = false;
      expect(displays.where((display) => display.isCurrent), isEmpty);
      expect(display.messages, isEmpty);
      final afterReplacementIO = (transport.feeds.length, loads);
      await tester.pumpWidget(host());
      expect(displays, isEmpty);
      expect((transport.feeds.length, loads), afterReplacementIO);
      expect((registrations, unregistrations), (3, 3));
      await tester.pumpWidget(const SizedBox());
      expect(
        (await pumpClientFuture(
          tester,
          repository.close(),
          'close diagnostic children',
        )).complete,
        isTrue,
      );
      await pumpClientFuture(
        tester,
        observer.cancel(),
        'close diagnostic observer',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real Children component releases controller stream independently of unresolved native close',
    (tester) async {
      final transport = _Transport();
      final repository = ConversationRepositoryImpl(
        transport: transport,
        directory: ThreadDirectoryStore(),
        budget: ResourceBudget(),
        onRevision: (_, _) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TimelineChildrenConnector(
              repository: repository,
              threadId: 'thread',
              parentId: 'opaque-parent',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(transport.opened.isCompleted, isTrue);
      transport.feed.send(ConversationChatEvent(batch: chatSet()));
      await tester.pump();
      await tester.pump();
      expect(transport.feed.acknowledgements, [1]);
      expect(transport.scope, isA<ChildrenChatScope>());
      expect((transport.scope as ChildrenChatScope).parentId, 'opaque-parent');
      expect(transport.demand!.maxItems, greaterThan(0));
      expect(transport.demand!.maxBytes, 256 * 1024);
      final controller = tester.widget<Chat>(find.byType(Chat)).chatController;
      expect(controller.messages.map((m) => m.id), ['item']);
      final done = Completer<void>();
      final observed = controller.operationsStream.listen(
        (_) {},
        onDone: done.complete,
      );
      transport.feed.closeGate = Completer<void>();
      transport.feed.reader.closeFailure = StateError(
        'read lease close failed',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(done.isCompleted, isTrue);
      expect(transport.feed.closeStarted.isCompleted, isTrue);
      expect(transport.feed.closeCompleted.isCompleted, isFalse);
      transport.feed.closeGate!.complete();
      final report = await pumpClientFuture(
        tester,
        repository.close(),
        'children native close failure',
      );
      expect(
        report.complete,
        isFalse,
        reason: 'Native failure remains owned, not hidden by widget disposal',
      );
      expect(report.unresolved, isNotEmpty);
      transport.feed.reader.closeFailure = null;
      final recovered = await pumpClientFuture(
        tester,
        repository.retryCleanup(),
        'children original close retry',
      );
      expect(recovered.complete, isTrue);
      await pumpClientFuture(
        tester,
        observed.cancel(),
        'children controller observer cancellation',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final failBeforeReplacement in [false, true]) {
    testWidgets(
      'Children query follows replacement feed and rejects old completions (early failure: $failBeforeReplacement)',
      (tester) async {
        final transport = _Transport();
        final repository = ConversationRepositoryImpl(
          transport: transport,
          directory: ThreadDirectoryStore(),
          budget: ResourceBudget(),
          onRevision: (_, _) {},
        );
        final recorded = _RecordingRepository(repository);
        final oldPage = Completer<ChatBatch>();
        final newPage = Completer<ChatBatch>();
        var oldReads = 0;
        var newReads = 0;
        var newLoads = 0;
        transport.feed.reader.onOlder = (before, demand) {
          expect(before, 'old-before');
          return oldPage.future;
        };
        transport.feed.reader.onContent = (_, range) async {
          oldReads++;
          return _window('old body', range);
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TimelineChildrenConnector(
                repository: recorded,
                threadId: 'thread',
                parentId: 'opaque-parent',
              ),
            ),
          ),
        );
        await tester.pump();
        transport.feed.send(
          ConversationChatEvent(
            batch: chatSet(before: 'old-before', messages: [_deferred()]),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('按需查看原文 · 100000 字节'));
        await pumpClientUntil(
          tester,
          () => oldReads == 1,
          'original child content read',
        );
        await tester.pump();
        expect(find.text('old body'), findsOneWidget);
        final oldOlder = tester
            .widget<ChatAnimatedListReversed>(
              find.byType(ChatAnimatedListReversed),
            )
            .onEndReached!();
        if (failBeforeReplacement) {
          oldPage.completeError(StateError('old page failure'));
          await pumpClientFuture(
            tester,
            oldOlder,
            'old page error before refresh',
          );
          await tester.pump();
          expect(find.textContaining('old page failure'), findsOneWidget);
        }
        recorded.contents.single.refresh();
        await pumpClientUntil(
          tester,
          () => transport.feeds.length == 2,
          'replacement child feed',
        );
        final replacement = transport.feeds.last;
        replacement.reader.onOlder = (before, demand) {
          expect(
            before,
            'new-before',
            reason: 'Never send an old cursor to the new reader',
          );
          newLoads++;
          return newPage.future;
        };
        replacement.reader.onContent = (_, range) async {
          newReads++;
          return _window('new body', range);
        };
        await tester.pump();
        expect(
          find.byType(Chat),
          findsNothing,
          reason: 'Before the replacement Set, old rows/cursors have no new-reader qualification',
        );
        expect(newLoads, 0);
        replacement.send(
          ConversationChatEvent(
            batch: chatSet(before: 'new-before', messages: [_deferred()]),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.byType(Chat),
          findsOneWidget,
          reason: 'A recovered Set clears obsolete errors',
        );
        expect(find.textContaining('old page failure'), findsNothing);
        final loadNew = tester
            .widget<ChatAnimatedListReversed>(
              find.byType(ChatAnimatedListReversed),
            )
            .onEndReached!;
        final newOlder = loadNew();
        expect(newLoads, 1);
        await tester.tap(find.text('按需查看原文 · 100000 字节'));
        await pumpClientUntil(
          tester,
          () => newReads == 1,
          'replacement child content read',
        );
        await tester.pump();
        expect(find.text('new body'), findsOneWidget);
        expect(oldReads, 1);
        if (!failBeforeReplacement) {
          oldPage.completeError(StateError('late old page failure'));
          await pumpClientFuture(
            tester,
            oldOlder,
            'late original page failure',
          );
          await tester.pump();
          expect(find.textContaining('late old page failure'), findsNothing);
          expect(
            identical(loadNew(), newOlder),
            isTrue,
            reason: 'Old finally cannot clear the new single-flight',
          );
          expect(newLoads, 1);
        }
        newPage.complete(
          ChatBatch(
            placement: ChatPlacement.prepend,
            messages: [
              chatMessage(id: 'replacement-older', body: 'older from new feed'),
            ],
          ),
        );
        await pumpClientFuture(tester, newOlder, 'replacement page acceptance');
        await tester.pump();
        expect(
          tester
              .widget<Chat>(find.byType(Chat))
              .chatController
              .messages
              .map((m) => m.id),
          ['replacement-older', 'deferred'],
        );
        await tester.pumpWidget(const SizedBox());
        expect(
          (await pumpClientFuture(
            tester,
            repository.close(),
            'close replacement child',
          )).complete,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

ChatMessage _deferred() => const ChatMessage(
  id: 'deferred',
  payload: DeferredPayload(
    reference: ContentRef(
      databaseId: 'database',
      target: ItemPayloadTarget(itemId: 'deferred'),
    ),
    byteLength: 100000,
  ),
);
ContentWindow _window(String text, ContentRange range) => ContentWindow(
  offset: range.offset,
  bytes: utf8.encode(text),
  generation: 'g',
  availableThrough: 100000,
  sealed: true,
);

final class _RecordingRepository extends Fake
    implements ConversationRepository {
  _RecordingRepository(this.delegate);
  final ConversationRepository delegate;
  final contents = <ConversationContent>[];
  @override
  Future<ConversationContent> openChildren({
    required String threadId,
    required String parentId,
    required ReadDemand demand,
  }) async {
    final content = await delegate.openChildren(
      threadId: threadId,
      parentId: parentId,
      demand: demand,
    );
    contents.add(content);
    return content;
  }
}

final class _Transport implements ConversationTransport {
  final feed = TestConversationFeed();
  final feeds = <TestConversationFeed>[];
  final opened = Completer<void>();
  ChatScope? scope;
  ReadDemand? demand;
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  }) async {
    this.scope = scope;
    this.demand = demand;
    final next = feeds.isEmpty
        ? feed
        : TestConversationFeed(subscriptionId: 'sub:${feeds.length}');
    feeds.add(next);
    if (!opened.isCompleted) opened.complete();
    return next;
  }
}
