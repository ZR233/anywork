import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_clock.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/timeline_observation.dart';

const _summary = WorkSummary(
  unavailable: 0,
  total: 3,
  terminal: 3,
  running: 0,
  waiting: 0,
  failed: 0,
  cancelled: 0,
  transferred: 0,
  createdAt: 1000,
  elapsedMs: 2000,
  durationMs: 2000,
);

Widget _host(WorkDisplayLocation location) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: CompletionRunView(
      id: 'observed-work',
      summary: _summary,
      location: location,
      executionPresent: location == WorkDisplayLocation.live,
      initiallyExpanded: false,
      now: () => DateTime.fromMillisecondsSinceEpoch(1002000, isUtc: true),
      childBuilder: (_) => const Text('exact Work body'),
    ),
  ),
);

void main() {
  testWidgets(
    'Work observer reads real Expansible and clicks original header',
    (tester) async {
      await tester.pumpWidget(_host(WorkDisplayLocation.live));
      final header = find.byKey(
        const ValueKey('completion-run-header:observed-work'),
      );
      final disclosure = find.byKey(
        const ValueKey('completion-run-disclosure:observed-work'),
      );
      final controller = tester.widget<Expansible>(disclosure).controller;
      expect(tester.widget(header), isNot(isA<TimelineActivityRow>()));
      expect(
        timelineWorkHeaderExpanded(tester, header, 'observed-work'),
        isFalse,
      );
      expect(controller.isExpanded, isFalse);
      final label = timelineGroupTitleFinder(tester, header);
      expect(label, findsOneWidget);
      final elapsed = find.descendant(
        of: header,
        matching: find.byKey(const ValueKey('work-header-elapsed')),
      );
      expect(elapsed, findsOneWidget);
      expect(tester.element(label), isNot(same(tester.element(elapsed))));
      expect(tester.widget<Text>(label).maxLines, 1);
      expect(tester.widget<Text>(elapsed).data, startsWith('执行了'));
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(
        timelineWorkHeaderExpanded(tester, header, 'observed-work'),
        isTrue,
      );
      expect(controller.isExpanded, isTrue);
      expect(find.text('exact Work body'), findsOneWidget);
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(
        timelineWorkHeaderExpanded(tester, header, 'observed-work'),
        isFalse,
      );
      expect(controller.isExpanded, isFalse);
      expect(find.text('exact Work body'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'history Work observer reads worked label without elapsed column',
    (tester) async {
      await tester.pumpWidget(_host(WorkDisplayLocation.history));
      final header = find.byKey(
        const ValueKey('completion-run-header:observed-work'),
      );
      final label = timelineGroupTitleFinder(tester, header);
      expect(label, findsOneWidget);
      expect(
        tester.widget<Text>(label).data,
        activityDurationLabel(
          tester.element(header),
          2,
          kind: ActivityDurationKind.worked,
        ),
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('work-header-elapsed')),
        ),
        findsNothing,
      );
      expect(
        timelineWorkHeaderExpanded(tester, header, 'observed-work'),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
