import 'dart:typed_data';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_projection.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_resting_cat.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/contracts/stamps.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/timeline_observation.dart';

Widget _host(Widget child, {double width = 720, double scale = 1}) =>
    MaterialApp(
      theme: pureStudioTheme(),
      locale: const Locale('zh'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

Finder _workTitle(Finder header) => find.descendant(
  of: header,
  matching: find.byKey(const ValueKey('work-header-title')),
);

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
const _thinking = ConversationActivityView(
  identity: 'thinking',
  kind: ConversationActivityKind.thinking,
);

void main() {
  testWidgets('imported Work with unknown times does not invent a duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CompletionRunView(
          id: 'imported',
          timing: const WorkTiming(startedAt: null),
          location: WorkDisplayLocation.history,
          initiallyExpanded: false,
          childBuilder: (_) => const SizedBox(),
        ),
      ),
    );
    expect(find.text('工作记录'), findsOneWidget);
    expect(find.text('工作了不到 1 秒'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'one Work clock includes idle and overnight time without reading members',
    (tester) async {
      var seconds = 1000;
      var reads = 0;
      await tester.pumpWidget(
        _host(
          CompletionRunView(
            id: 'clock',
            timing: const WorkTiming(startedAt: 1000),
            location: WorkDisplayLocation.live,
            executionPresent: false,
            initiallyExpanded: false,
            now: () => _at(seconds),
            childBuilder: (_) {
              reads++;
              return const Text('members');
            },
          ),
        ),
      );
      expect(find.text('工作记录'), findsOneWidget);
      expect(find.text('执行了不到 1 秒'), findsOneWidget);
      seconds = 1125;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('执行了 2 分 5 秒'), findsOneWidget);
      seconds += 86400;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('执行了 1442 分 5 秒'), findsOneWidget);
      expect(
        tester
            .widget<TimelineActivityIndicator>(
              find.byType(TimelineActivityIndicator),
            )
            .active,
        isFalse,
      );
      expect(reads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'hidden Work clock resumes from the same start without periodic refresh',
    (tester) async {
      var seconds = 1000;
      Widget view(bool visible) => _host(
        TickerMode(
          enabled: visible,
          child: CompletionRunView(
            id: 'hidden',
            timing: const WorkTiming(startedAt: 1000),
            location: WorkDisplayLocation.live,
            initiallyExpanded: false,
            now: () => _at(seconds),
            childBuilder: (_) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpWidget(view(false));
      seconds = 1125;
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(view(true));
      expect(find.text('执行了 2 分 5 秒'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final location in WorkDisplayLocation.values) {
    testWidgets(
      'sealed Work is frozen in $location and expands only on demand',
      (tester) async {
        var seconds = 1125;
        var reads = 0;
        await tester.pumpWidget(
          _host(
            CompletionRunView(
              id: 'sealed',
              timing: const WorkTiming(startedAt: 1000, finishedAt: 1125),
              state: DisplayBlockState.sealed,
              location: location,
              hasUnfinishedMembers: true,
              thinkingSummary: 'must stay out of history',
              activity: _thinking,
              executionPresent: true,
              initiallyExpanded: false,
              now: () => _at(seconds),
              childBuilder: (_) {
                reads++;
                return const Text('original member result');
              },
            ),
          ),
        );
        final header = find.byKey(
          const ValueKey('completion-run-header:sealed'),
        );
        expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
        expect(find.text('must stay out of history'), findsNothing);
        expect(find.byType(TimelineActivityIndicator), findsNothing);
        expect(reads, 0);
        seconds += 86400;
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
        expect(reads, 0);
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(find.text('original member result'), findsOneWidget);
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(find.text('original member result'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final (end, label) in [
    (1000, '工作了不到 1 秒'),
    (1009, '工作了 9 秒'),
    (1120, '工作了 2 分'),
    (1125, '工作了 2 分 5 秒'),
    (999, '工作了不到 1 秒'),
  ]) {
    testWidgets(
      'completed interval $end formats and clamps a backwards wall clock',
      (tester) async {
        await tester.pumpWidget(
          _host(
            CompletionRunView(
              id: 'format',
              timing: WorkTiming(startedAt: 1000, finishedAt: end),
              location: WorkDisplayLocation.history,
              initiallyExpanded: false,
              childBuilder: (_) => const SizedBox(),
            ),
          ),
        );
        expect(find.text(label), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final (width, scale) in [(720.0, 1.0), (360.0, 1.6)]) {
    testWidgets('live summary and clock share one row at $width/$scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CompletionRunView(
            id: 'narrow',
            timing: const WorkTiming(startedAt: 1000),
            thinkingSummary:
                '核对 **组件边界** 与 `LiveStatusBar` [本组摘要](https://example.com) ' *
                5,
            location: WorkDisplayLocation.live,
            executionPresent: true,
            activity: _thinking,
            initiallyExpanded: false,
            now: () => _at(1125),
            childBuilder: (_) => const Text('exact body'),
          ),
          width: width,
          scale: scale,
        ),
      );
      final header = find.byKey(const ValueKey('completion-run-header:narrow'));
      expect(find.byType(TimelineReasoningSummary), findsOneWidget);
      expect(find.text('执行了 2 分 5 秒'), findsOneWidget);
      final paragraph = timelineGroupTitleParagraph(tester, _workTitle(header));
      expect(paragraph.maxLines, 1);
      expect(paragraph.overflow, TextOverflow.ellipsis);
      expect(find.byType(TimelineRestingCat), findsOneWidget);
      await tester.tap(_workTitle(header));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('exact body'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'history members follow Timeline without a private vertical viewport',
    (tester) async {
      await tester.pumpWidget(
        _host(
          CompletionRunView(
            id: 'history',
            timing: const WorkTiming(startedAt: 1000, finishedAt: 1125),
            location: WorkDisplayLocation.history,
            initiallyExpanded: true,
            childBuilder: (_) => const SizedBox(
              height: 500,
              child: Text('member failure and cancellation details'),
            ),
          ),
        ),
      );
      expect(find.byType(Scrollable), findsNothing);
      expect(
        tester.getSize(find.byType(CompletionRunView)).height,
        greaterThan(500),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'current group retains Markdown through tool phases and clears at the next group',
    (tester) async {
      final h = _LiveHarness();
      addTearDown(h.dispose);
      h.now = () => _at(1125);
      h.currentWorkId = 'work';
      h.blocks = [_work('work', thought: '**本组** `最新摘要`')];
      h.notices = [const ExecutionLiveNotice(_thinking)];
      await tester.pumpWidget(h.host());
      expect(find.byType(TimelineReasoningSummary), findsOneWidget);
      expect(find.byType(ConversationActivityStatus), findsNothing);
      expect(find.text('执行了 2 分 5 秒'), findsOneWidget);
      expect(h.content.reads, 0);
      h.blocks = [
        _work('older', state: DisplayBlockState.sealed),
        _work('next'),
      ];
      h.currentWorkId = 'next';
      await tester.pumpWidget(h.host());
      expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
      expect(find.byType(TimelineReasoningSummary), findsNothing);
      expect(find.text('思考中'), findsOneWidget);
      expect(h.content.reads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'critical notices remain separate from the group and do not reset its clock',
    (tester) async {
      final h = _LiveHarness();
      addTearDown(h.dispose);
      h.now = () => _at(1125);
      h.currentWorkId = 'work';
      h.blocks = [_work('work')];
      h.notices = [
        const ExecutionLiveNotice(_thinking),
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'stopping',
            kind: ConversationActivityKind.stopping,
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(find.byType(CompletionRunView), findsOneWidget);
      expect(find.byType(ConversationActivityStatus), findsOneWidget);
      expect(find.text('执行了 2 分 5 秒'), findsOneWidget);
      expect(h.content.reads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

LiveDisplayBlock _work(
  String id, {
  DisplayBlockState state = DisplayBlockState.open,
  String? thought,
}) => LiveDisplayBlock(
  id: id,
  blockOrder: id == 'older' ? 1 : 2,
  state: state,
  source: const ForegroundTurnChatSource(turnId: 'turn'),
  thinkingSummary: thought,
  body: WorkDisplayBlock(
    timing: WorkTiming(
      startedAt: 1000,
      finishedAt: state == DisplayBlockState.sealed ? 1125 : null,
    ),
    members: DisplayBlockRef(databaseId: 'db', blockId: id),
  ),
);

class _Content extends Fake implements ConversationContent {
  int reads = 0;
  @override
  AttemptId get currentAttemptId => const AttemptId(1);
  @override
  ConversationQueryScope openScope({required int generation}) {
    reads++;
    throw StateError('Collapsed metadata must not read members or originals');
  }
}

class _LiveHarness {
  final content = _Content();
  final live = ValueNotifier<TailSnapshot?>(null);
  final images = TimelineImageResources(threadId: 'thread');
  final expansions = <String, TimelineExpansionIntent>{};
  List<LiveDisplayBlock> blocks = [];
  List<LiveStatusNotice> notices = [];
  String? currentWorkId;
  bool executionPresent = true;
  DateTime Function()? now;
  int revision = 0;
  Widget host() {
    live.value = TailSnapshot(
      currentWorkId: currentWorkId,
      revision: ++revision,
      layoutRevision: revision,
      readyFrontier: 0,
      executionPresent: executionPresent,
      blocks: blocks,
    );
    final projected = LiveStatusProjection.projectSurfaceAndTimelineWork(
      latestWindow: live.value,
      effectiveOutputWindow: live.value,
      effectiveTimelineWindow: live.value,
      activeTurnId: 'turn',
      outputPaging: const LatestLiveWindow(),
      rawNotices: notices,
    );
    final presenting = projected.surface == null
        ? null
        : LiveStatusPresenting(
            surface: projected.surface!,
            effectiveWindow: live.value,
            paging: const LatestLiveWindow(),
            showInteractionDetails: false,
          );
    final workSlice = LiveStatusTimelineWorkSlice(
      workBlocks: projected.timelineWorkBlocks,
      effectiveWindow: live.value,
    );
    Widget section(ConversationLiveSection section) =>
        ConversationCurrentConnector(
          section: section,
          threadId: 'thread',
          content: content,
          now: now,
          presenting: section == ConversationLiveSection.output
              ? presenting
              : null,
          workSlice: section == ConversationLiveSection.work ? workSlice : null,
          images: images,
          readAttachment: (_) async => Uint8List(0),
          isDisplayActive: () => true,
          liveUnit: (block, executionPresent) => TimelineDisplayUnit.live(
            block: block,
            executionPresent: executionPresent,
            expansion: expansions.putIfAbsent(
              block.id,
              TimelineExpansionIntent.new,
            ),
          ),
        );
    return _host(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          section(ConversationLiveSection.work),
          section(ConversationLiveSection.output),
        ],
      ),
    );
  }

  void dispose() {
    for (final intent in expansions.values) {
      intent.retire();
      intent.dispose();
    }
    images.release();
    live.dispose();
  }
}
