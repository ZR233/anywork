import 'support/display_record_observation.dart';

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
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state.dart';
import 'package:anywork/src/features/conversation/timeline/state/content_reference_identity.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_current_views.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_clock.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_image_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/features/status/context_usage_readout.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/conversation_credit_observation.dart';
import 'support/fixture_gate.dart';
import 'support/presentation_capture.dart';
import 'support/timeline_concept_images.dart';
import 'support/timeline_concept_presentation.dart';
import 'support/timeline_observation.dart';

part 'support/timeline_concept_media_handoff.dart';

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
const _emptyTextPrompt = 'A13：空正文保留真实边界，前后工作使用不同展示组。';
const _emptyTextAnswer = '空正文不显示卡片，前后工作分别保留。';
const _hotUpdatePrompt = '同一正文内依次追加二十个可控增量，保持展示身份不变。';
const _hotUpdateHead = '热更新正文：';
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
  final requestedPhase = Platform.environment['ANYWORK_TIMELINE_CONCEPT_PHASE'];
  final boundary =
      requestedPhase == 'boundary' || requestedPhase == 'boundary-reopen';
  final media =
      requestedPhase == 'media-handoff' ||
      requestedPhase == 'media-handoff-reopen';
  if (requestedPhase?.startsWith('media-handoff') == true && !media) {
    throw StateError('Unsupported media-handoff phase: $requestedPhase');
  }
  final reopen = boundary || media
      ? requestedPhase == 'boundary-reopen' ||
            requestedPhase == 'media-handoff-reopen'
      : Platform.environment['ANYWORK_TIMELINE_CONCEPT_REOPEN'] == '1';
  final missing =
      Platform.environment['ANYWORK_TIMELINE_CONCEPT_MEDIA_FAULT'] == '1';
  final phase = boundary || media
      ? requestedPhase!
      : missing
      ? 'media-missing'
      : reopen
      ? 'reopen'
      : 'journey';
  final reportName = boundary
      ? (reopen ? 'timeline-boundary-reopen.json' : 'timeline-boundary.json')
      : media
      ? (reopen
            ? 'timeline-media-handoff-reopen.json'
            : 'timeline-media-handoff.json')
      : missing
      ? 'timeline-concept-media-missing.json'
      : reopen
      ? 'timeline-concept-reopen.json'
      : 'timeline-concept.json';
  final report = <String, Object?>{
    'scenario': boundary
        ? 'timeline-boundary'
        : media
        ? 'media-handoff'
        : 'timeline-concept',
    'phase': phase,
    'runner': 'flutter.integration_test',
    'pass': false,
    'expectedRequiredProviderSteps': boundary
        ? 1
        : media
        ? 2
        : 10,
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
    final textScale = ValueNotifier<double>(1);
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
        final boundaryThread = report['threadId'];
        final boundaryLease = boundary && boundaryThread is String
            ? graph.timeline.lease(boundaryThread)
            : null;
        final boundaryDisplays = boundaryLease?.currentDisplays.toList() ?? [];
        graph.setConversationPageVisible(false);
        await tester.pumpWidget(const SizedBox());
        expect(
          (await graph.client.conversations.retryCleanup(
            deadline: DateTime.now().add(const Duration(seconds: 5)),
          )).complete,
          isTrue,
        );
        if (boundary && assertionsPassed) expect(boundaryLease, isNotNull);
        if (boundaryLease != null) {
          await boundaryLease.released.timeout(const Duration(seconds: 5));
          expect(boundaryLease.isRetired, isTrue);
          expect(boundaryLease.isReleased, isTrue);
          expect(boundaryLease.queryCleanupError, isNull);
          for (final boundaryCurrent in boundaryDisplays) {
            expect(boundaryCurrent.isCurrent, isFalse);
            expect(boundaryCurrent.windows, isEmpty);
          }
          report['boundaryLeaseCleanup'] = {
            'retired': boundaryLease.isRetired,
            'released': boundaryLease.isReleased,
            'queryCleanupError': null,
            'currentWindowsRevoked': true,
          };
        }
      } catch (_) {
        assertionsPassed = false;
        rethrow;
      } finally {
        tester.testTextInput.unregister();
        router.routerDelegate.removeListener(syncRoute);
        router.dispose();
        textScale.dispose();
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
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: textScale,
              child: child,
              builder: (context, scale, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          ),
        ),
      ),
    );
    report['window'] = await configurePresentationWindow(tester);
    await graph.client.directoryCommands.openProject(project);
    graph.setConversationPageVisible(true);
    final scene = _ConceptScene(
      tester,
      graph,
      provider,
      report,
      phase,
      textScale,
    );
    Map<String, dynamic>? boundarySaved;
    var selectedThread = emptyThread;
    if (boundary && reopen) {
      boundarySaved = jsonDecode(
        await File('$output/timeline-boundary.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(boundarySaved['pass'], isTrue);
      expect(boundarySaved['shutdown'], 'completed');
      expect(boundarySaved['phase'], 'boundary');
      expect(boundarySaved['expectedRequiredProviderSteps'], 1);
      selectedThread = boundarySaved['threadId'] as String;
      expect(selectedThread, isNotEmpty);
    }
    report['threadId'] = selectedThread;
    await scene.openThread(selectedThread);
    report['coldProcessSelection'] = await scene.observeSelectionFill(
      'cold-process-selection',
    );
    if (boundary) {
      if (reopen) {
        await scene.idle();
        final handoff = boundarySaved!['a07Handoff'] as Map<String, dynamic>;
        await scene.verifyOverlapHistory(handoff);
        report['a07Handoff'] = handoff;
        await scene.capture('cold-reopened');
        await scene._record('boundary-cold-reopened');
      } else {
        await scene.expectEmptyConversation();
        await scene.overlap();
      }
    } else if (media) {
      // Registered last, so lease release/join precedes even UI teardown and
      // Studio shutdown when a native assertion throws.
      if (!reopen) {
        addTearDown(() => scene.closeMediaLease(success: assertionsPassed));
      }
      await scene.mediaHandoff(project, reopen: reopen);
    } else if (reopen) {
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
  while (true) {
    if (clock.elapsed >= deadline) {
      fail('Timed out waiting for $description');
    }
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  }
}

typedef _ImageResult = ({
  ChatAtom foreground,
  TimelineDisplayUnit? finalUnit,
  DisplayMemberHead? finalMember,
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
    this.textScale,
  );
  final WidgetTester tester;
  final AppGraph graph;
  final Uri provider;
  final Map<String, Object?> report;
  final String phase;
  final ValueNotifier<double> textScale;
  final List<Map<String, Object?>> _checkpoints = [];
  static const _samplePump = Duration(milliseconds: 16);
  String get threadId => graph.client.selection.state.selectedThreadId!;
  TimelineDisplayLease get lease => graph.timeline.lease(threadId)!;
  late final observed = TimelineObservation(tester, () => lease);

  // Borrow existing immutable values only. None of these getters opens a query,
  // runs a body read, classifies atoms, or keeps a second presentation list.
  List<TimelineDisplayUnit> get main => observed.main.toList();
  List<ChatAtom> get live => observed.liveAtoms.toList();
  Iterable<TimelineDisplayUnit> get items => observed.singleBlocks;
  Iterable<ChatAtom> membersOf(String unitId) => lease.groupDisplays
      .where((display) => display.unitId == unitId)
      .expand((display) => display.atoms);
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

  Future<void> backFromSettings() async {
    final page = find.byKey(StudioDriverKeys.settingsPage);
    final back = find.byKey(StudioDriverKeys.settingsBack);
    try {
      await _until(
        tester,
        () =>
            page.evaluate().length == 1 &&
            back.evaluate().length == 1 &&
            tester.widget<InkWell>(back).onTap != null &&
            back.hitTestable().evaluate().length == 1,
        'actual settings page and unique enabled hittable back control',
      );
    } catch (error, stack) {
      report['settingsNavigationFailure'] = {
        'pageCount': page.evaluate().length,
        'backCount': back.evaluate().length,
        'hittableBackCount': back.hitTestable().evaluate().length,
        'exceptionType': error.runtimeType.toString(),
        'stack': stack.toString(),
      };
      rethrow;
    }
    await tap(back);
  }

  Future<void> submit(String text) async {
    final input = find.byKey(const ValueKey('composer-input'));
    try {
      await _until(tester, () => input.evaluate().isNotEmpty, 'composer input');
    } catch (error) {
      final client = graph.client;
      final selected = client.selection.state.selectedThreadId;
      final state = selected == null
          ? null
          : client.conversations.existingSession(selected)?.state;
      report['composerInputFailure'] = {
        'exceptionType': error.runtimeType.toString(),
        'selectedThreadId': selected,
        'visibleThreadId': client.conversations.visibleThreadId.value,
        'hasSnapshot': state?.hasSnapshot,
        'directoryThreadStatus': selected == null
            ? null
            : switch (client.threadDirectory
                  .observedThread(selected)
                  ?.backend) {
                NativeAgentBackendView(:final status) => status.name,
                AcpAgentBackendView() || null => null,
              },
        'workspaceThreadStatus': state?.workspace?.thread.status.name,
        'agentStatus': client.project.state.agents?.values
            .where((agent) => agent.threadId == selected)
            .firstOrNull
            ?.state
            .label,
      };
      rethrow;
    }
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
    final snapshot = target?.live.value;
    final currentDisplays = target?.currentDisplays.toList() ?? [];
    final status = state?.activity;
    final execution = state?.runtime?.execution;
    const activityKey = ValueKey('conversation-activity');
    final keyOnstage = find.byKey(activityKey).evaluate().length;
    final keyAll = find
        .byKey(activityKey, skipOffstage: false)
        .evaluate()
        .length;
    final liveEmpty = snapshot?.blocks.isEmpty ?? true;
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
        'currentDisplays': [
          for (final current in currentDisplays)
            {
              'isCurrent': current.isCurrent,
              'expanded': current.expanded,
              'turnId': current.turnId,
              'activityId': current.activityId,
              'windowCount': current.windows.length,
            },
        ],
      },
      'live': snapshot == null
          ? null
          : {
              'revision': snapshot.revision,
              'historyThrough': snapshot.historyThrough,
              'executionPresent': snapshot.executionPresent,
              'blockCount': snapshot.blocks.length,
              'blocks': [
                for (final block in snapshot.blocks.take(16))
                  {
                    'id': block.id,
                    'bodyKind': block.body.runtimeType.toString(),
                    'blockOrder': block.blockOrder,
                    'state': block.state.name,
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
              'section': widget.section.name,
              'surface': widget.presenting?.surface.runtimeType.toString(),
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
            'blockId': unit.id,
            'historyPos': unit.historyPos,
            'presentation': unit.body is WorkDisplayBlock ? 'work' : 'single',
            'memberBlockId': unit.memberReference?.blockId,
            'total': unit.summary?.total,
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
    for (final unit in main.where((unit) => unit.body is WorkDisplayBlock)) {
      expect(
        unit.atom,
        isNull,
        reason: 'Work header carries summary/ref, not representative payload',
      );
      final folded = ChatItemPresentation.forUnit(unit);
      expect(
        folded.bodies,
        isEmpty,
        reason: 'Work headers never inline member body bytes',
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
      if (unit.body is SingleDisplayBlock) continue;
      final header = observed.groupHeader(unit.id);
      expect(header, findsOneWidget);
      final title = timelineGroupTitleFinder(tester, header);
      expect(title, findsOneWidget);
      final paragraph = timelineGroupTitleParagraph(tester, title);
      final titleText = timelineGroupTitleText(tester, title);
      expect(titleText.trim(), isNotEmpty);
      expect(paragraph.maxLines, 1);
      expect(paragraph.softWrap, isFalse);
      expect(paragraph.overflow, TextOverflow.ellipsis);
      final indicator = find.descendant(
        of: header,
        matching: find.byType(TimelineActivityIndicator),
      );
      expect(indicator, findsOneWidget);
      final activity = tester.widget<TimelineActivityIndicator>(indicator);
      expect(activity.icon, isNotNull);
      final summary = unit.summary!;
      final live = unit.state == DisplayBlockState.open;
      if (!live || !unit.executionPresent || summary.failed > 0) {
        expect(activity.active, isFalse);
      } else if (summary.running > 0 || summary.waiting > 0) {
        expect(activity.active, isTrue);
      }
      final context = tester.element(header);
      final l10n = AppLocalizations.of(context);
      final tooltip = find.descendant(
        of: header,
        matching: find.byType(Tooltip),
      );
      expect(tooltip, findsOneWidget);
      expect(
        tester.widget<Tooltip>(tooltip).message,
        contains(l10n.timelineGroupMemberCount(summary.total)),
      );
      for (final outcome in [
        if (summary.failed > 0) l10n.timelineGroupFailedCount(summary.failed),
        if (summary.cancelled > 0)
          l10n.timelineGroupStoppedCount(summary.cancelled),
        if (summary.transferred > 0)
          l10n.timelineGroupTransferredCount(summary.transferred),
      ]) {
        expect(tester.widget<Tooltip>(tooltip).message, contains(outcome));
      }
      final elapsed = find.descendant(
        of: header,
        matching: find.byKey(const ValueKey('work-header-elapsed')),
      );
      final savedElapsed = summary.elapsedMs;
      if (!live) {
        expect(elapsed, findsNothing);
        expect(
          titleText,
          savedElapsed != null && savedElapsed >= 0
              ? activityDurationLabel(
                  context,
                  savedElapsed ~/ 1000,
                  kind: ActivityDurationKind.worked,
                )
              : l10n.timelineGroupRecord,
        );
      } else {
        final runView = tester.widget<CompletionRunView>(
          find.ancestor(of: header, matching: find.byType(CompletionRunView)),
        );
        final cleanIdle =
            summary.running == 0 &&
            summary.waiting == 0 &&
            summary.failed == 0 &&
            summary.cancelled == 0 &&
            summary.transferred == 0;
        final activeThought =
            [runView.activity?.thinkingSummary, summary.thinkingSummary]
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .firstOrNull;
        if (!unit.executionPresent) {
          expect(titleText, l10n.timelineGroupUnrestored);
        } else if ((summary.running > 0 || summary.waiting > 0 || cleanIdle) &&
            activeThought != null) {
          if (activeThought == '梳理 **会话共享组件** 与 `LiveStatusBar` 锁定边界') {
            expect(titleText, '梳理 会话共享组件 与 LiveStatusBar 锁定边界');
          } else if (!timelineNeedsSafeMarkdown(activeThought)) {
            expect(titleText, activeThought);
          }
        }
        final runningClock = unit.executionPresent && summary.createdAt != null;
        if (runningClock || savedElapsed != null && savedElapsed >= 0) {
          expect(elapsed, findsOneWidget);
          final clock = tester.widget<Text>(elapsed);
          expect(clock.maxLines, 1);
          expect(clock.softWrap, isFalse);
          expect(clock.data, startsWith('执行了'));
          final elapsedRect = tester.getRect(elapsed);
          final titleRect = tester.getRect(title);
          expect(elapsedRect.left, greaterThanOrEqualTo(titleRect.right));
          expect(elapsedRect.center.dy, closeTo(titleRect.center.dy, 1));
        } else {
          expect(elapsed, findsNothing);
        }
      }
      final expanded = observed.groupExpanded(unit.id);
      final arrow = find.descendant(
        of: header,
        matching: find.byIcon(
          expanded
              ? Icons.keyboard_arrow_down_rounded
              : Icons.chevron_right_rounded,
        ),
      );
      expect(arrow, findsOneWidget);
      final titleRect = tester.getRect(title);
      final indicatorRect = tester.getRect(indicator);
      final arrowRect = tester.getRect(arrow);
      expect(titleRect.width, greaterThan(0));
      expect(indicatorRect.right, lessThan(titleRect.left));
      expect(indicatorRect.center.dy, closeTo(titleRect.center.dy, 1));
      expect(titleRect.right, lessThanOrEqualTo(arrowRect.left));
      expect(arrowRect.right, lessThanOrEqualTo(tester.getRect(header).right));
    }
  }

  Future<void> capture(String name) =>
      capturePresentation(tester, 'concept-$phase-$name.png');

  Future<void> captureAccessibleVariants(
    String stage, {
    required String workBlockId,
    String? streamingAtomId,
  }) async {
    final captures = report.putIfAbsent(
      'accessibleCaptures',
      () => <Map<String, Object?>>[],
    ) as List<Map<String, Object?>>;
    final view = tester.view;
    final originalWidth = view.physicalSize.width / view.devicePixelRatio;
    final originalHeight = view.physicalSize.height / view.devicePixelRatio;
    final originalScale = textScale.value;
    void expectPausedState() {
      final work = observed.unit(workBlockId);
      expect(work.summary!.total, 2);
      expect(work.summary!.terminal, 1);
      expect(work.summary!.running, 1);
      if (streamingAtomId != null) {
        expect(work.historyPos, greaterThan(0));
        expect(work.state, DisplayBlockState.sealed);
        final text = observed.liveBlocks.singleWhere(
          (block) =>
              block.body is SingleDisplayBlock &&
              (block.body as SingleDisplayBlock).record.atom.id ==
                  streamingAtomId,
        );
        expect(
          (text.body as SingleDisplayBlock).record.atom.lifecycle,
          isA<ActiveChatAtom>(),
        );
      } else {
        expect(work.state, DisplayBlockState.open);
        expect(work.historyPos, isNull);
      }
    }

    expectPausedState();
    final evidence = <String, Object?>{
      'fixtureStage': stage,
      'workBlockId': workBlockId,
      'streamingAtomId': streamingAtomId,
      'liveBlockIds': observed.liveBlocks.map((block) => block.id).toList(),
      'liveBlocks': [
        for (final block in observed.liveBlocks)
          {
            'blockId': block.id,
            'state': block.state.name,
            ...switch (block.body) {
              WorkDisplayBlock(:final summary) => {
                'kind': 'work',
                'total': summary.total,
                'terminal': summary.terminal,
                'running': summary.running,
              },
              SingleDisplayBlock(record: DisplayRecord(:final atom)) => {
                'kind': 'single',
                'atomId': atom.id,
              },
            },
          },
      ],
      'originalViewport': {
        'width': originalWidth,
        'height': originalHeight,
        'textScale': originalScale,
      },
      'variants': <Map<String, Object?>>[],
    };
    captures.add(evidence);
    if (!Platform.environment.containsKey('ANYWORK_PRESENTATION_SCREENSHOTS')) {
      evidence['status'] = 'not requested; no native screenshot directory';
      return;
    }
    Object? primaryFailure;
    try {
      for (final scale in [1.0, 1.6]) {
        final name = scale == 1 ? '$stage-narrow' : '$stage-narrow-large-text';
        final variant = <String, Object?>{
          'fileName': 'concept-$phase-$name.png',
          'textScale': scale,
          'requestedLogicalWidth': 600,
          'requestedLogicalHeight': 900,
          'pass': false,
        };
        (evidence['variants'] as List<Map<String, Object?>>).add(variant);
        try {
          variant['viewport'] = await configurePresentationWindow(
            tester,
            logicalWidth: 600,
            logicalHeight: 900,
          );
          textScale.value = scale;
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          expect(
            MediaQuery.textScalerOf(tester.element(find.byType(TimelineView)))
                .scale(10),
            10 * scale,
          );
          expect(
            observed.liveBlocks.map((block) => block.id),
            orderedEquals(evidence['liveBlockIds'] as List<String>),
          );
          expectPausedState();
          if (streamingAtomId != null) {
            await _until(
              tester,
              () => _incrementGlyph(streamingAtomId, _overlapText) != null,
              'sealed Work snapshot and fully readable streaming body at $name',
            );
          }
          await capture(name);
          expect(tester.takeException(), isNull);
          variant['pass'] = true;
        } catch (error, stack) {
          variant['failure'] = '$error';
          variant['stack'] = '$stack';
          // Keep the failed real layout as evidence; never shrink text or hide
          // content to make a constrained native window look successful.
          final failureName = '$name-failed';
          try {
            await capture(failureName);
            variant['failureScreenshot'] = 'concept-$phase-$failureName.png';
          } catch (captureError) {
            variant['failureScreenshotError'] = '$captureError';
          }
          rethrow;
        } finally {
          variant['observedViewport'] = {
            'width': view.physicalSize.width / view.devicePixelRatio,
            'height': view.physicalSize.height / view.devicePixelRatio,
            'devicePixelRatio': view.devicePixelRatio,
          };
        }
      }
    } catch (error) {
      primaryFailure = error;
      rethrow;
    } finally {
      textScale.value = originalScale;
      try {
        evidence['restoredViewport'] = await configurePresentationWindow(
          tester,
          logicalWidth: originalWidth,
          logicalHeight: originalHeight,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(TimelineView)))
              .scale(10),
          10 * originalScale,
        );
        evidence['restoredTextScale'] = textScale.value;
      } catch (error, stack) {
        evidence['restoreFailure'] = '$error';
        evidence['restoreStack'] = '$stack';
        // Preserve the layout/resize failure if restoration fails as well.
        if (primaryFailure == null) rethrow;
      }
    }
  }

  // Same production glyph/ancestor-clip observation as timeline_presentation.
  // Every non-whitespace glyph inside this unique increment must be laid out
  // and visible, not just its shared "[" prefix or a clipped sliver. This
  // borrows layout and never opens a body query.
  Rect? _incrementGlyph(String atomId, String increment) {
    final member = find.byWidgetPredicate(
      (widget) => widget is TimelineMemberAtom && widget.atom.id == atomId,
    );
    if (member.evaluate().length != 1) return null;
    final bodies = find.descendant(
      of: member,
      matching: find.byType(TimelineMarkdown),
    );
    final surface = tester.renderObject<RenderBox>(
      find.byKey(presentationCaptureKey),
    );
    for (final rich
        in find
            .descendant(
              of: bodies,
              matching: find.byWidgetPredicate((widget) => widget is RichText),
            )
            .evaluate()) {
      final paragraph = rich.findRenderObject();
      if (paragraph is! RenderParagraph ||
          !paragraph.attached ||
          !paragraph.hasSize ||
          paragraph.debugNeedsLayout ||
          !surface.attached ||
          !surface.hasSize) {
        continue;
      }
      final text = paragraph.text.toPlainText();
      final start = text.indexOf(increment);
      if (start < 0) continue;
      Rect? incrementBounds;
      var fullyVisible = true;
      for (var offset = start; offset < start + increment.length; offset++) {
        if (text[offset].trim().isEmpty) continue;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 1),
        );
        if (boxes.isEmpty) fullyVisible = false;
        for (final box in boxes) {
          final laidOut = MatrixUtils.transformRect(
            paragraph.getTransformTo(surface),
            box.toRect(),
          );
          var visible = laidOut.intersect(Offset.zero & surface.size);
          RenderObject child = paragraph;
          while (!identical(child, surface)) {
            final parent = child.parent;
            if (parent == null || !parent.attached) return null;
            final clip = parent.describeApproximatePaintClip(child);
            if (clip != null) {
              visible = visible.intersect(
                MatrixUtils.transformRect(parent.getTransformTo(surface), clip),
              );
            }
            child = parent;
          }
          if (!visible.isFinite ||
              visible.isEmpty ||
              visible.width + 0.5 < laidOut.width ||
              visible.height + 0.5 < laidOut.height) {
            fullyVisible = false;
          }
          incrementBounds =
              incrementBounds?.expandToInclude(visible) ?? visible;
        }
      }
      if (fullyVisible && incrementBounds != null) return incrementBounds;
    }
    return null;
  }

  Map<String, Object?> _hotUpdateCut() {
    final refs = graph.client.conversations
        .session(threadId)
        .state
        .businessRefs;
    final window = lease.live.value!;
    final planDocument = refs?.plan?.document;
    return {
      'ownerGeneration': lease.generation,
      'appliedSets': lease.appliedSets,
      'appliedAppends': lease.appliedAppends,
      'appliedPrepends': lease.appliedPrepends,
      'mainIds': main.map((unit) => unit.id).toList(),
      'messageIds': lease.controller.messages
          .map((message) => message.id)
          .toList(),
      'structureRevision': window.revision,
      'historyThrough': window.historyThrough,
      'liveBlocks': [
        for (final block in window.blocks)
          {
            'blockId': block.id,
            'blockOrder': block.blockOrder,
            'state': block.state.name,
          },
      ],
      'businessRefs': {
        'present': refs != null,
        'planRevision': refs?.plan?.revision,
        'planPhase': refs?.plan?.phase.name,
        'planDocument': planDocument == null
            ? null
            : contentReferenceIdentity(planDocument).toString(),
        'interactionDatabaseId': refs?.interactions?.databaseId,
        'interactionCollection': refs?.interactions?.collection,
        'interactionRevision': refs?.interactions?.revision,
      },
    };
  }

  Future<void> hotUpdateSamples() async {
    await submit(_hotUpdatePrompt);
    await reach(
      'hot-ready',
      () => observed.liveBlocks.length == 1 && hasText(_hotUpdateHead),
    );
    final owner = lease;
    final controller = owner.controller;
    final block = observed.liveBlocks.single;
    expect(block.body, isA<SingleDisplayBlock>());
    final atom = (block.body as SingleDisplayBlock).record.atom;
    expect(atom.kind, ChatAtomKind.text);
    expect(atom.lifecycle, isA<ActiveChatAtom>());
    await _until(
      tester,
      () => _incrementGlyph(atom.id, _hotUpdateHead) != null,
      'hot update baseline body glyph laid out',
    );
    final refs = graph.client.conversations
        .session(threadId)
        .state
        .businessRefs;
    final before = _hotUpdateCut();
    final samples = <Map<String, Object?>>[];
    final evidence = <String, Object?>{
      'platform': Platform.operatingSystem,
      'buildMode': 'debug',
      'surface': 'native integration_test; production Rust→FRB→SDK→View',
      'display': Platform.environment['DISPLAY'],
      'displayCondition': 'X11 DISPLAY recorded above; outer harness must confirm Xvfb ownership',
      'provider': 'strict loopback fixture; one request / one stable Single',
      'pollIntervalMicros': _samplePump.inMicroseconds,
      'samplingInterval':
          'sequential observer-controlled gates; no fixed token interval; '
          'actual release spacing recorded per sample',
      'start': 'monotonic Stopwatch immediately before HTTP gate release',
      'stop':
          'first observation with every non-whitespace glyph of the unique '
          'increment laid out and fully visible in the production body, '
          'clipped by real surface and ancestor paint clips',
      'semantics':
          'test-observed upper bound including HTTP release and frame polling; '
          'not token network-to-screen latency; excludes screenshots/build time',
      'blockId': block.id,
      'atomId': atom.id,
      'before': before,
      'samples': samples,
    };
    report['hotUpdates'] = evidence;
    final clock = Stopwatch()..start();
    int? previousRelease;
    for (var index = 1; index <= 20; index++) {
      final previous = index == 1
          ? 'hot-ready'
          : 'hot-${(index - 1).toString().padLeft(2, '0')}';
      final next = 'hot-${index.toString().padLeft(2, '0')}';
      final increment = '[${index.toString().padLeft(2, '0')}]';
      expect(_incrementGlyph(atom.id, increment), isNull);
      expect(_hotUpdateCut(), before);
      final sample = <String, Object?>{
        'index': index,
        'releasedGate': previous,
        'increment': increment,
        'pass': false,
      };
      samples.add(sample);
      final startedAtUtc = DateTime.now().toUtc().toIso8601String();
      sample['releaseStartedAtUtc'] = startedAtUtc;
      final start = clock.elapsedMicroseconds;
      await release(previous);
      Rect? glyph;
      await _until(tester, () {
        glyph = _incrementGlyph(atom.id, increment);
        return glyph != null;
      }, 'increment $increment visible and laid out');
      final observedAt = clock.elapsedMicroseconds;
      sample.addAll({
        'releaseStartMicros': start,
        'observedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'releaseSpacingMicros': previousRelease == null
            ? null
            : start - previousRelease,
        'elapsedMicros': observedAt - start,
        'visibleGlyph': {
          'left': glyph!.left,
          'top': glyph!.top,
          'width': glyph!.width,
          'height': glyph!.height,
        },
      });
      previousRelease = start;
      // Gate reach/diagnostics happen after the measured endpoint.
      await reach(next, () => _incrementGlyph(atom.id, increment) != null);
      final after = _hotUpdateCut();
      sample['after'] = after;
      expect(lease, same(owner));
      expect(lease.controller, same(controller));
      expect(
        after,
        before,
        reason: 'Pure body deltas must not mutate Main/structure/refs',
      );
      expect(
        graph.client.conversations.session(threadId).state.businessRefs,
        refs,
      );
      final current = observed.liveBlocks.single;
      expect(current.id, block.id);
      expect((current.body as SingleDisplayBlock).record.atom.id, atom.id);
      expect(
        (current.body as SingleDisplayBlock).record.atom.source,
        atom.source,
      );
      expect(
        (current.body as SingleDisplayBlock).record.atom.lifecycle,
        isA<ActiveChatAtom>(),
      );
      sample['pass'] = true;
    }
    evidence['after'] = _hotUpdateCut();
    final values =
        samples.map((sample) => sample['elapsedMicros'] as int).toList()
          ..sort();
    expect(values, hasLength(20));
    evidence['summary'] = {
      'sampleCount': values.length,
      'percentileMethod': 'nearest-rank',
      'p95Micros': values[(values.length * 95 + 99) ~/ 100 - 1],
      'maxMicros': values.last,
    };
    await release('hot-20');
    await idle();
    await _until(
      tester,
      () => main.any((unit) => unit.id == block.id),
      'same hot-update Single handed to history after reliable terminal',
    );
  }

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
      await backFromSettings();
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
    final work = observed.liveWork.single;
    final source = member.source;
    expect(source, isA<ForegroundTurnChatSource>());
    final activeTurnId = (source as ForegroundTurnChatSource).turnId;
    expect(member.lifecycle, isA<ActiveChatAtom>());
    expect(member.contents, isNotEmpty);
    final state = graph.client.conversations.session(threadId).state;
    expect(state.activeTurn?.turnId, activeTurnId);
    final originalGroup = before.groupDisplays.singleWhere(
      (display) =>
          display.unitId == work.id &&
          display.blockReference == work.memberReference,
    );
    final originalHead = work.expansion.members!.page!.entries.single;
    expect(originalHead.record.atom.id, member.id);
    final originalCurrent = observed.currentDisplayForWork(work.id);
    expect(originalCurrent.isCurrent, isTrue);
    final historyIds = items.map((item) => item.id).toList();
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
    final summary = member.contents.singleWhere(
      (content) => content.role == ChatContentRole.reasoningSummary,
    );
    final summaryIdentity = contentReferenceIdentity(summary.reference);
    Future<TimelineCurrentWindowDisplay> readableMemberWindow(
      TimelineCurrentDisplay current,
      TimelineGroupDisplay group,
      DisplayMemberHead head,
      String description,
    ) async {
      TimelineCurrentWindowDisplay? observation;
      // Borrow only the renderer's existing watch. A query here could conceal
      // a missing production reference or a renderer that never opens it.
      await _until(tester, () {
        expect(current.isCurrent, isTrue);
        expect(group.isCurrent && group.expanded, isTrue);
        expect(group.unitId, work.id);
        expect(group.blockReference, work.memberReference);
        final row = observed.liveRenderer((
          blockId: work.id,
          displayId: head.memberKey,
          record: head.record,
        ));
        if (row.evaluate().length != 1) return false;
        final renderer = tester.state(row) as TimelineMemberDisplay;
        final windows = renderer.windows
            .where((window) => window.id == head.memberKey)
            .toList();
        for (final window in windows) {
          expect(window.error, isNull);
        }
        if (windows.isEmpty) return false;
        expect(windows, hasLength(1));
        observation = windows.single;
        expect(
          group.windows.where((window) => identical(window, observation)),
          hasLength(1),
        );
        expect(
          current.windows.where((window) => identical(window, observation)),
          hasLength(1),
        );
        expect(
          contentReferenceIdentity(observation!.reference),
          summaryIdentity,
        );
        final window = observation!.window;
        return window != null &&
            utf8
                .decode(window.bytes)
                .contains('梳理 **会话共享组件** 与 `LiveStatusBar` 锁定边界');
      }, description);
      expect(observation!.offset, 0);
      expect(observation!.window!.offset, 0);
      expect(observation!.window!.sealed, isFalse);
      return observation!;
    }

    final originalWindow = await readableMemberWindow(
      originalCurrent,
      originalGroup,
      originalHead,
      'the mounted original member reads the first reasoning delta',
    );
    final originalBody = originalWindow.window!;
    expect(lease, same(before));
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
    expect(originalWindow.window, isNull);
    expect(
      (await graph.client.conversations.retryCleanup(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      )).complete,
      isTrue,
    );
    await backFromSettings();
    await openThread(selectedThread);
    await _until(
      tester,
      () =>
          lease.appliedSets == 1 &&
          observed.liveWork.any(
            (unit) =>
                unit.id == work.id &&
                unit.memberReference == work.memberReference,
          ),
      'fresh Set and the same producer-defined live Work',
    );
    final after = lease;
    expect(
      lease.groupDisplays,
      isEmpty,
      reason: 'A new display lease starts folded, without member demand',
    );
    final resumedGroup = await observed.openWork(work.id);
    await _until(
      tester,
      () => live.any((atom) => atom.id == member.id && atom.source == source),
      'the same live member after explicit Work expansion',
    );
    expect(lease.generation, greaterThan(before.generation));
    final resumedCurrent = observed.currentDisplayForWork(work.id);
    expect(resumedCurrent.turnId, activeTurnId);
    final resumed = live.singleWhere((atom) => atom.id == member.id);
    expect(resumed.kind, member.kind);
    expect(resumed.sourceOrder, member.sourceOrder);
    expect(resumed.lifecycle, isA<ActiveChatAtom>());
    expect(resumed.contents.map(memberBody), orderedEquals(bodyIdentities));
    final resumedHead = observed
        .unit(work.id)
        .expansion
        .members!
        .page!
        .entries
        .single;
    expect(resumedHead.memberKey, originalHead.memberKey);
    expect(resumedHead.memberOrder, originalHead.memberOrder);
    expect(resumedHead.record.atom.id, member.id);
    final resumedWindow = await readableMemberWindow(
      resumedCurrent,
      resumedGroup,
      resumedHead,
      'the newly mounted member reads the same first reasoning delta',
    );
    expect(resumedWindow, isNot(same(originalWindow)));
    expect(
      contentReferenceIdentity(resumedWindow.reference),
      contentReferenceIdentity(originalWindow.reference),
    );
    expect(originalWindow.window, isNull);
    expect(lease, same(after));
    expect(after.appliedSets, 1);
    expect(items.map((item) => item.id), orderedEquals(historyIds));
    expect(items.where((item) => item.atom!.id == member.id), isEmpty);
    expect(main.where((unit) => unit.body is WorkDisplayBlock), isEmpty);
    report['midstreamReopen'] = {
      'gate': 'workgroup',
      'threadId': selectedThread,
      'turnId': activeTurnId,
      'memberId': resumed.id,
      'memberKind': resumed.kind.name,
      'memberKey': resumedHead.memberKey,
      'memberOrder': resumedHead.memberOrder,
      'oldGeneration': before.generation,
      'newGeneration': lease.generation,
      'oldLeaseReleased': before.isReleased,
      'newMainSets': lease.appliedSets,
      'historyItemIds': historyIds,
      'mountedBody': {
        'reference': summaryIdentity.toString(),
        'firstReasoningDeltaVerifiedBeforeAndAfter': true,
        'originalBytes': originalBody.bytes.length,
        'resumedBytes': resumedWindow.window!.bytes.length,
        'originalWindowReleased': originalWindow.window == null,
      },
      'activeContentReferences': [
        for (final content in resumed.contents)
          contentReferenceIdentity(content.reference).toString(),
      ],
    };
    await _record('workgroup-reopened');
    return resumed;
  }

  Future<void> idle() async {
    final currentDisplays = lease.currentDisplays.toList();
    await _until(
      tester,
      () =>
          observed.liveBlocks.isEmpty &&
          find.byKey(StudioDriverKeys.composerStop).evaluate().isEmpty &&
          find
              .byKey(const ValueKey('conversation-activity'))
              .evaluate()
              .isEmpty,
      'idle with no current strip',
    );
    expect(
      find.byType(ConversationCurrentConnector, skipOffstage: false),
      findsNothing,
    );
    expect(lease.currentDisplays, isEmpty);
    for (final current in currentDisplays) {
      expect(current.isCurrent, isFalse);
      expect(current.windows, isEmpty);
    }
  }

  Future<void> showUnit(String id) async {
    final unit = observed.unit(id);
    Finder target = observed.itemRow(id);
    if (unit.body is WorkDisplayBlock) {
      target = observed.groupHeader(id);
    } else if (unit.atom?.kind == ChatAtomKind.compaction) {
      target = find.descendant(
        of: target,
        matching: find.text('已完成压缩', findRichText: true),
      );
    }
    await observed.reveal(target, id);
  }

  Future<void> expand(TimelineDisplayUnit unit) async {
    await observed.openWork(unit.id);
  }

  void _recordMemberInventory(
    String stage,
    String? id, {
    TimelineGroupDisplay? original,
    Object? error,
  }) {
    Map<String, Object?>? reference(DisplayBlockRef? value) => value == null
        ? null
        : {'blockId': value.blockId, 'databaseId': value.databaseId};
    Map<String, Object?> display(TimelineGroupDisplay value) => {
      'unitId': value.unitId,
      'identity': identityHashCode(value),
      'runReference': reference(value.blockReference),
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
    for (final value in lease.groupDisplays) {
      if (id != null && value.unitId != id) continue;
      windows.add(display(value));
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
  Future<List<String>> contentIdentitiesForItem(
    String id, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (timeout <= Duration.zero) {
      fail(
        'Reading original Work member identities requires a positive deadline',
      );
    }
    final clock = Stopwatch()..start();
    Duration remaining() {
      final value = timeout - clock.elapsed;
      if (value <= Duration.zero) {
        fail('Timed out reading original Work member identities $id');
      }
      return value;
    }

    final unit = observed.unit(id);
    if (unit.body is SingleDisplayBlock) {
      expect(unit.id, isNotNull);
      return [unit.atom!.id];
    }
    final reusedWindow = lease.groupDisplays.any(
      (display) =>
          display.unitId == id && display.isCurrent && display.expanded,
    );
    TimelineGroupDisplay? original;
    _recordMemberInventory('before-open', id);
    try {
      final display = await observed.openWork(id, timeout: remaining());
      original = display;
      await observed.selectLatestMembers(display, timeout: remaining());
      final ids = <String>{};
      var olderPageCommands = 0;
      while (true) {
        await _until(
          tester,
          () {
            expect(display.isCurrent, isTrue);
            expect(display.expanded, isTrue);
            if (display.error case final error?) throw error;
            return !display.loading;
          },
          'original group member window is ready',
          timeout: remaining(),
        );
        ids.addAll(display.atoms.map((atom) => atom.id));
        if (display.before == null) break;
        // SDK admission precedes the frame that installs the enabled control.
        // Keep the original window and cursor while waiting for that same UI.
        await observed.loadOlderMemberPage(display, timeout: remaining());
        olderPageCommands++;
      }
      expect(ids, hasLength(unit.summary!.total));
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
        'reachedEarliestMember': true,
      });
      _recordMemberInventory('earliest-member', id, original: display);
      final heads = await observed.readMemberInventory(
        unit,
        expectedCount: unit.summary!.total,
      );
      expect(heads.map((head) => head.record.atom.id).toSet(), ids);
      return heads.map((head) => head.record.atom.id).toList();
    } catch (error) {
      _recordMemberInventory('failed', id, original: original, error: error);
      rethrow;
    }
  }

  Future<void> _closeInventoriedGroup(String id) async {
    if (observed.unit(id).body is SingleDisplayBlock) return;
    final display = lease.groupDisplays.singleWhere(
      (display) => display.unitId == id,
    );
    expect(display.isCurrent, isTrue);
    expect(display.expanded, isTrue);
    expect(display.before, isNull);
    expect(display.loading, isFalse);
    _recordMemberInventory(
      'earliest-member-before-close',
      id,
      original: display,
    );
    await observed.closeWork(display);
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
      'workBlocks': [
        for (final unit in main.where((unit) => unit.body is WorkDisplayBlock))
          {
            'id': unit.id,
            'blockId': unit.memberReference!.blockId,
            'ordinal': unit.summary!.total,
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

  Future<List<_ImageResult>> _imageResults(
    TimelineDisplayUnit unit,
    List<ChatAtom> atoms,
  ) async {
    final source = atoms.first.source as ForegroundTurnChatSource;
    final records = await collectDisplayRecords(
      observed,
      turnId: source.turnId,
    );
    final results = <_ImageResult>[];
    for (final call in [..._imageCalls, 'concept-image-failed']) {
      final starts = records
          .where(
            (entry) =>
                entry.record.atom.source == source &&
                entry.record.atom.tool?.callId == call &&
                entry.record.contentSource is CompletedOriginal,
          )
          .toList();
      if (starts.isEmpty) continue;
      expect(
        starts,
        hasLength(1),
        reason: 'One original foreground receipt per call',
      );
      final receipt = await readDisplayRecord(
        lease,
        starts.single.record,
        displayId: starts.single.member?.memberKey ?? starts.single.unit.id,
      );
      final foreground = receipt.atom!;
      final frontTool = (receipt.toolCard as DecodedToolCard).value;
      ObservedDisplayRecord location = starts.single;
      ChatItemPresentation value = receipt;
      if (foreground.delivery == ChatDeliveryKind.backgroundHandoff) {
        expect(
          (foreground.lifecycle as TerminalChatAtom).outcome,
          ChatTerminalOutcome.transferred,
        );
        expect(frontTool.statusString, 'backgroundStarted');
        expect(frontTool.outcome, isNull);
        expect(frontTool.taskId, isNotEmpty);
        final finals = records
            .where(
              (entry) =>
                  entry.record.atom.source is BackgroundResultChatSource &&
                  entry.record.atom.tool?.callId == call &&
                  entry.record.contentSource is CompletedOriginal,
            )
            .toList();
        if (finals.isEmpty) continue;
        expect(finals, hasLength(1));
        location = finals.single;
        value = await readDisplayRecord(
          lease,
          location.record,
          displayId: location.member?.memberKey ?? location.unit.id,
        );
        expect(value.atom!.source, isA<BackgroundResultChatSource>());
        expect(value.atom!.delivery, ChatDeliveryKind.independent);
        expect(
          (value.toolCard as DecodedToolCard).value.taskId,
          frontTool.taskId,
        );
      } else {
        expect(foreground.delivery, ChatDeliveryKind.foreground);
      }
      final tool = (value.toolCard as DecodedToolCard).value;
      expectImageOriginalOutcome(
        value.atom!,
        failed: call == 'concept-image-failed',
      );
      expect(value.atom!.turnId, source.turnId);
      expect(tool.name, 'view_image');
      expect(tool.toolCallId, call);
      expect(
        tool.outcome,
        call == 'concept-image-failed'
            ? TimelineToolOutcome.failed
            : TimelineToolOutcome.succeeded,
      );
      if (call == 'concept-image-failed') {
        expect(tool.error, contains('image source is not a regular file'));
        expect(value.attachments, isEmpty);
      } else {
        expect(tool.error, isNull);
        expect(value.attachments, hasLength(1));
      }
      results.add((
        foreground: foreground,
        finalUnit: location.unit,
        finalMember: location.member,
        finalAtom: value.atom!,
        presentation: value,
      ));
    }
    return results;
  }

  Future<List<_ImageResult>> _verifyImageMembers(
    TimelineDisplayUnit unit,
    TimelineGroupDisplay display,
  ) async {
    final seed = await observed.readFixtureAtoms(
      unit,
      expectedCount: unit.summary!.total,
    );
    final source = seed.first.source;
    final records = await collectDisplayRecords(observed, source: source);
    final originals = records
        .where((entry) => entry.record.contentSource is CompletedOriginal)
        .toList();
    final atoms = <ChatAtom>[];
    for (final entry in originals) {
      atoms.add((await readDisplayRecord(lease, entry.record)).atom!);
    }
    expect(source, isA<ForegroundTurnChatSource>());
    expect(
      lease.groupDisplays.singleWhere((value) => value.unitId == unit.id),
      same(display),
    );
    expect(display.isCurrent, isTrue);
    expect(display.expanded, isTrue);
    expect(display.blockReference, unit.memberReference);
    expect(display.loading, isFalse);
    expect(display.error, isNull);
    expect(display.atoms, isNotEmpty);
    expect(display.atoms.length, lessThanOrEqualTo(12));
    expect(unit.summary!.total, greaterThanOrEqualTo(1));
    expect(atoms.map((atom) => atom.id).toSet(), hasLength(atoms.length));
    expect(atoms.map((atom) => atom.source).toSet(), {source});
    expect(
      display.atoms.every(
        (member) => records.any(
          (entry) =>
              entry.unit.id == unit.id && entry.record.atom.id == member.id,
        ),
      ),
      isTrue,
    );
    for (final atom in atoms) {
      expect(atom.lifecycle, isA<TerminalChatAtom>());
    }
    final reasoning = atoms.where(
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
    final tools = atoms.where(
      (atom) =>
          atom.kind == ChatAtomKind.toolCall && atom.tool?.name == 'view_image',
    );
    expect(tools, hasLength(_imageCalls.length + 1));
    expect(tools.map((atom) => atom.tool?.callId).toSet(), {
      ..._imageCalls,
      'concept-image-failed',
    });
    final results = await _imageResults(unit, atoms);
    expect(results, hasLength(_imageCalls.length + 1));
    expect(
      atoms.every((atom) => atom.source == source),
      isTrue,
      reason: 'Foreground originals retain their source across display blocks',
    );
    final inventories =
        (report['imageMemberInventories'] ??= <Map<String, Object?>>[])
            as List<Map<String, Object?>>;
    inventories.add({
      'itemId': unit.id,
      'historyPos': unit.historyPos,
      'currentPageCount': display.atoms.length,
      'inventorySource': 'explicit finite fixture queries, not UI accumulation',
      'displayIdentity': identityHashCode(display),
      'blockId': display.blockReference!.blockId,
      'finiteInventoryComplete': true,
      'memberDomain': 'ForegroundMembers',
      'reasoningBodiesVerified': texts.length,
      'members': [
        for (final atom in atoms)
          {
            'id': atom.id,
            'kind': atom.kind.name,
            'sameSource': atom.source == source,
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
            'domain': result.finalMember != null ? 'WorkMember' : 'MainSingle',
            'blockId': result.finalUnit?.id,
            'memberKey': result.finalMember?.memberKey,
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

  Future<void> expectEmptyConversation() async {
    await _until(tester, () => !lease.hasOlder, 'empty conversation EOF');
    expect(lease.controller.messages, isEmpty);
    expect(live, isEmpty);
    // Hidden has no mounted current observer or borrowed content windows.
    // Content or real State notices mount their own observer when needed.
    expect(
      find.byType(ConversationCurrentConnector, skipOffstage: false),
      findsNothing,
    );
    expect(lease.currentDisplays, isEmpty);
    expect(find.byType(ConversationActivityBar), findsNothing);
    expect(find.byType(TimelineActivityRow), findsNothing);
    expect(find.byType(TimelineDisplayUnitView), findsNothing);
    await capture('empty');
  }

  Future<void> journey(String project) async {
    await expectEmptyConversation();
    final evidence = <String, Object?>{};
    report['conversationCredit'] = evidence;
    Future<TimelineFeed>? opening;
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
      expect(main.where((unit) => unit.body is WorkDisplayBlock), isEmpty);
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
          opening = (graph.client.transport as TimelineTransport)
              .openTimelineFeed(
                lease.threadId,
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
      () =>
          observed.liveWork.length == 1 &&
          observed.liveWork.single.summary!.total == 1,
    );
    final initialWork = observed.liveWork.single;
    final g1 = initialWork.id;
    expect(
      lease.groupDisplays,
      isEmpty,
      reason: 'A folded live Work must not open member or body demand',
    );
    final active = (await observed.readMemberPage(initialWork.memberReference!))
        .entries
        .single
        .record
        .atom;
    final source = active.source;
    expect(source, isA<ForegroundTurnChatSource>());
    expect(active.lifecycle, isA<ActiveChatAtom>());
    expect(
      lease.groupDisplays,
      isEmpty,
      reason: 'Explicit provenance inspection must not expand the UI',
    );
    report['initialWorkgroupCollapsed'] = true;
    await capture('workgroup');
    await observed.openWork(g1);
    final reopened = await reopenActiveWorkgroup();
    expect(reopened.id, active.id);
    await capture('workgroup-expanded');
    await release('workgroup');
    await reach(
      'group-idle',
      () => observed.liveWork.any(
        (unit) =>
            unit.id == g1 &&
            unit.summary!.total == 4 &&
            unit.summary!.terminal == 4,
      ),
    );
    final firstWork = observed.unit(g1);
    expect(firstWork.memberReference, initialWork.memberReference);
    final firstMembers = await observed.readFixtureAtoms(
      firstWork,
      expectedCount: 4,
    );
    expect(firstMembers, hasLength(4));
    expect(firstMembers.every((atom) => atom.source == source), isTrue);
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
    // Atomic completions are saved, but a Work without a boundary stays live.
    expect(main.any((unit) => unit.id == g1), isFalse);
    await capture('group-idle');
    // Opt-in acceptance coordination only: keep the existing provider gate
    // closed while an external SQLite backup captures this real open Work.
    // The acknowledgement is written by the observer coordinator, not the UI.
    final seedAckPath =
        Platform.environment['ANYWORK_CONCEPT_COLD_SEED_ACK'] ?? '';
    if (seedAckPath.isNotEmpty) {
      final pause = Stopwatch()..start();
      final acknowledgement = File(seedAckPath);
      while (!acknowledgement.existsSync()) {
        if (pause.elapsed >= const Duration(seconds: 180)) {
          fail('Timed out waiting for verified open Work seed backup: $g1');
        }
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
      final ack = jsonDecode(acknowledgement.readAsStringSync());
      expect(ack, isA<Map<String, dynamic>>());
      expect(ack['pass'], isTrue);
      expect(ack['openWorkBlockIds'], contains(g1));
      report['coldSeedCheckpoint'] = {
        'blockId': g1,
        'pauseMillis': pause.elapsedMilliseconds,
        'excludedFromLatencySamples': true,
      };
    }
    await release('group-idle');
    await reach(
      'text',
      () =>
          live.any((atom) => atom.kind == ChatAtomKind.text) && hasText(_textA),
    );
    final a = live.singleWhere((atom) => atom.kind == ChatAtomKind.text);
    _expectCurrentTextSurface(a, _textA);
    final frozenFirst = observed.unit(g1);
    expect(frozenFirst.historyPos, greaterThan(0));
    expect(frozenFirst.memberReference, firstWork.memberReference);
    expect(observed.liveBlocks.any((block) => block.id == g1), isFalse);
    expect(a.lifecycle, isA<ActiveChatAtom>());
    expect(a.contents, isNotEmpty);
    expect(items.where((entry) => entry.atom!.id == a.id), isEmpty);
    await capture('text');
    await release('text');
    await reach(
      'after-text',
      () =>
          observed.liveBlocks.isEmpty &&
          items.any((entry) => entry.atom!.id == a.id) &&
          graph.client.conversations.session(threadId).state.activity?.kind !=
              ThreadActivityKind.responding,
    );
    final aEntry = items.singleWhere((entry) => entry.atom!.id == a.id);
    expect(aEntry.body, isA<SingleDisplayBlock>());
    expect(find.byKey(const ValueKey('conversation-activity')), findsOneWidget);
    _expectNoRespondingNotice(a.turnId!);
    await capture('after-text');
    await release('after-text');
    await reach(
      'next-group',
      () => observed.liveWork.any((unit) => unit.id != g1),
    );
    final secondWork = observed.liveWork.single;
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TimelineMemberAtom &&
            widget.atom.id == a.id &&
            widget.atom.lifecycle is ActiveChatAtom,
      ),
      findsNothing,
    );
    _expectNoRespondingNotice(a.turnId!);
    final g2 = secondWork.id;
    expect(g2, isNot(g1));
    expect(secondWork.memberReference, isNot(firstWork.memberReference));
    expect(
      (await observed.readMemberPage(secondWork.memberReference!))
          .entries
          .single
          .record
          .atom
          .source,
      source,
    );
    await capture('next-group-collapsed');
    await observed.openWork(g2);
    expect(observed.unit(g1).body, same(frozenFirst.body));
    await capture('next-group');
    await release('next-group');
    await reach(
      'second-group-idle',
      () => observed.liveWork.any(
        (unit) =>
            unit.id == g2 && unit.summary!.terminal == unit.summary!.total,
      ),
    );
    expect(main.any((unit) => unit.id == g2), isFalse);
    await observed.closeWork(
      lease.groupDisplays.singleWhere((d) => d.unitId == g2),
    );
    await capture('group-idle-collapsed');
    final credit = await openCredit();
    await release('second-group-idle');
    await reach(
      'second-text',
      () =>
          live.any((atom) => atom.kind == ChatAtomKind.text) && hasText(_textB),
    );
    final b = live.singleWhere((atom) => atom.kind == ChatAtomKind.text);
    _expectCurrentTextSurface(b, _textB);
    expect(observed.unit(g2).historyPos, greaterThan(aEntry.historyPos!));
    expect(observed.unit(g2).memberReference, secondWork.memberReference);
    await release('second-text');
    await reach(
      'before-turn-end',
      () =>
          observed.liveBlocks.isEmpty &&
          items.any((entry) => entry.atom!.id == b.id),
    );
    final completedTextB = items.singleWhere((entry) => entry.atom!.id == b.id);
    final coreIds = {g1, aEntry.id, g2, completedTextB.id};
    final core = main.where((unit) => coreIds.contains(unit.id)).toList();
    expect(
      core.map((unit) => unit.id),
      orderedEquals([g1, aEntry.id, g2, completedTextB.id]),
    );
    for (var i = 1; i < core.length; i++) {
      expect(core[i].historyPos!, greaterThan(core[i - 1].historyPos!));
    }
    await _creditAsync(() async {
      await credit.queryCompletedText(
        blockId: completedTextB.id,
        historyPos: completedTextB.historyPos!,
        single: completedTextB.body as SingleDisplayBlock,
      );
      await credit.observeSuccessors(
        blockId: completedTextB.id,
        historyPos: completedTextB.historyPos!,
      );
      await credit.verifyClosed(
        completedOriginalId(
          (completedTextB.body as SingleDisplayBlock).record,
        )!,
      );
    });
    await release('before-turn-end');
    await idle();
    await _until(tester, () {
      final turn = graph.client.conversations.session(threadId).state.lastTurn;
      return turn?.turnId == completedTextB.atom!.turnId &&
          turn?.state.status == StudioTurnStatus.completed;
    }, 'the original successful Turn reaches typed terminal state');
    expect(
      items.where(
        (entry) =>
            entry.atom!.source == source &&
            entry.atom!.kind == ChatAtomKind.turnReceipt,
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
    await observed.revealMember(reason, reference: firstGroup.memberReference!);
    final reasoningBody = find.descendant(
      of: observed.memberRow(reason.id),
      matching: find.text('梳理 会话共享组件 与 LiveStatusBar 锁定边界', findRichText: true),
    );
    await _until(
      tester,
      () => reasoningBody.evaluate().length == 1,
      'reasoning body on original Work expansion',
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
      final imageClock = Stopwatch()..start();
      while (true) {
        final records = await collectDisplayRecords(observed);
        final calls = records
            .where(
              (entry) =>
                  entry.record.atom.source is ForegroundTurnChatSource &&
                  entry.record.atom.tool?.callId == _imageCalls.first &&
                  entry.record.contentSource is CompletedOriginal,
            )
            .toList();
        expect(calls.length, lessThanOrEqualTo(1));
        if (calls.isNotEmpty) {
          final source = calls.single.record.atom.source;
          final originals = records
              .where(
                (entry) =>
                    entry.record.atom.source == source &&
                    entry.record.contentSource is CompletedOriginal,
              )
              .toList();
          final reasoning = originals
              .where(
                (entry) => entry.record.atom.kind == ChatAtomKind.reasoning,
              )
              .toList();
          final images = originals
              .where((entry) => entry.record.atom.tool?.name == 'view_image')
              .toList();
          if (reasoning.length == _imageReasoningCount &&
              images.length == _imageCalls.length + 1) {
            imageWork = reasoning.first.unit;
            expect(imageWork.memberReference, isNotNull);
            break;
          }
        }
        if (imageClock.elapsed >= const Duration(seconds: 60)) {
          fail(
            'Image turn did not expose all 40 reasoning and 4 image originals',
          );
        }
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      report['imageWorkItemId'] = imageWork.id;
      imageDisplay = await observed.openWork(imageWork.id);
      await contentIdentitiesForItem(imageWork.id);
      await _awaitImageResults(imageWork, imageDisplay);
      await _verifyImageMembers(imageWork, imageDisplay);
      await _record('images-ready');
    } catch (error) {
      _recordImageFailure('images-ready', error, original: imageDisplay);
      rethrow;
    }
    await capture('images-live');
    await release('images-ready');
    await showImageContinuation(imageWork);
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
      () => items.any((entry) => entry.atom!.id == partialAtom),
      'failed partial retained',
    );
    final partial = items.singleWhere((entry) => entry.atom!.id == partialAtom);
    bool failedReceipt(TimelineDisplayUnit entry) =>
        entry.atom!.kind == ChatAtomKind.turnReceipt &&
        entry.atom!.source == partial.atom!.source &&
        entry.atom!.lifecycle is TerminalChatAtom &&
        (entry.atom!.lifecycle as TerminalChatAtom).outcome ==
            ChatTerminalOutcome.failed;
    await _until(
      tester,
      () => items.any(failedReceipt),
      'independent failed Turn receipt',
    );
    final failure = items.lastWhere(failedReceipt);
    expect(failure.id, isNot(partial.id));
    await showUnit(partial.id);
    await _until(
      tester,
      () => hasText(_partial),
      'failed partial still readable',
    );
    await showUnit(failure.id);
    final renderedFailure = await waitForTimelineConceptSingle(tester, failure);
    expect((renderedFailure.data['outcome'] as Map)['kind'], 'failed');
    await tap(
      find.descendant(
        of: itemFinder(failure.id),
        matching: find.byType(TimelineActivityDisclosure),
      ),
    );
    await _until(
      tester,
      () => hasText('concept provider permanent failure'),
      'independent provider failure reason',
    );
    await capture('failed');
    report['partialItemId'] = partial.id;
    report['failureItemId'] = failure.id;
    await overlap();
    await emptyText();
    await hotUpdateSamples();
    await idle();
    await capture('idle');
    await _record('journey-complete');
    report['coreMemberCounts'] = [firstMembers.length, 1];
    report['independentScenarioCoverage'] = {
      'questionsAndReceipts': 'question-history (separate strict provider)',
      'normalStopContinue': 'realtime-presentation (separate strict provider)',
    };
  }

  void _expectNoRespondingNotice(String turnId) {
    final notices = tester.widgetList<ConversationRealtimeNotices>(
      find.byType(ConversationRealtimeNotices),
    );
    expect(
      notices
          .expand((widget) => widget.notices)
          .whereType<ExecutionLiveNotice>()
          .where(
            (notice) =>
                notice.view.turnId == turnId &&
                notice.view.kind == ConversationActivityKind.responding,
          ),
      isEmpty,
      reason:
          'A rendered body or subsequent thinking has no stale output label',
    );
  }

  void _expectCurrentTextSurface(ChatAtom atom, String text) {
    final row = find.byWidgetPredicate(
      (widget) =>
          widget is TimelineMemberAtom &&
          widget.atom.id == atom.id &&
          widget.atom.lifecycle is ActiveChatAtom,
    );
    expect(row, findsOneWidget);
    final body = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) => widget is TimelineMarkdown && widget.text == text,
      ),
    );
    expect(
      body,
      findsOneWidget,
      reason: 'Ordinary current text has exactly one real body renderer',
    );
    for (final window in tester.widgetList<ConversationCurrentWindowView>(
      find.descendant(
        of: row,
        matching: find.byType(ConversationCurrentWindowView),
      ),
    )) {
      expect(window.label, isNull);
    }
    _expectNoRespondingNotice(atom.turnId!);
  }

  Future<void> showImageContinuation(TimelineDisplayUnit imageWork) async {
    final owner = lease;
    final source = (await observed.readFixtureAtoms(
      imageWork,
      expectedCount: imageWork.summary!.total,
    )).firstWhere((atom) => atom.source is ForegroundTurnChatSource).source;
    expect(source, isA<ForegroundTurnChatSource>());
    final turnId = (source as ForegroundTurnChatSource).turnId;
    final observation = <String, Object?>{
      'turnId': turnId,
      'sourceType': source.runtimeType.toString(),
      'mainAdmitted': false,
      'bodyVerified': false,
      'visible': false,
    };
    report['imageContinuation'] = observation;
    var phase = 'idle';
    Iterable<TimelineDisplayUnit> candidates() => items.where(
      (entry) =>
          entry.body is SingleDisplayBlock &&
          entry.atom!.source == source &&
          entry.atom!.turnId == turnId &&
          entry.atom!.kind == ChatAtomKind.text &&
          entry.atom!.textChannel == ThreadTextChannel.finalAnswer &&
          entry.atom!.lifecycle is TerminalChatAtom &&
          (entry.atom!.lifecycle as TerminalChatAtom).outcome ==
              ChatTerminalOutcome.completed,
    );
    try {
      await idle();
      final clock = Stopwatch()..start();
      Duration remaining() {
        final value = const Duration(seconds: 60) - clock.elapsed;
        if (value <= Duration.zero) {
          fail(
            'Timed out waiting for real image continuation answer at $phase',
          );
        }
        return value;
      }

      phase = 'Main admission';
      TimelineDisplayUnit? admitted;
      await _until(
        tester,
        () {
          expect(lease, same(owner));
          final matches = candidates().toList();
          expect(matches.length, lessThanOrEqualTo(1));
          admitted = matches.singleOrNull;
          return admitted != null;
        },
        'real image continuation completion in Main',
        timeout: remaining(),
      );
      final entry = admitted!;
      observation.addAll({
        'mainAdmitted': true,
        'blockId': entry.id,
        'recordId': completedOriginalId(
          (entry.body as SingleDisplayBlock).record,
        ),
        'historyPos': entry.historyPos,
        'completionSeq': entry.atom!.completionSeq,
        'atomId': entry.atom!.id,
        'mainPayloadType': entry.atom!.payload.runtimeType.toString(),
      });
      phase = 'completed body';
      var readableAtom = entry.atom!;
      if (entry.atom!.payload is DeferredPayload) {
        final scope = owner.content.openScope(generation: owner.generation);
        try {
          final readable = await scope
              .readCompleted(
                recordId: completedOriginalId(
                  (entry.body as SingleDisplayBlock).record,
                )!,
                demand: const ReadDemand(maxItems: 1, maxBytes: 64 * 1024),
              )
              .timeout(remaining());
          expect(
            readable.recordId,
            completedOriginalId((entry.body as SingleDisplayBlock).record),
          );
          expect(readable.completionSeq, entry.atom!.completionSeq);
          expect(readable.atom.id, entry.atom!.id);
          expect(readable.atom.source, source);
          expect(readable.atom.kind, entry.atom!.kind);
          expect(readable.atom.completionItemId, readable.recordId);
          expect(readable.atom.completionSeq, readable.completionSeq);
          final expectedLifecycle = entry.atom!.lifecycle as TerminalChatAtom;
          // Separate wire reads produce separate lifecycle objects. Compare
          // every terminal fact rather than requiring Dart object identity.
          expect(
            readable.atom.lifecycle,
            isA<TerminalChatAtom>()
                .having(
                  (value) => value.started?.effectSeq,
                  'started.effectSeq',
                  expectedLifecycle.started?.effectSeq,
                )
                .having(
                  (value) => value.started?.suborder,
                  'started.suborder',
                  expectedLifecycle.started?.suborder,
                )
                .having(
                  (value) => value.ended?.effectSeq,
                  'ended.effectSeq',
                  expectedLifecycle.ended?.effectSeq,
                )
                .having(
                  (value) => value.ended?.suborder,
                  'ended.suborder',
                  expectedLifecycle.ended?.suborder,
                )
                .having(
                  (value) => value.outcome,
                  'outcome',
                  expectedLifecycle.outcome,
                ),
          );
          expect(readable.atom.payload, isA<InlinePayload>());
          expect(
            (readable.atom.payload as InlinePayload).bytes.length,
            lessThanOrEqualTo(64 * 1024),
          );
          readableAtom = readable.atom;
        } finally {
          scope.retire();
          expect(
            (await scope.close(
              deadline: DateTime.now().add(const Duration(seconds: 5)),
            )).complete,
            isTrue,
          );
        }
      }
      final value = ChatItemPresentation.decode(readableAtom);
      expect(value.compatibility, ChatItemCompatibility.current);
      expect(value.type, 'text');
      expect(
        value.bodies.any((body) => value.inlineText(body.key) == _imageDone),
        isTrue,
        reason: 'The original Main completion must own the expected answer',
      );
      observation['bodyVerified'] = true;
      phase = 'Main reveal';
      await observed.revealSingle(entry, timeout: remaining());
      expect(lease, same(owner));
      expect(observed.unit(entry.id), same(entry));
      phase = 'visible text';
      await _until(
        tester,
        () => hasText(_imageDone),
        'real image continuation answer',
        timeout: remaining(),
      );
      expect(
        find.descendant(
          of: observed.itemRow(entry.id),
          matching: find.textContaining(_imageDone, findRichText: true),
        ),
        findsWidgets,
      );
      observation['visible'] = true;
    } catch (error, stack) {
      observation['failedPhase'] = phase;
      report['stageFailure'] = _stageFailure('images-ready', error, stack)
        ..addAll({
          'gateReleased': true,
          'waitPhase': phase,
          'mainAnswerCandidates': [
            for (final entry in candidates().take(8))
              {
                'blockId': entry.id,
                'recordId': completedOriginalId(
                  (entry.body as SingleDisplayBlock).record,
                ),
                'historyPos': entry.historyPos,
                'completionSeq': entry.atom!.completionSeq,
                'atomId': entry.atom!.id,
                'payloadType': entry.atom!.payload.runtimeType.toString(),
              },
          ],
        });
      rethrow;
    }
  }

  Future<void> _awaitImageResults(
    TimelineDisplayUnit unit,
    TimelineGroupDisplay display, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (timeout <= Duration.zero) {
      fail('Waiting for final image results requires a positive deadline');
    }
    final clock = Stopwatch()..start();
    Duration remaining() {
      final value = timeout - clock.elapsed;
      if (value <= Duration.zero) {
        fail('Timed out waiting for all exact final image results');
      }
      return value;
    }

    final atoms = await observed.readFixtureAtoms(
      unit,
      expectedCount: unit.summary!.total,
    );
    while (true) {
      remaining();
      expect(display.blockReference, unit.memberReference);
      final results = await _imageResults(unit, atoms);
      remaining();
      if (results.length == _imageCalls.length + 1) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
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
    expect(
      items.where((entry) => entry.atom!.source == active.source),
      isEmpty,
    );
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
    expect(row.indicatorStyle, TimelineActivityIndicatorStyle.compactingZip);
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
    await _until(
      tester,
      () =>
          find.byKey(StudioDriverKeys.contextUsageDetail()).evaluate().isEmpty,
      'context usage tooltip dismissed',
    );
    await capture('compacting');
    await release('compacting');
    await _until(
      tester,
      () => items.any(
        (entry) =>
            entry.atom!.source == active.source &&
            entry.atom!.kind == ChatAtomKind.compaction,
      ),
      'real completed compaction receipt',
    );
    await idle();
    final receipt = items.singleWhere(
      (entry) =>
          entry.atom!.source == active.source &&
          entry.atom!.kind == ChatAtomKind.compaction,
    );
    expect(receipt.body, isA<SingleDisplayBlock>());
    expect(
      (receipt.atom!.lifecycle as TerminalChatAtom).outcome,
      ChatTerminalOutcome.completed,
    );
    report['compactionItemId'] = receipt.id;
    await showUnit(receipt.id);
    final completedRows = find.descendant(
      of: itemFinder(receipt.id),
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

  Future<List<CompletedEntry>> _readOverlapOriginals(
    List<DisplayMemberHead> heads,
    TimelineDisplayUnit text,
  ) async {
    expect(heads, hasLength(2));
    expect(heads.first.memberKey, isNot(heads.last.memberKey));
    expect(heads.first.record.startFact, isNull);
    expect(heads.first.record.endFact, isNotNull);
    final scope = lease.content.openScope(generation: lease.generation);
    try {
      final originals = <CompletedEntry>[];
      for (final head in heads) {
        expect(completedOriginalId(head.record), isNotNull);
        final original = await scope.readCompleted(
          recordId: completedOriginalId(head.record)!,
          demand: const ReadDemand(maxItems: 1, maxBytes: 64 * 1024),
        );
        expect(original.recordId, completedOriginalId(head.record));
        expect(original.atom.id, head.record.atom.id);
        expect(original.atom.source, head.record.atom.source);
        expect(original.completionSeq, head.record.atom.completionSeq);
        expect(
          (original.atom.lifecycle as TerminalChatAtom).outcome,
          ChatTerminalOutcome.completed,
        );
        originals.add(original);
      }
      final body = text.body as SingleDisplayBlock;
      final original = await scope.readCompleted(
        recordId: completedOriginalId(body.record)!,
        demand: const ReadDemand(maxItems: 1, maxBytes: 64 * 1024),
      );
      expect(original.recordId, completedOriginalId(body.record));
      expect(original.atom.id, body.record.atom.id);
      expect(original.atom.source, heads.first.record.atom.source);
      expect(original.completionSeq, body.record.atom.completionSeq);
      expect(original.atom.completionItemId, original.recordId);
      expect(original.atom.completionSeq, original.completionSeq);
      expect(original.atom.lifecycle, isA<TerminalChatAtom>());
      originals.add(original);
      // Start/member order is A -> B; atomic completion order is B -> T -> A.
      expect(originals[1].completionSeq, lessThan(originals[2].completionSeq));
      expect(originals[2].completionSeq, lessThan(originals[0].completionSeq));
      return originals;
    } finally {
      scope.retire();
      expect((await scope.close()).complete, isTrue);
    }
  }

  Future<Map<String, Object?>> _overlapFrozenCut(
    TimelineDisplayUnit work,
  ) async {
    expect(work.state, DisplayBlockState.sealed);
    expect(work.historyPos, greaterThan(0));
    final page = await observed.readMemberPage(
      work.memberReference!,
      demand: const ReadDemand(maxItems: 12, maxBytes: 64 * 1024),
    );
    expect(page.sealed, isTrue);
    expect(page.before, isNull);
    expect(page.entries, hasLength(2));
    final summary = work.summary!;
    final bodies = <List<String>>[];
    for (final head in page.entries) {
      final value = await readDisplayRecord(lease, head.record);
      bodies.add(await displayBodyTexts(lease, value));
    }
    expect(page.entries.first.record.contentSource, isA<FrozenObservation>());
    expect(page.entries.first.record.atom.lifecycle, isA<ActiveChatAtom>());
    expect(page.entries.first.record.startFact, isNotNull);
    expect(page.entries.first.record.endFact, isNull);
    expect(page.entries.last.record.contentSource, isA<CompletedOriginal>());
    expect(bodies.first, contains(_overlapReasoning));
    expect(bodies.last, contains(_overlapEarlyReasoning));
    return {
      'rowId': work.id,
      'historyPos': work.historyPos,
      'state': work.state.name,
      'members': {
        'databaseId': work.memberReference!.databaseId,
        'blockId': work.memberReference!.blockId,
      },
      'summary': workSummaryEvidence(summary),
      'heads': [
        for (final head in page.entries)
          {
            'memberKey': head.memberKey,
            'order': head.memberOrder,
            ...displayRecordEvidence(head.record),
          },
      ],
      'bodies': bodies,
    };
  }

  Future<void> overlap() async {
    await submit(_overlapPrompt);
    await reach(
      'a07-reasoning-start',
      () =>
          observed.liveWork.length == 1 &&
          observed.liveWork.single.summary!.total == 1,
    );
    final work = observed.liveWork.single;
    final ref = work.memberReference!;
    final reasonHead = (await observed.readMemberPage(ref)).entries.single;
    final reason = reasonHead.record.atom;
    final source = reason.source as ForegroundTurnChatSource;
    final owner = lease;
    final current = observed.currentDisplayForWork(work.id);
    final controller = lease.controller;
    final generation = lease.generation;
    expect(reason.lifecycle, isA<ActiveChatAtom>());
    await observed.revealMember(reason, reference: ref);
    await _until(
      tester,
      () => hasText(_overlapReasoning),
      'A original active prefix is readable before B starts',
    );
    await release('a07-reasoning-start');
    await reach(
      'a07-b-terminal',
      () => observed.liveWork.any(
        (unit) =>
            unit.id == work.id &&
            unit.summary!.total == 2 &&
            unit.summary!.terminal == 1,
      ),
    );
    final earlyHeads = await observed.readMemberInventory(
      observed.unit(work.id),
      expectedCount: 2,
    );
    final early = earlyHeads.last;
    expect(early.record.atom.id, isNot(reason.id));
    expect(early.record.contentSource, isA<CompletedOriginal>());
    await observed.revealMember(early.record.atom, reference: ref);
    await _until(
      tester,
      () => hasText(_overlapEarlyReasoning),
      'B original body before text',
    );
    await captureAccessibleVariants('a07-b-terminal', workBlockId: work.id);
    await observed.closeWork(
      lease.groupDisplays.singleWhere((d) => d.unitId == work.id),
    );
    await release('a07-b-terminal');
    await reach(
      'a07-text-start',
      () => main.any((unit) => unit.id == work.id) && hasText('正文已经开始且可以读取，'),
    );
    final frozen = observed.unit(work.id);
    expect(frozen.memberReference, ref);
    expect(
      observed.liveBlocks.any((block) => block.id == work.id),
      isFalse,
      reason: 'Text Started freezes the old Work immediately; it is not footer work',
    );
    final textBlock = observed.liveBlocks.singleWhere(
      (block) => block.body is SingleDisplayBlock,
    );
    final text = (textBlock.body as SingleDisplayBlock).record.atom;
    expect(text.lifecycle, isA<ActiveChatAtom>());
    final frozenCut = await _overlapFrozenCut(frozen);
    Future<void> unchanged() async {
      expect(lease, same(owner));
      expect(lease.controller, same(controller));
      expect(lease.generation, generation);
      expect(await _overlapFrozenCut(observed.unit(work.id)), frozenCut);
    }

    await observed.revealMember(reason, reference: ref);
    await _until(
      tester,
      () => hasText(_overlapReasoning),
      'sealed A prefix remains readable',
    );
    await capture('a07-sealed-work-active-text');
    await release('a07-text-start');
    await reach('a07-text-readable', () => hasText(_overlapText));
    await unchanged();
    await captureAccessibleVariants(
      'a07-text-readable',
      workBlockId: work.id,
      streamingAtomId: text.id,
    );
    await observed.closeWork(
      lease.groupDisplays.singleWhere((d) => d.unitId == work.id),
    );
    await release('a07-text-readable');
    await reach(
      'a07-text-terminal',
      () => items.any((unit) => unit.atom!.id == text.id),
    );
    await unchanged();
    final completedText = items.singleWhere((unit) => unit.atom!.id == text.id);
    expect(frozen.historyPos!, lessThan(completedText.historyPos!));
    expect(
      observed.liveBlocks.any((block) => block.id == textBlock.id),
      isFalse,
    );
    await capture('a07-text-complete-frozen-prefix');
    await release('a07-text-terminal');
    await fixtureGate(tester, provider, 'a07-reasoning-terminal');
    final lateClock = Stopwatch()..start();
    late ObservedDisplayRecord lateEnd;
    while (true) {
      final records = await collectDisplayRecords(observed, source: source);
      final lateEnds = records
          .where(
            (entry) =>
                entry.unit.id != work.id &&
                entry.record.atom.id == reason.id &&
                entry.record.contentSource is CompletedOriginal,
          )
          .toList();
      expect(lateEnds.length, lessThanOrEqualTo(1));
      if (lateEnds.isNotEmpty) {
        lateEnd = lateEnds.single;
        break;
      }
      if (lateClock.elapsed >= const Duration(seconds: 60)) {
        fail('A terminal was not admitted as a new end record');
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    expect(lateEnd.member, isNotNull);
    expect(lateEnd.member!.memberKey, isNot(reasonHead.memberKey));
    expect(lateEnd.record.startFact, isNull);
    expect(lateEnd.record.endFact, isNotNull);
    expect(lateEnd.record.atom.lifecycle, isA<TerminalChatAtom>());
    await unchanged();
    final originals = await _readOverlapOriginals([
      lateEnd.member!,
      early,
    ], completedText);
    expect(originals[1].completionSeq, lessThan(originals[2].completionSeq));
    expect(originals[2].completionSeq, lessThan(originals[0].completionSeq));
    try {
      await observed.revealMember(
        lateEnd.record.atom,
        reference: lateEnd.unit.memberReference!,
      );
    } catch (error, stack) {
      // Capture the failing cut synchronously, before teardown or another pump.
      // This borrows existing resources only and does not expose member bodies.
      final failure = <String, Object?>{
        'stage': 'a07-reasoning-terminal-header',
        'exceptionType': error.runtimeType.toString(),
        'stack': stack.toString(),
      };
      report['lateEndFailure'] = failure;
      try {
        final id = lateEnd.unit.id;
        Map<String, Object?> unitCut(TimelineDisplayUnit unit) => {
          'id': unit.id,
          'historyPos': unit.historyPos,
          'memberBlockId': unit.memberReference?.blockId,
          'memberDatabaseId': unit.memberReference?.databaseId,
        };
        Map<String, Object?> elementCut(Element element) {
          final render = element.findRenderObject();
          final box = render is RenderBox && render.attached && render.hasSize
              ? render
              : null;
          final bounds = box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size;
          return {
            'mounted': element.mounted,
            'attached': render?.attached,
            'bounds': bounds == null
                ? null
                : [bounds.left, bounds.top, bounds.right, bounds.bottom],
            if (element.widget case TimelineDisplayUnitView(:final unit))
              'unit': unitCut(unit),
          };
        }

        failure.addAll({
          ..._stageFailure('a07-reasoning-terminal-header', error, stack),
          'target': unitCut(lateEnd.unit),
          'mainMatches': [
            for (final unit in main.where((unit) => unit.id == id))
              unitCut(unit),
          ],
          'headerOnstage': observed.groupHeader(id).evaluate().length,
          'headerAll': observed
              .groupHeader(id, skipOffstage: false)
              .evaluate()
              .map(elementCut)
              .toList(),
          'rowsAll': observed
              .groupRow(id, skipOffstage: false)
              .evaluate()
              .map(elementCut)
              .toList(),
          'scrollPositions': [
            for (final position in lease.scrollController.positions)
              {
                'pixels': position.hasPixels ? position.pixels : null,
                'min': position.hasContentDimensions
                    ? position.minScrollExtent
                    : null,
                'max': position.hasContentDimensions
                    ? position.maxScrollExtent
                    : null,
                'viewport': position.hasViewportDimension
                    ? position.viewportDimension
                    : null,
              },
          ],
          'workParents': [
            for (final parent
                in find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is ConversationCurrentConnector &&
                          widget.section == ConversationLiveSection.work &&
                          identical(widget.content, lease.content),
                      skipOffstage: false,
                    )
                    .evaluate())
              {
                ...elementCut(parent),
                'eligible': (parent.widget as ConversationCurrentConnector)
                    .isDisplayActive(),
                'selectedWorkRows': [
                  for (final row
                      in find
                          .descendant(
                            of: find.byElementPredicate(
                              (element) => identical(element, parent),
                              skipOffstage: false,
                            ),
                            matching: find.byType(
                              TimelineDisplayUnitView,
                              skipOffstage: false,
                            ),
                            skipOffstage: false,
                          )
                          .evaluate()
                          .take(16))
                    elementCut(row),
                ],
                'latestControlCount': find
                    .descendant(
                      of: find.byElementPredicate(
                        (element) => identical(element, parent),
                        skipOffstage: false,
                      ),
                      matching: find.text('最新实时片段', skipOffstage: false),
                      skipOffstage: false,
                    )
                    .evaluate()
                    .length,
              },
          ],
        });
      } catch (diagnosticError) {
        failure['diagnosticErrorType'] = diagnosticError.runtimeType.toString();
      }
      rethrow;
    }
    await _until(
      tester,
      () => hasText(_overlapReasoning),
      'new real A terminal body',
    );
    await capture('a07-late-end-new-work');
    await observed.closeWork(
      lease.groupDisplays.singleWhere((d) => d.unitId == lateEnd.unit.id),
    );
    await release('a07-reasoning-terminal');
    await idle();
    await unchanged();
    final endUnit = observed.unit(lateEnd.unit.id);
    expect(endUnit.historyPos, greaterThan(completedText.historyPos!));
    final handoff = <String, Object?>{
      'sourceTurnId': source.turnId,
      'frozenCut': frozenCut,
      'oldWorkId': work.id,
      'textRowId': completedText.id,
      'endWorkId': endUnit.id,
      'lateMemberKey': lateEnd.member!.memberKey,
      'reasonId': reason.id,
      'earlyReasonId': early.record.atom.id,
      'completionOrder': [
        originals[1].recordId,
        originals[2].recordId,
        originals[0].recordId,
      ],
      'completionSeqs': [
        originals[1].completionSeq,
        originals[2].completionSeq,
        originals[0].completionSeq,
      ],
    };
    report['overlapAtomIds'] = [reason.id, early.record.atom.id];
    report['a07Handoff'] = handoff;
    await tap(find.byKey(StudioDriverKeys.settingsOpen));
    await _until(
      tester,
      () => owner.isRetired && owner.isReleased,
      'original A07 lease and queries released',
    );
    await owner.released;
    expect(owner.queryCleanupError, isNull);
    expect(current.isCurrent, isFalse);
    expect(current.windows, isEmpty);
    await backFromSettings();
    await openThread(threadId);
    expect(lease, isNot(same(owner)));
    expect(lease.generation, greaterThan(generation));
    await verifyOverlapHistory(handoff);
    await _record('a07-sealed-history-reopened');
  }

  Future<void> verifyOverlapHistory(Map<String, dynamic> saved) async {
    final oldId = saved['oldWorkId'] as String;
    final textId = saved['textRowId'] as String;
    final endId = saved['endWorkId'] as String;
    await _admitSavedMain({oldId, textId, endId});
    final old = observed.unit(oldId);
    expect(await _overlapFrozenCut(old), saved['frozenCut']);
    final frozenHeads = await observed.readMemberInventory(
      old,
      expectedCount: 2,
    );
    await observed.revealMember(
      frozenHeads.first.record.atom,
      reference: old.memberReference!,
    );
    await _until(
      tester,
      () => hasText(_overlapReasoning),
      'reopened frozen A prefix',
    );
    await observed.closeWork(
      lease.groupDisplays.singleWhere((d) => d.unitId == oldId),
    );
    final ends = await observed.readMemberInventory(
      observed.unit(endId),
      expectedCount: observed.unit(endId).summary!.total,
    );
    final end = ends.singleWhere(
      (head) => head.memberKey == saved['lateMemberKey'],
    );
    expect(end.record.startFact, isNull);
    expect(end.record.endFact, isNotNull);
    expect(end.memberKey, isNot(frozenHeads.first.memberKey));
    final originals = await _readOverlapOriginals([
      end,
      frozenHeads.last,
    ], observed.unit(textId));
    expect([
      originals[1].recordId,
      originals[2].recordId,
      originals[0].recordId,
    ], saved['completionOrder']);
    expect([
      originals[1].completionSeq,
      originals[2].completionSeq,
      originals[0].completionSeq,
    ], saved['completionSeqs']);
    final endDisplay = await observed.revealMember(
      end.record.atom,
      reference: observed.unit(endId).memberReference!,
    );
    await _until(
      tester,
      () => hasText(_overlapReasoning),
      'reopened late A original body',
    );
    await observed.closeWork(endDisplay);
    await observed.revealSingle(observed.unit(textId));
    await _until(
      tester,
      () => hasText(_overlapText),
      'reopened actual A07 answer',
    );
  }

  Future<void> emptyText() async {
    await submit(_emptyTextPrompt);
    Iterable<LiveDisplayBlock> liveWork() =>
        lease.live.value?.blocks.where(
          (block) => block.body is WorkDisplayBlock,
        ) ??
        const [];
    Iterable<ChatAtom> liveText() =>
        lease.live.value?.blocks
            .map((block) => block.body)
            .whereType<SingleDisplayBlock>()
            .map((body) => body.record.atom)
            .where((atom) => atom.kind == ChatAtomKind.text) ??
        const [];
    await reach('a14-before-empty', () {
      final turn = graph.client.conversations
          .session(threadId)
          .state
          .activeTurn;
      if (turn == null) return false;
      return liveWork().any((block) {
        final summary = (block.body as WorkDisplayBlock).summary;
        return summary.total == 1 && summary.terminal == 1;
      });
    });
    final source = ForegroundTurnChatSource(
      turnId: graph.client.conversations
          .session(threadId)
          .state
          .activeTurn!
          .turnId,
    );
    final before = liveWork().single;
    final beforeBody = before.body as WorkDisplayBlock;
    expect(beforeBody.summary.total, 1);
    expect(
      main.where((unit) => unit.id == before.id),
      isEmpty,
      reason: 'Completed members wait in live until the real text boundary',
    );
    await release('a14-before-empty');
    await reach(
      'a14-empty-start',
      () => liveText().isNotEmpty && main.any((unit) => unit.id == before.id),
    );
    final empty = liveText().single;
    final firstPublished = main.singleWhere((unit) => unit.id == before.id);
    expect(firstPublished.memberReference, beforeBody.members);
    final owner = lease;
    final scope = owner.content.openScope(generation: owner.generation);
    final emptyObservation = <String, Object?>{'atomId': empty.id};
    report['emptyTextEvidence'] = emptyObservation;
    final readClock = Stopwatch()..start();
    Duration remainingReadTime() {
      final remaining = const Duration(seconds: 60) - readClock.elapsed;
      if (remaining <= Duration.zero) {
        fail('Timed out reading original A14 empty text evidence');
      }
      return remaining;
    }

    try {
      emptyObservation['phase'] = 'active-body';
      expect(empty.source, source);
      expect(empty.lifecycle, isA<ActiveChatAtom>());
      expect(empty.completionSeq, isNull);
      expect(empty.contentPresent, isNull);
      final activeBody = empty.contents
          .where((content) => content.role == ChatContentRole.body)
          .single;
      final activeWindow = await scope
          .readContent(
            reference: activeBody.reference,
            range: const ContentRange(offset: 0, maxBytes: 1024),
          )
          .timeout(remainingReadTime());
      expect(lease, same(owner));
      expect(activeWindow.offset, 0);
      expect(activeWindow.bytes, isEmpty);
      expect(activeWindow.availableThrough, 0);
      emptyObservation['active'] = {
        'contentPresent': 'unknown',
        'completionSeq': empty.completionSeq,
        'bodyBytes': activeWindow.bytes.length,
        'availableThrough': activeWindow.availableThrough,
        'generation': activeWindow.generation,
        'sealed': activeWindow.sealed,
      };
      await release('a14-empty-start');
      await reach(
        'a14-empty-terminal',
        () => !liveText().any((atom) => atom.id == empty.id),
      );
      readClock.reset();
      emptyObservation['phase'] = 'terminal-completion';
      // Ordinary text freezes under its original atom ID. Hidden excludes this
      // completion from Main, not from the original reader's point lookup.
      final completed = await scope
          .readCompleted(
            recordId: empty.id,
            demand: const ReadDemand(maxItems: 1, maxBytes: 64 * 1024),
          )
          .timeout(remainingReadTime());
      expect(lease, same(owner));
      expect(completed.recordId, empty.id);
      expect(completed.atom.id, empty.id);
      expect(completed.atom.completionItemId, completed.recordId);
      expect(completed.atom.completionSeq, completed.completionSeq);
      expect(completed.completionSeq, greaterThan(0));
      expect(completed.atom.source, source);
      expect(completed.atom.lifecycle, isA<TerminalChatAtom>());
      expect(completed.atom.contentPresent, isFalse);
      expect(completed.mainPresentation, MainPresentation.hidden);
      expect(completed.run, isNull);
      expect(completed.atom.payload, isA<InlinePayload>());
      expect(
        (completed.atom.payload as InlinePayload).bytes.length,
        lessThanOrEqualTo(64 * 1024),
      );
      final value = ChatItemPresentation.decode(completed.atom);
      expect(value.compatibility, ChatItemCompatibility.current);
      expect(value.type, 'text');
      expect(value.data['attachments'], isA<List>());
      expect(value.attachments, isEmpty);
      expect(value.bodies, hasLength(1));
      expect(value.bodies.single.byteLength, 0);
      final terminalBody = completed.atom.contents
          .where((content) => content.role == ChatContentRole.body)
          .single;
      final terminalWindow = await scope
          .readContent(
            reference: terminalBody.reference,
            range: const ContentRange(offset: 0, maxBytes: 1024),
          )
          .timeout(remainingReadTime());
      expect(terminalWindow.offset, 0);
      expect(terminalWindow.bytes, isEmpty);
      expect(terminalWindow.availableThrough, 0);
      expect(terminalWindow.sealed, isTrue);
      emptyObservation['terminal'] = {
        'recordId': completed.recordId,
        'completionSeq': completed.completionSeq,
        'contentPresent': completed.atom.contentPresent,
        'mainPresentation': completed.mainPresentation.name,
        'payloadType': value.type,
        'attachmentCount': value.attachments.length,
        'bodyByteLength': value.bodies.single.byteLength,
        'bodyBytes': terminalWindow.bytes.length,
        'availableThrough': terminalWindow.availableThrough,
        'sealed': terminalWindow.sealed,
      };
      emptyObservation['phase'] = 'verified';
    } finally {
      scope.retire();
      final cleanup = await scope.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
      emptyObservation['scopeJoined'] = cleanup.complete;
      expect(cleanup.complete, isTrue);
    }
    expect(
      main.where((unit) => unit.atom?.id == empty.id),
      isEmpty,
      reason: 'Empty text keeps its atomic record but never receives a display position',
    );
    await release('a14-empty-terminal');
    await reach(
      'a14-after-empty',
      () => liveWork().any(
        (block) =>
            block.id != before.id &&
            (block.body as WorkDisplayBlock).summary.total == 1,
      ),
    );
    final after = liveWork().singleWhere((block) => block.id != before.id);
    final afterBody = after.body as WorkDisplayBlock;
    expect(after.id, isNot(before.id));
    expect(afterBody.members, isNot(beforeBody.members));
    expect(main.where((unit) => unit.id == before.id), hasLength(1));
    await capture('a14-empty-separator');
    await release('a14-after-empty');
    await reach('a14-text-readable', () => hasText(_emptyTextAnswer));
    await release('a14-text-readable');
    await reach(
      'a14-before-turn-end',
      () => (lease.live.value?.blocks.isEmpty ?? true),
    );
    expect(
      main.where((unit) => unit.id == before.id || unit.id == after.id),
      hasLength(2),
    );
    expect(
      itemFinder(empty.id),
      findsNothing,
      reason: 'Structural empty text must not paint an empty bubble',
    );
    await release('a14-before-turn-end');
    await idle();
    final membersByBlock = <String, List<String>>{};
    for (final reference in [beforeBody.members, afterBody.members]) {
      final members = await lease.openDisplayMembers(
        reference: reference,
        window: const LatestDisplayMembers(),
        demand: const ReadDemand(maxItems: 2, maxBytes: 16384),
      );
      try {
        final page = await members.next();
        expect(page, isNotNull);
        expect(page!.block, reference);
        expect(page.sealed, isTrue);
        expect(page.entries, hasLength(1));
        expect(page.entries.single.record.atom.source, source);
        expect(page.entries.single.record.atom.id, isNot(empty.id));
        membersByBlock[reference.blockId] = page.entries
            .map((member) => member.record.atom.id)
            .toList();
        expect(await members.next(), isNull);
      } finally {
        members.requestClose();
        await members.close();
      }
    }
    report['emptySeparatorWorkBlocks'] = membersByBlock;
  }

  Future<void> _verifyImageResult(
    _ImageResult result, {
    TimelineGroupDisplay? display,
    required bool missing,
  }) async {
    final item = result.presentation;
    final tool = (item.toolCard as DecodedToolCard).value;
    final finalUnit = result.finalUnit;
    final finalMember = result.finalMember;
    TimelineGroupDisplay? resultDisplay;
    if (finalMember != null) {
      expect(finalUnit, isNotNull);
      resultDisplay = await observed.revealMember(
        result.finalAtom,
        reference: finalUnit!.memberReference!,
      );
    } else if (finalUnit == null) {
      expect(display, isNotNull);
      expect(
        await observed.revealMember(
          result.foreground,
          reference: display!.blockReference!,
        ),
        same(display),
      );
    } else {
      expect(finalUnit.body, isA<SingleDisplayBlock>());
      expect(finalUnit.memberReference, isNull);
      await observed.revealSingle(finalUnit);
      await waitForTimelineConceptSingle(tester, finalUnit);
    }
    final card = finalMember != null
        ? find.descendant(
            of: observed.groupRow(finalUnit!.id),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is ChatItemView &&
                  widget.item.id == finalMember.memberKey,
            ),
          )
        : finalUnit == null
        ? observed.memberRow(result.finalAtom.id)
        : observed.itemRow(finalUnit.id);
    expect(card, findsOneWidget);
    final rendered = tester.widget<ChatItemView>(card).item;
    expect(
      rendered.id,
      finalMember?.memberKey ?? (finalUnit == null ? item.id : finalUnit.id),
    );
    expect(rendered.compatibility, ChatItemCompatibility.current);
    expect(
      rendered.attachments.map((attachment) => attachment.id),
      orderedEquals(item.attachments.map((attachment) => attachment.id)),
    );
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
    expect(renderedTool.id, rendered.id);
    expect(renderedTool.toolCallId, tool.toolCallId);
    expect(renderedTool.outcome, tool.outcome);
    final disclosure = find.descendant(
      of: details,
      matching: find.byKey(ValueKey('timeline-tool-details:${rendered.id}')),
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
    Future<void> waitForDecodedMediaImage(
      Finder subtree, {
      required String stage,
      required List<int> expectedBytes,
      bool viewer = false,
    }) async {
      final rawImages = find.descendant(
        of: subtree,
        matching: find.byType(RawImage),
      );
      Map<String, Object?>? evidence;
      await _until(
        tester,
        () {
          expect(subtree, findsOneWidget);
          final decodeErrors = find.descendant(
            of: subtree,
            matching: find.textContaining('图片解码失败'),
          );
          expect(decodeErrors, findsNothing);
          if (viewer) {
            final route = ModalRoute.of(tester.element(subtree));
            expect(route, isNotNull);
            if (!route!.isCurrent || route.animation?.isCompleted != true) {
              return false;
            }
            final image = tester.widget<Image>(
              find.descendant(of: subtree, matching: find.byType(Image)),
            );
            expect(image.image, isA<MemoryImage>());
            expect(
              (image.image as MemoryImage).bytes,
              orderedEquals(expectedBytes),
            );
          }
          final raw = tester.widgetList<RawImage>(rawImages).toList();
          expect(raw.length, lessThanOrEqualTo(1));
          if (raw.isEmpty || raw.single.image == null) return false;
          expect(raw.single.image!.width, 64);
          expect(raw.single.image!.height, 64);
          final render = tester.renderObject<RenderImage>(rawImages);
          if (!render.attached || !render.hasSize || render.image == null) {
            return false;
          }
          expect(render.image!.width, 64);
          expect(render.image!.height, 64);
          if (!render.size.isFinite || render.size.isEmpty) return false;
          final rectangle = MatrixUtils.transformRect(
            render.getTransformTo(null),
            Offset.zero & render.size,
          );
          if (!rectangle.isFinite || rectangle.isEmpty) return false;
          var visible = rectangle.intersect(
            Offset.zero &
                (tester.view.physicalSize / tester.view.devicePixelRatio),
          );
          RenderObject? ancestor = render.parent;
          while (ancestor != null) {
            if (ancestor is RenderOffstage && ancestor.offstage) return false;
            if (ancestor is RenderOpacity && ancestor.opacity != 1) {
              return false;
            }
            if (ancestor is RenderClipRect ||
                ancestor is RenderClipRRect ||
                ancestor is RenderAbstractViewport) {
              visible = visible.intersect(
                MatrixUtils.transformRect(
                  ancestor.getTransformTo(null),
                  ancestor.paintBounds,
                ),
              );
            }
            ancestor = ancestor.parent;
          }
          if (visible.isEmpty ||
              visible.width < rectangle.width - 1 ||
              visible.height < rectangle.height - 1 ||
              rawImages.hitTestable().evaluate().length != 1) {
            return false;
          }
          evidence = {
            'stage': stage,
            'rowId': rendered.id,
            'resourceId': item.attachments.single.id,
            'decodedWidth': render.image!.width,
            'decodedHeight': render.image!.height,
            'renderWidth': render.size.width,
            'renderHeight': render.size.height,
            'visibleWidth': visible.width,
            'visibleHeight': visible.height,
            'hitTestable': true,
            if (viewer) 'viewerTransitionCompleted': true,
            if (viewer) 'viewerProviderBytesEqual': true,
          };
          return true;
        },
        'decoded, painted-size and visible $stage image ${tool.toolCallId}',
        timeout: remaining(),
      );
      final observations =
          (report['mediaImageRendering'] ??= <Map<String, Object?>>[])
              as List<Map<String, Object?>>;
      observations.add(evidence!);
    }

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
      expect(view.itemId, rendered.id);
      expect(view.attachment.id, item.attachments.single.id);
      expect(view.isTool, isTrue);
      if (missing) {
        expect(view.bytes, isNull);
        expect(view.error, isNotNull);
      } else {
        expect(view.error, isNull);
        expect(view.bytes, isNotEmpty);
        if (phase.startsWith('media-handoff')) {
          expect(
            view.bytes,
            orderedEquals(
              await File('${_environment('PROJECT')}/concept-image-a.png')
                  .readAsBytes(),
            ),
          );
          await waitForDecodedMediaImage(
            images,
            stage: 'details',
            expectedBytes: view.bytes!,
          );
          await capture('background-main-details');
        }
        final entry = StudioDriverKeys.toolImageEntryId(
          rendered.id,
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
        if (phase.startsWith('media-handoff')) {
          await waitForDecodedMediaImage(
            dialog,
            stage: 'viewer',
            expectedBytes: view.bytes!,
            viewer: true,
          );
          await capture('background-main-viewer');
        }
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
        'rowId': rendered.id,
        'toolCallId': tool.toolCallId,
        'delivery': finalMember != null ? 'WorkMember' : 'MainSingle',
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
      'domain': finalMember != null ? 'WorkMember' : 'MainSingle',
      'foregroundMemberId': result.foreground.id,
      'rowId': finalMember?.memberKey ?? finalUnit?.id ?? item.id,
      'atomId': result.finalAtom.id,
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
    if (resultDisplay != null) {
      await observed.closeWork(resultDisplay, timeout: remaining());
      expect(resultDisplay.windows, isEmpty);
      expect(resultDisplay.atoms, isEmpty);
    }
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
      expect(imageGroup.body, isA<WorkDisplayBlock>());
      expect(imageGroup.summary!.total, greaterThan(0));
      expect(imageGroup.state, DisplayBlockState.sealed);
      expect(imageGroup.atom, isNull);
      expect(imageGroup.memberReference, isNotNull);
    } catch (error) {
      _recordImageFailure('read-images-summary', error);
      rethrow;
    }
    final frozenBody = imageGroup.body;
    // A folded item carries summary/ref only, not hidden member/media widgets.
    final mountedBefore = lease.groupDisplays
        .where((display) => display.unitId == imageWorkItemId)
        .singleOrNull;
    if (mountedBefore == null) {
      expect(membersOf(imageWorkItemId), isEmpty);
    }
    final display = await observed.openWork(imageGroup.id);
    final mainIds = main.map((unit) => unit.id).toList();
    final before = lease.olderCursor;
    expect(before, isNull);
    report['imageMainBaseline'] = {
      'ownerGeneration': lease.generation,
      'hasOlder': lease.hasOlder,
      'olderCursor': before,
      'mainIds': mainIds,
    };
    final liveIds = observed.liveBlocks.map((block) => block.id).toList();
    late final List<_ImageResult> results;
    try {
      await contentIdentitiesForItem(imageGroup.id);
      await _awaitImageResults(imageGroup, display);
      results = await _verifyImageMembers(imageGroup, display);
    } catch (error) {
      _recordImageFailure('read-images', error, original: display);
      rethrow;
    }
    expect(display.blockReference, imageGroup.memberReference);
    expect(lease.olderCursor, before);
    expect(
      observed.liveBlocks.map((block) => block.id),
      orderedEquals(liveIds),
    );
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
    expect(main.map((unit) => unit.id), orderedEquals(mainIds));
    expect(lease.olderCursor, before);
    final afterMedia = observed.unit(imageWorkItemId).body;
    expect(
      afterMedia,
      same(frozenBody),
      reason: 'Member/media reads do not replace frozen Main block bodies',
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
    await observed.closeWork(display);
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
    expect(main.map((unit) => unit.id), orderedEquals(mainIds));
    final afterFinals = observed.unit(imageWorkItemId).body;
    expect(
      afterFinals,
      same(frozenBody),
      reason: 'Member/media reads do not replace Main representatives',
    );
    expect(display.atoms, isEmpty);
    expect(display.windows, isEmpty);
    if (input != null) {
      final itemValue = items.singleWhere(
        (item) => item.atom!.source == InputChatSource(inputId: input.inputId),
      );
      expect(itemValue.body, isA<SingleDisplayBlock>());
      expect(itemValue.atom!.kind, ChatAtomKind.input);
      expect(observed.unit(itemValue.id).memberReference, isNull);
      await showUnit(itemValue.id);
      final card = itemFinder(itemValue.id);
      late final ChatItemPresentation item;
      try {
        item = await waitForTimelineConceptSingle(tester, itemValue);
        input.verifyItem(itemValue, item.attachments);
        await waitForTimelineConceptInputImages(tester, item);
      } catch (error) {
        report['inputThumbnailFailure'] = {
          'itemId': itemValue.id,
          'cardCount': card.evaluate().length,
          'sameLease': identical(lease, originalLease),
          'error': error.toString(),
          'views': [
            for (final view in tester.widgetList<TimelineImageView>(
              find.byType(TimelineImageView, skipOffstage: false),
            ))
              if (view.itemId == itemValue.id)
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

  Future<void> _admitSavedMain(Set<String> requiredIds) async {
    final owner = lease;
    final controller = owner.controller;
    final generation = owner.generation;
    final clock = Stopwatch()..start();
    final pages = <Map<String, Object?>>[];
    final observation = <String, Object?>{
      'requiredMessageIds': requiredIds.toList(),
      'generation': generation,
      'initialCount': controller.messages.length,
      'initialCursor': owner.olderCursor,
      'initialHasOlder': owner.hasOlder,
      'pages': pages,
      'admitted': false,
    };
    report['savedMainAdmission'] = observation;
    List<String> missingIds() => requiredIds
        .where((id) => !controller.messages.any((message) => message.id == id))
        .toList();
    void stop(String reason) {
      observation.addAll({
        'missingMessageIds': missingIds(),
        'count': controller.messages.length,
        'cursor': owner.olderCursor,
        'hasOlder': owner.hasOlder,
        'elapsedMillis': clock.elapsedMilliseconds,
        'olderError': graph.timeline.source.value?.olderError?.toString(),
        'failure': reason,
      });
      fail('$reason: ${jsonEncode(observation)}');
    }

    void requireOwner() {
      if (!identical(lease, owner) ||
          !identical(owner.controller, controller) ||
          lease.generation != generation ||
          owner.isRetired ||
          owner.isReleased) {
        stop(
          'Saved Main admission lost its original lease/controller/generation',
        );
      }
    }

    while (true) {
      requireOwner();
      if (missingIds().isEmpty) break;
      if (!owner.hasOlder || owner.olderCursor == null) {
        stop('Main reached EOF without the exact saved message IDs');
      }
      final remaining = const Duration(seconds: 60) - clock.elapsed;
      if (remaining <= Duration.zero) {
        stop('Timed out admitting the exact saved Main message IDs');
      }
      final views = tester
          .widgetList<TimelineView>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TimelineView &&
                  identical(widget.controls, owner) &&
                  widget.threadId == owner.threadId &&
                  widget.view.generation == generation,
            ),
          )
          .toList();
      if (views.length != 1) stop('Expected one original Main paging view');
      final before = owner.olderCursor;
      final count = controller.messages.length;
      try {
        await views.single.onLoadOlder().timeout(remaining);
        await tester.pump();
      } catch (error) {
        stop('Original Main page failed: $error');
      }
      requireOwner();
      pages.add({
        'beforeCursor': before,
        'afterCursor': owner.olderCursor,
        'beforeCount': count,
        'afterCount': controller.messages.length,
      });
      if (graph.timeline.source.value?.olderError != null ||
          owner.olderCursor == before ||
          controller.messages.length <= count) {
        stop('Original Main page did not advance its cursor and loaded count');
      }
      expect(tester.takeException(), isNull);
    }
    for (final id in requiredIds) {
      expect(
        controller.messages.where((message) => message.id == id),
        hasLength(1),
      );
    }
    observation.addAll({
      'admitted': true,
      'finalCount': controller.messages.length,
      'finalCursor': owner.olderCursor,
      'elapsedMillis': clock.elapsedMilliseconds,
    });
  }

  Future<void> reopened(
    Map<String, dynamic> saved, {
    required bool missing,
  }) async {
    await idle();
    if (!missing) await warmSelectionSamples();
    final input = saved['imageInput'] as Map<String, dynamic>;
    final inputId = input['inputId'] as String;
    // A finite assertion demand, not another history collection. The original
    // page owner alone admits these saved Message IDs into its controller.
    await _admitSavedMain({
      input['itemId'] as String,
      saved['imageWorkItemId'] as String,
      ...(saved['coreOrder'] as List).cast<String>(),
      for (final field in ['oldWorkId', 'textRowId', 'endWorkId'])
        (saved['a07Handoff'] as Map<String, dynamic>)[field] as String,
      for (final field in [
        'partialItemId',
        'failureItemId',
        'compactionItemId',
      ])
        saved[field] as String,
    });
    // Production projection IDs survive reopen. Reveal exactly the saved Main
    // item, never search folded groups by member contents or ID prefixes.
    final target = find.byWidgetPredicate(
      (widget) => widget is ChatItemView && widget.item.id == input['itemId'],
    );
    await observed.reveal(target, input['itemId'] as String);
    final item = items.singleWhere(
      (item) => item.atom!.source == InputChatSource(inputId: inputId),
    );
    expect(item.id, input['itemId']);
    expect(
      completedOriginalId((item.body as SingleDisplayBlock).record),
      input['contentItemId'],
    );
    expect(item.historyPos, input['historyPos']);
    expect(item.atom!.completionSeq, input['completionSeq']);
    expect(item.body, isA<SingleDisplayBlock>());
    expect(item.atom!.kind, ChatAtomKind.input);
    final renderedInput = await waitForTimelineConceptSingle(tester, item);
    final attachments = renderedInput.attachments;
    expect(
      attachments.map((attachment) => attachment.id),
      orderedEquals((input['attachmentResourceIds'] as List).cast<String>()),
    );
    expect(attachments, hasLength(3));
    await waitForTimelineConceptInputImages(tester, renderedInput);
    final rectangles = [
      for (final attachment in attachments)
        tester.getRect(
          find.descendant(
            of: target,
            matching: find.byKey(
              StudioDriverKeys.viewImageThumbnail(attachment.id),
            ),
          ),
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
      reopenedUnits.map((unit) => unit.body is WorkDisplayBlock),
      orderedEquals([true, false, true, false]),
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
      expect(items.where((item) => item.id == id), hasLength(1));
      expect(
        items.singleWhere((item) => item.id == id).historyPos,
        greaterThan(0),
      );
    }
    report['reopenedInputId'] = inputId;
    report['ownerGeneration'] = lease.generation;
    await _record(missing ? 'media-missing-complete' : 'reopen-complete');
    await capture('complete');
  }
}
