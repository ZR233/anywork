import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_history_projection.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_resting_cat.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double width = 720, double scale = 1}) =>
    MaterialApp(
      theme: pureStudioTheme(),
      locale: const Locale('zh'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

Finder _workTitle(Finder header) => find.descendant(
  of: header,
  matching: find.byKey(const ValueKey('work-header-title')),
);

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
const _thinking = ConversationActivityView(
  identity: 'thinking',
  kind: ConversationActivityKind.thinking,
);

void main() {
  testWidgets('imported Work with unknown times does not invent a duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CompletionRunView(
          id: 'imported',
          timing: const WorkTiming(startedAtMillis: null),
          location: WorkDisplayLocation.history,
          initiallyExpanded: false,
          childBuilder: (_) => const SizedBox(),
        ),
      ),
    );
    expect(find.text('工作记录'), findsOneWidget);
    expect(find.text('工作了不到 1 秒'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'one Work clock includes idle and overnight time without reading members',
    (tester) async {
      var seconds = 1000;
      var reads = 0;
      await tester.pumpWidget(
        _host(
          CompletionRunView(
            id: 'clock',
            timing: const WorkTiming(startedAtMillis: 1_000_000),
            location: WorkDisplayLocation.live,
            executionPresent: false,
            initiallyExpanded: false,
            now: () => _at(seconds),
            childBuilder: (_) {
              reads++;
              return const Text('members');
            },
          ),
        ),
      );
      expect(find.text('工作记录'), findsOneWidget);
      expect(find.text('执行了不到 1 秒'), findsOneWidget);
      seconds = 1125;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('执行了 2 分 5 秒'), findsOneWidget);
      seconds += 3600;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('执行了 1 小时 2 分 5 秒'), findsOneWidget);
      seconds += 82800;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('执行了 1 日 2 分 5 秒'), findsOneWidget);
      expect(
        tester
            .widget<TimelineActivityIndicator>(
              find.byType(TimelineActivityIndicator),
            )
            .active,
        isFalse,
      );
      expect(reads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'hidden Work clock resumes from the same start without periodic refresh',
    (tester) async {
      var seconds = 1000;
      Widget view(bool visible) => _host(
        TickerMode(
          enabled: visible,
          child: CompletionRunView(
            id: 'hidden',
            timing: const WorkTiming(startedAtMillis: 1_000_000),
            location: WorkDisplayLocation.live,
            initiallyExpanded: false,
            now: () => _at(seconds),
            childBuilder: (_) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpWidget(view(false));
      seconds = 1125;
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(view(true));
      expect(find.text('执行了 2 分 5 秒'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final location in WorkDisplayLocation.values) {
    testWidgets(
      'sealed Work is frozen in $location and expands only on demand',
      (tester) async {
        var seconds = 1125;
        var reads = 0;
        await tester.pumpWidget(
          _host(
            CompletionRunView(
              id: 'sealed',
              timing: const WorkTiming(
                startedAtMillis: 1_000_000,
                finishedAtMillis: 1_125_000,
              ),
              state: DisplayBlockState.sealed,
              location: location,
              hasUnfinishedMembers: true,
              thinkingSummary: 'must stay out of history',
              activity: _thinking,
              executionPresent: true,
              initiallyExpanded: false,
              now: () => _at(seconds),
              childBuilder: (_) {
                reads++;
                return const Text('original member result');
              },
            ),
          ),
        );
        final header = find.byKey(
          const ValueKey('completion-run-header:sealed'),
        );
        expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
        expect(find.text('must stay out of history'), findsNothing);
        expect(find.byType(TimelineActivityIndicator), findsNothing);
        expect(reads, 0);
        seconds += 86400;
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
        expect(reads, 0);
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(find.text('original member result'), findsOneWidget);
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(find.text('original member result'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final (elapsedMillis, label) in [
    (null, '工作记录'),
    (-1, '工作记录'),
    (0, '工作了不到 1 秒'),
    (999, '工作了不到 1 秒'),
    (6000, '工作了 6 秒'),
    (7000, '工作了 7 秒'),
    (120_000, '工作了 2 分'),
    (125_000, '工作了 2 分 5 秒'),
  ]) {
    testWidgets(
      'history Work interval of $elapsedMillis milliseconds displays $label',
      (tester) async {
        const startedAt = 1_785_000_000_800;
        final block = TimelineHistoryProjection.block(
          WorkRangeTimelineItem(
            HistoryWorkRange(
              rangeId: 'work:history',
              beforeSeq: 3,
              firstSeq: 1,
              lastSeq: 2,
              startedAt: startedAt,
              endedAt: elapsedMillis == null ? null : startedAt + elapsedMillis,
              eventCount: 1,
            ),
          ),
          cut: const HistoryCut('work-history-cut'),
        );
        await tester.pumpWidget(
          _host(
            TimelineDisplayUnitView(
              unit: TimelineDisplayUnit(block: block),
              childBuilder: (_) => throw StateError('Work is collapsed'),
            ),
          ),
        );
        final header = find.byKey(
          const ValueKey('completion-run-header:work:history'),
        );
        expect(tester.widget<Text>(_workTitle(header)).data, label);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final (width, scale) in [(720.0, 1.0), (360.0, 1.6)]) {
    testWidgets('live summary and clock share one row at $width/$scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CompletionRunView(
            id: 'narrow',
            timing: const WorkTiming(startedAtMillis: 1_000_000),
            thinkingSummary:
                '核对 **组件边界** 与 `LiveStatusBar` [本组摘要](https://example.com) ' *
                5,
            location: WorkDisplayLocation.live,
            executionPresent: true,
            activity: _thinking,
            initiallyExpanded: false,
            now: () => _at(1125),
            childBuilder: (_) => const Text('exact body'),
          ),
          width: width,
          scale: scale,
        ),
      );
      final header = find.byKey(const ValueKey('completion-run-header:narrow'));
      expect(find.byType(TimelineReasoningSummary), findsOneWidget);
      expect(find.text('执行了 2 分 5 秒'), findsOneWidget);
      final summary = tester.widget<TimelineMarkdown>(
        find.descendant(
          of: _workTitle(header),
          matching: find.byType(TimelineMarkdown),
        ),
      );
      expect(summary.maxLines, 1);
      expect(summary.overflow, TextOverflow.ellipsis);
      expect(find.byType(TimelineRestingCat), findsOneWidget);
      await tester.tap(_workTitle(header));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('exact body'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'history members exceed 420 naturally and parent scrolling reaches final details',
    (tester) async {
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: CompletionRunView(
              id: 'history',
              timing: const WorkTiming(
                startedAtMillis: 1_000_000,
                finishedAtMillis: 1_125_000,
              ),
              location: WorkDisplayLocation.history,
              initiallyExpanded: true,
              childBuilder: (_) => const Column(
                children: [
                  SizedBox(height: 900),
                  Text('member failure and cancellation details'),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(CompletionRunView)).height,
        greaterThan(900),
      );
      expect(
        find.descendant(
          of: find.byType(CompletionRunView),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      final details = find.text('member failure and cancellation details');
      expect(details.hitTestable(), findsNothing);
      await tester.ensureVisible(details);
      await tester.pumpAndSettle();
      expect(details.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
