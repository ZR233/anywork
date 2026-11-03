import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
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

import 'support/fixture_gate.dart';
import 'support/presentation_capture.dart';
import 'support/timeline_concept_images.dart';

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

  // Borrow existing immutable values only. None of these getters opens a query,
  // runs a body read, classifies atoms, or keeps a second presentation list.
  List<TimelineDisplayUnit> get main => [
    for (final message in lease.controller.messages)
      if (message.metadata?[timelineDisplayUnitKey]
          case final TimelineDisplayUnit unit)
        unit,
  ];
  List<TimelineDisplayUnit> get live => lease.liveUnits.value;
  Iterable<ChatAtom> get atoms => main.expand((unit) => unit.members);
  bool hasText(String text) =>
      find.textContaining(text, findRichText: true).evaluate().isNotEmpty;
  Finder unitFinder(String id) => find.byWidgetPredicate(
    (widget) =>
        (widget is TimelineDisplayUnitView && widget.unit.id == id) ||
        (widget is ChatItemView &&
            widget.item.displayUnit == null &&
            widget.item.atom?.id == id),
  );
  Finder itemFinder(String id) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.item.atom?.id == id,
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
      'kind': value.kind.name,
      'live': value.live,
      'memberCount': value.memberCount,
      'activeCount': value.activeCount,
      'members': [for (final atom in value.members) atom.id],
      'toolCallIds': [
        for (final atom in value.members)
          if (atom.tool != null) atom.tool!.callId,
      ],
      'startedAt': value.startedAt,
      'finishedAt': value.finishedAt,
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
      if (value.live || value.kind != TimelineUnitKind.work) continue;
      final header = tester.widget<TimelineActivityRow>(
        find.byKey(ValueKey('source-unit-header:${value.id}')),
      );
      expect(header.active, isFalse, reason: 'history headers never spin');
      if (value.startedAt == null ||
          value.finishedAt == null ||
          value.olderCursor != null) {
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
        state.isLoadingOlder ||
        target.activity.value.loading;
    final error =
        state?.connectionError ??
        state?.olderError ??
        target.activity.value.error ??
        target.queryCleanupError;
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
      'residentMainMembers': main.fold<int>(
        0,
        (count, unit) => count + unit.members.length,
      ),
      'residentLiveMembers': target.liveUnits.value.fold<int>(
        0,
        (count, unit) => count + unit.members.length,
      ),
      'residentMeaning': 'currently resident members, not cumulative delivery',
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
    final member = original.members.single;
    final source = original.source;
    expect(source, isA<ForegroundTurnChatSource>());
    final activeTurnId = (source as ForegroundTurnChatSource).turnId;
    expect(original.sourceLifecycle, isA<ActiveChatSource>());
    expect(member.lifecycle, isA<ActiveChatAtom>());
    expect(member.contents, isNotEmpty);
    expect(before.content.current.value?.activeTurn?.id, activeTurnId);
    expect(before.content.current.value?.logicalStatus.isActive, isTrue);
    final originalCurrent = before.currentDisplay!;
    expect(originalCurrent.isCurrent, isTrue);
    final historyIds = atoms.map((atom) => atom.id).toList();
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
                unit.source == source &&
                unit.members.any(
                  (atom) =>
                      atom.id == member.id && atom.lifecycle is ActiveChatAtom,
                ),
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
    expect(reopened.source, source);
    expect(reopened.sourceLifecycle, isA<ActiveChatSource>());
    expect(reopened.kind, original.kind);
    expect(reopened.live, isTrue);
    expect(reopened.closedForAdmission, isFalse);
    expect(reopened.activeCount, 1);
    expect(reopened.members, hasLength(1));
    final resumed = reopened.members.single;
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
    expect(atoms.map((atom) => atom.id), orderedEquals(historyIds));
    expect(atoms.where((atom) => atom.id == member.id), isEmpty);
    expect(main.where((unit) => unit.kind == TimelineUnitKind.work), isEmpty);
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
      'historyAtomIds': historyIds,
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
          tester
              .widgetList<TimelineDisplayUnitView>(
                find.byType(TimelineDisplayUnitView),
              )
              .where((view) => !view.unit.live)
              .map((view) => main.indexWhere((unit) => unit.id == view.unit.id))
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
    await showUnit(unit.id);
    final header = find.byKey(ValueKey('source-unit-header:${unit.id}'));
    if (unit.expansion.expanded != true) await tap(header);
    await _until(
      tester,
      () => lease.groupDisplays.any(
        (display) => display.unitId == unit.id && display.expanded,
      ),
      'expanded real work segment',
    );
  }

  Future<void> journey(String project) async {
    await _until(tester, () => !lease.hasOlder, 'empty conversation EOF');
    expect(lease.controller.messages, isEmpty);
    expect(live, isEmpty);
    expect(find.byType(ConversationCurrentConnector), findsNothing);
    await capture('empty');
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
    expect(main.where((unit) => unit.kind == TimelineUnitKind.work), isEmpty);
    expect(find.byType(TimelineDisplayUnitView), findsNothing);
    await capture('thinking');
    await release('thinking');

    await reach(
      'workgroup',
      () =>
          live.length == 1 &&
          live.single.memberCount == 1 &&
          live.single.members.single.kind == ChatAtomKind.reasoning,
    );
    var g1 = live.single.id;
    final source = live.single.source;
    expect(live.single.live, isTrue);
    expect(
      tester
          .widget<ConversationCurrentConnector>(
            find.byType(ConversationCurrentConnector),
          )
          .units,
      same(lease.liveUnits),
    );
    expect(live.single.closedForAdmission, isFalse);
    expect(live.single.activeCount, 1);
    expect(main.where((unit) => unit.id == g1), isEmpty);
    expect(unitFinder(g1), findsOneWidget);
    await capture('workgroup');
    // A new owner may build different group IDs. Bind subsequent same-owner
    // assertions to its real unit; never compare old and new group keys.
    g1 = (await reopenActiveWorkgroup()).id;
    await capture('workgroup-reopened');
    await release('workgroup');

    await reach(
      'group-idle',
      () => live.any(
        (unit) =>
            unit.id == g1 && unit.memberCount == 4 && unit.activeCount == 0,
      ),
    );
    final quiet = live.single;
    expect(quiet.closedForAdmission, isFalse);
    expect(quiet.live, isTrue);
    expect(
      tester
          .widget<TimelineActivityRow>(
            find.byKey(ValueKey('source-unit-header:$g1')),
          )
          .label,
      '思考中',
    );
    expect(main.where((unit) => unit.id == g1), isEmpty);
    expect(
      quiet.members
          .where((atom) => atom.tool != null)
          .map((atom) => atom.tool!.callId),
      unorderedEquals([
        'concept-read-call',
        'concept-command-a',
        'concept-command-b',
      ]),
    );
    expect(
      quiet.members.every((atom) => atom.lifecycle is TerminalChatAtom),
      isTrue,
    );
    await capture('group-idle');
    await release('group-idle');

    await reach(
      'text',
      () =>
          main.any((unit) => unit.id == g1) &&
          live.any((unit) => unit.kind == TimelineUnitKind.text) &&
          hasText(_textA),
    );
    expect(main.where((unit) => unit.id == g1), hasLength(1));
    expect(
      main.where(
        (unit) => unit.source == source && unit.kind == TimelineUnitKind.text,
      ),
      isEmpty,
    );
    final a = live.single.id;
    expect(live.single.members.single.lifecycle, isA<ActiveChatAtom>());
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
      () => live.length == 1 && live.single.kind == TimelineUnitKind.work,
    );
    final g2 = live.single.id;
    expect(g2, isNot(g1));
    expect(live.single.source, source);
    expect(
      main.where((unit) => unit.id == g1).single.memberCount,
      quiet.memberCount,
    );
    expect(main.where((unit) => unit.id == g2), isEmpty);
    await capture('next-group');
    await release('next-group');
    await reach(
      'second-group-idle',
      () =>
          live.length == 1 &&
          live.single.id == g2 &&
          live.single.activeCount == 0,
    );
    expect(live.single.closedForAdmission, isFalse);
    await release('second-group-idle');
    await reach(
      'second-text',
      () =>
          main.any((unit) => unit.id == g2) &&
          live.length == 1 &&
          live.single.kind == TimelineUnitKind.text &&
          hasText(_textB),
    );
    final b = live.single.id;
    await release('second-text');
    await reach(
      'before-turn-end',
      () => live.isEmpty && main.any((unit) => unit.id == b),
    );
    expect(
      main.where((unit) => unit.source == source).map((unit) => unit.id),
      orderedEquals([g1, a, g2, b]),
    );
    await release('before-turn-end');
    await idle();
    final firstGroup = main.singleWhere((unit) => unit.id == g1);
    await expand(firstGroup);
    final reasoningBody = find.descendant(
      of: find.descendant(
        of: unitFinder(g1),
        matching: itemFinder(
          firstGroup.members
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
    report['coreAtomSegments'] = [
      for (final id in [g1, a, g2, b])
        main
            .singleWhere((unit) => unit.id == id)
            .members
            .map((atom) => atom.id)
            .toList(),
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
              .expand((unit) => unit.members)
              .where(
                (atom) =>
                    [
                      ..._imageCalls,
                      'concept-image-failed',
                    ].contains(atom.tool?.callId) &&
                    atom.lifecycle is TerminalChatAtom,
              )
              .length ==
          4,
    );
    await capture('images-live');
    await release('images-ready');
    await idle();
    await _until(
      tester,
      () => hasText(_imageDone),
      'real image continuation answer',
    );
    await verifyImages(input: input);

    await submit(_failedPrompt);
    await reach(
      'failed-partial',
      () =>
          live.any((unit) => unit.kind == TimelineUnitKind.text) &&
          hasText(_partial),
    );
    final partialAtom = live.single.members.single.id;
    await capture('failed-partial');
    await release('failed-partial');
    await idle();
    await _until(
      tester,
      () => atoms.any(
        (atom) => atom.id == partialAtom && atom.lifecycle is TerminalChatAtom,
      ),
      'failed partial retained',
    );
    await _until(
      tester,
      () => atoms.any(
        (atom) =>
            atom.kind == ChatAtomKind.turnReceipt &&
            atom.payload != null &&
            (ChatItemPresentation.decode(atom).data['outcome']
                    as Map)['kind'] ==
                'failed',
      ),
      'independent reliable failed Turn receipt',
    );
    final failure = atoms.lastWhere(
      (atom) =>
          atom.kind == ChatAtomKind.turnReceipt &&
          (ChatItemPresentation.decode(atom).data['outcome'] as Map)['kind'] ==
              'failed',
    );
    final failureItem = ChatItemPresentation.decode(failure);
    expect((failureItem.data['outcome'] as Map)['kind'], 'failed');
    expect(failure.id, isNot(partialAtom));
    await showUnit(
      main
          .singleWhere(
            (unit) => unit.members.any((atom) => atom.id == partialAtom),
          )
          .id,
    );
    await _until(
      tester,
      () => hasText(_partial),
      'failed partial still readable',
    );
    await showUnit(
      main
          .singleWhere(
            (unit) => unit.members.any((atom) => atom.id == failure.id),
          )
          .id,
    );
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
    report['partialAtomId'] = partialAtom;
    report['failureAtomId'] = failure.id;
    // A new real input after failure must still traverse the production composer.
    await overlap();
    await emptyText();
    await idle();
    await capture('idle');
    await _record('journey-complete');
    report['readImageResourceIds'] = imageResourceIds();
    report['coreMemberCounts'] = [quiet.memberCount, 1];
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
    List<ChatAtom> activeCompactions() => [
      for (final atom in owner.content.current.value?.atoms ?? <ChatAtom>[])
        if (atom.kind == ChatAtomKind.compaction &&
            atom.lifecycle is ActiveChatAtom)
          atom,
    ];
    Finder currentUnit(TimelineDisplayUnit unit) => find.descendant(
      of: currentConnector,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is TimelineDisplayUnitView && identical(widget.unit, unit),
      ),
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
    await reach('compacting', () {
      final active = activeCompactions();
      final units = owner.liveUnits.value;
      return active.length == 1 &&
          units.length == 1 &&
          units.single.members.any((atom) => atom.id == active.single.id) &&
          currentRows(units.single).evaluate().length == 1;
    });
    expect(lease, same(owner));
    expect(threadId, selectedThread);
    final active = activeCompactions().single;
    final unit = owner.liveUnits.value.single;
    expect(active.source, isA<OperationChatSource>());
    expect(
      owner.content.current.value!.sources
          .singleWhere((source) => source.source == active.source)
          .lifecycle,
      isA<ActiveChatSource>(),
    );
    expect(unit.kind, TimelineUnitKind.receipt);
    expect(unit.live, isTrue);
    expect(unit.source, active.source);
    expect(unit.sourceLifecycle, isA<ActiveChatSource>());
    expect(unit.members.single.id, active.id);
    expect(unit.members.single.lifecycle, isA<ActiveChatAtom>());
    expect(unit.memberCount, 1);
    expect(main.where((value) => value.source == active.source), isEmpty);
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
      'atomId': active.id,
      'unitId': unit.id,
      'unitKind': unit.kind.name,
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
    final prior = atoms
        .where((atom) => atom.kind == ChatAtomKind.compaction)
        .map((atom) => atom.id)
        .toSet();
    await release('compacting');
    await _until(
      tester,
      () => atoms.any(
        (atom) =>
            atom.kind == ChatAtomKind.compaction &&
            !prior.contains(atom.id) &&
            atom.lifecycle is TerminalChatAtom,
      ),
      'real completed compaction receipt',
    );
    await idle();
    final receipt = atoms
        .where(
          (atom) =>
              atom.kind == ChatAtomKind.compaction && !prior.contains(atom.id),
        )
        .single;
    expect(receipt.lifecycle, isA<TerminalChatAtom>());
    report['compactionAtomId'] = receipt.id;
    final completedUnit = main.singleWhere(
      (unit) => unit.members.any((atom) => atom.id == receipt.id),
    );
    expect(completedUnit.kind, TimelineUnitKind.receipt);
    expect(completedUnit.live, isFalse);
    expect(completedUnit.members.single.id, receipt.id);
    expect(completedUnit.memberCount, 1);
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
      () => live.length == 1 && live.single.kind == TimelineUnitKind.work,
    );
    final work = live.single.id;
    final reason = live.single.members.single.id;
    await release('a07-reasoning-start');
    await reach(
      'a07-text-start',
      () =>
          live.length == 2 &&
          live.any((unit) => unit.kind == TimelineUnitKind.text) &&
          hasText('正文已经开始且可以读取，'),
    );
    final text = live
        .singleWhere((unit) => unit.kind == TimelineUnitKind.text)
        .id;
    expect(
      live.singleWhere((unit) => unit.id == work).members.single.lifecycle,
      isA<ActiveChatAtom>(),
    );
    expect(main.where((unit) => unit.id == work || unit.id == text), isEmpty);
    await release('a07-text-start');
    await reach('a07-text-readable', () => hasText(_overlapText));
    await capture('a07-late-reasoning');
    await release('a07-text-readable');
    await reach(
      'a07-text-terminal',
      () => live.any(
        (unit) =>
            unit.id == text &&
            unit.members.every((atom) => atom.lifecycle is TerminalChatAtom),
      ),
    );
    expect(
      live.singleWhere((unit) => unit.id == work).members.single.id,
      reason,
    );
    expect(live.singleWhere((unit) => unit.id == work).activeCount, 1);
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
      () => live.length == 1 && live.single.activeCount == 0,
    );
    final before = live.single.id;
    await release('a14-before-empty');
    await reach('a14-empty-start', () => main.any((unit) => unit.id == before));
    // Structural empty text is allowed in owner metadata; never an empty bubble.
    final empty = live.singleWhere(
      (unit) => unit.kind == TimelineUnitKind.text,
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
      () => live.every((unit) => unit.activeCount == 0),
    );
    await release('a14-empty-terminal');
    await reach(
      'a14-after-empty',
      () => live.any((unit) => unit.kind == TimelineUnitKind.work),
    );
    final after = live
        .singleWhere((unit) => unit.kind == TimelineUnitKind.work)
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
      itemFinder(empty.members.single.id),
      findsNothing,
      reason: 'structural empty text must not paint an empty bubble',
    );
    await release('a14-before-turn-end');
    await idle();
    report['emptySeparatorWorkAtomIds'] = [
      ...main
          .singleWhere((unit) => unit.id == before)
          .members
          .map((atom) => atom.id),
      ...main
          .singleWhere((unit) => unit.id == after)
          .members
          .map((atom) => atom.id),
    ];
  }

  List<String> imageResourceIds() => [
    for (final call in _imageCalls)
      ChatItemPresentation.decode(
        atoms.singleWhere((atom) => atom.tool?.callId == call),
      ).attachments.single.id,
  ];

  Future<void> verifyImages({
    TimelineConceptImageInput? input,
    bool missing = false,
  }) async {
    final imageGroup = main.singleWhere(
      (unit) =>
          unit.members.any((atom) => atom.tool?.callId == _imageCalls.first),
    );
    await expand(imageGroup);
    final before = lease.olderCursor;
    final liveIds = live.map((unit) => unit.id).toList();
    // Use the production earlier-process button when the bounded group has a
    // continuation, not a Turn Children query or a test-owned pager.
    final earlier = find.byKey(ValueKey('source-unit-older:${imageGroup.id}'));
    if (earlier.evaluate().isNotEmpty) {
      final intent = imageGroup.expansion;
      final hadPage = intent.hasPage;
      final prior = intent.before;
      await tap(earlier);
      await _until(
        tester,
        () =>
            !intent.loading &&
            (intent.error != null ||
                (intent.hasPage && (!hadPage || intent.before != prior))),
        'ordinary completion-position detail window',
      );
      expect(intent.error, isNull);
      expect(intent.completionAnchor, isNotNull);
      expect(lease.olderCursor, before);
      expect(live.map((unit) => unit.id), orderedEquals(liveIds));
      report['ordinaryDetailWindowObserved'] = true;
    }
    for (final call in _imageCalls) {
      final atom = atoms.singleWhere((atom) => atom.tool?.callId == call);
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
    final failed = atoms.singleWhere(
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
    if (input != null) {
      final atom = atoms.singleWhere(
        (atom) => atom.source == InputChatSource(inputId: input.inputId),
      );
      final item = ChatItemPresentation.decode(atom);
      final unit = main.singleWhere(
        (unit) => unit.members.any((member) => member.id == atom.id),
      );
      await showUnit(unit.id);
      final card = itemFinder(atom.id);
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
        atom: atom,
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
    await capture('read-images');
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
    // UI-driven history demand. No cold-open comparison of display/group keys.
    final target = find.byWidgetPredicate(
      (widget) =>
          widget is ChatItemView &&
          widget.item.atom?.source == InputChatSource(inputId: inputId),
    );
    await reveal(target);
    final atom = atoms.singleWhere(
      (atom) => atom.source == InputChatSource(inputId: inputId),
    );
    expect(atom.id, input['atomId']);
    expect(atom.completionItemId, input['completionItemId']);
    final attachments = ChatItemPresentation.decode(atom).attachments;
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
    await _until(
      tester,
      () => atoms.any((atom) => atom.tool?.callId == _imageCalls.first),
      'saved image tool atoms',
    );
    expect(
      imageResourceIds(),
      orderedEquals((saved['readImageResourceIds'] as List).cast<String>()),
    );
    await verifyImages(missing: missing);
    final segments = (saved['coreAtomSegments'] as List)
        .map((segment) => (segment as List).cast<String>())
        .toList();
    await reveal(
      find.byWidgetPredicate(
        (widget) =>
            widget is TimelineDisplayUnitView &&
            widget.unit.members.any((atom) => atom.id == segments.first.first),
      ),
    );
    final reopenedUnits = [
      for (final segment in segments)
        main.singleWhere(
          (unit) => unit.members.any((atom) => atom.id == segment.first),
        ),
    ];
    expect(
      reopenedUnits.map((unit) => unit.kind),
      orderedEquals([
        TimelineUnitKind.work,
        TimelineUnitKind.text,
        TimelineUnitKind.work,
        TimelineUnitKind.text,
      ]),
    );
    expect(reopenedUnits.first.id, isNot(reopenedUnits[2].id));
    for (var index = 0; index < reopenedUnits.length; index++) {
      expect(
        reopenedUnits[index].members.map((atom) => atom.id),
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
      'partialAtomId',
      'failureAtomId',
      'compactionAtomId',
    ]) {
      final id = saved[field] as String;
      // Stable atom/item identities, not previous owner-local group keys.
      await reveal(
        find.byWidgetPredicate(
          (widget) => widget is ChatItemView && widget.item.atom?.id == id,
        ),
        unitId: main
            .singleWhere((unit) => unit.members.any((atom) => atom.id == id))
            .id,
      );
      expect(atoms.where((atom) => atom.id == id), hasLength(1));
    }
    report['readImageResourceIds'] = imageResourceIds();
    report['reopenedInputId'] = inputId;
    report['ownerGeneration'] = lease.generation;
    await _record(missing ? 'media-missing-complete' : 'reopen-complete');
    await capture('complete');
  }
}
