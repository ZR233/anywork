import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineDisplayUnit group({required bool live, String? before}) =>
    TimelineDisplayUnit(
      id: 'G',
      source: const ForegroundTurnChatSource(turnId: 'T'),
      kind: TimelineUnitKind.work,
      members: [
        ChatAtom(
          id: 'thought',
          source: const ForegroundTurnChatSource(turnId: 'T'),
          sourceOrder: 1,
          kind: ChatAtomKind.reasoning,
          delivery: ChatDeliveryKind.foreground,
          lifecycle: const TerminalChatAtom(
            started: null,
            ended: null,
            outcome: ChatTerminalOutcome.completed,
          ),
          contents: const [],
        ),
      ],
      live: live,
      closedForAdmission: !live,
      memberCount: 1,
      activeCount: 0,
      sourceLifecycle: live
          ? const ActiveChatSource()
          : const EndedChatSource(outcome: ChatTerminalOutcome.completed),
      failedCount: 0,
      stoppedCount: 0,
      olderCursor: before,
    );
Widget host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
void main() {
  testWidgets(
    'group-idle to text handoff rebuilds a shared intent without locked-tree errors',
    (tester) async {
      final controller = InMemoryChatController();
      final images = TimelineImageResources(threadId: 'T');
      var reads = 0;
      var bodyCloses = 0;
      final closePhases = <SchedulerPhase>[];
      final owner = TimelineMessageController(
        controller,
        generation: 3,
        imageResources: images,
        displayDemand: const ReadDemand(maxItems: 4, maxBytes: 32768),
        onUnitCreated: (unit) {
          unit.expansion.readEarlier = () async {
            reads++;
          };
          unit.expansion.retireBody = () {
            expect(unit.expansion.bodyActive, isFalse);
            bodyCloses++;
            closePhases.add(tester.binding.schedulerPhase);
          };
        },
      );
      addTearDown(() {
        owner.dispose();
        images.release();
        controller.dispose();
      });
      const source = ForegroundTurnChatSource(turnId: 'T');
      ChatAtom atom(int order, {bool complete = false, bool text = false}) =>
          ChatAtom(
            id: 'part-$order',
            completionItemId: complete ? 'payload-$order' : null,
            completionSeq: complete ? order : null,
            source: source,
            sourceOrder: order * 10,
            sourceState: const ChatSourceState(
              source: source,
              lifecycle: ActiveChatSource(),
              started: null,
              ended: null,
            ),
            kind: text ? ChatAtomKind.text : ChatAtomKind.reasoning,
            delivery: ChatDeliveryKind.foreground,
            contents: const [],
            lifecycle: complete
                ? const TerminalChatAtom(
                    started: null,
                    ended: null,
                    outcome: ChatTerminalOutcome.completed,
                  )
                : const ActiveChatAtom(
                    started: null,
                    status: ChatActiveStatus.running,
                  ),
          );
      await owner.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          before: 'H0',
          entries: const [],
        ),
      );
      for (var order = 1; order <= 4; order++) {
        await owner.applyBatch(
          ChatBatch(
            placement: ChatPlacement.append,
            entries: [ChatAtomEntry(atom(order))],
          ),
        );
        await owner.applyBatch(
          ChatBatch(
            placement: ChatPlacement.append,
            entries: [ChatAtomEntry(atom(order, complete: true))],
          ),
        );
      }
      final idle = owner.live.value.single;
      expect((idle.memberCount, idle.activeCount), (4, 0));
      expect(controller.messages, isEmpty);
      final intent = idle.expansion;
      final capturedErrors = <FlutterErrorDetails>[];
      final previousErrorHandler = FlutterError.onError!;
      FlutterError.onError = (details) {
        capturedErrors.add(details);
        debugPrint(
          'HANDOFF_ERROR phase=${tester.binding.schedulerPhase}\\n${details.exception}\\n${details.stack}',
        );
        previousErrorHandler(
          details,
        ); // Preserve the runner's real failure handling.
      };
      addTearDown(() {
        FlutterError.onError = previousErrorHandler;
      });
      Widget row(TimelineDisplayUnit unit) => TimelineDisplayUnitView(
        key: ValueKey(unit.id),
        unit: unit,
        memberBuilder: (atom) => Text('body:${atom.id}'),
      );
      await tester.pumpWidget(
        host(
          ValueListenableBuilder<List<TimelineDisplayUnit>>(
            valueListenable: owner.live,
            builder: (context, live, child) => Column(
              children: [
                Column(
                  key: const ValueKey('history-surface'),
                  children: [
                    for (final message in controller.messages)
                      row(
                        message.metadata![timelineDisplayUnitKey]
                            as TimelineDisplayUnit,
                      ),
                  ],
                ),
                Column(
                  key: const ValueKey('live-surface'),
                  children: live.map(row).toList(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(intent.bodyActive, isTrue);
      expect(
        intent.expanded,
        isNull,
        reason: 'Live initially opens without a user expansion intent',
      );
      final originalGeneration = intent.bodyGeneration;
      await owner.applyBatch(
        ChatBatch(
          placement: ChatPlacement.append,
          entries: [ChatAtomEntry(atom(5, text: true))],
        ),
      );
      final history =
          controller.messages.single.metadata![timelineDisplayUnitKey]
              as TimelineDisplayUnit;
      expect(history.id, idle.id);
      expect(history.expansion, same(intent));
      expect(history.live, isFalse);
      await tester.pump();
      final handoffException = tester.takeException();
      expect(handoffException, isNull);
      expect(capturedErrors, isEmpty);
      expect(bodyCloses, 1);
      expect(closePhases.single, SchedulerPhase.persistentCallbacks);
      expect(intent.bodyActive, isFalse);
      expect(intent.bodyGeneration, isNot(same(originalGeneration)));
      expect(intent.isRetired, isFalse);
      expect(reads, 0);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'No recurring rebuild or post-frame polling',
      );
      expect(find.byKey(ValueKey(idle.id)), findsOneWidget);
      expect(find.text('body:part-1'), findsNothing);
      await tester.tap(find.byKey(ValueKey('source-unit-header:${idle.id}')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(intent.expanded, isTrue);
      expect(intent.bodyActive, isTrue);
      expect(find.text('body:part-1'), findsOneWidget);
      intent.retire();
      expect(intent.bodyActive, isFalse);
      expect(
        bodyCloses,
        2,
        reason: 'Permanent retirement still revokes resources synchronously',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(reads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'same compact component: live opens thinking, history folds with unknown duration',
    (tester) async {
      await tester.pumpWidget(
        host(
          TimelineDisplayUnitView(
            unit: group(live: true),
            memberBuilder: (_) => const Text('actual reasoning'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('思考中'), findsOneWidget);
      expect(find.text('actual reasoning'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        host(
          TimelineDisplayUnitView(
            unit: group(live: false),
            memberBuilder: (_) => const Text('actual reasoning'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('工作记录'), findsOneWidget);
      expect(find.text('actual reasoning'), findsNothing);
      expect(find.textContaining('0 秒'), findsNothing);
      await tester.tap(find.text('工作记录'));
      await tester.pumpAndSettle();
      expect(find.text('actual reasoning'), findsOneWidget);
    },
  );
  testWidgets(
    'explicit fold intent survives live to history without a new group identity',
    (tester) async {
      final live = group(live: true);
      await tester.pumpWidget(
        host(
          TimelineDisplayUnitView(
            unit: live,
            memberBuilder: (_) => const Text('reasoning'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('思考中'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(live.expansion.expanded, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        host(
          TimelineDisplayUnitView(
            unit: live.copy(live: false),
            memberBuilder: (_) => const Text('reasoning'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('reasoning'), findsNothing);
      expect(live.id, 'G');
    },
  );
  testWidgets(
    'ordinary page request is explicit and single-flight, never a hidden full-group read',
    (tester) async {
      var reads = 0;
      await tester.pumpWidget(
        host(
          TimelineDisplayUnitView(
            unit: group(live: false, before: 'opaque-observed-cursor'),
            memberBuilder: (_) => const Text('reasoning'),
            onLoadEarlier: () async {
              reads++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 0);
      await tester.tap(find.text('工作记录'));
      await tester.pumpAndSettle();
      expect(reads, 0);
      await tester.tap(find.text('读取更早过程'));
      await tester.pumpAndSettle();
      expect(reads, 1);
    },
  );
}
