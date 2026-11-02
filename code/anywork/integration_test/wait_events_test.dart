import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_children_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Real AppGraph/FRB/SQLite and production routes. Only the native exit shell is
// omitted: the official test runner, not StudioExitCoordinator, owns this process.
// No driver_main, requestData protocol, copied timeline, or synthetic business state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  late AppGraph graph;
  late ProviderContainer container;
  final projectRoot = Platform.environment['ANYWORK_WAIT_PROJECTS'];

  setUpAll(() async {
    expect(
      projectRoot,
      isNotNull,
      reason: 'Use manual-gui --scenario wait-events',
    );
    graph = createProductionAppGraph();
    container = ProviderContainer(
      overrides: [
        appGraphProvider.overrideWithValue(graph),
        statisticsRepositoryProvider.overrideWithValue(
          graph.statisticsRepository,
        ),
      ],
    );
    await graph.initialize();
  });
  tearDownAll(() async {
    try {
      final report = await runStudioShutdown(
        graph.client.transport,
        (_) {},
        remainingMs: 30000,
        closeClient: (deadline) => graph.close(deadline: deadline),
      );
      expect(report.shutdown.isClean, isTrue);
      expect(report.shutdown.issues, isEmpty);
      expect(
        report.shutdown.persistence,
        isA<DrainedStudioPendingPersistence>(),
      );
    } finally {
      container.dispose();
    }
  });

  Future<_Scene> open(WidgetTester tester, String name) async {
    final router = createApplicationRouter();
    // This suite tests Waiting, not native IME compatibility. The SDK warns
    // that enterText and a real IME can overwrite each other's editing state.
    // Use its standard keyboard for the entire scene, before any field mounts.
    tester.testTextInput.register();
    final testErrorHandler = FlutterError.onError!;
    FlutterError.onError = (details) {
      // Keep the framework's full creator/constraint diagnostics as well as its
      // ordinary test failure; takeException alone only retains the exception.
      debugPrintSynchronously(details.toString());
      testErrorHandler(details);
    };
    graph.setConversationPageVisible(true);
    addTearDown(() async {
      try {
        graph.setConversationPageVisible(false);
        await tester.pumpWidget(const SizedBox());
        await _Scene(tester, graph).until(
          () => graph.client.budget.used(ResourceKind.chatHandle) == 0,
          'retired scene read handles joined',
        );
      } finally {
        tester.testTextInput.unregister();
        router.dispose();
        FlutterError.onError = testErrorHandler;
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: pureStudioTheme(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await graph.client.directoryCommands.openProject('$projectRoot/$name');
    return _Scene(tester, graph);
  }

  for (final (name, prefix, completedName, runningName) in const [
    ('sleep-first', 'sleep-first-wait-t', 'sleep', 'exec'),
    ('tool-first', 'tool-first-wait-t', 'exec', 'sleep'),
  ]) {
    testWidgets('$name: immutable any-of result reaches the real history UI', (
      tester,
    ) async {
      final scene = await open(tester, name);
      await scene.submit('[[wait_${name.replaceAll('-', '_')}]]');
      final children = await scene.completedTurn();
      final wait = scene.tool(children, prefix);
      final result = scene.result(wait);
      expect(result['timedOut'], isFalse);
      final tasks = (result['tasks'] as List).cast<Map<String, dynamic>>();
      expect(tasks, hasLength(2));
      final completed = tasks.singleWhere((t) => t['toolId'] == completedName);
      final running = tasks.singleWhere((t) => t['toolId'] == runningName);
      expect(completed['status'], 'succeeded');
      expect(running['status'], 'running');
      expect(running['cancelRequested'], isFalse);
      expect(completed['taskId'], isNot(running['taskId']));
      expect(wait.presentationContract, 'builtin.wait@1');
      // A later UI read verifies the original immutable result, not whether
      // the model is still running. Early-return proof belongs to Core barriers.
      await scene.expandWait(wait, ThreadWaitStateView.ready);

      if (name == 'sleep-first') {
        final previous = scene.latestTurnId;
        await scene.closeTurn(children);
        await scene.submit('[[wait_already_ready]]');
        final ready = await scene.completedTurn(after: previous);
        expect(
          scene.result(scene.tool(ready, 'already-ready-wait-t'))['timedOut'],
          isFalse,
        );
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }

  testWidgets('timeout is rendered from the result, not inferred from EOF', (
    tester,
  ) async {
    final scene = await open(tester, 'timeout');
    await scene.submit('[[wait_timeout]]');
    final children = await scene.completedTurn();
    final wait = scene.tool(children, 'timeout-wait-t');
    final result = scene.result(wait);
    expect(result['timedOut'], isTrue);
    final target = (result['tasks'] as List).single as Map;
    expect(target['status'], 'running');
    expect(target['cancelRequested'], isFalse);
    await scene.expandWait(wait, ThreadWaitStateView.timedOut);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('child wakes parent; a later request retains one report', (
    tester,
  ) async {
    final scene = await open(tester, 'child');
    await scene.submit('[[wait_child]]');
    final children = await scene.completedTurn();
    final result = scene.result(scene.tool(children, 'child-wait-t'));
    expect(result['messagesReady'], isTrue);
    final previous = scene.latestTurnId;
    await scene.closeTurn(children);
    await scene.submit('[[wait_child_confirm]]');
    await scene.waitForTurn(after: previous);
    // The fixture validates the real parent provider context and report identity;
    // its strict request failures are propagated by the Rust harness.
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('stop cancels Waiting but leaves the previous Turn timer alive', (
    tester,
  ) async {
    final scene = await open(tester, 'cancel');
    await scene.submit('[[wait_cancel_prepare]]');
    final prepared = await scene.completedTurn();
    final started = scene.tool(
      prepared,
      'cancel-sleep-t',
      status: 'backgroundStarted',
    );
    final taskId = (started.data['invocation'] as Map)['taskId'];
    expect(taskId, isA<String>());
    final prepareTurn = scene.latestTurnId;
    await scene.closeTurn(prepared);
    await scene.submit('[[wait_cancel]]');
    await scene.until(
      () =>
          scene.lease.content.current.value?.active?.latestTool?.callId
              .startsWith('cancel-wait-t') ==
          true,
      'original wait call in the canonical current head',
    );
    if (scene.lease.currentDisplay?.expanded != true) {
      await scene.tap(find.byKey(StudioDriverKeys.conversationActivity));
    }
    await scene.tap(find.byKey(StudioDriverKeys.currentCollection('tools')));
    await scene.until(() {
      final tools = scene.lease.currentDisplay?.collections
          .where((c) => c.reference.collection == 'tools')
          .firstOrNull;
      if (tools?.error case final error?) throw StateError('$error');
      return tools?.page?.entries.any((entry) {
            final payload = entry.payload;
            if (payload is! InlinePayload) return false;
            final tool = jsonDecode(utf8.decode(payload.bytes)) as Map;
            return tool['name'] == 'wait' &&
                (tool['wait'] as Map?)?['state'] == 'waiting';
          }) ??
          false;
    }, 'real current Waiting');
    await scene.tap(find.byKey(const ValueKey('composer-stop')));
    final stopped = await scene.completedTurn(
      after: prepareTurn,
      outcome: 'cancelled',
    );
    expect(stopped.isCurrent, isTrue);
    final stoppedTurn = scene.latestTurnId;
    await scene.closeTurn(stopped);
    await scene.submit('[[wait_cancel_query]]');
    final queried = await scene.completedTurn(after: stoppedTurn);
    final result = scene.result(scene.tool(queried, 'cancel-query-t'));
    final task = result['task'] as Map;
    expect(task['taskId'], taskId);
    expect(task['status'], 'running');
    expect(task['cancelRequested'], isFalse);
    expect(
      scene.tool(queried, 'cancel-query-cancel-t').toolCard,
      isA<DecodedToolCard>(),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

final class _Scene {
  _Scene(this.tester, this.graph);
  final WidgetTester tester;
  final AppGraph graph;
  String? latestTurnId;

  TimelineDisplayLease get lease =>
      graph.timeline.lease(graph.client.selection.state.selectedThreadId!)!;

  Future<void> until(
    bool Function() ready,
    String description, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final clock = Stopwatch()..start();
    while (!ready()) {
      if (clock.elapsed >= timeout) {
        fail('Timed out waiting for $description');
      }
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
  }

  Future<void> tap(Finder finder) async {
    await until(() => finder.evaluate().isNotEmpty, finder.toString());
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump();
    await until(
      () => finder.hitTestable().evaluate().length == 1,
      'hittable $finder',
    );
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> submit(String prompt) async {
    final returnLive = find.byKey(StudioDriverKeys.timelineReturnLive);
    if (returnLive.hitTestable().evaluate().isNotEmpty) {
      await tap(returnLive);
    }
    final input = find.byKey(const ValueKey('composer-input'));
    await until(() => input.evaluate().isNotEmpty, 'composer');
    try {
      await tester.enterText(input, prompt);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, prompt);
      await tap(find.byKey(const ValueKey('composer-submit')));
    } catch (_) {
      final composer = tester.widget<PromptComposerView>(
        find.byType(PromptComposerView),
      );
      debugPrintSynchronously(
        'Composer submission failure: text=${tester.widget<TextField>(input).controller!.text}, '
        'draft=${composer.composer.draft}, pending=${composer.composer.isSubmissionPending}, '
        'sdkDraft=${graph.client.drafts.existingComposer(graph.client.selection.state.selectedThreadId!)?.state.draft}, '
        'execution=${composer.execution?.id}/${composer.execution?.phase}, '
        'continuation=${composer.continuation?.claimed}, '
        'stop=${composer.stopCommand?.phase}/${composer.stopCommand?.accepted}/${composer.stopCommand?.target.label}, '
        'blocker=${composer.blocker}, failure=${composer.failure}, '
        'enabled=${composer.enabled}, locked=${composer.submissionLocked}',
      );
      rethrow;
    }
  }

  Future<ChatItemPresentation> waitForTurn({
    String? after,
    String outcome = 'completed',
  }) async {
    ChatItemPresentation? turn;
    await until(() {
      final id = graph.client.selection.state.selectedThreadId;
      if (id == null) return false;
      final display = graph.timeline.lease(id);
      if (display == null) return false;
      turn = display.controller.messages
          .map(chatItemPresentationOf)
          .whereType<ChatItemPresentation>()
          .where((item) => item.type == 'turn')
          .lastOrNull;
      return turn != null && turn!.id != after;
    }, 'completed Turn');
    final original = turn!;
    latestTurnId = original.id;
    expect((original.data['outcome'] as Map)['kind'], outcome);
    return original;
  }

  Future<TimelineChildrenDisplay> completedTurn({
    String? after,
    String outcome = 'completed',
  }) async {
    final original = await waitForTurn(after: after, outcome: outcome);
    expect(original.childrenParentId, isNotNull);
    final row = find.byWidgetPredicate(
      (widget) => widget is ChatItemView && widget.item.id == original.id,
    );
    if (row.evaluate().isEmpty) {
      // The reversed production list may retain the reader's old position.
      // Materialize the already-loaded target using Flutter's real scroll API.
      await tester.scrollUntilVisible(
        row,
        -200,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              identical(widget.controller, lease.scrollController),
        ),
      );
    }
    final headers = find.descendant(of: row, matching: find.byType(ListTile));
    await until(() => headers.evaluate().isNotEmpty, 'mounted original Turn');
    final header = headers.first;
    final title = find.descendant(
      of: header,
      matching: find.byType(TimelineActivityRow),
    );
    await until(
      () => title.evaluate().isNotEmpty,
      'mounted original Turn title',
    );
    if (!tester.widget<TimelineActivityRow>(title).expanded) {
      await tap(header);
    }
    TimelineChildrenDisplay? children;
    final childWidget = find.descendant(
      of: row,
      matching: find.byType(TimelineChildrenConnector),
    );
    try {
      await until(() {
        if (childWidget.evaluate().isEmpty) return false;
        expect(childWidget, findsOneWidget);
        expect(
          tester.widget<TimelineChildrenConnector>(childWidget).parentId,
          original.childrenParentId,
        );
        children = tester.state(childWidget) as TimelineChildrenDisplay;
        if (children?.error case final error?) throw StateError('$error');
        return children?.ready == true && children?.isCurrent == true;
      }, 'original Children Set');
    } catch (_) {
      debugPrint(
        'Children failure: item=${original.id}, parent=${original.childrenParentId}, '
        'mounted=${row.evaluate().length}, '
        'builder=${tester.widget<ChatItemView>(row).childrenBuilder != null}, '
        'childWidgets=${childWidget.evaluate().length}, '
        'child=${children == null ? null : (children!.parentId, children!.ready, children!.isCurrent, children!.error)}, '
        'titles=${tester.widgetList<TimelineActivityRow>(title).map((w) => (w.label, w.expanded)).toList()}, '
        'displays=${lease.childrenDisplays.map((d) => (d.parentId, d.ready, d.isCurrent, d.error)).toList()}',
      );
      rethrow;
    }
    expect(children!.appliedSets, 1);
    return children!;
  }

  ChatItemPresentation tool(
    TimelineChildrenDisplay children,
    String prefix, {
    String status = 'succeeded',
  }) {
    expect(children.isCurrent, isTrue);
    final matches = children.messages
        .map(chatItemPresentationOf)
        .whereType<ChatItemPresentation>()
        .where((item) {
          final reading = item.toolCard;
          return reading is DecodedToolCard &&
              reading.value.toolCallId.startsWith(prefix) &&
              reading.value.statusString == status;
        })
        .toList();
    expect(matches, hasLength(1), reason: '$prefix / $status');
    return matches.single;
  }

  Future<void> closeTurn(TimelineChildrenDisplay children) async {
    final row = find.byWidgetPredicate(
      (widget) => widget is ChatItemView && widget.item.id == latestTurnId,
    );
    await tap(find.descendant(of: row, matching: find.byType(ListTile)).first);
    await until(
      () =>
          !children.isCurrent &&
          graph.client.budget.used(ResourceKind.chatHandle) == 1,
      'previous Children retired and its real handle released',
    );
  }

  Map<String, dynamic> result(ChatItemPresentation item) =>
      jsonDecode(item.inlineText('tool.result')!) as Map<String, dynamic>;

  Future<void> expandWait(
    ChatItemPresentation item,
    ThreadWaitStateView expected,
  ) async {
    final card = find.byKey(StudioDriverKeys.waitingCard(item.id));
    await tap(find.descendant(of: card, matching: find.byType(ListTile)).first);
    await until(
      () => find
          .byKey(StudioDriverKeys.waitingDetails(item.id))
          .evaluate()
          .isNotEmpty,
      'expanded immutable wait details',
    );
    final details = find.byWidgetPredicate(
      (widget) => widget is TimelineWaitDetails && widget.identity == item.id,
    );
    expect(
      tester.widget<TimelineWaitDetails>(details).presentation.state,
      expected,
    );
    expect(
      find.byKey(StudioDriverKeys.waitingDetails(item.id)),
      findsOneWidget,
    );
  }
}
