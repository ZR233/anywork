import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_content_range_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

import 'support/history_turns.dart';
import 'support/timeline_observation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('real wait tool reaches visible history and closes normally', (
    tester,
  ) async {
    final projects = Platform.environment['ANYWORK_WAIT_PROJECTS'];
    expect(
      projects,
      isNotNull,
      reason: 'Use cargo xtask test-project --suite desktop --case wait_events',
    );
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final graph = createProductionAppGraph();
    final container = ProviderContainer(
      overrides: [
        appGraphProvider.overrideWithValue(graph),
        statisticsRepositoryProvider.overrideWithValue(
          graph.statisticsRepository,
        ),
      ],
    );
    var shutdownComplete = false;
    addTearDown(() async {
      if (shutdownComplete) return;
      await tester.pumpWidget(const SizedBox.shrink());
      await graph.close(budget: ClientCloseBudget(const Duration(seconds: 10)));
      container.dispose();
    });

    await graph.initialize();
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AnyworkApp(enableDesktopHost: false),
      ),
    );
    graph.setConversationPageVisible(true);
    await graph.client.directoryCommands.openProject(
      path.join(projects!, 'sleep-first'),
    );

    await _until(tester, () {
      final selection = graph.client.selection.state;
      final composer = tester
          .widgetList<PromptComposerView>(find.byType(PromptComposerView))
          .where((widget) => widget.state.enabled)
          .where(
            (widget) => switch (widget.targetKey) {
              StartComposerTarget(:final workspaceId) =>
                workspaceId == selection.selectedProjectId,
              ThreadComposerTarget(:final threadId) =>
                threadId == selection.selectedThreadId,
              _ => false,
            },
          );
      return !selection.needsOpen && composer.length == 1;
    }, 'production composer');
    final input = find.byKey(const ValueKey('composer-input'));
    await tester.enterText(input, '[[wait_sleep_first]]');
    await tester.pump();
    expect(
      tester.widget<TextField>(input).controller!.text,
      '[[wait_sleep_first]]',
    );
    final priorThreadId = graph.client.selection.state.selectedThreadId;
    final priorTurnId = priorThreadId == null
        ? null
        : graph.client.conversations
              .session(priorThreadId)
              .state
              .lastTurn
              ?.turnId;
    await tester.tap(find.byKey(StudioDriverKeys.composerSubmit));

    String? threadId;
    await _until(tester, () {
      final selected = graph.client.selection.state.selectedThreadId;
      if (selected == null ||
          graph.client.conversations.visibleThreadId.value != selected) {
        return false;
      }
      threadId = selected;
      return true;
    }, 'selected wait Thread');
    final completed = await waitForCompletedHistoryTurn(
      conversations: graph.client.conversations,
      threadId: threadId!,
      matches: (head) =>
          head.inputId != null &&
          (threadId != priorThreadId || head.turnId != priorTurnId),
      description: 'completed wait Turn in History',
      timeout: const Duration(minutes: 2),
    );
    expect(completed.inputId, isNotNull);
    bool isObservedWait(ChatAtom? atom) =>
        atom?.tool?.name == 'wait' &&
        atom?.source == ForegroundTurnChatSource(turnId: completed.turnId) &&
        switch (atom?.wait?.intent) {
          ThreadWaitEventsIntentView(:final targets) => targets.length == 2,
          _ => false,
        };
    await _until(
      tester,
      () => graph.timeline.lease(threadId!) != null,
      'timeline for the completed wait Turn',
    );

    final lease = graph.timeline.lease(threadId!)!;
    expect(lease.history.threadId, threadId);
    expect(lease.current.threadId, threadId);
    expect(
      lease.history.metadata.readerId,
      isNot(lease.current.metadata.readerId),
    );
    final observed = TimelineObservation(tester, () => lease);
    await _until(
      tester,
      () => observed.main.any((unit) => unit.body is WorkDisplayBlock),
      'historical Work row',
    );
    final work = observed.main.firstWhere(
      (unit) => unit.body is WorkDisplayBlock,
    );
    final header = find.byKey(ValueKey('completion-run-header:${work.id}'));
    await observed.until(
      () => header.hitTestable().evaluate().length == 1,
      'hittable Work header',
    );
    await tester.tap(header);
    await tester.pump();

    await _until(
      tester,
      () => observed.mountedMembers.any(isObservedWait),
      'historical wait tool member',
    );
    final atom = observed.mountedMembers.singleWhere(isObservedWait);
    expect(atom.wait?.state, ThreadWaitStateView.ready);
    expect(atom.lifecycle, isA<TerminalChatAtom>());

    late ChatItemPresentation waitItem;
    await _until(tester, () {
      final matches = tester
          .widgetList<ChatItemView>(find.byType(ChatItemView))
          .where((view) => isObservedWait(view.item.atom))
          .toList();
      if (matches.length != 1) return false;
      waitItem = matches.single.item;
      return waitItem.compatibility == ChatItemCompatibility.current;
    }, 'wait tool canonical original');
    expect(waitItem.displayRecord?.contentSource, isA<CompletedOriginal>());
    final toolRow = find.byWidgetPredicate(
      (widget) => widget is ChatItemView && isObservedWait(widget.item.atom),
    );

    final panel = tester
        .widgetList<TimelineWaitPanel>(find.byType(TimelineWaitPanel))
        .singleWhere(
          (value) =>
              value.presentation.intent is ThreadWaitEventsIntentView &&
              value.presentation.state == ThreadWaitStateView.ready,
        );
    expect(panel.presentation.messagesReady, isFalse);
    final card = find.byKey(StudioDriverKeys.waitingCard(panel.identity));
    await observed.tap(card);
    await observed.until(
      () => find
          .byKey(StudioDriverKeys.waitingDetails(panel.identity))
          .evaluate()
          .isNotEmpty,
      'wait details visible',
    );
    final details = tester.widget<TimelineWaitDetails>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TimelineWaitDetails && widget.identity == panel.identity,
      ),
    );
    expect(details.presentation.state, ThreadWaitStateView.ready);
    expect(
      (details.presentation.intent as ThreadWaitEventsIntentView).targets,
      isNotEmpty,
    );
    TimelineContentRangeView? resultWindow;
    await _until(tester, () {
      for (final view in tester.widgetList<TimelineContentRangeView>(
        find.descendant(
          of: toolRow,
          matching: find.byType(TimelineContentRangeView),
        ),
      )) {
        if (view.contentKey == 'tool.result' &&
            (view.window?.bytes.isNotEmpty ?? false)) {
          resultWindow = view;
          return true;
        }
      }
      return false;
    }, 'historical tool result window');
    final result = jsonDecode(utf8.decode(resultWindow!.window!.bytes)) as Map;
    expect(result['timedOut'], isFalse);
    expect(result['tasks'], isA<List>());

    expect(completed.state, HistoryTurnState.completed);
    graph.setConversationPageVisible(false);
    await tester.pumpWidget(const SizedBox.shrink());
    await _until(tester, () => lease.isReleased, 'timeline released');
    final shutdown = await runStudioShutdown(
      graph.client.transport,
      (_) {},
      remainingMs: 30000,
      closeClient: (budget) => graph.close(budget: budget),
      closeRoot: graph.closeLifecycleRoot,
    );
    expect(shutdown.shutdown.isClean, isTrue);
    expect(shutdown.shutdown.issues, isEmpty);
    expect(
      shutdown.shutdown.persistence,
      isA<DrainedStudioPendingPersistence>(),
    );
    shutdownComplete = true;
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String description, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed >= timeout) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  }
}
