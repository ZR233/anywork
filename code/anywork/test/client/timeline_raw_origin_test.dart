// 原始记录条目的呈现契约：历史载荷与运行时说明是两种事实，不能互相冒充。
//
// 覆盖 `ThreadRawItemOrigin` 在界面的分支：`runtimeControl` 用本地化“运行时说明”行呈现且
// 没有可展开载荷；`stored` 仍是“原始历史记录”并可展开原样载荷。像素与真实数据由 Driver
// 人工证据覆盖（design/19、design/26 §26.7）。
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final timestamp = DateTime.utc(2026, 1, 2, 3, 4, 5);

  StudioTimelineItem rawItem(
    String id, {
    required int ordinal,
    required ThreadRawItemStateView state,
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: ordinal,
      revision: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
      state: state,
    ),
    saved: true,
    lifecycle: StudioTimelineLifecycle.terminal,
    omittedBytes: 0,
    details: const [],
  );

  TimelineDisplayLease leaseWith(List<StudioTimelineItem> items) {
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

  Future<void> pumpTimeline(
    WidgetTester tester,
    TimelineDisplayLease lease,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TimelineView(
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
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('运行时说明不冒充原始历史记录，历史载荷仍可展开', (tester) async {
    final lease = leaseWith([
      rawItem(
        'notice',
        ordinal: 1,
        state: ThreadRawItemStateView(
          const [],
          'This session continued after it was stopped.',
          timestamp,
          origin: ThreadRawItemOrigin.runtimeControl,
        ),
      ),
      rawItem(
        'payload',
        ordinal: 2,
        state: ThreadRawItemStateView(
          const [RawHistoryPayload('pl.model.receipt', 1, '{"ok":false}')],
          'Unsupported saved response encoding',
          timestamp,
          origin: ThreadRawItemOrigin.stored,
        ),
      ),
    ]);

    await pumpTimeline(tester, lease);

    final context = tester.element(find.byType(TimelineView));
    final l10n = context.l10n;
    expect(
      find.byKey(const ValueKey('runtime-notice-notice')),
      findsOneWidget,
      reason: '运行时说明有自己的行身份',
    );
    expect(find.text(l10n.timelineRuntimeNotice), findsOneWidget);
    expect(
      find.byKey(const ValueKey('raw-history-notice')),
      findsNothing,
      reason: '运行时说明没有可展开载荷，不能显示成原始历史记录',
    );
    expect(
      find.text('This session continued after it was stopped.'),
      findsNothing,
      reason: '运行时说明展示界面本地化文案，不回显内部说明原文',
    );

    expect(find.text(l10n.timelineRawRecord), findsOneWidget);
    final storedTile = find.byKey(const ValueKey('raw-history-payload'));
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
  });
}
