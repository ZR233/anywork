// Opt-in 组件行为证明（默认门禁不运行）。
//
// 唯一列表路线是公开 `Chat` + 原生 `ChatAnimatedListReversed` + stock
// `InMemoryChatController`；这里证明生产 `TimelineView` 的真实绑定、真实用户意图才进入
// History、视口自动补齐/重试、以及全文查看器只读当前 lease 的详情引用。
// 算法层覆盖由 test/client/timeline_display_lease_test.dart 与
// timeline_session_owner_test.dart 承担，不在这里重复。
import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/shared/studio_driver_key_values.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/timeline/timeline_activity_row.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/shared/studio_chrome.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../client/support/unused_account_ports.dart';

void main() {
  final timestamp = DateTime.utc(2026, 1, 1);

  StudioTimelineItem textItem(
    String id, {
    required int ordinal,
    String body = '正文',
    bool terminal = true,
    int omitted = 0,
    List<StudioTimelineDetailRef> details = const [],
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: ordinal,
      revision: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
      bodyOmittedUnits: omitted,
      executionTerminal: terminal,
      saved: true,
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: body,
        attachments: const [],
        lifecycle: terminal
            ? CompletedThreadContentView(timestamp)
            : const StreamingThreadContentView(),
      ),
    ),
    saved: true,
    lifecycle: terminal
        ? StudioTimelineLifecycle.terminal
        : StudioTimelineLifecycle.streaming,
    omittedBytes: omitted,
    details: details,
  );

  StudioTimelineItem toolItem(
    String id, {
    int ordinal = 1,
    String name = 'exec_command',
    required String arguments,
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: ordinal,
      revision: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
      saved: true,
      executionTerminal: true,
      state: ThreadToolItemStateView(
        invocation: ThreadToolInvocationView(
          toolCallId: id,
          callId: id,
          name: name,
          arguments: arguments,
        ),
        lifecycle: SucceededThreadToolView(
          timestamp,
          ThreadToolOutputView(
            result: 'ok',
            attachments: const [],
            outputArtifacts: const [],
          ),
        ),
      ),
    ),
    saved: true,
    lifecycle: StudioTimelineLifecycle.terminal,
    omittedBytes: 0,
    details: const [],
  );

  StudioTimelineItem imageToolItem(
    String id, {
    required int ordinal,
    String attachmentId = 'att-shared',
    String name = 'view_image',
    String result = 'ok',
    int revision = 1,
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: ordinal,
      revision: revision,
      createdAt: timestamp,
      updatedAt: timestamp,
      saved: true,
      executionTerminal: true,
      state: ThreadToolItemStateView(
        invocation: ThreadToolInvocationView(
          toolCallId: id,
          callId: id,
          name: name,
          arguments: '{"path":"/workspace/images/shot.png"}',
        ),
        lifecycle: SucceededThreadToolView(
          timestamp,
          ThreadToolOutputView(
            result: result,
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
            outputArtifacts: const [],
          ),
        ),
      ),
    ),
    saved: true,
    lifecycle: StudioTimelineLifecycle.terminal,
    omittedBytes: 0,
    details: const [],
  );

  TimelineDisplayLease leaseFor({
    required List<StudioTimelineItem> items,
    String? before,
    bool hasOlder = false,
  }) {
    final lease = TimelineDisplayLease(
      threadId: 'thread',
      generation: 1,
      openQueries: (_) => null,
    );
    lease.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'test',
        version: 0,
        items: items,
        before: before,
        hasOlder: hasOlder,
      ),
    );
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
  }) => MediaQuery(
    data: MediaQueryData(size: size),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: ProviderScope(
        overrides: [
          if (client != null) anyworkClientProvider.overrideWithValue(client),
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
    final lease = leaseFor(items: [textItem('item-a', ordinal: 1)]);
    await tester.pumpWidget(
      host(
        TimelineView(
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
    expect(find.byKey(StudioDriverKeys.timelineRow('item-a')), findsOneWidget);
    expect(lease.isMounted, isTrue);

    // 真实子树卸载后 lease 才能释放 controller。
    await tester.pumpWidget(host(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(lease.isMounted, isFalse);
    await lease.retire();
    expect(lease.isReleased, isTrue);

    // 已释放的代次明确拒绝再次挂载，而不是把已销毁 controller 交给子树。
    expect(lease.bind, throwsStateError);
  });

  testWidgets('只有真实用户滚动离开底端才进入 History，改窗不误判', (tester) async {
    final items = [
      for (var index = 0; index < 40; index++)
        textItem('item-$index', ordinal: index, body: '第 $index 段正文' * 4),
    ];
    final lease = leaseFor(items: items, before: 'cursor', hasOlder: true);
    var enteredHistory = 0;
    await tester.pumpWidget(
      host(
        TimelineView(
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
    final lease = leaseFor(items: [textItem('only', ordinal: 1)]);
    var loads = 0;
    var retries = 0;
    final page = Completer<void>();
    await tester.pumpWidget(
      host(
        TimelineView(
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
        TimelineView(
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
    final lease = leaseFor(items: []);
    await tester.pumpWidget(
      host(
        TimelineView(
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
      StudioTimelinePatch(
        subscriptionId: 'test',
        from: 0,
        to: 1,
        changes: [StudioTimelineAdd(textItem('first-live', ordinal: 1))],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(StudioDriverKeys.timelineRow('first-live')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('短内容补页被连接切换取消后，同游标可重新自动补齐', (tester) async {
    final lease = leaseFor(
      items: [textItem('only', ordinal: 1)],
      before: 'cursor',
      hasOlder: true,
    );
    var loads = 0;
    final firstPage = Completer<void>();
    Future<void> render(TimelineSessionViewState view) async {
      await tester.pumpWidget(
        host(
          TimelineView(
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
    // A fast retirement can finish between two frames: loading/opening are
    // canonical transitions, but need not become separate rendered widgets.
    firstPage.complete();
    await tester.pump();
    await render(ready.copyWith());
    await tester.pumpAndSettle();
    expect(loads, 2, reason: '取消不应永久封住同一页的视口需求');
  });

  testWidgets('窗口扩大后按实际视口补页，resize 不改变阅读模式', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lease = leaseFor(
      items: [for (var i = 0; i < 12; i++) textItem('row-$i', ordinal: i)],
      before: 'cursor',
      hasOlder: true,
    );
    var loads = 0;
    var histories = 0;
    final page = Completer<void>();
    await tester.pumpWidget(
      host(
        TimelineView(
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
      items: [toolItem('new-tool', ordinal: 100, arguments: '{}')],
      before: 'cursor',
      hasOlder: true,
    );
    var view = viewState(hasOlder: true);
    var loads = 0;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, update) => TimelineView(
            threadId: 'thread',
            view: view,
            lease: lease,
            onLoadOlder: () async {
              loads++;
              final page = loads == 1
                  ? StudioTimelinePage(
                      items: [
                        toolItem('older-tool', ordinal: 99, arguments: '{}'),
                      ],
                      before: 'next',
                      hasOlder: true,
                    )
                  : StudioTimelinePage(
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
    final lease = leaseFor(items: [textItem('only', ordinal: 1)]);
    var returns = 0;
    await tester.pumpWidget(
      host(
        TimelineView(
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
    expect(find.byKey(StudioDriverKeys.timelineNewOutput), findsOneWidget);
    await tester.tap(find.byKey(StudioDriverKeys.timelineReturnLive));
    await tester.pumpAndSettle();
    expect(returns, 1);

    await tester.pumpWidget(
      host(
        TimelineView(
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
      items: [
        textItem(
          'big',
          ordinal: 1,
          body: '预览正文',
          omitted: 120,
          details: const [
            StudioTimelineDetailRef(
              field: ThreadTextFieldView(),
              revision: 1,
              totalBytes: 126,
              previewBytes: 6,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      host(
        TimelineView(
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

  List<StudioTimelineItem> longHistory({int count = 120}) => [
    for (var index = 0; index < count; index++)
      textItem('item-$index', ordinal: index, body: '第 $index 段正文' * 4),
  ];

  testWidgets('键盘 PageUp 是真实阅读意图，改窗与流式增长不是', (tester) async {
    final lease = leaseFor(
      items: longHistory(),
      before: 'cursor',
      hasOlder: true,
    );
    var enteredHistory = 0;
    var olderLoads = 0;
    await tester.pumpWidget(
      host(
        TimelineView(
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
      items: longHistory(),
      before: 'cursor',
      hasOlder: true,
    );
    var enteredHistory = 0;
    await tester.pumpWidget(
      host(
        TimelineView(
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
      items: [
        textItem(
          'big',
          ordinal: 1,
          body: '预览',
          omitted: 40,
          details: const [
            StudioTimelineDetailRef(
              field: ThreadTextFieldView(),
              revision: 1,
              totalBytes: 46,
              previewBytes: 6,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      host(
        TimelineView(
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
      final transport = _DetailTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'd4a-viewer',
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      addTearDown(() => client.close(deadline: deadline));
      late final TimelineSessionOwner owner;
      late final TimelineDisplayLease lease;
      late final _DetailConnection first;
      // 真实异步（连接首帧/代次建立）必须在 runAsync 中等待：fake-async 不会推进它。
      await tester.runAsync(() async {
        client.selection.markOpened();
        client.threadDirectory.applyBaseline(
          ThreadDirectoryPage(threads: [_thread()], revision: 1),
          revision: 1,
        );
        owner = TimelineSessionOwner(client: client);
        addTearDown(() => owner.close(deadline: deadline));
        client.workspace.selectThread('thread', projectId: 'project');
        await owner.source.waitFor((state) => state?.generation != 0);
      });
      expect(owner.source.value?.generation, isNot(0));
      lease = owner.lease('thread')!;
      first = transport.connections.single;

      await tester.pumpWidget(
        host(
          TimelineView(
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
      expect(tester.widget<SelectableText>(text).data, 'AAAAAA');
      expect(
        tester
            .widget<IconButton>(find.byKey(StudioDriverKeys.timelineDetailCopy))
            .onPressed,
        isNull,
        reason: '未读完整时不允许“复制全文”',
      );

      // 第二块在 attempt 更替后失效 → 可见可重试错误。
      first.detailCalls[1].reply.completeError(const StaleTimelineScope());
      await _pumpFrames(tester);
      expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsOneWidget);
      expect(find.textContaining('scope has been retired'), findsOneWidget);
      expect(tester.widget<SelectableText>(text).data, 'AAAAAA');

      // 连接 attempt 更替（新订阅尚未建立）：旧 scope 失活。
      final session = client.existingSession('thread')!;
      transport.holdNextOpen = true;
      await tester.runAsync(() async {
        session.timeline.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 20));
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
      expect(tester.widget<SelectableText>(text).data, 'AAAAAA');

      // 新基线到达 → 新代次；生产 shell 用新 lease 重建列表，旧代次真实卸载后退役。
      await tester.runAsync(() async {
        transport.releaseHeld();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await _pumpFrames(tester);
      final nextLease = owner.lease('thread')!;
      expect(nextLease.generation, greaterThan(lease.generation));
      await tester.pumpWidget(
        host(
          TimelineView(
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
      // 旧代次真实退役并释放（owner 已 retire；这里等待真实 released ACK）。
      await tester.runAsync(() async {
        await lease.retire();
        await lease.released;
      });
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

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester);
      await tester.runAsync(() async {
        await owner.close(deadline: deadline);
        await client.close(deadline: deadline);
      });
      await _pumpFrames(tester, frames: 2);
    });
  });

  testWidgets('关闭在途读取：停新块、await 自己已受理读取后才离开', (tester) async {
    final (client, owner, transport) = await _openDetailSession(tester);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final lease = owner.lease('thread')!;
    final first = transport.connections.single;

    await tester.pumpWidget(
      host(
        TimelineView(
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

    // 读取仍在途：点关闭必须先等它真的退出，不能同步 pop 出假 ACK。
    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
    await _pumpFrames(tester);
    expect(
      find.byKey(StudioDriverKeys.timelineDetailDialog),
      findsOneWidget,
      reason: '已受理读取未退出前不得关闭',
    );
    expect(first.detailCalls, hasLength(1), reason: '停止后续块');

    // 底层读取退出后，关闭完成。
    first.detailCalls.single.reply.complete(_chunk(continuation: 'c1'));
    // 退出等待结束、route 退场动画走完后查看器才真正离开树。
    await _pumpFrames(tester, frames: 16);
    expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);
    expect(first.detailCalls, hasLength(1), reason: '关闭后不再发新块');

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester);
    await tester.runAsync(() async {
      await owner.close(deadline: deadline);
      await client.close(deadline: deadline);
    });
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
        TimelineView(
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
    first.detailCalls[1].reply.completeError(const StaleTimelineScope());
    await _pumpFrames(tester);
    expect(find.byKey(StudioDriverKeys.timelineDetailRetry), findsOneWidget);

    // 新连接已打开但首帧仍挂起：旧 lease 保持活跃，新 attempt 的 scope 已可用。
    transport.holdNextInitial = true;
    final session = client.existingSession('thread')!;
    await tester.runAsync(() async {
      session.timeline.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await _pumpFrames(tester);
    expect(transport.connections, hasLength(2));

    await tester.tap(find.byKey(StudioDriverKeys.timelineDetailRetry));
    await _pumpFrames(tester);
    final second = transport.connections[1];
    expect(second.detailCalls, hasLength(1), reason: '重试走新 attempt 的 scope');
    expect(second.detailCalls.single.query.continuation, 'c1');
    expect(second.detailCalls.single.query.revision, 1);
    second.detailCalls.single.reply.complete(_chunk(text: 'BBBBBB'));
    await _pumpFrames(tester);

    final text = find.byKey(StudioDriverKeys.timelineDetailText);
    expect(tester.widget<SelectableText>(text).data, 'AAAAAABBBBBB');
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
    expect(copied, 'AAAAAABBBBBB', reason: '复制内容必须等于逐块拼接的真实正文');
    expect(lease.generation, generation, reason: '同 lease 重试不换代');
    expect(first.detailCalls, hasLength(2), reason: '旧 attempt 不再收块');

    transport.releaseInitial();
    await _pumpFrames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester);
    await tester.runAsync(() async {
      await owner.close(deadline: deadline);
      await client.close(deadline: deadline);
    });
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
          TimelineView(
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
        'AAAAAA',
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

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester);
      await tester.runAsync(() async {
        await owner.close(deadline: deadline);
        await client.close(deadline: deadline);
      });
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
          TimelineView(
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
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel(hints.single), findsWidgets);
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

      // 真实点击仍打开查看器，并在读完当前块后正常关闭。
      await tester.tap(open);
      await _pumpFrames(tester);
      expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsOneWidget);
      connection.detailCalls.single.reply.complete(_chunk());
      await _pumpFrames(tester);
      await tester.tap(find.byKey(StudioDriverKeys.timelineDetailClose));
      await _pumpFrames(tester, frames: 16);
      expect(find.byKey(StudioDriverKeys.timelineDetailDialog), findsNothing);

      // 平台剪贴板：只截获 Flutter 自己经 `_copy()` 写出的 `Clipboard.setData`，
      // 测试不构造、也不自行写入任何复制字符串。
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

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester);
      await tester.runAsync(() async {
        await owner.close(deadline: deadline);
        await client.close(deadline: deadline);
      });
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
        TimelineView(
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
      find
          .ancestor(
            of: find.byKey(StudioDriverKeys.timelineActivitySummary(group.id)),
            matching: find.byType(ListTile),
          )
          .first,
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
    final l10n = AppLocalizations.of(tester.element(notice));
    expect(
      tester.widgetList<TimelineActivityRow>(rows).map((row) => row.label),
      [l10n.timelineToolArguments, l10n.timelineToolOutput],
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

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester);
    await tester.runAsync(() async {
      await owner.close(deadline: deadline);
      await client.close(deadline: deadline);
    });
    await _pumpFrames(tester, frames: 2);
  });

  // ---- 只读滚动诊断：查询时现场读取当前 controller，不复用通知快照 -----------------

  testWidgets('滚动诊断每次请求读当前 position：拖动中 true，抬手归 false 后立即 false', (
    tester,
  ) async {
    final (client, owner, _) = await _openDetailSession(
      tester,
      baseline: _longBaseline(),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final lease = owner.lease('thread')!;
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
      await tester.runAsync(() async {
        final report = await accounts.close(deadline: deadline);
        expect(report.unresolved, isEmpty);
      });
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
        TimelineView(
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
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester);
    await tester.runAsync(() async {
      await lease.retire();
      await lease.released;
    });
    expect(
      StudioDriverState.readFacts().timelineScroll,
      isNull,
      reason: '退役/无挂载代次不得继续报告上一代几何',
    );
    await tester.runAsync(() async {
      await owner.close(deadline: deadline);
      final accountReport = await accounts.close(deadline: deadline);
      expect(accountReport.unresolved, isEmpty);
      await client.close(deadline: deadline);
    });
    await _pumpFrames(tester, frames: 2);
  });

  testWidgets('单段思考展开后展示组内概要行，仅含概要时不提供二次展开，含内容时可二次展开', (tester) async {
    for (final (summary, content) in [
      (['**Summary** `evidence`'], ['Full reasoning evidence']),
      (['**Summary** `evidence`'], <String>[]),
      (<String>[], ['Full reasoning evidence']),
      (<String>['  '], <String>[]),
    ]) {
      final lease = leaseFor(
        items: [
          StudioTimelineItem(
            item: ThreadItemView(
              id: 'thinking',
              threadId: 'thread',
              turnId: 'turn',
              ordinal: 1,
              revision: 1,
              createdAt: timestamp,
              updatedAt: timestamp.add(const Duration(seconds: 3)),
              saved: true,
              state: ThreadThinkingItemStateView(
                summary: summary,
                content: content,
                lifecycle: CompletedThreadContentView(
                  timestamp.add(const Duration(seconds: 3)),
                ),
              ),
            ),
            saved: true,
            lifecycle: StudioTimelineLifecycle.terminal,
            omittedBytes: 0,
            details: const [],
          ),
        ],
      );
      await tester.pumpWidget(
        host(
          TimelineView(
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
      final topSummaryFinder = find.byKey(
        StudioDriverKeys.timelineActivitySummary(group.id),
      );
      final topRow = tester.widget<TimelineActivityRow>(topSummaryFinder);
      expect(topRow.icon, isNull, reason: '顶层总折叠行去掉左侧图标');
      expect(topRow.label, 'Worked for 3s', reason: '顶层总折叠行显示整组工作时长');

      await tester.tap(
        find
            .ancestor(of: topSummaryFinder, matching: find.byType(ListTile))
            .first,
      );
      await tester.pumpAndSettle();
      final hasSummary = summary.any((chunk) => chunk.trim().isNotEmpty);
      final hasContent = content.any((chunk) => chunk.trim().isNotEmpty);
      final innerSummaryFinder = find.byKey(
        StudioDriverKeys.timelineActivitySummary('thinking'),
      );
      expect(innerSummaryFinder, findsOneWidget);
      final innerRow = tester.widget<TimelineActivityRow>(innerSummaryFinder);
      expect(innerRow.expandable, hasContent, reason: '仅含概要而无正文的思考行不提供二次展开能力');
      expect(
        find.byKey(const ValueKey('timeline-thinking-summary-thinking')),
        hasSummary ? findsOneWidget : findsNothing,
      );
      if (hasContent) {
        await tester.tap(
          find
              .ancestor(of: innerSummaryFinder, matching: find.byType(ListTile))
              .first,
        );
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const ValueKey('timeline-thinking-content-thinking')),
        hasContent ? findsOneWidget : findsNothing,
      );
      expect(find.text('No reasoning text was provided.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await lease.retire();
    }
  });

  testWidgets(
    '独立 TimelineActivityGroupBlock 仅接受自有 sealed 消息，支持持续追加、上层转换与分组边界报错',
    (tester) async {
      final controller = TimelineActivityGroupController(
        id: 'standalone-group',
      );
      addTearDown(controller.dispose);

      // 1. 通过组件自有的 sealed TimelineThinkingGroupMessage 追加首条仅含概要的思考消息。
      controller.addOrThrow(
        TimelineThinkingGroupMessage(
          id: 'think-only-summary',
          threadId: 'thread',
          turnId: 'turn-1',
          order: 1,
          createdAt: timestamp,
          completedAt: timestamp.add(const Duration(seconds: 2)),
          summary: '正在设计方案 `step-1`',
        ),
      );

      await tester.pumpWidget(
        host(
          Scaffold(body: TimelineActivityGroupBlock(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      Finder topSummary() =>
          find.byKey(StudioDriverKeys.timelineActivitySummary(controller.id));
      TimelineActivityRow readTopRow() =>
          tester.widget<TimelineActivityRow>(topSummary());

      expect(readTopRow().icon, isNull);
      expect(readTopRow().label, 'Worked for 2s');

      // 2. 上层调用方通过 TimelineActivityGroupAdapter 将 StudioTimelineItem 转换为组件自有消息并追加。
      final completedToolItem = StudioTimelineItem(
        item: ThreadItemView(
          id: 'tool-1',
          threadId: 'thread',
          turnId: 'turn-1',
          ordinal: 2,
          revision: 1,
          createdAt: timestamp.add(const Duration(seconds: 2)),
          updatedAt: timestamp.add(const Duration(seconds: 8)),
          saved: true,
          state: ThreadToolItemStateView(
            invocation: const ThreadToolInvocationView(
              toolCallId: 'tool-1',
              name: 'read_file',
              arguments: '{"path":"/workspace/README.md"}',
            ),
            lifecycle: SucceededThreadToolView(
              timestamp.add(const Duration(seconds: 8)),
              const ThreadToolOutputView(
                result: 'done',
                attachments: [],
                outputArtifacts: [],
              ),
            ),
          ),
        ),
        saved: true,
        lifecycle: StudioTimelineLifecycle.terminal,
        omittedBytes: 0,
        details: const [],
      );
      final convertedTool = TimelineActivityGroupAdapter.convertItem(
        completedToolItem,
      );
      expect(convertedTool, isA<TimelineActivityConverted>());
      final addToolResult = controller.tryAdd(
        (convertedTool as TimelineActivityConverted).message,
      );
      expect(addToolResult, isA<TimelineGroupAddAccepted>());
      await tester.pumpAndSettle();
      expect(readTopRow().icon, isNull);
      expect(readTopRow().label, 'Worked for 8s · 1 tools');

      // 3. 展开工作组，验证仅含概要的思考消息不提供二次展开（expandable: false）。
      await tester.tap(
        find.ancestor(of: topSummary(), matching: find.byType(ListTile)).first,
      );
      await tester.pumpAndSettle();
      final innerThinkingSummary = find.byKey(
        StudioDriverKeys.timelineActivitySummary('think-only-summary'),
      );
      expect(innerThinkingSummary, findsOneWidget);
      expect(
        tester.widget<TimelineActivityRow>(innerThinkingSummary).expandable,
        isFalse,
      );
      expect(
        find.byKey(
          const ValueKey('timeline-thinking-summary-think-only-summary'),
        ),
        findsOneWidget,
      );

      // 4. 当向工作组追加跨轮次 / 跨线程 / 回退状态不一致的 sealed 消息时，返回 TimelineGroupBoundaryError。
      final turnRejected = controller.tryAdd(
        TimelineThinkingGroupMessage(
          id: 'think-turn-2',
          threadId: 'thread',
          turnId: 'turn-2',
          order: 3,
          createdAt: timestamp.add(const Duration(seconds: 9)),
          completedAt: timestamp.add(const Duration(seconds: 10)),
          summary: 'Next turn',
        ),
      );
      expect(turnRejected, isA<TimelineGroupAddRejected>());
      expect(
        (turnRejected as TimelineGroupAddRejected).error.reason,
        TimelineGroupBoundaryReason.turnMismatch,
      );

      final threadRejected = controller.tryAdd(
        TimelineThinkingGroupMessage(
          id: 'think-thread-2',
          threadId: 'thread-2',
          turnId: 'turn-1',
          order: 3,
          createdAt: timestamp.add(const Duration(seconds: 9)),
          completedAt: timestamp.add(const Duration(seconds: 10)),
          summary: 'Other thread',
        ),
      );
      expect(
        (threadRejected as TimelineGroupAddRejected).error.reason,
        TimelineGroupBoundaryReason.threadMismatch,
      );

      final rolledBackRejected = controller.tryAdd(
        TimelineThinkingGroupMessage(
          id: 'think-rolled-back',
          threadId: 'thread',
          turnId: 'turn-1',
          order: 3,
          rolledBack: true,
          createdAt: timestamp.add(const Duration(seconds: 9)),
          completedAt: timestamp.add(const Duration(seconds: 10)),
          summary: 'Rolled back',
        ),
      );
      expect(
        (rolledBackRejected as TimelineGroupAddRejected).error.reason,
        TimelineGroupBoundaryReason.contextDispositionMismatch,
      );

      // 5. 上层转换器对组外类型（助手正文、未完成项等）直接拒绝转换。
      final assistantItem = StudioTimelineItem(
        item: ThreadItemView(
          id: 'assistant-1',
          threadId: 'thread',
          turnId: 'turn-1',
          ordinal: 4,
          revision: 1,
          createdAt: timestamp,
          updatedAt: timestamp,
          saved: true,
          state: ThreadTextItemStateView(
            channel: ThreadTextChannel.finalAnswer,
            text: 'Answer',
            attachments: const [],
            lifecycle: CompletedThreadContentView(timestamp),
          ),
        ),
        saved: true,
        lifecycle: StudioTimelineLifecycle.terminal,
        omittedBytes: 0,
        details: const [],
      );
      final rejectedConversion = TimelineActivityGroupAdapter.convertItem(
        assistantItem,
      );
      expect(rejectedConversion, isA<TimelineActivityConversionRejected>());
      expect(
        (rejectedConversion as TimelineActivityConversionRejected).reason,
        TimelineActivityRejectionReason.nonActivityKind,
      );
    },
  );

  testWidgets('读取文件以状态和文件名单行展示，详情只在点击后构建', (tester) async {
    final lease = leaseFor(
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
        TimelineView(
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
      find
          .ancestor(
            of: find.byKey(
              StudioDriverKeys.timelineActivitySummary(
                lease.presentationFor('read-1')!.id,
              ),
            ),
            matching: find.byType(ListTile),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('timeline-tool-details:read-1'));
    expect(tester.getSize(row).height, lessThanOrEqualTo(40));
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(
      find.textContaining('target.dart', findRichText: true),
      findsOneWidget,
    );
    expect(find.byTooltip('/workspace/src/target.dart'), findsOneWidget);
    expect(find.byType(StudioCodeBlock), findsNothing);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(StudioCodeBlock), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await lease.retire();
  });

  // ---- S1 图片增量：默认折叠、用户展开语义与引用释放 --------------------------------

  testWidgets('图片组默认折叠只按需读取，同 ID 更新保持用户展开/折叠，引用释放可判别', (tester) async {
    final transport = _ImageTransport(failures: 1);
    final client = AnyworkClient(transport: transport, clientId: 'd4a-images');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    addTearDown(() => client.close(deadline: deadline));
    await tester.runAsync(() async => client.selection.markOpened());

    final lease = leaseFor(
      items: [
        imageToolItem('call-a', ordinal: 1, name: 'mcp__plot'),
        imageToolItem('call-b', ordinal: 2),
      ],
    );
    final entryA = StudioDriverKeys.toolImageEntryId('call-a', 'att-shared');
    final entryB = StudioDriverKeys.toolImageEntryId('call-b', 'att-shared');
    Finder toggleFor(String id) => find
        .ancestor(
          of: find.byKey(
            StudioDriverKeys.timelineActivitySummary(
              lease.presentationFor(id)!.id,
            ),
          ),
          matching: find.byType(ListTile),
        )
        .first;
    var version = 0;
    void patch(List<StudioTimelineChange> changes) {
      expect(
        lease.applyPatch(
          StudioTimelinePatch(
            subscriptionId: 'test',
            from: version,
            to: ++version,
            priority: StudioTimelinePriority.immediate,
            changes: changes,
          ),
        ),
        isTrue,
      );
    }

    await tester.pumpWidget(
      host(
        TimelineView(
          threadId: 'thread',
          view: viewState(),
          lease: lease,
          onLoadOlder: () async {},
          onRetryOlder: () async {},
          onReturnLive: () async {},
          onEnterHistory: () {},
          onRetryConnection: () async {},
        ),
        client: client,
      ),
    );
    await tester.pumpAndSettle();

    // 默认折叠：没有缩略图，也没有任何字节读取（生产不再自动展开）。
    expect(toggleFor('call-a'), findsOneWidget);
    expect(
      find.byKey(StudioDriverKeys.viewImageThumbnail(entryA)),
      findsNothing,
    );
    expect(
      find.byKey(StudioDriverKeys.viewImageThumbnail(entryB)),
      findsNothing,
    );
    expect(transport.reads, isEmpty, reason: '折叠状态不得读取原图');

    // 连续调用共用展开意图，两个缩略图复用同一附件读取。
    await tester.tap(toggleFor('call-a'));
    await _pumpFrames(tester);
    await tester.pumpAndSettle();
    expect(transport.reads, ['thread:att-shared']);
    expect(
      find.byKey(StudioDriverKeys.timelineImageRetry(entryA)),
      findsOneWidget,
    );
    expect(
      find.byKey(StudioDriverKeys.timelineImageRetry(entryB)),
      findsOneWidget,
    );
    // Each call keeps its own retry identity; both share the retried byte read.
    await tester.tap(find.byKey(StudioDriverKeys.timelineImageRetry(entryA)));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(StudioDriverKeys.timelineImageRetry(entryB)));
    await _pumpFrames(tester);
    await tester.pumpAndSettle();
    expect(
      find.byKey(StudioDriverKeys.viewImageThumbnail(entryA)),
      findsOneWidget,
    );
    expect(
      find.byKey(StudioDriverKeys.viewImageThumbnail(entryB)),
      findsOneWidget,
    );
    expect(transport.reads, ['thread:att-shared', 'thread:att-shared']);
    expect(
      find.byKey(const ValueKey('timeline-tool-details:call-a')),
      findsNothing,
    );
    expect(find.text('/workspace/images/shot.png'), findsNothing);
    await tester.tap(find.byKey(StudioDriverKeys.viewImageThumbnail(entryA)));
    await tester.pumpAndSettle();
    expect(find.text('/workspace/images/shot.png'), findsOneWidget);
    expect(find.text('shot.png'), findsOneWidget);
    // Tools may return text alongside images (including MCP). Keep that result
    // available inside the viewer without adding tool rows below thumbnails.
    await tester.tap(find.byKey(ValueKey('timeline-image-details-$entryA')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('timeline-tool-details:call-a')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('timeline-image-details-close')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StudioDriverKeys.timelineImageClose));
    await tester.pumpAndSettle();

    // 同 canonicalID 的普通内容更新：保持用户已展开，且共享缓存不重读。
    patch([
      StudioTimelineAdd(
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
      find.byKey(StudioDriverKeys.viewImageThumbnail(entryA)),
      findsOneWidget,
      reason: '用户展开后同 ID 更新保持展开',
    );
    expect(transport.reads, hasLength(2), reason: '同附件不得重读');

    // 用户主动折叠后再更新：不得自动展开。
    await tester.tap(toggleFor('call-a'));
    await _pumpFrames(tester);
    await tester.pumpAndSettle();
    expect(
      find.byKey(StudioDriverKeys.viewImageThumbnail(entryA)),
      findsNothing,
    );
    patch([
      StudioTimelineAdd(
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
      find.byKey(StudioDriverKeys.viewImageThumbnail(entryA)),
      findsNothing,
      reason: '用户折叠后同 ID 更新不得自动展开',
    );
    expect(transport.reads, hasLength(2));

    // 共享引用：移除 call-a 后 call-b 仍持有该附件 → 缓存保留，展开不重读。
    patch([const StudioTimelineRemove('call-a')]);
    await _pumpFrames(tester);
    await tester.tap(toggleFor('call-b'));
    await _pumpFrames(tester);
    await tester.pumpAndSettle();
    expect(
      find.byKey(StudioDriverKeys.viewImageThumbnail(entryB)),
      findsOneWidget,
    );
    expect(transport.reads, hasLength(2), reason: '共享附件在仍有引用时不丢缓存');

    // 最后一个引用消失 → 缓存释放：重新插入并展开会重新读取。
    patch([const StudioTimelineRemove('call-b')]);
    await _pumpFrames(tester);
    patch([
      StudioTimelineAdd(imageToolItem('call-a', ordinal: 3, name: 'mcp__plot')),
    ]);
    await _pumpFrames(tester);
    await tester.tap(toggleFor('call-a'));
    await _pumpFrames(tester);
    await tester.pumpAndSettle();
    expect(transport.reads, hasLength(3), reason: '最后引用释放后重新展开必须重新读取');

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester);
    await tester.runAsync(() => client.close(deadline: deadline));
    await _pumpFrames(tester, frames: 2);
  });

  testWidgets('退役展示尚未卸载时不再发布阅读意图', (tester) async {
    final lease = leaseFor(items: longHistory());
    var intents = 0;
    await tester.pumpWidget(
      host(
        TimelineView(
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
      await tester.pumpWidget(const SizedBox.shrink());
      await released;
    }
  });

  testWidgets('退役展示的已捕获按钮回调不再发布动作', (tester) async {
    for (final phase in [
      TimelineConnectionPhase.ready,
      TimelineConnectionPhase.failed,
    ]) {
      final lease = leaseFor(items: [textItem('old', ordinal: 1)]);
      var actions = 0;
      Future<void> action() async {
        actions++;
      }

      await tester.pumpWidget(
        host(
          TimelineView(
            threadId: 'thread',
            lease: lease,
            view: viewState(
              mode: TimelineDisplayMode.history,
              connection: phase,
              hasOlder: true,
              olderError: 'retry',
              connectionError: 'retry',
            ),
            onLoadOlder: action,
            onRetryOlder: action,
            onReturnLive: action,
            onRetryConnection: action,
            onEnterHistory: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final callbacks = <VoidCallback>[];
      for (final key in [
        StudioDriverKeys.timelineReturnLive,
        StudioDriverKeys.timelineRetryOlder,
        StudioDriverKeys.timelineRetryConnection,
      ]) {
        final finder = find.byKey(key);
        if (finder.evaluate().isNotEmpty) {
          final callback = switch (tester.widget(finder)) {
            InkWell(:final onTap) => onTap,
            ButtonStyleButton(:final onPressed) => onPressed,
            _ => throw StateError('Unexpected timeline action widget'),
          };
          if (callback != null) callbacks.add(callback);
        }
      }
      expect(callbacks, isNotEmpty);
      final released = lease.retire();
      try {
        for (final callback in callbacks) {
          callback();
        }
        await tester.pump();
        expect(actions, 0, reason: '回调属于捕获它的展示寿命');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await released;
      }
    }
  });

  // ---- R2 嵌套工具内部滚动：桌面平台语义下的承重证明 -----------------------------

  testWidgets(
    '嵌套工具内部滚动不会把主 Timeline 推进 History',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      final lease = leaseFor(
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
          TimelineView(
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
        find
            .ancestor(
              of: find.byKey(
                StudioDriverKeys.timelineActivitySummary(
                  lease.presentationFor('tool-1')!.id,
                ),
              ),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-tool-details:tool-1')),
      );
      await tester.pumpAndSettle();
      final candidates = find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-tool-details:tool-1')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.vertical,
        ),
      );
      expect(candidates, findsWidgets);
      // 选出工具参数那个真正可滚动的内部区域（有独立 extent）。
      Finder? inner;
      ScrollPosition? innerPosition;
      for (var index = 0; index < candidates.evaluate().length; index++) {
        final candidate = candidates.at(index);
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(of: candidate, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
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
    final lease = leaseFor(items: longHistory());
    var enteredHistory = 0;
    var loads = 0;
    await tester.pumpWidget(
      host(
        TimelineView(
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
    final lease = leaseFor(items: [textItem('only', ordinal: 1)]);
    var retries = 0;
    await tester.pumpWidget(
      host(
        TimelineView(
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
        TimelineView(
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
    expect(
      find.text('Reconnecting messages… Current content is preserved.'),
      findsOneWidget,
    );
    expect(find.byKey(StudioDriverKeys.timelineRow('only')), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.timelineRetryConnection), findsNothing);

    // failed：可见错误 + retry；点 retry 只重试连接，代次与内容不变。
    await tester.pumpWidget(
      host(
        TimelineView(
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
      find.text(
        'Unable to synchronize messages. Current content is preserved.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(StudioDriverKeys.timelineRetryConnection));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(lease.generation, 1, reason: '连接重试不得换代');
    expect(find.byKey(StudioDriverKeys.timelineRow('only')), findsOneWidget);
  });
}

Future<(AnyworkClient, TimelineSessionOwner, _DetailTransport)>
_openDetailSession(
  WidgetTester tester, {
  StudioTimelineBaseline? baseline,
}) async {
  final transport = _DetailTransport(baseline: baseline);
  final client = AnyworkClient(transport: transport, clientId: 'd4a-viewer');
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  addTearDown(() => client.close(deadline: deadline));
  late final TimelineSessionOwner owner;
  await tester.runAsync(() async {
    client.selection.markOpened();
    client.threadDirectory.applyBaseline(
      ThreadDirectoryPage(threads: [_thread()], revision: 1),
      revision: 1,
    );
    owner = TimelineSessionOwner(client: client);
    addTearDown(() => owner.close(deadline: deadline));
    client.workspace.selectThread('thread', projectId: 'project');
    await owner.source.waitFor((state) => state?.generation != 0);
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
  workspacePath: '/tmp/thread',
);

/// 首帧：一条带截断文本详情的条目。
StudioTimelineBaseline _detailBaseline() {
  final timestamp = DateTime.utc(2026);
  return StudioTimelineBaseline(
    subscriptionId: 'sub',
    version: 1,
    before: null,
    hasOlder: false,
    items: [
      StudioTimelineItem(
        item: ThreadItemView(
          id: 'big',
          threadId: 'thread',
          turnId: 'turn',
          ordinal: 1,
          revision: 1,
          createdAt: timestamp,
          updatedAt: timestamp,
          saved: true,
          executionTerminal: true,
          bodyOmittedUnits: 6,
          state: ThreadTextItemStateView(
            channel: ThreadTextChannel.finalAnswer,
            text: 'preview',
            attachments: const [],
            lifecycle: CompletedThreadContentView(timestamp),
          ),
        ),
        saved: true,
        lifecycle: StudioTimelineLifecycle.terminal,
        omittedBytes: 6,
        details: const [
          StudioTimelineDetailRef(
            field: ThreadTextFieldView(),
            revision: 1,
            totalBytes: 12,
            previewBytes: 6,
          ),
        ],
      ),
    ],
  );
}

/// 受控内容连接：详情请求由测试用 `Completer` 逐块放行，避免帧数/睡眠式断言。
/// 静态长内容基线：真实溢出视口，滚动几何由标准 controller 产生。
StudioTimelineBaseline _longBaseline({int count = 40}) {
  final timestamp = DateTime.utc(2026);
  return StudioTimelineBaseline(
    subscriptionId: 'sub',
    version: 1,
    before: null,
    hasOlder: true,
    items: [
      for (var index = 0; index < count; index++)
        StudioTimelineItem(
          item: ThreadItemView(
            id: 'line-$index',
            threadId: 'thread',
            turnId: 'turn',
            ordinal: index,
            revision: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            saved: true,
            executionTerminal: true,
            state: ThreadTextItemStateView(
              channel: ThreadTextChannel.finalAnswer,
              text: '第 $index 段静态正文' * 6,
              attachments: const [],
              lifecycle: CompletedThreadContentView(timestamp),
            ),
          ),
          saved: true,
          lifecycle: StudioTimelineLifecycle.terminal,
          omittedBytes: 0,
          details: const [],
        ),
    ],
  );
}

/// 跨块正文选择夹具：前后 canonical 正文夹一条带详情入口行的大条目。
StudioTimelineBaseline _selectionBaseline() {
  final timestamp = DateTime.utc(2026);
  StudioTimelineItem canonical(String id, int ordinal, String body) =>
      StudioTimelineItem(
        item: ThreadItemView(
          id: id,
          threadId: 'thread',
          turnId: 'turn',
          ordinal: ordinal,
          revision: 1,
          createdAt: timestamp,
          updatedAt: timestamp,
          saved: true,
          executionTerminal: true,
          state: ThreadTextItemStateView(
            channel: ThreadTextChannel.finalAnswer,
            text: body,
            attachments: const [],
            lifecycle: CompletedThreadContentView(timestamp),
          ),
        ),
        saved: true,
        lifecycle: StudioTimelineLifecycle.terminal,
        omittedBytes: 0,
        details: const [],
      );
  return StudioTimelineBaseline(
    subscriptionId: 'sub',
    version: 1,
    before: null,
    hasOlder: false,
    items: [
      canonical('before', 1, '前段canonical正文'),
      StudioTimelineItem(
        item: ThreadItemView(
          id: 'big',
          threadId: 'thread',
          turnId: 'turn',
          ordinal: 2,
          revision: 1,
          createdAt: timestamp,
          updatedAt: timestamp,
          saved: true,
          executionTerminal: true,
          bodyOmittedUnits: 6,
          state: ThreadTextItemStateView(
            channel: ThreadTextChannel.finalAnswer,
            text: '截断前的preview',
            attachments: const [],
            lifecycle: CompletedThreadContentView(timestamp),
          ),
        ),
        saved: true,
        lifecycle: StudioTimelineLifecycle.terminal,
        omittedBytes: 6,
        details: const [
          StudioTimelineDetailRef(
            field: ThreadTextFieldView(),
            revision: 1,
            totalBytes: 12,
            previewBytes: 6,
          ),
        ],
      ),
      canonical('after', 3, '后段canonical正文'),
    ],
  );
}

/// 双字段夹具：一次工具调用的参数与输出同时被截断，两条详情引用都可读。
StudioTimelineBaseline _twoFieldBaseline() {
  final timestamp = DateTime.utc(2026);
  return StudioTimelineBaseline(
    subscriptionId: 'sub',
    version: 1,
    before: null,
    hasOlder: false,
    items: [
      StudioTimelineItem(
        item: ThreadItemView(
          id: 'tool',
          threadId: 'thread',
          turnId: 'turn',
          ordinal: 1,
          revision: 1,
          createdAt: timestamp,
          updatedAt: timestamp,
          saved: true,
          executionTerminal: true,
          state: ThreadToolItemStateView(
            invocation: ThreadToolInvocationView(
              toolCallId: 'tool',
              callId: 'tool',
              name: 'exec_command',
              arguments: '{"command":"cargo test"}',
            ),
            lifecycle: SucceededThreadToolView(
              timestamp,
              ThreadToolOutputView(
                result: 'ok',
                attachments: const [],
                outputArtifacts: const [],
              ),
            ),
          ),
        ),
        saved: true,
        lifecycle: StudioTimelineLifecycle.terminal,
        omittedBytes: 12,
        details: const [
          StudioTimelineDetailRef(
            field: ThreadToolArgumentsFieldView(),
            revision: 1,
            totalBytes: 8,
            previewBytes: 4,
          ),
          StudioTimelineDetailRef(
            field: ThreadToolResultFieldView(),
            revision: 1,
            totalBytes: 8,
            previewBytes: 4,
          ),
        ],
      ),
    ],
  );
}

final class _DetailConnection implements StudioTimelineConnection {
  _DetailConnection({required this.baseline, this.initialGate});

  final StudioTimelineBaseline baseline;

  /// 非空时首帧保持挂起：连接已登记、initial 未完成（旧 lease 仍活跃）。
  final Completer<StudioTimelineBaseline>? initialGate;
  final List<
    ({
      StudioTimelineDetailQuery query,
      Completer<StudioTimelineDetailChunk> reply,
    })
  >
  detailCalls = [];
  final Completer<StudioTimelineUpdate?> _pending = Completer();
  int initialCalls = 0;
  int closeCalls = 0;
  bool closed = false;

  @override
  Future<StudioTimelineBaseline> initial() {
    initialCalls++;
    final gate = initialGate;
    return gate == null ? Future.value(baseline) : gate.future;
  }

  @override
  Future<StudioTimelineUpdate?> next() => _pending.future;

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) async =>
      const StudioTimelinePage(items: [], before: null, hasOlder: false);

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) {
    final reply = Completer<StudioTimelineDetailChunk>();
    detailCalls.add((query: query, reply: reply));
    return reply.future;
  }

  @override
  void requestClose() {
    closed = true;
    if (!_pending.isCompleted) _pending.complete(null);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
  }
}

final class _UnusedTimelineAccountPorts extends UnusedAccountPorts {}

/// 真实附件字节通路的受控 backend：记录实际读取，返回可解码的 1×1 PNG。
final class _ImageTransport implements StudioTransport {
  _ImageTransport({this.failures = 0});
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

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused transport capability: ${invocation.memberName}',
  );
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
  _DetailTransport({StudioTimelineBaseline? baseline})
    : _baseline = baseline ?? _detailBaseline();

  final StudioTimelineBaseline _baseline;
  final List<_DetailConnection> connections = [];
  bool holdNextOpen = false;
  bool holdNextInitial = false;
  Completer<void>? _held;
  Completer<StudioTimelineBaseline>? _initialGate;

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) {
    final gate = holdNextInitial ? (_initialGate = Completer()) : null;
    holdNextInitial = false;
    final connection = _DetailConnection(
      baseline: _baseline,
      initialGate: gate,
    );
    connections.add(connection);
    if (holdNextOpen) {
      holdNextOpen = false;
      final held = _held = Completer<void>();
      return held.future.then((_) => connection);
    }
    return Future.value(connection);
  }

  void releaseHeld() {
    _held?.complete();
    _held = null;
  }

  /// 放行挂起的首帧（会交付新基线）。
  void releaseInitial() {
    final gate = _initialGate;
    _initialGate = null;
    if (gate != null && !gate.isCompleted) gate.complete(_detailBaseline());
  }

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused transport capability: ${invocation.memberName}',
  );
}

StudioTimelineDetailChunk _chunk({
  String? continuation,
  String text = 'AAAAAA',
}) => StudioTimelineDetailChunk(
  itemId: 'big',
  field: const ThreadTextFieldView(),
  revision: 1,
  text: text,
  totalBytes: 12,
  continuation: continuation,
);

/// 只推进有限帧：查看器读取中可能出现进度指示，`pumpAndSettle` 会等不到静止。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
