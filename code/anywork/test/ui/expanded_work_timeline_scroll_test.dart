import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork_previews/src/features/conversation/timeline/previews/expanded_work_timeline_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _layout(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Finder _marker(int number) => find.byKey(
  ValueKey('expanded-marker-${number.toString().padLeft(3, '0')}'),
);
Finder _groupVerticalScrolls() => find.descendant(
  of: find.byType(CompletionRunView),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable &&
        (widget.axisDirection == AxisDirection.down ||
            widget.axisDirection == AxisDirection.up),
  ),
);

void main() {
  testWidgets(
    'preview fixture isolates activity rows from an inherited dark ListTileTheme',
    (tester) async {
      const inheritedTileColor = Color(0xff111111);
      await tester.pumpWidget(
        Theme(
          data: ThemeData.dark(),
          child: const ListTileTheme(
            data: ListTileThemeData(tileColor: inheritedTileColor),
            child: ExpandedWorkTimelineFixture(initialCount: 2),
          ),
        ),
      );
      await _layout(tester);
      final row = find.byType(TimelineActivityRow).first;
      expect(row, findsOneWidget);
      final context = tester.element(row);
      final ownTheme = pureStudioTheme(locale: const Locale('zh'));
      expect(Theme.of(context).brightness, ownTheme.brightness);
      expect(
        ListTileTheme.of(context).tileColor,
        ownTheme.listTileTheme.tileColor,
      );
      expect(ListTileTheme.of(context).tileColor, isNot(inheritedTileColor));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final location in WorkDisplayLocation.values) {
    testWidgets(
      '$location production main timeline reaches first middle last of 120 mixed members',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(820, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey<ExpandedWorkTimelineFixtureState>();
        await tester.pumpWidget(
          ExpandedWorkTimelineFixture(key: key, location: location),
        );
        await _layout(tester);
        expect(find.byType(CompletionRunView), findsOneWidget);
        expect(
          tester.getSize(find.byType(CompletionRunView)).height,
          greaterThan(420),
        );
        expect(_groupVerticalScrolls(), findsNothing);
        final scroll = key.currentState!.controls.scrollController;
        expect(scroll.hasClients, isTrue);
        expect(scroll.position.maxScrollExtent, greaterThan(2000));
        for (final number in [1, 60, 120]) {
          final row = _marker(number);
          expect(row, findsOneWidget);
          await Scrollable.ensureVisible(tester.element(row), alignment: .5);
          await _layout(tester);
          expect(
            row.hitTestable(),
            findsOneWidget,
            reason:
                'Member $number is reachable through the production main scroll',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('$location bottom follows additions and async height', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(820, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey<ExpandedWorkTimelineFixtureState>();
      await tester.pumpWidget(
        ExpandedWorkTimelineFixture(
          key: key,
          location: location,
          initialCount: 30,
        ),
      );
      await _layout(tester);
      final state = key.currentState!;
      final scroll = state.controls.scrollController;
      scroll.jumpTo(scroll.position.minScrollExtent);
      await _layout(tester);
      state.appendMember();
      await _layout(tester);
      expect(
        scroll.position.pixels,
        closeTo(scroll.position.minScrollExtent, 1),
      );
      await state.growMiddle();
      await _layout(tester);
      expect(
        scroll.position.pixels,
        closeTo(scroll.position.minScrollExtent, 1),
      );
      expect(
        find.text(
          '完整 31 项 · ${location == WorkDisplayLocation.history ? '历史消息行' : '当前消息行'}',
        ),
        findsOneWidget,
      );
      expect(_groupVerticalScrolls(), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      '$location actual main drag enters history and later growth does not force bottom',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(820, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey<ExpandedWorkTimelineFixtureState>();
        await tester.pumpWidget(
          ExpandedWorkTimelineFixture(
            key: key,
            location: location,
            initialCount: 30,
          ),
        );
        await _layout(tester);
        final state = key.currentState!;
        final scroll = state.controls.scrollController;
        await Scrollable.ensureVisible(
          tester.element(_marker(15)),
          alignment: .5,
        );
        await _layout(tester);
        expect(
          state.mode,
          TimelineDisplayMode.live,
          reason: 'Programmatic reveal alone is not user intent',
        );
        final main = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable && identical(widget.controller, scroll),
        );
        expect(main, findsOneWidget);
        await tester.drag(main, const Offset(0, 120));
        await _layout(tester);
        expect(state.mode, TimelineDisplayMode.history);
        final reading = scroll.position.pixels;
        expect(reading, greaterThan(100));
        state.appendMember();
        await _layout(tester);
        expect(
          scroll.position.pixels,
          greaterThan(100),
          reason:
              'Appending must not return an upward-reading user to the bottom',
        );
        expect(_marker(15).hitTestable(), findsOneWidget);
        await state.growMiddle();
        await _layout(tester);
        expect(state.mode, TimelineDisplayMode.history);
        expect(
          scroll.position.pixels,
          greaterThan(100),
          reason: 'Async details must not steal the upward-reading intent',
        );
        expect(_groupVerticalScrolls(), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
