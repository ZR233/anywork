import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/timeline_observation.dart';

// An explicit, closed synthetic home is prepared outside the app and supplied
// through ANYWORK_HOME. This suite never edits SQLite or copies a message stream.
// Run with cargo xtask test-project --suite desktop --case conversation_read_work.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final input = Platform.environment['ANYWORK_READ_CASES'];
  final output = Platform.environment['ANYWORK_READ_REPORT'];
  if (input == null || output == null) {
    throw StateError('Supply ANYWORK_READ_CASES and ANYWORK_READ_REPORT');
  }
  final cases = (jsonDecode(File(input).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  if (cases.isEmpty) {
    throw StateError('At least one prepared read case is required');
  }
  late AppGraph graph;
  late ProviderContainer container;
  final samples = <Map<String, Object?>>[];

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
    expect(
      graph.client.bootstrapState.value.failure,
      isNull,
      reason: 'The prepared home must bootstrap before measuring reads',
    );
    await _verifyDirectoryObservation(graph);
  });
  tearDownAll(() async {
    try {
      final report = await runStudioShutdown(
        graph.client.transport,
        (_) {},
        remainingMs: 30000,
        closeClient: (deadline) => graph.close(deadline: deadline),
      );
      expect(
        report.shutdown.isClean,
        isTrue,
        reason: report.shutdown.issues.toString(),
      );
      expect(report.shutdown.issues, isEmpty);
      expect(
        report.shutdown.persistence,
        isA<DrainedStudioPendingPersistence>(),
      );
    } finally {
      container.dispose();
      await File(output).writeAsString(
        jsonEncode({'samples': samples, 'timeline': binding.reportData}),
      );
    }
  });

  for (final fixture in cases) {
    final name = fixture['name'] as String;
    final threadId = fixture['threadId'] as String;
    final total = fixture['mainItems'] as int;
    final switchThreadId = fixture['switchThreadId'] as String?;
    testWidgets('$name: bounded cold read, actual layout and independent page', (
      tester,
    ) async {
      addTearDown(() async {
        graph.setConversationPageVisible(false);
        await tester.pumpWidget(const SizedBox());
        expect(
          (await graph.client.conversations.retryCleanup(
            deadline: DateTime.now().add(const Duration(seconds: 5)),
          )).complete,
          isTrue,
        );
      });
      await binding.traceAction(
        () async {
          developer.Timeline.instantSync(
            'conversation.read.start',
            arguments: {'threadId': threadId},
          );
          await graph.client.directoryCommands.selectThread(threadId);
          graph.setConversationPageVisible(true);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const AnyworkApp(enableDesktopHost: false),
            ),
          );
          TimelineDisplayLease? lease() => graph.timeline.lease(threadId);
          await _until(
            tester,
            () => lease()?.firstContentLayout != null,
            'same-generation actual content layout',
          );
          final display = lease()!;
          final observed = TimelineObservation(tester, () => display);
          final first = display.firstContentLayout!;
          expect(display.appliedSets, 1);
          expect(display.loadedCount, greaterThan(0));
          expect(display.loadedCount, lessThan(total));
          expect(find.byType(ChatItemView), findsWidgets);
          final initial = display.loadedCount;
          final mounted = find.byType(ChatItemView).evaluate().length;
          expect(mounted, lessThanOrEqualTo(initial));
          expect(display.hasOlder, isTrue);
          final ids = observed.main.map((unit) => unit.id).toList();
          expect(ids, hasLength(display.loadedCount));
          expect(
            observed.mountedMembers,
            isEmpty,
            reason: 'folded Main admission must not open member windows',
          );
          final beforeCursor = display.olderCursor;
          final view = tester.widget<TimelineView>(find.byType(TimelineView));
          await view.onLoadOlder();
          await tester.pump();
          expect(identical(display, lease()), isTrue);
          expect(display.loadedCount, greaterThan(initial));
          expect(display.olderCursor, isNot(beforeCursor));
          expect(
            observed.main.map((unit) => unit.id).toSet(),
            hasLength(display.loadedCount),
          );
          expect(
            display.controller.messages
                .skip(display.loadedCount - initial)
                .map((item) => item.id),
            ids,
          );
          expect(display.appliedSets, 1);
          expect(display.appliedPrepends, greaterThan(0));
          expect(display.appliedAppends, 0);
          expect(tester.takeException(), isNull);
          samples.add({
            'name': name,
            'threadId': threadId,
            'generation': display.generation,
            'mainItems': total,
            'initialControllerMessages': initial,
            'mountedRows': mounted,
            'afterPageControllerMessages': display.loadedCount,
            'selectionId': first.selectionId,
            'firstContentLayoutMicros': first.elapsedMicros,
          });
          if (switchThreadId != null) {
            developer.Timeline.instantSync('conversation.switch.start');
            await graph.client.directoryCommands.selectThread(switchThreadId);
            await _until(
              tester,
              () =>
                  display.isReleased &&
                  graph.timeline.lease(switchThreadId)?.firstContentLayout !=
                      null,
              'B content and A resource release',
            );
            final intermediate = graph.timeline.lease(switchThreadId)!;
            await graph.client.directoryCommands.selectThread(threadId);
            await _until(
              tester,
              () =>
                  intermediate.isReleased &&
                  lease()?.firstContentLayout != null,
              'new A content and B resource release',
            );
            final reopened = lease()!;
            expect(reopened.generation, greaterThan(display.generation));
            expect(reopened.appliedSets, 1);
            expect(reopened.controller.messages.map((item) => item.id), ids);
            samples.last.addAll({
              'switchThreadId': switchThreadId,
              'switchGeneration': reopened.generation,
              'switchControllerMessages': reopened.loadedCount,
              'switchContentLayoutMicros':
                  reopened.firstContentLayout!.elapsedMicros,
              'oldAReleased': display.isReleased,
              'oldBReleased': intermediate.isReleased,
            });
            developer.Timeline.instantSync('conversation.switch.end');
          }
          developer.Timeline.instantSync('conversation.read.end');
        },
        streams: const ['Dart'],
        reportKey: name,
      );
      // JIT compiler events can fill the VM's fixed ring before the first
      // frame. Record only the official Dart stream needed here and reject
      // incomplete evidence instead of treating a missing initial Set as zero.
      final timeline = binding.reportData![name] as Map<String, dynamic>;
      final events = (timeline['traceEvents'] as List)
          .cast<Map<String, dynamic>>();
      for (final marker in [
        'conversation.read.start',
        'conversation.read.end',
        'conversation.row.build',
        'conversation.admission',
      ]) {
        expect(events.where((event) => event['name'] == marker), isNotEmpty);
      }
      final applied = events
          .where((event) => event['name'] == 'conversation.applied')
          .map((event) => event['args'] as Map<String, dynamic>);
      expect(
        applied.singleWhere(
          (args) =>
              args['placement'] == 'set' &&
              args['generation'] == samples.last['generation'],
        )['acceptedEntries'],
        samples.last['initialControllerMessages'],
      );
      expect(
        applied.where((args) => args['placement'] == 'prepend'),
        isNotEmpty,
      );
      expect(
        applied.where((args) => args['placement'] == 'set').length,
        switchThreadId == null ? 1 : 3,
      );
    });
  }
}

Future<void> _verifyDirectoryObservation(AppGraph graph) async {
  final observation = graph.client.threadDirectory.observeThreads(
    const DirectoryQuery(),
    DirectoryWindow(limit: 1),
  );
  try {
    final state = await observation.state
        .waitFor(
          (state) => state.frame != null || state.error != null || state.closed,
        )
        .timeout(const Duration(seconds: 30));
    if (state.error case final error?) {
      fail('Prepared thread directory failed: $error');
    }
    expect(
      state.closed,
      isFalse,
      reason: 'Prepared thread directory closed before its initial frame',
    );
    expect(
      state.frame,
      isNotNull,
      reason: 'Prepared thread directory must publish an initial frame',
    );
  } finally {
    await observation.release();
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > const Duration(seconds: 30)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  }
}
