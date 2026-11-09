import 'dart:async';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/completion_run_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/completion_fixtures.dart';
import '../support/display_fixtures.dart';

void main() {
  testWidgets(
    'expanded live block moves to history without reopening its bounded member demand',
    (tester) async {
      final intent = TimelineExpansionIntent()..expanded = true;
      final native = _Members();
      final images = TimelineImageResources(threadId: 'thread');
      var opens = 0;
      intent.openDisplayMembers = (reference, window, demand) async {
        expect(
          reference,
          const DisplayBlockRef(databaseId: 'db', blockId: 'work'),
        );
        expect(window, isA<LatestDisplayMembers>());
        expect(demand.maxItems, lessThan(10000));
        opens++;
        return native;
      };
      final body = displayWork('work', 1, total: 10000).body;
      final live = TimelineDisplayUnit.live(
        block: LiveDisplayBlock(
          id: 'work',
          blockOrder: 1,
          body: body,
          closing: false,
        ),
        executionPresent: true,
        expansion: intent,
      );
      final content = _Content();
      Widget host(TimelineDisplayUnit unit, String parent) => MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: KeyedSubtree(
            key: ValueKey(parent),
            child: TimelineDisplayUnitView(
              unit: unit,
              childBuilder: (_) => CompletionRunConnector(
                unit: unit,
                threadId: 'thread',
                content: content,
                images: images,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(live, 'live'));
      await tester.pump();
      native.page.complete(
        DisplayMemberPage(
          block: const DisplayBlockRef(databaseId: 'db', blockId: 'work'),
          revision: 1,
          sealed: false,
          entries: [
            DisplayMemberHead(
              memberKey: 'member-key',
              memberOrder: 500,
              atom: completionEntry(
                'member',
                1,
                presentation: MainPresentation.single,
                text: '已完成成员仍在组内',
              ).atom,
              completionId: 'member',
            ),
          ],
          before: 500,
        ),
      );
      await tester.pump();
      expect(find.text('已完成成员仍在组内'), findsOneWidget);
      expect(find.text('更早成员'), findsOneWidget);
      final demand = intent.members;
      final history = TimelineDisplayUnit(
        block: DisplayBlock(id: 'work', historyPos: 1, body: body),
        expansion: intent,
      );
      await tester.pumpWidget(host(history, 'history'));
      await tester.pump();
      expect(intent.members, same(demand));
      expect(intent.expanded, isTrue);
      expect(opens, 1);
      expect(native.requested, isFalse);
      expect(find.text('已完成成员仍在组内'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('completion-run-header:work')),
      );
      expect(
        native.requested,
        isTrue,
        reason: 'fold revokes this demand before animation',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox.shrink());
      intent.retire();
      images.release();
    },
  );
}

class _Content extends Fake implements ConversationContent {}

class _Members implements DisplayMembers {
  final page = Completer<DisplayMemberPage?>();
  final changed = Completer<DisplayMemberPage?>();
  int calls = 0;
  bool requested = false;
  @override
  Future<DisplayMemberPage?> next() =>
      calls++ == 0 ? page.future : changed.future;
  @override
  void requestClose() {
    requested = true;
    if (calls > 1 && !changed.isCompleted) {
      changed.completeError(const StaleConversationScope());
    }
  }

  @override
  Future<void> close() async {}
}
