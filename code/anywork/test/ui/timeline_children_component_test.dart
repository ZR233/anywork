import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_children_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_children_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/src/contracts/stamps.dart';
import 'package:anywork_client/src/conversation/data/conversation_repository_impl.dart';
import 'package:anywork_client/src/lifecycle/close_report.dart';
import 'package:anywork_client/src/observation/latest_value.dart';
import 'package:anywork_client/src/studio/stores/thread_directory_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart'
    show InMemoryChatController, Message;
import 'package:flutter_chat_ui/flutter_chat_ui.dart' show Chat;
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart'
    hide chatMessage, chatSet;
import '../../../anywork_client/test/support/timeline_transport.dart'
    as main_fixtures
    show chatMessage;
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';

ThreadDirectoryStore _threadDirectory() =>
    ThreadDirectoryStore(feed: RecordingDemoTransport());

void main() {
  for (final run in [false, true]) {
    testWidgets(
      '${run ? 'Run' : 'Children'} accepts Activity barriers then pages and closes without touching Main',
      (tester) async {
        final transport = _Transport();
        final repository = ConversationRepositoryImpl(
          transport: transport,
          directory: _threadDirectory(),
          onRevision: (_, _) {},
        );
        const reference = CompletionRunRef(
          databaseId: 'database',
          indexVersion: 1,
          startSeq: 1,
        );
        CompletedEntry runEntry(String id, int sequence) => CompletedEntry(
          recordId: id,
          completionSeq: sequence,
          run: CompletionRunPosition(startSeq: 1, ordinal: sequence),
          mainPresentation: MainPresentation.foregroundWork,
          atom: memberMessage(id: id),
        );
        transport.feed.reader.onOlder = (before, _) async {
          expect(before, 'before');
          return ChatBatch(
            placement: ChatPlacement.prepend,
            entries: [
              run
                  ? runEntry('older', 1)
                  : memberEntry(memberMessage(id: 'older')),
            ],
            throughSeq: 100,
          );
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TimelineChildrenConnector(
                repository: run ? null : repository,
                threadId: 'thread',
                parentId: 'parent',
                runReference: run ? reference : null,
                openRun: run
                    ? (reference, demand) => repository.openRun(
                        threadId: 'thread',
                        reference: reference,
                        demand: demand,
                      )
                    : null,
              ),
            ),
          ),
        );
        await tester.pump();
        transport.feed.send(
          ConversationChatEvent(
            batch: run
                ? ChatBatch(
                    placement: ChatPlacement.set,
                    entries: [runEntry('item', 100)],
                    before: 'before',
                    throughSeq: 100,
                  )
                : memberSet(before: 'before'),
          ),
        );
        await pumpClientUntil(
          tester,
          () => transport.feed.acknowledgements.contains(1),
          'initial completed Set ACK',
        );
        final controller = tester
            .widget<Chat>(find.byType(Chat))
            .chatController;
        final original = controller.messages.single;
        transport.feed.send(
          ConversationActivityEvent(
            snapshot: ActivitySnapshot(
              revision: 1,
              completedThrough: 100,
              executionPresent: false,
              entries: const [],
            ),
          ),
        );
        await pumpClientUntil(
          tester,
          () => transport.feed.acknowledgements.contains(2),
          'independent Activity ACK',
        );
        expect(controller.messages.single, same(original));
        expect(repository.session('thread').activity.value, isNull);
        await tester.tap(
          find.byKey(const ValueKey('timeline-children-load-older')),
        );
        await pumpClientUntil(
          tester,
          () => controller.messages.length == 2,
          'page after Activity',
        );
        expect(controller.messages.map((message) => message.id), [
          'older',
          'item',
        ]);
        await tester.pumpWidget(const SizedBox());
        await pumpClientUntil(
          tester,
          () => transport.feed.closeStarted.isCompleted,
          'scope close',
        );
        final report = await pumpClientFuture(
          tester,
          repository.close(),
          'independent scope and repository joined',
        );
        expect(report.complete, isTrue);
        expect(transport.feed.acknowledgements, [1, 2]);
      },
    );
  }
  for (final lateFailure in [false, true]) {
    testWidgets(
      'genuine business parent rejects retired open ${lateFailure ? 'failure' : 'success'} without rebinding into B',
      (tester) async {
        final repository = _PendingRepository();
        final a = ValueNotifier(false);
        final b = ValueNotifier(false);
        addTearDown(a.dispose);
        addTearDown(b.dispose);
        final displays = <TimelineChildrenDisplay>{};
        Widget host(String parent, ValueNotifier<bool> retirement) =>
            MaterialApp(
              theme: pureStudioTheme(),
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: TimelineChildrenConnector(
                  key: ValueKey(parent),
                  repository: repository,
                  threadId: 'thread',
                  parentId: parent,
                  parentRetirement: retirement,
                  isParentActive: () => !retirement.value,
                  registerDisplay: (display) {
                    displays.add(display);
                    return () => displays.remove(display);
                  },
                ),
              ),
            );
        await tester.pumpWidget(host('business-parent:α/17', a));
        expect(repository.requests.single.$1, 'business-parent:α/17');
        final originalState = tester.state(
          find.byType(TimelineChildrenConnector),
        );
        final originalDisplay = originalState as TimelineChildrenDisplay;
        a.value = true;
        expect(originalState.mounted, isTrue);
        expect(originalDisplay.isCurrent, isFalse);
        await tester.pumpWidget(host('business-parent:β/91', b));
        final current = _LateContent();
        repository.requests.last.$2.complete(current);
        await tester.pump();
        await current.consumer!.applyBatch(
          memberSet(messages: [memberMessage(id: 'B')]),
        );
        await tester.pump();
        final displayB = displays.single;
        final messageB = displayB.messages.single;
        final late = _LateContent();
        if (lateFailure) {
          repository.requests.first.$2.completeError(
            StateError('retired open failed'),
          );
        } else {
          repository.requests.first.$2.complete(late);
        }
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(displayB.parentId, 'business-parent:β/91');
        expect(displayB.messages.single, same(messageB));
        expect(displayB.error, isNull);
        expect(find.textContaining('retired open failed'), findsNothing);
        if (!lateFailure) {
          expect(late.closeCalls, 1);
          expect(late.consumer, isNull);
        }
        a.value = false; // A's old notifier cannot requalify the B display.
        expect(displayB.isCurrent, isTrue);
        expect(repository.requests.length, 2);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(displays, isEmpty);
        expect(current.attachment!.isCancelled, isTrue);
        expect(current.closeCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Children use one controller, grow naturally and delegate scrolling to the reading viewport',
    (tester) async {
      final controller = InMemoryChatController(
        messages: [
          _controllerMessage(memberMessage(id: 'short', body: '短的真实子内容')),
        ],
      );
      var pages = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 360,
                  child: TimelineChildrenView(
                    controller: controller,
                    generation: 1,
                    isDisplayActive: () => true,
                    onLoadOlder: () async {
                      pages++;
                    },
                    contentRangeBuilder: (_, _, label, _, _) => Text(label),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final children = find.byType(TimelineChildrenView);
      final chat = tester.widget<Chat>(find.byType(Chat));
      expect(chat.chatController, same(controller));
      expect(chat.backgroundColor, Colors.transparent);
      expect(tester.getSize(children).height, lessThan(100));
      final scroll = find.descendant(
        of: children,
        matching: find.byType(Scrollable),
      );
      expect(tester.state<ScrollableState>(scroll).position.maxScrollExtent, 0);

      await controller.setMessages([
        for (var i = 0; i < 40; i++)
          _controllerMessage(memberMessage(id: 'long-$i', body: '消息 $i 的真实正文')),
      ], animated: false);
      await tester.pumpAndSettle();
      expect(tester.getSize(children).height, greaterThan(320));
      expect(tester.state<ScrollableState>(scroll).position.maxScrollExtent, 0);
      final outer = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(outer.position.maxScrollExtent, greaterThan(0));
      expect(
        tester.widget<Chat>(find.byType(Chat)).chatController,
        same(controller),
      );
      await tester.tap(
        find.byKey(const ValueKey('timeline-children-load-older')),
      );
      await tester.pumpAndSettle();
      expect(pages, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'Children display diagnostics borrow the real controller and actual admitted operations without IO',
    (tester) async {
      final transport = _Transport();
      final repository = ConversationRepositoryImpl(
        transport: transport,
        directory: _threadDirectory(),
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
        ConversationChatEvent(batch: memberSet(before: 'before')),
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
      await tester.tap(
        find.byKey(const ValueKey('timeline-children-load-older')),
      );
      await tester.pump();
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
            fromSeq: 100,
            throughSeq: 101,
            entries: [memberEntry(memberMessage(id: 'append'), sequence: 101)],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(display.appliedAppends, 1);
      page.complete(
        ChatBatch(
          placement: ChatPlacement.prepend,
          throughSeq: 100,
          entries: [memberEntry(memberMessage(id: 'older'))],
        ),
      );
      await pumpClientUntil(
        tester,
        () => !display.loadingOlder,
        'diagnostic page applied',
      );
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
          batch: memberSet(messages: [memberMessage(id: 'retired-during-Set')]),
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
          batch: memberSet(
            messages: [memberMessage(id: 'replacement', body: '旧 Children 正文')],
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
      recorded.contents.single.refresh();
      await pumpClientUntil(
        tester,
        () => transport.feeds.length == 4,
        'fresh immutable Children attempt',
      );
      transport.feeds.last.send(
        ConversationChatEvent(
          batch: memberSet(
            messages: [memberMessage(id: 'replacement', body: '新 Children 正文')],
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
      final originalFeed = transport.feeds.last;
      final acknowledgedBeforeRetirement = List.of(
        originalFeed.acknowledgements,
      );
      parentActive = false;
      expect(displays.where((display) => display.isCurrent), isEmpty);
      expect(display.messages, isEmpty);
      originalFeed.send(
        ConversationChatEvent(
          batch: ChatBatch(
            placement: ChatPlacement.append,
            fromSeq: 100,
            throughSeq: 101,
            entries: [
              memberEntry(memberMessage(id: 'unaccepted'), sequence: 101),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        originalFeed.acknowledgements,
        acknowledgedBeforeRetirement,
        reason: 'An inactive parent must revoke its SDK consumer before ACK',
      );
      expect(originalFeed.closeStarted.isCompleted, isTrue);
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
        directory: _threadDirectory(),
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
      transport.feed.send(ConversationChatEvent(batch: memberSet()));
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

  testWidgets(
    'parent qualification loss rejects an active SDK lease without ACK and new owner gets a clean lease',
    (tester) async {
      final transport = _Transport();
      final repository = ConversationRepositoryImpl(
        transport: transport,
        directory: _threadDirectory(),
        onRevision: (_, _) {},
      );
      var parentActive = true;
      Widget host(String parentId) => MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TimelineChildrenConnector(
            key: ValueKey(parentId),
            repository: repository,
            threadId: 'thread',
            parentId: parentId,
            isParentActive: () => parentActive,
          ),
        ),
      );
      await tester.pumpWidget(host('owner-A'));
      await tester.pump();
      final oldFeed = transport.feeds.single;
      oldFeed.send(ConversationChatEvent(batch: memberSet()));
      await pumpClientUntil(
        tester,
        () => oldFeed.acknowledgements.contains(1),
        'initial Children Set ACK',
      );
      expect(
        tester
            .widget<Chat>(find.byType(Chat))
            .chatController
            .messages
            .map((message) => message.id),
        ['item'],
      );

      // This changes only the original parent qualification callback result:
      // neither the widget nor the retirement notifier is rebuilt/signalled.
      parentActive = false;
      oldFeed.send(
        ConversationChatEvent(
          batch: ChatBatch(
            placement: ChatPlacement.append,
            fromSeq: 100,
            throughSeq: 101,
            entries: [
              memberEntry(memberMessage(id: 'must-not-apply'), sequence: 101),
            ],
          ),
        ),
      );
      await tester.pump();
      await pumpClientUntil(
        tester,
        () => oldFeed.closeStarted.isCompleted,
        'retired original Children lease close',
      );
      expect(oldFeed.acknowledgements, [1]);
      expect(oldFeed.closeCalls, greaterThan(0));

      parentActive = true;
      await tester.pumpWidget(host('owner-B'));
      await pumpClientUntil(
        tester,
        () => transport.feeds.length == 2,
        'new Children owner lease',
      );
      final newFeed = transport.feeds.last;
      newFeed.send(
        ConversationChatEvent(
          batch: memberSet(messages: [memberMessage(id: 'new-owner')]),
        ),
      );
      await pumpClientUntil(
        tester,
        () => newFeed.acknowledgements.contains(1),
        'new Children owner Set ACK',
      );
      expect(
        tester
            .widget<Chat>(find.byType(Chat))
            .chatController
            .messages
            .map((message) => message.id),
        ['new-owner'],
      );
      expect(oldFeed.acknowledgements, [1]);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await pumpClientFuture(
        tester,
        repository.close(),
        'close Children repository',
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
          directory: _threadDirectory(),
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
            batch: memberSet(before: 'old-before', messages: [_deferred()]),
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
        await tester.tap(
          find.byKey(const ValueKey('timeline-children-load-older')),
        );
        await tester.pump();
        if (failBeforeReplacement) {
          oldPage.completeError(StateError('old page failure'));
          await pumpClientUntil(
            tester,
            () => find.textContaining('old page failure').evaluate().isNotEmpty,
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
            batch: memberSet(before: 'new-before', messages: [_deferred()]),
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
        final newLoad = find.byKey(
          const ValueKey('timeline-children-load-older'),
        );
        await tester.tap(newLoad);
        await tester.pump();
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
          var oldSettled = false;
          unawaited(
            oldPage.future.then<void>(
              (_) => oldSettled = true,
              onError: (Object _) => oldSettled = true,
            ),
          );
          oldPage.completeError(StateError('late old page failure'));
          await pumpClientUntil(
            tester,
            () => oldSettled,
            'late original page failure',
          );
          await tester.pump();
          expect(find.textContaining('late old page failure'), findsNothing);
          expect(
            tester.widget<TextButton>(newLoad).onPressed,
            isNull,
            reason: 'Old finally cannot clear the new single-flight',
          );
          expect(newLoads, 1);
        }
        newPage.complete(
          ChatBatch(
            placement: ChatPlacement.prepend,
            throughSeq: 100,
            entries: [
              memberEntry(
                memberMessage(
                  id: 'replacement-older',
                  body: 'older from new feed',
                ),
              ),
            ],
          ),
        );
        await pumpClientUntil(
          tester,
          () => tester
              .widget<Chat>(find.byType(Chat))
              .chatController
              .messages
              .any((message) => message.id == 'replacement-older'),
          'replacement page acceptance',
        );
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

Message _controllerMessage(ChatAtom item) {
  final value = ChatItemPresentation.decode(item);
  return Message.custom(
    id: item.id,
    authorId: value.authorId,
    createdAt: value.createdAt,
    metadata: {chatItemPresentationKey: value},
  );
}

ChatAtom _deferred() => ChatAtom(
  id: 'deferred',
  source: const ReceiptChatSource(receiptId: 'deferred'),
  sourceOrder: null,
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.independent,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contents: const [],
  payload: const DeferredPayload(
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

final class _PendingRepository extends Fake implements ConversationRepository {
  final requests = <(String, Completer<ConversationContent>)>[];
  @override
  Future<ConversationContent> openChildren({
    required String threadId,
    required String parentId,
    required ReadDemand demand,
  }) {
    final completion = Completer<ConversationContent>();
    requests.add((parentId, completion));
    return completion.future;
  }
}

final class _LateContent extends Fake implements ConversationContent {
  final source = LatestValue<ChatUiState<bool>>(
    const ChatReady('thread', true),
  );
  final attachments = LatestValue(false);
  ConversationBatchConsumer? consumer;
  Observation? attachment;
  int closeCalls = 0;
  @override
  ValueObservation<ChatUiState<bool>> get state => source;
  @override
  AttemptId get currentAttemptId => const AttemptId(1);
  @override
  bool get isClosed => closeCalls != 0;
  @override
  Observation attachConsumer(
    ConversationBatchConsumer consumer, {
    required ReadDemand demand,
  }) {
    this.consumer = consumer;
    return attachment = attachments.watch((_) {});
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    closeCalls++;
    return CloseReport();
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

// Children use immutable completed records, independently from Main display cards.
CompletedEntry memberEntry(ChatAtom atom, {int sequence = 1}) => CompletedEntry(
  recordId: atom.completionItemId ?? atom.id,
  completionSeq: sequence,
  run: CompletionRunPosition(startSeq: sequence, ordinal: 1),
  mainPresentation: MainPresentation.single,
  atom: atom,
);
ChatAtom memberMessage({String id = 'item', String body = 'body'}) => ChatAtom(
  id: id,
  completionItemId: id,
  source: ReceiptChatSource(receiptId: id),
  sourceOrder: null,
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.independent,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contents: const [],
  payload: main_fixtures.chatMessage(id: id, body: body).atom.payload,
);
ChatBatch memberSet({List<ChatAtom>? messages, String? before}) => ChatBatch(
  placement: ChatPlacement.set,
  entries: (messages ?? [memberMessage()]).indexed
      .map((pair) => memberEntry(pair.$2, sequence: 100 + pair.$1))
      .toList(),
  before: before,
  throughSeq: 100 + (messages?.length ?? 1) - 1,
);
