import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_feed_projection.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_outcome_card.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
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

ChatItemPresentation feedText(
  String id,
  String text,
  Map<String, Object?>? recovery,
) => chatItemPresentationOf(
  timelineFeedMessage(
    TimelineAssistantText(
      id: id,
      seq: 1,
      channel: 'commentary',
      text: text,
      isFinalTurnDelivery: false,
      outcome: 'completed',
      modelRecovery: StudioModelRecoveryNotice.fromJson(recovery),
    ),
  ),
)!;

void main() {
  testWidgets(
    'recovered and cancelled notices retain the provider diagnostics',
    (tester) async {
      final fixture = jsonDecode(
        File('test/fixtures/provider_recovery_notices.json').readAsStringSync(),
      ) as Map<String, Object?>;
      for (final (phase, status, code, errorType, requestId, stage, message)
          in [
            (
              'recovered',
              'Model request recovered',
              'upstream_connection_closed',
              'connection_error',
              'req-recovery-recovered',
              'Connection handshake',
              'The provider closed the connection during the handshake.',
            ),
            (
              'cancelled',
              'Automatic recovery was cancelled.',
              'service_unavailable',
              'overloaded_error',
              'req-recovery-cancelled',
              'Response stream',
              'The provider became unavailable while streaming the answer.',
            ),
          ]) {
        final notice = fixture[phase] as Map<String, Object?>;
        final original = notice['failure'] as Map<String, Object?>;
        final originalBody = original['message'] as String;
        final item = feedText(phase, originalBody, notice);
        expect(item.modelRecovery?.toJson(), notice);
        await tester.pumpWidget(
          _host(
            ChatItemView(key: ValueKey(phase), item: item),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(status), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        await tester.tap(find.text('Technical details'));
        await tester.pumpAndSettle();
        for (final detail in [code, errorType, requestId, stage, '503']) {
          expect(find.text(detail), findsOneWidget);
        }
        expect(
          find.descendant(
            of: find.byType(TimelineModelRecoveryStatus),
            matching: find.text(message),
          ),
          findsOneWidget,
        );
        expect(find.text('Model request recovery stopped'), findsNothing);
      }
    },
  );

  testWidgets('renders Feed recovery metadata and preserves ordinary text', (
    tester,
  ) async {
    ChatItemPresentation eventText(
      String id,
      String originalBody, {
      Map<String, Object?>? metaRecovery,
      Map<String, Object?>? frozenRecovery,
    }) {
      return feedText(id, originalBody, metaRecovery ?? frozenRecovery);
    }

    final fixture = jsonDecode(
      File('test/fixtures/provider_recovery_notices.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final waiting = eventText(
      'waiting',
      'The provider limited the request.',
      metaRecovery: fixture['waiting'] as Map<String, Object?>,
    );
    final frozenRepair = eventText(
      'repair',
      'An attachment handle expired.',
      frozenRecovery: {
        'phase': 'repairing',
        'failureKind': 'invalidRequest',
        'reason': 'refreshAttachments',
        'retryCount': 2,
        'maxRetries': 2,
      },
    );
    const legacyBody = '正在修复模型请求';
    final legacy = eventText('legacy', legacyBody);
    final unknown = eventText(
      'unknown-phase',
      'Unknown recovery phase body',
      metaRecovery: {'phase': 'unknown', 'retryCount': 1, 'maxRetries': 2},
    );
    const cancelledBody = 'Provider diagnostic retained after cancellation.';
    final cancelled = eventText(
      'cancelled-recovery',
      cancelledBody,
      metaRecovery: {'phase': 'cancelled', 'retryCount': 1, 'maxRetries': 2},
    );
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            for (final item in [
              waiting,
              frozenRepair,
              legacy,
              unknown,
              cancelled,
            ])
              ChatItemView(item: item),
          ],
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimelineModelRecoveryStatus), findsNWidgets(3));
    expect(find.text('Waiting to retry the model request'), findsOneWidget);
    expect(find.text('Temporary rate limit'), findsOneWidget);
    expect(find.text('Retry 1 of 2'), findsNWidgets(2));
    expect(find.text('Scheduled wait: 45 s'), findsOneWidget);
    expect(find.text('Repairing the model request'), findsOneWidget);
    expect(find.text('Refresh attachments'), findsOneWidget);
    expect(find.text('Retry 2 of 2'), findsOneWidget);
    expect(find.text(legacyBody), findsOneWidget);
    expect(find.text('Unknown recovery phase body'), findsOneWidget);
    expect(find.text('Automatic recovery was cancelled.'), findsOneWidget);
    expect(find.text(cancelledBody), findsOneWidget);
  });

  testWidgets('shows why retries stopped and keeps provider diagnostics', (
    tester,
  ) async {
    final outcome = jsonDecode(
      File('test/fixtures/provider_failure_retry.json').readAsStringSync(),
    );
    final item = TimelinePreviewFixtures.item('retry-stopped', 'turn', {
      'outcome': outcome,
    });
    await tester.pumpWidget(
      _host(ChatItemView(item: item), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Temporary rate limit'), findsOneWidget);
    expect(find.text('Retries used: 2 of 2'), findsOneWidget);
    expect(
      find.text('Automatic recovery stopped after reaching the retry limit.'),
      findsOneWidget,
    );
    expect(find.text('Provider suggests waiting 45s'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('timeline-error-details-toggle:retry-stopped')),
    );
    await tester.pumpAndSettle();

    expect(find.text('req-rate-limit-fixture'), findsOneWidget);
    expect(find.text('rate_limit_error'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('47000 ms'), findsOneWidget);
    expect(find.text('Provider suggests waiting 45s'), findsOneWidget);
  });

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
      expect(find.textContaining('已重试'), findsNothing);
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
    expect(find.text('Provider suggests waiting 5s'), findsOneWidget);
    expect(find.text('Turn reached budget limit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
