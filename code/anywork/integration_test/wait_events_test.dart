import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_feed_projection.dart';
import 'package:anywork/src/features/conversation/timeline/tools/support/tool_detail_panel.dart';
import 'package:anywork/src/features/conversation/timeline/tools/support/tool_detail_values.dart';
import 'package:anywork/src/features/conversation/timeline/tools/tool_item_view.dart';
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
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // This native journey waits for real FRB/provider I/O. Let the engine draw
  // requested frames while the test yields instead of making each readiness
  // check depend on completion of a timed LiveTestWidgetsFlutterBinding pump.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
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
    await _until(
      tester,
      () {
        final selected = graph.client.selection.state.selectedThreadId;
        if (selected == null ||
            graph.client.conversations.visibleThreadId.value != selected) {
          return false;
        }
        threadId = selected;
        return true;
      },
      'selected wait Thread',
      diagnostic: () {
        final selected = graph.client.selection.state.selectedThreadId;
        final state = selected == null
            ? null
            : graph.client.conversations.sessionState(selected);
        return 'selected=$selected visible=${graph.client.conversations.visibleThreadId.value} '
            'sync=${state?.sync.phase.name} error=${state?.sync.errorMessage} '
            'active=${state?.activeTurn?.turnId} last=${state?.lastTurn?.turnId}';
      },
    );
    debugPrint('wait-events: waiting for canonical completed Turn');
    final completed = await tester.runAsync(
      () => waitForCompletedTurn(
        feeds: graph.client.transport,
        threadId: threadId!,
        matches: (head) =>
            head.inputId != null &&
            (threadId != priorThreadId || head.turnId != priorTurnId),
        description: 'canonical completed wait Turn',
        timeout: const Duration(minutes: 2),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(completed, isNotNull);
    expect(completed!.inputId, isNotNull);
    bool isObservedWait(WorkGroupMember member) {
      if (member is! WorkGroupToolCall ||
          member.toolName != 'wait' ||
          member.turnId != completed.turnId) {
        return false;
      }
      // The fixture executes two wait calls in this Turn. Select the events
      // wait with both targets through the production payload reader, then
      // use its callId for every subsequent identity assertion.
      final card = timelineFeedMember(member).toolCard;
      return card is DecodedToolCard &&
          switch (card.value.wait?.intent) {
            ThreadWaitEventsIntentView(:final targets) => targets.length == 2,
            _ => false,
          };
    }

    await _until(
      tester,
      () => graph.timeline.lease(threadId!) != null,
      'timeline for the completed wait Turn',
    );

    final lease = graph.timeline.lease(threadId!)!;
    final observed = TimelineObservation(
      tester,
      () => lease,
      idle: () => _idle(tester),
    );
    await _until(
      tester,
      () => observed.main.whereType<TimelineWorkGroup>().isNotEmpty,
      'historical Work row',
    );
    TimelineWorkGroup? matchingWork;
    WorkGroupToolCall? historicalWait;
    for (final candidate in observed.main.whereType<TimelineWorkGroup>()) {
      final members = await lease.loadWorkGroupMembers(candidate);
      final waits = members
          .whereType<WorkGroupToolCall>()
          .where(isObservedWait)
          .toList();
      expect(waits.length, lessThanOrEqualTo(1));
      if (waits.isNotEmpty) {
        historicalWait = waits.single;
        matchingWork = candidate;
      }
      if (matchingWork != null) break;
    }
    expect(
      matchingWork,
      isNotNull,
      reason: 'The completed wait belongs to its original Work',
    );
    final work = matchingWork!;
    final header = find.byKey(ValueKey('completion-run-header:${work.id}'));
    await observed.reveal(header, work.id);
    await observed.tap(header);

    await _until(
      tester,
      () => observed.mountedMembers.whereType<WorkGroupToolCall>().any(
        (member) => member.callId == historicalWait!.callId,
      ),
      'historical wait tool member',
    );
    late TimelineToolItemView panel;
    late ChatItemPresentation waitItem;
    await _until(tester, () {
      final matches = tester
          .widgetList<TimelineToolItemView>(find.byType(TimelineToolItemView))
          .where((value) => value.item.toolCallId == historicalWait!.callId)
          .toList();
      if (matches.length != 1) return false;
      panel = matches.single;
      waitItem = tester
          .widget<ChatItemView>(observed.itemRow(panel.item.id))
          .item;
      expect(waitItem.turnId, completed.turnId);
      expect(waitItem.toolCallId, historicalWait!.callId);
      return waitItem.compatibility == ChatItemCompatibility.current;
    }, 'wait tool canonical original');
    final original = historicalWait!;
    final mounted = observed.mountedMembers
        .whereType<WorkGroupToolCall>()
        .singleWhere((member) => member.callId == original.callId);
    expect(isObservedWait(mounted), isTrue);
    expect(mounted, original);
    expect(waitItem.id, original.id);
    expect(waitItem.raw, original.payloadJson);
    final payload = jsonDecode(original.payloadJson) as Map<String, Object?>;
    final meta = payload['meta'] as Map<String, Object?>;
    expect(meta['state'], {'kind': 'knownTerminal', 'outcome': 'completed'});
    expect(panel.item.wait!.state, ThreadWaitStateView.ready);
    final resultReference = original.bodies.singleWhere(
      (body) => body.bodyKey == 'tool.result',
    );
    expect(waitItem.body('tool.result')!.feedReference, resultReference);
    final card = find.byKey(StudioDriverKeys.waitingCard(panel.item.id));
    await observed.tap(card);
    await observed.until(
      () => find
          .byKey(StudioDriverKeys.waitingDetails(panel.item.id))
          .evaluate()
          .isNotEmpty,
      'wait details visible',
    );
    final details = tester.widget<TimelineWaitDetails>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TimelineWaitDetails && widget.identity == panel.item.id,
      ),
    );
    expect(details.presentation.state, ThreadWaitStateView.ready);
    expect(
      (details.presentation.intent as ThreadWaitEventsIntentView).targets,
      hasLength(2),
    );
    final diagnostics = find.byKey(
      StudioDriverKeys.waitingDiagnostics(panel.item.id),
    );
    await observed.tap(diagnostics);
    String? rawResult;
    await _until(tester, () {
      for (final view in tester.widgetList<TimelineContentRangeView>(
        find.descendant(
          of: diagnostics,
          matching: find.byType(TimelineContentRangeView),
        ),
      )) {
        final window = view.window;
        final text =
            window?.text ??
            (window?.bytesBase64 == null
                ? null
                : utf8.decode(base64Decode(window!.bytesBase64!)));
        if (view.contentKey == 'tool.result' &&
            text != null &&
            text.isNotEmpty) {
          rawResult = text;
          return true;
        }
      }
      final semanticBodies = tester
          .widgetList<TimelineToolSemanticBody>(
            find.descendant(
              of: diagnostics,
              matching: find.byType(TimelineToolSemanticBody),
            ),
          )
          .toList();
      if (panel.item.output.isNotEmpty &&
          semanticBodies.isNotEmpty &&
          semanticBodies.every(
            (body) =>
                body.values.isNotEmpty &&
                !body.values.any((value) => value is ToolDetailUnavailable),
          )) {
        rawResult = panel.item.output;
        return true;
      }
      return false;
    }, 'historical tool result');
    final result = jsonDecode(rawResult!) as Map;
    expect(result['timedOut'], isFalse);
    expect(result['messagesReady'], panel.item.wait!.messagesReady);

    expect(completed.state.status, StudioTurnStatus.completed);
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
  String Function()? diagnostic,
}) async {
  debugPrint('wait-events: waiting for $description');
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed >= timeout) {
      fail('Timed out waiting for $description; ${diagnostic?.call() ?? ''}');
    }
    await _idle(tester);
    expect(tester.takeException(), isNull);
  }
  debugPrint('wait-events: observed $description');
}

Future<void> _idle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
}
