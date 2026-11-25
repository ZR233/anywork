import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/studio_reactive_projections.dart';
import 'package:anywork/src/features/status/context_usage_readout.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/status_detail_panel.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'diagnostic-rich context keeps costs visible and compaction actionable',
    (tester) async {
      final gaps = List.generate(
        7,
        (index) => _call('gap-$index', cancelled: true),
      );
      final projection = StudioContextProjection(
        threadId: 'thread-observed',
        modelId: 'model-under-test',
        contextTokens: 409780,
        contextWindow: 1050000,
        maxContextWindow: 1050000,
        autoCompactLimit: 475000,
        totalTokens: 71321660,
        costLabel: '',
        promptTokens: 71111000,
        completionTokens: 210660,
        cachedPromptTokens: 70030000,
        cacheWriteTokens: 0,
        reasoningTokens: 84320,
        inferenceCount: 285,
        cacheUsage: const CacheUsageView(
          sampleCount: 282,
          legacySampleCountUnknown: true,
          inputTokens: 71100000,
          cacheReadTokens: 70030000,
          hitRate: 0.98,
          hasIncompleteUsage: true,
        ),
        estimatedCosts: const [
          RuntimeCostView(currency: 'USD', amount: 2.5),
          RuntimeCostView(currency: 'CNY', amount: 1.2),
        ],
        estimatedCacheSavings: const [
          RuntimeCostView(currency: 'USD', amount: 12),
        ],
        hasUnpricedUsage: true,
        hasIncompleteUsage: true,
        usageDiagnostics: ThreadUsageDiagnostics(
          incompleteCalls: 8,
          missingCalls: 7,
          partialCalls: 1,
          invalidCalls: 0,
          overflowCalls: 0,
          byPurpose: const [
            UsagePurposeCountSnapshot(
              purpose: 'turn',
              calls: 285,
              incompleteCalls: 8,
            ),
          ],
          otherPurposeCalls: 0,
          byIssue: const [
            UsageIssueCountSnapshot(
              issue: UsageGapIssue(
                field: UsageCounterField.total,
                reason: UsageGapReason.nonTerminalSample,
              ),
              calls: 1,
            ),
          ],
          recentGaps: gaps,
          latestCall: _call('latest-success', cancelled: false),
          legacyUnknown: true,
          countsOverflowed: false,
        ),
      );
      var compactCalls = 0;
      await _showDetail(tester, projection, onCompact: () => compactCalls++);
      final detail = find.byKey(StudioDriverKeys.contextUsageDetail());
      final l10n = AppLocalizations.of(tester.element(detail));
      final trigger = find.byKey(StudioDriverKeys.contextUsage());
      expect(tester.getSize(trigger), const Size(32, 32));
      expect(
        tester
            .widgetList<StatusDetailPanel>(
              find.descendant(
                of: detail,
                matching: find.byType(StatusDetailPanel),
              ),
            )
            .map((panel) => panel.title),
        [
          l10n.statusContextLabel,
          l10n.statusModelLabel,
          l10n.statusSessionUsageSection,
          l10n.statusCost,
        ],
      );
      expect(find.text('model-under-test'), findsOneWidget);
      expect(find.text('409.78k / 475k'), findsOneWidget);
      expect(find.text(l10n.statusAutoCompactLimitLabel), findsNothing);
      expect(
        find.text('71.32m · Incomplete · Missing final usage reports'),
        findsOneWidget,
      );
      expect(find.text('98% · Incomplete'), findsOneWidget);
      expect(find.text('282'), findsNothing);
      expect(find.textContaining('thread-observed'), findsNothing);
      expect(find.textContaining('latest-success'), findsNothing);
      expect(find.textContaining('gap-'), findsNothing);
      expect(find.text(r'$2.50').hitTestable(), findsOneWidget);
      expect(find.text('￥1.20 · Unpriced').hitTestable(), findsOneWidget);
      expect(find.text(r'$12.00').hitTestable(), findsOneWidget);
      final scrollable = tester.state<ScrollableState>(
        find.ancestor(of: detail, matching: find.byType(Scrollable)).first,
      );
      expect(scrollable.position.maxScrollExtent, 0);

      await tester.tap(find.byKey(StudioDriverKeys.compactContext()));
      expect(compactCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown usage stays unknown and cannot trigger compaction', (
    tester,
  ) async {
    await _showDetail(
      tester,
      const StudioContextProjection(
        threadId: 'thread-empty',
        modelId: '',
        contextTokens: 0,
        contextWindow: 0,
        maxContextWindow: null,
        autoCompactLimit: null,
        totalTokens: 0,
        costLabel: '',
        promptTokens: 0,
        completionTokens: 0,
        cachedPromptTokens: 0,
        cacheWriteTokens: 0,
        reasoningTokens: 0,
        inferenceCount: 0,
        cacheUsage: CacheUsageView(),
        estimatedCosts: [],
        estimatedCacheSavings: [],
        hasUnpricedUsage: false,
        hasIncompleteUsage: false,
      ),
    );
    final detail = find.byKey(StudioDriverKeys.contextUsageDetail());
    final l10n = AppLocalizations.of(tester.element(detail));
    for (final label in [
      l10n.statusModelMaxContextLabel,
      l10n.statusInputTokensLabel,
      l10n.statusOutputTokensLabel,
      l10n.statusTotalTokensLabel,
      l10n.statusCacheLabel,
      l10n.statusCostEstimateLabel,
    ]) {
      final row = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: row, matching: find.text('—')),
        findsOneWidget,
      );
    }
    expect(find.text('0 / —'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.text(l10n.statusInferenceCountLabel), findsNothing);
    expect(find.text(l10n.statusCacheHitTokensLabel), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.byKey(StudioDriverKeys.compactContext()))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow scaled detail keeps the full model name accessible', (
    tester,
  ) async {
    const modelId = 'provider/a-model-with-an-extraordinarily-long-name';
    final mouse = await _showDetail(
      tester,
      const StudioContextProjection(
        threadId: 'thread-narrow',
        modelId: modelId,
        contextTokens: 0,
        contextWindow: 160000,
        maxContextWindow: 200000,
        autoCompactLimit: 120000,
        totalTokens: 0,
        costLabel: '',
        promptTokens: 0,
        completionTokens: 0,
        cachedPromptTokens: 0,
        cacheWriteTokens: 0,
        reasoningTokens: 0,
        inferenceCount: 0,
        cacheUsage: CacheUsageView(),
        estimatedCosts: [],
        estimatedCacheSavings: [],
        hasUnpricedUsage: false,
        hasIncompleteUsage: false,
      ),
      viewport: const Size(260, 720),
      textScaler: const TextScaler.linear(2),
    );
    final detail = find.byKey(StudioDriverKeys.contextUsageDetail());
    final name = find.descendant(of: detail, matching: find.text(modelId));
    expect(tester.widget<Text>(name).maxLines, 1);
    expect(tester.widget<Text>(name).overflow, TextOverflow.ellipsis);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('160k'), findsOneWidget);
    expect(find.text('200k'), findsOneWidget);

    await mouse.moveTo(tester.getCenter(name));
    await tester.pump(const Duration(milliseconds: 250));
    expect(detail, findsOneWidget);
    expect(find.text(modelId), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(detail, findsOneWidget);
    expect(find.text(modelId), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

Future<TestGesture> _showDetail(
  WidgetTester tester,
  StudioContextProjection projection, {
  VoidCallback? onCompact,
  Size viewport = const Size(1280, 720),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: pureStudioTheme(),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: ContextUsageReadout(
            projection: projection,
            onCompact: onCompact,
          ),
        ),
      ),
    ),
  );
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(
    tester.getCenter(find.byKey(StudioDriverKeys.contextUsage())),
  );
  await tester.pump(const Duration(milliseconds: 121));
  await tester.pumpAndSettle();
  return mouse;
}

UsageCallSnapshot _call(String callId, {required bool cancelled}) =>
    UsageCallSnapshot(
      threadId: 'thread-observed',
      callId: callId,
      turnId: 'turn-observed',
      effectSequence: 3,
      observedAt: 1700000000,
      purpose: 'turn',
      outcome: cancelled
          ? UsageTerminalStatus.cancelled
          : UsageTerminalStatus.succeeded,
      status: cancelled
          ? UsageReportStatus.missing
          : UsageReportStatus.reported,
      usage: UsageReport(
        inputTokens: cancelled ? null : 10,
        outputTokens: cancelled ? null : 0,
        cacheReadTokens: null,
        cacheWriteTokens: null,
        reasoningTokens: null,
        totalTokens: cancelled ? null : 10,
      ),
    );
