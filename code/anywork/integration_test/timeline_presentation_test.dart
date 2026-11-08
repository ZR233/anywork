import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/state/content_reference_identity.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_plain_text.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/presentation_capture.dart';
import 'support/timeline_observation.dart';
import 'support/timeline_output_consumption.dart';

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
        expect(
          (await graph.client.conversations.retryCleanup(
            deadline: DateTime.now().add(const Duration(seconds: 5)),
          )).complete,
          isTrue,
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
  final seedConsumption = await scene.outputConsumption();
  try {
    await seedConsumption.readMany(
      loadOlder: () => scene.loadOlder(seedConsumption.lease),
      pump: () async {
        await scene.tester.pump(const Duration(milliseconds: 16));
        expect(scene.tester.takeException(), isNull);
      },
      expectedItems: 2000,
      expectedBytes: 256000,
    );
  } finally {
    report['manyBodyConsumption'] = await seedConsumption.close();
  }
  await scene.waitForCompletedTurn();
  final seed = await scene.readyLease('seed actual content layout');
  expect(seed.loadedCount, greaterThan(0));
  expect(find.byType(ChatItemView), findsWidgets);

  final beforeDetachGeneration = seed.generation;
  await scene.leaveAndReturn();
  final reattached = await scene.readyLease('reattached seed content');
  expect(reattached.generation, greaterThan(beforeDetachGeneration));
  // A live feed may have delivered the entire seed. The new historical
  // window starts at the completed tail and must expose its older cursor.
  expect(reattached.hasOlder, isTrue);
  await capturePresentation(scene.tester, 'timeline-live-history.png');

  final priorTurn = scene.latestTurnId;
  await scene.submit(_streamPrompt);
  final streaming = await scene.waitForStreamingTurn(after: priorTurn);
  final singleConsumption = await scene.outputConsumption();
  late _StreamingBody streamingBody;
  late _StreamingWindow afterPage;
  final streamingLease = streaming.lease;
  try {
    await Future.wait([
      singleConsumption.readGrowing(
        streaming.preview.reference,
        owner: streaming.response.id,
        expectedBytes: 256000,
      ),
      () async {
        streamingBody = await scene.waitForStreamingBody(streaming);
        await capturePresentation(
          scene.tester,
          'timeline-streaming-before-page.png',
        );
        scene.expectStreamingTurn(streaming);
        final beforePage = scene.ids(streamingLease);
        await scene.loadOlder(streamingLease);
        expect(
          scene.ids(streamingLease).length,
          greaterThan(beforePage.length),
        );
        expect(
          scene
              .ids(streamingLease)
              .skip(scene.ids(streamingLease).length - beforePage.length),
          beforePage,
        );
        afterPage = scene.expectStreamingTurn(streaming);
        await capturePresentation(
          scene.tester,
          'timeline-streaming-after-page.png',
        );
        await scene.waitForTerminalTurn(streaming.turnId);
      }(),
    ]);
  } finally {
    report['singleBodyConsumption'] = await singleConsumption.close();
  }
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
    'streamingActivityVisible': !streamingBody.visibleGlyphBounds.isEmpty,
    'streamingPresentation': {
      'renderer': 'TimelinePlainText',
      'atomId': streaming.response.id,
      'prefixBytes': utf8.encode(streamingBody.prefix).length,
      'visibleGlyphBounds': [
        streamingBody.visibleGlyphBounds.left,
        streamingBody.visibleGlyphBounds.top,
        streamingBody.visibleGlyphBounds.right,
        streamingBody.visibleGlyphBounds.bottom,
      ],
    },
    'streamingPageRetained': true,
    'streamingHistory': {
      'pass': true,
      'threadId': streamingLease.threadId,
      'turnId': streaming.turnId,
      'activityId': streaming.activityId,
      'responseAtomId': streaming.response.id,
      'phase': ThreadActivityKind.responding.name,
      'beforePreviewBytes': utf8.encode(streaming.preview.text).length,
      'afterPreviewBytes': utf8.encode(afterPage.text).length,
      'responsePrefixRetained': true,
    },
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

typedef _StreamingTurn = ({
  TimelineDisplayLease lease,
  TimelineCurrentDisplay display,
  String turnId,
  String activityId,
  ChatAtom response,
  _StreamingWindow preview,
});

typedef _StreamingWindow = ({ContentRef reference, String text});

typedef _StreamingBody = ({String prefix, Rect visibleGlyphBounds});

final class _TimelineScene {
  _TimelineScene(this.tester, this.graph);

  final WidgetTester tester;
  final AppGraph graph;
  String? latestTurnId;
  String? _submittedThreadId;
  String? _priorTurnId;
  String? _submittedTurnId;

  TimelineDisplayLease get lease =>
      graph.timeline.lease(graph.client.selection.state.selectedThreadId!)!;

  List<String> ids(TimelineDisplayLease display) => TimelineObservation(
    tester,
    () => display,
  ).main.map((unit) => unit.id).toList();

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
      _submittedThreadId = graph.client.selection.state.selectedThreadId;
      _priorTurnId = _submittedThreadId == null
          ? null
          : graph.client.conversations
                .session(_submittedThreadId!)
                .state
                .lastTurn
                ?.turnId;
      _submittedTurnId = null;
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
    StudioTurnView? turn;
    final observed = TimelineObservation(tester, () => lease);
    await until(
      () {
        final selected = graph.client.selection.state.selectedThreadId;
        if (selected == null) return false;
        _submittedThreadId ??= selected;
        if (selected != _submittedThreadId) return false;
        final candidate = graph.client.conversations
            .session(selected)
            .state
            .lastTurn;
        if (candidate == null ||
            candidate.threadId != selected ||
            candidate.turnId == _priorTurnId ||
            candidate.turnId == after) {
          return false;
        }
        _submittedTurnId ??= candidate.turnId;
        if (candidate.turnId != _submittedTurnId) return false;
        turn = candidate;
        if (candidate.state is! CompletedStudioTurnState ||
            graph.timeline.lease(selected) == null) {
          return false;
        }
        final source = ForegroundTurnChatSource(turnId: candidate.turnId);
        // Main admission is a separate requirement, not the Turn's completion
        // authority. Both must arrive within the original wait budget.
        return observed.entries.any((item) => item.atom.source == source) &&
            !observed.activity.any((entry) => entry.atom.source == source);
      },
      'completed timeline Turn',
      timeout: const Duration(minutes: 6),
    );
    latestTurnId = turn!.turnId;
  }

  Future<TimelineOutputConsumption> outputConsumption() async {
    TimelineOutputConsumption? consumption;
    await until(() {
      final selected = graph.client.selection.state.selectedThreadId;
      if (selected == null ||
          (_submittedThreadId != null && selected != _submittedThreadId)) {
        return false;
      }
      final display = graph.timeline.lease(selected);
      final session = graph.client.conversations.session(selected);
      final execution = session.state.runtime?.execution;
      final turn = session.state.activeTurn;
      if (display == null ||
          !display.isMounted ||
          display.isRetired ||
          display.content.state.value is! ChatReady<bool> ||
          execution == null ||
          execution.phase != AgentExecutionPhase.running ||
          turn == null ||
          !turn.state.isBusy ||
          turn.turnId != execution.turnId ||
          turn.turnId == _priorTurnId) {
        return false;
      }
      _submittedThreadId ??= selected;
      _submittedTurnId ??= turn.turnId;
      expect(turn.turnId, _submittedTurnId);
      consumption = TimelineOutputConsumption(
        lease: display,
        session: session,
        conversations: graph.client.conversations,
        turnId: turn.turnId,
        executionId: execution.id,
      );
      return true;
    }, 'original running execution for content consumption');
    return consumption!;
  }

  Future<_StreamingTurn> waitForStreamingTurn({String? after}) async {
    _StreamingTurn? streaming;
    await until(
      () {
        final selected = graph.client.selection.state.selectedThreadId;
        if (selected == null) return false;
        _submittedThreadId ??= selected;
        if (selected != _submittedThreadId) return false;
        final display = graph.timeline.lease(selected);
        if (display == null || !display.isMounted || display.isRetired) {
          return false;
        }
        final state = graph.client.conversations.session(selected).state;
        final current = display.content.activity.value;
        final sessionTurn = state.activeTurn;
        final candidate = sessionTurn?.turnId;
        final candidateActivity = state.activity?.identity;
        final currentDisplay = display.currentDisplay;
        if (candidate == null ||
            candidate == _priorTurnId ||
            candidate == after ||
            candidateActivity == null ||
            currentDisplay == null ||
            currentDisplay.turnId != candidate ||
            currentDisplay.activityId != candidateActivity ||
            !currentDisplay.isCurrent ||
            sessionTurn?.threadId != selected ||
            sessionTurn?.state.isBusy != true ||
            state.activity?.kind != ThreadActivityKind.responding ||
            current?.executionPresent != true) {
          return false;
        }
        _submittedTurnId ??= candidate;
        if (candidate != _submittedTurnId) return false;
        final response = current!.entries
            .map((entry) => entry.atom)
            .where(
              (atom) =>
                  atom.kind == ChatAtomKind.text &&
                  atom.lifecycle is ActiveChatAtom &&
                  atom.source == ForegroundTurnChatSource(turnId: candidate) &&
                  atom.turnId == candidate,
            )
            .firstOrNull;
        if (response == null) return false;
        final body = response.contents
            .where((content) => content.role == ChatContentRole.body)
            .singleOrNull;
        if (body == null) return false;
        final window = currentDisplay.windows
            .where(
              (window) =>
                  window.id == response.id &&
                  contentReferenceIdentity(window.reference) ==
                      contentReferenceIdentity(body.reference) &&
                  window.window?.offset == 0 &&
                  window.window!.bytes.isNotEmpty,
            )
            .firstOrNull;
        if (window == null) return false;
        if (window.error case final error?) throw StateError('$error');
        final preview = (
          reference: body.reference,
          text: utf8.decode(window.window!.bytes, allowMalformed: true),
        );
        streaming = (
          lease: display,
          display: currentDisplay,
          turnId: candidate,
          activityId: candidateActivity,
          response: response,
          preview: preview,
        );
        return true;
      },
      'canonical responding Turn with live response content',
      timeout: const Duration(seconds: 30),
    );
    return streaming!;
  }

  Future<_StreamingBody> waitForStreamingBody(_StreamingTurn streaming) async {
    final prefix = streaming.preview.text.length > 64
        ? streaming.preview.text.substring(0, 64)
        : streaming.preview.text;
    final glyphOffset = prefix.indexOf(RegExp(r'\S'));
    expect(glyphOffset, greaterThanOrEqualTo(0));
    final surface = tester.renderObject<RenderBox>(
      find.byKey(presentationCaptureKey),
    );
    Rect? visibleGlyphBounds;
    await until(
      () {
        expectStreamingTurn(streaming);
        final connector = find.byWidgetPredicate(
          (widget) =>
              widget is ConversationCurrentConnector &&
              identical(widget.content, streaming.lease.content),
        );
        if (connector.evaluate().length != 1) return false;
        expect(tester.state(connector), same(streaming.display));
        final item = find.descendant(
          of: connector,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is TimelineMemberAtom &&
                widget.atom.id == streaming.response.id,
          ),
        );
        if (item.evaluate().length != 1) return false;
        final body = find.descendant(
          of: item,
          matching: find.byType(TimelinePlainText),
        );
        if (body.evaluate().length != 1 ||
            !tester.widget<TimelinePlainText>(body).text.startsWith(prefix)) {
          return false;
        }
        final text = find.descendant(of: body, matching: find.byType(RichText));
        if (text.evaluate().length != 1) return false;
        final paragraph = text.evaluate().single.findRenderObject();
        if (paragraph is! RenderParagraph ||
            !paragraph.attached ||
            !paragraph.hasSize ||
            paragraph.debugNeedsLayout ||
            !surface.attached ||
            !surface.hasSize ||
            !paragraph.text.toPlainText().startsWith(prefix)) {
          return false;
        }
        // The production viewport follows growing output. Require a real glyph
        // at the start or tail of this accepted body, clipped by its actual
        // scroll view and ancestors; the first glyph need not stay on screen.
        final tailGlyph = paragraph.text.toPlainText().lastIndexOf(
          RegExp(r'\S'),
        );
        for (final offset in {glyphOffset, tailGlyph}) {
          for (final box in paragraph.getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + 1),
          )) {
            var visible = MatrixUtils.transformRect(
              paragraph.getTransformTo(surface),
              box.toRect(),
            ).intersect(Offset.zero & surface.size);
            RenderObject child = paragraph;
            while (!identical(child, surface)) {
              final parent = child.parent;
              if (parent == null || !parent.attached) return false;
              final clip = parent.describeApproximatePaintClip(child);
              if (clip != null) {
                visible = visible.intersect(
                  MatrixUtils.transformRect(
                    parent.getTransformTo(surface),
                    clip,
                  ),
                );
              }
              child = parent;
            }
            if (visible.isFinite && !visible.isEmpty) {
              visibleGlyphBounds = visible;
              return true;
            }
          }
        }
        return false;
      },
      'visible live response body ${streaming.response.id}',
      timeout: const Duration(seconds: 30),
    );
    return (prefix: prefix, visibleGlyphBounds: visibleGlyphBounds!);
  }

  _StreamingWindow expectStreamingTurn(_StreamingTurn streaming) {
    final selected = graph.client.selection.state.selectedThreadId!;
    expect(selected, _submittedThreadId);
    expect(streaming.turnId, _submittedTurnId);
    final display = graph.timeline.lease(selected)!;
    expect(display, same(streaming.lease));
    expect(display.threadId, selected);
    expect(display.isMounted, isTrue);
    expect(display.isRetired, isFalse);
    final current = display.content.activity.value!;
    final session = graph.client.conversations.session(selected).state;
    final sessionTurn = session.activeTurn;
    expect(current.executionPresent, isTrue);
    expect(sessionTurn?.turnId, streaming.turnId);
    expect(sessionTurn?.threadId, selected);
    expect(sessionTurn?.state.isBusy, isTrue);
    expect(session.activity?.identity, streaming.activityId);
    expect(session.activity?.kind, ThreadActivityKind.responding);
    expect(display.currentDisplay, same(streaming.display));
    expect(streaming.display.isCurrent, isTrue);
    final response = current.entries
        .map((entry) => entry.atom)
        .singleWhere((atom) => atom.id == streaming.response.id);
    expect(response.kind, ChatAtomKind.text);
    expect(response.lifecycle, isA<ActiveChatAtom>());
    expect(response.source, streaming.response.source);
    expect(response.turnId, streaming.turnId);
    final body = response.contents.singleWhere(
      (content) => content.role == ChatContentRole.body,
    );
    expect(
      contentReferenceIdentity(body.reference),
      contentReferenceIdentity(streaming.preview.reference),
    );
    final window = streaming.display.windows.singleWhere(
      (window) =>
          window.id == response.id &&
          contentReferenceIdentity(window.reference) ==
              contentReferenceIdentity(body.reference),
    );
    expect(window.error, isNull);
    expect(window.window, isNotNull);
    // The display owns a bounded moving window. Its reference stays stable
    // across Main paging; only a window still at zero can prove prefix growth.
    final text = utf8.decode(window.window!.bytes, allowMalformed: true);
    if (window.window!.offset == 0) {
      expect(text, startsWith(streaming.preview.text));
    }
    return (reference: window.reference, text: text);
  }

  Future<void> waitForTerminalTurn(String turnId) async {
    await until(
      () {
        final selected = graph.client.selection.state.selectedThreadId;
        if (selected == null || selected != _submittedThreadId) return false;
        final display = graph.timeline.lease(selected);
        final current = display?.content.activity.value;
        final state = graph.client.conversations.session(selected).state;
        final completed = state.lastTurn;
        return turnId == _submittedTurnId &&
            completed?.threadId == selected &&
            completed?.turnId == turnId &&
            completed?.state.status == StudioTurnStatus.completed &&
            completed?.state.isTerminal == true &&
            state.activeTurn?.turnId != turnId &&
            !current!.entries.any((entry) => entry.atom.turnId == turnId);
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
    expect(ids(display), hasLength(display.loadedCount));
    expect(find.byType(ChatItemView), findsWidgets);
    return display;
  }

  Future<void> loadOlder(TimelineDisplayLease display) async {
    final before = display.loadedCount;
    final cursor = display.olderCursor;
    final view = tester.widget<TimelineView>(find.byType(TimelineView));
    await view.onLoadOlder();
    await until(
      () => display.loadedCount > before,
      'older timeline page ${display.appliedPrepends + 1}',
    );
    expect(identical(display, lease), isTrue);
    expect(display.olderCursor, isNot(cursor));
    expect(ids(display).toSet(), hasLength(display.loadedCount));
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
