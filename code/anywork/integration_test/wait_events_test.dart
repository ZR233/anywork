import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/timeline_observation.dart';

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
      reason: 'Use cargo xtask test-project --suite desktop --case wait_events',
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
        FlutterError.onError = testErrorHandler;
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AnyworkApp(enableDesktopHost: false),
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
    final prepared = await scene.completedTurn();
    final started = await scene.tool(
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
    expect(stoppedReceipt.atomKind, ChatAtomKind.turnReceipt);
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
  _Scene(this.tester, this.graph);
  final WidgetTester tester;
  final AppGraph graph;
  String? latestTurnId;
  String? _submittedThreadId;
  String? _priorTurnId;
  String? _submittedTurnId;

  TimelineDisplayLease get lease =>
      graph.timeline.lease(graph.client.selection.state.selectedThreadId!)!;
  late final observed = TimelineObservation(tester, () => lease);

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

  Future<StudioTurnView> waitForTurn({
    String? after,
    StudioTurnStatus outcome = StudioTurnStatus.completed,
  }) async {
    StudioTurnView? turn;
    await until(() {
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
      if (!candidate.state.isTerminal ||
          candidate.state.status != outcome ||
          graph.timeline.lease(id) == null) {
        return false;
      }
      final source = ForegroundTurnChatSource(turnId: candidate.turnId);
      // State proves completion; Main must separately accept this source in
      // the same original wait budget before the history assertions proceed.
      if (!observed.items.any((item) => item.source == source) ||
          observed.live.any((unit) => unit.item.source == source)) {
        return false;
      }
      if (outcome == StudioTurnStatus.cancelled) {
        final receipts = observed.items
            .where(
              (item) =>
                  item.source == source &&
                  item.kind == TimelineItemKind.status &&
                  item.atomKind == ChatAtomKind.turnReceipt,
            )
            .toList();
        expect(receipts.length, lessThanOrEqualTo(1));
        return receipts.singleOrNull?.outcome == ChatTerminalOutcome.cancelled;
      }
      return true;
    }, '${outcome.name} Turn');
    final original = turn!;
    latestTurnId = original.turnId;
    expect(original.state.status, outcome);
    return original;
  }

  Future<StudioTurnView> completedTurn({
    String? after,
    StudioTurnStatus outcome = StudioTurnStatus.completed,
  }) async {
    final original = await waitForTurn(after: after, outcome: outcome);
    final source = ForegroundTurnChatSource(turnId: original.turnId);
    expect(observed.workFor(source), isNotEmpty);
    // The typed Turn identifies the real source. Tool lookup still opens and
    // verifies its original ordinary work segment, independently of completion.
    return original;
  }

  Future<TimelineItem> turnReceipt(
    StudioTurnView turn,
    ChatTerminalOutcome outcome,
  ) async {
    final source = ForegroundTurnChatSource(turnId: turn.turnId);
    expect(graph.client.selection.state.selectedThreadId, turn.threadId);
    final receipt = observed.items.singleWhere(
      (item) =>
          item.source == source &&
          item.kind == TimelineItemKind.status &&
          item.atomKind == ChatAtomKind.turnReceipt,
    );
    expect(receipt.outcome, outcome);
    final payload = receipt.payload;
    final byteLength = payload is InlinePayload
        ? payload.bytes.length
        : payload is DeferredPayload
        ? payload.byteLength
        : null;
    final reason =
        'Known small wait fixture requires Inline/current business '
        'presentation within the original frame budget: id=${receipt.id}, '
        'payloadType=${payload?.runtimeType}, byteLength=$byteLength. '
        'Over-budget payloads may remain Deferred in the product.';
    expect(payload is InlinePayload, isTrue, reason: reason);
    expect(
      ChatItemPresentation.forUnit(observed.unit(receipt.id)).compatibility,
      ChatItemCompatibility.current,
      reason: reason,
    );
    await observed.revealItem(receipt);
    final rendered = tester
        .widget<ChatItemView>(observed.itemRow(receipt.id))
        .item;
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
    final groups = observed.workFor(source).toList();
    expect(groups, isNotEmpty);
    await observed.openSourceGroups(source);
    final matches = observed.mountedMembers
        .where(
          (atom) =>
              atom.source == source &&
              atom.tool?.callId.startsWith(prefix) == true,
        )
        .map(ChatItemPresentation.decode)
        .where((item) {
          final reading = item.toolCard;
          return reading is DecodedToolCard &&
              reading.value.toolCallId.startsWith(prefix) &&
              reading.value.statusString == status;
        })
        .toList();
    expect(matches, hasLength(1), reason: '$prefix / $status');
    final item = matches.single;
    final reference = observed.unitForMember(item.atom!.id).item.members!;
    final display = await observed.revealMember(
      item.atom!,
      reference: reference,
    );
    expect(display.expanded, isTrue);
    expect(
      display.atoms.where(
        (atom) =>
            atom.id == item.atom!.id &&
            atom.tool?.callId ==
                (item.toolCard as DecodedToolCard).value.toolCallId,
      ),
      hasLength(1),
    );
    return item;
  }

  Future<void> closeTurn(StudioTurnView turn) async {
    await observed.closeSource(ForegroundTurnChatSource(turnId: turn.turnId));
    await until(
      () => graph.client.budget.used(ResourceKind.chatHandle) == 1,
      'ordinary group scopes released; only original Main handle remains',
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
      return turn.turnId == _submittedTurnId &&
          observed.live.any(
            (unit) =>
                unit.item.kind == TimelineItemKind.workGroup &&
                unit.item.source ==
                    ForegroundTurnChatSource(turnId: turn.turnId),
          );
    }, 'live work item with explicit member reference');
    final source = ForegroundTurnChatSource(turnId: _submittedTurnId!);
    await observed.openSourceGroups(source);
    await until(
      () =>
          observed.mountedMembers
              .where(
                (atom) =>
                    atom.source == source &&
                    atom.tool?.callId.startsWith(prefix) == true,
              )
              .length ==
          1,
      'exact live wait atom',
    );
    final atom = observed.mountedMembers.singleWhere(
      (atom) =>
          atom.source == source && atom.tool?.callId.startsWith(prefix) == true,
    );
    final unit = observed.unitForMember(atom.id);
    expect(atom.lifecycle, isA<ActiveChatAtom>());
    expect(atom.wait?.state, ThreadWaitStateView.waiting);
    await observed.openGroup(unit.id);
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
      observed.mountedMembers
          .singleWhere((member) => member.id == atom.id)
          .lifecycle,
      isA<ActiveChatAtom>(),
    );
    expect(tester.getSize(panel).isEmpty, isFalse);
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
