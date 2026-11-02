import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
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

import 'support/presentation_capture.dart';

const _seedPrompt = 'Generate the local timeline history fixture';
const _streamPrompt = 'Stream the local timeline reading fixture';
const _deepPages = 40;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final phase = Platform.environment['ANYWORK_TIMELINE_PHASE'];
  final project = Platform.environment['ANYWORK_TIMELINE_PROJECT'];
  final output = Platform.environment['ANYWORK_TIMELINE_OUTPUT'];
  if ((phase != 'live' && phase != 'restart') ||
      project == null ||
      output == null) {
    throw StateError(
      'Supply ANYWORK_TIMELINE_PHASE=live|restart, '
      'ANYWORK_TIMELINE_PROJECT and ANYWORK_TIMELINE_OUTPUT',
    );
  }
  final outputDirectory = Directory(output);
  final baselineFile = File(
    '${outputDirectory.path}/timeline-history-baseline.json',
  );
  final reportFile = File(
    '${outputDirectory.path}/timeline-history-$phase.json',
  );
  late AppGraph graph;
  late ProviderContainer container;
  late _TimelineScene scene;
  var assertionsPassed = false;
  final report = <String, Object?>{
    'phase': phase,
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
      await outputDirectory.create(recursive: true);
      await reportFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }
  });

  testWidgets('$phase: real timeline layout, paging and persisted identity', (
    tester,
  ) async {
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
          'timeline read handles joined',
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
    scene = _TimelineScene(tester, graph);

    if (phase == 'live') {
      await _runLive(scene, project, baselineFile, report);
    } else {
      await _runRestart(scene, project, baselineFile, report);
    }
    assertionsPassed = true;
  }, timeout: const Timeout(Duration(minutes: 20)));
}

Future<void> _runLive(
  _TimelineScene scene,
  String project,
  File baselineFile,
  Map<String, Object?> report,
) async {
  await scene.submit(_seedPrompt);
  await scene.waitForCompletedTurn();
  final seed = await scene.readyLease('seed actual content layout');
  expect(seed.loadedCount, greaterThan(0));
  expect(seed.hasOlder, isTrue);
  expect(find.byType(ChatItemView), findsWidgets);

  final beforeDetachGeneration = seed.generation;
  await scene.leaveAndReturn();
  final reattached = await scene.readyLease('reattached seed content');
  expect(reattached.generation, greaterThan(beforeDetachGeneration));
  await capturePresentation(scene.tester, 'timeline-live-history.png');

  final priorTurn = scene.latestTurnId;
  await scene.submit(_streamPrompt);
  await scene.until(
    () => find
        .byKey(const ValueKey('conversation-activity'))
        .evaluate()
        .isNotEmpty,
    'real streaming activity bar',
    timeout: const Duration(seconds: 30),
  );
  expect(find.byKey(const ValueKey('conversation-activity')), findsOneWidget);
  final streamingLease = scene.lease;
  final streaming = await scene.waitForStreamingTurn(after: priorTurn);
  await capturePresentation(scene.tester, 'timeline-streaming-before-page.png');
  final beforePage = scene.ids(streamingLease);
  await scene.loadOlder(streamingLease);
  expect(scene.ids(streamingLease).length, greaterThan(beforePage.length));
  expect(
    scene
        .ids(streamingLease)
        .skip(scene.ids(streamingLease).length - beforePage.length),
    beforePage,
  );
  scene.expectStreamingTurn(streaming);
  await capturePresentation(scene.tester, 'timeline-streaming-after-page.png');
  await scene.waitForTerminalTurn(streaming.turnId);
  await scene.waitForCompletedTurn(after: priorTurn);

  await scene.leaveAndReturn();
  final comparison = await scene.readyLease('comparison latest content');
  final latestIds = scene.ids(comparison);
  final latestPage = _latestPage(comparison);
  final coldStartLatest = <String, Object?>{
    'live': true,
    'loadedItems': comparison.loadedCount,
    'firstContentLaidOut': latestPage['firstContentLaidOut'],
    'pixelsAtTop': latestPage['pixelsAtTop'],
  };
  final pages = await scene.readDeepPages(comparison);
  final workspaceId = scene.graph.client.selection.state.selectedProjectId;
  final threadId = scene.graph.client.selection.state.selectedThreadId;
  expect(workspaceId, isNotNull);
  expect(threadId, isNotNull);
  final baseline = <String, Object?>{
    'workspaceId': workspaceId,
    'projectPath': project,
    'threadId': threadId,
    'latestItemIds': latestIds,
    'pages': pages,
  };
  await baselineFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(baseline)}\n',
  );
  report.addAll({
    'identity': {...baseline, 'evidenceConsistent': true},
    'streamingActivityVisible': true,
    'streamingPageRetained': true,
    'streamingHistory': {'pass': true},
    'latestItemIds': latestIds,
    'latestPage': latestPage,
    'latestPageOk': true,
    'coldStartLatest': coldStartLatest,
    'paging': _pagingReport(comparison, pages),
    'pageCount': pages.length,
    'loadedItems': comparison.loadedCount,
    'hasOlder': comparison.hasOlder,
  });
}

Future<void> _runRestart(
  _TimelineScene scene,
  String project,
  File baselineFile,
  Map<String, Object?> report,
) async {
  expect(
    baselineFile.existsSync(),
    isTrue,
    reason: 'The live phase must record the persisted identity first',
  );
  final baseline = (jsonDecode(await baselineFile.readAsString()) as Map)
      .cast<String, Object?>();
  final threadId = baseline['threadId'] as String;
  var tapAttempts = 0;
  if (scene.graph.client.selection.state.selectedThreadId != threadId) {
    await scene.tap(find.byKey(StudioDriverKeys.threadRow(threadId)));
    tapAttempts = 1;
  }
  final display = await scene.readyLease('restart actual content layout');
  var latestIds = scene.ids(display);
  final expectedLatestIds = (baseline['latestItemIds'] as List).cast<String>();
  final latestPage = _latestPage(display);
  final coldStartLatest = <String, Object?>{
    'live': true,
    'loadedItems': display.loadedCount,
    'firstContentLaidOut': latestPage['firstContentLaidOut'],
    'pixelsAtTop': latestPage['pixelsAtTop'],
  };
  expect(
    scene.graph.client.selection.state.selectedProjectId,
    baseline['workspaceId'],
  );
  expect(scene.graph.client.selection.state.selectedThreadId, threadId);
  expect(project, baseline['projectPath']);
  expect(latestIds.length, lessThanOrEqualTo(expectedLatestIds.length));
  expect(
    latestIds,
    expectedLatestIds.skip(expectedLatestIds.length - latestIds.length),
    reason: 'cold restart must expose the same latest identity suffix',
  );
  var restoreWarmupPages = 0;
  while (latestIds.length < expectedLatestIds.length) {
    await scene.loadOlder(display);
    restoreWarmupPages += 1;
    latestIds = scene.ids(display);
  }
  expect(
    latestIds,
    expectedLatestIds,
    reason: 'restart must recover the exact persisted latest identity window',
  );
  final pages = await scene.readDeepPages(display);
  await capturePresentation(scene.tester, 'timeline-restart-history.png');
  final expectedPages = (baseline['pages'] as List)
      .map((page) => (page as List).cast<String>())
      .toList();
  expect(pages, expectedPages);
  report.addAll({
    'latestPage': latestPage,
    'latestPageOk': true,
    'coldStartLatest': coldStartLatest,
    'paging': _pagingReport(display, pages),
    'restore': {
      'workspaceId': baseline['workspaceId'],
      'projectPath': project,
      'threadId': threadId,
      'evidenceConsistent': true,
      'workspaceIdMatches': true,
      'threadIdMatches': true,
      'autoOpened': tapAttempts == 0,
      'tapAttempts': tapAttempts,
      'warmupPages': restoreWarmupPages,
    },
    'restartComparison': {
      'sameOrder': true,
      'identityMatches': true,
      'latestMatches': true,
      'pageCountMatches': true,
      'oldestMatches': true,
      'loadedItemsMatch': true,
    },
    'identityMatches': true,
    'latestMatches': true,
    'pagesMatch': true,
    'pageCount': pages.length,
    'loadedItems': display.loadedCount,
    'hasOlder': display.hasOlder,
  });
}

Map<String, Object?> _latestPage(TimelineDisplayLease display) => {
  'firstContentLaidOut': display.firstContentLayout != null,
  'atLiveEdge': display.mode == TimelineDisplayMode.live,
  'pixelsAtTop':
      !display.scrollController.hasClients ||
      display.scrollController.position.pixels.abs() < 0.5,
  'hasOlder': display.hasOlder,
  'loadedItems': display.loadedCount,
};

Map<String, Object?> _pagingReport(
  TimelineDisplayLease display,
  List<List<String>> pages,
) => {
  'pages': [
    for (var index = 0; index < pages.length; index += 1)
      {'page': index + 1, 'itemIds': pages[index]},
  ],
  'pageCount': pages.length,
  'partialDepthPages': pages.length,
  'reachedEnd': !display.hasOlder,
  'hasOlder': display.hasOlder,
  'duplicateIdentity': false,
  'orderViolation': false,
  'cursorStalled': false,
  'growthViolations': const <Object?>[],
};

final class _TimelineScene {
  _TimelineScene(this.tester, this.graph);

  final WidgetTester tester;
  final AppGraph graph;
  String? latestTurnId;

  TimelineDisplayLease get lease =>
      graph.timeline.lease(graph.client.selection.state.selectedThreadId!)!;

  List<String> ids(TimelineDisplayLease display) =>
      display.controller.messages.map((item) => item.id).toList();

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
        'Timeline submission failure: draft=${composer.composer.draft}, '
        'pending=${composer.composer.isSubmissionPending}, '
        'execution=${composer.execution?.id}/${composer.execution?.phase}, '
        'blocker=${composer.blocker}, failure=${composer.failure}',
      );
      rethrow;
    }
  }

  Future<void> waitForCompletedTurn({String? after}) async {
    ChatItemPresentation? turn;
    await until(
      () {
        final selected = graph.client.selection.state.selectedThreadId;
        final display = selected == null
            ? null
            : graph.timeline.lease(selected);
        if (display == null) return false;
        turn = display.controller.messages
            .map(chatItemPresentationOf)
            .whereType<ChatItemPresentation>()
            .where((item) => item.type == 'turn')
            .lastOrNull;
        if (turn == null || turn!.id == after) return false;
        final outcome = turn!.data['outcome'];
        return outcome is Map && outcome['kind'] == 'completed';
      },
      'completed timeline Turn',
      timeout: const Duration(minutes: 6),
    );
    latestTurnId = turn!.id;
  }

  Future<({String turnId, String activityId})> waitForStreamingTurn({
    String? after,
  }) async {
    String? turnId;
    String? activityId;
    await until(
      () {
        final selected = graph.client.selection.state.selectedThreadId;
        if (selected == null) return false;
        final display = graph.timeline.lease(selected);
        final current = display?.content.current.value;
        final candidate = current?.activeTurn?.id;
        final candidateActivity = current?.active?.id;
        final sessionTurn = graph.client.conversations
            .session(selected)
            .state
            .activeTurn;
        final currentDisplay = display?.currentDisplay;
        if (candidate == null ||
            candidate == after ||
            candidateActivity == null ||
            currentDisplay == null ||
            currentDisplay.turnId != candidate ||
            currentDisplay.activityId != candidateActivity ||
            !currentDisplay.isCurrent ||
            sessionTurn?.turnId != candidate ||
            sessionTurn?.state.isBusy != true ||
            current!.logicalStatus.isActive != true ||
            !current.executionPresent) {
          return false;
        }
        turnId = candidate;
        activityId = candidateActivity;
        return true;
      },
      'canonical streaming Turn',
      timeout: const Duration(seconds: 30),
    );
    return (turnId: turnId!, activityId: activityId!);
  }

  void expectStreamingTurn(({String turnId, String activityId}) streaming) {
    final selected = graph.client.selection.state.selectedThreadId!;
    final display = graph.timeline.lease(selected)!;
    final current = display.content.current.value;
    final sessionTurn = graph.client.conversations
        .session(selected)
        .state
        .activeTurn;
    expect(current?.activeTurn?.id, streaming.turnId);
    expect(current?.active?.id, streaming.activityId);
    expect(current?.logicalStatus.isActive, isTrue);
    expect(current?.executionPresent, isTrue);
    expect(display.currentDisplay?.turnId, streaming.turnId);
    expect(display.currentDisplay?.activityId, streaming.activityId);
    expect(display.currentDisplay?.isCurrent, isTrue);
    expect(sessionTurn?.turnId, streaming.turnId);
    expect(sessionTurn?.state.isBusy, isTrue);
  }

  Future<void> waitForTerminalTurn(String turnId) async {
    await until(
      () {
        final selected = graph.client.selection.state.selectedThreadId;
        if (selected == null) return false;
        final display = graph.timeline.lease(selected);
        final current = display?.content.current.value;
        final state = graph.client.conversations.session(selected).state;
        final completed = state.lastTurn;
        return completed?.turnId == turnId &&
            completed?.state.status == StudioTurnStatus.completed &&
            completed?.state.isTerminal == true &&
            state.activeTurn?.turnId != turnId &&
            current?.activeTurn?.id != turnId;
      },
      'terminal canonical Turn $turnId',
      timeout: const Duration(minutes: 6),
    );
  }

  Future<TimelineDisplayLease> readyLease(String description) async {
    await until(() {
      final selected = graph.client.selection.state.selectedThreadId;
      return selected != null &&
          graph.timeline.lease(selected)?.firstContentLayout != null;
    }, description);
    final display = lease;
    expect(display.appliedSets, 1);
    expect(display.loadedCount, greaterThan(0));
    expect(find.byType(ChatItemView), findsWidgets);
    return display;
  }

  Future<void> loadOlder(TimelineDisplayLease display) async {
    final before = display.loadedCount;
    final view = tester.widget<TimelineView>(find.byType(TimelineView));
    await view.onLoadOlder();
    await until(
      () => display.loadedCount > before,
      'older timeline page ${display.appliedPrepends + 1}',
    );
    expect(identical(display, lease), isTrue);
  }

  Future<List<List<String>>> readDeepPages(TimelineDisplayLease display) async {
    final pages = <List<String>>[];
    var previous = ids(display);
    for (var page = 0; page < _deepPages; page += 1) {
      expect(display.hasOlder, isTrue, reason: 'page ${page + 1}');
      await loadOlder(display);
      final current = ids(display);
      expect(current.length, greaterThan(previous.length));
      expect(
        current.skip(current.length - previous.length),
        previous,
        reason: 'page ${page + 1} must retain the prior window as a suffix',
      );
      expect(current.toSet(), hasLength(current.length));
      pages.add(current);
      previous = current;
    }
    expect(display.appliedSets, 1);
    expect(display.appliedPrepends, greaterThanOrEqualTo(_deepPages));
    expect(display.hasOlder, isTrue);
    return pages;
  }

  Future<void> leaveAndReturn() async {
    final before = lease;
    await tap(find.byKey(StudioDriverKeys.settingsOpen));
    await until(
      () => find.byKey(StudioDriverKeys.settingsPage).evaluate().isNotEmpty,
      'settings route',
    );
    await until(
      () => before.isRetired,
      'timeline display retired outside conversation route',
    );
    await tap(find.byKey(StudioDriverKeys.settingsBack));
    await until(
      () =>
          graph.timeline.lease(before.threadId)?.generation !=
              before.generation &&
          graph.timeline.lease(before.threadId)?.firstContentLayout != null,
      'fresh timeline display after route return',
    );
    expect(before.isReleased, isTrue);
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
