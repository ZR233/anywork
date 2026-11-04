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
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_image_view.dart';
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
const _emptyTextPrompt = 'A14：空正文开始和结束仍然分开前后两段工作。';
const _emptyTextAnswer = '空正文没有可见气泡，但前后工作不属于同一段。';
const _imageCalls = ['concept-image-a', 'concept-image-b', 'concept-image-c'];

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
        await _until(
          tester,
          () => graph.client.budget.used(ResourceKind.chatHandle) == 0,
          'all concept read handles joined',
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
  String description,
) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > const Duration(seconds: 60)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  }
}

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
  List<TimelineDisplayUnit> get live => lease.liveUnits.value;
  Iterable<TimelineItem> get items => main.map((unit) => unit.item);
  Iterable<ChatAtom> membersOf(String unitId) => lease.groupDisplays
      .where((display) => display.unitId == unitId)
      .expand((display) => display.atoms);
  ChatItemPresentation presentation(TimelineItem item) =>
      ChatItemPresentation.decodePayload(item.id, item.payload!);
  bool hasText(String text) =>
      find.textContaining(text, findRichText: true).evaluate().isNotEmpty;
  Finder unitFinder(String id) => find.byWidgetPredicate(
    (widget) =>
        (widget is TimelineDisplayUnitView && widget.unit.id == id) ||
        (widget is ChatItemView &&
            widget.item.displayUnit == null &&
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
    await _until(tester, ready, 'production state at $stage');
    await _record(stage);
  }

  Future<void> release(String stage) =>
      fixtureGate(tester, provider, stage, release: true);

  Future<void> _record(String stage) async {
    // Observe real metrics after the production View's layout/post-frame work.
    // This pump does not advance a provider gate or issue a page command.
    await tester.pump();
    expect(tester.takeException(), isNull);
    Map<String, Object?> unit(TimelineDisplayUnit value) => {
      'id': value.id,
      'kind': value.item.kind.name,
      'live': value.live,
      'memberCount': value.item.summary?.memberCount,
      'activeCount': value.item.summary?.activeCount,
      'membersRef': value.item.members?.itemId,
      'mountedMemberIds': [for (final atom in membersOf(value.id)) atom.id],
      'memberWindows': [
        for (final display in lease.groupDisplays)
          if (display.unitId == value.id)
            {
              'displayIdentity': identityHashCode(display),
              'isCurrent': display.isCurrent,
              'expanded': display.expanded,
              'before': display.before,
              'loading': display.loading,
              'error': display.error?.toString(),
              'atoms': [
                for (final atom in display.atoms)
                  {
                    'id': atom.id,
                    'kind': atom.kind.name,
                    'sourceOrder': atom.sourceOrder,
                    'turnId': atom.turnId,
                    'attemptId': atom.attemptId,
                    'completionItemId': atom.completionItemId,
                    'completionSeq': atom.completionSeq,
                    'lifecycle': atom.lifecycle.runtimeType.toString(),
                    if (atom.lifecycle is ActiveChatAtom)
                      'status': (atom.lifecycle as ActiveChatAtom).status.name,
                    if (atom.lifecycle is TerminalChatAtom)
                      'outcome':
                          (atom.lifecycle as TerminalChatAtom).outcome.name,
                    if (atom.lifecycle is TerminalChatAtom)
                      'endedEffectSeq':
                          (atom.lifecycle as TerminalChatAtom).ended?.effectSeq,
                    'sourceLifecycle': atom.sourceState?.lifecycle.runtimeType
                        .toString(),
                    'sourceEndedEffectSeq': atom.sourceState?.ended?.effectSeq,
                  },
              ],
            },
      ],
      'toolCallIds': [
        for (final atom in membersOf(value.id))
          if (atom.tool != null) atom.tool!.callId,
      ],
      'startedAt': value.item.startedAt,
      'finishedAt': value.item.finishedAt,
    };
    _checkpoints.add({
      'stage': stage,
      'ownerGeneration': lease.generation,
      'mainMessageCount': lease.controller.messages.length,
      'main': main.map(unit).toList(),
      'live': live.map(unit).toList(),
      'hasOlder': lease.hasOlder,
      'frameObservation': frameObservation(lease),
    });
    report['checkpoints'] = _checkpoints;
    // Unit IDs and member counts are intentionally different observations.
    expect(main.map((unit) => unit.id).toSet(), hasLength(main.length));
    expect(
      main
          .map((unit) => unit.id)
          .toSet()
          .intersection(live.map((unit) => unit.id).toSet()),
      isEmpty,
      reason: 'one display unit must not be in both Main and current',
    );
    expect(main.every((unit) => !unit.live), isTrue);
    for (final view in tester.widgetList<TimelineDisplayUnitView>(
      find.byType(TimelineDisplayUnitView),
    )) {
      final value = view.unit;
      if (value.live || value.item.kind != TimelineItemKind.workGroup) continue;
      final header = tester.widget<TimelineActivityRow>(
        find.byKey(ValueKey('source-unit-header:${value.id}')),
      );
      expect(header.active, isFalse, reason: 'history headers never spin');
      if (value.item.summary?.startedAt == null ||
          value.item.summary?.finishedAt == null) {
        expect(
          header.label,
          '工作记录',
          reason:
              'an unknown interval is not a fabricated zero-second duration',
        );
      }
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
      'residentLiveItems': target.liveUnits.value.length,
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
    report['warmSelections'] = {
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
      await _until(
        tester,
        () => graph.client.budget.used(ResourceKind.chatHandle) == 0,
        'warm selection original read handles joined',
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
  Future<TimelineDisplayUnit> reopenActiveWorkgroup() async {
    final before = lease;
    final original = live.single;
    final originalMembers = await observed.openGroup(original.id);
    final member = originalMembers.atoms.single;
    final source = original.item.source;
    expect(source, isA<ForegroundTurnChatSource>());
    final activeTurnId = (source as ForegroundTurnChatSource).turnId;
    expect(original.item.summary!.activeCount, 1);
    expect(member.lifecycle, isA<ActiveChatAtom>());
    expect(member.contents, isNotEmpty);
    expect(before.content.current.value?.activeTurn?.id, activeTurnId);
    expect(before.content.current.value?.logicalStatus.isActive, isTrue);
    final originalCurrent = before.currentDisplay!;
    expect(originalCurrent.isCurrent, isTrue);
    final historyIds = items.map((item) => item.id).toList();
    expect(historyIds, isNotEmpty);
    expect(historyIds.toSet(), hasLength(historyIds.length));

    // Active parts already use their real item-owned body. Reopening must keep
    // that member owner/key, not substitute a current domain or a UI group key.
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
    final selectedThread = before.threadId;
    await tap(find.byKey(StudioDriverKeys.settingsOpen));
    await _until(
      tester,
      () => find.byKey(StudioDriverKeys.settingsPage).evaluate().isNotEmpty,
      'settings page while the original model member remains held',
    );
    await _until(
      tester,
      () => before.isRetired && before.isReleased,
      'original Main lease retired and all its original query scopes joined',
    );
    // released completes only after unmount, mutations and owned-query close.
    // Do not read before.queries: that getter would admit another read scope.
    await before.released;
    expect(before.queryCleanupError, isNull);
    expect(originalCurrent.isCurrent, isFalse);
    expect(originalCurrent.windows, isEmpty);
    expect(originalMembers.isCurrent, isFalse);
    expect(originalMembers.atoms, isEmpty);
    await _until(
      tester,
      () => graph.client.budget.used(ResourceKind.chatHandle) == 0,
      'no previous conversation read handle remains outside its page',
    );

    await tap(find.byKey(StudioDriverKeys.settingsBack));
    await openThread(selectedThread);
    await _until(tester, () {
      final next = graph.timeline.lease(selectedThread);
      if (next == null || identical(next, before) || !next.isMounted) {
        return false;
      }
      return next.appliedSets == 1 &&
          next.currentDisplay?.isCurrent == true &&
          next.liveUnits.value.any(
            (unit) =>
                unit.item.source == source &&
                unit.id == original.id &&
                unit.item.members == original.item.members &&
                unit.item.summary?.activeCount == 1,
          );
    }, 'fresh native Set still carries the same active source and member');
    final after = lease;
    expect(after.generation, greaterThan(before.generation));
    expect(after.appliedSets, 1);
    expect(after.content.current.value?.activeTurn?.id, activeTurnId);
    expect(after.content.current.value?.logicalStatus.isActive, isTrue);
    expect(after.currentDisplay!.turnId, activeTurnId);
    expect(graph.client.selection.state.selectedThreadId, selectedThread);
    expect(
      tester
          .widget<ConversationCurrentConnector>(
            find.byType(ConversationCurrentConnector),
          )
          .units,
      same(after.liveUnits),
    );
    expect(live, hasLength(1));
    final reopened = live.single;
    expect(reopened.item.source, source);
    expect(reopened.id, original.id);
    expect(reopened.item.members, original.item.members);
    expect(reopened.item.kind, original.item.kind);
    expect(reopened.live, isTrue);
    expect(reopened.item.admissionClosed, isFalse);
    expect(reopened.item.summary!.activeCount, 1);
    final resumedDisplay = await observed.openGroup(reopened.id);
    expect(resumedDisplay.atoms, hasLength(1));
    final resumed = resumedDisplay.atoms.single;
    expect(resumed.id, member.id);
    expect(resumed.source, member.source);
    expect(resumed.kind, member.kind);
    expect(resumed.sourceOrder, member.sourceOrder);
    expect(resumed.lifecycle, isA<ActiveChatAtom>());
    expect(
      (resumed.lifecycle as ActiveChatAtom).status,
      (member.lifecycle as ActiveChatAtom).status,
    );
    expect(resumed.contents.map(memberBody), orderedEquals(bodyIdentities));
    expect(items.map((item) => item.id), orderedEquals(historyIds));
    expect(items.where((item) => item.contentItemId == member.id), isEmpty);
    expect(
      main.where((unit) => unit.item.kind == TimelineItemKind.workGroup),
      isEmpty,
    );
    expect(unitFinder(reopened.id), findsOneWidget);
    report['midstreamReopen'] = {
      'gate': 'workgroup',
      'threadId': selectedThread,
      'turnId': activeTurnId,
      'memberId': resumed.id,
      'memberKind': resumed.kind.name,
      'oldGeneration': before.generation,
      'newGeneration': after.generation,
      'oldLeaseReleased': before.isReleased,
      'newMainSets': after.appliedSets,
      'historyItemIds': historyIds,
      'activeContentReferences': [
        for (final content in resumed.contents)
          {
            'role': content.role.name,
            'databaseId': content.reference.databaseId,
            'key': (content.reference.target as BodyContentTarget).key,
            'ownerKind': 'item',
            'ownerId':
                ((content.reference.target as BodyContentTarget).owner
                        as ItemContentOwner)
                    .itemId,
          },
      ],
    };
    await _record('workgroup-reopened');
    return reopened;
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
    await reveal(unitFinder(id), unitId: id);
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
                  TimelineDisplayUnitView(:final unit) when !unit.live =>
                    unit.id,
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
    await observed.openGroup(unit.id);
  }

  void _recordMemberInventory(
    String stage,
    String id, {
    TimelineGroupDisplay? original,
    Object? error,
  }) {
    Map<String, Object?>? reference(TimelineMembersRef? value) => value == null
        ? null
        : {
            'itemId': value.itemId,
            'databaseId': value.databaseId,
            'projectionVersion': value.projectionVersion,
            'projectionGeneration': value.projectionGeneration,
          };
    Map<String, Object?> display(TimelineGroupDisplay value) => {
      'unitId': value.unitId,
      'identity': identityHashCode(value),
      'membersRef': reference(value.membersRef),
      'isCurrent': value.isCurrent,
      'expanded': value.expanded,
      'before': value.before,
      'loading': value.loading,
      'error': value.error?.toString(),
      'mountedMemberCount': value.atoms.length,
    };
    // Borrow only already mounted consumers, including one still awaiting a
    // permit. This synchronous diagnostic never opens, pages or copies atoms.
    final windows = <Map<String, Object?>>[];
    for (final element in find.byType(TimelineChildrenConnector).evaluate()) {
      final widget = element.widget as TimelineChildrenConnector;
      if (widget.threadId != lease.threadId ||
          widget.membersRef == null ||
          element is! StatefulElement) {
        continue;
      }
      final Object state = element.state;
      if (state is! TimelineChildrenDisplay) continue;
      windows.add({
        'parentId': state.parentId,
        'membersRef': reference(widget.membersRef),
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
      'chatHandleCapacity':
          graph.client.budget.capacities[ResourceKind.chatHandle],
      'chatHandleUsed': graph.client.budget.used(ResourceKind.chatHandle),
      'chatHandles': [
        for (final usage in graph.client.budget.usage)
          if (usage.kind == ResourceKind.chatHandle)
            {'owner': usage.owner, 'phase': usage.phase.name},
      ],
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
    if (unit.item.kind != TimelineItemKind.workGroup) {
      expect(unit.item.contentItemId, isNotNull);
      return [unit.item.contentItemId!];
    }
    final reusedWindow = lease.groupDisplays.any(
      (display) =>
          display.unitId == id && display.isCurrent && display.expanded,
    );
    TimelineGroupDisplay? original;
    _recordMemberInventory('before-open', id);
    try {
      final display = await observed.openGroup(id);
      original = display;
      final ids = <String>{};
      var olderPageCommands = 0;
      while (true) {
        ids.addAll(display.atoms.map((atom) => atom.id));
        if (display.before == null && !display.loading) break;
        final before = display.before;
        final older = find.descendant(
          of: observed.groupRow(id),
          matching: find.byKey(const ValueKey('timeline-children-load-older')),
        );
        await observed.tap(older);
        olderPageCommands++;
        await _until(tester, () {
          if (display.error case final error?) throw StateError('$error');
          return !display.loading && display.before != before;
        }, 'explicit group member page advanced');
      }
      expect(ids, hasLength(unit.item.summary!.memberCount));
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
      _recordMemberInventory('eof-before-close', id, original: display);
      // Inventory retains IDs, not simultaneous historical member leases.
      // Revoke this original window through its ordinary UI before proceeding.
      await observed.closeGroup(display);
      _recordMemberInventory('closed', id, original: display);
      return ids.toList();
    } catch (error) {
      _recordMemberInventory('failed', id, original: original, error: error);
      rethrow;
    }
  }

  Future<void> journey(String project) async {
    await _until(tester, () => !lease.hasOlder, 'empty conversation EOF');
    expect(lease.controller.messages, isEmpty);
    expect(live, isEmpty);
    expect(find.byType(ConversationCurrentConnector), findsNothing);
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
      expect(
        main.where((unit) => unit.item.kind == TimelineItemKind.workGroup),
        isEmpty,
      );
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
      () =>
          live.length == 1 &&
          live.single.item.summary!.memberCount == 1 &&
          live.single.item.summary!.categories.single.category ==
              TimelineCategory.thinking,
    );
    var g1 = live.single.id;
    final source = live.single.item.source;
    expect(live.single.live, isTrue);
    expect(
      tester
          .widget<ConversationCurrentConnector>(
            find.byType(ConversationCurrentConnector),
          )
          .units,
      same(lease.liveUnits),
    );
    expect(live.single.item.admissionClosed, isFalse);
    expect(live.single.item.summary!.activeCount, 1);
    expect(main.where((unit) => unit.id == g1), isEmpty);
    expect(unitFinder(g1), findsOneWidget);
    await capture('workgroup');
    // The projection owns stable item identity across owner replacement.
    g1 = (await reopenActiveWorkgroup()).id;
    final openedMembers = lease.groupDisplays.singleWhere(
      (display) => display.unitId == g1,
    );
    await capture('workgroup-reopened');
    await release('workgroup');

    await reach(
      'group-idle',
      () => live.any(
        (unit) =>
            unit.id == g1 &&
            unit.item.summary!.memberCount == 4 &&
            unit.item.summary!.activeCount == 0,
      ),
    );
    final quiet = live.single;
    await _until(
      tester,
      () =>
          membersOf(quiet.id).length == quiet.item.summary!.memberCount &&
          membersOf(quiet.id)
              .every((atom) => atom.lifecycle is TerminalChatAtom),
      'same explicitly opened live member window reaches terminal state',
    );
    expect(
      lease.groupDisplays.singleWhere((display) => display.unitId == quiet.id),
      same(openedMembers),
      reason: 'member handoff must not replace the explicitly opened display',
    );
    expect(openedMembers.isCurrent, isTrue);
    expect(openedMembers.expanded, isTrue);
    expect(openedMembers.error, isNull);
    await _record('same-member-window-terminal');
    expect(quiet.item.admissionClosed, isFalse);
    expect(quiet.live, isTrue);
    expect(
      tester
          .widget<TimelineActivityRow>(
            find.byKey(ValueKey('source-unit-header:$g1')),
          )
          .label,
      '等待后继边界',
    );
    expect(main.where((unit) => unit.id == g1), isEmpty);
    expect(
      membersOf(quiet.id)
          .where((atom) => atom.tool != null)
          .map((atom) => atom.tool!.callId),
      unorderedEquals([
        'concept-read-call',
        'concept-command-a',
        'concept-command-b',
      ]),
    );
    expect(
      membersOf(quiet.id).every((atom) => atom.lifecycle is TerminalChatAtom),
      isTrue,
    );
    await capture('group-idle');
    await release('group-idle');

    await reach(
      'text',
      () =>
          main.any((unit) => unit.id == g1) &&
          live.any((unit) => unit.item.kind == TimelineItemKind.text) &&
          hasText(_textA),
    );
    expect(main.where((unit) => unit.id == g1), hasLength(1));
    expect(
      main.where(
        (unit) =>
            unit.item.source == source &&
            unit.item.kind == TimelineItemKind.text,
      ),
      isEmpty,
    );
    final a = live.single.id;
    expect(live.single.item.outcome, isNull);
    expect(live.single.item.atomKind, ChatAtomKind.text);
    expect(live.single.item.contents, isNotEmpty);
    await capture('text');
    await release('text');

    await reach(
      'after-text',
      () => live.isEmpty && main.any((unit) => unit.id == a),
    );
    expect(main.where((unit) => unit.id == a), hasLength(1));
    expect(find.byKey(const ValueKey('conversation-activity')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('conversation-activity')),
        matching: find.text('思考中'),
      ),
      findsOneWidget,
    );
    await capture('after-text');
    await release('after-text');

    await reach(
      'next-group',
      () =>
          live.length == 1 &&
          live.single.item.kind == TimelineItemKind.workGroup,
    );
    final g2 = live.single.id;
    expect(g2, isNot(g1));
    expect(live.single.item.source, source);
    expect(
      main.where((unit) => unit.id == g1).single.item.summary!.memberCount,
      quiet.item.summary!.memberCount,
    );
    expect(main.where((unit) => unit.id == g2), isEmpty);
    await capture('next-group');
    await release('next-group');
    await reach(
      'second-group-idle',
      () =>
          live.length == 1 &&
          live.single.id == g2 &&
          live.single.item.summary!.activeCount == 0,
    );
    expect(live.single.item.admissionClosed, isFalse);
    final credit = await openCredit();
    await release('second-group-idle');
    await reach(
      'second-text',
      () =>
          main.any((unit) => unit.id == g2) &&
          live.length == 1 &&
          live.single.item.kind == TimelineItemKind.text &&
          hasText(_textB),
    );
    final b = live.single.id;
    await release('second-text');
    await reach(
      'before-turn-end',
      () => live.isEmpty && main.any((unit) => unit.id == b),
    );
    expect(
      main.where((unit) => unit.item.source == source).map((unit) => unit.id),
      orderedEquals([g1, a, g2, b]),
    );
    final completedTextB = main.singleWhere((unit) => unit.id == b).item;
    await _creditAsync(() async {
      await credit.queryCompletedText(completedTextB);
      await credit.observeSuccessors();
      await credit.verifyClosed(completedTextB.contentItemId!);
    });
    await release('before-turn-end');
    await idle();
    final firstGroup = main.singleWhere((unit) => unit.id == g1);
    await _until(tester, () {
      final turn = graph.client.conversations.session(threadId).state.lastTurn;
      return turn != null &&
          turn.threadId == threadId &&
          turn.turnId == completedTextB.turnId &&
          turn.state.isTerminal &&
          turn.state.status == StudioTurnStatus.completed;
    }, 'the original successful Turn reaches the Client typed terminal state');
    expect(
      main.where(
        (unit) =>
            unit.item.source == firstGroup.item.source &&
            unit.item.atomKind == ChatAtomKind.turnReceipt,
      ),
      isEmpty,
      reason: 'A normal successful Turn does not manufacture a Main receipt',
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
    await expand(firstGroup);
    final reasoningBody = find.descendant(
      of: find.descendant(
        of: unitFinder(g1),
        matching: itemFinder(
          membersOf(firstGroup.id)
              .singleWhere((atom) => atom.kind == ChatAtomKind.reasoning)
              .id,
        ),
      ),
      matching: find.text('梳理会话共享组件与锁定边界', findRichText: true),
    );
    await _until(
      tester,
      () => reasoningBody.evaluate().length == 1,
      'reasoning body on first group expansion',
    );
    // Drain this ExpansionTile animation only; active indicators elsewhere need
    // not settle, and the first-content/fill timing witnesses are unchanged.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(reasoningBody, findsOneWidget);
    expect(reasoningBody.hitTestable(), findsOneWidget);
    final reasoningBounds = tester.getRect(reasoningBody);
    expect(reasoningBounds.width, greaterThan(0));
    expect(reasoningBounds.height, greaterThan(0));
    expect(
      reasoningBounds.intersect(tester.getRect(unitFinder(g1))),
      reasoningBounds,
      reason: 'The expanded group must not clip its reasoning body',
    );
    expect(
      reasoningBounds.intersect(tester.getRect(find.byKey(lease.chatKey))),
      reasoningBounds,
      reason: 'The reasoning body must be visible in the timeline viewport',
    );
    // A work unit is not a Turn container; tool call identities are singular.
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
    report['coreOrder'] = [g1, a, g2, b];
    // Save production item IDs, never infer a parent from member contents.
    report['coreContentIdentities'] = [
      for (final id in [g1, a, g2, b]) await contentIdentitiesForItem(id),
    ];
    await capture('core-main');
    await compact();

    final input = await submitTimelineConceptImageInput(
      tester,
      graph,
      threadId: threadId,
      projectPath: project,
    );
    report['imageInput'] = input.toJson();
    await reach(
      'images-ready',
      () =>
          live
              .where(
                (unit) =>
                    unit.item.kind == TimelineItemKind.workGroup &&
                    unit.item.summary!.memberCount == 4 &&
                    unit.item.summary!.activeCount == 0,
              )
              .length ==
          1,
    );
    final imageWork = live.singleWhere(
      (unit) => unit.item.kind == TimelineItemKind.workGroup,
    );
    report['imageWorkItemId'] = imageWork.id;
    await expand(imageWork);
    expect(membersOf(imageWork.id).map((atom) => atom.tool?.callId).toSet(), {
      ..._imageCalls,
      'concept-image-failed',
    });
    expect(
      membersOf(imageWork.id)
          .every((atom) => atom.lifecycle is TerminalChatAtom),
      isTrue,
    );
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
          live.any((unit) => unit.item.kind == TimelineItemKind.text) &&
          hasText(_partial),
    );
    final partialItem = live.single.id;
    await capture('failed-partial');
    await release('failed-partial');
    await idle();
    await _until(
      tester,
      () => items.any(
        (item) =>
            item.id == partialItem &&
            item.position != null &&
            item.outcome != null,
      ),
      'failed partial retained',
    );
    await _until(
      tester,
      () => items.any(
        (item) =>
            item.kind == TimelineItemKind.status &&
            item.atomKind == ChatAtomKind.turnReceipt &&
            item.payload != null &&
            (presentation(item).data['outcome'] as Map)['kind'] == 'failed',
      ),
      'independent reliable failed Turn receipt',
    );
    final failure = items.lastWhere(
      (item) =>
          item.atomKind == ChatAtomKind.turnReceipt &&
          (presentation(item).data['outcome'] as Map)['kind'] == 'failed',
    );
    final failureItem = presentation(failure);
    expect((failureItem.data['outcome'] as Map)['kind'], 'failed');
    expect(failure.id, isNot(partialItem));
    await showUnit(partialItem);
    await _until(
      tester,
      () => hasText(_partial),
      'failed partial still readable',
    );
    await showUnit(failure.id);
    final receipt = itemFinder(failure.id);
    final disclosure = find.descendant(
      of: receipt,
      matching: find.byType(TimelineActivityDisclosure),
    );
    await tap(disclosure);
    await _until(
      tester,
      () => hasText('concept provider permanent failure'),
      'independent provider failure reason',
    );
    await capture('failed');
    report['partialItemId'] = partialItem;
    report['failureItemId'] = failure.id;
    // A new real input after failure must still traverse the production composer.
    await overlap();
    await emptyText();
    await idle();
    await capture('idle');
    await _record('journey-complete');
    report['coreMemberCounts'] = [quiet.item.summary!.memberCount, 1];
    report['independentScenarioCoverage'] = {
      'questionsAndReceipts': 'question-history (separate strict provider)',
      'normalStopContinue': 'realtime-presentation (separate strict provider)',
    };
  }

  Future<void> compact() async {
    final owner = lease;
    final selectedThread = threadId;
    final currentConnector = find.byWidgetPredicate(
      (widget) =>
          widget is ConversationCurrentConnector &&
          identical(widget.content, owner.content) &&
          identical(widget.units, owner.liveUnits),
    );
    List<TimelineItem> activeCompactions() => [
      for (final item in owner.content.current.value?.items ?? <TimelineItem>[])
        if (item.kind == TimelineItemKind.status &&
            item.atomKind == ChatAtomKind.compaction &&
            item.outcome == null)
          item,
    ];
    Finder currentUnit(TimelineDisplayUnit unit) => find.descendant(
      of: currentConnector,
      matching: find.byKey(ValueKey(unit.id)),
    );
    Finder currentRows(TimelineDisplayUnit unit) => find.descendant(
      of: currentUnit(unit),
      matching: find.byType(TimelineActivityRow),
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
    try {
      await reach('compacting', () {
        final active = activeCompactions();
        final units = owner.liveUnits.value;
        return active.length == 1 &&
            units.length == 1 &&
            units.single.id == active.single.id &&
            currentRows(units.single).evaluate().length == 1;
      });
    } on Object {
      // Preserve each real predicate input before shutdown retires the owner.
      // This observation starts no read, advances no gate, and relaxes nothing.
      Map<String, Object?> itemObservation(TimelineItem item) => {
        'id': item.id,
        'kind': item.kind.name,
        'atomKind': item.atomKind?.name,
        'outcome': item.outcome?.name,
        'source': '${item.source}',
      };
      report['compactionFailure'] = {
        'sameOwner': identical(lease, owner),
        'ownerGeneration': owner.generation,
        'selectedGeneration': lease.generation,
        'currentConnectorCount': currentConnector.evaluate().length,
        'activeHead': owner.content.current.value?.active?.kind.name,
        'currentItems': [
          for (final item
              in owner.content.current.value?.items ?? <TimelineItem>[])
            itemObservation(item),
        ],
        'liveUnits': [
          for (final unit in owner.liveUnits.value)
            {
              'id': unit.id,
              'kind': unit.item.kind.name,
              'live': unit.live,
              'item': itemObservation(unit.item),
              'matchingViewCount': currentUnit(unit).evaluate().length,
              'matchingRowCount': currentRows(unit).evaluate().length,
            },
        ],
        'currentRows': [
          for (final row in tester.widgetList<TimelineActivityRow>(
            find.descendant(
              of: currentConnector,
              matching: find.byType(TimelineActivityRow),
            ),
          ))
            {
              'label': row.label,
              'active': row.active,
              'expandable': row.expandable,
              'icon': row.icon?.codePoint,
            },
        ],
      };
      rethrow;
    }
    expect(lease, same(owner));
    expect(threadId, selectedThread);
    final active = activeCompactions().single;
    final unit = owner.liveUnits.value.single;
    expect(active.source, isA<OperationChatSource>());
    expect(active.outcome, isNull);
    expect(active.position, isNull);
    expect(unit.item.kind, TimelineItemKind.status);
    expect(unit.live, isTrue);
    expect(unit.item.source, active.source);
    expect(unit.id, active.id);
    expect(unit.item.outcome, isNull);
    expect(unit.item.summary, isNull);
    expect(unit.item.members, isNull);
    expect(main.where((value) => value.item.source == active.source), isEmpty);
    expect(currentConnector, findsOneWidget);
    expect(currentUnit(unit), findsOneWidget);
    expect(
      find.descendant(
        of: currentConnector,
        matching: find.byType(ConversationActivityBar),
      ),
      findsNothing,
    );
    final rowFinder = currentRows(unit);
    expect(rowFinder, findsOneWidget);
    final row = tester.widget<TimelineActivityRow>(rowFinder);
    expect(
      row.label,
      AppLocalizations.of(tester.element(rowFinder))
          .conversationActivityCompacting,
    );
    expect(row.icon, Icons.compress_outlined);
    expect(row.active, isTrue);
    expect(row.expandable, isFalse);
    report['compactionCurrent'] = {
      'itemId': active.id,
      'contentItemId': active.contentItemId,
      'unitId': unit.id,
      'unitKind': unit.item.kind.name,
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
    final prior = items
        .where((item) => item.atomKind == ChatAtomKind.compaction)
        .map((item) => item.id)
        .toSet();
    await release('compacting');
    await _until(
      tester,
      () => items.any(
        (item) =>
            item.atomKind == ChatAtomKind.compaction &&
            !prior.contains(item.id) &&
            item.outcome == ChatTerminalOutcome.completed &&
            item.position != null,
      ),
      'real completed compaction receipt',
    );
    await idle();
    final receipt = items
        .where(
          (item) =>
              item.atomKind == ChatAtomKind.compaction &&
              !prior.contains(item.id),
        )
        .single;
    expect(receipt.outcome, ChatTerminalOutcome.completed);
    report['compactionItemId'] = receipt.id;
    final completedUnit = main.singleWhere((unit) => unit.id == receipt.id);
    expect(completedUnit.item.kind, TimelineItemKind.status);
    expect(completedUnit.live, isFalse);
    expect(completedUnit.item.contentItemId, receipt.contentItemId);
    expect(completedUnit.item.summary, isNull);
    expect(completedUnit.item.members, isNull);
    await showUnit(completedUnit.id);
    await _until(
      tester,
      () => hasText('已完成压缩'),
      'completed compaction on production page',
    );
    final completedItem = itemFinder(receipt.id);
    expect(completedItem, findsOneWidget);
    final completedRows = find.descendant(
      of: completedItem,
      matching: find.byType(TimelineActivityRow),
    );
    expect(completedRows, findsOneWidget);
    final completedRow = tester.widget<TimelineActivityRow>(completedRows);
    expect(
      completedRow.label,
      AppLocalizations.of(tester.element(completedRows))
          .timelineContextCompacted,
    );
    expect(completedRow.icon, Icons.compress_outlined);
    expect(completedRow.active, isFalse);
    expect(completedRow.expandable, isFalse);
    await capture('compacted');
  }

  Future<void> overlap() async {
    await submit(_overlapPrompt);
    await reach(
      'a07-reasoning-start',
      () =>
          live.length == 1 &&
          live.single.item.kind == TimelineItemKind.workGroup,
    );
    final work = live.single.id;
    await expand(live.single);
    final reason = membersOf(work).single.id;
    await release('a07-reasoning-start');
    await reach(
      'a07-text-start',
      () =>
          live.length == 2 &&
          live.any((unit) => unit.item.kind == TimelineItemKind.text) &&
          hasText('正文已经开始且可以读取，'),
    );
    final text = live
        .singleWhere((unit) => unit.item.kind == TimelineItemKind.text)
        .id;
    expect(membersOf(work).single.lifecycle, isA<ActiveChatAtom>());
    expect(main.where((unit) => unit.id == work || unit.id == text), isEmpty);
    await release('a07-text-start');
    await reach('a07-text-readable', () => hasText(_overlapText));
    await capture('a07-late-reasoning');
    await release('a07-text-readable');
    await reach(
      'a07-text-terminal',
      () => live.any((unit) => unit.id == text && unit.item.outcome != null),
    );
    expect(membersOf(work).single.id, reason);
    expect(
      live.singleWhere((unit) => unit.id == work).item.summary!.activeCount,
      1,
    );
    expect(main.where((unit) => unit.id == text), isEmpty);
    await release('a07-text-terminal');
    await reach(
      'a07-reasoning-terminal',
      () =>
          main.any((unit) => unit.id == work) &&
          main.any((unit) => unit.id == text),
    );
    final order = main.map((unit) => unit.id).toList();
    expect(order.indexOf(work), lessThan(order.indexOf(text)));
    await release('a07-reasoning-terminal');
    await idle();
    report['overlapAtomIds'] = [reason];
  }

  Future<void> emptyText() async {
    await submit(_emptyTextPrompt);
    await reach(
      'a14-before-empty',
      () => live.length == 1 && live.single.item.summary!.activeCount == 0,
    );
    final before = live.single.id;
    await release('a14-before-empty');
    await reach('a14-empty-start', () => main.any((unit) => unit.id == before));
    // Structural empty text is allowed in owner metadata; never an empty bubble.
    final empty = live.singleWhere(
      (unit) => unit.item.kind == TimelineItemKind.text,
    );
    expect(
      find.descendant(
        of: unitFinder(empty.id),
        matching: find.byType(ChatItemView),
      ),
      findsNothing,
    );
    await release('a14-empty-start');
    await reach(
      'a14-empty-terminal',
      () => live.every(
        (unit) => unit.item.kind == TimelineItemKind.workGroup
            ? unit.item.summary!.activeCount == 0
            : unit.item.outcome != null,
      ),
    );
    await release('a14-empty-terminal');
    await reach(
      'a14-after-empty',
      () => live.any((unit) => unit.item.kind == TimelineItemKind.workGroup),
    );
    final after = live
        .singleWhere((unit) => unit.item.kind == TimelineItemKind.workGroup)
        .id;
    expect(after, isNot(before));
    await capture('a14-empty-separator');
    await release('a14-after-empty');
    await reach(
      'a14-text-readable',
      () => main.any((unit) => unit.id == after) && hasText(_emptyTextAnswer),
    );
    await release('a14-text-readable');
    await reach('a14-before-turn-end', () => live.isEmpty);
    expect(main.where((unit) => unit.id == before), hasLength(1));
    expect(main.where((unit) => unit.id == after), hasLength(1));
    expect(
      itemFinder(empty.id),
      findsNothing,
      reason: 'structural empty text must not paint an empty bubble',
    );
    await release('a14-before-turn-end');
    await idle();
    report['emptySeparatorWorkAtomIds'] = [
      ...await contentIdentitiesForItem(before),
      ...await contentIdentitiesForItem(after),
    ];
  }

  Future<void> verifyImages({
    required String imageWorkItemId,
    TimelineConceptImageInput? input,
    bool missing = false,
  }) async {
    final imageGroup = main.singleWhere((unit) => unit.id == imageWorkItemId);
    expect(imageGroup.item.kind, TimelineItemKind.workGroup);
    expect(imageGroup.item.summary!.memberCount, 4);
    expect(imageGroup.item.summary!.activeCount, 0);
    expect(imageGroup.item.summary!.failedCount, 1);
    expect(imageGroup.item.admissionClosed, isTrue);
    expect(imageGroup.item.members, isNotNull);
    final summary = imageGroup.item.summary!;
    // A folded item carries summary/ref only, not hidden member/media widgets.
    final mountedBefore = lease.groupDisplays
        .where((display) => display.unitId == imageWorkItemId)
        .singleOrNull;
    if (mountedBefore == null) {
      expect(membersOf(imageWorkItemId), isEmpty);
    }
    await expand(imageGroup);
    final mainIds = items.map((item) => item.id).toList();
    final before = lease.olderCursor;
    final liveIds = live.map((unit) => unit.id).toList();
    await contentIdentitiesForItem(imageGroup.id);
    final display = lease.groupDisplays.singleWhere(
      (display) => display.unitId == imageGroup.id,
    );
    expect(display.membersRef, imageGroup.item.members);
    expect(lease.olderCursor, before);
    expect(live.map((unit) => unit.id), orderedEquals(liveIds));
    report['ordinaryDetailWindowObserved'] = true;
    report['readImageResourceIds'] = [
      for (final call in _imageCalls)
        ChatItemPresentation.decode(
          display.atoms.singleWhere((atom) => atom.tool?.callId == call),
        ).attachments.single.id,
    ];
    for (final call in _imageCalls) {
      final atom = display.atoms.singleWhere(
        (atom) => atom.tool?.callId == call,
      );
      final item = ChatItemPresentation.decode(atom);
      expect(item.attachments, hasLength(1));
      final card = itemFinder(atom.id);
      await _until(
        tester,
        () => card.evaluate().isNotEmpty,
        'one real image tool card $call',
      );
      final toggle = find.descendant(
        of: card,
        matching: find.byType(TimelineActivityDisclosure),
      );
      await tap(toggle);
      await _until(
        tester,
        () => find
            .descendant(of: card, matching: find.byType(TimelineImageView))
            .evaluate()
            .any((element) {
              final view = element.widget as TimelineImageView;
              return missing ? view.error != null : view.bytes != null;
            }),
        missing
            ? 'real media resource load failure $call'
            : 'real image bytes $call',
      );
      final views = tester.widgetList<TimelineImageView>(
        find.descendant(of: card, matching: find.byType(TimelineImageView)),
      );
      expect(views, hasLength(1));
      expect(views.single.attachment.id, item.attachments.single.id);
      if (missing) {
        expect(views.single.bytes, isNull);
        expect(views.single.error, isNotNull);
      } else {
        expect(views.single.error, isNull);
        expect(views.single.bytes, isNotEmpty);
      }
    }
    final failed = display.atoms.singleWhere(
      (atom) => atom.tool?.callId == 'concept-image-failed',
    );
    final failedItem = ChatItemPresentation.decode(failed);
    expect(failedItem.attachments, isEmpty);
    expect(failed.lifecycle, isA<TerminalChatAtom>());
    expect(
      (failed.lifecycle as TerminalChatAtom).outcome,
      ChatTerminalOutcome.failed,
    );
    final failedRow = itemFinder(failed.id);
    await _until(
      tester,
      () => failedRow.evaluate().isNotEmpty,
      'directory read failure card',
    );
    await tap(
      find.descendant(
        of: failedRow,
        matching: find.byType(TimelineActivityDisclosure),
      ),
    );
    await _until(
      tester,
      () => hasText('image source is not a regular file'),
      'tool failure distinct from media resource failure',
    );
    await capture('read-images');
    expect(items.map((item) => item.id), orderedEquals(mainIds));
    final afterMedia = observed.unit(imageWorkItemId).item.summary!;
    expect(afterMedia.memberCount, summary.memberCount);
    expect(afterMedia.activeCount, summary.activeCount);
    expect(afterMedia.failedCount, summary.failedCount);
    expect(afterMedia.startedAt, summary.startedAt);
    expect(afterMedia.finishedAt, summary.finishedAt);
    final openHandles = graph.client.budget.used(ResourceKind.chatHandle);
    await observed.closeGroup(display);
    expect(display.atoms, isEmpty);
    expect(display.before, isNull);
    expect(imageGroup.expansion.bodyActive, isFalse);
    await _until(
      tester,
      () => graph.client.budget.used(ResourceKind.chatHandle) < openHandles,
      'collapsed image member scope and media/body owners joined',
    );
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
    if (input != null) {
      final itemValue = items.singleWhere(
        (item) => item.source == InputChatSource(inputId: input.inputId),
      );
      expect(itemValue.kind, TimelineItemKind.text);
      expect(itemValue.atomKind, ChatAtomKind.input);
      expect(itemValue.members, isNull);
      final item = presentation(itemValue);
      await showUnit(itemValue.id);
      final card = itemFinder(itemValue.id);
      await _until(
        tester,
        () => item.attachments.every(
          (attachment) => find
              .byKey(StudioDriverKeys.viewImageThumbnail(attachment.id))
              .evaluate()
              .isNotEmpty,
        ),
        'three decoded real user input thumbnails',
      );
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
      (item) => item.source == InputChatSource(inputId: inputId),
    );
    expect(item.id, input['itemId']);
    expect(item.contentItemId, input['contentItemId']);
    expect(item.kind, TimelineItemKind.text);
    expect(item.atomKind, ChatAtomKind.input);
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
      reopenedUnits.map((unit) => unit.item.kind),
      orderedEquals([
        TimelineItemKind.workGroup,
        TimelineItemKind.text,
        TimelineItemKind.workGroup,
        TimelineItemKind.text,
      ]),
    );
    expect(reopenedUnits.first.id, isNot(reopenedUnits[2].id));
    for (var index = 0; index < reopenedUnits.length; index++) {
      expect(
        await contentIdentitiesForItem(reopenedUnits[index].id),
        orderedEquals(segments[index]),
      );
      if (index > 0) {
        expect(
          main.indexOf(reopenedUnits[index]),
          greaterThan(main.indexOf(reopenedUnits[index - 1])),
        );
      }
    }
    for (final field in [
      'partialItemId',
      'failureItemId',
      'compactionItemId',
    ]) {
      final id = saved[field] as String;
      await showUnit(id);
      expect(items.where((item) => item.id == id), hasLength(1));
      expect(items.singleWhere((item) => item.id == id).position, isNotNull);
    }
    report['reopenedInputId'] = inputId;
    report['ownerGeneration'] = lease.generation;
    await _record(missing ? 'media-missing-complete' : 'reopen-complete');
    await capture('complete');
  }
}
