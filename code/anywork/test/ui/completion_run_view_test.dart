import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_feed_projection.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_clock.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_resting_cat.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_writing_indicator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets(
      'rebuilding a sealed work group preserves disclosure and retires it on collapse ($language)',
      (tester) async {
        final message = timelineFeedMessage(_work('first'));
        var built = 0;
        var retired = 0;
        Widget display() {
          return MaterialApp(
            locale: Locale(language),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChatItemView(
                key: ValueKey(message.id),
                item: chatItemPresentationOf(message)!,
                groupMembersBuilder: (_) {
                  built++;
                  return _Body(onDispose: () => retired++);
                },
              ),
            ),
          );
        }

        await tester.pumpWidget(display());
        expect(find.text(_runTitle(tester)), findsOneWidget);
        expect(find.byType(TimelineActivityIndicator), findsNothing);
        expect(find.byType(TimelineRestingCat), findsNothing);
        expect(find.byType(TimelineWritingIndicator), findsNothing);
        expect(built, 0);
        expect(find.byType(_Body), findsNothing);
        await tester.tap(find.text(_runTitle(tester)));
        await tester.pumpAndSettle();
        expect(find.text('成员正文'), findsOneWidget);
        final first = tester.element(find.byType(_Body));
        final unit = chatItemPresentationOf(message)!.displayUnit!;
        final token = unit.expansion.bodyGeneration;
        await tester.pumpWidget(display());
        expect(find.text(_runTitle(tester)), findsOneWidget);
        expect(find.byType(TimelineActivityIndicator), findsNothing);
        expect(tester.element(find.byType(_Body)), same(first));
        expect(unit.expansion.bodyGeneration, same(token));
        expect(retired, 0);
        await tester.tap(find.text(_runTitle(tester)));
        // Eligibility is revoked in the tap callback, before the closing animation.
        expect(unit.expansion.bodyActive, isFalse);
        await tester.pumpAndSettle();
        expect(find.byType(_Body), findsNothing);
        expect(retired, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'collapsed Work timing requires zero unrequested member reads ($language)',
      (tester) async {
        final message = timelineFeedMessage(_work('first'));
        var reads = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChatItemView(
                item: chatItemPresentationOf(message)!,
                groupMembersBuilder: (_) {
                  reads++;
                  return const Text('仅在展开后读取');
                },
              ),
            ),
          ),
        );
        expect(find.text(_runTitle(tester)), findsOneWidget);
        expect(reads, 0);
        expect(find.textContaining('失败'), findsNothing);
        expect(find.textContaining('思考'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

TimelineWorkGroup _work(String id) => TimelineWorkGroup(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  memberCount: 1,
  summary: '',
  status: WorkGroupStatus.completed,
  startedAtMs: 0,
  finishedAtMs: 1000,
);

String _runTitle(WidgetTester tester) => activityDurationLabel(
  tester.element(find.byType(Scaffold)),
  1,
  kind: ActivityDurationKind.worked,
);

class _Body extends StatefulWidget {
  const _Body({required this.onDispose});
  final VoidCallback onDispose;
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  @override
  Widget build(BuildContext context) => const Text('成员正文');
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
