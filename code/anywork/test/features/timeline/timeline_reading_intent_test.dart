import 'package:anywork/src/presentation/providers/client_provider.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/presentation/providers/thread_session_store.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';

import '../../client/support/recording_demo_transport.dart';
import '../../client/support/pump_client_future.dart';

/// 阅读意图（UI 像素锚点）与后端窗口焦点（ViewFocus）必须分开：
/// 普通窗口内滚动只改锚点；只有真正的定位意图才允许换后端焦点。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';

  testWidgets('未挂载锚点的逐帧定位在用户拖动时立即中止', (tester) async {
    final now = DateTime.utc(2026);
    final rows = TimelineRowProjector().project([
      for (var index = 0; index < 80; index++)
        ThreadItemView(
          id: 'locate-$index',
          threadId: threadId,
          turnId: 'turn',
          ordinal: index,
          revision: 1,
          createdAt: now,
          updatedAt: now,
          state: ThreadTextItemStateView(
            channel: ThreadTextChannel.finalAnswer,
            text: List.filled(2 + index % 3, '第 $index 条正文').join('\n\n'),
            attachments: const [],
            lifecycle: CompletedThreadContentView(now),
          ),
        ),
    ]);
    final notifications = <Notification>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                height: 320,
                child: NotificationListener<Notification>(
                  onNotification: (event) {
                    notifications.add(event);
                    return false;
                  },
                  child: TimelineView(
                    threadId: threadId,
                    viewId: 'locate-view',
                    rows: rows,
                    body: const ThreadHistoryWindow(),
                    turn: null,
                    anchor: const TimelineAnchor(
                      'locate-70',
                      -10,
                      readingIntent: TimelineReadingIntent.browseHistory,
                    ),
                    onCommand: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final position = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!
        .position;
    final target = find.byKey(StudioDriverKeys.timelineRow('locate-70'));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      if (notifications
              .whereType<ObserverScrollStartNotification>()
              .isNotEmpty &&
          position.pixels > 0 &&
          target.evaluate().isEmpty) {
        break;
      }
    }
    expect(
      notifications.whereType<ObserverScrollStartNotification>(),
      hasLength(1),
    );
    expect(
      notifications.whereType<ObserverScrollDecisionNotification>(),
      isEmpty,
    );
    expect(position.pixels, greaterThan(0));
    expect(
      target,
      findsNothing,
      reason: 'the variable-height index search is still in progress',
    );
    final viewport = tester.getRect(find.byType(CustomScrollView));
    final gesture = await tester.startGesture(
      Offset(viewport.right - 12, viewport.center.dy),
    );
    await gesture.moveBy(const Offset(0, 40));
    expect(
      notifications.whereType<ScrollStartNotification>().any(
        (event) => event.dragDetails != null,
      ),
      isTrue,
    );
    final heldPixels = position.pixels;
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        position.pixels,
        closeTo(heldPixels, .5),
        reason: 'a cancelled index search must not take over the held drag',
      );
      expect(tester.takeException(), isNull);
    }
    expect(
      notifications.whereType<ObserverScrollInterruptionNotification>(),
      hasLength(1),
    );
    expect(
      notifications.whereType<ObserverScrollDecisionNotification>(),
      isEmpty,
    );
    await gesture.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('ViewFocus 去重语义', () {
    late ProviderContainer container;
    late AppGraph graph;
    late ProviderSubscription<Object?> sessionHold;

    setUp(() async {
      graph = AppGraph(
        transport: RecordingDemoTransport(),
        clientId: 'view-focus',
      );
      container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      await graph.client.bootstrap();
      await graph.client.directoryCommands.selectThread(threadId);
      sessionHold = container.listen(
        threadSessionStoreProvider(threadId),
        (_, _) {},
      );
      await graph.client
          .session(threadId)
          .source
          .waitFor((s) => s.hasChatWindow);
    });

    tearDown(() async {
      sessionHold.close();
      container.dispose();
      await graph.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
    });

    test('已经确认的同一目标不再发起 focus', () async {
      final store = graph.client.session(threadId);
      final request = store.requestViewFocus('item-1');
      expect(request, isNotNull);
      store.settleViewFocus(request!, succeeded: true);
      expect(store.confirmedViewFocus, 'item-1');
      expect(store.viewFocusPending, isFalse);

      expect(store.requestViewFocus('item-1'), isNull);
    });

    test('焦点失败后同一目标仍能重试', () async {
      final store = graph.client.session(threadId);
      final request = store.requestViewFocus('item-1');
      expect(request, isNotNull);
      store.settleViewFocus(request!, succeeded: false);
      expect(store.confirmedViewFocus, isNull);

      // 失败不能把本地意图当成已完成：同一目标必须再次成为真实请求。
      expect(
        store.requestViewFocus('item-1'),
        isNotNull,
        reason: '一次 focus 失败被本地锚点永久压住',
      );
    });

    test('在途的同一目标合并为一次请求', () async {
      final store = graph.client.session(threadId);
      expect(store.requestViewFocus('item-1'), isNotNull);
      expect(store.requestViewFocus('item-1'), isNull);
      expect(store.viewFocusPending, isTrue);
    });
  });

  testWidgets('切换会话后，旧会话登记的帧末校正不再作用于新会话', (tester) async {
    final rows = _rows(40);
    final commands = <({String threadId, TimelineCommand command})>[];

    Widget view({required String threadId, required int epoch}) {
      return ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              height: 480,
              child: TimelineView(
                threadId: threadId,
                rows: rows,
                body: const ThreadHistoryWindow(),
                turn: null,
                hasOlder: false,
                hasNewer: false,
                windowEpoch: epoch,
                viewId: '$threadId:$epoch',
                onCommand: (command) =>
                    commands.add((threadId: threadId, command: command)),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(view(threadId: 'thread-a', epoch: 1));
    await tester.pump();
    commands.clear();
    // 同一帧内换会话：旧会话登记的回调必须凭身份被丢弃，不能把新会话滚到旧位置。
    await tester.pumpWidget(view(threadId: 'thread-b', epoch: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      commands.where((event) => event.threadId == 'thread-a'),
      isEmpty,
      reason: '旧会话的帧末校正不能在新会话上执行',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('浏览历史中继续滚动不再按每次滚动重发 native focus', (tester) async {
    final api = RecordingDemoTransport();
    final graph = AppGraph(transport: api, clientId: 'timeline-scroll');
    addTearDown(
      () => pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
        'reading-intent teardown',
      ),
    );
    await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
    await pumpClientFuture(
      tester,
      graph.client.directoryCommands.selectThread(threadId),
      'select Thread',
    );
    await pumpClientFuture(
      tester,
      graph.client.session(threadId).source.waitFor((s) => s.hasChatWindow),
      'first ChatView frame',
    );
    final window = api.windows.single;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(graph)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => SizedBox(
                height: 480,
                child: TimelineView(
                  threadId: threadId,
                  rows: _rows(40),
                  body: const ThreadHistoryWindow(),
                  turn: null,
                  hasOlder: false,
                  hasNewer: false,
                  onCommand: (command) {
                    if (command is TimelineAnchorChanged) {
                      unawaited(
                        ref
                            .read(anyworkClientProvider)
                            .threadCommands
                            .updateTimelineAnchor(threadId, command.anchor),
                      );
                    }
                  },
                  windowEpoch: 1,
                  viewId: graph.client.session(threadId).state.chatViewId,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 第一次拖动是「进入浏览历史」的意图切换：允许换一次后端焦点。
    await tester.drag(
      find.byKey(StudioDriverKeys.timeline),
      const Offset(0, 160),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final afterEnter = window.focusRequests.length;

    // 继续在同一窗口内滚动：顶行会变，但后端焦点不应因此重发。
    for (var step = 0; step < 3; step++) {
      await tester.drag(
        find.byKey(StudioDriverKeys.timeline),
        const Offset(0, 120),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(afterEnter, lessThanOrEqualTo(1), reason: '进入历史阅读最多换一次焦点');
    expect(
      window.focusRequests.length,
      afterEnter,
      reason: '窗口内继续滚动不得按每次换顶行重发 focus',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    final report = await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'reading-intent owner close',
    );
    expect(report.unresolved, isEmpty);
  });
}

List<TimelineRow> _rows(int count) {
  final now = DateTime.utc(2026, 1, 1);
  return [
    for (var index = 0; index < count; index++)
      TimelineTextRow(
        item: ThreadItemView(
          id: 'item-$index',
          threadId: 'thread-main',
          turnId: 'turn-1',
          ordinal: index,
          revision: 1,
          createdAt: now,
          updatedAt: now,
          state: ThreadTextItemStateView(
            channel: ThreadTextChannel.user,
            text: '第 $index 条消息',
            attachments: const [],
            lifecycle: CompletedThreadContentView(now),
          ),
        ),
        part: TimelineEntry(
          id: 'item-$index',
          groupId: 'turn-1',
          type: TimelineEntryType.text,
          text: '第 $index 条消息',
          threadId: 'thread-main',
          turnId: 'turn-1',
          textChannel: TimelineTextChannel.user,
          order: index,
          sequence: index,
          createdAt: now,
          updatedAt: now,
        ),
      ),
  ];
}
