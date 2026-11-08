import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_children_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/content_reference_identity.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_image_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/features/status/context_usage_readout.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/conversation_credit_observation.dart';
import 'support/fixture_gate.dart';
import 'support/presentation_capture.dart';
import 'support/timeline_concept_images.dart';
import 'support/timeline_observation.dart';

const _prompt = '把会话设计稿组件化，检查工作组与正文的交接边界。';
const _textA = '已确认共享组件与交接边界，接下来检查收尾。';
const _textB = '收尾检查完成，工作组与正文分别保留。';
const _imageDone = '三张设计截图已读取；目录不是图片，读取失败已保留。';
const _failedPrompt = '保留这段部分结果，再展示供应商失败。';
const _partial = '已经完成的部分结果必须保留，不能因后续失败而消失。';
const _overlapPrompt = 'A07：推理尚未结束时开始正文，并保留可读流。';
const _overlapText = '正文已经开始且可以读取，先前推理稍后才结束。';
const _overlapReasoning = '这段推理在正文开始后继续保持活动。';
const _overlapEarlyReasoning = '后开始的推理 B 已先完成，推理 A 仍在进行。';
const _emptyTextPrompt = 'A14：空正文开始和结束不分隔前后相邻工作。';
const _emptyTextAnswer = '空正文没有可见气泡，前后相邻工作仍属于同一段。';
const _imageCalls = ['concept-image-a', 'concept-image-b', 'concept-image-c'];
const _imageReasoningCount = 40;
const _imageMemberCount = 44;

/// Three native processes, one isolated SQLite database, one strict provider.
/// Only the journey sends requests. Reopen phases consume saved input/atom IDs,
/// never owner-local group IDs. Independent question-history and realtime suites
/// retain their own provider scripts and are not registered in this process.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final project = _environment('PROJECT');
  final output = _environment('OUTPUT');
  final provider = Uri.parse(_environment('PROVIDER'));
  final emptyThread = _environment('EMPTY_THREAD');
  final reopen = Platform.environment['ANYWORK_TIMELINE_CONCEPT_REOPEN'] == '1';
  final missing =
      Platform.environment['ANYWORK_TIMELINE_CONCEPT_MEDIA_FAULT'] == '1';
  final phase = missing
      ? 'media-missing'
      : reopen
      ? 'reopen'
      : 'journey';
  final reportName = missing
      ? 'timeline-concept-media-missing.json'
      : reopen
      ? 'timeline-concept-reopen.json'
      : 'timeline-concept.json';
  final report = <String, Object?>{
    'scenario': 'timeline-concept',
    'phase': phase,
    'runner': 'flutter.integration_test',
    'pass': false,
    'expectedRequiredProviderSteps': 9,
    'processObservation': {
      'dartIoPid': pid,
      'entryObservedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'dartExecutable': Platform.resolvedExecutable,
      'integrationTarget': 'integration_test/timeline_concept_test.dart',
      'phase': phase,
      'buildMode': 'debug',
      'platform': Platform.operatingSystem,
      'runnerPid': null,
      'nativeExitCode': null,
      'forcedReclaimObserved': null,
      'osExitEvidence': 'unknown; SDK shutdown is not an OS exit report',
    },
    'independentScenarioEntrypoints': {
      'questions': 'integration_test/question_history_test.dart',
      'receipts': 'integration_test/question_history_test.dart',
      'stopContinue': 'integration_test/realtime_presentation_test.dart',
    },
  };
  late AppGraph graph;
  late ProviderContainer container;
  var assertionsPassed = false;
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
      report['sdkShutdownRequestedAtUtc'] = DateTime.now()
          .toUtc()
          .toIso8601String();
      final shutdown = await runStudioShutdown(
        graph.client.transport,
        (_) {},
        remainingMs: 30000,
        closeClient: (deadline) => graph.close(deadline: deadline),
      );
      expect(shutdown.shutdown.isClean, isTrue);
      expect(shutdown.shutdown.issues, isEmpty);
      expect(
        shutdown.shutdown.persistence,
        isA<DrainedStudioPendingPersistence>(),
      );
      report['shutdown'] = 'completed';
      report['sdkShutdownCompletedAtUtc'] = DateTime.now()
          .toUtc()
          .toIso8601String();
      report['pass'] = assertionsPassed;
    } finally {
      container.dispose();
      final file = File('$output/$reportName');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }
  });
  testWidgets('concept production page: $phase', (tester) async {
    final previousErrorHandler = FlutterError.onError!;
    final frameworkErrors = <Map<String, Object?>>[];
    report['frameworkErrors'] = frameworkErrors;
    FlutterError.onError = (details) {
      if (frameworkErrors.length < 8) {
        frameworkErrors.add({
          'exception': details.exceptionAsString(),
          'stack': details.stack?.toString(),
        });
      }
      debugPrint(
        'NATIVE_FRAMEWORK_ERROR\n${details.exceptionAsString()}\n${details.stack}',
      );
      // Preserve the official runner's failure handling after recording its cause.
      previousErrorHandler(details);
    };
    addTearDown(() {
      FlutterError.onError = previousErrorHandler;
    });
    final router = createApplicationRouter();
    void syncRoute() {
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

    router.routerDelegate.addListener(syncRoute);
    tester.testTextInput.register();
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
        router.routerDelegate.removeListener(syncRoute);
        router.dispose();
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
    report['window'] = await configurePresentationWindow(tester);
    await graph.client.directoryCommands.openProject(project);
    graph.setConversationPageVisible(true);
    final scene = _ConceptScene(tester, graph, provider, report, phase);
    await scene.openThread(emptyThread);
    report['threadId'] = emptyThread;
    report['coldProcessSelection'] = await scene.observeSelectionFill(
      'cold-process-selection',
    );
    if (reopen) {
      final saved = jsonDecode(
        await File('$output/timeline-concept.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(saved['pass'], isTrue);
      expect(saved['shutdown'], 'completed');
      expect(saved['threadId'], emptyThread);
      await scene.reopened(saved, missing: missing);
    } else {
      await scene.journey(project);
    }
    expect(tester.takeException(), isNull);
    assertionsPassed = true;
  });
}

String _environment(String suffix) {
  final name = 'ANYWORK_TIMELINE_CONCEPT_$suffix';
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) throw StateError('Supply $name');
  return value;
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String description, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = timeout < const Duration(seconds: 60)
      ? timeout
      : const Duration(seconds: 60);
  if (deadline <= Duration.zero) {
    fail('No remaining wait budget for $description');
  }
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > deadline) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  }
}

typedef _ImageResult = ({
  ChatAtom foreground,
  TimelineDisplayUnit? finalUnit,
  ChatAtom finalAtom,
  ChatItemPresentation presentation,
});

final class _ConceptScene {
  _ConceptScene(
    this.tester,
    this.graph,
    this.provider,
    this.report,
    this.phase,
  );
  final WidgetTester tester;
  final AppGraph graph;
  final Uri provider;
  final Map<String, Object?> report;
  final String phase;
  final List<Map<String, Object?>> _checkpoints = [];
  static const _samplePump = Duration(milliseconds: 16);
  String get threadId => graph.client.selection.state.selectedThreadId!;
  TimelineDisplayLease get lease => graph.timeline.lease(threadId)!;
  late final observed = TimelineObservation(tester, () => lease);

  // Borrow existing immutable values only. None of these getters opens a query,
  // runs a body read, classifies atoms, or keeps a second presentation list.
  List<TimelineDisplayUnit> get main => observed.main.toList();
  List<ChatAtom> get live =>
      observed.activity.map((entry) => entry.atom).toList();
  Iterable<CompletedEntry> get items => observed.entries;
  Iterable<ChatAtom> membersOf(String unitId) => lease.groupDisplays
      .where((display) => display.unitId == unitId)
      .expand((display) => display.atoms);
  ChatItemPresentation presentation(CompletedEntry entry) =>
      ChatItemPresentation.decode(entry.atom);
  bool hasText(String text) =>
      find.textContaining(text, findRichText: true).evaluate().isNotEmpty;
  Finder unitFinder(String id) => find.byWidgetPredicate(
    (widget) =>
        (widget is TimelineDisplayUnitView && widget.unit.id == id) ||
        (widget is ChatItemView &&
            widget.item.type != 'displayUnit' &&
            widget.item.id == id),
  );
  Finder itemFinder(String id) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.item.id == id,
  );

  Future<void> openThread(String id) async {
    await _until(
      tester,
      () => find.byKey(StudioDriverKeys.threadRow(id)).evaluate().isNotEmpty,
      'isolated thread row',
    );
    await tap(find.byKey(StudioDriverKeys.threadRow(id)));
    await _until(
      tester,
      () =>
          graph.client.selection.state.selectedThreadId == id &&
          graph.timeline.lease(id)?.isMounted == true,
      'selected thread and mounted production timeline',
    );
  }

  Future<void> tap(Finder finder) async {
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> submit(String text) async {
    final input = find.byKey(const ValueKey('composer-input'));
    await _until(tester, () => input.evaluate().isNotEmpty, 'composer input');
    await tester.enterText(input, text);
    await tester.pump();
    expect(graph.client.drafts.composer(threadId).state.draft, text);
    await tap(find.byKey(const ValueKey('composer-submit')));
  }

  Future<void> reach(String stage, bool Function() ready) async {
    await fixtureGate(tester, provider, stage);
    try {
      await _until(tester, ready, 'production state at $stage');
    } catch (error, stack) {
      // Borrow the failing cut before teardown. No query, refresh, extra pump,
      // body text or arbitrary widget dump may alter/expose this observation.
      try {
        report['stageFailure'] = _stageFailure(stage, error, stack);
      } catch (diagnosticError) {
        report['stageFailure'] = {
          'stage': stage,
          'gateReached': true,
          'exceptionType': error.runtimeType.toString(),
          'stack': stack.toString(),
          'diagnosticErrorType': diagnosticError.runtimeType.toString(),
        };
      }
      rethrow;
    }
    await _record(stage);
  }

  Map<String, Object?> _stageFailure(
    String stage,
    Object error,
    StackTrace stack,
  ) {
    final selected = graph.client.selection.state.selectedThreadId;
    final session = selected == null
        ? null
        : graph.client.conversations.existingSession(selected);
    final state = session?.state;
    final target = selected == null ? null : graph.timeline.lease(selected);
    final snapshot = target?.content.activity.value;
    final current = target?.currentDisplay;
    final status = state?.activity;
    final execution = state?.runtime?.execution;
    const activityKey = ValueKey('conversation-activity');
    final keyOnstage = find.byKey(activityKey).evaluate().length;
    final keyAll = find
        .byKey(activityKey, skipOffstage: false)
        .evaluate()
        .length;
    final liveEmpty = snapshot?.entries.isEmpty ?? true;
    Map<String, Object?>? turn(StudioTurnView? value) => value == null
        ? null
        : {
            'threadId': value.threadId,
            'turnId': value.turnId,
            'revision': value.revision,
            'status': value.state.status.name,
            'activity': value.state.activity?.name,
          };
    final connectors = find.byType(
      ConversationCurrentConnector,
      skipOffstage: false,
    );
    final relevant = find.byWidgetPredicate(
      (widget) =>
          widget is ConversationCurrentConnector ||
          widget is ConversationActivityBar ||
          widget is ConversationActivityStatus ||
          widget is TimelineView ||
          widget.key == activityKey,
      skipOffstage: false,
    );
    final surface =
        Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
    final tree = <Map<String, Object?>>[];
    for (final element in relevant.evaluate().take(20)) {
      final render = element.findRenderObject();
      Rect? bounds;
      if (render is RenderBox && render.attached && render.hasSize) {
        bounds = render.localToGlobal(Offset.zero) & render.size;
      }
      final ancestors = <Map<String, Object?>>[];
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        ancestors.add({
          'type': widget.runtimeType.toString(),
          if (widget is Offstage) 'offstage': widget.offstage,
          if (widget is Opacity) 'opacity': widget.opacity,
          if (widget is TickerMode) 'enabled': widget.enabled,
        });
        return ancestors.length < 12;
      });
      tree.add({
        'type': element.widget.runtimeType.toString(),
        'mounted': element.mounted,
        'renderAttached': render?.attached,
        'tickerEnabled': TickerMode.valuesOf(element).enabled,
        'bounds': bounds == null
            ? null
            : [bounds.left, bounds.top, bounds.right, bounds.bottom],
        'overlapsSurface': bounds?.overlaps(surface),
        'ancestors': ancestors,
      });
    }
    return {
      'stage': stage,
      'gateReached': true,
      'observedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'exceptionType': error.runtimeType.toString(),
      'stack': stack.toString(),
      if (stage == 'thinking')
        'thinkingConditions': {
          'liveEmpty': liveEmpty,
          'activityKeyPresent': keyOnstage > 0,
          'combined': liveEmpty && keyOnstage > 0,
        },
      'selectedThreadId': selected,
      'visibleThreadId': graph.client.conversations.visibleThreadId.value,
      'state': {
        'hasSnapshot': state?.hasSnapshot,
        'revision': state?.revision,
        'epoch': state?.streamEpoch,
        'baseRevision': state?.baseRevision,
        'syncPhase': state?.sync.phase.name,
        'activeTurn': turn(state?.activeTurn),
        'lastTurn': turn(state?.lastTurn),
        'execution': execution == null
            ? null
            : {
                'id': execution.id,
                'turnId': execution.turnId,
                'phase': execution.phase.name,
              },
        'activity': status == null
            ? null
            : {
                'identity': status.identity,
                'revision': status.revision,
                'kind': status.kind.name,
                'turnId': status.turnId,
                'executionId': status.executionId,
                'attemptId': status.attemptId,
              },
      },
      'lease': {
        'present': target != null,
        'generation': target?.generation,
        'mounted': target?.isMounted,
        'retired': target?.isRetired,
        'released': target?.isReleased,
        'appliedSets': target?.appliedSets,
        'contentState': target?.content.state.value.runtimeType.toString(),
        'sameSessionContent':
            session != null && identical(session.content, target?.content),
        'sameSessionActivity':
            session != null && identical(session.activity.value, snapshot),
        'currentDisplay': current == null
            ? null
            : {
                'isCurrent': current.isCurrent,
                'expanded': current.expanded,
                'turnId': current.turnId,
                'activityId': current.activityId,
                'windowCount': current.windows.length,
              },
      },
      'activity': snapshot == null
          ? null
          : {
              'revision': snapshot.revision,
              'completedThrough': snapshot.completedThrough,
              'executionPresent': snapshot.executionPresent,
              'entryCount': snapshot.entries.length,
              'entries': [
                for (final entry in snapshot.entries.take(16))
                  {
                    'identityType': entry.identity.runtimeType.toString(),
                    'id': entry.atom.id,
                    'kind': entry.atom.kind.name,
                    'lifecycle': entry.atom.lifecycle.runtimeType.toString(),
                    'sourceType': entry.atom.source.runtimeType.toString(),
                    'turnId': entry.atom.turnId,
                    'attemptId': entry.atom.attemptId,
                    'completionSeq': entry.atom.completionSeq,
                  },
              ],
            },
      'widgets': {
        'activityKeyOnstage': keyOnstage,
        'activityKeyAll': keyAll,
        'activityBarOnstage': find
            .byType(ConversationActivityBar)
            .evaluate()
            .length,
        'activityBarAll': find
            .byType(ConversationActivityBar, skipOffstage: false)
            .evaluate()
            .length,
        'currentConnectorOnstage': find
            .byType(ConversationCurrentConnector)
            .evaluate()
            .length,
        'currentConnectorAll': connectors.evaluate().length,
        'connectors': [
          for (final widget in tester.widgetList<ConversationCurrentConnector>(
            connectors,
          ))
            {
              'sameContent': identical(widget.content, target?.content),
              'displayActive': widget.isDisplayActive(),
              'viewKind': widget.view?.kind.name,
              'stateActivityKind': widget.session.activity?.kind.name,
              'stateActiveTurnId': widget.session.activeTurn?.turnId,
            },
        ],
        'treeLimit': 20,
        'tree': tree,
      },
    };
  }

  Future<void> release(String stage) =>
      fixtureGate(tester, provider, stage, release: true);

  Future<void> _record(String stage) async {
    await tester.pump();
    expect(tester.takeException(), isNull);
    _checkpoints.add({
      'stage': stage,
      'ownerGeneration': lease.generation,
      'mainMessageCount': lease.controller.messages.length,
      'main': [
        for (final unit in main)
          {
            'id': unit.id,
            'recordId': unit.entry.recordId,
            'completionSeq': unit.entry.completionSeq,
            'presentation': unit.entry.mainPresentation.name,
            'startSeq': unit.entry.run?.startSeq,
            'ordinal': unit.entry.run?.ordinal,
            'mountedMemberIds': [
              for (final atom in membersOf(unit.id)) atom.id,
            ],
          },
      ],
      'activity': [
        for (final atom in live)
          {
            'id': atom.id,
            'kind': atom.kind.name,
            'lifecycle': atom.lifecycle.runtimeType.toString(),
          },
      ],
      'hasOlder': lease.hasOlder,
      'frameObservation': frameObservation(lease),
    });
    report['checkpoints'] = _checkpoints;
    expect(main.map((unit) => unit.id).toSet(), hasLength(main.length));
    for (final unit in main.where((unit) => unit.run != null)) {
      expect(unit.entry.atom.payload, isA<DeferredPayload>());
      final folded = ChatItemPresentation.forUnit(unit);
      expect(
        folded.bodies,
        isEmpty,
        reason: 'Main work representatives never inline body bytes',
      );
      expect(
        folded.attachments,
        isEmpty,
        reason: 'Folded work cards never materialize attachment data',
      );
    }
    for (final view in tester.widgetList<TimelineDisplayUnitView>(
      find.byType(TimelineDisplayUnitView),
    )) {
      final unit = view.unit;
      if (unit.run == null) continue;
      final header = tester.widget<TimelineActivityRow>(
        observed.groupHeader(unit.id),
      );
      expect(header.active, isFalse);
      final label =
          unit.entry.mainPresentation == MainPresentation.backgroundResults
          ? '后台结果'
          : '工作记录';
      expect(header.label, '$label · ${unit.entry.run!.ordinal} 项');
    }
  }

  Future<void> capture(String name) =>
      capturePresentation(tester, 'concept-$phase-$name.png');

  /// A synchronous borrow at the end of an already pumped frame. Reading these
  /// values starts no query, paging, body read, or new presentation generation.
  Map<String, Object?> frameObservation(TimelineDisplayLease target) {
    final views = find
        .byWidgetPredicate(
          (widget) =>
              widget is TimelineView &&
              identical(widget.controls, target) &&
              widget.threadId == target.threadId &&
              widget.view.generation == target.generation,
        )
        .evaluate()
        .toList();
    TimelineView? view;
    var visible = false;
    if (views.length == 1) {
      final element = views.single;
      view = element.widget as TimelineView;
      final render = element.findRenderObject();
      visible =
          !target.isRetired &&
          target.isMounted &&
          TickerMode.valuesOf(element).enabled &&
          (view.isDisplayActive?.call() ?? true) &&
          render is RenderBox &&
          render.attached &&
          render.hasSize &&
          !render.size.isEmpty;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if ((widget is Offstage && widget.offstage) ||
            (widget is Opacity && widget.opacity == 0)) {
          visible = false;
          return false;
        }
        return true;
      });
      if (visible && render is RenderBox) {
        final bounds = render.localToGlobal(Offset.zero) & render.size;
        final surface =
            Offset.zero &
            (tester.view.physicalSize / tester.view.devicePixelRatio);
        visible = bounds.overlaps(surface);
      }
    }
    final scroll = target.scrollController;
    final position = scroll.hasClients && scroll.positions.length == 1
        ? scroll.position
        : null;
    final metricsReady =
        position != null &&
        position.hasViewportDimension &&
        position.hasContentDimensions &&
        position.viewportDimension > 0;
    final state = view?.view;
    final loading =
        state == null ||
        state.connection != TimelineConnectionPhase.ready ||
        state.isLoadingOlder;
    final error =
        state?.connectionError ?? state?.olderError ?? target.queryCleanupError;
    final selected =
        graph.client.selection.state.selectedThreadId == target.threadId &&
        identical(graph.timeline.lease(target.threadId), target);
    final geometricallyFilled =
        metricsReady &&
        position.maxScrollExtent > position.minScrollExtent + .5;
    final explicitEof = target.appliedSets > 0 && !target.hasOlder;
    final stable =
        selected &&
        !target.isRetired &&
        target.isMounted &&
        visible &&
        target.appliedSets > 0 &&
        metricsReady &&
        !position.isScrollingNotifier.value &&
        !loading &&
        error == null;
    final first = target.firstContentLayout;
    if (first != null) {
      expect(first.generation, target.generation);
      expect(first.selectionId, target.selectionId);
      expect(first.selectionStartedMicros, target.selectionStartedMicros);
    }
    final observed = graph.timeline.monotonicMicros;
    final completed = stable && (geometricallyFilled || explicitEof);
    return {
      'threadId': target.threadId,
      'ownerGeneration': target.generation,
      'selectionId': target.selectionId,
      'selectionStartedMicros': target.selectionStartedMicros,
      'firstContentElapsedMicros': first?.elapsedMicros,
      'frameObservedMicros': observed,
      'fillObservedMicros': completed ? observed : null,
      'selectionToFillObservedMicros':
          completed && target.selectionStartedMicros != null
          ? observed - target.selectionStartedMicros!
          : null,
      'geometricallyFilled': geometricallyFilled,
      'explicitEof': explicitEof,
      'viewportDimension': metricsReady ? position.viewportDimension : null,
      'minScrollExtent': metricsReady ? position.minScrollExtent : null,
      'maxScrollExtent': metricsReady ? position.maxScrollExtent : null,
      'hasOlder': target.hasOlder,
      'connection': state?.connection.name,
      'loading': loading,
      'error': error?.toString(),
      'selected': selected,
      'mounted': target.isMounted,
      'visible': visible,
      'stableFrame': stable,
      'appliedSets': target.appliedSets,
      'appliedPrepends': target.appliedPrepends,
      'appliedAppends': target.appliedAppends,
      'batchCounterMeaning': 'Main admitted batches, not IO page counts',
      'residentMainMessages': target.controller.messages.length,
      'residentLiveItems': target.content.activity.value?.entries.length ?? 0,
      'residentMountedMembers': target.groupDisplays.fold<int>(
        0,
        (count, display) => count + display.atoms.length,
      ),
      'residentMeaning': 'Main/current items and explicit mounted member windows; not cumulative delivery',
    };
  }

  /// First test-observed stable completion frame: an upper bound, not the
  /// production fill instant. Pump only; the production View owns auto-fill.
  Future<Map<String, Object?>> observeSelectionFill(String label) async {
    final target = lease;
    final generation = target.generation;
    final deadline = Stopwatch()..start();
    var frames = 0;
    final wallStart = DateTime.now().toUtc().toIso8601String();
    while (true) {
      await tester.pump(_samplePump);
      frames++;
      expect(tester.takeException(), isNull);
      expect(lease, same(target));
      expect(lease.generation, generation);
      final observation = frameObservation(target);
      if (observation['error'] != null) {
        fail('Selection observation failed: ${observation['error']}');
      }
      if (observation['fillObservedMicros'] != null) {
        expect(target.selectionId, isNotNull);
        expect(target.selectionStartedMicros, isNotNull);
        return {
          'label': label,
          'phase': phase,
          'platform': Platform.operatingSystem,
          'buildMode': 'debug integration_test',
          'processPid': pid,
          ...observation,
          'pumpSamplingMicros': _samplePump.inMicroseconds,
          'pumpedFrames': frames,
          'timeMeaning':
              'first test-observed stable completion frame upper bound',
          'observationStartedAtUtc': wallStart,
          'observationCompletedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'excludes': ['screenshots', 'build time'],
        };
      }
      if (deadline.elapsed > const Duration(seconds: 60)) {
        fail(
          'No filled viewport or explicit EOF at a stable frame: $observation',
        );
      }
    }
  }

  Future<void> warmSelectionSamples() async {
    final samples = <Map<String, Object?>>[];
    report['warmSelections'] = <String, Object?>{
      'platform': Platform.operatingSystem,
      'buildMode': 'debug integration_test',
      'cacheCondition':
          'same process; OS cache uncontrolled; not cold evidence',
      'samples': samples,
    };
    final generations = <int>{lease.generation};
    final selections = <int?>{lease.selectionId};
    for (var index = 0; index < 20; index++) {
      final before = lease;
      final id = before.threadId;
      expect(before.controller.messages, isNotEmpty);
      await tap(find.byKey(StudioDriverKeys.settingsOpen));
      await _until(
        tester,
        () => find.byKey(StudioDriverKeys.settingsPage).evaluate().isNotEmpty,
        'warm selection settings route',
      );
      await _until(
        tester,
        () => before.isRetired && before.isReleased,
        'warm selection original owner and scopes fully released',
      );
      await before.released;
      expect(before.queryCleanupError, isNull);
      expect(
        (await graph.client.conversations.retryCleanup(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        )).complete,
        isTrue,
      );
      final navigationStartedAtUtc = DateTime.now().toUtc().toIso8601String();
      await tap(find.byKey(StudioDriverKeys.settingsBack));
      await openThread(id);
      final next = lease;
      expect(next, isNot(same(before)));
      expect(next.generation, greaterThan(before.generation));
      expect(generations.add(next.generation), isTrue);
      expect(next.selectionId, isNotNull);
      expect(selections.add(next.selectionId), isTrue);
      final sample = await observeSelectionFill('warm-selection-${index + 1}');
      sample['selectionNavigationStartedAtUtc'] = navigationStartedAtUtc;
      expect(next.appliedSets, 1);
      expect(next.controller.messages, isNotEmpty);
      // A nonempty saved Thread must provide the existing actual layout witness;
      // an empty/idle cold sample may validly retain null.
      await _until(
        tester,
        () => next.firstContentLayout != null,
        'saved nonempty warm selection first-content witness',
      );
      sample['firstContentElapsedMicros'] =
          next.firstContentLayout!.elapsedMicros;
      samples.add(sample);
    }
    expect(samples, hasLength(20));
    Map<String, Object?> summary(String field) {
      final values = samples.map((sample) => sample[field] as int).toList()
        ..sort();
      return {
        'sampleCount': values.length,
        'percentileMethod': 'nearest-rank',
        'p95Micros': values[(values.length * 95 + 99) ~/ 100 - 1],
        'maxMicros': values.last,
      };
    }

    (report['warmSelections'] as Map<String, Object?>).addAll({
      'firstContent': summary('firstContentElapsedMicros'),
      'fillObserved': summary('selectionToFillObservedMicros'),
    });
  }

  /// Runs only while the existing workgroup gate holds the first active member.
  /// Navigation is production UI, not a second feed or a fabricated Set.
  Future<ChatAtom> reopenActiveWorkgroup() async {
    final before = lease;
    final member = live.single;
    final source = member.source;
    expect(source, isA<ForegroundTurnChatSource>());
    final activeTurnId = (source as ForegroundTurnChatSource).turnId;
    expect(member.lifecycle, isA<ActiveChatAtom>());
    expect(member.contents, isNotEmpty);
    final state = graph.client.conversations.session(threadId).state;
    expect(state.activeTurn?.turnId, activeTurnId);
    final originalCurrent = before.currentDisplay!;
    expect(originalCurrent.isCurrent, isTrue);
    final historyIds = items.map((item) => item.recordId).toList();
    expect(historyIds, isNotEmpty);
    expect(historyIds.toSet(), hasLength(historyIds.length));
    Object memberBody(ChatAtomContent content) {
      final target = content.reference.target;
      expect(target, isA<BodyContentTarget>());
      final body = target as BodyContentTarget;
      expect(body.owner, isA<ItemContentOwner>());
      final owner = body.owner as ItemContentOwner;
      expect(owner.itemId, member.id);
      return (
        content.role,
        content.reference.databaseId,
        owner.itemId,
        body.key,
      );
    }

    final bodyIdentities = member.contents.map(memberBody).toList();
    final selectedThread = threadId;
    await tap(find.byKey(StudioDriverKeys.settingsOpen));
    await _until(
      tester,
      () => find.byKey(StudioDriverKeys.settingsPage).evaluate().isNotEmpty,
      'settings while the original Activity is held',
    );
    await _until(
      tester,
      () => before.isRetired && before.isReleased,
      'original Main lease and query scopes joined',
    );
    await before.released;
    expect(before.queryCleanupError, isNull);
    expect(originalCurrent.isCurrent, isFalse);
    expect(originalCurrent.windows, isEmpty);
    expect(
      (await graph.client.conversations.retryCleanup(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      )).complete,
      isTrue,
    );
    await tap(find.byKey(StudioDriverKeys.settingsBack));
    await openThread(selectedThread);
    await _until(
      tester,
      () =>
          lease.appliedSets == 1 &&
          live.any((atom) => atom.id == member.id && atom.source == source),
      'fresh Set and the same independently delivered Activity',
    );
    expect(lease.generation, greaterThan(before.generation));
    expect(lease.currentDisplay!.turnId, activeTurnId);
    final resumed = live.singleWhere((atom) => atom.id == member.id);
    expect(resumed.kind, member.kind);
    expect(resumed.sourceOrder, member.sourceOrder);
    expect(resumed.lifecycle, isA<ActiveChatAtom>());
    expect(resumed.contents.map(memberBody), orderedEquals(bodyIdentities));
    expect(items.map((item) => item.recordId), orderedEquals(historyIds));
    expect(items.where((item) => item.atom.id == member.id), isEmpty);
    expect(main.where((unit) => unit.run != null), isEmpty);
    report['midstreamReopen'] = {
      'gate': 'workgroup',
      'threadId': selectedThread,
      'turnId': activeTurnId,
      'memberId': resumed.id,
      'memberKind': resumed.kind.name,
      'oldGeneration': before.generation,
      'newGeneration': lease.generation,
      'oldLeaseReleased': before.isReleased,
      'newMainSets': lease.appliedSets,
      'historyItemIds': historyIds,
      'activeContentReferences': [
        for (final content in resumed.contents)
          contentReferenceIdentity(content.reference).toString(),
      ],
    };
    await _record('workgroup-reopened');
    return resumed;
  }

  Future<void> idle() async {
    await _until(
      tester,
      () =>
          live.isEmpty &&
          find.byKey(StudioDriverKeys.composerStop).evaluate().isEmpty &&
          find
              .byKey(const ValueKey('conversation-activity'))
              .evaluate()
              .isEmpty,
      'idle with no current strip',
    );
  }

  Future<void> showUnit(String id) async {
    final unit = observed.unit(id);
    Finder target = observed.itemRow(id);
    if (unit.run != null) {
      target = observed.groupHeader(id);
    } else if (unit.entry.atom.kind == ChatAtomKind.compaction) {
      target = find.descendant(
        of: target,
        matching: find.text('已完成压缩', findRichText: true),
      );
    }
    await observed.reveal(target, id);
  }

  Future<void> reveal(Finder finder, {String? unitId}) async {
    final scrollable = find
        .descendant(
          of: find.byKey(lease.chatKey),
          matching: find.byType(Scrollable),
        )
        .first;
    final clock = Stopwatch()..start();
    // Exercise ordinary UI demand until the row is mounted. The deadline bounds
    // the test, not page count; no group-head query or fixed page budget.
    while (finder.evaluate().isEmpty) {
      if (clock.elapsed > const Duration(seconds: 60)) {
        fail('Timed out revealing a real Main item');
      }
      final target = unitId == null
          ? -1
          : main.indexWhere((unit) => unit.id == unitId);
      final mounted =
          tester.allWidgets
              .map(
                (widget) => switch (widget) {
                  TimelineDisplayUnitView(:final unit) => unit.id,
                  ChatItemView(:final item) => item.id,
                  _ => null,
                },
              )
              .map((id) => main.indexWhere((unit) => unit.id == id))
              .where((index) => index >= 0)
              .toList()
            ..sort();
      final newer = target >= 0 && mounted.isNotEmpty && target > mounted.last;
      await tester.drag(scrollable, Offset(0, newer ? -320 : 320));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(finder);
    await tester.pump();
    expect(finder, findsOneWidget);
  }

  Future<void> expand(TimelineDisplayUnit unit) async {
    await observed.openRun(unit.id);
  }

  void _recordMemberInventory(
    String stage,
    String? id, {
    TimelineGroupDisplay? original,
    Object? error,
  }) {
    Map<String, Object?>? reference(CompletionRunRef? value) => value == null
        ? null
        : {
            'startSeq': value.startSeq,
            'databaseId': value.databaseId,
            'indexVersion': value.indexVersion,
          };
    Map<String, Object?> display(TimelineGroupDisplay value) => {
      'unitId': value.unitId,
      'identity': identityHashCode(value),
      'runReference': reference(value.runReference),
      'isCurrent': value.isCurrent,
      'expanded': value.expanded,
      'before': value.before,
      'loading': value.loading,
      'error': value.error?.toString(),
      'mountedMemberCount': value.atoms.length,
      'bodyWindowCount': value.windows.length,
    };
    // Borrow only already mounted consumers, including one still awaiting a
    // permit. This synchronous diagnostic never opens, pages or copies atoms.
    final windows = <Map<String, Object?>>[];
    for (final element in find.byType(TimelineChildrenConnector).evaluate()) {
      final widget = element.widget as TimelineChildrenConnector;
      if (widget.threadId != lease.threadId ||
          widget.runReference == null ||
          element is! StatefulElement) {
        continue;
      }
      final Object state = element.state;
      if (state is! TimelineChildrenDisplay) continue;
      windows.add({
        'parentId': state.parentId,
        'runReference': reference(widget.runReference),
        'generation': state.generation,
        'isCurrent': state.isCurrent,
        'ready': state.ready,
        'olderCursor': state.olderCursor,
        'loadingOlder': state.loadingOlder,
        'error': state.error?.toString(),
        'appliedSets': state.appliedSets,
        'appliedPrepends': state.appliedPrepends,
        'appliedAppends': state.appliedAppends,
      });
    }
    final events =
        (report['memberInventoryLifecycle'] ??= <Map<String, Object?>>[])
            as List<Map<String, Object?>>;
    events.add({
      'stage': stage,
      'itemId': id,
      'mainLeaseGeneration': lease.generation,
      'groupDisplays': lease.groupDisplays.map(display).toList(),
      'memberWindows': windows,
      if (original != null) 'originalDisplay': display(original),
      if (error != null) 'failure': error.toString(),
    });
  }

  /// Explicit UI member demand to EOF. Retain only observed IDs for archived
  /// evidence, not raw atoms or a second group projection. Record explicit
  /// member demands separately from reused windows and Main batch counters.
  Future<List<String>> contentIdentitiesForItem(String id) async {
    final unit = observed.unit(id);
    if (unit.run == null) {
      expect(unit.entry.recordId, isNotNull);
      return [unit.entry.recordId];
    }
    final reusedWindow = lease.groupDisplays.any(
      (display) =>
          display.unitId == id && display.isCurrent && display.expanded,
    );
    TimelineGroupDisplay? original;
    _recordMemberInventory('before-open', id);
    try {
      final display = await observed.openRun(id);
      original = display;
      final ids = <String>{};
      var olderPageCommands = 0;
      while (true) {
        await _until(tester, () {
          expect(display.isCurrent, isTrue);
          expect(display.expanded, isTrue);
          if (display.error case final error?) throw error;
          return !display.loading;
        }, 'original group member window is ready');
        ids.addAll(display.atoms.map((atom) => atom.id));
        if (display.before == null) break;
        final before = display.before;
        final older = find.descendant(
          of: observed.groupRow(id),
          matching: find.byKey(const ValueKey('timeline-children-load-older')),
        );
        // SDK admission precedes the frame that installs the enabled control.
        // Keep the original window and cursor while waiting for that same UI.
        await _until(tester, () {
          expect(display.isCurrent, isTrue);
          expect(display.before, before);
          if (display.error case final error?) throw error;
          final matches = older.evaluate().length;
          expect(matches, lessThanOrEqualTo(1));
          return matches == 1 &&
              tester.widget<TextButton>(older).onPressed != null;
        }, 'enabled original group pagination control');
        await observed.tap(older);
        olderPageCommands++;
        await _until(tester, () {
          if (display.error case final error?) throw StateError('$error');
          return !display.loading && display.before != before;
        }, 'explicit group member page advanced');
      }
      expect(ids, hasLength(unit.entry.run!.ordinal));
      final observations =
          (report['memberPageObservations'] ??= <Map<String, Object?>>[])
              as List<Map<String, Object?>>;
      observations.add({
        'itemId': id,
        'reusedMountedWindow': reusedWindow,
        'memberScopeOpenCommands': reusedWindow ? 0 : 1,
        'olderPageCommands': olderPageCommands,
        'costMeaning':
            'explicit UI demands; not physical/native IO page counts',
        'distinctObservedMembers': ids.length,
        'eof': true,
      });
      _recordMemberInventory('eof', id, original: display);
      final ordered = display.atoms.map((atom) => atom.id).toList();
      expect(ordered.toSet(), ids);
      return ordered;
    } catch (error) {
      _recordMemberInventory('failed', id, original: original, error: error);
      rethrow;
    }
  }

  Future<void> _closeInventoriedGroup(String id) async {
    if (observed.unit(id).run == null) return;
    final display = lease.groupDisplays.singleWhere(
      (display) => display.unitId == id,
    );
    expect(display.isCurrent, isTrue);
    expect(display.expanded, isTrue);
    expect(display.before, isNull);
    expect(display.loading, isFalse);
    _recordMemberInventory('eof-before-close', id, original: display);
    await observed.closeRun(display);
    _recordMemberInventory('closed', id, original: display);
  }

  void _recordImageFailure(
    String stage,
    Object error, {
    TimelineGroupDisplay? original,
  }) {
    final state = graph.client.conversations.session(threadId).state;
    report['imageFailure'] = {
      'stage': stage,
      'failure': error.toString(),
      'expectedMemberCount': _imageMemberCount,
      'activeTurnId': state.activeTurn?.turnId,
      'lastTurnId': state.lastTurn?.turnId,
      'activityAtomIds': [for (final atom in live) atom.id],
      'workRuns': [
        for (final unit in main.where((unit) => unit.run != null))
          {
            'id': unit.id,
            'startSeq': unit.run!.reference.startSeq,
            'ordinal': unit.entry.run!.ordinal,
          },
      ],
    };
    _recordMemberInventory(
      '$stage-failed',
      original?.unitId,
      original: original,
      error: error,
    );
  }

  List<_ImageResult> _imageResults(
    TimelineDisplayUnit unit,
    TimelineGroupDisplay display,
  ) {
    expect(unit.entry.atom.source, isA<ForegroundTurnChatSource>());
    expect(observed.workFor(unit.entry.atom.source), hasLength(1));
    final turnId = (unit.entry.atom.source as ForegroundTurnChatSource).turnId;
    final tools = display.atoms
        .where((atom) => atom.kind == ChatAtomKind.toolCall)
        .toList();
    expect(tools, hasLength(_imageCalls.length + 1));
    expect(tools.map((atom) => atom.tool?.callId).toSet(), {
      ..._imageCalls,
      'concept-image-failed',
    });
    final foreground = {for (final atom in tools) atom.tool!.callId: atom};
    final tasks = <String, String>{};
    final results = <_ImageResult>[];

    TimelineToolPresentation toolOf(ChatItemPresentation value) {
      expect(value.compatibility, ChatItemCompatibility.current);
      expect(value.type, 'tool');
      expect(value.toolCard, isA<DecodedToolCard>());
      return (value.toolCard as DecodedToolCard).value;
    }

    void accept(
      ChatAtom atom,
      TimelineDisplayUnit? finalUnit,
      ChatAtom finalAtom,
      ChatItemPresentation value,
    ) {
      final tool = toolOf(value);
      expect(tool.name, 'view_image');
      expect(tool.toolCallId, atom.tool!.callId);
      expect(
        results.where(
          (result) => result.foreground.tool!.callId == tool.toolCallId,
        ),
        isEmpty,
        reason: 'Each image call has exactly one real final presentation',
      );
      if (tool.toolCallId == 'concept-image-failed') {
        expect(tool.outcome, TimelineToolOutcome.failed);
        expect(tool.error, contains('image source is not a regular file'));
        expect(value.attachments, isEmpty);
      } else {
        expect(tool.outcome, TimelineToolOutcome.succeeded);
        expect(tool.error, isNull);
        expect(value.attachments, hasLength(1));
      }
      results.add((
        foreground: atom,
        finalUnit: finalUnit,
        finalAtom: finalAtom,
        presentation: value,
      ));
    }

    for (final atom in tools) {
      expect(atom.source, unit.entry.atom.source);
      expect(atom.turnId, turnId);
      expect(atom.tool!.name, 'view_image');
      expect(atom.lifecycle, isA<TerminalChatAtom>());
      final terminal = atom.lifecycle as TerminalChatAtom;
      final value = ChatItemPresentation.decode(atom);
      final tool = toolOf(value);
      expect(tool.toolCallId, atom.tool!.callId);
      expect(tool.name, atom.tool!.name);
      switch (atom.delivery) {
        case ChatDeliveryKind.foreground:
          expect(
            terminal.outcome,
            tool.toolCallId == 'concept-image-failed'
                ? ChatTerminalOutcome.failed
                : ChatTerminalOutcome.completed,
          );
          accept(atom, null, atom, value);
        case ChatDeliveryKind.backgroundHandoff:
          expect(terminal.outcome, ChatTerminalOutcome.transferred);
          expect(tool.statusString, 'backgroundStarted');
          expect(tool.outcome, isNull);
          expect(tool.taskId, isNotNull);
          expect(tool.taskId, isNotEmpty);
          tasks[tool.toolCallId] = tool.taskId!;
        default:
          fail('Unexpected foreground image delivery: ${atom.delivery}');
      }
    }
    expect(tasks.values.toSet(), hasLength(tasks.length));
    for (final item in observed.mountedMembers.where(
      (atom) =>
          atom.source is BackgroundResultChatSource &&
          atom.kind == ChatAtomKind.toolCall,
    )) {
      final finalUnit = observed.unitForMember(item.id);
      final value = ChatItemPresentation.decode(item);
      final reading = value.toolCard;
      if (reading is! DecodedToolCard) {
        if (item.turnId == turnId) {
          fail('Image Turn Main result ${item.id} has no decoded tool card');
        }
        continue;
      }
      final tool = reading.value;
      if (item.turnId != turnId &&
          !foreground.containsKey(tool.toolCallId) &&
          !tasks.containsValue(tool.taskId)) {
        continue;
      }
      expect(item.turnId, turnId);
      expect(
        finalUnit.entry.mainPresentation,
        MainPresentation.backgroundResults,
      );
      expect(item.source, isA<BackgroundResultChatSource>());
      expect(item.delivery, ChatDeliveryKind.independent);
      expect(
        (item.lifecycle as TerminalChatAtom).outcome,
        ChatTerminalOutcome.completed,
      );
      expect(item.completionItemId, isNotNull);
      expect(item.completionItemId, isNotEmpty);
      expect(tasks.containsKey(tool.toolCallId), isTrue);
      expect(tool.taskId, tasks[tool.toolCallId]);
      final atom = foreground[tool.toolCallId]!;
      expect(item.completionItemId, isNot(atom.completionItemId));
      accept(atom, finalUnit, item, value);
    }
    return results;
  }

  List<_ImageResult> _verifyImageMembers(
    TimelineDisplayUnit unit,
    TimelineGroupDisplay display,
  ) {
    expect(unit.entry.atom.source, isA<ForegroundTurnChatSource>());
    expect(
      lease.groupDisplays.singleWhere((value) => value.unitId == unit.id),
      same(display),
    );
    expect(display.isCurrent, isTrue);
    expect(display.expanded, isTrue);
    expect(display.runReference, unit.run?.reference);
    expect(display.before, isNull);
    expect(display.loading, isFalse);
    expect(display.error, isNull);
    expect(display.atoms, hasLength(_imageMemberCount));
    expect(
      display.atoms.map((atom) => atom.id).toSet(),
      hasLength(_imageMemberCount),
    );
    expect(display.atoms.map((atom) => atom.source).toSet(), {
      unit.entry.atom.source,
    });
    for (final atom in display.atoms) {
      expect(atom.lifecycle, isA<TerminalChatAtom>());
    }
    final reasoning = display.atoms.where(
      (atom) => atom.kind == ChatAtomKind.reasoning,
    );
    expect(reasoning, hasLength(_imageReasoningCount));
    final texts = <String>[];
    for (final atom in reasoning) {
      expect(atom.tool, isNull);
      expect(
        (atom.lifecycle as TerminalChatAtom).outcome,
        ChatTerminalOutcome.completed,
      );
      final item = ChatItemPresentation.decode(atom);
      expect(item.compatibility, ChatItemCompatibility.current);
      expect(item.type, 'thinking');
      expect(item.data['outcome'], isA<Map<String, Object?>>());
      expect(
        (item.data['outcome'] as Map<String, Object?>)['kind'],
        'completed',
      );
      expect(item.bodies, hasLength(1));
      final text = item.inlineText(item.bodies.single.key);
      expect(text, isNotNull);
      texts.add(text!);
    }
    expect(
      texts,
      unorderedEquals([
        for (var index = 0; index < _imageReasoningCount; index++)
          '检查设计截图与读取边界 $index',
      ]),
    );
    final tools = display.atoms.where(
      (atom) => atom.kind == ChatAtomKind.toolCall,
    );
    expect(tools, hasLength(_imageCalls.length + 1));
    expect(tools.map((atom) => atom.tool?.callId).toSet(), {
      ..._imageCalls,
      'concept-image-failed',
    });
    final results = _imageResults(unit, display);
    expect(results, hasLength(_imageCalls.length + 1));
    expect(
      display.atoms.every((atom) => atom.source == unit.entry.atom.source),
      isTrue,
      reason: 'Background final results keep their independent Run',
    );
    final inventories =
        (report['imageMemberInventories'] ??= <Map<String, Object?>>[])
            as List<Map<String, Object?>>;
    inventories.add({
      'itemId': unit.id,
      'completionSeq': unit.entry.completionSeq,
      'displayIdentity': identityHashCode(display),
      'runStartSeq': display.runReference!.startSeq,
      'eof': true,
      'memberDomain': 'ForegroundMembers',
      'reasoningBodiesVerified': texts.length,
      'members': [
        for (final atom in display.atoms)
          {
            'id': atom.id,
            'kind': atom.kind.name,
            'sameSource': atom.source == unit.entry.atom.source,
            'turnId': atom.turnId,
            'sourceOrder': atom.sourceOrder,
            'completionItemId': atom.completionItemId,
            'delivery': atom.delivery.name,
            'outcome': (atom.lifecycle as TerminalChatAtom).outcome.name,
            if (atom.tool != null) 'toolCallId': atom.tool!.callId,
            'contentReferences': [
              for (final content in atom.contents)
                {
                  'role': content.role.name,
                  'identity': contentReferenceIdentity(content.reference)
                      .toString(),
                },
            ],
          },
      ],
      'finalResults': [
        for (final result in results)
          {
            'domain': result.finalUnit == null
                ? 'ForegroundRun'
                : 'BackgroundRun',
            'foregroundMemberId': result.foreground.id,
            'id': result.presentation.id,
            'contentItemId': result.finalAtom.completionItemId,
            'turnId': result.finalAtom.turnId,
            'sourceKind': result.finalAtom.source.runtimeType.toString(),
            'delivery': result.finalAtom.delivery.name,
            'outcome':
                (result.finalAtom.lifecycle as TerminalChatAtom).outcome.name,
            'toolCallId': result.foreground.tool!.callId,
            'taskId':
                (result.presentation.toolCard as DecodedToolCard).value.taskId,
            'status': (result.presentation.toolCard as DecodedToolCard)
                .value
                .statusString,
            'bodyKeys': result.presentation.bodies
                .map((body) => body.key)
                .toList(),
            'contentReferences': [
              for (final content in result.finalAtom.contents)
                {
                  'role': content.role.name,
                  'identity': contentReferenceIdentity(content.reference)
                      .toString(),
                },
            ],
            'attachmentResourceIds': result.presentation.attachments
                .map((attachment) => attachment.id)
                .toList(),
          },
      ],
    });
    return results;
  }

  Future<void> journey(String project) async {
    await _until(tester, () => !lease.hasOlder, 'empty conversation EOF');
    expect(lease.controller.messages, isEmpty);
    expect(live, isEmpty);
    // Keep the original current observer mounted across activity transitions,
    // while an idle empty conversation must render no content or activity.
    expect(find.byType(ConversationCurrentConnector), findsOneWidget);
    expect(lease.currentDisplay!.isCurrent, isTrue);
    expect(lease.currentDisplay!.windows, isEmpty);
    expect(find.byType(ConversationActivityBar), findsNothing);
    expect(find.byType(TimelineActivityRow), findsNothing);
    expect(find.byType(TimelineDisplayUnitView), findsNothing);
    await capture('empty');
    final evidence = <String, Object?>{};
    report['conversationCredit'] = evidence;
    Future<ConversationFeed>? opening;
    ConversationCreditObservation? credit;
    Object? primaryFailure;
    try {
      await submit(_prompt);
      await reach(
        'thinking',
        () =>
            live.isEmpty &&
            find
                .byKey(const ValueKey('conversation-activity'))
                .evaluate()
                .isNotEmpty,
      );
      expect(main.where((unit) => unit.run != null), isEmpty);
      expect(find.byType(TimelineDisplayUnitView), findsNothing);
      await capture('thinking');
      await _journeyWithCredit(project, () async {
        // Exercise ordinary withheld credit across one new completed text,
        // not cold-source replacement or full-story retention pressure.
        // This observation is opened exactly once, before text B starts.
        evidence['openedAtGate'] = 'second-group-idle';
        evidence['openedForTurnId'] = graph.client.conversations
            .session(threadId)
            .state
            .lastTurn
            ?.turnId;
        await _creditAsync(() async {
          opening = graph.client.transport.openConversationFeed(
            lease.threadId,
            scope: const MainChatScope(),
            demand: const ReadDemand(maxItems: 32, maxBytes: 256 * 1024),
          );
          final feed = await opening!.timeout(
            ConversationCreditObservation.deadline,
          );
          credit = ConversationCreditObservation(feed, evidence);
          await credit!.holdInitialSet();
        });
        return credit!;
      });
    } catch (error, stack) {
      primaryFailure = error;
      evidence['primaryFailure'] = error.toString();
      evidence['primaryStack'] = stack.toString();
      rethrow;
    } finally {
      try {
        await _creditAsync(() async {
          if (opening == null) return;
          // Retain cleanup on the opening future even if open timed out. A
          // late handle must still close; the timeout is not cancellation.
          Future<void> cleanup() async {
            final feed = await opening!;
            credit ??= ConversationCreditObservation(feed, evidence);
            await credit!.close();
          }

          await cleanup().timeout(ConversationCreditObservation.deadline);
        });
      } catch (error, stack) {
        evidence['cleanupFailure'] = error.toString();
        evidence['cleanupStack'] = stack.toString();
        if (primaryFailure == null) rethrow;
        debugPrint('CREDIT_CLEANUP_ERROR\n$error\n$stack');
      }
    }
  }

  /// Keep native futures and their deadlines outside widget virtual time.
  /// Capture inside runAsync so its runner error reporting cannot swallow the
  /// failure before the journey's original-handle finally block sees it.
  Future<void> _creditAsync(Future<void> Function() action) async {
    Object? failure;
    StackTrace? failureStack;
    await tester.runAsync(() async {
      try {
        await action();
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
      }
    });
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
  }

  Future<void> _journeyWithCredit(
    String project,
    Future<ConversationCreditObservation> Function() openCredit,
  ) async {
    await release('thinking');
    await reach(
      'workgroup',
      () => live.length == 1 && live.single.kind == ChatAtomKind.reasoning,
    );
    final active = live.single;
    final source = active.source;
    expect(source, isA<ForegroundTurnChatSource>());
    expect(active.lifecycle, isA<ActiveChatAtom>());
    expect(
      lease.groupDisplays,
      isEmpty,
      reason: 'Activity never opens a historical member window',
    );
    report['initialWorkgroupCollapsed'] = true;
    await capture('workgroup');
    final reopened = await reopenActiveWorkgroup();
    expect(reopened.id, active.id);
    await release('workgroup');
    await reach(
      'group-idle',
      () =>
          observed.workFor(source).isNotEmpty &&
          !live.any((atom) => atom.source == source),
    );
    final firstRuns = observed.workFor(source).toList();
    final g1 = firstRuns.first.id;
    final firstMembers = <ChatAtom>[];
    for (final unit in firstRuns) {
      await contentIdentitiesForItem(unit.id);
      firstMembers.addAll(membersOf(unit.id));
    }
    expect(firstMembers, hasLength(4));
    expect(
      firstMembers.every((atom) => atom.lifecycle is TerminalChatAtom),
      isTrue,
    );
    expect(
      firstMembers
          .where((atom) => atom.tool != null)
          .map((atom) => atom.tool!.callId),
      unorderedEquals([
        'concept-read-call',
        'concept-command-a',
        'concept-command-b',
      ]),
    );
    // Already completed members appear before any subsequent text starts.
    expect(main.any((unit) => unit.id == g1), isTrue);
    await capture('group-idle');
    await release('group-idle');
    await reach(
      'text',
      () =>
          live.any((atom) => atom.kind == ChatAtomKind.text) && hasText(_textA),
    );
    final a = live.singleWhere((atom) => atom.kind == ChatAtomKind.text);
    expect(a.lifecycle, isA<ActiveChatAtom>());
    expect(a.contents, isNotEmpty);
    expect(items.where((entry) => entry.atom.id == a.id), isEmpty);
    await capture('text');
    await release('text');
    await reach(
      'after-text',
      () => live.isEmpty && items.any((entry) => entry.atom.id == a.id),
    );
    final aEntry = items.singleWhere((entry) => entry.atom.id == a.id);
    expect(aEntry.mainPresentation, MainPresentation.single);
    expect(find.byKey(const ValueKey('conversation-activity')), findsOneWidget);
    await capture('after-text');
    await release('after-text');
    await reach(
      'next-group',
      () => live.any((atom) => atom.kind == ChatAtomKind.reasoning),
    );
    expect(live.single.source, source);
    expect(observed.unit(g1).entry, same(firstRuns.first.entry));
    await capture('next-group');
    await release('next-group');
    await reach(
      'second-group-idle',
      () =>
          live.isEmpty &&
          observed
              .workFor(source)
              .any((unit) => unit.entry.completionSeq > aEntry.completionSeq),
    );
    final g2 = observed.workFor(source).last.id;
    expect(g2, isNot(g1));
    final credit = await openCredit();
    await release('second-group-idle');
    await reach(
      'second-text',
      () =>
          live.any((atom) => atom.kind == ChatAtomKind.text) && hasText(_textB),
    );
    final b = live.singleWhere((atom) => atom.kind == ChatAtomKind.text);
    await release('second-text');
    await reach(
      'before-turn-end',
      () => live.isEmpty && items.any((entry) => entry.atom.id == b.id),
    );
    final completedTextB = items.singleWhere((entry) => entry.atom.id == b.id);
    final core = main
        .where((unit) => unit.entry.atom.source == source)
        .toList();
    expect(
      core.map((unit) => unit.id),
      orderedEquals([g1, aEntry.recordId, g2, completedTextB.recordId]),
    );
    for (var i = 1; i < core.length; i++) {
      expect(
        core[i].entry.completionSeq,
        greaterThan(core[i - 1].entry.completionSeq),
      );
    }
    await _creditAsync(() async {
      await credit.queryCompletedText(completedTextB);
      await credit.observeSuccessors();
      await credit.verifyClosed(completedTextB.recordId);
    });
    await release('before-turn-end');
    await idle();
    await _until(tester, () {
      final turn = graph.client.conversations.session(threadId).state.lastTurn;
      return turn?.turnId == completedTextB.atom.turnId &&
          turn?.state.status == StudioTurnStatus.completed;
    }, 'the original successful Turn reaches typed terminal state');
    expect(
      items.where(
        (entry) =>
            entry.atom.source == source &&
            entry.atom.kind == ChatAtomKind.turnReceipt,
      ),
      isEmpty,
      reason: 'Successful Turn must not manufacture a Main receipt',
    );
    final completedTurn = graph.client.conversations
        .session(threadId)
        .state
        .lastTurn!;
    report['completedTurn'] = {
      'source': 'Client typed state',
      'threadId': completedTurn.threadId,
      'turnId': completedTurn.turnId,
      'status': completedTurn.state.status.name,
      'isTerminal': completedTurn.state.isTerminal,
    };
    final firstGroup = observed.unit(g1);
    await expand(firstGroup);
    final reason = membersOf(g1)
        .singleWhere((atom) => atom.kind == ChatAtomKind.reasoning);
    await observed.revealMember(reason, reference: firstGroup.run!.reference);
    final reasoningBody = find.descendant(
      of: observed.memberRow(reason.id),
      matching: find.text('梳理会话共享组件与锁定边界', findRichText: true),
    );
    await _until(
      tester,
      () => reasoningBody.evaluate().length == 1,
      'reasoning body on original Run expansion',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(reasoningBody.hitTestable(), findsOneWidget);
    final reasoningBounds = tester.getRect(reasoningBody);
    expect(reasoningBounds.width, greaterThan(0));
    expect(reasoningBounds.height, greaterThan(0));
    expect(
      reasoningBounds.intersect(tester.getRect(unitFinder(g1))),
      reasoningBounds,
    );
    expect(
      reasoningBounds.intersect(tester.getRect(find.byKey(lease.chatKey))),
      reasoningBounds,
    );
    for (final call in [
      'concept-read-call',
      'concept-command-a',
      'concept-command-b',
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ChatItemView && widget.item.atom?.tool?.callId == call,
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: unitFinder(g1),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    report['coreOrder'] = core.map((unit) => unit.id).toList();
    final identities = <List<String>>[];
    report['coreContentIdentities'] = identities;
    for (final unit in core) {
      identities.add(await contentIdentitiesForItem(unit.id));
      await _closeInventoriedGroup(unit.id);
    }
    await capture('core-main');
    await compact();
    final input = await submitTimelineConceptImageInput(
      tester,
      graph,
      threadId: threadId,
      projectPath: project,
    );
    report['imageInput'] = input.toJson();
    TimelineGroupDisplay? imageDisplay;
    late TimelineDisplayUnit imageWork;
    try {
      await fixtureGate(tester, provider, 'images-ready');
      await _until(
        tester,
        () =>
            main
                .where(
                  (unit) =>
                      unit.entry.mainPresentation ==
                          MainPresentation.foregroundWork &&
                      unit.entry.run!.ordinal == _imageMemberCount,
                )
                .length ==
            1,
        'completed foreground image Run representative',
      );
      imageWork = main.singleWhere(
        (unit) =>
            unit.entry.mainPresentation == MainPresentation.foregroundWork &&
            unit.entry.run!.ordinal == _imageMemberCount,
      );
      report['imageWorkItemId'] = imageWork.id;
      imageDisplay = await observed.openRun(imageWork.id);
      await contentIdentitiesForItem(imageWork.id);
      await _openBackgroundRuns();
      await _until(
        tester,
        () =>
            _imageResults(imageWork, imageDisplay!).length ==
            _imageCalls.length + 1,
        'all exact final image results in independently read Runs',
      );
      _verifyImageMembers(imageWork, imageDisplay);
      await _record('images-ready');
    } catch (error) {
      _recordImageFailure('images-ready', error, original: imageDisplay);
      rethrow;
    }
    await capture('images-live');
    await release('images-ready');
    await idle();
    await _until(
      tester,
      () => hasText(_imageDone),
      'real image continuation answer',
    );
    await verifyImages(imageWorkItemId: imageWork.id, input: input);
    await submit(_failedPrompt);
    await reach(
      'failed-partial',
      () =>
          live.any((atom) => atom.kind == ChatAtomKind.text) &&
          hasText(_partial),
    );
    final partialAtom = live.single.id;
    await capture('failed-partial');
    await release('failed-partial');
    await idle();
    await _until(
      tester,
      () => items.any((entry) => entry.atom.id == partialAtom),
      'failed partial retained',
    );
    final partial = items.singleWhere((entry) => entry.atom.id == partialAtom);
    await _until(
      tester,
      () => items.any(
        (entry) =>
            entry.atom.kind == ChatAtomKind.turnReceipt &&
            (presentation(entry).data['outcome'] as Map)['kind'] == 'failed',
      ),
      'independent failed Turn receipt',
    );
    final failure = items.lastWhere(
      (entry) =>
          entry.atom.kind == ChatAtomKind.turnReceipt &&
          (presentation(entry).data['outcome'] as Map)['kind'] == 'failed',
    );
    expect(failure.recordId, isNot(partial.recordId));
    await showUnit(partial.recordId);
    await _until(
      tester,
      () => hasText(_partial),
      'failed partial still readable',
    );
    await showUnit(failure.recordId);
    await tap(
      find.descendant(
        of: itemFinder(failure.recordId),
        matching: find.byType(TimelineActivityDisclosure),
      ),
    );
    await _until(
      tester,
      () => hasText('concept provider permanent failure'),
      'independent provider failure reason',
    );
    await capture('failed');
    report['partialItemId'] = partial.recordId;
    report['failureItemId'] = failure.recordId;
    await overlap();
    await emptyText();
    await idle();
    await capture('idle');
    await _record('journey-complete');
    report['coreMemberCounts'] = [firstMembers.length, 1];
    report['independentScenarioCoverage'] = {
      'questionsAndReceipts': 'question-history (separate strict provider)',
      'normalStopContinue': 'realtime-presentation (separate strict provider)',
    };
  }

  Future<void> _openBackgroundRuns() async {
    for (final unit
        in main
            .where(
              (unit) =>
                  unit.entry.mainPresentation ==
                  MainPresentation.backgroundResults,
            )
            .toList()) {
      await contentIdentitiesForItem(unit.id);
    }
  }

  Future<void> compact() async {
    final owner = lease;
    final selectedThread = threadId;
    final connector = find.byWidgetPredicate(
      (widget) =>
          widget is ConversationCurrentConnector &&
          identical(widget.content, owner.content),
    );
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(
      location: tester.getCenter(find.byKey(StudioDriverKeys.contextUsage())),
    );
    addTearDown(hover.removePointer);
    await hover.moveTo(
      tester.getCenter(find.byKey(StudioDriverKeys.contextUsage())),
    );
    final control = find.byKey(StudioDriverKeys.compactContext());
    await _until(
      tester,
      () => control.evaluate().isNotEmpty,
      'production compaction button',
    );
    await tap(control);
    await hover.moveTo(Offset.zero);
    await reach(
      'compacting',
      () =>
          live.where((atom) => atom.kind == ChatAtomKind.compaction).length ==
          1,
    );
    expect(lease, same(owner));
    expect(threadId, selectedThread);
    final active = live.singleWhere(
      (atom) => atom.kind == ChatAtomKind.compaction,
    );
    expect(active.source, isA<OperationChatSource>());
    expect(active.lifecycle, isA<ActiveChatAtom>());
    expect(active.completionSeq, isNull);
    expect(items.where((entry) => entry.atom.source == active.source), isEmpty);
    expect(connector, findsOneWidget);
    expect(
      find.descendant(
        of: connector,
        matching: find.byType(ConversationActivityBar),
      ),
      findsOneWidget,
    );
    final rows = find.descendant(
      of: connector,
      matching: find.byType(TimelineActivityRow),
    );
    await _until(
      tester,
      () => rows.evaluate().length == 1,
      'one active compaction row',
    );
    final row = tester.widget<TimelineActivityRow>(rows);
    expect(
      row.label,
      AppLocalizations.of(tester.element(rows)).conversationActivityCompacting,
    );
    expect(row.icon, Icons.compress_outlined);
    expect(row.active, isTrue);
    expect(row.expandable, isFalse);
    report['compactionCurrent'] = {
      'itemId': active.id,
      'operationId': (active.source as OperationChatSource).operationId,
      'rowLabel': row.label,
      'rowActive': row.active,
      'rowExpandable': row.expandable,
    };
    expect(
      tester
          .widget<ContextUsageReadout>(find.byType(ContextUsageReadout))
          .compacting,
      isTrue,
    );
    expect(find.byKey(StudioDriverKeys.composerStop), findsNothing);
    await capture('compacting');
    await release('compacting');
    await _until(
      tester,
      () => items.any(
        (entry) =>
            entry.atom.source == active.source &&
            entry.atom.kind == ChatAtomKind.compaction,
      ),
      'real completed compaction receipt',
    );
    await idle();
    final receipt = items.singleWhere(
      (entry) =>
          entry.atom.source == active.source &&
          entry.atom.kind == ChatAtomKind.compaction,
    );
    expect(receipt.mainPresentation, MainPresentation.single);
    expect(
      (receipt.atom.lifecycle as TerminalChatAtom).outcome,
      ChatTerminalOutcome.completed,
    );
    report['compactionItemId'] = receipt.recordId;
    await showUnit(receipt.recordId);
    final completedRows = find.descendant(
      of: itemFinder(receipt.recordId),
      matching: find.byType(TimelineActivityRow),
    );
    await _until(
      tester,
      () => completedRows.evaluate().length == 1,
      'completed compaction on production page',
    );
    final completed = tester.widget<TimelineActivityRow>(completedRows);
    expect(
      completed.label,
      AppLocalizations.of(tester.element(completedRows))
          .timelineContextCompacted,
    );
    expect(completed.icon, Icons.compress_outlined);
    expect(completed.active, isFalse);
    expect(completed.expandable, isFalse);
    await capture('compacted');
  }

  Future<void> overlap() async {
    await submit(_overlapPrompt);
    await reach(
      'a07-reasoning-start',
      () => live.length == 1 && live.single.kind == ChatAtomKind.reasoning,
    );
    final reason = live.single;
    final originalLease = lease;
    final originalController = lease.controller;
    final originalGeneration = lease.generation;
    final current = lease.currentDisplay!;
    final source = reason.source;
    expect(source, isA<ForegroundTurnChatSource>());
    final turnId = (source as ForegroundTurnChatSource).turnId;
    void expectActiveReasoning() {
      expect(lease, same(originalLease));
      expect(lease.controller, same(originalController));
      expect(lease.generation, originalGeneration);
      expect(current.isCurrent, isTrue);
      final atom = live.singleWhere((atom) => atom.id == reason.id);
      expect(atom.source, source);
      expect(atom.sourceOrder, reason.sourceOrder);
      expect(atom.lifecycle, isA<ActiveChatAtom>());
      expect(items.where((entry) => entry.atom.id == reason.id), isEmpty);
    }

    expectActiveReasoning();
    await release('a07-reasoning-start');
    await reach(
      'a07-b-terminal',
      () => items.any(
        (entry) =>
            entry.atom.source == source &&
            entry.atom.kind == ChatAtomKind.reasoning &&
            entry.atom.id != reason.id,
      ),
    );
    expectActiveReasoning();
    expect(live, hasLength(1));
    final early = main.singleWhere(
      (unit) =>
          unit.entry.atom.source == source &&
          unit.entry.atom.kind == ChatAtomKind.reasoning,
    );
    expect(early.entry.mainPresentation, MainPresentation.foregroundWork);
    expect(early.entry.run!.ordinal, 1);
    expect(early.entry.atom.payload, isA<DeferredPayload>());
    expect(early.entry.atom.lifecycle, isA<TerminalChatAtom>());
    expect(early.entry.completionSeq, greaterThan(0));
    expect(main.where((unit) => unit.entry.atom.source == source), [
      same(early),
    ], reason: 'B completes into its own Main card while A is still active');
    await showUnit(early.id);
    expect(
      tester
          .widget<TimelineActivityRow>(observed.groupHeader(early.id))
          .expanded,
      isFalse,
    );
    expect(
      lease.groupDisplays.where((display) => display.unitId == early.id),
      isEmpty,
    );
    expect(
      lease.currentDisplay!.windows.where(
        (window) => window.id == early.entry.atom.id,
      ),
      isEmpty,
      reason: 'Completed B is not read as an Activity body',
    );
    expect(hasText(_overlapEarlyReasoning), isFalse);
    final earlyDisplay = await observed.openRun(early.id);
    expect(await contentIdentitiesForItem(early.id), [early.entry.atom.id]);
    final earlyMember = earlyDisplay.atoms.single;
    expect(earlyMember.id, early.entry.atom.id);
    expect(earlyMember.source, source);
    expect(earlyMember.completionItemId, early.entry.recordId);
    expect(earlyMember.completionSeq, early.entry.completionSeq);
    expect(
      (earlyMember.lifecycle as TerminalChatAtom).outcome,
      ChatTerminalOutcome.completed,
    );
    await observed.revealMember(earlyMember, reference: early.run!.reference);
    final earlyBody = find.descendant(
      of: observed.memberRow(earlyMember.id),
      matching: find.textContaining(_overlapEarlyReasoning, findRichText: true),
    );
    await _until(
      tester,
      () => earlyBody.evaluate().isNotEmpty,
      'B body read only after expanding its independent Run',
    );
    expectActiveReasoning();
    expect(lease.controller, same(originalController));
    await observed.closeRun(earlyDisplay);
    expect(earlyDisplay.atoms, isEmpty);
    expect(earlyDisplay.windows, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(hasText(_overlapEarlyReasoning), isFalse);
    await capture('a07-b-completed-before-text');
    await release('a07-b-terminal');
    await reach(
      'a07-text-start',
      () => live.length == 2 && hasText('正文已经开始且可以读取，'),
    );
    final text = live.singleWhere((atom) => atom.kind == ChatAtomKind.text);
    expectActiveReasoning();
    expect(items.where((entry) => entry.atom.id == text.id), isEmpty);
    await release('a07-text-start');
    await reach('a07-text-readable', () => hasText(_overlapText));
    expectActiveReasoning();
    await capture('a07-late-reasoning');
    await release('a07-text-readable');
    await reach(
      'a07-text-terminal',
      () => items.any((entry) => entry.atom.id == text.id),
    );
    expectActiveReasoning();
    expect(live.where((atom) => atom.id == text.id), isEmpty);
    final completedText = items.singleWhere(
      (entry) => entry.atom.id == text.id,
    );
    expect(completedText.mainPresentation, MainPresentation.single);
    expect(
      main
          .where((unit) => unit.entry.atom.source == source)
          .map((unit) => unit.id),
      orderedEquals([early.id, completedText.recordId]),
      reason: 'B is visible before text; unfinished A has no completed card',
    );
    expect(completedText.completionSeq, greaterThan(early.entry.completionSeq));
    expect(observed.unit(early.id).entry, same(early.entry));
    await release('a07-text-terminal');
    await reach(
      'a07-reasoning-terminal',
      () => items.any((entry) => entry.atom.id == reason.id),
    );
    final work = main.singleWhere((unit) => unit.entry.atom.id == reason.id);
    expect(
      work.entry.completionSeq,
      greaterThan(completedText.completionSeq),
      reason: 'Late reasoning stays after completed text, never reinserted before it',
    );
    expect(work.entry.mainPresentation, MainPresentation.foregroundWork);
    expect(work.id, isNot(early.id));
    expect(work.run!.reference, isNot(early.run!.reference));
    expect(
      main
          .where((unit) => unit.entry.atom.source == source)
          .map((unit) => unit.id),
      orderedEquals([early.id, completedText.recordId, work.id]),
      reason: 'Late A starts a new Run after text instead of joining B',
    );
    expect(observed.unit(early.id).entry, same(early.entry));
    expect(
      work.entry.run!.ordinal,
      1,
      reason: 'A single completed work item is still a card',
    );
    expect(live.where((atom) => atom.id == reason.id), isEmpty);
    final display = await observed.openRun(work.id);
    await contentIdentitiesForItem(work.id);
    final member = display.atoms.single;
    expect(member.id, reason.id);
    expect(member.source, source);
    expect(member.sourceOrder, reason.sourceOrder);
    expect(member.completionItemId, work.entry.recordId);
    expect(member.completionSeq, work.entry.completionSeq);
    expect(
      (member.lifecycle as TerminalChatAtom).outcome,
      ChatTerminalOutcome.completed,
    );
    expect(lease.controller, same(originalController));
    await release('a07-reasoning-terminal');
    await idle();
    await _until(tester, () {
      final turn = graph.client.conversations.session(threadId).state.lastTurn;
      return turn?.turnId == turnId &&
          turn?.state.status == StudioTurnStatus.completed;
    }, 'original overlap Turn finishes');
    report['overlapAtomIds'] = [earlyMember.id, reason.id];
    Map<String, Object?> identity(TimelineDisplayUnit unit) => {
      'messageId': unit.id,
      'recordId': unit.entry.recordId,
      'completionSeq': unit.entry.completionSeq,
      'atomId': unit.entry.atom.id,
      'mainPresentation': unit.entry.mainPresentation.name,
      if (unit.run case final run?)
        'run': {
          'databaseId': run.reference.databaseId,
          'indexVersion': run.reference.indexVersion,
          'startSeq': run.reference.startSeq,
        },
    };
    final handoff = <String, Object?>{
      'completionOrder': [
        early.entry.recordId,
        completedText.recordId,
        work.entry.recordId,
      ],
      'completionSeqs': [
        early.entry.completionSeq,
        completedText.completionSeq,
        work.entry.completionSeq,
      ],
      'records': [
        identity(early),
        identity(observed.unit(completedText.recordId)),
        identity(work),
      ],
      'sourceTurnId': turnId,
      'earlyBodyReadThroughRun': true,
      'earlyRunRevokedBeforeText': !earlyDisplay.isCurrent,
    };
    report['a07Handoff'] = handoff;
    await observed.closeRun(display);
    expect(
      (await graph.client.conversations.retryCleanup(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      )).complete,
      isTrue,
    );
    expect(lease, same(originalLease));
    expect(lease.controller, same(originalController));
    expect(lease.generation, originalGeneration);
    expect(display.isCurrent, isFalse);
    expect(display.atoms, isEmpty);
    expect(display.windows, isEmpty);
    final selectedThread = threadId;
    await tap(find.byKey(StudioDriverKeys.settingsOpen));
    await _until(
      tester,
      () => originalLease.isRetired && originalLease.isReleased,
      'A07 original Main lease and member/body queries released on navigation',
    );
    await originalLease.released;
    expect(originalLease.queryCleanupError, isNull);
    expect(current.isCurrent, isFalse);
    expect(current.windows, isEmpty);
    await tap(find.byKey(StudioDriverKeys.settingsBack));
    await openThread(selectedThread);
    expect(lease, isNot(same(originalLease)));
    expect(lease.generation, greaterThan(originalGeneration));
    await _until(
      tester,
      () => lease.appliedSets == 1,
      'fresh Main Set after the completed A07 selection reopens',
    );
    await verifyOverlapHistory(handoff);
    handoff['selectionReopened'] = {
      'oldGeneration': originalGeneration,
      'newGeneration': lease.generation,
      'oldLeaseReleased': originalLease.isReleased,
      'mainSets': lease.appliedSets,
    };
    await _record('a07-closed');
  }

  Future<void> verifyOverlapHistory(Map<String, dynamic> saved) async {
    final records = (saved['records'] as List).cast<Map<String, dynamic>>();
    expect(records, hasLength(3));
    final source = ForegroundTurnChatSource(
      turnId: saved['sourceTurnId'] as String,
    );
    final owner = lease;
    final controller = lease.controller;
    for (var index = 0; index < records.length; index++) {
      final savedRecord = records[index];
      final id = savedRecord['messageId'] as String;
      final isWork = savedRecord['run'] != null;
      await reveal(
        isWork ? observed.groupHeader(id) : observed.itemRow(id),
        unitId: id,
      );
      final unit = observed.unit(id);
      expect(unit.entry.recordId, savedRecord['recordId']);
      expect(unit.entry.completionSeq, savedRecord['completionSeq']);
      expect(unit.entry.atom.id, savedRecord['atomId']);
      expect(unit.entry.atom.source, source);
      expect(unit.entry.mainPresentation.name, savedRecord['mainPresentation']);
      if (isWork) {
        final reference = savedRecord['run'] as Map<String, dynamic>;
        expect(unit.run!.reference.databaseId, reference['databaseId']);
        expect(unit.run!.reference.indexVersion, reference['indexVersion']);
        expect(unit.run!.reference.startSeq, reference['startSeq']);
        expect(unit.entry.run!.ordinal, 1);
        expect(unit.entry.atom.payload, isA<DeferredPayload>());
        expect(await contentIdentitiesForItem(id), [
          savedRecord['atomId'],
        ], reason: 'Each saved Run reads its original member to EOF');
        final display = lease.groupDisplays.singleWhere(
          (display) => display.unitId == id,
        );
        final member = display.atoms.single;
        expect(member.id, savedRecord['atomId']);
        expect(member.completionItemId, savedRecord['recordId']);
        expect(member.completionSeq, savedRecord['completionSeq']);
        expect(member.source, source);
        expect(
          (member.lifecycle as TerminalChatAtom).outcome,
          ChatTerminalOutcome.completed,
        );
        await observed.revealMember(member, reference: unit.run!.reference);
        final expectedBody = index == 0
            ? _overlapEarlyReasoning
            : _overlapReasoning;
        await _until(
          tester,
          () => find
              .descendant(
                of: observed.memberRow(member.id),
                matching: find.textContaining(expectedBody, findRichText: true),
              )
              .evaluate()
              .isNotEmpty,
          'saved A07 Run member body at $index',
        );
        await observed.closeRun(display);
        expect(display.atoms, isEmpty);
        expect(display.windows, isEmpty);
      } else {
        expect(unit.run, isNull);
        expect(unit.entry.mainPresentation, MainPresentation.single);
        await _until(
          tester,
          () => find
              .descendant(
                of: observed.itemRow(id),
                matching: find.textContaining(_overlapText, findRichText: true),
              )
              .evaluate()
              .isNotEmpty,
          'saved A07 completed text body',
        );
      }
      expect(lease, same(owner));
      expect(lease.controller, same(controller));
      expect(lease.appliedSets, 1);
    }
    expect(
      main
          .where((unit) => unit.entry.atom.source == source)
          .map((unit) => unit.id),
      orderedEquals(records.map((record) => record['messageId'])),
    );
    expect(
      main
          .where((unit) => unit.entry.atom.source == source)
          .map((unit) => unit.entry.recordId),
      orderedEquals(saved['completionOrder'] as List),
    );
    expect(
      main
          .where((unit) => unit.entry.atom.source == source)
          .map((unit) => unit.entry.completionSeq),
      orderedEquals(saved['completionSeqs'] as List),
    );
    expect(
      (await graph.client.conversations.retryCleanup(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      )).complete,
      isTrue,
    );
    report['a07HistoryVerified'] = {
      'phase': phase,
      'generation': lease.generation,
      'completionOrder': saved['completionOrder'],
      'completionSeqs': saved['completionSeqs'],
      'runMembersReadToEof': 2,
      'memberScopesJoined': true,
    };
  }

  Future<void> emptyText() async {
    await submit(_emptyTextPrompt);
    await reach('a14-before-empty', () {
      final turn = graph.client.conversations
          .session(threadId)
          .state
          .activeTurn;
      if (turn == null) return false;
      return live.isEmpty &&
          observed
              .workFor(ForegroundTurnChatSource(turnId: turn.turnId))
              .any((unit) => unit.entry.run!.ordinal == 1);
    });
    final source = ForegroundTurnChatSource(
      turnId: graph.client.conversations
          .session(threadId)
          .state
          .activeTurn!
          .turnId,
    );
    final before = observed.workFor(source).single;
    expect(before.entry.run!.ordinal, 1);
    await release('a14-before-empty');
    await reach(
      'a14-empty-start',
      () => live.any((atom) => atom.kind == ChatAtomKind.text),
    );
    final empty = live.singleWhere((atom) => atom.kind == ChatAtomKind.text);
    expect(empty.contentPresent, isFalse);
    await release('a14-empty-start');
    await reach(
      'a14-empty-terminal',
      () => !live.any((atom) => atom.id == empty.id),
    );
    expect(
      items.where((entry) => entry.atom.id == empty.id),
      isEmpty,
      reason: 'An empty completed body is Hidden and does not divide a Run',
    );
    await release('a14-empty-terminal');
    await reach(
      'a14-after-empty',
      () => observed.workFor(source).single.entry.run!.ordinal == 2,
    );
    final after = observed.workFor(source).single;
    expect(after.id, before.id);
    expect(after.run!.reference, before.run!.reference);
    await capture('a14-empty-separator');
    await release('a14-after-empty');
    await reach('a14-text-readable', () => hasText(_emptyTextAnswer));
    await release('a14-text-readable');
    await reach('a14-before-turn-end', () => live.isEmpty);
    expect(observed.workFor(source), hasLength(1));
    expect(
      itemFinder(empty.id),
      findsNothing,
      reason: 'Structural empty text must not paint an empty bubble',
    );
    await release('a14-before-turn-end');
    await idle();
    final atomIds = await contentIdentitiesForItem(after.id);
    expect(atomIds, hasLength(2));
    report['emptySeparatorWorkAtomIds'] = atomIds;
    await _closeInventoriedGroup(after.id);
  }

  Future<void> _verifyImageResult(
    _ImageResult result, {
    TimelineGroupDisplay? display,
    required bool missing,
  }) async {
    final item = result.presentation;
    final tool = (item.toolCard as DecodedToolCard).value;
    final finalUnit = result.finalUnit;
    if (finalUnit == null) {
      expect(display, isNotNull);
      expect(
        await observed.revealMember(
          result.foreground,
          reference: display!.runReference!,
        ),
        same(display),
      );
    } else {
      await observed.revealMember(
        result.finalAtom,
        reference: finalUnit.run!.reference,
      );
    }
    final card = observed.memberRow(result.finalAtom.id);
    expect(card, findsOneWidget);
    final rendered = tester.widget<ChatItemView>(card).item;
    expect(rendered.id, item.id);
    if (finalUnit == null) {
      expect(rendered.atom!.id, result.foreground.id);
      expect(rendered.atom!.source, result.foreground.source);
    } else {
      expect(rendered.atom?.id, result.finalAtom.id);
      expect(rendered.atom?.source, result.finalAtom.source);
    }
    final details = find.descendant(
      of: card,
      matching: find.byType(TimelineToolDetails),
    );
    expect(details, findsOneWidget);
    final detailsElement = tester.element(details);
    final renderedTool = tester.widget<TimelineToolDetails>(details).item;
    expect(renderedTool.toolCallId, tool.toolCallId);
    expect(renderedTool.outcome, tool.outcome);
    final disclosure = find.descendant(
      of: details,
      matching: find.byKey(ValueKey('timeline-tool-details:${tool.id}')),
    );
    expect(disclosure, findsOneWidget);
    final disclosureElement = tester.element(disclosure);
    final tiles = find.descendant(
      of: disclosure,
      matching: find.byElementPredicate(
        (element) =>
            element.widget is ExpansionTile &&
            identical(
              element
                  .findAncestorWidgetOfExactType<TimelineActivityDisclosure>(),
              disclosureElement.widget,
            ),
      ),
    );
    expect(tiles, findsOneWidget);
    final tileElement = tester.element(tiles);
    final title = find.descendant(
      of: disclosure,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            identical(
              widget.title,
              (tileElement.widget as ExpansionTile).title,
            ),
      ),
    );
    final header = find.descendant(
      of: title,
      matching: find.byType(TimelineActivityRow),
    );
    bool expanded() {
      expect(details, findsOneWidget);
      expect(tester.element(details), same(detailsElement));
      expect(disclosure, findsOneWidget);
      expect(tester.element(disclosure), same(disclosureElement));
      expect(tiles, findsOneWidget);
      expect(tester.element(tiles), same(tileElement));
      expect(tileElement.mounted, isTrue);
      expect(title, findsOneWidget);
      expect(header, findsOneWidget);
      return tester.widget<TimelineActivityRow>(header).expanded;
    }

    if (!expanded()) await observed.tap(title);
    expect(expanded(), isTrue);
    // Reuse this call's original media/error wait allowance for its actual body,
    // Viewer and UI close too, rather than granting each step a new deadline.
    final readWait = Stopwatch()..start();
    Duration remaining() => const Duration(seconds: 60) - readWait.elapsed;
    final declarations = result.finalAtom.contents
        .where(
          (content) =>
              content.role == ChatContentRole.toolArguments ||
              content.role == ChatContentRole.toolOutput,
        )
        .toList();
    final bodyConnectors = find.descendant(
      of: card,
      matching: find.byType(TimelineContentRangeConnector),
    );
    final windows = [
      for (final element in bodyConnectors.evaluate())
        (element as StatefulElement).state as TimelineCurrentWindowDisplay,
    ];
    expect(windows, isNotEmpty);
    expect(
      windows.map((window) => contentReferenceIdentity(window.reference)),
      unorderedEquals(
        declarations.map(
          (content) => contentReferenceIdentity(content.reference),
        ),
      ),
    );
    final images = find.descendant(
      of: card,
      matching: find.byType(TimelineImageView),
    );
    final failure = find.descendant(
      of: card,
      matching: find.textContaining(
        'image source is not a regular file',
        findRichText: true,
      ),
    );
    final succeeded = tool.outcome == TimelineToolOutcome.succeeded;
    await _until(
      tester,
      () {
        for (final window in windows) {
          if (window.error case final error?) throw StateError('$error');
        }
        if (windows.any((window) => window.window == null)) return false;
        if (!succeeded) return failure.evaluate().isNotEmpty;
        return tester
            .widgetList<TimelineImageView>(images)
            .any((view) => missing ? view.error != null : view.bytes != null);
      },
      'real final image bytes or directory error ${tool.toolCallId}',
      timeout: remaining(),
    );
    if (succeeded) {
      final views = tester.widgetList<TimelineImageView>(images);
      expect(views, hasLength(1));
      final view = views.single;
      expect(view.itemId, item.id);
      expect(view.attachment.id, item.attachments.single.id);
      expect(view.isTool, isTrue);
      if (missing) {
        expect(view.bytes, isNull);
        expect(view.error, isNotNull);
      } else {
        expect(view.error, isNull);
        expect(view.bytes, isNotEmpty);
        final entry = StudioDriverKeys.toolImageEntryId(
          item.id,
          item.attachments.single.id,
        );
        await observed.tap(
          find.descendant(
            of: card,
            matching: find.byKey(StudioDriverKeys.viewImageThumbnail(entry)),
          ),
        );
        final dialog = find.byKey(StudioDriverKeys.viewImageDialog(entry));
        await _until(
          tester,
          () => dialog.evaluate().length == 1,
          'real final tool image Viewer ${tool.toolCallId}',
          timeout: remaining(),
        );
        expect(
          find.descendant(of: dialog, matching: find.byType(InteractiveViewer)),
          findsOneWidget,
        );
        await observed.tap(
          find.descendant(
            of: dialog,
            matching: find.byKey(StudioDriverKeys.timelineImageClose),
          ),
        );
        await _until(
          tester,
          () => dialog.evaluate().isEmpty,
          'final tool image Viewer closed',
          timeout: remaining(),
        );
      }
    } else {
      expect(images, findsNothing);
      expect(failure, findsWidgets);
      await capture('read-images');
    }
    expect(expanded(), isTrue);
    try {
      // Keep the same title's center inside both nested and reversed viewports.
      await observed.tap(title, scrollAlignment: 0.5);
    } catch (error) {
      // Preserve the original tap failure and only observe its original control.
      // A laid-out title can still be clipped or covered after the Viewer closes.
      final failure = <String, Object?>{
        'toolId': tool.id,
        'toolCallId': tool.toolCallId,
        'delivery': finalUnit == null ? 'ForegroundMembers' : 'MainStatus',
        'error': error.toString(),
      };
      report['imageResultUiFailure'] = failure;
      try {
        final titles = title.evaluate().toList(growable: false);
        failure['titleMatches'] = titles.length;
        failure['titleHitTestableMatches'] = title
            .hitTestable()
            .evaluate()
            .length;
        failure['dialogMatches'] = find.byType(Dialog).evaluate().length;
        failure['modalBarrierMatches'] = find
            .byType(ModalBarrier)
            .evaluate()
            .length;
        if (titles.length == 1) {
          final rect = tester.getRect(title);
          final center = tester.getCenter(title);
          failure['titleRect'] = [rect.left, rect.top, rect.right, rect.bottom];
          failure['titleCenter'] = [center.dx, center.dy];
          failure['centerHitTestPath'] = [
            for (final entry in tester.hitTestOnBinding(center).path)
              entry.target.runtimeType.toString(),
          ];
          final scrollables = <Map<String, Object?>>[];
          titles.single.visitAncestorElements((element) {
            if (element is StatefulElement &&
                element.state is ScrollableState) {
              final state = element.state as ScrollableState;
              final position = state.position;
              final viewport = tester.getRect(
                find.byElementPredicate(
                  (candidate) => identical(candidate, element),
                ),
              );
              scrollables.add({
                'axisDirection': position.axisDirection.name,
                'viewportRect': [
                  viewport.left,
                  viewport.top,
                  viewport.right,
                  viewport.bottom,
                ],
                'pixels': position.hasPixels ? position.pixels : null,
                'viewportDimension': position.hasViewportDimension
                    ? position.viewportDimension
                    : null,
                'minScrollExtent': position.hasContentDimensions
                    ? position.minScrollExtent
                    : null,
                'maxScrollExtent': position.hasContentDimensions
                    ? position.maxScrollExtent
                    : null,
              });
            }
            return true;
          });
          failure['ancestorScrollables'] = scrollables;
        }
      } catch (diagnosticError) {
        failure['diagnosticError'] = diagnosticError.toString();
      }
      rethrow;
    }
    expect(expanded(), isFalse);
    await _until(
      tester,
      () => windows.every((window) => window.window == null),
      'closed final image card revokes its original body windows',
      timeout: remaining(),
    );
    final closeRemaining = remaining();
    expect(closeRemaining > Duration.zero, isTrue);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      closeRemaining,
    );
    expect(tester.takeException(), isNull);
    expect(windows.every((window) => window.window == null), isTrue);
    expect(images, findsNothing);
    expect(bodyConnectors, findsNothing);
    final observations =
        (report['imageResultUi'] ??= <Map<String, Object?>>[])
            as List<Map<String, Object?>>;
    observations.add({
      'domain': finalUnit == null ? 'ForegroundMembers' : 'MainStatus',
      'foregroundMemberId': result.foreground.id,
      'rowId': item.id,
      'toolCallId': tool.toolCallId,
      'taskId': tool.taskId,
      'status': tool.statusString,
      'attachmentResourceIds': item.attachments
          .map((attachment) => attachment.id)
          .toList(),
      'mediaMissing': succeeded && missing,
      'originalBodyWindowCount': windows.length,
      'originalBodyWindowsRevoked': true,
      'titleExpandedAfterClose': false,
    });
  }

  Future<void> verifyImages({
    required String imageWorkItemId,
    TimelineConceptImageInput? input,
    bool missing = false,
  }) async {
    // Prepare this finite scene through the same Main paging owner before
    // freezing the unchanged-order baseline. This is not a scroll witness.
    final originalLease = lease;
    final pageClock = Stopwatch()..start();
    while (originalLease.hasOlder) {
      expect(lease, same(originalLease));
      final before = originalLease.olderCursor;
      expect(before, isNotNull);
      final remaining = const Duration(seconds: 60) - pageClock.elapsed;
      expect(remaining > Duration.zero, isTrue);
      await graph.timeline
          .loadOlder(threadId, generation: originalLease.generation)
          .timeout(remaining);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(lease, same(originalLease));
      expect(graph.timeline.source.value?.olderError, isNull);
      expect(originalLease.olderCursor, isNot(before));
    }
    final imageGroup = main.singleWhere((unit) => unit.id == imageWorkItemId);
    try {
      expect(
        imageGroup.entry.mainPresentation,
        MainPresentation.foregroundWork,
      );
      expect(imageGroup.entry.run!.ordinal, _imageMemberCount);
      expect(imageGroup.entry.atom.lifecycle, isA<TerminalChatAtom>());
      expect(imageGroup.entry.atom.payload, isA<DeferredPayload>());
      expect(imageGroup.run?.reference, isNotNull);
    } catch (error) {
      _recordImageFailure('read-images-summary', error);
      rethrow;
    }
    final representative = imageGroup.entry;
    // A folded item carries summary/ref only, not hidden member/media widgets.
    final mountedBefore = lease.groupDisplays
        .where((display) => display.unitId == imageWorkItemId)
        .singleOrNull;
    if (mountedBefore == null) {
      expect(membersOf(imageWorkItemId), isEmpty);
    }
    final display = await observed.openRun(imageGroup.id);
    final mainIds = items.map((item) => item.recordId).toList();
    final before = lease.olderCursor;
    expect(before, isNull);
    report['imageMainBaseline'] = {
      'ownerGeneration': lease.generation,
      'hasOlder': lease.hasOlder,
      'olderCursor': before,
      'mainIds': mainIds,
    };
    final liveIds = live.map((unit) => unit.id).toList();
    late final List<_ImageResult> results;
    try {
      await contentIdentitiesForItem(imageGroup.id);
      await _openBackgroundRuns();
      results = _verifyImageMembers(imageGroup, display);
    } catch (error) {
      _recordImageFailure('read-images', error, original: display);
      rethrow;
    }
    expect(display.runReference, imageGroup.run?.reference);
    expect(lease.olderCursor, before);
    expect(live.map((unit) => unit.id), orderedEquals(liveIds));
    report['ordinaryDetailWindowObserved'] = true;
    report['readImageResourceIds'] = [
      for (final call in _imageCalls)
        results
            .singleWhere((result) => result.foreground.tool!.callId == call)
            .presentation
            .attachments
            .single
            .id,
    ];
    for (final result in results.where((result) => result.finalUnit == null)) {
      await _verifyImageResult(result, display: display, missing: missing);
    }
    expect(items.map((item) => item.recordId), orderedEquals(mainIds));
    expect(lease.olderCursor, before);
    final afterMedia = observed.unit(imageWorkItemId).entry;
    expect(
      afterMedia,
      same(representative),
      reason: 'Member/media reads do not replace Main representatives',
    );
    expect(
      lease.groupDisplays.singleWhere((value) => value.unitId == imageGroup.id),
      same(display),
    );
    _recordMemberInventory(
      'media-before-close',
      imageGroup.id,
      original: display,
    );
    await observed.closeRun(display);
    _recordMemberInventory('media-closed', imageGroup.id, original: display);
    expect(display.atoms, isEmpty);
    expect(display.before, isNull);
    expect(imageGroup.expansion.bodyActive, isFalse);
    final joinedWait = Stopwatch()..start();
    expect(
      (await graph.client.conversations.retryCleanup(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      )).complete,
      isTrue,
    );
    final joinedRemaining = const Duration(seconds: 60) - joinedWait.elapsed;
    expect(joinedRemaining > Duration.zero, isTrue);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      joinedRemaining,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: observed.groupRow(imageGroup.id),
        matching: find.byType(TimelineImageView),
      ),
      findsNothing,
    );
    await tester.pump();
    expect(
      display.atoms,
      isEmpty,
      reason: 'late member delivery cannot restore folded body',
    );
    expect(display.windows, isEmpty);
    // Independent results keep their own Main rows and resource owners. Close
    // the original member scope first; it cannot close these cards for us.
    for (final result in results.where((result) => result.finalUnit != null)) {
      await _verifyImageResult(result, missing: missing);
    }
    expect(items.map((item) => item.recordId), orderedEquals(mainIds));
    final afterFinals = observed.unit(imageWorkItemId).entry;
    expect(
      afterFinals,
      same(representative),
      reason: 'Member/media reads do not replace Main representatives',
    );
    expect(display.atoms, isEmpty);
    expect(display.windows, isEmpty);
    if (input != null) {
      final itemValue = items.singleWhere(
        (item) => item.atom.source == InputChatSource(inputId: input.inputId),
      );
      expect(itemValue.mainPresentation, MainPresentation.single);
      expect(itemValue.atom.kind, ChatAtomKind.input);
      expect(observed.unit(itemValue.recordId).run, isNull);
      final item = presentation(itemValue);
      await showUnit(itemValue.recordId);
      final card = itemFinder(itemValue.recordId);
      try {
        await _until(tester, () {
          for (final view in tester.widgetList<TimelineImageView>(
            find.descendant(of: card, matching: find.byType(TimelineImageView)),
          )) {
            if (view.error case final error?) throw error;
          }
          return item.attachments.every(
            (attachment) => find
                .byKey(StudioDriverKeys.viewImageThumbnail(attachment.id))
                .evaluate()
                .isNotEmpty,
          );
        }, 'three decoded real user input thumbnails');
      } catch (error) {
        report['inputThumbnailFailure'] = {
          'itemId': itemValue.recordId,
          'cardCount': card.evaluate().length,
          'sameLease': identical(lease, originalLease),
          'error': error.toString(),
          'views': [
            for (final view in tester.widgetList<TimelineImageView>(
              find.byType(TimelineImageView, skipOffstage: false),
            ))
              if (view.itemId == itemValue.recordId)
                {
                  'attachmentId': view.attachment.id,
                  'active': view.active,
                  'bytes': view.bytes?.length,
                  'width': view.width,
                  'height': view.height,
                  'error': view.error?.toString(),
                },
          ],
        };
        rethrow;
      }
      report['imageInput'] = input.verifyHorizontalLayout(
        tester,
        item: itemValue,
        attachments: item.attachments,
        itemFinder: card,
        thumbnailFinder: (id) =>
            find.byKey(StudioDriverKeys.viewImageThumbnail(id)),
      );
      final first = item.attachments.first.id;
      await tap(find.byKey(StudioDriverKeys.viewImageThumbnail(first)));
      await _until(
        tester,
        () => find
            .byKey(StudioDriverKeys.timelineImageDialog(first))
            .evaluate()
            .isNotEmpty,
        'original image dialog',
      );
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await capture('read-images-original');
      await tap(find.byKey(StudioDriverKeys.timelineImageClose));
    }
    report['mediaResourceFailureObserved'] = missing;
  }

  Future<void> reopened(
    Map<String, dynamic> saved, {
    required bool missing,
  }) async {
    await idle();
    if (!missing) await warmSelectionSamples();
    final input = saved['imageInput'] as Map<String, dynamic>;
    final inputId = input['inputId'] as String;
    // Production projection IDs survive reopen. Reveal exactly the saved Main
    // item, never search folded groups by member contents or ID prefixes.
    final target = find.byWidgetPredicate(
      (widget) => widget is ChatItemView && widget.item.id == input['itemId'],
    );
    await reveal(target);
    final item = items.singleWhere(
      (item) => item.atom.source == InputChatSource(inputId: inputId),
    );
    expect(item.recordId, input['itemId']);
    expect(item.recordId, input['contentItemId']);
    expect(item.mainPresentation, MainPresentation.single);
    expect(item.atom.kind, ChatAtomKind.input);
    final attachments = presentation(item).attachments;
    expect(
      attachments.map((attachment) => attachment.id),
      orderedEquals((input['attachmentResourceIds'] as List).cast<String>()),
    );
    expect(attachments, hasLength(3));
    await _until(
      tester,
      () =>
          tester
              .widgetList<TimelineImageView>(
                find.descendant(
                  of: target,
                  matching: find.byType(TimelineImageView),
                ),
              )
              .where((view) => view.bytes != null && view.error == null)
              .length ==
          3,
      'cold-open user attachment bytes remain readable',
    );
    final rectangles = [
      for (final attachment in attachments)
        tester.getRect(
          find.byKey(StudioDriverKeys.viewImageThumbnail(attachment.id)),
        ),
    ];
    for (var index = 1; index < rectangles.length; index++) {
      expect(rectangles[index].top, closeTo(rectangles.first.top, 1));
      expect(
        rectangles[index].left,
        greaterThanOrEqualTo(rectangles[index - 1].right),
      );
    }
    final imageWorkItemId = saved['imageWorkItemId'] as String;
    await showUnit(imageWorkItemId);
    await verifyImages(imageWorkItemId: imageWorkItemId, missing: missing);
    expect(
      report['readImageResourceIds'],
      orderedEquals((saved['readImageResourceIds'] as List).cast<String>()),
    );
    final segments = (saved['coreContentIdentities'] as List)
        .map((segment) => (segment as List).cast<String>())
        .toList();
    final coreIds = (saved['coreOrder'] as List).cast<String>();
    await showUnit(coreIds.first);
    final reopenedUnits = [
      for (final id in coreIds) main.singleWhere((unit) => unit.id == id),
    ];
    expect(
      reopenedUnits.map((unit) => unit.entry.mainPresentation),
      orderedEquals([
        MainPresentation.foregroundWork,
        MainPresentation.single,
        MainPresentation.foregroundWork,
        MainPresentation.single,
      ]),
    );
    expect(reopenedUnits.first.id, isNot(reopenedUnits[2].id));
    for (var index = 0; index < reopenedUnits.length; index++) {
      expect(
        await contentIdentitiesForItem(reopenedUnits[index].id),
        orderedEquals(segments[index]),
      );
      await _closeInventoriedGroup(reopenedUnits[index].id);
      if (index > 0) {
        expect(
          main.indexOf(reopenedUnits[index]),
          greaterThan(main.indexOf(reopenedUnits[index - 1])),
        );
      }
    }
    await verifyOverlapHistory(saved['a07Handoff'] as Map<String, dynamic>);
    for (final field in [
      'partialItemId',
      'failureItemId',
      'compactionItemId',
    ]) {
      final id = saved[field] as String;
      await showUnit(id);
      expect(items.where((item) => item.recordId == id), hasLength(1));
      expect(
        items.singleWhere((item) => item.recordId == id).completionSeq,
        greaterThan(0),
      );
    }
    report['reopenedInputId'] = inputId;
    report['ownerGeneration'] = lease.generation;
    await _record(missing ? 'media-missing-complete' : 'reopen-complete');
    await capture('complete');
  }
}
