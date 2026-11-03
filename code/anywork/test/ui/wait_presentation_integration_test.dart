import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final terminal in [
    ThreadWaitStateView.ready,
    ThreadWaitStateView.timedOut,
    ThreadWaitStateView.cancelled,
  ]) {
    testWidgets(
      'Waiting to $terminal preserves disclosure and task identity in a narrow scroll view',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(640, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const identity = 'original-wait-call';
        const taskId = 'task:original-sleep-call';
        final input = ValueNotifier(
          ThreadWaitPresentationView(
            state: ThreadWaitStateView.waiting,
            intent: ThreadWaitEventsIntentView(
              targets: const [
                ThreadWaitTargetView(
                  taskId: taskId,
                  toolName: 'sleep',
                  summary: '原始计时任务；等待结束不等于取消该任务',
                  status: ThreadWaitTargetStatusView.running,
                ),
              ],
              timeoutMs: 5000,
            ),
          ),
        );
        addTearDown(input.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(640, 600),
                textScaler: const TextScaler.linear(1.5),
                disableAnimations: terminal == ThreadWaitStateView.cancelled,
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 500),
                      ValueListenableBuilder(
                        valueListenable: input,
                        builder: (_, value, _) => TimelineWaitPanel(
                          identity: identity,
                          presentation: value,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final card = find.byKey(StudioDriverKeys.waitingCard(identity));
        final header = find
            .descendant(of: card, matching: find.byType(ListTile))
            .first;
        await tester.ensureVisible(header);
        await tester.tap(header);
        // Waiting has an intentional infinite pulse. Pump only the finite
        // disclosure animation; never use frame settling as business readiness.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(StudioDriverKeys.waitingDetails(identity)),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TimelineActivityRow>(
                find
                    .descendant(
                      of: card,
                      matching: find.byType(TimelineActivityRow),
                    )
                    .first,
              )
              .expanded,
          isTrue,
        );
        final originalIntent = input.value.intent;
        input.value = ThreadWaitPresentationView(
          state: terminal,
          intent: originalIntent,
          messagesReady: terminal == ThreadWaitStateView.ready,
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('timeline-wait-pulse')), findsNothing);
        final details = tester.widget<TimelineWaitDetails>(
          find.byType(TimelineWaitDetails),
        );
        expect(details.identity, identity);
        expect(details.presentation.state, terminal);
        expect(details.presentation.intent, same(originalIntent));
        final diagnostics = find.byKey(
          StudioDriverKeys.waitingDiagnostics(identity),
        );
        final diagnosticsHeader = find
            .descendant(of: diagnostics, matching: find.byType(ListTile))
            .first;
        await tester.ensureVisible(diagnosticsHeader);
        await tester.tap(diagnosticsHeader);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final raw = find.descendant(
          of: diagnostics,
          matching: find.byType(SelectableText),
        );
        expect(tester.widget<SelectableText>(raw).data, contains(taskId));
        expect(tester.takeException(), isNull);
        final bounds = tester.getRect(card);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(640));
        await tester.ensureVisible(header);
        await tester.tap(header);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester
              .widget<TimelineActivityRow>(find.byType(TimelineActivityRow))
              .expanded,
          isFalse,
        );
        expect(
          find.byKey(StudioDriverKeys.waitingDetails(identity)).hitTestable(),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
