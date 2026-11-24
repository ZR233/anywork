import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_outcome_card.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_previews/src/features/conversation/timeline/previews/timeline_preview_fixtures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(
  Widget child, {
  Locale locale = const Locale('zh'),
  double width = 760,
  double textScale = 1,
}) => MaterialApp(
  theme: pureStudioTheme(locale: locale),
  locale: locale,
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: SelectionArea(
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'failed turn directly shows message without expanding and hides raw JSON by default',
    (tester) async {
      await tester.pumpWidget(
        _host(ChatItemView(item: TimelinePreviewFixtures.failedTurnOverloaded)),
      );
      await tester.pumpAndSettle();

      const message = '该模型当前访问量过大，请您稍后再试[2026112409252610a0f9ae03204283]';
      expect(find.byType(TimelineErrorCard), findsOneWidget);
      expect(find.text('轮次失败'), findsOneWidget);
      expect(find.text('模型服务'), findsOneWidget);
      expect(find.text('overloaded'), findsOneWidget);
      expect(find.text('用时 2 分 14 秒'), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      // providerKind: "unknown" is suppressed from pills and raw JSON is hidden.
      expect(find.text('unknown'), findsNothing);
      expect(find.text('公开原始记录'), findsNothing);
      expect(find.textContaining('"startedAt"'), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey(
            'timeline-error-details-toggle:preview-turn-failed-overloaded',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('不自动重试'), findsOneWidget);
      expect(find.text('公开原始记录'), findsOneWidget);
      expect(find.textContaining('"startedAt"'), findsNothing);

      await tester.tap(find.text('公开原始记录'));
      await tester.pumpAndSettle();

      expect(find.textContaining('"startedAt"'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('copy button copies exact failure message to clipboard', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      _host(ChatItemView(item: TimelinePreviewFixtures.failedTurnOverloaded)),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('timeline-error-copy:preview-turn-failed-overloaded'),
      ),
    );
    await tester.pump();

    expect(copied, '该模型当前访问量过大，请您稍后再试[2026112409252610a0f9ae03204283]');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long failure message collapses initially and toggles expansion',
    (tester) async {
      final longMessage = List.generate(
        14,
        (index) => '第 ${index + 1} 行诊断信息：连接上游节点超时并触发退避重试策略。',
      ).join('\n');
      final item = TimelinePreviewFixtures.item('long-fail', 'turn', {
        'outcome': {
          'kind': 'failed',
          'data': {
            'failure': {'category': 'provider', 'message': longMessage},
          },
        },
      });

      await tester.pumpWidget(_host(ChatItemView(item: item)));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text(longMessage));
      expect(textWidget.maxLines, 6);
      expect(find.text('展开全部'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('timeline-error-expand-message:long-fail')),
      );
      await tester.pumpAndSettle();

      final expandedText = tester.widget<Text>(find.text(longMessage));
      expect(expandedText.maxLines, isNull);
      expect(find.text('收起'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('budgetLimited and cancelled turns render localized details', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChatItemView(item: TimelinePreviewFixtures.budgetLimitedTurn),
            ChatItemView(item: TimelinePreviewFixtures.cancelledTurn),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('轮次达到预算上限'), findsOneWidget);
    expect(find.text('已达到模型步数上限，本轮执行已停止。'), findsOneWidget);
    expect(find.text('模型 24 步'), findsOneWidget);
    expect(find.text('工具 41 次'), findsOneWidget);
    expect(find.text('等待 2 次'), findsOneWidget);
    expect(find.text('已整理上下文'), findsOneWidget);
    expect(find.text('本轮已取消'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow viewport with 1.6x text scale and English locale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChatItemView(item: TimelinePreviewFixtures.failedTurnRetryable503),
            ChatItemView(item: TimelinePreviewFixtures.budgetLimitedTurn),
          ],
        ),
        locale: const Locale('en'),
        width: 340,
        textScale: 1.6,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn failed'), findsOneWidget);
    expect(find.text('HTTP 503'), findsOneWidget);
    expect(find.text('Retry after 5s'), findsOneWidget);
    expect(find.text('Turn reached budget limit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
