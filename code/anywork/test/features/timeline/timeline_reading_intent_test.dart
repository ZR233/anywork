import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/bridge/studio_bridge.dart';
import 'package:anywork/src/data/commands/thread_commands.dart';
import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/data/repositories/studio_api_provider.dart';
import 'package:anywork/src/data/stores/chat_view_events.dart';
import 'package:anywork/src/data/stores/chat_view_metrics.dart';
import 'package:anywork/src/data/stores/thread_directory_store.dart';
import 'package:anywork/src/data/stores/thread_session_store.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';

/// 阅读意图（UI 像素锚点）与后端窗口焦点（ViewFocus）必须分开：
/// 普通窗口内滚动只改锚点；只有真正的定位意图才允许换后端焦点。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';

  group('ViewFocus 去重语义', () {
    late ProviderContainer container;
    late BridgeTopicLeaseBundle shell;
    late ProviderSubscription<Object?> sessionHold;

    setUp(() async {
      ChatViewMetrics.reset();
      final api = DemoStudioBridgeDataSource(lspActivityLoop: false);
      container = ProviderContainer(
        overrides: [studioBridgeDataSourceProvider.overrideWithValue(api)],
      );
      shell = container.read(studioBridgeProvider).acquireShellBundle();
      await _until(
        () => container.read(threadDirectoryStoreProvider).loaded,
        '目录基线',
      );
      sessionHold = container.listen(
        threadSessionStoreProvider(threadId),
        (_, _) {},
      );
      await _until(
        () => container.read(threadSessionStoreProvider(threadId)).hasSnapshot,
        'Thread 快照',
      );
    });

    tearDown(() async {
      sessionHold.close();
      await shell.release();
      container.dispose();
    });

    test('已经确认的同一目标不再发起 focus', () async {
      final store = container.read(
        threadSessionStoreProvider(threadId).notifier,
      );
      expect(store.requestViewFocus('item-1'), isTrue);
      store.settleViewFocus('item-1', succeeded: true);
      expect(store.confirmedViewFocus, 'item-1');
      expect(store.viewFocusPending, isFalse);

      expect(store.requestViewFocus('item-1'), isFalse);
      expect(ChatViewMetrics.focusCalls, 0);
    });

    test('焦点失败后同一目标仍能重试', () async {
      final store = container.read(
        threadSessionStoreProvider(threadId).notifier,
      );
      expect(store.requestViewFocus('item-1'), isTrue);
      store.settleViewFocus('item-1', succeeded: false);
      expect(store.confirmedViewFocus, isNull);

      // 失败不能把本地意图当成已完成：同一目标必须再次成为真实请求。
      expect(
        store.requestViewFocus('item-1'),
        isTrue,
        reason: '一次 focus 失败被本地锚点永久压住',
      );
    });

    test('在途的同一目标合并为一次请求', () async {
      final store = container.read(
        threadSessionStoreProvider(threadId).notifier,
      );
      expect(store.requestViewFocus('item-1'), isTrue);
      expect(store.requestViewFocus('item-1'), isFalse);
      expect(store.viewFocusPending, isTrue);
    });
  });

  testWidgets('切换会话后，旧会话登记的帧末校正不再作用于新会话', (tester) async {
    ChatViewEvents.reset();
    final rows = _rows(40);

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
                turn: null,
                hasOlder: false,
                hasNewer: false,
                canExtendLatest: false,
                windowEpoch: epoch,
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(view(threadId: 'thread-a', epoch: 1));
    await tester.pump();
    // 同一帧内换会话：旧会话登记的回调必须凭身份被丢弃，不能把新会话滚到旧位置。
    await tester.pumpWidget(view(threadId: 'thread-b', epoch: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final corrections = ChatViewEvents.ofKind(
      ChatViewEventKind.scrollCorrection,
    );
    expect(
      corrections.where((event) => event.identity['thread'] == 'thread-a'),
      isEmpty,
      reason: '旧会话的帧末校正不能在新会话上执行',
    );
  });

  testWidgets('浏览历史中继续滚动不再按每次滚动重发 native focus', (tester) async {
    ChatViewMetrics.reset();
    final api = DemoStudioBridgeDataSource(lspActivityLoop: false);
    var windowEpoch = 1;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [studioBridgeDataSourceProvider.overrideWithValue(api)],
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
                  turn: null,
                  hasOlder: false,
                  hasNewer: false,
                  canExtendLatest: false,
                  onCommand: (command) {
                    if (command is TimelineAnchorChanged) {
                      unawaited(
                        ref
                            .read(threadCommandsProvider.notifier)
                            .updateTimelineAnchor(threadId, command.anchor),
                      );
                    }
                  },
                  windowEpoch: windowEpoch++,
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
    final afterEnter = ChatViewMetrics.focusCalls;

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
      ChatViewMetrics.focusCalls,
      afterEnter,
      reason: '窗口内继续滚动不得按每次换顶行重发 focus',
    );
  });
}

List<TimelineRow> _rows(int count) {
  final now = DateTime.utc(2026, 1, 1);
  return [
    for (var index = 0; index < count; index++)
      TimelineRow.item(
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
        type: TimelineRowType.userMessage,
      ),
  ];
}

Future<void> _until(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$what 未在 10 秒内收敛');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
