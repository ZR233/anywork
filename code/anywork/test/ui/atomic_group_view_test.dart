import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: child,
    ),
  ),
);

void main() {
  testWidgets(
    'folded huge group never invokes its member builder; fold revokes before animation',
    (tester) async {
      final unit = TimelineDisplayUnit(
        item: workItem('huge', count: 100000),
        live: false,
      );
      var builds = 0;
      await tester.pumpWidget(
        _host(
          TimelineDisplayUnitView(
            unit: unit,
            executionPresent: false,
            childBuilder: (_) {
              builds++;
              return const Text('实际成员');
            },
          ),
        ),
      );
      expect(builds, 0);
      expect(find.text('实际成员'), findsNothing);
      expect(find.text('100000 项'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('source-unit-header:huge')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(builds, greaterThan(0));
      expect(find.text('实际成员'), findsOneWidget);
      expect(unit.expansion.bodyActive, isTrue);
      await tester.tap(find.byKey(const ValueKey('source-unit-header:huge')));
      // No pump: resources lose qualification synchronously, before unmount.
      expect(unit.expansion.bodyActive, isFalse);
      expect(unit.expansion.retirement.value, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('实际成员'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'summary totals and failure counts do not become loaded-window totals',
    (tester) async {
      final unit = TimelineDisplayUnit(
        item: workItem(
          'summary',
          count: 82,
          failed: 4,
          cancelled: 2,
          start: 10,
          end: 18,
        ),
        live: false,
      );
      unit.expansion.expanded = true;
      await tester.pumpWidget(
        _host(
          TimelineDisplayUnitView(
            unit: unit,
            executionPresent: false,
            childBuilder: (_) => const Text('只有一页成员'),
          ),
        ),
      );
      expect(find.text('工作了 8 秒'), findsOneWidget);
      expect(find.text('82 项 · 4 项执行失败 · 2 项已停止'), findsOneWidget);
      expect(find.text('只有一页成员'), findsOneWidget);
      expect(
        tester
            .widget<TimelineActivityRow>(find.byType(TimelineActivityRow))
            .active,
        isFalse,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('工作了 8 秒'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'terminal current members waiting for boundary never pretend to keep executing',
    (tester) async {
      final unit = TimelineDisplayUnit(
        item: workItem('waiting', closed: false, start: 10, end: 14),
        live: true,
      );
      await tester.pumpWidget(
        _host(
          TimelineDisplayUnitView(
            unit: unit,
            executionPresent: true,
            childBuilder: (_) => const Text('成员'),
          ),
        ),
      );
      expect(find.text('等待后继边界'), findsOneWidget);
      expect(
        tester
            .widget<TimelineActivityRow>(find.byType(TimelineActivityRow))
            .active,
        isFalse,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('等待后继边界'), findsOneWidget);
      expect(find.textContaining('秒'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'same item handoff retains expansion, unknown time remains unknown in narrow scaled layout',
    (tester) async {
      final live = TimelineDisplayUnit(
        item: workItem('handoff', closed: false, active: 1),
        live: true,
      );
      Widget scene(
        TimelineDisplayUnit unit, {
        required bool executionPresent,
      }) => _host(
        SizedBox(
          width: 390,
          child: TimelineDisplayUnitView(
            key: ValueKey(unit.id),
            unit: unit,
            executionPresent: executionPresent,
            childBuilder: (_) => const Text('可读思考'),
          ),
        ),
        scale: 1.6,
      );
      await tester.pumpWidget(scene(live, executionPresent: true));
      await tester.tap(
        find.byKey(const ValueKey('source-unit-header:handoff')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('可读思考'), findsOneWidget);
      final history = TimelineDisplayUnit(
        item: workItem('handoff'),
        live: false,
        expansion: live.expansion,
      );
      await tester.pumpWidget(scene(history, executionPresent: false));
      expect(find.text('可读思考'), findsOneWidget);
      expect(find.text('工作记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
