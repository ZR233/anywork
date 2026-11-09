import 'dart:ui' show Tristate;

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/plan_summary_card.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  double scale = 1,
  Locale locale = const Locale('zh'),
}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'whole plan card toggles one reader with keyboard and expanded semantics',
    (tester) async {
      var expanded = false;
      var toggles = 0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => PlanSummaryCard(
              title: '完整实施计划',
              expanded: expanded,
              onToggle: () => setState(() {
                expanded = !expanded;
                toggles++;
              }),
            ),
          ),
        ),
      );

      final card = find.byType(PlanSummaryCard);
      SemanticsNode node() => tester.getSemantics(card);
      expect(node().flagsCollection.isButton, isTrue);
      expect(node().flagsCollection.isExpanded, Tristate.isFalse);
      expect(find.text('查看完整计划'), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);
      final titleRect = tester.getRect(find.text('完整实施计划'));
      final helpRect = tester.getRect(find.text('请阅读计划，再批准或提出修改意见。'));
      expect(helpRect.left, titleRect.left);
      final badgeRect = tester.getRect(
        find
            .ancestor(
              of: find.text('等待确认'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(badgeRect.left, titleRect.left);
      expect(
        tester.getRect(find.text('查看完整计划')).left,
        greaterThan(badgeRect.right),
      );
      expect(
        tester.getRect(find.byIcon(Icons.expand_more)).right,
        tester.getRect(find.byType(Card)).right - 16,
      );

      // The title, document icon and action all belong to the same hit target.
      await tester.tap(find.text('完整实施计划'));
      await tester.pumpAndSettle();
      expect(toggles, 1);
      expect(node().flagsCollection.isExpanded, Tristate.isTrue);
      expect(find.text('收起计划'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.description_outlined));
      await tester.pumpAndSettle();
      expect(toggles, 2);
      await tester.tap(find.text('查看完整计划'));
      await tester.pumpAndSettle();
      expect(toggles, 3);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        Focus.of(tester.element(find.text('完整实施计划'))).hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(toggles, 4);
      expect(node().flagsCollection.isExpanded, Tristate.isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(toggles, 5);
      expect(node().flagsCollection.isExpanded, Tristate.isTrue);
    },
  );

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      'long ${locale.languageCode} title wraps at narrow width and 1.5 text scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final title = locale.languageCode == 'zh'
            ? '完整计划标题应自然换行，确保窄窗口与放大文字时仍能阅读全部实施目标与关键步骤，不省略最后一行'
            : 'A complete implementation plan with a long document title that remains readable in a narrow window with larger text';
        for (final expanded in [false, true]) {
          await tester.pumpWidget(
            _host(
              Padding(
                padding: const EdgeInsets.all(24),
                child: PlanSummaryCard(
                  title: title,
                  expanded: expanded,
                  onToggle: () {},
                ),
              ),
              scale: 1.5,
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final text = tester.widget<Text>(find.text(title));
          expect(text.maxLines, isNull);
          expect(text.overflow, isNull);
          final titleRect = tester.getRect(find.text(title));
          expect(titleRect.height, greaterThan(60));
          final cardRect = tester.getRect(find.byType(Card));
          expect(titleRect.left, greaterThanOrEqualTo(cardRect.left));
          expect(titleRect.right, lessThanOrEqualTo(cardRect.right));
          expect(cardRect.right, lessThanOrEqualTo(320));
          final badgeLabel = locale.languageCode == 'zh'
              ? '等待确认'
              : 'Awaiting confirmation';
          final actionLabel = locale.languageCode == 'zh'
              ? (expanded ? '收起计划' : '查看完整计划')
              : (expanded ? 'Collapse plan' : 'View full plan');
          final badgeRect = tester.getRect(
            find
                .ancestor(
                  of: find.text(badgeLabel),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          final actionRect = tester.getRect(find.text(actionLabel));
          expect(badgeRect.left, titleRect.left);
          expect(actionRect.left, titleRect.left);
          expect(actionRect.top, greaterThanOrEqualTo(badgeRect.bottom));
          for (final label in [badgeLabel, actionLabel]) {
            final labelText = tester.widget<Text>(find.text(label));
            expect(labelText.maxLines, isNull);
            expect(labelText.overflow, isNull);
            expect(
              tester.getRect(find.text(label)).right,
              lessThanOrEqualTo(cardRect.right - 16),
            );
          }
        }
      },
    );
  }
}
