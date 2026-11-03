import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/previews/conversation_live_status_previews.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/content_reference_identity.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_current_views.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
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
      await scene.untilReadableCurrentText(
        timeout: const Duration(seconds: 20),
      );
      await capturePresentation(tester, 'realtime-streaming.png');
      await scene.completed(answer: 'realtime delayed first token');

      await scene.submit('Realtime reasoning then answer');
      await scene.until(
        () =>
            scene.observed.atoms.any(
              (atom) => atom.kind == ChatAtomKind.reasoning,
            ) ||
            scene.observed.live
                .expand((unit) => unit.members)
                .any((atom) => atom.kind == ChatAtomKind.reasoning),
        'real reasoning member admitted',
      );
      await scene.completed(answer: 'realtime reasoning answer');
      await scene.openLatestTurnThinking();
      await capturePresentation(tester, 'realtime-reasoning.png');
      await scene.closeLatestTurnGroups();

      await scene.submit('Realtime long command');
      await scene.untilLaidOutCurrentTools(
        minimum: 2,
        toolCallIds: const {'realtime-long-call', 'realtime-long-wait-call'},
      );
      await capturePresentation(tester, 'realtime-exec-wait.png');
      await scene.completed(answer: 'realtime long command complete');

      final priorParallelAtoms = scene.observed.atoms
          .map((atom) => atom.id)
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
      await scene.verifyExecReceipts(priorParallelAtoms, const {
        'realtime-parallel-call-a': 'realtime-parallel-a-line-05',
        'realtime-parallel-call-b': 'realtime-parallel-b-line-07',
      });

      final priorHostCwdAtoms = scene.observed.atoms
          .map((atom) => atom.id)
          .toSet();
      await scene.submit('Realtime host cwd command');
      await scene.untilLaidOutCurrentTools(
        minimum: 1,
        runningExecCallIds: const {'realtime-host-cwd-call'},
        settleDisclosure: false,
      );
      await capturePresentation(tester, 'realtime-host-cwd-running.png');
      await scene.completed(answer: 'realtime host cwd complete');
      await scene.verifyExecReceipts(priorHostCwdAtoms, const {
        'realtime-host-cwd-call': 'realtime-host-cwd-line-03',
      });

      await scene.submit('Realtime provider error');
      await scene.terminal('failed');
      await capturePresentation(
        tester,
        'realtime-provider-error-collapsed.png',
      );
      final failedTurn = scene._latestTurn()!;
      final failed = await scene.openTurnReceipt(
        failedTurn,
        expectedOutcome: 'failed',
      );
      final failureText = find
          .descendant(
            of: failed,
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
      await scene.closeTurnReceipt(failedTurn);
      await scene.returnAfterReadingHistory();

      await scene.submit('Realtime cancellable stream');
      final cancelledText = await scene.untilReadableCurrentText(
        timeout: const Duration(seconds: 30),
      );
      await capturePresentation(tester, 'realtime-before-cancel.png');
      await scene.tap(find.byKey(StudioDriverKeys.composerStop));
      await scene.terminal('cancelled');
      expect(
        scene.observed.atoms.where((atom) => atom.id == cancelledText.id),
        hasLength(1),
        reason: 'accepted partial text survives cancellation',
      );
      expect(
        scene.lease.currentDisplay?.windows.where(
              (window) => window.id == cancelledText.id,
            ) ??
            const [],
        isEmpty,
      );
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
  late final observed = TimelineObservation(tester, () => lease);

  TimelineDisplayLease get lease =>
      graph.timeline.lease(graph.client.selection.state.selectedThreadId!)!;

  List<ChatItemPresentation> get items => observed.atoms
      .where((atom) => atom.payload != null)
      .map(ChatItemPresentation.decode)
      .toList();

  Future<ChatItemPresentation> openLatestTurnThinking() async {
    final turn = _latestTurn()!;
    final groups = observed.workFor(turn.atom!.source).toList();
    expect(groups, isNotEmpty);
    final reasoning = groups
        .expand((unit) => unit.members)
        .where((atom) => atom.kind == ChatAtomKind.reasoning)
        .toList();
    expect(reasoning, isNotEmpty);
    for (final atom in reasoning) {
      final display = await observed.revealAtom(atom);
      expect(display, isNotNull);
      expect(
        display!.atoms.where((member) => member.id == atom.id),
        hasLength(1),
      );
      await until(
        () => _laidOut(observed.atomRow(atom.id)),
        'reasoning member in its original Main work segment',
      );
      final row = observed.atomRow(atom.id);
      expect(tester.widget<ChatItemView>(row).item.type, 'thinking');
      expect(display.error, isNull);
    }
    return ChatItemPresentation.decode(reasoning.last);
  }

  Future<void> closeLatestTurnGroups() =>
      observed.closeSource(_latestTurn()!.atom!.source);

  Future<Finder> openTurnReceipt(
    ChatItemPresentation turn, {
    required String expectedOutcome,
  }) async {
    expect(turn.atom!.kind, ChatAtomKind.turnReceipt);
    expect((turn.data['outcome'] as Map)['kind'], expectedOutcome);
    await observed.revealAtom(turn.atom!);
    final row = observed.atomRow(turn.atom!.id);
    final header = find
        .descendant(of: row, matching: find.byType(TimelineActivityRow))
        .first;
    if (!tester.widget<TimelineActivityRow>(header).expanded) {
      await tap(
        find
            .descendant(
              of: row,
              matching: find.byType(TimelineActivityDisclosure),
            )
            .first,
      );
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    return row;
  }

  Future<void> closeTurnReceipt(ChatItemPresentation turn) async {
    final row = observed.atomRow(turn.atom!.id);
    final header = find
        .descendant(of: row, matching: find.byType(TimelineActivityRow))
        .first;
    expect(tester.widget<TimelineActivityRow>(header).expanded, isTrue);
    await tap(
      find
          .descendant(
            of: row,
            matching: find.byType(TimelineActivityDisclosure),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<TimelineActivityRow>(header).expanded, isFalse);
  }

  Future<ContentWindow> readDeclaredRange(
    ChatAtom atom,
    ChatContentRole role,
    String fragment,
  ) async {
    final reference = atom.contents
        .singleWhere((content) => content.role == role)
        .reference;
    final connector = find.byWidgetPredicate(
      (widget) =>
          widget is TimelineContentRangeConnector &&
          widget.itemId == atom.id &&
          widget.contentKey == role.name,
    );
    await until(
      () => connector.evaluate().length == 1,
      'declared ${role.name} range of ${atom.tool!.callId}',
    );
    final owner = tester.state(connector) as TimelineCurrentWindowDisplay;
    expect(
      contentReferenceIdentity(owner.reference),
      contentReferenceIdentity(reference),
    );
    final read = find.byKey(
      StudioDriverKeys.timelineContentOpen(atom.id, role.name),
    );
    if (owner.window == null) await tap(read);
    await until(() {
      if (owner.error case final error?) throw StateError('$error');
      return owner.window != null;
    }, 'accepted bounded ${role.name} window');
    final window = owner.window!;
    expect(window.offset, 0);
    expect(window.sealed, isTrue);
    expect(window.bytes, isNotEmpty);
    expect(window.bytes.length, lessThanOrEqualTo(64 * 1024));
    final text = utf8.decode(window.bytes);
    expect(text, contains(fragment));
    final rendered = find.byKey(
      StudioDriverKeys.timelineContentWindow(atom.id, role.name),
    );
    await until(() => _laidOut(rendered), 'actual bounded body text');
    await _revealTextFragment(tester, rendered, fragment);
    expect(owner.window, same(window));
    return window;
  }

  Future<void> verifyExecReceipts(
    Set<String> priorAtomIds,
    Map<String, String> expected,
  ) async {
    bool requestedResult(ChatAtom atom) {
      if (priorAtomIds.contains(atom.id) ||
          !expected.containsKey(atom.tool?.callId) ||
          atom.payload == null) {
        return false;
      }
      final reading = ChatItemPresentation.decode(atom).toolCard;
      return reading is DecodedToolCard &&
          reading.value.statusString == 'succeeded';
    }

    await until(
      () => expected.keys.every(
        (call) =>
            observed.atoms
                .where(requestedResult)
                .where((atom) => atom.tool!.callId == call)
                .length ==
            1,
      ),
      'all exact completed exec receipts in real Main units',
    );
    final targets = observed.atoms.where(requestedResult).toList();
    expect(
      targets.map((atom) => atom.tool!.callId).toSet(),
      expected.keys.toSet(),
    );
    expect(targets, hasLength(expected.length));
    final controller = lease.controller;
    final mainSets = lease.appliedSets;
    final witnessed = <String>{};
    try {
      for (final atom in targets) {
        final group = await observed.revealAtom(atom);
        final item = ChatItemPresentation.decode(atom);
        final tool = (item.toolCard as DecodedToolCard).value;
        final lastLine = expected[tool.toolCallId]!;
        expect(tool.name, 'exec');
        expect(tool.statusString, 'succeeded');
        expect(tool.exitCode, 0);
        expect(tool.output, contains(lastLine));
        final details = find.descendant(
          of: observed.atomRow(atom.id),
          matching: find.byType(TimelineToolDetails),
        );
        expect(details, findsOneWidget);
        final renderedTool = tester.widget<TimelineToolDetails>(details).item;
        expect(renderedTool.toolCallId, tool.toolCallId);
        expect(renderedTool.statusString, 'succeeded');
        final disclosure = find
            .descendant(
              of: details,
              matching: find.byType(TimelineActivityDisclosure),
            )
            .first;
        final title = find
            .descendant(
              of: disclosure,
              matching: find.byType(TimelineActivityRow),
            )
            .first;
        if (!tester.widget<TimelineActivityRow>(title).expanded) {
          await tap(disclosure);
        }
        final output = await readDeclaredRange(
          atom,
          ChatContentRole.toolOutput,
          lastLine,
        );
        final outputBorrow = tester.state(
          find.byWidgetPredicate(
            (widget) =>
                widget is TimelineContentRangeConnector &&
                widget.itemId == atom.id &&
                widget.contentKey == ChatContentRole.toolOutput.name,
          ),
        ) as TimelineCurrentWindowDisplay;
        if (tool.toolCallId == 'realtime-host-cwd-call') {
          final arguments = await readDeclaredRange(
            atom,
            ChatContentRole.toolArguments,
            'cwd',
          );
          final cwd =
              (jsonDecode(utf8.decode(arguments.bytes)) as Map)['cwd']
                  as String;
          expect(cwd, isNotEmpty);
          expect(tool.output, contains('realtime-host-cwd-actual:$cwd'));
        }
        if (group != null) {
          expect(group.error, isNull);
          expect(group.expanded && group.isCurrent, isTrue);
          expect(
            group.atoms.where((member) => member.id == atom.id),
            hasLength(1),
          );
        } else {
          // A real independent/background result is its own Main receipt, not
          // force-fit into the latest foreground group.
          expect(observed.unitForAtom(atom.id).kind, TimelineUnitKind.receipt);
        }
        expect(lease.controller, same(controller));
        expect(lease.appliedSets, mainSets);
        expect(witnessed.add(tool.toolCallId), isTrue);
        debugPrintSynchronously(
          'Exec receipt laid out: ${jsonEncode({'callId': tool.toolCallId, 'atomId': atom.id, 'state': tool.statusString, 'sourceOrder': atom.sourceOrder, 'lastLine': lastLine, 'groupId': group?.unitId, 'outputBytes': output.bytes.length})}',
        );
        await capturePresentation(
          tester,
          'realtime-${tool.toolCallId}-succeeded.png',
        );
        if (group != null) {
          await observed.closeGroup(group);
        } else {
          await tap(disclosure);
        }
        await until(
          () => outputBorrow.window == null,
          'collapsed member revokes its original bounded output borrow',
        );
      }
      expect(witnessed, expected.keys.toSet());
      await returnAfterReadingHistory();
    } catch (_) {
      final scroll = lease.scrollController;
      debugPrintSynchronously(
        'Exec receipt navigation failure: ${jsonEncode({'mode': lease.mode.name, 'pixels': scroll.hasClients ? scroll.position.pixels : null, 'maxExtent': scroll.hasClients ? scroll.position.maxScrollExtent : null, 'witnessed': witnessed.toList()})}',
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

  Future<ChatAtom> untilReadableCurrentText({required Duration timeout}) async {
    ChatAtom? accepted;
    await until(
      () {
        final candidates = observed.live
            .where((unit) => unit.kind == TimelineUnitKind.text)
            .expand((unit) => unit.members)
            .where(
              (atom) =>
                  atom.kind == ChatAtomKind.text &&
                  atom.lifecycle is ActiveChatAtom,
            );
        for (final atom in candidates) {
          final view = find.byWidgetPredicate(
            (widget) =>
                widget is ConversationCurrentWindowView &&
                widget.id == atom.id &&
                widget.error == null &&
                widget.text.isNotEmpty,
          );
          if (!_laidOut(view)) continue;
          final windows =
              lease.currentDisplay?.windows
                  .where((window) => window.id == atom.id)
                  .toList() ??
              const [];
          for (final window in windows) {
            if (window.error case final error?) throw StateError('$error');
          }
          if (windows.isEmpty ||
              windows.every((window) => window.window == null)) {
            continue;
          }
          expect(
            atom.contents.any(
              (content) => windows.any(
                (window) =>
                    contentReferenceIdentity(content.reference) ==
                    contentReferenceIdentity(window.reference),
              ),
            ),
            isTrue,
          );
          accepted = atom;
          return true;
        }
        return false;
      },
      'readable production live text with its original content-window borrow',
      timeout: timeout,
    );
    return accepted!;
  }

  // Live atoms without a completion payload use the real tool disclosure,
  // including wait. Only a completed wait payload has a TimelineWaitPanel.
  Finder currentToolCard(ChatAtom atom) =>
      atom.payload != null && atom.tool?.name == 'wait'
      ? find.byWidgetPredicate(
          (widget) => widget is TimelineWaitPanel && widget.identity == atom.id,
        )
      : find.byWidgetPredicate(
          (widget) =>
              widget is TimelineToolDetails &&
              widget.item.id == atom.id &&
              widget.item.toolCallId == atom.tool?.callId &&
              widget.item.name == atom.tool?.name,
        );

  Future<void> untilLaidOutCurrentTools({
    required int minimum,
    Set<String> toolCallIds = const {},
    Set<String> runningExecCallIds = const {},
    bool settleDisclosure = true,
  }) async {
    final clock = Stopwatch()..start();
    var settled = !settleDisclosure;
    try {
      while (true) {
        final units = observed.live
            .where(
              (unit) => unit.members.any(
                (atom) => atom.kind == ChatAtomKind.toolCall,
              ),
            )
            .toList();
        for (final unit in units) {
          await observed.openGroup(unit.id);
        }
        final tools = observed.live
            .expand((unit) => unit.members)
            .where((atom) => atom.kind == ChatAtomKind.toolCall)
            .toList();
        final running = tools
            .where(
              (atom) =>
                  atom.tool?.name == 'exec' && atom.lifecycle is ActiveChatAtom,
            )
            .map((atom) => atom.tool!.callId)
            .toSet();
        final expectedCallIds = {...toolCallIds, ...runningExecCallIds};
        final required = expectedCallIds.isEmpty
            ? tools
            : tools
                  .where((atom) => expectedCallIds.contains(atom.tool?.callId))
                  .toList();
        final laidOut = required
            .where((atom) => _laidOut(currentToolCard(atom)))
            .length;
        if (tools.length >= minimum &&
            required.isNotEmpty &&
            required
                .map((atom) => atom.tool?.callId)
                .toSet()
                .containsAll(expectedCallIds) &&
            laidOut == required.length &&
            running.containsAll(runningExecCallIds)) {
          if (!settled) {
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
            settled = true;
            continue;
          }
          expect(
            required.map((atom) => atom.tool?.callId).toSet(),
            hasLength(required.length),
          );
          for (final atom in required) {
            final title = find.descendant(
              of: currentToolCard(atom),
              matching: find.byType(TimelineActivityRow),
            );
            expect(title, findsOneWidget);
            expect(_laidOut(title), isTrue);
            final row = tester.widget<TimelineActivityRow>(title);
            expect(row.label.trim(), isNotEmpty);
            // A full-width row's center can be empty space. The real title
            // inside this exact atom's tool card must remain readable/hittable.
            final label = find.descendant(
              of: title,
              matching: find.text(row.label),
            );
            expect(label, findsOneWidget);
            expect(_laidOut(label), isTrue);
            expect(label.hitTestable(), findsOneWidget);
          }
          for (final call in runningExecCallIds) {
            final atom = required.singleWhere(
              (atom) => atom.tool?.callId == call,
            );
            final widget = tester.widget<TimelineToolDetails>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TimelineToolDetails && widget.item.id == atom.id,
              ),
            );
            expect(widget.item.statusString, 'running');
          }
          for (var index = 1; index < required.length; index++) {
            expect(
              tester.getTopLeft(currentToolCard(required[index])).dy,
              greaterThanOrEqualTo(
                tester.getTopLeft(currentToolCard(required[index - 1])).dy,
              ),
              reason: 'rendered tools retain the owner-provided member order',
            );
          }
          debugPrintSynchronously(
            'Realtime current tools: ${jsonEncode({'minimum': minimum, 'atomIds': tools.map((atom) => atom.id).toList(), 'callIds': tools.map((atom) => atom.tool?.callId).toList(), 'exactRunningExecIds': running.toList(), 'laidOut': laidOut, 'contentWindows': lease.currentDisplay?.windows.length})}',
          );
          return;
        }
        if (clock.elapsed >= const Duration(minutes: 3)) {
          fail('Timed out waiting for $minimum real current tool cards');
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
    return items.where((item) => item.type == 'turn').lastOrNull;
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
