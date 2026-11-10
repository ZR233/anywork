import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/timeline_observation.dart';
import 'support/presentation_capture.dart';
import 'support/wait_selection_trace.dart';

typedef _StartedBackgroundTask = ({String callId, String taskId});

// Real AppGraph/FRB/SQLite and production routes. Only the native exit shell is
// omitted: the official test runner, not StudioExitCoordinator, owns this process.
// No driver_main, requestData protocol, copied timeline, or synthetic business state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  late AppGraph graph;
  late WaitSelectionTrace trace;
  final projectRoot = Platform.environment['ANYWORK_WAIT_PROJECTS'];
  final captureReport = <String, Object?>{
    'scenario': 'wait-events',
    'runner': 'flutter.integration_test',
    'coverageGaps': {
      'permissionApproval':
          'The existing wait stories do not request approval.',
      'storageFailure':
          'No visible storage failure is produced by these stories.',
    },
    'presentationCaptures': <Map<String, Object?>>[],
  };

  setUpAll(() async {
    expect(
      projectRoot,
      isNotNull,
      reason: 'Use cargo xtask test-project --suite desktop --case wait_events',
    );
    graph = createProductionAppGraph();
    trace = WaitSelectionTrace(graph, captureReport);
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
      trace.close();
      final traceOutput = Platform.environment['ANYWORK_WAIT_TRACE_OUTPUT'];
      if (traceOutput != null) await trace.write(traceOutput);
      final directory =
          Platform.environment['ANYWORK_PRESENTATION_SCREENSHOTS'];
      if (directory != null && directory.isNotEmpty) {
        await File('$directory/wait-events-captures.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(captureReport)}\n',
        );
      }
    }
  });

  Future<_Scene> open(WidgetTester tester, String name) async {
    // Match production's root ProviderScope lifetime. Each test mounts a new
    // application root, so it must not inherit the scheduler of a disposed
    // UncontrolledProviderScope from a previous test. The application graph,
    // SDK and timeline owner remain shared and close only in tearDownAll.
    final container = ProviderContainer(
      observers: [trace],
      overrides: [
        appGraphProvider.overrideWithValue(graph),
        statisticsRepositoryProvider.overrideWithValue(
          graph.statisticsRepository,
        ),
      ],
    );
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
        expect(
          (await graph.client.conversations.retryCleanup(
            deadline: DateTime.now().add(const Duration(seconds: 5)),
          )).complete,
          isTrue,
        );
      } finally {
        container.dispose();
        tester.testTextInput.unregister();
        FlutterError.onError = testErrorHandler;
      }
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: presentationCaptureKey,
        child: UncontrolledProviderScope(
          container: container,
          child: const AnyworkApp(enableDesktopHost: false),
        ),
      ),
    );
    captureReport['nativeWindow'] = await configurePresentationWindow(tester);
    trace.snapshot(tester, name, 'before-open-project');
    await graph.client.directoryCommands.openProject('$projectRoot/$name');
    trace.snapshot(tester, name, 'after-open-project');
    return _Scene(tester, graph, name, captureReport, trace);
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
      final turn = await scene.completedTurn();
      final wait = await scene.tool(turn, prefix);
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
      await scene.capture(
        'wait-events-$name-ready.png',
        '[[wait_${name.replaceAll('-', '_')}]]; immutable ready result expanded',
        'Real any-of result: one task succeeded while the other was still running.',
        wait.atom!,
      );

      if (name == 'sleep-first') {
        final previous = scene.latestTurnId;
        await scene.closeTurn(turn);
        await scene.submit('[[wait_already_ready]]');
        final ready = await scene.completedTurn(after: previous);
        expect(
          scene.result(
            await scene.tool(ready, 'already-ready-wait-t'),
          )['timedOut'],
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
    final turn = await scene.completedTurn();
    final wait = await scene.tool(turn, 'timeout-wait-t');
    final result = scene.result(wait);
    expect(result['timedOut'], isTrue);
    final target = (result['tasks'] as List).single as Map;
    expect(target['status'], 'running');
    expect(target['cancelRequested'], isFalse);
    await scene.expandWait(wait, ThreadWaitStateView.timedOut);
    await scene.capture(
      'wait-events-timeout-result.png',
      '[[wait_timeout]]; immutable timeout result expanded',
      'Real timedOut result does not imply cancellation of its running task.',
      wait.atom!,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('child wakes parent; a later request retains one report', (
    tester,
  ) async {
    final scene = await open(tester, 'child');
    await scene.submit('[[wait_child]]');
    final turn = await scene.completedTurn();
    final result = scene.result(await scene.tool(turn, 'child-wait-t'));
    expect(result['messagesReady'], isTrue);
    final previous = scene.latestTurnId;
    await scene.closeTurn(turn);
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
    late _StartedBackgroundTask startedTask;
    final prepared = await scene.completedTurn(
      readBackgroundStart: (turn) async {
        final started = await scene.tool(
          turn,
          'cancel-sleep-t',
          status: 'backgroundStarted',
        );
        final card = (started.toolCard as DecodedToolCard).value;
        expect(card.taskId, isNotNull);
        startedTask = (callId: card.toolCallId, taskId: card.taskId!);
        debugPrint('WAIT_BACKGROUND_STARTED $startedTask');
        return startedTask;
      },
    );
    final taskId = startedTask.taskId;
    expect(taskId, isA<String>());
    scene.expectBackgroundTaskLive(prepared, startedTask);
    final prepareTurn = scene.latestTurnId;
    await scene.closeTurn(prepared);
    await scene.submit('[[wait_cancel]]');
    // The typed live Work and original member window below prove the exact
    // running call; the GUI no longer consumes the atomic Activity channel.
    await scene.currentWaiting('cancel-wait-t');
    await scene.tap(find.byKey(const ValueKey('composer-stop')));
    final stopped = await scene.completedTurn(
      after: prepareTurn,
      outcome: StudioTurnStatus.cancelled,
    );
    final stoppedReceipt = await scene.turnReceipt(
      stopped,
      ChatTerminalOutcome.cancelled,
    );
    expect(stoppedReceipt.atom!.kind, ChatAtomKind.turnReceipt);
    scene.expectBackgroundTaskLive(prepared, startedTask);
    final stoppedTurn = scene.latestTurnId;
    await scene.closeTurn(stopped);
    await scene.submit('[[wait_cancel_query]]');
    final queried = await scene.completedTurn(after: stoppedTurn);
    final result = scene.result(await scene.tool(queried, 'cancel-query-t'));
    final task = result['task'] as Map;
    expect(task['taskId'], taskId);
    expect(task['status'], 'running');
    expect(task['cancelRequested'], isFalse);
    expect(
      (await scene.tool(queried, 'cancel-query-cancel-t')).toolCard,
      isA<DecodedToolCard>(),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

final class _Scene {
  _Scene(this.tester, this.graph, this.name, this.captureReport, this.trace);
  final WidgetTester tester;
  final AppGraph graph;
  final String name;
  final Map<String, Object?> captureReport;
  final WaitSelectionTrace trace;
  String? latestTurnId;
  String? _submittedThreadId;
  String? _priorTurnId;
  String? _submittedTurnId;

  TimelineDisplayLease get lease =>
      graph.timeline.lease(graph.client.selection.state.selectedThreadId!)!;
  late final observed = TimelineObservation(tester, () => lease);

  Future<void> capture(
    String fileName,
    String stage,
    String coverage,
    ChatAtom atom,
  ) async {
    final evidence = <String, Object?>{
      'fileName': fileName,
      'fixtureStage': stage,
      'coverage': coverage,
      'threadId': lease.threadId,
      'turnId': atom.turnId,
      'blockId': observed.unitForMember(atom.id).id,
      'memberId': atom.id,
      'toolCallId': atom.tool?.callId,
      'waitState': atom.wait?.state.name,
      'captureRequested':
          Platform
              .environment['ANYWORK_PRESENTATION_SCREENSHOTS']
              ?.isNotEmpty ??
          false,
      'captureCompleted': false,
    };
    (captureReport['presentationCaptures'] as List<Map<String, Object?>>).add(
      evidence,
    );
    await capturePresentation(tester, fileName);
    expect(tester.takeException(), isNull);
    evidence['captureCompleted'] = evidence['captureRequested'];
  }

  Future<void> until(
    FutureOr<bool> Function() ready,
    String description, {
    Duration timeout = const Duration(seconds: 60),
    String Function()? diagnostic,
  }) async {
    final clock = Stopwatch()..start();
    while (true) {
      final remaining = timeout - clock.elapsed;
      if (await Future<bool>.sync(ready).timeout(
        remaining > Duration.zero ? remaining : Duration.zero,
        onTimeout: () => false,
      )) {
        return;
      }
      if (clock.elapsed >= timeout) {
        final details = diagnostic?.call();
        fail(
          'Timed out waiting for $description'
          '${details == null ? '' : '\n$details'}',
        );
      }
      await tester.pump(const Duration(milliseconds: 50));
      trace.snapshot(tester, name, 'pump');
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
    // SDK project selection can precede its keyed composer subtree. An input
    // from the previous workspace must not qualify the new submission.
    final composerTarget = find.byWidgetPredicate((widget) {
      if (widget is! PromptComposerView) return false;
      final selection = graph.client.selection.state;
      return widget.pasteTargetId ==
              (selection.selectedThreadId ?? selection.selectedProjectId) &&
          widget.enabled &&
          !widget.submissionLocked;
    });
    final input = find.descendant(
      of: composerTarget,
      matching: find.byKey(const ValueKey('composer-input')),
    );
    await until(
      () => input.evaluate().length == 1,
      'composer for the actual selected target',
    );
    try {
      trace.snapshot(tester, name, 'before-enter');
      await tester.enterText(input, prompt);
      trace.snapshot(tester, name, 'after-enter');
      await tester.pump();
      trace.snapshot(tester, name, 'after-enter-pump');
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
    } catch (error, stack) {
      trace.dump();
      try {
        final composer = tester
            .widgetList<PromptComposerView>(find.byType(PromptComposerView))
            .singleOrNull;
        final selected = graph.client.selection.state.selectedThreadId;
        final diagnostic = {
          'scene': name,
          'error': error.toString(),
          'selectedThreadId': selected,
          'selectionNeedsOpen': graph.client.selection.state.needsOpen,
          'workspacePaneThreadIds': [
            for (final pane in tester.widgetList<AgentWorkspacePane>(
              find.byType(AgentWorkspacePane, skipOffstage: false),
            ))
              pane.threadId,
          ],
          'text': tester
              .widgetList<TextField>(input)
              .singleOrNull
              ?.controller
              ?.text,
          'draft': composer?.composer.draft,
          'pending': composer?.composer.isSubmissionPending,
          'sdkDraft': selected == null
              ? null
              : graph.client.drafts.existingComposer(selected)?.state.draft,
          'execution': composer?.execution?.id,
          'blocker': composer?.blocker?.runtimeType.toString(),
          'failure': composer?.failure?.runtimeType.toString(),
          'enabled': composer?.enabled,
          'locked': composer?.submissionLocked,
        };
        captureReport['submissionFailure:$name'] = diagnostic;
        debugPrintSynchronously(
          'WAIT_SUBMISSION_FAILURE ${jsonEncode(diagnostic)}',
        );
        await capturePresentation(
          tester,
          'wait-events-$name-submission-failure.png',
        );
      } catch (diagnosticError) {
        debugPrintSynchronously(
          'WAIT_SUBMISSION_DIAGNOSTIC_FAILURE ${diagnosticError.runtimeType}',
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<StudioTurnView> waitForTurn({
    String? after,
    StudioTurnStatus outcome = StudioTurnStatus.completed,
    Future<_StartedBackgroundTask> Function(StudioTurnView)?
    readBackgroundStart,
  }) async {
    StudioTurnView? turn;
    _StartedBackgroundTask? backgroundTask;
    Future<bool> ready({bool checkActivity = true}) async {
      final id = graph.client.selection.state.selectedThreadId;
      if (id == null) return false;
      _submittedThreadId ??= id;
      if (id != _submittedThreadId) return false;
      final candidate = graph.client.conversations.session(id).state.lastTurn;
      if (candidate == null ||
          candidate.threadId != id ||
          candidate.turnId == _priorTurnId ||
          candidate.turnId == after) {
        return false;
      }
      _submittedTurnId ??= candidate.turnId;
      if (candidate.turnId != _submittedTurnId) return false;
      turn = candidate;
      final originalLease = graph.timeline.lease(id);
      if (!candidate.state.isTerminal ||
          candidate.state.status != outcome ||
          originalLease == null ||
          !originalLease.isMounted ||
          originalLease.isRetired) {
        return false;
      }
      final source = ForegroundTurnChatSource(turnId: candidate.turnId);
      // State proves completion; Main must separately accept this source and
      // mount its original viewport within this same wait budget before reveal.
      // An independent background timer may still be live after this Turn.
      if (observed.liveBlocks.any((block) => block.source == source)) {
        return false;
      }
      final mainScrollable = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            identical(widget.controller, originalLease.scrollController),
      );
      if (mainScrollable.evaluate().length != 1) return false;
      if (!await observed.hasHistoricalSource(source)) return false;
      // A bounded member query cannot qualify a later selection/generation.
      if (graph.client.selection.state.selectedThreadId != id ||
          !identical(graph.timeline.lease(id), originalLease) ||
          !originalLease.isMounted ||
          originalLease.isRetired) {
        return false;
      }
      final current = graph.client.conversations
          .existingSession(id)
          ?.state
          .lastTurn;
      if (current?.turnId != candidate.turnId ||
          current?.state.isTerminal != true ||
          current?.state.status != outcome ||
          observed.liveBlocks.any((block) => block.source == source)) {
        return false;
      }
      if (checkActivity && backgroundTask != null) {
        final tools = graph.client.conversations
            .existingSession(id)
            ?.state
            .activity
            ?.tools;
        if (tools == null ||
            tools.active.length != 1 ||
            tools.background != 1 ||
            !_matchesBackgroundTask(tools.active.single, backgroundTask)) {
          return false;
        }
      }
      if (outcome == StudioTurnStatus.cancelled) {
        final receipts = observed.singleBlocks
            .where(
              (item) =>
                  item.atom!.source == source &&
                  item.atom!.kind == ChatAtomKind.turnReceipt,
            )
            .toList();
        expect(receipts.length, lessThanOrEqualTo(1));
        return (receipts.singleOrNull?.atom?.lifecycle as TerminalChatAtom?)
                ?.outcome ==
            ChatTerminalOutcome.cancelled;
      }
      return true;
    }

    const budget = Duration(seconds: 60);
    final clock = Stopwatch()..start();
    try {
      if (readBackgroundStart != null) {
        // Main must accept the real source before reading its original handoff.
        // The source and exact live-task checks share the original wait budget.
        await until(
          () => ready(checkActivity: false),
          '${outcome.name} Turn Main source for background handoff',
          timeout: budget,
        );
        backgroundTask = await readBackgroundStart(turn!);
      }
      final remaining = budget - clock.elapsed;
      if (remaining <= Duration.zero) {
        fail('Timed out waiting for ${outcome.name} Turn');
      }
      await until(
        () => ready(),
        '${outcome.name} Turn',
        timeout: remaining,
        diagnostic: () {
          final id = graph.client.selection.state.selectedThreadId;
          final candidate = id == null
              ? null
              : graph.client.conversations.session(id).state.lastTurn;
          final originalLease = id == null ? null : graph.timeline.lease(id);
          final source = candidate == null
              ? null
              : ForegroundTurnChatSource(turnId: candidate.turnId);
          final liveBlocks = originalLease == null
              ? const <LiveDisplayBlock>[]
              : observed.liveBlocks
                    .where((block) => block.source == source)
                    .toList();
          final activities = id == null
              ? const <ThreadActivityToolEntry>[]
              : graph.client.conversations
                        .existingSession(id)
                        ?.state
                        .activity
                        ?.tools
                        .active ??
                    const <ThreadActivityToolEntry>[];
          final mainTools = originalLease == null
              ? const <String>[]
              : observed.mountedMembers
                    .where(
                      (atom) =>
                          atom.source == source &&
                          atom.tool != null &&
                          atom.lifecycle is TerminalChatAtom,
                    )
                    .map(_toolDiagnostic)
                    .toList();
          final viewportCount = originalLease == null
              ? null
              : find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is Scrollable &&
                          identical(
                            widget.controller,
                            originalLease.scrollController,
                          ),
                    )
                    .evaluate()
                    .length;
          return 'selectedThread=$id submittedThread=$_submittedThreadId '
              'submittedTurn=$_submittedTurnId priorTurn=$_priorTurnId after=$after '
              'candidate=${candidate?.turnId}/${candidate?.state.status} '
              'terminal=${candidate?.state.isTerminal} expected=$outcome '
              'lease=${originalLease != null} viewportCount=$viewportCount '
              'sameSourceLiveBlocks=${liveBlocks.map((block) => block.id).toList()}\n'
              'activeTools=${activities.map(_activityDiagnostic).toList()}\n'
              'sameSourceMountedCompletedTools=$mainTools';
        },
      );
    } catch (_) {
      trace.snapshot(tester, name, 'turn-failure');
      trace.dump();
      final failureKey = 'turnWaitFailure:$name:${outcome.name}';
      if (!captureReport.containsKey(failureKey)) {
        final selected = graph.client.selection.state.selectedThreadId;
        final sessionId = selected ?? _submittedThreadId;
        try {
          final cut = timelineWaitFailureSnapshot(
            tester: tester,
            selectedThreadId: selected,
            submittedThreadId: _submittedThreadId,
            submittedTurnId: _submittedTurnId,
            previousTurnId: _priorTurnId,
            afterTurnId: after,
            targetTurnId: turn?.turnId,
            expectedOutcome: outcome.name,
            lease: selected == null ? null : graph.timeline.lease(selected),
            session: sessionId == null
                ? null
                : graph.client.conversations.existingSession(sessionId)?.state,
          );
          cut.addAll({
            'scene': name,
            'selectionNeedsOpen': graph.client.selection.state.needsOpen,
            'workspacePaneThreadIds': [
              for (final pane in tester.widgetList<AgentWorkspacePane>(
                find.byType(AgentWorkspacePane, skipOffstage: false),
              ))
                pane.threadId,
            ],
            'ownerSourceThreadId': graph.timeline.source.value?.threadId,
            'connectorOnstage': find
                .byType(TimelineConnector)
                .evaluate()
                .length,
            'connectorAll': find
                .byType(TimelineConnector, skipOffstage: false)
                .evaluate()
                .length,
            'timelineViewOnstage': find.byType(TimelineView).evaluate().length,
            'timelineViewAll': find
                .byType(TimelineView, skipOffstage: false)
                .evaluate()
                .length,
          });
          captureReport[failureKey] = cut;
          debugPrintSynchronously('WAIT_TURN_FAILURE ${jsonEncode(cut)}');
          await capturePresentation(
            tester,
            'wait-events-$name-${outcome.name}-failure.png',
          );
        } catch (diagnosticError) {
          captureReport['$failureKey:diagnostic'] = {
            'diagnosticFailureKind': diagnosticError.runtimeType.toString(),
          };
          debugPrintSynchronously(
            'WAIT_TURN_FAILURE ${jsonEncode(captureReport['$failureKey:diagnostic'])}',
          );
        }
      }
      rethrow;
    }
    final original = turn!;
    latestTurnId = original.turnId;
    expect(original.state.status, outcome);
    return original;
  }

  bool _matchesBackgroundTask(
    ThreadActivityToolEntry entry,
    _StartedBackgroundTask task,
  ) =>
      entry.callId == task.callId &&
      entry.taskId == task.taskId &&
      entry.state == ThreadActivityToolState.running;

  void expectBackgroundTaskLive(
    StudioTurnView sourceTurn,
    _StartedBackgroundTask task,
  ) {
    expect(graph.client.selection.state.selectedThreadId, sourceTurn.threadId);
    final activity = graph.client.conversations
        .existingSession(sourceTurn.threadId)
        ?.state
        .activity;
    expect(activity, isNotNull);
    expect(activity!.threadId, sourceTurn.threadId);
    final activities = activity.tools.active;
    expect(activities, hasLength(1));
    expect(activity.tools.background, 1);
    expect(_matchesBackgroundTask(activities.single, task), isTrue);
    debugPrint(
      'WAIT_BACKGROUND_LIVE callId=${task.callId} taskId=${task.taskId} '
      'sourceTurn=${sourceTurn.turnId} ${_activityDiagnostic(activities.single)}',
    );
  }

  String _activityDiagnostic(ThreadActivityToolEntry entry) =>
      'callId=${entry.callId} taskId=${entry.taskId} name=${entry.name} '
      'state=${entry.state.name} ordinal=${entry.ordinal} '
      'startedAt=${entry.startedAt}';

  String _toolDiagnostic(ChatAtom atom) {
    final card = atom.tool == null || atom.payload == null
        ? null
        : ChatItemPresentation.decode(atom).toolCard;
    final taskId = card is DecodedToolCard ? card.value.taskId : null;
    final status = card is DecodedToolCard ? card.value.statusString : null;
    return 'atomId=${atom.id} kind=${atom.kind} '
        'callId=${atom.tool?.callId} taskId=$taskId status=$status '
        'lifecycle=${atom.lifecycle.runtimeType} '
        'payload=${atom.payload.runtimeType}';
  }

  Future<StudioTurnView> completedTurn({
    String? after,
    StudioTurnStatus outcome = StudioTurnStatus.completed,
    Future<_StartedBackgroundTask> Function(StudioTurnView)?
    readBackgroundStart,
  }) async {
    final original = await waitForTurn(
      after: after,
      outcome: outcome,
      readBackgroundStart: readBackgroundStart,
    );
    final source = ForegroundTurnChatSource(turnId: original.turnId);
    expect(await observed.workForSource(source), isNotEmpty);
    // The typed Turn identifies the real source. Tool lookup still opens and
    // verifies its original ordinary work segment, independently of completion.
    return original;
  }

  Future<TimelineDisplayUnit> turnReceipt(
    StudioTurnView turn,
    ChatTerminalOutcome outcome,
  ) async {
    final source = ForegroundTurnChatSource(turnId: turn.turnId);
    expect(graph.client.selection.state.selectedThreadId, turn.threadId);
    final receipt = observed.singleBlocks.singleWhere(
      (item) =>
          item.atom!.source == source &&
          item.atom!.kind == ChatAtomKind.turnReceipt,
    );
    expect((receipt.atom!.lifecycle as TerminalChatAtom).outcome, outcome);
    final reason =
        'Canonical wait Turn receipt must restore in its real Main row: '
        '${receipt.id}';
    await observed.revealSingle(receipt);
    late ChatItemPresentation rendered;
    await until(() {
      final row = observed.itemRow(receipt.id);
      if (row.evaluate().length != 1) return false;
      final value = tester.widget<ChatItemView>(row).item;
      if (value.compatibility != ChatItemCompatibility.current) return false;
      rendered = value;
      return true;
    }, 'canonical cancelled Turn receipt renderer');
    expect(rendered.atom?.id, receipt.atom!.id);
    expect(rendered.atom?.source, source);
    expect(rendered.atom?.completionItemId, receipt.atom!.completionItemId);
    expect(rendered.atom?.completionSeq, receipt.atom!.completionSeq);
    expect(
      rendered.compatibility,
      ChatItemCompatibility.current,
      reason: reason,
    );
    expect(rendered.type, 'turn');
    expect((rendered.data['outcome'] as Map)['kind'], outcome.name);
    return receipt;
  }

  Future<ChatItemPresentation> tool(
    StudioTurnView turn,
    String prefix, {
    String status = 'succeeded',
  }) async {
    final source = ForegroundTurnChatSource(turnId: turn.turnId);
    expect(graph.client.selection.state.selectedThreadId, turn.threadId);
    final groups = await observed.workForSource(source);
    expect(groups, isNotEmpty);
    await observed.openSourceWork(source);
    final matches = observed.mountedMembers
        .where(
          (atom) =>
              atom.source == source &&
              atom.tool?.callId.startsWith(prefix) == true,
        )
        .toList();
    expect(
      matches,
      hasLength(1),
      reason: 'one original tool atom: ${turn.threadId}/${turn.turnId}/$prefix',
    );
    final atom = matches.single;
    expect(atom.kind, ChatAtomKind.toolCall);
    expect(atom.source, source);
    expect(atom.lifecycle, isA<TerminalChatAtom>());
    expect(atom.completionItemId, isNotNull);
    expect(atom.completionSeq, isNotNull);
    // Select by reliable metadata; business assertions consume only the actual
    // renderer after its qualified canonical read, not the Deferred head.
    final reason =
        'Canonical wait tool must restore in its original member row =${atom.id}, '
        'completion=${atom.completionItemId}/${atom.completionSeq}, '
        'call=${atom.tool!.callId}.';
    final reference = observed.unitForMember(atom.id).memberReference!;
    final display = await observed.revealMember(atom, reference: reference);
    expect(display.expanded, isTrue);
    expect(
      display.atoms.where(
        (member) =>
            member.id == atom.id &&
            member.source == source &&
            member.tool?.callId == atom.tool!.callId,
      ),
      hasLength(1),
    );
    late ChatItemPresentation rendered;
    await until(() {
      final row = observed.memberRow(atom.id);
      if (row.evaluate().length != 1) return false;
      final value = tester.widget<ChatItemView>(row).item;
      if (value.compatibility != ChatItemCompatibility.current) return false;
      rendered = value;
      return true;
    }, 'canonical wait tool renderer ${atom.id}');
    expect(
      rendered.compatibility,
      ChatItemCompatibility.current,
      reason: reason,
    );
    expect(rendered.type, 'tool', reason: reason);
    expect(rendered.atom!.completionItemId, atom.completionItemId);
    expect(rendered.atom!.completionSeq, atom.completionSeq);
    expect(rendered.toolCard, isA<DecodedToolCard>(), reason: reason);
    final card = (rendered.toolCard as DecodedToolCard).value;
    expect(card.toolCallId, atom.tool!.callId, reason: reason);
    expect(card.name, atom.tool!.name, reason: reason);
    expect(card.statusString, status, reason: reason);
    return rendered;
  }

  Future<void> closeTurn(StudioTurnView turn) async {
    await observed.closeSourceWork(
      ForegroundTurnChatSource(turnId: turn.turnId),
    );
    expect(
      (await graph.client.conversations.retryCleanup(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      )).complete,
      isTrue,
    );
  }

  Future<void> currentWaiting(String prefix) async {
    await until(() {
      final threadId = graph.client.selection.state.selectedThreadId;
      if (threadId == null || threadId != _submittedThreadId) return false;
      final turn = graph.client.conversations
          .session(threadId)
          .state
          .activeTurn;
      if (turn == null ||
          turn.threadId != threadId ||
          turn.turnId == _priorTurnId ||
          !turn.state.isBusy) {
        return false;
      }
      _submittedTurnId ??= turn.turnId;
      return turn.turnId == _submittedTurnId && observed.liveWork.isNotEmpty;
    }, 'live work item with explicit member reference');
    final source = ForegroundTurnChatSource(turnId: _submittedTurnId!);
    await observed.openSourceWork(source);
    await until(
      () =>
          observed.liveAtoms
              .where(
                (atom) =>
                    atom.source == source &&
                    atom.tool?.callId.startsWith(prefix) == true,
              )
              .length ==
          1,
      'exact live wait atom',
    );
    final atom = observed.liveAtoms.singleWhere(
      (atom) =>
          atom.source == source && atom.tool?.callId.startsWith(prefix) == true,
    );
    expect(atom.lifecycle, isA<ActiveChatAtom>());
    expect(atom.wait?.state, ThreadWaitStateView.waiting);
    final panel = find.byWidgetPredicate(
      (widget) =>
          widget is TimelineWaitPanel &&
          widget.identity == atom.id &&
          widget.presentation.state == ThreadWaitStateView.waiting,
    );
    await until(
      () => panel.evaluate().length == 1,
      'typed production Waiting panel',
    );
    expect(
      observed.liveAtoms
          .singleWhere((member) => member.id == atom.id)
          .lifecycle,
      isA<ActiveChatAtom>(),
    );
    expect(tester.getSize(panel).isEmpty, isFalse);
    await Scrollable.ensureVisible(tester.element(panel), alignment: 0.5);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await capture(
      'wait-events-$name-waiting.png',
      '[[wait_cancel]]; exact live wait member / before stop',
      'Real active wait member and its production Waiting panel; not a permission dock.',
      atom,
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
    await Scrollable.ensureVisible(tester.element(details), alignment: 0.5);
    await tester.pump();
    expect(tester.takeException(), isNull);
  }
}
