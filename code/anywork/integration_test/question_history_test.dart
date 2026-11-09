import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/connectors/composer_dock_connector.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_view_model.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_dock_view.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/interactions/views/user_input_view.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/interaction_details_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/thread_session_store.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/presentation_capture.dart';
import 'support/fixture_gate.dart';
import 'support/timeline_observation.dart';

const _prompt =
    'Local GUI question history fixture: confirm the release note wording';
const _styleAnswer = '轻量回执';
const _notesAnswer = '第一行：发布说明保留两句结论与一条风险提示。\n第二行：这一段用来核对自由文本的换行与复制。';
const _secretAnswer = 'sk-question-history-fixture';
const _questionCallId = 'question-history-call';
const _finalAnswer = '收到：按轻量回执整理发布说明，风险提示单独成句。';
const _preservedDraft = '（回答完问题后继续沿用这段暂存草稿）\n保留换行与未发送状态。';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final project = Platform.environment['ANYWORK_QUESTION_HISTORY_PROJECT'];
  final output = Platform.environment['ANYWORK_QUESTION_HISTORY_OUTPUT'];
  final provider = Platform.environment['ANYWORK_QUESTION_HISTORY_PROVIDER'];
  if (project == null || output == null || provider == null) {
    throw StateError(
      'Supply ANYWORK_QUESTION_HISTORY_PROJECT and '
      'ANYWORK_QUESTION_HISTORY_OUTPUT and ANYWORK_QUESTION_HISTORY_PROVIDER',
    );
  }
  final reportFile = File('$output/question-history.json');
  late AppGraph graph;
  late ProviderContainer container;
  var assertionsPassed = false;
  final report = <String, Object?>{
    'scenario': 'question-history',
    'runner': 'flutter.integration_test',
    'pass': false,
    'captureCoverageGaps': {
      'planPendingDock': 'This strict story only calls request_user_input.',
      'permissionApproval': 'This story does not request permission approval.',
    },
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
      await reportFile.parent.create(recursive: true);
      await reportFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }
  });

  testWidgets('real question interaction becomes a redacted history receipt', (
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

    report['nativeWindow'] = await configurePresentationWindow(tester);
    final captures = <Map<String, Object?>>[];
    report['presentationCaptures'] = captures;
    Future<void> capture(
      String fileName,
      String stage,
      String coverage, {
      String? receiptId,
      String? receiptBlockId,
    }) async {
      final threadId = graph.client.selection.state.selectedThreadId!;
      final state = graph.client.conversations.session(threadId).state;
      final evidence = <String, Object?>{
        'fileName': fileName,
        'fixtureStage': stage,
        'coverage': coverage,
        'threadId': threadId,
        'turnId': state.lastTurn?.turnId,
        'interactionIds': state.interactions.map((value) => value.id).toList(),
        'receiptAtomId': ?receiptId,
        'receiptBlockId': ?receiptBlockId,
        'mainBlockIds': graph.timeline
            .lease(threadId)!
            .controller
            .messages
            .map((message) => message.id)
            .toList(),
        'captureRequested':
            Platform
                .environment['ANYWORK_PRESENTATION_SCREENSHOTS']
                ?.isNotEmpty ??
            false,
        'captureCompleted': false,
      };
      captures.add(evidence);
      await capturePresentation(tester, fileName);
      expect(tester.takeException(), isNull);
      evidence['captureCompleted'] = evidence['captureRequested'];
    }

    final priorThreadId = graph.client.selection.state.selectedThreadId;
    final priorTurnId = priorThreadId == null
        ? null
        : graph.client.conversations
              .session(priorThreadId)
              .state
              .lastTurn
              ?.turnId;
    await _submitPrompt(tester, _prompt);
    await fixtureGate(tester, Uri.parse(provider), 'questions-pending');
    String? questionThreadId;
    String? questionTurnId;
    await _until(tester, () {
      final threadId = graph.client.selection.state.selectedThreadId;
      if (threadId == null) return false;
      final turn = graph.client.conversations.session(threadId).state.lastTurn;
      if (turn == null ||
          turn.threadId != threadId ||
          (threadId == priorThreadId && turn.turnId == priorTurnId)) {
        return false;
      }
      questionThreadId = threadId;
      questionTurnId = turn.turnId;
      return true;
    }, 'accepted first input selects its real Thread and Turn');
    await tester.pump();
    final draftInput = find.byKey(const ValueKey('composer-input'));
    await _until(
      tester,
      () => draftInput.evaluate().isNotEmpty,
      'composer before questions',
    );
    await tester.enterText(draftInput, _preservedDraft);
    await tester.pump();
    expect(
      tester.widget<TextField>(draftInput).controller!.text,
      _preservedDraft,
    );
    final draftThread = graph.client.selection.state.selectedThreadId!;
    expect(draftThread, questionThreadId);
    expect(
      graph.client.drafts.composer(draftThread).state.draft,
      _preservedDraft,
    );
    await fixtureGate(
      tester,
      Uri.parse(provider),
      'questions-pending',
      release: true,
    );
    StudioTurnView? questionTurn;
    try {
      await _until(
        tester,
        () {
          if (graph.client.selection.state.selectedThreadId != draftThread) {
            return false;
          }
          final turn = graph.client.conversations
              .session(draftThread)
              .state
              .lastTurn;
          if (turn?.threadId != draftThread ||
              turn?.turnId != questionTurnId ||
              turn?.state is! CompletedStudioTurnState) {
            return false;
          }
          questionTurn = turn;
          return find
              .byKey(StudioDriverKeys.userInputSubmit)
              .evaluate()
              .isNotEmpty;
        },
        'real request_user_input controls',
        timeout: const Duration(minutes: 2),
      );
    } catch (error, stack) {
      final routeState = router.routerDelegate.state;
      await _reportMissingQuestionControls(
        tester: tester,
        graph: graph,
        container: container,
        routeTargetThreadId: routeState.name == BotConversationRoute.name
            ? routeState.pathParameters['threadId']
            : graph.client.selection.state.needsOpen
            ? null
            : graph.client.selection.state.selectedThreadId,
        originalError: error,
        originalStack: stack,
      );
      Error.throwWithStackTrace(error, stack);
    }
    expect(find.text('展示风格'), findsOneWidget);
    expect(
      graph.client.drafts.composer(draftThread).state.draft,
      _preservedDraft,
    );
    expect(
      find.byKey(const ValueKey('composer-input')),
      findsNothing,
      reason:
          'Questions dock temporarily replaces, rather than clears, the draft',
    );
    await capture(
      'question-pending-dock.png',
      'questions-pending released; request_user_input awaiting answers',
      'Real ordinary question dock replaces, but preserves, the unsent draft.',
    );
    report['stateInteractionReference'] = await _verifyStateInteractionDetails(
      tester,
      graph,
      draftThread,
      report,
    );
    expect(find.text('这次时间线里的问答回执，你更想要哪种展示？'), findsOneWidget);
    await _tap(tester, find.byKey(StudioDriverKeys.userInputFirstOption));
    await _tap(tester, find.byKey(StudioDriverKeys.userInputSubmit));

    final notes = find.byKey(StudioDriverKeys.userInputText('notes'));
    await _until(tester, () => notes.evaluate().isNotEmpty, 'notes question');
    expect(find.text('交付说明'), findsOneWidget);
    await tester.enterText(notes, _notesAnswer);
    await tester.pump();
    await _tap(tester, find.byKey(StudioDriverKeys.userInputSubmit));

    final secret = find.byKey(StudioDriverKeys.userInputText('token'));
    await _until(tester, () => secret.evaluate().isNotEmpty, 'secret question');
    expect(find.text('访问令牌'), findsOneWidget);
    final secretField = tester.widget<TextField>(secret);
    expect(secretField.obscureText, isTrue);
    expect(secretField.maxLines, 1);
    await tester.enterText(secret, _secretAnswer);
    await tester.pump();
    expect(tester.widget<TextField>(secret).controller!.text, _secretAnswer);
    await _tap(tester, find.byKey(StudioDriverKeys.userInputSubmit));

    await _until(
      tester,
      () => find.text(_finalAnswer).evaluate().isNotEmpty,
      'fixture continuation answer',
      timeout: const Duration(minutes: 3),
    );
    await _until(
      tester,
      () =>
          draftInput.evaluate().isNotEmpty &&
          tester.widget<TextField>(draftInput).controller!.text ==
              _preservedDraft,
      'original unsent draft restored after answering',
    );
    expect(
      graph.client.drafts.composer(draftThread).state.draft,
      _preservedDraft,
    );
    await capture(
      'question-draft-restored.png',
      'InteractionAnswers continuation completed',
      'Real continuation answer and restored original unsent draft.',
    );
    final receipt = await _questionReceipt(tester, graph, questionTurn!);
    final receiptRoot = find.byKey(
      StudioDriverKeys.timelineUserInput(receipt.id),
    );
    Finder scoped(Finder matching) =>
        find.descendant(of: receiptRoot, matching: matching);
    expect(receiptRoot, findsOneWidget);
    expect(scoped(find.text('展示风格')), findsNothing);
    expect(scoped(find.text('交付说明')), findsNothing);
    expect(scoped(find.textContaining(_notesAnswer)), findsNothing);
    expect(scoped(find.textContaining(_secretAnswer)), findsNothing);
    expect(scoped(find.text('敏感内容已隐藏')), findsNothing);
    await Scrollable.ensureVisible(tester.element(receiptRoot), alignment: 0.5);
    // ExpansionTile's official default is 200ms; only settle this terminal receipt.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    _expectReceiptTextVisible(tester, receiptRoot, receiptRoot);
    await capture(
      'question-receipt-collapsed.png',
      'completed question receipt; collapsed',
      'Real receipt is laid out without public answer bodies or private content.',
      receiptId: receipt.atom!.id,
      receiptBlockId: receipt.id,
    );
    await _tap(tester, receiptRoot);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await _until(
      tester,
      () => scoped(find.textContaining(_styleAnswer)).evaluate().isNotEmpty,
      'expanded public question receipt',
    );
    expect(scoped(find.text('展示风格')), findsOneWidget);
    expect(scoped(find.textContaining(_styleAnswer)), findsWidgets);
    expect(scoped(find.text('交付说明')), findsOneWidget);
    expect(scoped(find.textContaining(_notesAnswer)), findsWidgets);
    expect(scoped(find.textContaining(_secretAnswer)), findsNothing);
    expect(scoped(find.text('敏感内容已隐藏')), findsOneWidget);
    Finder answerText(String value) => scoped(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'plain-text-${receipt.id}:tool.user-input.answer.',
            ) &&
            (widget.data?.contains(value) ?? false),
      ),
    );
    for (final witness in [
      (answerText(_styleAnswer), 'question-receipt-expanded-style.png'),
      (answerText(_notesAnswer), 'question-receipt-expanded-notes.png'),
      (scoped(find.text('敏感内容已隐藏')), 'question-receipt-expanded.png'),
    ]) {
      expect(witness.$1, findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(witness.$1),
        alignment: 0.5,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      _expectReceiptTextVisible(tester, receiptRoot, witness.$1);
      await capture(
        witness.$2,
        'completed question receipt; expanded',
        'Real receipt public answer/redaction witness; private answer is absent.',
        receiptId: receipt.atom!.id,
        receiptBlockId: receipt.id,
      );
    }
    expect(find.byType(ChatItemView), findsWidgets);

    report.addAll({
      'interactionLaidOut': true,
      'draftPreservedAndRestored': true,
      'secretInputObscured': true,
      'continuationVisible': true,
      'receiptItemId': receipt.id,
      'receiptExpanded': true,
      'publicAnswersVisible': true,
      'secretAbsentFromPublicHistory': true,
    });
    assertionsPassed = true;
  }, timeout: const Timeout(Duration(minutes: 8)));
}

void _expectReceiptTextVisible(
  WidgetTester tester,
  Finder receipt,
  Finder witness,
) {
  final render = tester.renderObject<RenderBox>(witness);
  expect(render.attached && render.hasSize && !render.size.isEmpty, isTrue);
  final rect = tester.getRect(witness);
  final receiptRect = tester.getRect(receipt).inflate(1);
  expect(receiptRect.contains(rect.topLeft), isTrue);
  expect(receiptRect.contains(rect.bottomRight), isTrue);
  RenderObject? ancestor = render.parent;
  while (ancestor != null) {
    if ((ancestor is RenderClipRect || ancestor is RenderAbstractViewport) &&
        ancestor is RenderBox) {
      final viewport = (ancestor.localToGlobal(Offset.zero) & ancestor.size)
          .inflate(1);
      expect(viewport.contains(rect.topLeft), isTrue);
      expect(viewport.contains(rect.bottomRight), isTrue);
    }
    ancestor = ancestor.parent;
  }
}

Future<Map<String, Object?>> _verifyStateInteractionDetails(
  WidgetTester tester,
  AppGraph graph,
  String threadId,
  Map<String, Object?> report,
) async {
  final layout = <Map<String, Object?>>[];
  report['interactionDetailLayout'] = layout;
  Map<String, Object?> measureLayout(Finder target) {
    final sample = <String, Object?>{};
    List<double> rect(Rect value) => [
      value.left,
      value.top,
      value.width,
      value.height,
    ];
    try {
      final matches = target.evaluate().toList();
      sample['matches'] = matches.length;
      if (matches.length != 1) return sample;
      final element = matches.single;
      final render = element.findRenderObject();
      if (render is! RenderBox || !render.attached || !render.hasSize) {
        return sample;
      }
      final bounds = render.localToGlobal(Offset.zero) & render.size;
      final surface =
          Offset.zero &
          (tester.view.physicalSize / tester.view.devicePixelRatio);
      var visible = bounds.intersect(surface);
      final scrolls = <Map<String, Object?>>[];
      element.visitAncestorElements((ancestor) {
        if (ancestor is StatefulElement &&
            ancestor.state is ScrollableState &&
            scrolls.length < 3) {
          final scroll = ancestor.state as ScrollableState;
          final position = scroll.position;
          final viewport = ancestor.findRenderObject();
          final view =
              viewport is RenderBox && viewport.attached && viewport.hasSize
              ? viewport.localToGlobal(Offset.zero) & viewport.size
              : null;
          if (view != null) visible = visible.intersect(view);
          scrolls.add({
            'viewportRect': view == null ? null : rect(view),
            'pixels': position.pixels,
            'minScrollExtent': position.minScrollExtent,
            'maxScrollExtent': position.maxScrollExtent,
            'viewportDimension': position.viewportDimension,
          });
        }
        return true;
      });
      sample.addAll({
        'targetRect': rect(bounds),
        'windowRect': rect(surface),
        'visibleRect': visible.isEmpty ? null : rect(visible),
        'fullyWithinScrollViewports': visible == bounds,
        'hitTestableCount': target.hitTestable().evaluate().length,
        'scrolls': scrolls,
      });
    } catch (error) {
      sample['diagnosticErrorType'] = error.runtimeType.toString();
    }
    return sample;
  }

  void recordLayout(String stage, Finder target) {
    if (layout.length < 24) {
      layout.add({'stage': stage, ...measureLayout(target)});
    }
  }

  final geometryClock = Stopwatch()..start();
  Future<void> revealReadable(Finder target, String stage) async {
    String? previousGeometry;
    var stableFrames = 0;
    while (true) {
      final remaining = const Duration(seconds: 60) - geometryClock.elapsed;
      if (remaining <= Duration.zero) {
        recordLayout('$stage-timeout', target);
        fail('Timed out locating stable readable interaction detail: $stage');
      }
      expect(target, findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(target),
        alignment: 0.5,
      ).timeout(remaining);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      final sample = measureLayout(target);
      final geometry = jsonEncode([
        sample['targetRect'],
        sample['visibleRect'],
        sample['scrolls'],
      ]);
      stableFrames = geometry == previousGeometry ? stableFrames + 1 : 0;
      previousGeometry = geometry;
      if (stableFrames < 3) continue;
      layout.add({'stage': stage, 'stableFrames': stableFrames, ...sample});
      expect(sample['diagnosticErrorType'], isNull);
      expect(sample['scrolls'], isNotEmpty);
      expect(sample['visibleRect'], isNotNull);
      expect(
        sample['fullyWithinScrollViewports'],
        isTrue,
        reason:
            'The stable $stage must fit wholly inside the actual activity '
            'scroll viewport, not merely overlap the window: ${jsonEncode(sample)}',
      );
      return;
    }
  }

  final session = graph.client.conversations.session(threadId);
  final pending = session.state.interactions.singleWhere(
    (interaction) => interaction.payload is UserInputInteractionPayload,
  );
  final payload = pending.payload as UserInputInteractionPayload;
  final publicQuestions = payload.questions
      .where((question) => !question.isSecret)
      .toList();
  final secretQuestions = payload.questions
      .where((question) => question.isSecret)
      .toList();
  expect(publicQuestions, isNotEmpty);
  expect(secretQuestions, isNotEmpty);
  final publicText = {
    for (final question in publicQuestions) ...[
      question.header,
      question.question,
      for (final option in question.options) ...[
        option.label,
        option.description,
      ],
    ],
  }..remove('');
  final privateText = {
    _secretAnswer,
    for (final question in secretQuestions) ...[
      question.header,
      question.question,
      for (final option in question.options) ...[
        option.label,
        option.description,
      ],
    ],
  }..remove('');
  final reference = session.state.businessRefs?.interactions;
  expect(
    reference,
    isNotNull,
    reason: 'The real State must carry the readable interaction head',
  );
  expect(reference!.collection, 'interactions');
  expect(reference.databaseId, isNotEmpty);
  final connector = find.byWidgetPredicate(
    (widget) =>
        widget is InteractionDetailsConnector &&
        identical(widget.content, session.content) &&
        widget.reference == reference,
  );
  await _until(
    tester,
    () => connector.evaluate().length == 1,
    'State reference wired to the production interaction details reader',
  );
  final submit = find.byKey(StudioDriverKeys.userInputSubmit);
  final originalSubmit = tester.element(submit);
  expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  final stateRevision = session.state.revision;
  final actionView = find.byKey(
    ValueKey('user-input-view-$threadId-${pending.id}'),
  );
  expect(tester.widget<UserInputView>(actionView).enabled, isTrue);
  final resourceEvidence = <String, Object?>{
    'stateRevisionBefore': stateRevision,
    'interactionId': pending.id,
    'interactionRevisionBefore': pending.revision,
    'referenceRevisionBefore': reference.revision,
  };
  report['interactionReadResourceEvidence'] = resourceEvidence;
  void expectResourceUnchanged(String stage) {
    final currentReference = session.state.businessRefs?.interactions;
    final currentPending = session.state.interactions.singleWhere(
      (interaction) => interaction.id == pending.id,
    );
    resourceEvidence[stage] = {
      'stateRevision': session.state.revision,
      'referenceRevision': currentReference?.revision,
      'interactionId': currentPending.id,
      'interactionRevision': currentPending.revision,
    };
    expect(currentReference, reference);
    expect(currentReference!.revision, reference.revision);
    expect(currentPending, same(pending));
    expect(currentPending.id, pending.id);
    expect(currentPending.revision, pending.revision);
    expect(currentPending.payload, same(payload));
    expect(currentPending.threadId, pending.threadId);
    expect(currentPending.turnId, pending.turnId);
    expect(tester.widget<UserInputView>(actionView).enabled, isTrue);
    expect(tester.element(submit), same(originalSubmit));
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  }

  expect(
    find.descendant(of: connector, matching: submit),
    findsNothing,
    reason: 'Read-only details do not reconstruct actionable questions',
  );
  final l10n = AppLocalizations.of(tester.element(connector));
  final title = find.descendant(
    of: connector,
    matching: find.text(l10n.interactionDetailsTitle),
  );
  recordLayout('header-before-open', title);
  await revealReadable(title, 'header-ready-to-open');
  try {
    await _tap(tester, title);
  } finally {
    recordLayout('header-after-open-attempt', title);
  }
  Finder detailText(String text) => find.descendant(
    of: connector,
    matching: find.textContaining(text, findRichText: true),
  );
  void expectPrivateDetailsHidden() {
    for (final text in privateText) {
      expect(
        detailText(text),
        findsNothing,
        reason: 'Read-only details must omit secret prompts and values',
      );
      expect(
        find.descendant(
          of: connector,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is EditableText && widget.controller.text.contains(text),
          ),
        ),
        findsNothing,
      );
    }
  }

  await _until(tester, () {
    expect(
      find.descendant(
        of: connector,
        matching: find.textContaining(l10n.interactionDetailsInvalidFormat),
      ),
      findsNothing,
      reason: 'Native collection payload must decode in the real UI',
    );
    expectPrivateDetailsHidden();
    return publicText.every((text) => detailText(text).evaluate().isNotEmpty);
  }, 'public interaction content read from the real State reference');
  var publicTextIndex = 0;
  for (final text in publicText) {
    final visible = detailText(text).first;
    await revealReadable(visible, 'public-text-${publicTextIndex++}');
    expect(visible, findsOneWidget);
    final bounds = tester.getRect(visible);
    expect(bounds.isEmpty, isFalse);
  }
  expectPrivateDetailsHidden();
  expectResourceUnchanged('afterRead');
  await revealReadable(title, 'header-ready-to-collapse');
  await _tap(tester, title);
  await tester.pump(const Duration(milliseconds: 300));
  recordLayout('header-after-collapse', title);
  for (final text in publicText) {
    expect(detailText(text), findsNothing);
  }
  expectPrivateDetailsHidden();
  expect(find.descendant(of: connector, matching: submit), findsNothing);
  expect(tester.element(submit), same(originalSubmit));
  expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  expectResourceUnchanged('afterCollapse');
  expect(
    (await graph.client.conversations.retryCleanup(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    )).complete,
    isTrue,
  );
  return {
    'source': 'native-State.businessRefs.interactions',
    'databaseId': reference.databaseId,
    'collection': reference.collection,
    'revision': reference.revision,
    'interactionId': pending.id,
    'bodyReadInProductionUi': true,
    'publicTextTargetsFullyVisible': publicTextIndex,
    'publicQuestionsVerified': publicQuestions.length,
    'secretPromptsAndValuesHidden': true,
    'originalActionableControlRetained': true,
    'detailScopeJoinedAfterCollapse': true,
  };
}

Future<void> _reportMissingQuestionControls({
  required WidgetTester tester,
  required AppGraph graph,
  required ProviderContainer container,
  required String? routeTargetThreadId,
  required Object originalError,
  required StackTrace originalStack,
}) async {
  final selection = graph.client.selection.state;
  final selectedThreadId = selection.selectedThreadId;
  final visibleThreadId = graph.client.conversations.visibleThreadId.value;
  final diagnosticThreadId =
      routeTargetThreadId ?? visibleThreadId ?? selectedThreadId;
  final session = diagnosticThreadId == null
      ? null
      : container.read(threadSessionStoreProvider(diagnosticThreadId));
  final composer = diagnosticThreadId == null
      ? null
      : container.read(composerDockViewModelProvider(diagnosticThreadId));
  final composerValue = switch (composer) {
    AsyncData(:final value) => value,
    _ => null,
  };
  final latestTurn = session?.workspace?.latestTurn;
  int questionsIn(InteractionPayload payload) => switch (payload) {
    UserInputInteractionPayload(:final questions) => questions.length,
    _ => 0,
  };

  final summary = <String, Object?>{
    'event': 'question-controls-missing',
    'selectedThreadId': selectedThreadId,
    'visibleThreadId': visibleThreadId,
    'targetThreadId': routeTargetThreadId,
    'diagnosticThreadId': diagnosticThreadId,
    'session': session == null
        ? null
        : <String, Object?>{
            'threadId': session.threadId,
            'sync': <String, Object?>{
              'phase': session.sync.phase.name,
              'errorMessage': session.sync.errorMessage,
              'retryExhausted': session.sync.retryExhausted,
            },
            'hasSnapshot': session.hasSnapshot,
            'epoch': session.streamEpoch,
            'revision': session.revision,
            'latestTurn': latestTurn == null
                ? null
                : <String, Object?>{
                    'turnId': latestTurn.turnId,
                    'threadId': latestTurn.threadId,
                    'revision': latestTurn.revision,
                    'status': latestTurn.state.status.name,
                    'activity': latestTurn.state.activity?.name,
                  },
            'interactions': [
              for (final interaction in session.interactions)
                <String, Object?>{
                  'id': interaction.id,
                  'kind': interaction.kind.name,
                  'revision': interaction.revision,
                  'payloadType': interaction.payload.runtimeType.toString(),
                  'questions': questionsIn(interaction.payload),
                },
            ],
          },
    'composerDockViewModel': composer == null
        ? null
        : <String, Object?>{
            'loading': composer.isLoading,
            'hasError': composer.hasError,
            'error': composer.error?.toString(),
            'threadId': composerValue?.row?.threadId,
            'executionClosed': composerValue?.executionClosed,
            'activeInteraction': composerValue?.activeInteraction == null
                ? null
                : <String, Object?>{
                    'id': composerValue!.activeInteraction!.id,
                    'kind': composerValue.activeInteraction!.kind.name,
                    'revision': composerValue.activeInteraction!.revision,
                    'payloadType': composerValue
                        .activeInteraction!
                        .payload
                        .runtimeType
                        .toString(),
                    'questions': questionsIn(
                      composerValue.activeInteraction!.payload,
                    ),
                  },
          },
    'widgets': <String, Object?>{
      'UserInputView': find.byType(UserInputView).evaluate().length,
      'ComposerDockConnector': find
          .byType(ComposerDockConnector)
          .evaluate()
          .length,
      'ComposerDockView': find.byType(ComposerDockView).evaluate().length,
    },
  };
  debugPrintSynchronously(
    'Question controls diagnostic:\n'
    '${const JsonEncoder.withIndent('  ').convert(summary)}',
  );
  debugDumpApp();
  debugPrintSynchronously(
    'Original question controls failure: $originalError\n$originalStack',
  );
  try {
    await capturePresentation(tester, 'question-controls-missing.png');
  } catch (captureError, captureStack) {
    debugPrintSynchronously(
      'Question controls diagnostic capture failure: '
      '$captureError\n$captureStack',
    );
    Error.throwWithStackTrace(
      StateError(
        'Question controls failed ($originalError), and diagnostic capture '
        'failed ($captureError)',
      ),
      StackTrace.fromString(
        'Original question controls failure:\n$originalStack\n'
        'Diagnostic capture failure:\n$captureStack',
      ),
    );
  }
}

Future<ChatItemPresentation> _questionReceipt(
  WidgetTester tester,
  AppGraph graph,
  StudioTurnView questionTurn,
) async {
  final threadId = questionTurn.threadId;
  expect(questionTurn.state, isA<CompletedStudioTurnState>());
  final observed = TimelineObservation(tester, () {
    expect(graph.client.selection.state.selectedThreadId, threadId);
    return graph.timeline.lease(threadId)!;
  });
  // Answer submission creates a continuation Turn. Its real terminal state
  // must not be confused with the earlier Turn that requested the interaction.
  await _until(tester, () {
    if (graph.client.selection.state.selectedThreadId != threadId) return false;
    final turn = graph.client.conversations.session(threadId).state.lastTurn;
    return turn != null &&
        turn.threadId == threadId &&
        turn.turnId != questionTurn.turnId &&
        turn.state is CompletedStudioTurnState;
  }, 'completed real question continuation Turn');
  final source = ForegroundTurnChatSource(turnId: questionTurn.turnId);
  TimelineDisplayUnit? target;
  await _until(tester, () {
    final matches = observed.main
        .where(
          (unit) =>
              unit.body is SingleDisplayBlock &&
              unit.atom!.source == source &&
              unit.atom!.kind == ChatAtomKind.interaction &&
              (unit.atom!.lifecycle as TerminalChatAtom).outcome ==
                  ChatTerminalOutcome.completed,
        )
        .toList();
    expect(matches.length, lessThanOrEqualTo(1));
    target = matches.singleOrNull;
    return target != null;
  }, 'completed question interaction in independent Main status');
  final status = target!;
  final atom = status.atom!;
  expect(
    (atom.lifecycle as TerminalChatAtom).outcome,
    ChatTerminalOutcome.completed,
  );
  expect(status.body, isA<SingleDisplayBlock>());
  final reason =
      'Canonical question receipt must restore through its original renderer: '
      '${status.id}/${atom.id}';
  // Reveal the independent status through the production Main owner, then
  // inspect the receipt actually supplied to its real UI, not a fabricated atom.
  await observed.reveal(observed.itemRow(status.id), status.id);
  late ChatItemPresentation receipt;
  await _until(tester, () {
    final row = observed.itemRow(status.id);
    if (row.evaluate().length != 1) return false;
    final value = tester.widget<ChatItemView>(row).item;
    if (value.compatibility != ChatItemCompatibility.current) return false;
    receipt = value;
    return true;
  }, 'canonical question receipt renderer');
  expect(receipt.id, status.id);
  expect(receipt.atom, same(atom));
  expect(observed.unit(receipt.id).atom!.source, source);
  expect(receipt.compatibility, ChatItemCompatibility.current, reason: reason);
  expect(receipt.type, 'tool');
  final invocation = receipt.data['invocation'] as Map<String, Object?>;
  expect(invocation['toolCallId'], _questionCallId);
  expect(invocation['name'], 'request_user_input');
  final input = receipt.data['userInput'] as Map<String, Object?>;
  final questions = (input['questions'] as List).cast<Map<String, Object?>>();
  expect(questions.map((question) => question['id']), [
    'style',
    'notes',
    'token',
  ]);
  final state = input['state'] as Map<String, Object?>;
  expect(state['kind'], 'resolved');
  final answers = (state['answers'] as List).cast<Map<String, Object?>>();
  expect(answers.map((answer) => answer['questionId']), [
    'style',
    'notes',
    'token',
  ]);
  expect(answers.last['redacted'], isTrue);
  expect(answers.last['answerCount'], 0);
  expect(
    receipt.bodies.where(
      (body) => body.key.startsWith('tool.user-input.answer.2.'),
    ),
    isEmpty,
  );
  for (final body in receipt.bodies) {
    if (body.inline case final bytes?) {
      expect(utf8.decode(bytes), isNot(contains(_secretAnswer)));
    }
  }
  await _until(tester, () {
    return find
        .byKey(StudioDriverKeys.timelineUserInput(receipt.id))
        .evaluate()
        .isNotEmpty;
  }, 'laid out question history receipt');
  return receipt;
}

Future<void> _submitPrompt(WidgetTester tester, String prompt) async {
  final input = find.byKey(const ValueKey('composer-input'));
  await _until(tester, () => input.evaluate().isNotEmpty, 'composer');
  try {
    await tester.enterText(input, prompt);
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, prompt);
    await _tap(tester, find.byKey(const ValueKey('composer-submit')));
  } catch (_) {
    final composer = tester.widget<PromptComposerView>(
      find.byType(PromptComposerView),
    );
    debugPrintSynchronously(
      'Question submission failure: draft=${composer.composer.draft}, '
      'pending=${composer.composer.isSubmissionPending}, '
      'execution=${composer.execution?.id}/${composer.execution?.phase}, '
      'blocker=${composer.blocker}, failure=${composer.failure}',
    );
    rethrow;
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, () => finder.evaluate().isNotEmpty, finder.toString());
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await _until(
    tester,
    () => finder.hitTestable().evaluate().length == 1,
    'hittable $finder',
  );
  await tester.tap(finder);
  await tester.pump();
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
