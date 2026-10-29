// 原始记录条目的呈现契约：历史载荷与运行时说明是两种事实，不能互相冒充。
//
// 覆盖 `ThreadRawItemOrigin` 在界面的分支：`runtimeControl` 用本地化“运行时说明”行呈现且
// 没有可展开载荷；`stored` 仍是“原始历史记录”并可展开原样载荷。像素与真实数据由 Driver
// 人工证据覆盖（design/19、design/26 §26.7）。
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/conversation_fixtures.dart';
import 'support/pump_client_future.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final timestamp = DateTime.utc(2026, 1, 2, 3, 4, 5);

  ConversationItem rawItem(
    String id, {
    required int ordinal,
    required ConversationRawDescriptor descriptor,
    Map<ThreadContentFieldView, String> fields = const {},
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    ordinal: ordinal,
    createdAt: timestamp,
    updatedAt: timestamp,
    descriptor: descriptor,
    fields: fields,
  );

  TimelineDisplayLease leaseWith(
    WidgetTester tester,
    List<ConversationItem> items,
  ) {
    final lease = TimelineDisplayLease(
      threadId: 'thread',
      generation: 1,
      content: conversationContentFixture(tester: tester),
    );
    lease.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'test',
        version: 0,
        items: items,
        before: null,
        hasOlder: false,
      ),
    );
    return lease;
  }

  TimelineSessionViewState viewState() => TimelineSessionViewState(
    threadId: 'thread',
    generation: 1,
    mode: TimelineDisplayMode.live,
    connection: TimelineConnectionPhase.ready,
    connectionError: null,
    olderCursor: null,
    hasOlder: false,
    isLoadingOlder: false,
    olderError: null,
    hasNewOutput: false,
    isPreparingLive: false,
  );

  Future<void> unmountTimeline(
    WidgetTester tester,
    TimelineDisplayLease lease,
  ) async {
    if (lease.isReleased) return;
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      lease.retire(),
      'raw timeline stock operations done',
    );
    expect(lease.isReleased, isTrue, reason: '卸载后等待真实 stock operations done');
  }

  Future<void> pumpTimeline(
    WidgetTester tester,
    TimelineDisplayLease lease,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => unmountTimeline(tester, lease));
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TimelineView(
            threadId: 'thread',
            view: viewState(),
            controls: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
            onDetail: (_, _) {},
            onLink: (_) {},
            isSafeLink: (_) => false,
            imageBuilder: (_, _, _) => const SizedBox.shrink(),
            remoteImageBuilder: (_, _) => const SizedBox.shrink(),
            groupMediaBuilder: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('运行时说明不冒充原始历史记录，历史载荷仍可展开', (tester) async {
    final lease = leaseWith(tester, [
      rawItem(
        'notice',
        ordinal: 1,
        descriptor: ConversationRawDescriptor(
          payloads: const [],
          notice: 'This session continued after it was stopped.',
          recordedAt: timestamp,
          origin: ThreadRawItemOrigin.runtimeControl,
        ),
      ),
      rawItem(
        'payload',
        ordinal: 2,
        descriptor: ConversationRawDescriptor(
          payloads: const [
            ConversationRawPayloadDescriptor(
              format: 'pl.model.receipt',
              version: 1,
            ),
          ],
          notice: 'Unsupported saved response encoding',
          recordedAt: timestamp,
          origin: ThreadRawItemOrigin.stored,
        ),
        fields: {const ThreadRawPayloadFieldView(0): '{"ok":false}'},
      ),
    ]);

    await pumpTimeline(tester, lease);

    final context = tester.element(find.byType(TimelineView));
    final l10n = context.l10n;
    final notice = find.byKey(StudioDriverKeys.timelineBlock('notice'));
    expect(notice, findsOneWidget, reason: '运行时说明有自己的行身份');
    expect(find.text(l10n.timelineRuntimeNotice), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(
            find.descendant(of: notice, matching: find.byType(InkWell)),
          )
          .onTap,
      isNull,
      reason: '运行时说明没有可展开载荷，不能显示成原始历史记录',
    );
    expect(
      find.text('This session continued after it was stopped.'),
      findsNothing,
      reason: '运行时说明展示界面本地化文案，不回显内部说明原文',
    );

    expect(find.text(l10n.timelineRawRecord), findsOneWidget);
    final storedTile = find.byKey(StudioDriverKeys.timelineBlock('payload'));
    expect(storedTile, findsOneWidget, reason: '真历史载荷仍按原样保留展开入口');
    expect(
      find.text('Unsupported saved response encoding'),
      findsOneWidget,
      reason: '历史记录的 notice 仍由后端提供',
    );
    // 展开历史载荷：原样正文必须可见，证明它没有被运行时说明替换。
    await tester.tap(storedTile);
    await tester.pumpAndSettle();
    expect(find.text('{"ok":false}'), findsOneWidget, reason: '展开后显示原始载荷正文');
    await unmountTimeline(tester, lease);
  });
}
