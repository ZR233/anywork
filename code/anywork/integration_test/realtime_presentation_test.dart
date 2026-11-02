import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_children_connector.dart';
import 'package:anywork/src/features/conversation/timeline/previews/conversation_live_status_previews.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_children_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/shared/studio_code_block.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/presentation_capture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final project = Platform.environment['ANYWORK_REALTIME_PROJECT'];
  final output = Platform.environment['ANYWORK_REALTIME_OUTPUT'];
  if (project == null || output == null) {
    throw StateError(
      'Supply ANYWORK_REALTIME_PROJECT and ANYWORK_REALTIME_OUTPUT',
    );
  }
  final reportFile = File('$output/realtime-presentation.json');
  late AppGraph graph;
  late ProviderContainer container;
  var assertionsPassed = false;
  final report = <String, Object?>{
    'scenario': 'realtime-presentation',
    'fixture': 'realtime',
    'runner': 'flutter.integration_test',
    'pass': false,
  };

  setUpAll(() async {
    graph = AppGraph.production();
    container = ProviderContainer(
      overrides: [
        appGraphProvider.overrideWithValue(graph),
        statisticsRepositoryProvider.overrideWithValue(
          graph.statisticsRepository,
        ),
      ],
    );
    await graph.initialize();
    expect(graph.client.bootstrapState.value.failure, isNull);
  });

  tearDownAll(() async {
    try {
      final shutdown = await runStudioShutdown(
        graph.client.transport,
        (_) {},
        remainingMs: 30000,
        closeClient: (deadline) => graph.close(deadline: deadline),
      );
      expect(
        shutdown.shutdown.isClean,
        isTrue,
        reason: shutdown.shutdown.issues.toString(),
      );
      expect(shutdown.shutdown.issues, isEmpty);
      expect(
        shutdown.shutdown.persistence,
        isA<DrainedStudioPendingPersistence>(),
      );
      report['shutdown'] = 'completed';
      report['pass'] = assertionsPassed;
    } finally {
      container.dispose();
      await reportFile.parent.create(recursive: true);
      await reportFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }
  });

  testWidgets(
    'real realtime states render through production current and history',
    (tester) async {
      final router = createApplicationRouter();
      void syncConversationRoute() {
        if (router.routerDelegate.currentConfiguration.isEmpty) return;
        final state = router.routerDelegate.state;
        graph.client.selection.beginNavigation();
        graph.setConversationPageVisible(
          state.name == StudioRoute.name ||
              state.name == BotConversationRoute.name,
          threadId: state.name == BotConversationRoute.name
              ? state.pathParameters['threadId']!
              : null,
        );
      }

      router.routerDelegate.addListener(syncConversationRoute);
      tester.testTextInput.register();
      final testErrorHandler = FlutterError.onError!;
      FlutterError.onError = (details) {
        debugPrintSynchronously(details.toString());
        testErrorHandler(details);
      };
      addTearDown(() async {
        try {
          graph.setConversationPageVisible(false);
          await tester.pumpWidget(const SizedBox());
          await _until(
            tester,
            () => graph.client.budget.used(ResourceKind.chatHandle) == 0,
            'realtime-presentation read handles joined',
          );
        } finally {
          tester.testTextInput.unregister();
          router.routerDelegate.removeListener(syncConversationRoute);
          router.dispose();
          FlutterError.onError = testErrorHandler;
        }
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: presentationCaptureKey,
          child: UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              theme: pureStudioTheme(),
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        ),
      );
      await graph.client.directoryCommands.openProject(project);
      graph.setConversationPageVisible(true);
      final scene = _RealtimeScene(tester, graph);

      await capturePresentation(tester, 'realtime-start.png');
      await scene.submit('Realtime delayed first token');
      await scene.untilKey(const ValueKey('conversation-activity'));
      await capturePresentation(tester, 'realtime-thinking.png');
      await scene.untilKey(
        const ValueKey('conversation-activity-response-stream'),
        timeout: const Duration(seconds: 20),
      );
      await capturePresentation(tester, 'realtime-streaming.png');
      await scene.completed(answer: 'realtime delayed first token');

      await scene.submit('Realtime reasoning then answer');
      await scene.untilKey(const ValueKey('conversation-activity'));
      await scene.completed(answer: 'realtime reasoning answer');
      await scene.openLatestTurnThinking();
      await capturePresentation(tester, 'realtime-reasoning.png');
      await scene.closeLatestTurnChildren();

      await scene.submit('Realtime long command');
      await scene.untilLaidOutCurrentTools(minimum: 2);
      await capturePresentation(tester, 'realtime-exec-wait.png');
      await scene.completed(answer: 'realtime long command complete');

      final priorParallelTurns = scene.items
          .where((item) => item.type == 'turn')
          .map((item) => item.id)
          .toSet();
      await scene.submit('Realtime parallel tools');
      await scene.untilLaidOutCurrentTools(
        minimum: 2,
        runningExecCallIds: const {
          'realtime-parallel-call-a',
          'realtime-parallel-call-b',
        },
      );
      expect(
        find.text('realtime parallel tools complete'),
        findsNothing,
        reason: 'Both exact exec calls must be running before the final answer',
      );
      await capturePresentation(tester, 'realtime-parallel-running.png');
      await scene.completed(answer: 'realtime parallel tools complete');
      await scene.verifyExecReceipts(priorParallelTurns, const {
        'realtime-parallel-call-a': 'realtime-parallel-a-line-05',
        'realtime-parallel-call-b': 'realtime-parallel-b-line-07',
      });

      final priorHostCwdTurns = scene.items
          .where((item) => item.type == 'turn')
          .map((item) => item.id)
          .toSet();
      await scene.submit('Realtime host cwd command');
      await scene.untilLaidOutCurrentTools(
        minimum: 1,
        runningExecCallIds: const {'realtime-host-cwd-call'},
        settleDisclosure: false,
      );
      await capturePresentation(tester, 'realtime-host-cwd-running.png');
      await scene.completed(answer: 'realtime host cwd complete');
      await scene.verifyExecReceipts(priorHostCwdTurns, const {
        'realtime-host-cwd-call': 'realtime-host-cwd-line-03',
      });

      await scene.submit('Realtime provider error');
      await scene.terminal('failed');
      await capturePresentation(
        tester,
        'realtime-provider-error-collapsed.png',
      );
      final failedTurn = scene._latestTurn()!;
      final failed = await scene.openTurnChildren(
        failedTurn,
        expectedOutcome: 'failed',
      );
      final failureText = find
          .descendant(
            of: failed.row,
            matching: find.textContaining('realtime fixture provider error'),
          )
          .first;
      await scene.until(
        () => _laidOut(failureText),
        'provider failure laid out',
      );
      await _revealTextFragment(
        tester,
        failureText,
        'realtime fixture provider error',
      );
      await capturePresentation(tester, 'realtime-provider-error.png');
      await scene.closeTurnChildren(failedTurn);
      await scene.returnAfterReadingHistory();

      await scene.submit('Realtime cancellable stream');
      await scene.untilKey(
        const ValueKey('conversation-activity-response-stream'),
        timeout: const Duration(seconds: 30),
      );
      await capturePresentation(tester, 'realtime-before-cancel.png');
      await scene.tap(find.byKey(StudioDriverKeys.composerStop));
      await scene.terminal('cancelled');
      await capturePresentation(tester, 'realtime-stopped.png');

      await scene.submit('Realtime continue after cancel');
      await scene.completed(answer: 'realtime continued after cancel');
      expect(find.byType(ChatItemView), findsWidgets);

      // Supplemental native production-component capture, not a fixture-driven
      // compaction lifecycle. Keep its evidence separate from the real journey.
      graph.setConversationPageVisible(false);
      await tester.pumpWidget(
        RepaintBoundary(
          key: presentationCaptureKey,
          child: conversationLiveStatusCompactingPreview(),
        ),
      );
      await tester.pump();
      await capturePresentation(tester, 'component-compacting.png');

      report.addAll({
        'syntheticComponentCaptures': ['component-compacting.png'],
        'delayedStreamVisible': true,
        'reasoningHistoryVisible': true,
        'execWaitCardsVisible': true,
        'parallelCardsVisible': true,
        'hostCwdCardsVisible': true,
        'providerErrorVisible': true,
        'cancelledViaProductionControl': true,
        'resumeVisible': true,
      });
      assertionsPassed = true;
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

final class _RealtimeScene {
  _RealtimeScene(this.tester, this.graph);

  final WidgetTester tester;
  final AppGraph graph;
  String? _priorTurn;
  final Set<(String, String, int)> _reloadedToolReferences = {};

  TimelineDisplayLease get lease =>
      graph.timeline.lease(graph.client.selection.state.selectedThreadId!)!;

  List<ChatItemPresentation> get items => lease.controller.messages
      .map(chatItemPresentationOf)
      .whereType<ChatItemPresentation>()
      .toList();

  Future<ChatItemPresentation> openLatestTurnThinking() async {
    final turn = _latestTurn();
    expect(turn, isNotNull);
    final opened = await openTurnChildren(turn!);
    ChatItemPresentation? thinking;
    await until(() {
      final children = opened.display;
      if (children.error case final error?) throw StateError('$error');
      if (!children.ready || !children.isCurrent) return false;
      thinking = children.messages
          .map(chatItemPresentationOf)
          .whereType<ChatItemPresentation>()
          .where((item) => item.type == 'thinking')
          .lastOrNull;
      return thinking != null &&
          find
              .descendant(
                of: opened.row,
                matching: find.byKey(ValueKey('chat-item:${thinking!.id}')),
              )
              .evaluate()
              .isNotEmpty;
    }, 'laid out thinking item in reasoning Turn Children');
    expect(opened.display.appliedSets, 1);
    return thinking!;
  }

  Future<({Finder row, Finder tree, TimelineChildrenDisplay display})>
  openTurnChildren(
    ChatItemPresentation turn, {
    String expectedOutcome = 'completed',
  }) async {
    expect(turn.type, 'turn');
    expect(turn.data['outcome'], isA<Map<String, Object?>>());
    expect(
      (turn.data['outcome'] as Map<String, Object?>)['kind'],
      expectedOutcome,
    );
    final parentId = turn.childrenParentId;
    expect(parentId, isNotNull);
    final row = find.byWidgetPredicate(
      (widget) => widget is ChatItemView && widget.item.id == turn.id,
    );
    if (row.evaluate().isEmpty) {
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
    await until(() => headers.evaluate().isNotEmpty, 'mounted terminal Turn');
    final header = headers.first;
    final childrenTree = find.descendant(
      of: row,
      matching: find.byType(TimelineChildrenConnector),
    );
    if (childrenTree.evaluate().isEmpty) {
      await tap(header);
    }
    // Official ExpansionTile defaults to 200ms. Do not settle live spinners.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    TimelineChildrenDisplay? children;
    await until(() {
      if (childrenTree.evaluate().isEmpty) return false;
      expect(childrenTree, findsOneWidget);
      expect(
        tester.widget<TimelineChildrenConnector>(childrenTree).parentId,
        parentId,
      );
      children = lease.childrenDisplays
          .where((display) => display.parentId == parentId)
          .lastOrNull;
      if (children?.error case final error?) throw StateError('$error');
      return children?.ready == true && children?.isCurrent == true;
    }, 'current terminal Turn Children');
    expect(children!.appliedSets, 1);
    return (row: row, tree: childrenTree, display: children!);
  }

  Future<void> closeLatestTurnChildren() => closeTurnChildren(_latestTurn()!);

  Future<void> closeTurnChildren(ChatItemPresentation turn) async {
    final row = find.byWidgetPredicate(
      (widget) => widget is ChatItemView && widget.item.id == turn.id,
    );
    final tree = find.descendant(
      of: row,
      matching: find.byType(TimelineChildrenConnector),
    );
    expect(tree, findsOneWidget);
    await tap(find.descendant(of: row, matching: find.byType(ListTile)).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await until(
      () =>
          tree.evaluate().isEmpty &&
          !lease.childrenDisplays.any(
            (display) =>
                display.parentId == turn.childrenParentId && display.isCurrent,
          ),
      'collapsed terminal Turn Children retired',
    );
  }

  Future<void> verifyExecReceipts(
    Set<String> priorTurnIds,
    Map<String, String> expected,
  ) async {
    final witnessed = <String>{};
    final turns = items
        .where((item) => item.type == 'turn' && !priorTurnIds.contains(item.id))
        .toList();
    // The strict fixture has four Responses steps for this prompt and its deliveries.
    expect(turns, isNotEmpty);
    expect(turns.length, lessThanOrEqualTo(4));
    try {
      for (final turn in turns) {
        final opened = await openTurnChildren(turn);
        final view = find.descendant(
          of: opened.tree,
          matching: find.byType(TimelineChildrenView),
        );
        expect(view, findsOneWidget);
        final controller = tester.widget<TimelineChildrenView>(view).controller;
        final tools = opened.display.messages
            .map(chatItemPresentationOf)
            .whereType<ChatItemPresentation>()
            .where((item) => item.type == 'tool');
        for (final item in tools) {
          final reading = item.toolCard;
          if (reading is! DecodedToolCard) continue;
          final tool = reading.value;
          final lastLine = expected[tool.toolCallId];
          if (lastLine == null || tool.statusString != 'succeeded') continue;
          expect(tool.name, 'exec');
          expect(tool.exitCode, 0);
          expect(tool.output, contains(lastLine));
          if (tool.toolCallId == 'realtime-host-cwd-call') {
            final arguments =
                jsonDecode(tool.arguments) as Map<String, dynamic>;
            final cwd = arguments['cwd'] as String;
            expect(cwd, isNotEmpty);
            expect(tool.output, contains('realtime-host-cwd-actual:$cwd'));
          }
          final card = find.descendant(
            of: opened.tree,
            matching: find.byKey(ValueKey('chat-item:${item.id}')),
          );
          if (card.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              card,
              120,
              scrollable: find
                  .descendant(of: view, matching: find.byType(Scrollable))
                  .first,
              maxScrolls: 20,
            );
          }
          expect(_laidOut(card), isTrue);
          final details = find.descendant(
            of: card,
            matching: find.byType(TimelineToolDetails),
          );
          expect(details, findsOneWidget);
          final renderedTool = tester.widget<TimelineToolDetails>(details).item;
          expect(renderedTool.toolCallId, tool.toolCallId);
          expect(renderedTool.statusString, 'succeeded');
          final outputLabel = AppLocalizations.of(tester.element(details))
              .timelineToolOutput;
          final output = find.descendant(
            of: details,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is StudioCodeBlock &&
                  widget.language == outputLabel &&
                  widget.text.contains(lastLine),
            ),
          );
          if (output.evaluate().isEmpty) {
            await tap(
              find
                  .descendant(of: details, matching: find.byType(ListTile))
                  .first,
            );
          }
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          await until(() => _laidOut(output), 'exact exec output block');
          final text = find.descendant(
            of: output,
            matching: find.text(tester.widget<StudioCodeBlock>(output).text),
          );
          expect(text, findsOneWidget);
          await _revealTextFragment(tester, text, lastLine);
          expect(opened.display.error, isNull);
          expect(opened.display.isCurrent, isTrue);
          expect(opened.display.appliedSets, 1);
          expect(
            tester.widget<TimelineChildrenView>(view).controller,
            same(controller),
          );
          witnessed.add(tool.toolCallId);
          debugPrintSynchronously(
            'Exec receipt laid out: '
            '${jsonEncode({'callId': tool.toolCallId, 'state': tool.statusString, 'lastLine': lastLine, 'appliedSets': opened.display.appliedSets})}',
          );
          await capturePresentation(
            tester,
            'realtime-${tool.toolCallId}-succeeded.png',
          );
        }
        await closeTurnChildren(turn);
      }
      expect(witnessed, expected.keys.toSet());
      await returnAfterReadingHistory();
    } catch (_) {
      final scroll = lease.scrollController;
      final latest = find.byKey(StudioDriverKeys.timelineReturnLive);
      debugPrintSynchronously(
        'Exec receipt navigation failure: ${jsonEncode({'mode': lease.mode.name, 'pixels': scroll.hasClients ? scroll.position.pixels : null, 'maxExtent': scroll.hasClients ? scroll.position.maxScrollExtent : null, 'returnWidgets': latest.evaluate().length, 'returnHitTargets': latest.hitTestable().evaluate().length})}',
      );
      await capturePresentation(tester, 'realtime-exec-receipts-failure.png');
      rethrow;
    }
  }

  Future<void> returnAfterReadingHistory() async {
    // Programmatic revelation is not a user's reading intent.
    final scroll = lease.scrollController;
    expect(scroll.hasClients, isTrue);
    if (scroll.position.maxScrollExtent <= 0.5) return;
    final main = find.byWidgetPredicate(
      (widget) => widget is Scrollable && identical(widget.controller, scroll),
    );
    final towardLatest = scroll.position.pixels > 0.5;
    final distance =
        (towardLatest
                ? scroll.position.pixels / 2
                : scroll.position.maxScrollExtent / 2)
            .clamp(1.0, 60.0)
            .toDouble();
    final delta = towardLatest ? -distance : distance;
    debugPrintSynchronously(
      'Main history gesture: ${jsonEncode({'mode': lease.mode.name, 'pixels': scroll.position.pixels, 'maxExtent': scroll.position.maxScrollExtent, 'axis': scroll.position.axisDirection.name, 'logicalDelta': delta})}',
    );
    await tester.drag(main, switch (scroll.position.axisDirection) {
      AxisDirection.up => Offset(0, delta),
      AxisDirection.down => Offset(0, -delta),
      _ => throw StateError('Main timeline must scroll vertically'),
    });
    await tester.pump();
    final latest = find.byKey(StudioDriverKeys.timelineReturnLive);
    await until(
      () => latest.hitTestable().evaluate().isNotEmpty,
      'production return-to-latest action after reading history',
    );
    await tap(latest);
    await until(
      () => scroll.position.pixels.abs() < 0.5,
      'latest timeline viewport after reading receipts',
    );
  }

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
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
  }

  Future<void> untilKey(
    Key key, {
    Duration timeout = const Duration(seconds: 60),
  }) => until(
    () => find.byKey(key).evaluate().isNotEmpty,
    'laid out $key',
    timeout: timeout,
  );

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
    _priorTurn = _latestTurn()?.id;
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
        'Realtime submission failure: draft=${composer.composer.draft}, '
        'pending=${composer.composer.isSubmissionPending}, '
        'execution=${composer.execution?.id}/${composer.execution?.phase}, '
        'blocker=${composer.blocker}, failure=${composer.failure}',
      );
      rethrow;
    }
  }

  Future<void> completed({required String answer}) async {
    await terminal('completed');
    await tester.pump();
    final returnToLatest = find
        .byKey(StudioDriverKeys.timelineReturnLive)
        .hitTestable();
    if (returnToLatest.evaluate().isNotEmpty) {
      await tap(returnToLatest);
    }
    try {
      await until(
        () => find.textContaining(answer).evaluate().isNotEmpty,
        'completed answer "$answer"',
        timeout: const Duration(minutes: 2),
      );
    } catch (_) {
      final scroll = lease.scrollController;
      debugPrintSynchronously(
        'Missing completed answer: ${jsonEncode({'answer': answer, 'mainPixels': scroll.hasClients ? scroll.position.pixels : null, 'mainMaxExtent': scroll.hasClients ? scroll.position.maxScrollExtent : null, 'returnActionVisible': returnToLatest.evaluate().isNotEmpty, 'renderedRows': find.byType(ChatItemView).evaluate().length, 'latestItemIds': items.reversed.take(4).map((item) => item.id).toList()})}',
      );
      await capturePresentation(
        tester,
        'realtime-completed-answer-missing.png',
      );
      rethrow;
    }
  }

  Future<void> terminal(String kind) async {
    await until(
      () {
        final turn = _latestTurn();
        return turn != null &&
            turn.id != _priorTurn &&
            turn.data['outcome'] is Map &&
            (turn.data['outcome'] as Map)['kind'] == kind;
      },
      '$kind realtime Turn',
      timeout: const Duration(minutes: 3),
    );
  }

  Future<void> untilLaidOutCurrentTools({
    required int minimum,
    Set<String> runningExecCallIds = const {},
    bool settleDisclosure = true,
  }) async {
    final activity = find.byKey(const ValueKey('conversation-activity'));
    final collectionTitle = find.byKey(
      StudioDriverKeys.currentCollection('tools'),
    );
    final reload = find.byKey(
      StudioDriverKeys.currentCollectionReload('tools'),
    );
    final clock = Stopwatch()..start();
    String? priorDiagnostic;
    var disclosureSettled = false;
    try {
      while (true) {
        final current = lease.currentDisplay;
        final collection = current?.collections
            .where((display) => display.reference.collection == 'tools')
            .lastOrNull;
        // A real query error is terminal, never a reason to press reload.
        if (collection?.error case final error?) throw StateError('$error');
        final reference = collection?.reference;
        final page = collection?.page;
        final entries = page?.entries ?? const <CurrentCollectionEntry>[];
        final runningExecIds = <String>{};
        if (runningExecCallIds.isNotEmpty) {
          for (final entry in entries) {
            expect(entry.payload, isA<InlinePayload>());
            final data = jsonDecode(
              utf8.decode((entry.payload as InlinePayload).bytes),
            ) as Map<String, dynamic>;
            if (data['name'] == 'exec' && data['state'] == 'running') {
              expect(data['callId'], entry.id);
              runningExecIds.add(data['callId'] as String);
            }
          }
        }
        final requiredEntries = runningExecCallIds.isEmpty
            ? entries
            : entries
                  .where((entry) => runningExecCallIds.contains(entry.id))
                  .toList();
        final laidOut = requiredEntries.where((entry) {
          final elements = find
              .byKey(StudioDriverKeys.currentCollectionEntry('tools', entry.id))
              .evaluate();
          if (elements.length != 1) return false;
          final render = elements.single.findRenderObject();
          return render is RenderBox &&
              render.attached &&
              render.hasSize &&
              !render.size.isEmpty;
        }).length;
        final identity = reference == null
            ? null
            : (reference.databaseId, reference.collection, reference.revision);
        final diagnostic = <String, Object?>{
          'minimum': minimum,
          'reference': identity == null
              ? null
              : {
                  'databaseId': identity.$1,
                  'collection': identity.$2,
                  'revision': identity.$3,
                },
          'currentExpanded': current?.expanded,
          'expanded': collection?.expanded,
          'loading': collection?.loading,
          'pageRevision': page?.revision,
          'entries': entries.length,
          'laidOut': laidOut,
          'reloadVisible': reload.hitTestable().evaluate().isNotEmpty,
          'actualReload': false,
          if (runningExecCallIds.isNotEmpty)
            'exactRunningExecIds': runningExecIds
                .intersection(runningExecCallIds)
                .toList(),
        };
        final encoded = jsonEncode(diagnostic);
        if (encoded != priorDiagnostic) {
          debugPrintSynchronously('Realtime current tools: $encoded');
          priorDiagnostic = encoded;
        }
        if (current?.expanded == true &&
            collection?.expanded == true &&
            page != null &&
            page.revision == reference?.revision &&
            entries.length >= minimum &&
            laidOut == requiredEntries.length &&
            runningExecIds.containsAll(runningExecCallIds)) {
          // Recheck the same live UI contract after its finite disclosure animation.
          if (settleDisclosure && !disclosureSettled) {
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
            disclosureSettled = true;
            continue;
          }
          return;
        }
        if (clock.elapsed >= const Duration(minutes: 3)) {
          fail('Timed out waiting for $minimum production current tool cards');
        }
        final Finder? action;
        if (current?.expanded != true) {
          action = activity;
        } else if (collection?.expanded != true) {
          action = collectionTitle;
        } else if (identity != null &&
            collection?.loading == false &&
            !_reloadedToolReferences.contains(identity) &&
            reload.evaluate().length == 1 &&
            tester.widget<TextButton>(reload).onPressed != null) {
          action = reload;
        } else {
          action = null;
        }
        if (action != null && action.evaluate().length == 1) {
          if (action.hitTestable().evaluate().length == 1) {
            await tester.tap(action);
            if (identical(action, reload)) {
              _reloadedToolReferences.add(identity!);
              debugPrintSynchronously(
                'Realtime current tools: '
                '${jsonEncode({...diagnostic, 'actualReload': true})}',
              );
            }
          } else {
            await Scrollable.ensureVisible(
              tester.element(action),
              alignment: 0.5,
            );
          }
        }
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
    } catch (_) {
      await capturePresentation(
        tester,
        'realtime-current-tools-$minimum-failure.png',
      );
      rethrow;
    }
  }

  ChatItemPresentation? _latestTurn() {
    final threadId = graph.client.selection.state.selectedThreadId;
    if (threadId == null) return null;
    final display = graph.timeline.lease(threadId);
    if (display == null) return null;
    return display.controller.messages
        .map(chatItemPresentationOf)
        .whereType<ChatItemPresentation>()
        .where((item) => item.type == 'turn')
        .lastOrNull;
  }
}

bool _laidOut(Finder finder) {
  final elements = finder.evaluate();
  if (elements.length != 1) return false;
  final render = elements.single.findRenderObject();
  return render is RenderBox &&
      render.attached &&
      render.hasSize &&
      !render.size.isEmpty;
}

Future<void> _revealTextFragment(
  WidgetTester tester,
  Finder finder,
  String fragment,
) async {
  expect(_laidOut(finder), isTrue);
  final text = find.descendant(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains(fragment),
    ),
  );
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final start = paragraph.text.toPlainText().indexOf(fragment);
  expect(start, greaterThanOrEqualTo(0));
  final selection = TextSelection(
    baseOffset: start,
    extentOffset: start + fragment.length,
  );
  final boxes = paragraph.getBoxesForSelection(selection);
  expect(boxes, isNotEmpty);
  final bounds = boxes
      .map((box) => box.toRect())
      .reduce((left, right) => left.expandToInclude(right));
  paragraph.showOnScreen(
    rect: bounds,
    duration: const Duration(milliseconds: 300),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull);
  for (final box in paragraph.getBoxesForSelection(selection)) {
    final local = box.toRect();
    final rect = Rect.fromPoints(
      paragraph.localToGlobal(local.topLeft),
      paragraph.localToGlobal(local.bottomRight),
    );
    RenderObject? ancestor = paragraph.parent;
    while (ancestor != null) {
      if ((ancestor is RenderClipRect || ancestor is RenderAbstractViewport) &&
          ancestor is RenderBox) {
        final viewport = (ancestor.localToGlobal(Offset.zero) & ancestor.size)
            .inflate(1);
        final diagnostic =
            '$fragment $rect in ${ancestor.runtimeType} $viewport; '
            '${Scrollable.maybeOf(tester.element(text))?.position}';
        expect(viewport.contains(rect.topLeft), isTrue, reason: diagnostic);
        expect(viewport.contains(rect.bottomRight), isTrue, reason: diagnostic);
      }
      ancestor = ancestor.parent;
    }
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed >= const Duration(seconds: 60)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  }
}
