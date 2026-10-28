// Opt-in 组件行为证明（默认门禁不运行）。
//
// 唯一列表路线是公开 `Chat` + 原生 `ChatAnimatedListReversed` + stock
// `InMemoryChatController`；这里证明生产 `TimelineView` 的真实绑定、真实用户意图才进入
// History、视口自动补齐/重试、以及全文查看器只读当前 lease 的详情引用。
// 算法层覆盖由 test/client/timeline_display_lease_test.dart 与
// timeline_session_owner_test.dart 承担，不在这里重复。
import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_detail_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_entry.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_view_model.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_entry_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_key_values.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyer_chat_image_message/flyer_chat_image_message.dart';

import '../../client/support/conversation_fixtures.dart';
import '../../client/support/mapped_conversation_feed.dart';
import '../../client/support/pump_client_future.dart';
import '../../client/support/unused_account_ports.dart';
import 'support/timeline_component_fixtures.dart';

void main() {
  ConversationItem textItem(
    String id, {
    required int ordinal,
    String body = '正文',
    bool terminal = true,
    int? totalBytes,
  }) => componentText(
    id,
    ordinal: ordinal,
    body: body,
    terminal: terminal,
    totalBytes: totalBytes,
  );

  ConversationItem toolItem(
    String id, {
    int ordinal = 1,
    String name = 'exec_command',
    required String arguments,
  }) => componentTool(id, ordinal: ordinal, name: name, arguments: arguments);

  ConversationItem imageToolItem(
    String id, {
    required int ordinal,
    String attachmentId = 'att-shared',
    String name = 'view_image',
    String result = 'ok',
    int revision = 1,
    int? totalResultBytes,
  }) => componentTool(
    id,
    ordinal: ordinal,
    name: name,
    arguments: '{"path":"/workspace/images/shot.png"}',
    result: result,
    revision: revision,
    totalResultBytes: totalResultBytes,
    attachments: [
      ThreadAttachmentView(
        id: attachmentId,
        modality: AttachmentModalityView.image,
        mediaType: 'image/png',
        byteSize: _onePixelPng.length,
        filename: 'shot.png',
        width: 1,
        height: 1,
      ),
    ],
  );

  TimelineDisplayLease leaseFor(
    WidgetTester tester, {
    required List<ConversationItem> items,
    String? before,
    bool hasOlder = false,
  }) {
    // Pure-list cases borrow real SDK content without declaring feed demand.
    final content = conversationContentFixture(tester: tester);
    final lease = TimelineDisplayLease(
      threadId: 'thread',
      generation: 1,
      content: content,
    );
    lease.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'test',
        version: 0,
        items: items,
        before: before,
        hasOlder: hasOlder,
      ),
    );
    addTearDown(() async {
      await _unmountTimeline(tester);
      await pumpClientFuture(
        tester,
        lease.retire(),
        'pure-list lease teardown',
      );
      expect(lease.isReleased, isTrue);
    });
    return lease;
  }

  TimelineSessionViewState viewState({
    TimelineDisplayMode mode = TimelineDisplayMode.live,
    bool hasOlder = false,
    bool isLoadingOlder = false,
    Object? olderError,
    bool hasNewOutput = false,
    bool isPreparingLive = false,
    TimelineConnectionPhase connection = TimelineConnectionPhase.ready,
    Object? connectionError,
  }) => TimelineSessionViewState(
    threadId: 'thread',
    generation: 1,
    mode: mode,
    connection: connection,
    connectionError: connectionError,
    olderCursor: hasOlder ? 'cursor' : null,
    hasOlder: hasOlder,
    isLoadingOlder: isLoadingOlder,
    olderError: olderError,
    hasNewOutput: hasNewOutput,
    isPreparingLive: isPreparingLive,
  );

  /// 需要真实 Client 的用例（附件字节等）在这里注入 override。
  Widget host(
    Widget child, {
    Size size = const Size(900, 700),
    AnyworkClient? client,
    TimelineSessionOwner? owner,
  }) => MediaQuery(
    data: MediaQueryData(size: size),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: ProviderScope(
        overrides: [
          if (client != null) anyworkClientProvider.overrideWithValue(client),
          if (owner != null)
            timelineSessionOwnerProvider.overrideWithValue(owner),
        ],
        child: MaterialApp(
          theme: pureStudioTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SizedBox.expand(child: child)),
        ),
      ),
    ),
  );

  testWidgets('生产 Timeline 使用公开 Chat + ChatAnimatedListReversed 并真实绑卸载', (
    tester,
  ) async {
    final lease = leaseFor(tester, items: [textItem('item-a', ordinal: 1)]);
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Chat), findsOneWidget);
    expect(find.byType(ChatAnimatedListReversed), findsOneWidget);
    expect(lease.controller.messages.single, isA<TextMessage>());
    expect(
      timelineEntryOf(lease.controller.messages.single),
      same(lease.presentationFor('item-a')),
    );
    expect(find.byKey(StudioDriverKeys.timelineRow('item-a')), findsOneWidget);
    expect(lease.isMounted, isTrue);

    // 真实子树卸载后 lease 才能释放 controller。
    await tester.pumpWidget(host(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(lease.isMounted, isFalse);
    await pumpClientFuture(
      tester,
      lease.retire(),
      'unmounted Chat lease release',
    );
    expect(lease.isReleased, isTrue);

    // 已释放的代次明确拒绝再次挂载，而不是把已销毁 controller 交给子树。
    expect(lease.bind, throwsStateError);
  });

  testWidgets('只有真实用户滚动离开底端才进入 History，改窗不误判', (tester) async {
    final items = [
      for (var index = 0; index < 40; index++)
        textItem('item-$index', ordinal: index, body: '第 $index 段正文' * 4),
    ];
    final lease = leaseFor(
      tester,
      items: items,
      before: 'cursor',
      hasOlder: true,
    );
    var enteredHistory = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () => enteredHistory += 1,
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 改窗只有布局修正，没有读者意图。
    await tester.binding.setSurfaceSize(const Size(700, 600));
    await tester.pumpAndSettle();
    expect(enteredHistory, 0, reason: 'resize 不是阅读意图');
    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpAndSettle();

    // 真实拖动离开 offset 0。
    await tester.drag(
      find.byType(ChatAnimatedListReversed),
      const Offset(0, 240),
    );
    await tester.pumpAndSettle();
    expect(enteredHistory, greaterThan(0));
    expect(lease.mode, TimelineDisplayMode.live, reason: '意图由 owner 改变模式');
  });

  testWidgets('短内容自动加载更早，失败保留内容并可重试', (tester) async {
    final lease = leaseFor(tester, items: [textItem('only', ordinal: 1)]);
    var loads = 0;
    var retries = 0;
    final page = Completer<void>();
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true),
          lease: lease,
          onLoadOlder: () async {
            loads += 1;
            await page.future;
          },
          onRetryOlder: () async {
            retries += 1;
          },
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.byKey(StudioDriverKeys.timelineRow('only')), findsOneWidget);

    // 分页失败：内容仍在，入口变成可重试。
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true, olderError: StateError('boom')),
          lease: lease,
          onLoadOlder: () async {
            loads += 1;
          },
          onRetryOlder: () async {
            retries += 1;
          },
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    page.complete();
    await tester.pumpAndSettle();
    expect(loads, 1, reason: '失败不能由布局或重建自动重试');
    expect(find.byKey(StudioDriverKeys.timelineRow('only')), findsOneWidget);
    await tester.tap(find.byKey(StudioDriverKeys.timelineRetryOlder));
    await tester.pumpAndSettle();
    expect(retries, 1);
  });

  testWidgets('空基线后首条消息通过原生列表立即显示', (tester) async {
    final lease = leaseFor(tester, items: []);
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    lease.applyPatch(
      ConversationPatch(
        subscriptionId: 'test',
        from: 0,
        to: 1,
        changes: [ConversationAdd(textItem('first-live', ordinal: 1))],
        priority: ConversationPriority.immediate,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(StudioDriverKeys.timelineRow('first-live')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('短内容在途分页结束后，同游标 ready 重建可重新受理', (tester) async {
    final lease = leaseFor(
      tester,
      items: [textItem('only', ordinal: 1)],
      before: 'cursor',
      hasOlder: true,
    );
    var loads = 0;
    final firstPage = Completer<void>();
    Future<void> render(TimelineSessionViewState view) async {
      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: view,
            lease: lease,
            onLoadOlder: () async {
              loads++;
              if (loads == 1) await firstPage.future;
            },
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pump();
    }

    final ready = viewState(mode: TimelineDisplayMode.history, hasOlder: true);
    await render(ready);
    await tester.pumpAndSettle();
    expect(loads, 1);
    // This View-only gate ends normally. Rebuilding ready must re-admit its
    // viewport demand; real SDK scope cancellation is covered below.
    firstPage.complete();
    await tester.pump();
    await render(ready.copyWith());
    await tester.pumpAndSettle();
    expect(loads, 2, reason: '在途结束后 ready 重建应重新受理同一页的视口需求');
  });

  testWidgets('窗口扩大后按实际视口补页，resize 不改变阅读模式', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lease = leaseFor(
      tester,
      items: [for (var i = 0; i < 12; i++) textItem('row-$i', ordinal: i)],
      before: 'cursor',
      hasOlder: true,
    );
    var loads = 0;
    var histories = 0;
    final page = Completer<void>();
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true),
          lease: lease,
          onLoadOlder: () async {
            loads++;
            await page.future;
          },
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {
            histories++;
          },
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(lease.scrollController.position.maxScrollExtent, greaterThan(0));
    expect(loads, 0);
    await tester.binding.setSurfaceSize(const Size(900, 2600));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(histories, 0);
    expect(lease.scrollController.position.pixels, closeTo(0, 0.5));
    await tester.binding.setSurfaceSize(const Size(900, 2500));
    await tester.pumpAndSettle();
    expect(loads, 1, reason: '反复几何通知共享同一个在途需求');
    await tester.pumpWidget(host(const SizedBox.shrink()));
    page.complete();
    await tester.pump();
  });

  testWidgets('分页只补充折叠组而高度不变时继续检查推进后的游标', (tester) async {
    final lease = leaseFor(
      tester,
      items: [toolItem('new-tool', ordinal: 100, arguments: '{}')],
      before: 'cursor',
      hasOlder: true,
    );
    var view = viewState(hasOlder: true);
    var loads = 0;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, update) => componentTimeline(
            threadId: 'thread',
            view: view,
            lease: lease,
            onLoadOlder: () async {
              loads++;
              final page = loads == 1
                  ? ConversationPage(
                      items: [
                        toolItem('older-tool', ordinal: 99, arguments: '{}'),
                      ],
                      before: 'next',
                      hasOlder: true,
                    )
                  : ConversationPage(
                      items: [
                        textItem('old-text', ordinal: 98, body: '历史正文\n' * 120),
                      ],
                      before: null,
                      hasOlder: false,
                    );
              lease.prependOlder(page);
              update(
                () => view = view.copyWith(
                  olderCursor: page.before,
                  hasOlder: page.hasOlder,
                ),
              );
            },
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(view.hasOlder, isFalse);
    expect(lease.loadedCount, 3);
    expect(lease.scrollController.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('History 显示回到实时入口，并在准备期禁用重复触发', (tester) async {
    final lease = leaseFor(tester, items: [textItem('only', ordinal: 1)]);
    var returns = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(
            mode: TimelineDisplayMode.history,
            hasNewOutput: true,
          ),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {
            returns += 1;
          },
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('有新输出'), findsOneWidget);
    await tester.tap(find.byKey(StudioDriverKeys.timelineReturnLive));
    await tester.pumpAndSettle();
    expect(returns, 1);

    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(
            mode: TimelineDisplayMode.history,
            isPreparingLive: true,
          ),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {
            returns += 1;
          },
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    // 准备期的进度指示是持续动画：只推进帧，不等静止。
    await tester.pump();
    await tester.tap(find.byKey(StudioDriverKeys.timelineReturnLive));
    await tester.pump();
    expect(returns, 1, reason: '准备期间的新代次请求不重复触发');
  });

  testWidgets('详情查看器按字段打开、可关闭，且不改动历史行预览', (tester) async {
    final lease = leaseFor(
      tester,
      items: [textItem('big', ordinal: 1, body: '预览正文', totalBytes: 126)],
    );
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final open = find.byKey(StudioDriverKeys.timelineDetailOpen('big', 'text'));
    expect(open, findsOneWidget);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsOneWidget);
    // 没有活动查询 scope：查看器显示可重试错误，而不是伪造全文。
    expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsOneWidget);
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
    expect(find.byKey(StudioDriverKeys.timelineRow('big')), findsOneWidget);
  });

  // ---- B1 键盘 / 滚动条轨道：真实阅读意图 --------------------------------------

  List<ConversationItem> longHistory({int count = 120}) => [
    for (var index = 0; index < count; index++)
      textItem('item-$index', ordinal: index, body: '第 $index 段正文' * 4),
  ];

  testWidgets('键盘 PageUp 是真实阅读意图，改窗与流式增长不是', (tester) async {
    final history = longHistory();
    history[history.length - 1] = componentText(
      'item-119',
      ordinal: 119,
      body: '第 119 段正文' * 4,
      terminal: false,
    );
    final lease = leaseFor(
      tester,
      items: history,
      before: 'cursor',
      hasOlder: true,
    );
    var enteredHistory = 0;
    var olderLoads = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true),
          lease: lease,
          onLoadOlder: () async {
            olderLoads++;
          },
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () => enteredHistory += 1,
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 改窗只有布局修正：不是阅读意图。
    await tester.binding.setSurfaceSize(const Size(720, 620));
    await tester.pumpAndSettle();
    expect(enteredHistory, 0, reason: 'resize 不是阅读意图');
    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpAndSettle();
    expect(enteredHistory, 0);

    expect(lease.controller.messages.last, isA<TextStreamMessage>());
    expect(
      lease.applyPatch(
        ConversationPatch(
          subscriptionId: 'test',
          from: 0,
          to: 1,
          priority: ConversationPriority.immediate,
          changes: [
            ConversationAdd(
              componentText(
                'item-119',
                ordinal: 119,
                revision: 2,
                terminal: false,
                body: '${'第 119 段正文' * 4}\n流式新增第一行\n第二行',
              ),
            ),
          ],
        ),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(enteredHistory, 0, reason: '真实流式高度增长不是阅读意图');

    // 键盘：先让焦点落在正文（真实用户路径：点选正文后再翻页），再按 PageUp。
    // 鼠标点选正文：官方 SelectionArea 在鼠标按下时请求焦点，读历史用键盘时焦点在它上面。
    await tester.tap(
      find.byKey(StudioDriverKeys.timelineRow('item-119')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(
      enteredHistory,
      greaterThan(0),
      reason: 'PageUp 走 ScrollAction，必须登记为真实用户意图',
    );
    final afterPageUp = lease.scrollController.position.pixels;
    expect(afterPageUp, greaterThan(0.5));

    // PageDown 同属 ScrollIntent：不能被吞掉，必须由 Flutter 原生动作滚回（反向列表
    // offset 0 即底端，所以 PageDown 的方向是回到 0，而不是离开底端进 History）。
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(
      lease.scrollController.position.pixels,
      lessThan(afterPageUp),
      reason: 'PageDown 必须真实滚动（未被 app 吞掉或改倍率）',
    );
    final position = lease.scrollController.position;
    for (
      var page = 0;
      page < 32 && position.extentAfter > position.viewportDimension * 1.8;
      page++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
    }
    expect(position.extentAfter, greaterThan(position.viewportDimension));
    expect(
      position.extentAfter,
      lessThanOrEqualTo(position.viewportDimension * 1.8),
    );
    final beforeThreshold = olderLoads;
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    // Observe the real multi-frame ScrollAction animation, not just its last frame.
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(position.extentAfter, lessThan(position.viewportDimension));
    expect(
      olderLoads,
      greaterThan(beforeThreshold),
      reason: '同一次键盘滚动动画跨入一屏范围就预取，无需再按一次',
    );
  });

  testWidgets('滚动条轨道点击分页进入 History', (tester) async {
    final lease = leaseFor(
      tester,
      items: longHistory(),
      before: 'cursor',
      hasOlder: true,
    );
    var enteredHistory = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(hasOlder: true),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () => enteredHistory += 1,
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(StudioDriverKeys.timeline));
    // 原生悬停唤回淡出的滚动条，再点击轨道（顶端不在底部 thumb 内）。
    final trackPoint = Offset(rect.right - 2, rect.top + 12);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(trackPoint));
    await tester.pumpAndSettle();
    await tester.tapAt(trackPoint, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(enteredHistory, greaterThan(0), reason: '轨道点击是真实用户意图');
    expect(lease.scrollController.position.pixels, greaterThan(0.5));
    await tester.sendEventToBinding(mouse.removePointer());
  });

  testWidgets('详情字段 token 由唯一 formatter 给出且不同问答 part 不撞', (tester) async {
    // 独立构造的同值字段必须得到同一 token；不同问答 part 必须不同。
    expect(
      StudioDriverKeyValues.timelineDetailField(const ThreadTextFieldView()),
      StudioDriverKeyValues.timelineDetailField(const ThreadTextFieldView()),
    );
    expect(
      StudioDriverKeyValues.timelineDetailField(
        const ThreadToolUserInputFieldView(
          questionIndex: 0,
          part: ThreadUserInputHeaderFieldPartView(),
        ),
      ),
      isNot(
        StudioDriverKeyValues.timelineDetailField(
          const ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputAnswerFieldPartView(0),
          ),
        ),
      ),
    );
    expect(
      StudioDriverKeyValues.timelineDetailField(
        const ThreadToolUserInputFieldView(
          questionIndex: 1,
          part: ThreadUserInputQuestionFieldPartView(),
        ),
      ),
      'user-input-1-question',
    );

    // 视图上的按钮 key 与快照 token 同源。
    final lease = leaseFor(
      tester,
      items: [textItem('big', ordinal: 1, body: '预览', totalBytes: 46)],
    );
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'big',
          StudioDriverKeyValues.timelineDetailField(
            const ThreadTextFieldView(),
          ),
        ),
      ),
      findsOneWidget,
    );
  });

  // ---- B4 详情查看器：活动 scope、重试不重拼、退役即终态 --------------------------

  group('B4 详情查看器', () {
    testWidgets('每块/重试都取当前 lease 的活动 scope，退役后停止并要求重开', (tester) async {
      final (client, owner, transport) = await _openDetailSession(tester);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      final lease = owner.lease('thread')!;
      final first = transport.connections.single;

      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: owner.source.value!,
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(
          StudioDriverKeys.timelineDetailOpen(
            'big',
            StudioDriverKeyValues.timelineDetailField(
              const ThreadTextFieldView(),
            ),
          ),
        ),
      );
      await _pumpFrames(tester);

      // 第一块：从活动 scope 请求，continuation 为 null、revision 固定。
      expect(first.detailCalls, hasLength(1));
      expect(first.detailCalls.single.query.continuation, isNull);
      expect(first.detailCalls.single.query.revision, 1);
      first.detailCalls.single.reply.complete(_chunk(continuation: 'c1'));
      await _pumpFrames(tester);

      // 自动继续：第二块携带同一 revision 的 continuation，前缀不重复。
      expect(first.detailCalls, hasLength(2));
      expect(first.detailCalls[1].query.continuation, 'c1');
      final text = find.byKey(StudioDriverKeys.timelineDetailText);
      expect(tester.widget<SelectableText>(text).data, '甲🐱\n');
      expect(
        tester
            .widget<IconButton>(find.byKey(StudioDriverKeys.timelineDetailCopy))
            .onPressed,
        isNull,
        reason: '未读完整时不允许“复制全文”',
      );

      // 第二块在 attempt 更替后失效 → 可见可重试错误。
      first.detailCalls[1].reply.completeError(const StaleConversationScope());
      await _pumpFrames(tester);
      expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsOneWidget);
      expect(find.textContaining('scope has been retired'), findsOneWidget);
      expect(tester.widget<SelectableText>(text).data, '甲🐱\n');

      // 连接 attempt 更替（新订阅尚未建立）：旧 scope 失活。
      final session = client.conversations.session('thread');
      transport.holdNextOpen = true;
      await tester.runAsync(() async {
        session.content.refresh();
        await transport.opened(2);
      });
      await _pumpFrames(tester);

      // 重试：从当前 lease 重新取活动 scope；不得再向旧 attempt 发块。
      await tester.tap(find.byKey(StudioDriverKeys.timelineDetailRetry));
      await _pumpFrames(tester);
      expect(
        first.detailCalls,
        hasLength(2),
        reason: '重试不得复用旧 scope 继续向旧 attempt 发块',
      );
      expect(
        find.textContaining('attempt has been retired'),
        findsOneWidget,
        reason: '重试必须落在新 attempt 的 scope 上（旧 scope 会永远报 scope retired）',
      );
      expect(tester.widget<SelectableText>(text).data, '甲🐱\n');

      // 新基线到达 → 新代次；生产 shell 用新 lease 重建列表，旧代次真实卸载后退役。
      await tester.runAsync(() async {
        transport.releaseHeld();
        await session.content.ready;
        await owner.source.waitFor(
          (state) => state != null && state.generation > lease.generation,
        );
      });
      await _pumpFrames(tester);
      final nextLease = owner.lease('thread')!;
      expect(nextLease.generation, greaterThan(lease.generation));
      expect(lease.isMounted, isTrue, reason: '换代前旧 View 仍真实挂载');
      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: owner.source.value!,
            lease: nextLease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(
        lease.isMounted,
        isFalse,
        reason: '新 key 必须销毁旧 View 并解绑旧 controls',
      );
      expect(nextLease.isMounted, isTrue, reason: '同位置新 View 必须绑定新 controls');
      // 旧代次真实退役并释放（owner 已 retire；这里等待真实 released ACK）。
      await pumpClientFuture(tester, lease.retire(), 'B4 old lease retirement');
      await pumpClientFuture(
        tester,
        lease.released,
        'B4 old lease released ACK',
      );
      await _pumpFrames(tester);

      // lease 退役：终态、无 retry、不拼接新内容、不再向新连接发块。
      expect(
        find.byKey(StudioDriverKeys.timelineDetailTerminal),
        findsOneWidget,
      );
      expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsNothing);
      // 退役即释放正文/累计字节并禁复制（不是只保 prefix）。
      expect(tester.widget<SelectableText>(text).data, '');
      expect(
        tester
            .widget<IconButton>(find.byKey(StudioDriverKeys.timelineDetailCopy))
            .onPressed,
        isNull,
      );
      expect(transport.connections, hasLength(2));
      expect(transport.connections[1].detailCalls, isEmpty);

      await _unmountTimeline(tester);
      await _pumpFrames(tester);
      await _closeDetailSession(tester, owner, client, deadline);
      await _pumpFrames(tester, frames: 2);
    });
  });

  testWidgets('关闭在途读取：停新块、await 自己已受理读取后才离开', (tester) async {
    final (client, owner, transport) = await _openDetailSession(tester);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final lease = owner.lease('thread')!;
    final first = transport.connections.single;
    final queriesBefore = client.budget.used(ResourceKind.pendingOperation);

    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: owner.source.value!,
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'big',
          StudioDriverKeyValues.timelineDetailField(
            const ThreadTextFieldView(),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(first.detailCalls, hasLength(1));
    expect(
      client.budget.used(ResourceKind.pendingOperation),
      queriesBefore + 1,
      reason: '真实 SDK scope 持有已受理读取的 permit',
    );

    // 读取仍在途：点关闭必须先等它真的退出，不能同步 pop 出假 ACK。
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await _pumpFrames(tester);
    expect(
      find.byKey(StudioDriverKeys.timelineDetailDialog),
      findsOneWidget,
      reason: '已受理读取未退出前不得关闭',
    );
    expect(first.detailCalls, hasLength(1), reason: '停止后续块');
    expect(
      client.budget.used(ResourceKind.pendingOperation),
      queriesBefore + 1,
      reason: '关闭请求不能提前释放尚未退出的读取',
    );

    // 底层读取退出后，关闭完成。
    first.detailCalls.single.reply.complete(_chunk(continuation: 'c1'));
    // 退出等待结束、route 退场动画走完后查看器才真正离开树。
    await _pumpFrames(tester, frames: 16);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
    expect(first.detailCalls, hasLength(1), reason: '关闭后不再发新块');
    expect(client.budget.used(ResourceKind.pendingOperation), queriesBefore);
    expect(first.closed, isFalse, reason: '详情关闭只释放自己的 scope，不关闭共享 feed');

    await _unmountTimeline(tester);
    await _pumpFrames(tester);
    await _closeDetailSession(tester, owner, client, deadline);
    expect(lease.isReleased, isTrue);
    expect(first.closed, isTrue);
    expect(first.closeCalls, 1);
    expect(client.budget.usage, isEmpty);
    await _pumpFrames(tester, frames: 2);
  });

  testWidgets('同 lease 重试走新 attempt 的 scope 并成功续读，不重字、可复制', (tester) async {
    final (client, owner, transport) = await _openDetailSession(tester);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final lease = owner.lease('thread')!;
    final first = transport.connections.single;
    final generation = lease.generation;

    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: owner.source.value!,
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'big',
          StudioDriverKeyValues.timelineDetailField(
            const ThreadTextFieldView(),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
    first.detailCalls.single.reply.complete(_chunk(continuation: 'c1'));
    await _pumpFrames(tester);
    first.detailCalls[1].reply.completeError(const StaleConversationScope());
    await _pumpFrames(tester);
    expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsOneWidget);

    // 新连接已打开但首帧仍挂起：旧 lease 保持活跃，新 attempt 的 scope 已可用。
    transport.holdNextInitial = true;
    final session = client.conversations.session('thread');
    await tester.runAsync(() async {
      session.content.refresh();
      await transport.opened(2);
    });
    await _pumpFrames(tester);
    expect(transport.connections, hasLength(2));

    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailRetry));
    await _pumpFrames(tester);
    final second = transport.connections[1];
    expect(second.detailCalls, hasLength(1), reason: '重试走新 attempt 的 scope');
    expect(second.detailCalls.single.query.continuation, 'c1');
    expect(second.detailCalls.single.query.revision, 1);
    second.detailCalls.single.reply.complete(_chunk(text: '乙\r\n'));
    await _pumpFrames(tester);

    final text = find.byKey(StudioDriverKeys.timelineDetailText);
    expect(tester.widget<SelectableText>(text).data, '甲🐱\n乙\r\n');
    expect(
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.timelineDetailCopy))
          .onPressed,
      isNotNull,
      reason: '完整读完后允许复制全文',
    );
    // S4：真实点击复制，平台剪贴板实际写入的就是逐字拼接的完整正文。
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailCopy));
    await _pumpFrames(tester);
    expect(copied, '甲🐱\n乙\r\n', reason: '复制内容必须等于逐块拼接的真实正文');
    expect(lease.generation, generation, reason: '同 lease 重试不换代');
    expect(first.detailCalls, hasLength(2), reason: '旧 attempt 不再收块');

    transport.releaseInitial();
    await tester.runAsync(() async {
      await session.content.ready;
      await owner.source.waitFor(
        (state) => state != null && state.generation > generation,
      );
    });
    await _pumpFrames(tester);
    final replacement = owner.lease('thread')!;
    expect(replacement, isNot(same(lease)));
    expect(
      replacement.queries!.generation,
      replacement.generation,
      reason: '新基线的新代次必须拥有自己的真实查询 scope',
    );
    expect(find.byKey(StudioDriverKeys.timelineDetailTerminal), findsOneWidget);
    expect(
      tester.widget<SelectableText>(text).data,
      '',
      reason: '已复制完成的旧查看器同样在展示退役时释放原文',
    );
    await _unmountTimeline(tester);
    await _pumpFrames(tester);
    await _closeDetailSession(tester, owner, client, deadline);
    await _pumpFrames(tester, frames: 2);
  });

  // ---- R1 typed 确定失效：同一冻结引用重试无意义 -----------------------------------

  for (final code in const <StudioFailureCode>[
    StudioFailureCode.staleRevision,
    StudioFailureCode.notFound,
  ]) {
    testWidgets('SDK 明确 ${code.name} 时查看器进入终态：清正文、无 retry、禁复制', (tester) async {
      final (client, owner, transport) = await _openDetailSession(tester);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      final lease = owner.lease('thread')!;
      final connection = transport.connections.single;

      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: owner.source.value!,
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          StudioDriverKeys.timelineDetailOpen(
            'big',
            StudioDriverKeyValues.timelineDetailField(
              const ThreadTextFieldView(),
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
      connection.detailCalls.single.reply.complete(_chunk(continuation: 'c1'));
      await _pumpFrames(tester);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(StudioDriverKeys.timelineDetailText),
            )
            .data,
        '甲🐱\n',
      );

      // 真实 SDK 公开通路：受控 backend 在该冻结引用上返回 typed 失败。
      connection.detailCalls[1].reply.completeError(
        StudioFailure(
          code: code,
          message: 'detail reference is no longer readable',
          retryable: true,
          correlationId: 'synthetic-${code.name}',
        ),
      );
      await _pumpFrames(tester);

      expect(
        find.byKey(StudioDriverKeys.timelineDetailTerminal),
        findsOneWidget,
        reason: '确定失效必须给终态，不能停在通用 error',
      );
      expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsNothing);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(StudioDriverKeys.timelineDetailText),
            )
            .data,
        '',
        reason: '终态释放正文缓存',
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(StudioDriverKeys.timelineDetailCopy))
            .onPressed,
        isNull,
      );
      expect(connection.detailCalls, hasLength(2), reason: '终态不得继续发块');

      await _unmountTimeline(tester);
      await _pumpFrames(tester);
      await _closeDetailSession(tester, owner, client, deadline);
      await _pumpFrames(tester, frames: 2);
    });
  }

  // ---- R4 正文选择边界：界面提示不是 canonical 正文 -------------------------------

  /// design/26 §26.8：正文选择只包含所选内容域的文本。详情入口行是界面提示，不属于
  /// canonical 正文，不随跨块选择进入剪贴板；入口的点击、焦点与辅助语义保留。
  testWidgets(
    '跨块全选的实际复制内容只含 canonical 正文，入口行文案不进入剪贴板',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      final (client, owner, transport) = await _openDetailSession(
        tester,
        baseline: _selectionBaseline(),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      final lease = owner.lease('thread')!;
      final connection = transport.connections.single;

      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: owner.source.value!,
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 提示子树当前真实渲染的文案：不是测试自己构造的字符串。
      final notice = find.byKey(StudioDriverKeys.timelineItemBodyNotice('big'));
      expect(notice, findsOneWidget);
      final rows = find.descendant(
        of: notice,
        matching: find.byType(TimelineActivityRow),
      );
      final activityRows = tester
          .widgetList<TimelineActivityRow>(rows)
          .toList();
      expect(activityRows, hasLength(1), reason: '基线只有一个被截断字段，因此只有一行入口');
      final hints = tester
          .widgetList<Text>(
            find.descendant(of: notice, matching: find.byType(Text)),
          )
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      expect(hints, hasLength(1), reason: '每字段一行入口文案，不再有截断说明句');
      expect(activityRows.single.label, hints.single, reason: '活动行文案就是唯一入口文案');
      expect(
        tester
            .widget<Text>(
              find.descendant(of: notice, matching: find.byType(Text)).first,
            )
            .maxLines,
        1,
        reason: '入口行只占一行，超出在行内省略',
      );

      // 选择边界不夺走入口：仍可点击、可进入键盘焦点、保留辅助语义标签。
      final open = find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'big',
          StudioDriverKeyValues.timelineDetailField(
            const ThreadTextFieldView(),
          ),
        ),
      );
      expect(tester.widget<InkWell>(open).onTap, isNotNull);
      await tester.ensureVisible(open);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      // Flutter merges this row with its preview into the tappable node; the
      // complete accessible label and actions still have to remain intact.
      expect(
        tester.getSemantics(open),
        matchesSemantics(
          label: '截断前的preview\n完整正文',
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
      final buttonLabel = tester.element(
        find.descendant(of: open, matching: find.byType(Text)).first,
      );
      Focus.of(buttonLabel).requestFocus();
      await tester.pump();
      expect(
        Focus.of(buttonLabel).hasFocus,
        isTrue,
        reason: '正文选择边界不得移除详情入口的键盘焦点',
      );

      // 平台剪贴板只截获 Flutter 真实复制路径写出的值，不自行写入期望值。
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      // 真实点击打开查看器；全文接纳与复制、列表预览复制是两个独立信号。
      const fullText = '截断前的preview补足完整内容呀';
      await tester.tap(open);
      await _pumpFrames(tester);
      expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsOneWidget);
      connection.detailCalls.single.reply.complete(
        _chunk(text: fullText, totalBytes: 40),
      );
      await _pumpFrames(tester);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(StudioDriverKeys.timelineDetailText),
            )
            .data,
        fullText,
      );
      final detailOwner = tester
          .widget<TimelineDetailConnector>(find.byType(TimelineDetailConnector))
          .owner;
      expect(detailOwner.state.text, fullText);
      expect(detailOwner.state.error, isNull);
      expect(detailOwner.state.complete, isTrue);
      expect(detailOwner.state.loading, isFalse);
      expect(detailOwner.state.terminal, isFalse);
      expect(detailOwner.canCopy, isTrue);
      expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsNothing);
      expect(find.byKey(StudioDriverKeys.timelineDetailTerminal), findsNothing);
      final detailCopy = find.byKey(StudioDriverKeys.timelineDetailCopy);
      expect(tester.widget<IconButton>(detailCopy).onPressed, isNotNull);
      await tester.tap(detailCopy);
      await _pumpFrames(tester);
      expect(copied, fullText, reason: '40 字节全文经真实详情复制路径原样写入');
      await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
      await _pumpFrames(tester, frames: 16);
      expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);

      copied = null;
      final regionFinder = find.byType(SelectableRegion);
      expect(regionFinder, findsOneWidget);
      final region = tester.state<SelectableRegionState>(regionFinder);
      // 跨块全选：与工具栏 Select All / Ctrl+A 同一条公开选择状态通路。
      region.selectAll();
      await tester.pumpAndSettle();
      final copy = region.contextMenuButtonItems.singleWhere(
        (item) => item.type == ContextMenuButtonType.copy,
      );
      copy.onPressed!();
      await _pumpFrames(tester);

      expect(copied, isNotNull, reason: '真实复制路径写入了平台剪贴板');
      // 选区的 plainText 保留按钮内文本的硬换行，这里只做断言侧的空白规范化比较，
      // 不改写生产复制字符串。
      final normalized = copied!.replaceAll(RegExp(r'\s+'), ' ');
      for (final hint in hints) {
        expect(
          normalized,
          isNot(contains(hint)),
          reason: '界面提示不属于 canonical 正文，不得进入剪贴板',
        );
      }
      expect(
        copied,
        '前段canonical正文截断前的preview后段canonical正文',
        reason: '精确等于所选内容域的正文（SDK 顺序拼接、不插分隔）',
      );

      await _unmountTimeline(tester);
      await _pumpFrames(tester);
      await _closeDetailSession(tester, owner, client, deadline);
      await _pumpFrames(tester, frames: 2);
    },
  );

  // ---- 详情入口行：每个被截断字段一行，不额外渲染说明句 ----------------------------

  testWidgets('参数与输出同时被截断时每个字段恰好一行活动行入口', (tester) async {
    final (client, owner, _) = await _openDetailSession(
      tester,
      baseline: _twoFieldBaseline(),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final lease = owner.lease('thread')!;

    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: owner.source.value!,
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 工具条目属于活动组：展开后成员行与其详情入口才构建。
    final group = lease.presentationFor('tool')!;
    await tester.tap(
      find.byKey(StudioDriverKeys.timelineActivitySummary(group.id)),
    );
    await tester.pumpAndSettle();

    final notice = find.byKey(StudioDriverKeys.timelineItemBodyNotice('tool'));
    expect(notice, findsOneWidget);
    final rows = find.descendant(
      of: notice,
      matching: find.byType(TimelineActivityRow),
    );
    // 基线恰好两个被截断字段：入口行数必须等于字段数，没有额外的说明行。
    expect(rows, findsNWidgets(2), reason: '每个被截断字段一行入口');
    expect(
      tester.widgetList<TimelineActivityRow>(rows).map((row) => row.label),
      [
        timelineFieldLabel(const ThreadToolArgumentsFieldView()),
        timelineFieldLabel(const ThreadToolResultFieldView()),
      ],
      reason: '行文案是字段领域名，不是截断说明句',
    );
    for (final field in const <ThreadContentFieldView>[
      ThreadToolArgumentsFieldView(),
      ThreadToolResultFieldView(),
    ]) {
      final open = find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'tool',
          StudioDriverKeyValues.timelineDetailField(field),
        ),
      );
      expect(open, findsOneWidget, reason: '每个被截断字段都有自己的入口');
      expect(tester.widget<InkWell>(open).onTap, isNotNull);
      expect(
        find.descendant(of: open, matching: find.byType(TimelineActivityRow)),
        findsOneWidget,
        reason: '入口就是一行活动行，不另建行样式',
      );
    }

    await _unmountTimeline(tester);
    await _pumpFrames(tester);
    await _closeDetailSession(tester, owner, client, deadline);
    await _pumpFrames(tester, frames: 2);
  });

  // ---- 只读滚动诊断：查询时现场读取当前 controller，不复用通知快照 -----------------

  testWidgets('滚动诊断每次请求读当前 position：拖动中 true，抬手归 false 后立即 false', (
    tester,
  ) async {
    final (client, owner, transport) = await _openDetailSession(
      tester,
      baseline: _longBaseline(),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final lease = owner.lease('thread')!;
    await _emitTailAdditions(
      tester,
      owner: owner,
      lease: lease,
      connection: transport.connections.single,
      from: 1,
      to: 2,
      items: [
        for (var index = 32; index < 40; index++)
          componentText(
            'line-$index',
            ordinal: index,
            body: '第 $index 段静态正文' * 6,
          ),
      ],
    );
    expect(lease.loadedCount, 40);
    expect(lease.items.map((item) => item.id), [
      for (var index = 0; index < 40; index++) 'line-$index',
    ]);
    // Driver only reads these domains; any account transport use fails closed.
    final accounts = (await tester.runAsync(() async {
      final ports = _UnusedTimelineAccountPorts();
      return AccountDomainResources(
        feed: ports,
        configuration: ports,
        modelPort: ports,
        usagePort: ports,
        acpPort: ports,
        coordinator: client.settingsWrites,
        mutations: client.mutations,
        budget: client.budget,
        owner: 'timeline-driver-accounts',
      );
    }))!;
    addTearDown(() async {
      // Account resources were constructed in the real event zone above.
      final report = await tester.runAsync(
        () => accounts.close(deadline: deadline),
      );
      expect(report!.unresolved, isEmpty);
    });
    bindStudioDriver(
      client,
      timeline: owner,
      accountsRepository: accounts.accounts,
      modelsRepository: accounts.models,
      usageRepository: accounts.usage,
      acpService: accounts.acp,
    );

    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: owner.source.value!,
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final controller = lease.scrollController;
    final position = controller.position;
    expect(position.maxScrollExtent, greaterThan(200), reason: '静态长内容真实溢出');

    // 静止：诊断等于当前真实几何，不滚动。
    final idle = StudioDriverState.readFacts().timelineScroll;
    expect(idle, isNotNull);
    expect(idle!.threadId, 'thread');
    expect(idle.generation, lease.generation);
    expect(idle.pixels, position.pixels);
    expect(idle.maxScrollExtent, position.maxScrollExtent);
    expect(idle.isScrolling, isFalse);
    expect(idle.isScrolling, position.isScrollingNotifier.value);
    expect(idle.atLiveEdge, isTrue);

    // 真实内容拖动：标准 position 自己进入滚动活动，诊断必须当场为 true。
    final anchor = tester.getCenter(
      find.byKey(StudioDriverKeys.timelineRow('line-39')),
    );
    final gesture = await tester.startGesture(
      anchor,
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(position.isScrollingNotifier.value, isTrue, reason: '拖动确实在滚动');
    final dragging = StudioDriverState.readFacts().timelineScroll;
    expect(dragging, isNotNull);
    expect(dragging!.isScrolling, isTrue);
    expect(dragging.isScrolling, position.isScrollingNotifier.value);
    expect(dragging.pixels, position.pixels, reason: '诊断读的是同一个 position');
    final pixelsWhileDragging = position.pixels;

    // 抬手：等标准 position 自己结束（真实动画/惯性），不加滚动/改窗/内容增长。
    await gesture.up();
    for (var frame = 0; frame < 240; frame++) {
      if (!position.isScrollingNotifier.value) break;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      position.isScrollingNotifier.value,
      isFalse,
      reason: '标准 position 已经自己结束滚动',
    );
    // 同一帧内立刻读诊断：不依赖后续任何一次滚动通知/几何事件。
    final settled = StudioDriverState.readFacts().timelineScroll;
    expect(settled, isNotNull);
    expect(
      settled!.isScrolling,
      isFalse,
      reason: 'ScrollEnd 通知早于 notifier 提交，缓存会把这里永久留在 true',
    );
    expect(settled.isScrolling, position.isScrollingNotifier.value);
    expect(settled.pixels, position.pixels);
    expect(position.pixels, isNot(0), reason: '确实是从内容里滚出来的位置');
    expect(
      position.pixels,
      greaterThanOrEqualTo(pixelsWhileDragging - 1),
      reason: '抬手后没有再被追加滚动',
    );

    // 再连读两次仍是现读：不是把一次 false 缓成常量。
    final again = StudioDriverState.readFacts().timelineScroll!;
    expect(again.isScrolling, position.isScrollingNotifier.value);
    expect(again.pixels, position.pixels);

    // 真实子树卸载 + 旧代次退役：不返回上一代几何，也不拿别的 Thread 的代次顶替。
    await _unmountTimeline(tester);
    await _pumpFrames(tester);
    await pumpClientFuture(tester, lease.retire(), 'Driver lease retirement');
    await pumpClientFuture(tester, lease.released, 'Driver lease released ACK');
    expect(
      StudioDriverState.readFacts().timelineScroll,
      isNull,
      reason: '退役/无挂载代次不得继续报告上一代几何',
    );
    final ownerReport = await pumpClientFuture(
      tester,
      owner.close(deadline: deadline),
      'Driver timeline owner close',
    );
    expect(ownerReport.unresolved, isEmpty);
    final accountReport = await tester.runAsync(
      () => accounts.close(deadline: deadline),
    );
    expect(accountReport!.unresolved, isEmpty);
    final clientReport = await pumpClientFuture(
      tester,
      client.close(deadline: deadline),
      'Driver client close',
    );
    expect(clientReport.unresolved, isEmpty);
    await _pumpFrames(tester, frames: 2);
  });

  testWidgets('单段思考一次展开保留概要和内容，缺失字段不生成空区块', (tester) async {
    for (final (summary, content) in [
      (['Summary evidence'], ['Full reasoning evidence']),
      (['Summary evidence'], <String>[]),
      (<String>[], ['Full reasoning evidence']),
      (<String>['  '], <String>[]),
    ]) {
      final lease = leaseFor(
        tester,
        items: [
          conversationFixture(
            id: 'thinking',
            threadId: 'thread',
            ordinal: 1,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            descriptor: ConversationThinkingDescriptor(
              lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
            ),
            fields: {
              for (final (chunkIndex, chunk) in summary.indexed)
                ThreadThinkingSummaryFieldView(chunkIndex): chunk,
              for (final (chunkIndex, chunk) in content.indexed)
                ThreadThinkingContentFieldView(chunkIndex): chunk,
            },
          ),
        ],
      );
      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: viewState(),
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final group = lease.presentationFor('thinking')!;
      await tester.tap(
        find.byKey(StudioDriverKeys.timelineActivitySummary(group.id)),
      );
      await tester.pumpAndSettle();
      final hasSummary = summary.any((chunk) => chunk.trim().isNotEmpty);
      final hasContent = content.any((chunk) => chunk.trim().isNotEmpty);
      final fields = tester
          .widgetList<TimelineMarkdown>(
            find.descendant(
              of: find.byKey(StudioDriverKeys.timelineBlock('thinking')),
              matching: find.byType(TimelineMarkdown),
            ),
          )
          .map((widget) => widget.text)
          .toList();
      expect(fields, [
        if (hasSummary) summary.join(),
        if (hasContent) content.join(),
      ], reason: '一次展开同时展示真实概要/正文，空白或缺失字段不生成空区块');
      if (hasSummary) {
        expect(find.text(summary.join(), findRichText: true), findsOneWidget);
      }
      if (hasContent) {
        expect(find.text(content.join(), findRichText: true), findsOneWidget);
      }
      expect(find.text('No reasoning text was provided.'), findsNothing);
      await _unmountTimeline(tester);
      await tester.pumpAndSettle();
      await pumpClientFuture(tester, lease.retire(), 'thinking lease release');
    }
  });

  testWidgets('读取文件以状态和文件名单行展示，详情只在点击后构建', (tester) async {
    final lease = leaseFor(
      tester,
      items: [
        toolItem(
          'read-1',
          name: 'read_file',
          arguments: '{"path":"/workspace/src/target.dart"}',
        ),
      ],
    );
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        StudioDriverKeys.timelineActivitySummary(
          lease.presentationFor('read-1')!.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final block = find.byKey(StudioDriverKeys.timelineBlock('read-1'));
    final row = find
        .descendant(of: block, matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(row).height, lessThanOrEqualTo(40));
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(
      find.textContaining('target.dart', findRichText: true),
      findsOneWidget,
    );
    expect(find.byTooltip('/workspace/src/target.dart'), findsOneWidget);
    final bodies = find.descendant(
      of: block,
      matching: find.byType(TimelineMarkdown),
    );
    expect(bodies, findsNothing, reason: '点击前不得构建工具参数/结果正文');
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<TimelineMarkdown>(bodies).map((body) => body.text),
      ['{"path":"/workspace/src/target.dart"}', 'ok'],
      reason: '点击后按原文展示参数和结果，不依赖旧私有代码块形状',
    );
    await _unmountTimeline(tester);
    await tester.pumpAndSettle();
    await pumpClientFuture(tester, lease.retire(), 'read-file lease release');
  });

  // ---- S1 图片增量：默认折叠、用户展开语义与引用释放 --------------------------------

  testWidgets('图片组默认折叠只按需读取，同 ID 更新保持用户展开/折叠，引用释放可判别', (tester) async {
    const arguments = '{"path":"/workspace/images/shot.png"}';
    const fullResult = 'ok: tool produced shared image';
    final transport = _ImageTransport(
      failures: 1,
      baseline: componentBaseline([
        imageToolItem(
          'call-a',
          ordinal: 1,
          name: 'mcp__plot',
          totalResultBytes: utf8.encode(fullResult).length,
        ),
        imageToolItem('call-b', ordinal: 2),
      ]),
    );
    final (client, owner, _) = await _openDetailSession(
      tester,
      backend: transport,
    );
    final lease = owner.lease('thread')!;
    final connection = transport.connections.single;
    final pendingBefore = client.budget.used(ResourceKind.pendingOperation);
    final entryA = StudioDriverKeys.toolImageEntryId('call-a', 'att-shared');
    Finder toggleFor(String id) => find.byKey(
      StudioDriverKeys.timelineActivitySummary(lease.presentationFor(id)!.id),
    );
    var version = lease.appliedVersion!;
    Future<void> patch(List<ConversationChange> changes) async {
      connection.emit(
        ConversationPatch(
          subscriptionId: connection.subscriptionId,
          from: version,
          to: ++version,
          priority: ConversationPriority.immediate,
          changes: changes,
        ),
      );
      await pumpClientUntil(
        tester,
        () => lease.appliedVersion == version,
        'image feed patch version $version applied',
      );
      expect(owner.lease('thread'), same(lease));
      expect(lease.appliedVersion, version);
      expect(transport.connections, hasLength(1));
    }

    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: owner.source.value!,
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
        client: client,
        owner: owner,
      ),
    );
    await tester.pumpAndSettle();

    // 默认折叠：没有缩略图，也没有任何字节读取（生产不再自动展开）。
    expect(toggleFor('call-a'), findsOneWidget);
    expect(_imageThumbnail('call-a'), findsNothing);
    expect(_imageThumbnail('call-b'), findsNothing);
    expect(transport.reads, isEmpty, reason: '折叠状态不得读取原图');

    // 连续调用共用展开意图，两个缩略图复用同一附件读取。
    await tester.tap(toggleFor('call-a'));
    await _pumpFrames(tester);
    await tester.pumpAndSettle();
    expect(transport.reads, ['thread:att-shared']);
    // The expanded production group is lazy and shorter than its first image.
    // Reach the second member through its actual inner scroll viewport.
    await tester.scrollUntilVisible(
      _imageRetry('call-b'),
      80,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(_imageRetry('call-a'), findsOneWidget);
    expect(_imageRetry('call-b'), findsOneWidget);
    // One shared retry replaces the failed attempt for BOTH mounted consumers.
    // Revealing the whole first button would evict the second lazy member.
    // Tap its actual visible portion instead, without calling either callback.
    final visibleRetry = tester
        .getRect(_imageRetry('call-a'))
        .intersect(tester.getRect(find.byType(ListView)));
    expect(visibleRetry.isEmpty, isFalse);
    await tester.tapAt(visibleRetry.center);
    expect(_imageConnector('call-a'), findsOneWidget);
    expect(_imageConnector('call-b'), findsOneWidget);
    // Native descriptor decoding needs the real event queue. The focus/layout
    // change can also evict the first lazy member; reach it again by scrolling.
    await pumpClientUntil(
      tester,
      () => _imageThumbnail('call-b').evaluate().length == 1,
      'shared-retry second image thumbnail decoded',
    );
    await tester.scrollUntilVisible(
      _imageConnector('call-a'),
      -40,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await pumpClientUntil(
      tester,
      () =>
          _imageThumbnail('call-a').evaluate().length == 1 &&
          _imageThumbnail('call-b').evaluate().length == 1,
      'both shared-retry image thumbnails decoded',
    );
    expect(_imageThumbnail('call-a'), findsOneWidget);
    expect(_imageThumbnail('call-b'), findsOneWidget);
    expect(_imageRetry('call-a'), findsNothing);
    expect(_imageRetry('call-b'), findsNothing);
    expect(transport.reads, ['thread:att-shared', 'thread:att-shared']);
    expect(find.text('/workspace/images/shot.png'), findsNothing);
    await tester.ensureVisible(_imageThumbnail('call-a'));
    await tester.pump();
    await tester.tap(_imageThumbnail('call-a'));
    await tester.pumpAndSettle();
    final imageDialog = find.byKey(StudioDriverKeys.viewImageDialog(entryA));
    expect(imageDialog, findsOneWidget);
    expect(find.text('shot.png'), findsOneWidget);
    expect(transport.reads, hasLength(2), reason: '原图复用共享字节，不新增读取');

    Finder detailAction(ThreadContentFieldView field) => find.descendant(
      of: imageDialog,
      matching: find.byKey(
        StudioDriverKeys.timelineDetailOpen(
          'call-a',
          StudioDriverKeyValues.timelineDetailField(field),
        ),
      ),
    );
    final argumentAction = detailAction(const ThreadToolArgumentsFieldView());
    final resultAction = detailAction(const ThreadToolResultFieldView());
    expect(argumentAction, findsOneWidget);
    expect(resultAction, findsOneWidget);
    expect(tester.widget<TextButton>(argumentAction).onPressed, isNotNull);
    expect(tester.widget<TextButton>(resultAction).onPressed, isNotNull);

    // The complete path is accessible in the typed argument route, not a
    // Flutter-side JSON/path panel. Each viewer owns its production scope.
    final sharedScope = lease.queries!;
    await tester.tap(argumentAction);
    await _pumpFrames(tester);
    final argumentOwner = tester
        .widget<TimelineDetailConnector>(find.byType(TimelineDetailConnector))
        .owner;
    expect(argumentOwner.lease, same(lease));
    expect(argumentOwner.field, const ThreadToolArgumentsFieldView());
    expect(connection.detailCalls, hasLength(1));
    expect(connection.detailCalls[0].itemId, 'call-a');
    expect(
      connection.detailCalls[0].query.field,
      const ThreadToolArgumentsFieldView(),
    );
    expect(connection.detailCalls[0].query.revision, 1);
    expect(connection.detailCalls[0].query.continuation, isNull);
    connection.detailCalls[0].reply.complete(
      ConversationDetailChunk(
        itemId: 'call-a',
        field: const ThreadToolArgumentsFieldView(),
        revision: 1,
        text: '{"path":"/workspace/images/',
        totalBytes: utf8.encode(arguments).length,
        continuation: 'path-tail',
      ),
    );
    await _pumpFrames(tester);
    expect(connection.detailCalls, hasLength(2));
    expect(connection.detailCalls[1].itemId, 'call-a');
    expect(
      connection.detailCalls[1].query.field,
      const ThreadToolArgumentsFieldView(),
    );
    expect(connection.detailCalls[1].query.continuation, 'path-tail');
    connection.detailCalls[1].reply.complete(
      ConversationDetailChunk(
        itemId: 'call-a',
        field: const ThreadToolArgumentsFieldView(),
        revision: 1,
        text: 'shot.png"}',
        totalBytes: utf8.encode(arguments).length,
        continuation: null,
      ),
    );
    await _pumpFrames(tester);
    expect(argumentOwner.state.text, arguments);
    expect(argumentOwner.state.error, isNull);
    expect(argumentOwner.state.complete, isTrue);
    expect(argumentOwner.canCopy, isTrue);
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(StudioDriverKeys.timelineDetailText),
          )
          .data,
      arguments,
      reason: '参数原文中的完整路径可读',
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await _pumpFrames(tester, frames: 16);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
    expect(client.budget.used(ResourceKind.pendingOperation), pendingBefore);
    expect(sharedScope.isActive, isTrue);
    expect(connection.closeCalls, 0);

    // Text accompanying an MCP image remains available as the full result
    // field. The baseline deliberately contains only its truncated preview.
    await tester.tap(resultAction);
    await _pumpFrames(tester);
    final resultOwner = tester
        .widget<TimelineDetailConnector>(find.byType(TimelineDetailConnector))
        .owner;
    expect(resultOwner, isNot(same(argumentOwner)));
    expect(resultOwner.lease, same(lease));
    expect(resultOwner.field, const ThreadToolResultFieldView());
    expect(connection.detailCalls, hasLength(3));
    expect(connection.detailCalls[2].itemId, 'call-a');
    expect(
      connection.detailCalls[2].query.field,
      const ThreadToolResultFieldView(),
    );
    expect(connection.detailCalls[2].query.continuation, isNull);
    connection.detailCalls[2].reply.complete(
      ConversationDetailChunk(
        itemId: 'call-a',
        field: const ThreadToolResultFieldView(),
        revision: 1,
        text: fullResult,
        totalBytes: utf8.encode(fullResult).length,
        continuation: null,
      ),
    );
    await _pumpFrames(tester);
    expect(resultOwner.state.text, fullResult);
    expect(resultOwner.state.error, isNull);
    expect(resultOwner.state.complete, isTrue);
    expect(resultOwner.canCopy, isTrue);
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(StudioDriverKeys.timelineDetailText),
          )
          .data,
      fullResult,
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await _pumpFrames(tester, frames: 16);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);

    // A fresh viewer admits its own query. Closing with that backend gate held
    // cannot acknowledge scope release or close the shared feed.
    await tester.tap(resultAction);
    await _pumpFrames(tester);
    expect(connection.detailCalls, hasLength(4));
    expect(connection.detailCalls[3].itemId, 'call-a');
    expect(
      connection.detailCalls[3].query.field,
      const ThreadToolResultFieldView(),
    );
    expect(connection.detailCalls[3].query.continuation, isNull);
    expect(sharedScope.pendingQueries, 0, reason: '详情不借用共享分页 scope');
    expect(
      client.budget.used(ResourceKind.pendingOperation),
      pendingBefore + 1,
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await _pumpFrames(tester);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsOneWidget);
    expect(
      client.budget.used(ResourceKind.pendingOperation),
      pendingBefore + 1,
    );
    expect(connection.closeCalls, 0);
    connection.detailCalls[3].reply.complete(
      ConversationDetailChunk(
        itemId: 'call-a',
        field: const ThreadToolResultFieldView(),
        revision: 1,
        text: fullResult,
        totalBytes: utf8.encode(fullResult).length,
        continuation: null,
      ),
    );
    await _pumpFrames(tester, frames: 16);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
    expect(sharedScope.isActive, isTrue);
    expect(client.budget.used(ResourceKind.pendingOperation), pendingBefore);
    expect(connection.closeCalls, 0);
    expect(transport.reads, hasLength(2), reason: '原图与工具详情操作均不重新读取附件');
    await tester.tap(find.byKey(StudioDriverKeys.timelineImageClose));
    await tester.pumpAndSettle();
    expect(imageDialog, findsNothing);

    // 同 canonicalID 的普通内容更新：保持用户已展开，且共享缓存不重读。
    await patch([
      ConversationAdd(
        imageToolItem(
          'call-a',
          ordinal: 1,
          name: 'mcp__plot',
          result: 'ok (streamed)',
          revision: 2,
        ),
      ),
    ]);
    await _pumpFrames(tester);
    expect(
      _imageThumbnail('call-a'),
      findsOneWidget,
      reason: '用户展开后同 ID 更新保持展开',
    );
    expect(transport.reads, hasLength(2), reason: '同附件不得重读');

    // 用户主动折叠后再更新：不得自动展开。
    await tester.tap(toggleFor('call-a'));
    await _pumpFrames(tester);
    await tester.pumpAndSettle();
    expect(_imageThumbnail('call-a'), findsNothing);
    await patch([
      ConversationAdd(
        imageToolItem(
          'call-a',
          ordinal: 1,
          name: 'mcp__plot',
          result: 'ok (final)',
          revision: 3,
        ),
      ),
    ]);
    await _pumpFrames(tester);
    expect(
      _imageThumbnail('call-a'),
      findsNothing,
      reason: '用户折叠后同 ID 更新不得自动展开',
    );
    expect(transport.reads, hasLength(2));

    // 共享引用：移除 call-a 后 call-b 仍持有该附件 → 缓存保留，展开不重读。
    await patch([const ConversationRemove('call-a')]);
    await _pumpFrames(tester);
    await tester.tap(toggleFor('call-b'));
    await pumpClientUntil(
      tester,
      () => _imageThumbnail('call-b').evaluate().length == 1,
      'retained shared image thumbnail decoded',
    );
    expect(_imageThumbnail('call-b'), findsOneWidget);
    expect(transport.reads, hasLength(2), reason: '共享附件在仍有引用时不丢缓存');

    // 最后一个引用消失 → 缓存释放：重新插入并展开会重新读取。
    await patch([const ConversationRemove('call-b')]);
    await _pumpFrames(tester);
    await patch([
      // Reappearance keeps the item's stable ordering identity; it changes
      // neither the attachment reference-release boundary nor the new read.
      ConversationAdd(
        imageToolItem('call-a', ordinal: 1, name: 'mcp__plot', revision: 4),
      ),
    ]);
    await _pumpFrames(tester);
    await tester.tap(toggleFor('call-a'));
    await pumpClientUntil(
      tester,
      () => _imageThumbnail('call-a').evaluate().length == 1,
      'reinserted image thumbnail decoded after last reference release',
    );
    expect(transport.reads, hasLength(3), reason: '最后引用释放后重新展开必须重新读取');
    expect(_imageThumbnail('call-a'), findsOneWidget);
    expect(_imageRetry('call-a'), findsNothing);

    await _unmountTimeline(tester);
    await _pumpFrames(tester);
  });

  testWidgets('退役展示尚未卸载时不再发布阅读意图', (tester) async {
    final lease = leaseFor(tester, items: longHistory());
    var intents = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onRetryConnection: () async {},
          onEnterHistory: () => intents++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final released = lease.retire();
    try {
      final pointer = TestPointer(9, PointerDeviceKind.mouse);
      final center = tester.getCenter(find.byKey(StudioDriverKeys.timeline));
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.pumpAndSettle();
      expect(lease.scrollController.position.pixels, greaterThan(0));
      expect(intents, 0, reason: '旧子树的最后一次滚动不能冻结已经切回的新展示');
    } finally {
      await _unmountTimeline(tester);
      await pumpClientFuture(tester, released, 'retired mounted lease release');
    }
  });

  testWidgets('退役展示的已捕获按钮回调不再发布动作', (tester) async {
    for (final phase in [
      TimelineConnectionPhase.ready,
      TimelineConnectionPhase.failed,
    ]) {
      final baseline = componentBaseline(
        [
          for (var index = 0; index < 32; index++)
            componentText(
              'history-$index',
              ordinal: 100 + index,
              body: '旧展示第 $index 段正文' * 8,
            ),
        ],
        before: 'old-cursor',
        hasOlder: true,
      );
      final (client, owner, transport) = await _openDetailSession(
        tester,
        baseline: baseline,
      );
      final lease = owner.lease('thread')!;
      final first = transport.connections.single;
      await _emitTailAdditions(
        tester,
        owner: owner,
        lease: lease,
        connection: first,
        from: 1,
        to: 2,
        items: [
          for (var index = 32; index < 40; index++)
            componentText(
              'history-$index',
              ordinal: 100 + index,
              body: '旧展示第 $index 段正文' * 8,
            ),
        ],
      );
      expect(lease.loadedCount, 40);
      expect(lease.items.map((item) => item.id), [
        for (var index = 0; index < 40; index++) 'history-$index',
      ]);
      expect(first.pageCalls, isEmpty, reason: '补足规模仅用真实增量，不占分页计数');
      final pendingBefore = client.budget.used(ResourceKind.pendingOperation);
      await owner.dispatch('thread', const TimelineEnterHistory());
      expect(lease.hasOlder, isTrue);
      expect(lease.olderCursor, 'old-cursor');

      // Obtain the real error banner from a legally admitted history query.
      final failedPage = owner.loadOlder(
        'thread',
        generation: lease.generation,
      );
      await pumpClientFuture(
        tester,
        first.pageEntered(1),
        'history page admitted',
      );
      expect(first.pageCalls.single.before, 'old-cursor');
      final pageFailure = StateError('synthetic history page failure');
      first.pageCalls.single.reply.completeError(pageFailure);
      await pumpClientFuture(tester, failedPage, 'failed history page settled');
      expect(owner.source.value!.olderError, same(pageFailure));
      expect(owner.source.value!.hasOlder, isTrue);
      expect(lease.hasOlder, isTrue);
      expect(lease.queries!.isActive, isTrue);
      expect(client.budget.used(ResourceKind.pendingOperation), pendingBefore);

      Future<void> renderConnector() async {
        await tester.pumpWidget(
          host(
            const TimelineConnector(threadId: 'thread'),
            client: client,
            owner: owner,
          ),
        );
        await tester.pump();
      }

      const actionKeys = <Key>[
        StudioDriverKeys.timelineRetryOlder,
        StudioDriverKeys.timelineReturnLive,
        StudioDriverKeys.timelineRetryConnection,
      ];
      Map<Key, VoidCallback> captureActions(Set<Key> expected) {
        final callbacks = <Key, VoidCallback>{};
        for (final key in actionKeys) {
          final finder = find.byKey(key);
          if (!expected.contains(key)) {
            expect(finder, findsNothing, reason: '$phase 不应显示 $key');
            continue;
          }
          expect(finder, findsOneWidget, reason: '$phase 必须显示可操作的 $key');
          final callback = tester.widget<ButtonStyleButton>(finder).onPressed;
          expect(callback, isNotNull, reason: '$phase 的 $key 必须实际可操作');
          callbacks[key] = callback!;
        }
        expect(callbacks.keys, unorderedEquals(expected));
        return callbacks;
      }

      await renderConnector();
      await tester.pumpAndSettle();
      expect(
        lease.scrollController.position.maxScrollExtent,
        greaterThan(0),
        reason: '长历史真实溢出，避免自动补页掩盖被测按钮',
      );
      final readyCallbacks = captureActions({
        StudioDriverKeys.timelineRetryOlder,
        StudioDriverKeys.timelineReturnLive,
      });
      final oldScope = lease.queries!;

      // First invoke retry while valid. It MUST admit the same real cursor;
      // retaining that query gate proves the later no-op is not an empty setup.
      readyCallbacks[StudioDriverKeys.timelineRetryOlder]!();
      await pumpClientFuture(
        tester,
        first.pageEntered(2),
        'retry history page admitted',
      );
      await tester.pump();
      expect(first.pageCalls[1].before, 'old-cursor');
      expect(oldScope.pendingQueries, 1);
      expect(owner.source.value!.isLoadingOlder, isTrue);
      expect(
        client.budget.used(ResourceKind.pendingOperation),
        pendingBefore + 1,
      );
      final acceptedPage = owner.retryOlder(
        'thread',
        generation: lease.generation,
      );
      expect(first.pageCalls, hasLength(2), reason: '借用原在途 join，不再受理一页');

      var callbacks = readyCallbacks;
      if (phase == TimelineConnectionPhase.failed) {
        const openFailure = StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'synthetic reconnect open failure',
          retryable: false,
          correlationId: 'retired-actions-connection',
        );
        // Exercise SDK failure/retry exhaustion, not a fabricated ViewState.
        // Waiting for its terminal state observes the real retry policy; there
        // is no sleep or test-side replacement of the connection state machine.
        transport.openFailure = openFailure;
        await tester.runAsync(() async {
          client.conversations.session('thread').content.refresh();
          await owner.source.waitFor(
            (state) => state?.connection == TimelineConnectionPhase.failed,
          );
        });
        await tester.pump();
        expect(owner.source.value!.connectionError, same(openFailure));
        expect(owner.lease('thread'), same(lease));
        expect(lease.hasOlder, isTrue);
        expect(oldScope.pendingQueries, 1);
        callbacks = captureActions({
          StudioDriverKeys.timelineReturnLive,
          StudioDriverKeys.timelineRetryConnection,
        });
      }

      final beforeRetirement = owner.source.value;
      final oldMessages = List<Message>.of(lease.controller.messages);
      final oldVersion = lease.appliedVersion;
      final opensBeforeRetirement = transport.openCalls;
      final queriesBeforeRetirement = transport.queryAdmissions;
      final released = lease.retire();
      expect(lease.isMounted, isTrue);
      expect(lease.isReleased, isFalse);
      expect(oldScope.isActive, isFalse);
      for (final action in callbacks.entries) {
        action.value();
        await tester.pump();
        expect(
          owner.source.value,
          same(beforeRetirement),
          reason: '${action.key} 不得从仍挂载的退役 View 发布动作',
        );
        expect(owner.lease('thread'), same(lease));
        expect(lease.isMounted, isTrue);
        expect(lease.isReleased, isFalse);
        expect(lease.appliedVersion, oldVersion);
        expect(lease.controller.messages, orderedEquals(oldMessages));
        expect(
          transport.openCalls,
          opensBeforeRetirement,
          reason: '${action.key}',
        );
        expect(
          transport.queryAdmissions,
          queriesBeforeRetirement,
          reason: '${action.key}',
        );
        expect(oldScope.pendingQueries, 1);
        expect(
          client.budget.used(ResourceKind.pendingOperation),
          pendingBefore + 1,
        );
      }

      // Establish a genuine replacement while the original accepted page is
      // still blocked. No empty-tree pump is allowed to stand in for rebind.
      transport.openFailure = null;
      transport.baseline = ConversationBaseline(
        subscriptionId: 'replacement-authority',
        version: 7,
        items: [
          for (var index = 0; index < 32; index++)
            componentText(
              'history-$index',
              ordinal: 100 + index,
              revision: 2,
              body: '新展示第 $index 段正文' * 8,
            ),
        ],
        before: 'old-cursor',
        hasOlder: true,
      );
      await tester.runAsync(() => owner.returnToLive('thread'));
      final replacement = owner.lease('thread')!;
      expect(replacement, isNot(same(lease)));
      expect(replacement.generation, greaterThan(lease.generation));
      expect(replacement.hasOlder, isTrue);
      expect(replacement.olderCursor, 'old-cursor');
      expect(replacement.appliedVersion, 7);
      expect(replacement.loadedCount, 32);
      await _emitTailAdditions(
        tester,
        owner: owner,
        lease: replacement,
        connection: transport.connections.last,
        from: 7,
        to: 8,
        items: [
          for (var index = 32; index < 40; index++)
            componentText(
              'history-$index',
              ordinal: 100 + index,
              revision: 2,
              body: '新展示第 $index 段正文' * 8,
            ),
        ],
      );
      expect(replacement.appliedVersion, 8);
      expect(replacement.loadedCount, 40);
      expect(transport.connections.last.pageCalls, isEmpty);
      await renderConnector();
      await tester.pumpAndSettle();
      expect(lease.isMounted, isFalse);
      expect(replacement.isMounted, isTrue);
      expect(lease.isReleased, isFalse, reason: '卸载不提前释放原查询许可');
      expect(replacement.items.map((item) => item.id), [
        for (var index = 0; index < 40; index++) 'history-$index',
      ]);
      expect(
        replacement
            .itemOf('history-39')!
            .fieldFor(const ThreadTextFieldView())!
            .text,
        '新展示第 39 段正文' * 8,
      );
      final replacementState = owner.source.value!;
      expect(replacementState.isLoadingOlder, isFalse);
      expect(replacementState.isPreparingLive, isFalse);
      final replacementMessages = List<Message>.of(
        replacement.controller.messages,
      );
      const replacementVersion = 8;
      final opensBeforeReplay = transport.openCalls;
      final queriesBeforeReplay = transport.queryAdmissions;
      final replacementBodies = {
        for (var index = 0; index < 40; index++)
          'history-$index': '新展示第 $index 段正文' * 8,
      };
      void expectReplacementUnchanged() {
        expect(owner.lease('thread'), same(replacement));
        expect(owner.source.value, same(replacementState));
        expect(owner.source.value!.isLoadingOlder, isFalse);
        expect(owner.source.value!.isPreparingLive, isFalse);
        expect(replacement.appliedVersion, replacementVersion);
        expect(
          replacement.controller.messages,
          orderedEquals(replacementMessages),
        );
        expect({
          for (final item in replacement.items)
            item.id: item.fieldFor(const ThreadTextFieldView())!.text,
        }, replacementBodies);
        expect(replacement.items.map((item) => item.revision), everyElement(2));
        expect(transport.openCalls, opensBeforeReplay);
        expect(transport.queryAdmissions, queriesBeforeReplay);
      }

      for (final action in callbacks.entries) {
        action.value();
        await tester.pump();
        expectReplacementUnchanged();
        expect(oldScope.pendingQueries, 1, reason: '${action.key} 不得遗失原 query');
        expect(
          client.budget.used(ResourceKind.pendingOperation),
          pendingBefore + 1,
        );
        expect(first.closeCalls, 0, reason: '原后端 gate 未退出前不能确认 feed join');
      }

      // Complete only the original backend gate, then join the SDK scope and
      // lease. Late history must not append into the replacement or reset it.
      first.pageCalls[1].reply.complete(
        ConversationPage(
          items: [componentText('late-old', ordinal: 99, body: '迟到的旧页')],
          before: 'older-next',
          hasOlder: true,
        ),
      );
      await _pumpFrames(tester);
      await pumpClientFuture(
        tester,
        acceptedPage,
        'original accepted history page join',
      );
      final report = await pumpClientFuture(
        tester,
        oldScope.close(),
        'old history scope close',
      );
      expect(report.unresolved, isEmpty);
      await pumpClientFuture(tester, released, 'old history lease release');
      await tester.pump();
      expect(lease.isReleased, isTrue);
      expect(first.closeCalls, 1);
      expect(oldScope.pendingQueries, 0);
      expect(client.budget.used(ResourceKind.pendingOperation), pendingBefore);
      expectReplacementUnchanged();
      expect(replacement.itemOf('late-old'), isNull);

      // A real replacement scope can now query the SAME cursor. This is the
      // SDK cancellation/retry proof; the small View-only ready test is not.
      final replacementPage = owner.loadOlder(
        'thread',
        generation: replacement.generation,
      );
      final second = transport.connections.last;
      await pumpClientFuture(
        tester,
        second.pageEntered(1),
        'replacement page admitted',
      );
      expect(second.pageCalls.single.before, 'old-cursor');
      expect(replacement.queries, isNot(same(oldScope)));
      expect(replacement.queries!.generation, replacement.generation);
      expect(replacement.queries!.isActive, isTrue);
      expect(
        client.budget.used(ResourceKind.pendingOperation),
        pendingBefore + 1,
      );
      second.pageCalls.single.reply.complete(
        ConversationPage(
          items: [
            componentText(
              'replacement-older',
              ordinal: 99,
              body: '新 scope 接纳的旧页',
            ),
          ],
          before: null,
          hasOlder: false,
        ),
      );
      await pumpClientFuture(
        tester,
        replacementPage,
        'replacement page settled',
      );
      await tester.pump();
      expect(owner.lease('thread'), same(replacement));
      expect(
        replacement
            .itemOf('replacement-older')!
            .fieldFor(const ThreadTextFieldView())!
            .text,
        '新 scope 接纳的旧页',
      );
      expect(replacement.hasOlder, isFalse);
      expect(owner.source.value!.isLoadingOlder, isFalse);
      expect(client.budget.used(ResourceKind.pendingOperation), pendingBefore);
      await _unmountTimeline(tester);
    }
  });

  // ---- R2 嵌套工具内部滚动：桌面平台语义下的承重证明 -----------------------------

  testWidgets(
    '嵌套工具内部滚动不会把主 Timeline 推进 History',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      final lease = leaseFor(
        tester,
        items: [
          toolItem(
            'tool-1',
            arguments: [
              for (var line = 0; line < 40; line++) 'line-$line: payload',
            ].join('\n'),
          ),
        ],
      );
      var enteredHistory = 0;
      await tester.pumpWidget(
        host(
          componentTimeline(
            threadId: 'thread',
            view: viewState(),
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () => enteredHistory += 1,
            onRetryConnection: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          StudioDriverKeys.timelineActivitySummary(
            lease.presentationFor('tool-1')!.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(StudioDriverKeys.timelineBlock('tool-1')),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      // The new feature's native group ListView owns the bounded tool viewport;
      // do not require the retired private code-block scroll widget.
      final groupView = find
          .ancestor(
            of: find.byKey(
              StudioDriverKeys.timelineActivitySummary(
                lease.presentationFor('tool-1')!.id,
              ),
            ),
            matching: find.byType(TimelineEntryView),
          )
          .first;
      final candidates = find.descendant(
        of: groupView,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
        ),
      );
      expect(candidates, findsWidgets);
      // 选出承载展开工具参数、真正可滚动的内部区域（有独立 extent）。
      Finder? inner;
      ScrollPosition? innerPosition;
      for (var index = 0; index < candidates.evaluate().length; index++) {
        final candidate = candidates.at(index);
        final position = tester.state<ScrollableState>(candidate).position;
        if (position.maxScrollExtent > 0) {
          inner = candidate;
          innerPosition = position;
          break;
        }
      }
      expect(inner, isNotNull, reason: '工具参数有自己的可滚动区域');
      final innerBefore = innerPosition!.pixels;

      // 真实用户输入作用在内部区域：鼠标滚轮落在嵌套视图内。
      final innerRect = tester.getRect(inner!);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(innerRect.center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      // 内层确实是滚动目标：自己的 position 真实前进，而不是只固定了外层。
      expect(
        innerPosition.pixels,
        isNot(innerBefore),
        reason: '嵌套工具内部必须真实滚动，而不是被吞掉',
      );
      expect(innerPosition.pixels, greaterThan(0));
      expect(enteredHistory, 0, reason: '嵌套工具内部滚动不得改主 Timeline 模式');
      expect(lease.scrollController.position.pixels, 0, reason: '外层几何不动');
    },
  );

  // ---- R3 无位移动作不得悬挂意图 --------------------------------------------------

  testWidgets('底端无位移的键盘/轨道动作不把之后的几何修正误判为用户意图', (tester) async {
    final lease = leaseFor(tester, items: longHistory());
    var enteredHistory = 0;
    var loads = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {
            loads += 1;
          },
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () => enteredHistory += 1,
          onRetryConnection: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final loadsAtStart = loads;
    // 已在底端：先点选最靠近底端的正文让键盘焦点进入，再按 PageDown
    // （反向列表底端无位移）。
    await tester.tap(
      find.byKey(StudioDriverKeys.timelineRow('item-119')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(lease.scrollController.position.pixels, 0);

    // 真实非用户的 depth-0 几何修正：只移动标准 position（`jumpTo` 不发
    // `UserScrollNotification`，Start/Update/End 都不带 dragDetails），等价于布局/内容
    // 扩展引起的像素修正，而不是读者滚动。无位移动作若留下悬挂意图，这里会被判成
    // “用户离开底端”。
    final position = lease.scrollController.position;
    expect(position.maxScrollExtent, greaterThan(200), reason: '确保存在可修正的几何');
    lease.scrollController.jumpTo(200);
    await tester.pumpAndSettle();
    expect(position.pixels, 200);
    expect(enteredHistory, 0, reason: '无位移动作不得把后续几何修正误判为用户意图');
    // 同一无位移动作之后再做一次反向修正也不得触发。
    lease.scrollController.jumpTo(0);
    await tester.pumpAndSettle();
    expect(enteredHistory, 0);

    // 端点轨道：底端 thumb 按下不翻页（探针确认几何），也不得留下意图。
    final scrollbar = find
        .byWidgetPredicate((widget) => widget is RawScrollbar)
        .first;
    final barRect = tester.getRect(scrollbar);
    final endpoint = Offset(barRect.right - 6, barRect.bottom - 4);
    // 自动淡出后先按真实鼠标悬停唤回滚动条，避免透明时点击穿透使本用例空跑。
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(endpoint));
    await tester.pumpAndSettle();
    final paintFinder = find.descendant(
      of: scrollbar,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is ScrollbarPainter,
      ),
    );
    final painter =
        tester.widget<CustomPaint>(paintFinder).foregroundPainter!
            as ScrollbarPainter;
    final box = tester.renderObject<RenderBox>(paintFinder);
    expect(
      painter.hitTestOnlyThumbInteractive(
        box.globalToLocal(endpoint),
        PointerDeviceKind.mouse,
      ),
      isTrue,
      reason: '端点动作必须命中可见 thumb，而不是穿透到正文',
    );
    await tester.tapAt(endpoint, kind: PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.removePointer());
    await tester.pumpAndSettle();
    expect(position.pixels, 0, reason: '底端轨道动作不产生位移');
    lease.scrollController.jumpTo(200);
    await tester.pumpAndSettle();
    expect(enteredHistory, 0, reason: '端点轨道动作不得留下悬挂意图');
    lease.scrollController.jumpTo(0);
    await tester.pumpAndSettle();

    // 随后改窗/内容增长引起的几何修正同样不得被当成用户离开底端。
    await tester.binding.setSurfaceSize(const Size(760, 640));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpAndSettle();
    expect(enteredHistory, 0, reason: '无位移动作不得留下悬挂意图');
    expect(loads, loadsAtStart, reason: '这些动作都不是分页意图');
  });

  // ---- R4 有内容时连接状态可见 + 重试不换代 ---------------------------------------

  testWidgets('重连/失败在已有内容时可见，重试不换代也不丢 History', (tester) async {
    final lease = leaseFor(tester, items: [textItem('only', ordinal: 1)]);
    var retries = 0;
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(mode: TimelineDisplayMode.history),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {
            retries += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.timelineConnectionNotice), findsNothing);

    // reconnecting：可见提示，内容仍在，无 retry。
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(
            mode: TimelineDisplayMode.history,
            connection: TimelineConnectionPhase.reconnecting,
          ),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {
            retries += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(StudioDriverKeys.timelineConnectionNotice),
      findsOneWidget,
    );
    final reconnectNotice = find.byKey(
      StudioDriverKeys.timelineConnectionNotice,
    );
    expect(
      find.descendant(of: reconnectNotice, matching: find.byType(Text)),
      findsWidgets,
      reason: '重连状态必须有实际可见提示，且已有内容保留',
    );
    expect(find.byKey(StudioDriverKeys.timelineRow('only')), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.timelineRetryConnection), findsNothing);

    // failed：可见错误 + retry；点 retry 只重试连接，代次与内容不变。
    await tester.pumpWidget(
      host(
        componentTimeline(
          threadId: 'thread',
          view: viewState(
            mode: TimelineDisplayMode.history,
            connection: TimelineConnectionPhase.failed,
            connectionError: StateError('synthetic connection failure'),
          ),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {
            retries += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(StudioDriverKeys.timelineConnectionNotice),
      findsOneWidget,
    );
    expect(
      find.textContaining('synthetic connection failure'),
      findsOneWidget,
      reason: '错误信息在已有 History 内容旁仍可见',
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineRetryConnection));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(lease.generation, 1, reason: '连接重试不得换代');
    expect(find.byKey(StudioDriverKeys.timelineRow('only')), findsOneWidget);
  });
}

// Feed input and synchronization only: the SDK validates the patch, and its
// existing owner observer applies it before this state waiter can complete.
Future<void> _emitTailAdditions(
  WidgetTester tester, {
  required TimelineSessionOwner owner,
  required TimelineDisplayLease lease,
  required _DetailConnection connection,
  required int from,
  required int to,
  required List<ConversationItem> items,
}) async {
  expect(lease.loadedCount, 32);
  expect(lease.appliedVersion, from);
  expect(items, hasLength(8));
  await tester.runAsync(() async {
    connection.emit(
      ConversationPatch(
        subscriptionId: connection.subscriptionId,
        from: from,
        to: to,
        priority: ConversationPriority.immediate,
        changes: [for (final item in items) ConversationAdd(item)],
      ),
    );
    await lease.content.state.waitFor(
      (state) =>
          lease.appliedVersion == to ||
          state is ChatReconnecting<ConversationContentFrame> ||
          state is ChatFailed<ConversationContentFrame> ||
          state is ChatClosed<ConversationContentFrame>,
    );
  });
  expect(owner.lease('thread'), same(lease));
  expect(lease.appliedVersion, to);
  expect(lease.loadedCount, 40);
  final frame = lease.content.lastDeliveredFrame;
  expect(frame, isA<ConversationPatchFrame>());
  final patch = (frame! as ConversationPatchFrame).patch;
  expect(patch.subscriptionId, connection.subscriptionId);
  expect(patch.from, from);
  expect(patch.to, to);
}

// The Client/owner are constructed by the widget test, while their first feed
// is started in runAsync below. Close must drive both zones; assertions stay
// outside the future being pumped so Flutter's guarded test APIs do not reenter.
Future<void> _closeDetailSession(
  WidgetTester tester,
  TimelineSessionOwner owner,
  AnyworkClient client,
  DateTime deadline,
) async {
  final ownerReport = await pumpClientFuture(
    tester,
    owner.close(deadline: deadline),
    'detail session owner close',
  );
  expect(ownerReport.unresolved, isEmpty);
  final clientReport = await pumpClientFuture(
    tester,
    client.close(deadline: deadline),
    'detail session client close',
  );
  expect(clientReport.unresolved, isEmpty);
}

Future<(AnyworkClient, TimelineSessionOwner, _DetailTransport)>
_openDetailSession(
  WidgetTester tester, {
  ConversationBaseline? baseline,
  _DetailTransport? backend,
}) async {
  final transport = backend ?? _DetailTransport(baseline: baseline);
  final client = AnyworkClient(transport: transport, clientId: 'd4a-viewer');
  final owner = TimelineSessionOwner(client: client);
  // Keep cleanup registered even if a behavior assertion fails with a gate open.
  // Settle backend gates, close the real route, then unmount and join its owners.
  addTearDown(() async {
    transport.releasePending();
    await _unmountTimeline(tester);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    await _closeDetailSession(tester, owner, client, deadline);
    expect(client.budget.usage, isEmpty);
  });
  await tester.runAsync(() async {
    client.selection.markOpened();
    client.threadDirectory.applyBaseline(
      ThreadDirectoryPage(threads: [_thread()], revision: 1),
      revision: 1,
    );
    client.workspace.selectThread('thread', projectId: 'project');
    client.conversations.setVisibleThread('thread');
    owner.select('thread');
    await client.conversations.session('thread').content.ready;
    await owner.source.waitFor(
      (state) =>
          state != null &&
          state.generation > 0 &&
          state.connection == TimelineConnectionPhase.ready,
    );
  });
  return (client, owner, transport);
}

StudioThread _thread() => StudioThread(
  id: 'thread',
  projectId: 'project',
  title: 'Thread',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/workspace/thread',
);

/// Typed baseline facts; no old ThreadItem shell or duplicate detail metadata.
ConversationBaseline _detailBaseline() => componentBaseline([
  componentText('big', ordinal: 1, body: '预览', totalBytes: 13),
]);

// Only the Driver scenario uses this feed baseline. Its last eight rows arrive
// through a real patch; a tail's initial frame is bounded to 32, not page's 100.
ConversationBaseline _longBaseline() => componentBaseline(
  [
    for (var index = 0; index < 32; index++)
      componentText('line-$index', ordinal: index, body: '第 $index 段静态正文' * 6),
  ],
  before: 'cursor',
  hasOlder: true,
);

ConversationBaseline _selectionBaseline() => componentBaseline([
  componentText('before', ordinal: 1, body: '前段canonical正文'),
  componentText('big', ordinal: 2, body: '截断前的preview', totalBytes: 40),
  componentText('after', ordinal: 3, body: '后段canonical正文'),
]);

ConversationBaseline _twoFieldBaseline() => componentBaseline([
  componentTool(
    'tool',
    arguments: '{"command":"cargo test"}',
    result: 'ok',
    totalArgumentsBytes: 80,
    totalResultBytes: 8,
  ),
]);

final class _UnusedTimelineAccountPorts extends UnusedAccountPorts {}

/// 真实附件字节通路的受控 backend：记录实际读取，返回可解码的 1×1 PNG。
final class _ImageTransport extends _DetailTransport {
  _ImageTransport({this.failures = 0, super.baseline});
  int failures;
  final List<String> reads = [];

  @override
  Future<Uint8List> readThreadAttachment(
    String threadId,
    String attachmentId,
  ) async {
    reads.add('$threadId:$attachmentId');
    if (failures > 0) {
      failures--;
      throw StateError('Fixture image temporarily unavailable');
    }
    return _onePixelPng;
  }
}

/// 1×1 透明 PNG：真实解码路径可用，避免用伪造字节触发解码错误。
final Uint8List _onePixelPng = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);

final class _DetailTransport implements StudioTransport {
  _DetailTransport({ConversationBaseline? baseline})
    : baseline = baseline ?? _detailBaseline();
  ConversationBaseline baseline;
  final List<_DetailConnection> connections = [];
  int openCalls = 0;
  Object? openFailure;
  int get queryAdmissions => connections.fold(
    0,
    (count, connection) =>
        count + connection.pageCalls.length + connection.detailCalls.length,
  );
  final List<Completer<_DetailConnection>> _opened = [];
  bool holdNextOpen = false;
  bool holdNextInitial = false;
  Completer<void>? _held;
  Completer<void>? _initialGate;

  Future<_DetailConnection> opened(int count) {
    while (_opened.length < count) {
      _opened.add(Completer<_DetailConnection>());
    }
    return _opened[count - 1].future;
  }

  @override
  Future<ConversationFeed> openConversationFeed(String threadId) async {
    openCalls++;
    final failure = openFailure;
    if (failure != null) throw failure;
    final gate = holdNextInitial ? (_initialGate = Completer<void>()) : null;
    holdNextInitial = false;
    final connection = _DetailConnection(
      baseline: baseline,
      serial: connections.length + 1,
      initialGate: gate,
    );
    connections.add(connection);
    opened(connections.length);
    _opened[connections.length - 1].complete(connection);
    if (holdNextOpen) {
      holdNextOpen = false;
      final held = _held = Completer<void>();
      await held.future;
    }
    return connection;
  }

  void releaseHeld() {
    _held!.complete();
    _held = null;
  }

  void releaseInitial() {
    _initialGate!.complete();
    _initialGate = null;
  }

  void releasePending() {
    final held = _held;
    if (held != null && !held.isCompleted) held.complete();
    final initial = _initialGate;
    if (initial != null && !initial.isCompleted) initial.complete();
    for (final connection in connections) {
      for (final call in connection.pageCalls) {
        if (!call.reply.isCompleted) {
          call.reply.completeError(const StaleConversationScope());
        }
      }
      for (final call in connection.detailCalls) {
        if (!call.reply.isCompleted) {
          call.reply.completeError(const StaleConversationScope());
        }
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused transport capability: ${invocation.memberName}',
  );
}

/// Backend gates only: all scope admission, attempts, reducers and permits are SDK-owned.
final class _DetailConnection extends ScriptedConversationFeed {
  _DetailConnection({
    required ConversationBaseline baseline,
    required int serial,
    this.initialGate,
  }) : super(
         threadId: 'thread',
         subscriptionId: 'detail-$serial',
         baseline: () => ConversationBaseline(
           subscriptionId: 'detail-$serial',
           version: baseline.version,
           items: baseline.items,
           before: baseline.before,
           hasOlder: baseline.hasOlder,
         ),
         state: () => ThreadSnapshotFrame(
           workspace: ThreadWorkspace(
             thread: _thread(),
             revision: 1,
             interactions: const [],
             runtime: const ThreadRuntimeView(
               modelId: 'fixture',
               contextTokens: 0,
               contextWindow: 100,
               totalTokens: 0,
               costLabel: '',
               activeSkills: [],
               activeMcpServers: [],
               activeLspServers: [],
             ),
           ),
         ),
       );
  final Completer<void>? initialGate;
  final List<({String? before, int? limit, Completer<ConversationPage> reply})>
  pageCalls = [];
  final List<Completer<void>> _pageAdmissions = [];
  Future<void> pageEntered(int count) {
    while (_pageAdmissions.length < count) {
      _pageAdmissions.add(Completer<void>());
    }
    return _pageAdmissions[count - 1].future;
  }

  final List<
    ({
      String itemId,
      ConversationDetailQuery query,
      Completer<ConversationDetailChunk> reply,
    })
  >
  detailCalls = [];

  @override
  Stream<ConversationFrame> get events async* {
    final source = super.events;
    if (initialGate != null) await initialGate!.future;
    yield* source;
  }

  @override
  Future<ConversationPage> page({String? before, int? limit}) {
    final reply = Completer<ConversationPage>();
    pageCalls.add((before: before, limit: limit, reply: reply));
    pageEntered(pageCalls.length);
    _pageAdmissions[pageCalls.length - 1].complete();
    return reply.future;
  }

  @override
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) {
    final reply = Completer<ConversationDetailChunk>();
    detailCalls.add((itemId: itemId, query: query, reply: reply));
    return reply.future;
  }

  @override
  Future<void> close() async {
    requestClose();
    // A stopped producer cannot forget already accepted backend reads.
    for (final call in pageCalls) {
      try {
        await call.reply.future;
      } catch (_) {
        /* delivered to the SDK caller */
      }
    }
    for (final call in detailCalls) {
      try {
        await call.reply.future;
      } catch (_) {
        /* delivered to the SDK caller */
      }
    }
    await super.close();
  }
}

ConversationDetailChunk _chunk({
  String? continuation,
  String? text,
  int totalBytes = 13,
}) => ConversationDetailChunk(
  itemId: 'big',
  field: const ThreadTextFieldView(),
  revision: 1,
  text: text ?? (continuation == null ? '甲🐱\n乙\r\n' : '甲🐱\n'),
  totalBytes: totalBytes,
  continuation: continuation,
);

Finder _imageConnector(String toolId) => find.byWidgetPredicate(
  (widget) =>
      widget is TimelineImageConnector &&
      widget.message.id == '$toolId:attachment:att-shared',
);

Finder _imageThumbnail(String toolId) => find.descendant(
  of: _imageConnector(toolId),
  matching: find.byType(FlyerChatImageMessage),
);

Finder _imageRetry(String toolId) => find.descendant(
  of: _imageConnector(toolId),
  matching: find.byType(TextButton),
);

/// Close the real route/owner before removing its Navigator, so disposal cannot
/// turn an unjoined viewer into a false resource-release acknowledgement.
Future<void> _unmountTimeline(WidgetTester tester) async {
  final close = find.byKey(StudioDriverKeys.timelineDetailClose);
  if (close.evaluate().isNotEmpty) {
    await tester.tap(close);
    await _pumpFrames(tester, frames: 16);
    await pumpClientUntil(
      tester,
      () =>
          find.byKey(StudioDriverKeys.timelineDetailDialog).evaluate().isEmpty,
      'detail route close before unmount',
    );
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
  }
  await tester.pumpWidget(const SizedBox.shrink());
}

/// 只推进有限帧：查看器读取中可能出现进度指示，`pumpAndSettle` 会等不到静止。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
