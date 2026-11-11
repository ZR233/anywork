import 'dart:typed_data';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state_machine.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_clock.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_resting_cat.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/contracts/stamps.dart';
import 'package:gpt_markdown/custom_widgets/custom_divider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/timeline_observation.dart';
import '../support/chat_fixtures.dart';

WorkSummary _summary({
  int? createdAt = 1000,
  int? elapsedMs = 125000,
  int total = 4,
  int running = 0,
  int waiting = 0,
  int failed = 0,
  int cancelled = 0,
  int transferred = 0,
  String? thought,
}) => WorkSummary(
  unavailable: 0,
  total: total,
  terminal: total - running - waiting,
  running: running,
  waiting: waiting,
  failed: failed,
  cancelled: cancelled,
  transferred: transferred,
  // A deliberately different legacy active duration must never reach the title.
  durationMs: 9000,
  createdAt: createdAt,
  elapsedMs: elapsedMs,
  thinkingSummary: thought,
);

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

void main() {
  testWidgets(
    'sealed pending Work freezes elapsed and is neither running nor unrestored',
    (tester) async {
      var now = DateTime.fromMillisecondsSinceEpoch(1125000);
      await tester.pumpWidget(
        _host(
          CompletionRunView(
            id: 'sealed-pending',
            state: DisplayBlockState.sealed,
            location: WorkDisplayLocation.live,
            executionPresent: false,
            summary: _summary(running: 2, waiting: 1),
            initiallyExpanded: false,
            now: () => now,
            childBuilder: (_) => const Text('sealed rows'),
          ),
          width: 360,
          scale: 1.6,
        ),
      );
      expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
      expect(find.textContaining('尚未恢复'), findsNothing);
      expect(
        tester
            .widget<TimelineActivityClock>(find.byType(TimelineActivityClock))
            .running,
        isFalse,
      );
      expect(
        tester
            .widget<TimelineActivityIndicator>(
              find.byType(TimelineActivityIndicator),
            )
            .active,
        isFalse,
      );
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final (width, scale) in [(720.0, 1.0), (390.0, 1.6), (360.0, 1.6)]) {
    testWidgets(
      'collapsed live Work is one row with reserved duration at $width/$scale',
      (tester) async {
        var reads = 0;
        const thought = '这是一条很长的有界思考概要，用来证明窄窗优先省略概要而不是时间和展开操作';
        await tester.pumpWidget(
          _host(
            CompletionRunView(
              id: 'row',
              location: WorkDisplayLocation.live,
              summary: _summary(thought: thought),
              executionPresent: true,
              initiallyExpanded: false,
              now: () => DateTime.fromMillisecondsSinceEpoch(1125000),
              childBuilder: (_) {
                reads++;
                return const Text('成员正文');
              },
            ),
            width: width,
            scale: scale,
          ),
        );
        expect(reads, 0);
        expect(find.text('成员正文'), findsNothing);
        expect(find.text('工作记录 · 4 项'), findsNothing);
        final label = find.text(thought);
        final elapsed = find.text('执行了 2 分 5 秒');
        final arrow = find.byIcon(Icons.chevron_right_rounded);
        expect(elapsed, findsOneWidget);
        expect(tester.widget<Text>(label).maxLines, 1);
        final a = tester.getRect(label);
        final b = tester.getRect(elapsed);
        final c = tester.getRect(arrow);
        expect(a.right, lessThanOrEqualTo(b.left));
        expect((a.center.dy - b.center.dy).abs(), lessThan(2));
        expect(b.right, lessThanOrEqualTo(c.left));
        expect(c.right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final bounded in [true, false]) {
    testWidgets(
      'live Work scrolls all members with ${bounded ? '162px' : 'unbounded'} parent height',
      (tester) async {
        var reads = 0;
        final expanded = <bool>[];
        final work = CompletionRunView(
          id: 'constrained',
          location: WorkDisplayLocation.live,
          summary: _summary(createdAt: null, thought: '当前工作概要'),
          executionPresent: true,
          initiallyExpanded: false,
          onExpandedChanged: expanded.add,
          childBuilder: (_) {
            reads++;
            return Column(
              children: [
                for (var index = 0; index < 12; index++)
                  TimelineActivityRow(
                    label: '成员 $index',
                    icon: Icons.terminal,
                    expandable: false,
                  ),
              ],
            );
          },
        );
        await tester.pumpWidget(
          _host(
            bounded
                ? SizedBox(height: 162, child: work)
                : SingleChildScrollView(child: work),
            width: 390,
          ),
        );
        final header = find.byKey(
          const ValueKey('completion-run-header:constrained'),
        );
        expect(reads, 0);
        expect(find.text('成员 0'), findsNothing);
        await tester.tap(header);
        for (var frame = 0; frame < 6; frame++) {
          await tester.pump(const Duration(milliseconds: 32));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        expect(reads, greaterThan(0));
        final workFinder = find.byType(CompletionRunView);
        final viewport = find.descendant(
          of: workFinder,
          matching: find.byType(SingleChildScrollView),
        );
        expect(viewport, findsOneWidget);
        final viewportRect = tester.getRect(viewport);
        final headerRect = tester.getRect(header);
        final workRect = tester.getRect(workFinder);
        expect(viewportRect.height, greaterThan(0));
        expect(viewportRect.height, lessThanOrEqualTo(186));
        expect(viewportRect.top, greaterThanOrEqualTo(headerRect.bottom));
        if (bounded) {
          expect(workRect.height, 162);
          expect(viewportRect.bottom, lessThanOrEqualTo(workRect.bottom));
        } else {
          expect(viewportRect.height, 186);
        }
        expect(header.hitTestable(), findsOneWidget);
        expect(find.text('当前工作概要').hitTestable(), findsOneWidget);
        expect(
          find
              .descendant(
                of: header,
                matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
              )
              .hitTestable(),
          findsOneWidget,
        );
        final scrollable = find.descendant(
          of: workFinder,
          matching: find.byType(Scrollable),
        );
        expect(scrollable, findsOneWidget);
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, greaterThan(0));
        final last = find.text('成员 11');
        expect(last.hitTestable(), findsNothing);
        await tester.dragUntilVisible(last, scrollable, const Offset(0, -80));
        await tester.pumpAndSettle();
        expect(position.pixels, greaterThan(0));
        expect(last.hitTestable(), findsOneWidget);
        expect(header.hitTestable(), findsOneWidget);
        await tester.tap(header);
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(find.text('成员 11'), findsNothing);
        expect(expanded, [true, false]);
        expect(
          find
              .descendant(
                of: header,
                matching: find.byIcon(Icons.chevron_right_rounded),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'all terminal without a boundary keeps the creation clock, then history freezes elapsed',
    (tester) async {
      var now = DateTime.fromMillisecondsSinceEpoch(1125000);
      Widget view(WorkDisplayLocation location) => _host(
        CompletionRunView(
          id: 'same',
          location: location,
          summary: _summary(),
          executionPresent: location == WorkDisplayLocation.live,
          initiallyExpanded: false,
          now: () => now,
          childBuilder: (_) => const Text('body'),
        ),
      );
      await tester.pumpWidget(view(WorkDisplayLocation.live));
      expect(find.text('执行了 2 分 5 秒'), findsOneWidget);
      expect(
        tester
            .widget<TimelineActivityClock>(find.byType(TimelineActivityClock))
            .running,
        isTrue,
      );
      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('执行了 2 分 7 秒'), findsOneWidget);
      await tester.pumpWidget(view(WorkDisplayLocation.history));
      expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
      expect(
        tester
            .widget<TimelineActivityClock>(find.byType(TimelineActivityClock))
            .running,
        isFalse,
      );
      now = now.add(const Duration(minutes: 3));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
      expect(find.textContaining('9 秒'), findsNothing);
      await tester.pumpWidget(
        _host(
          CompletionRunView(
            id: 'future',
            location: WorkDisplayLocation.live,
            summary: _summary(
              createdAt: now.millisecondsSinceEpoch ~/ 1000 + 10,
            ),
            executionPresent: true,
            initiallyExpanded: false,
            now: () => now,
            childBuilder: (_) => const Text('body'),
          ),
        ),
      );
      expect(find.textContaining('执行了'), findsNothing);
      expect(find.text('执行了不到 1 秒'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final (location, owner, milliseconds, expected) in [
    (WorkDisplayLocation.live, false, 125000, '执行了 2 分 5 秒'),
    (WorkDisplayLocation.live, false, 0, '执行了不到 1 秒'),
    (WorkDisplayLocation.history, false, 500, '工作了不到 1 秒'),
    (WorkDisplayLocation.history, false, null, '工作记录'),
    (WorkDisplayLocation.history, false, -1, '工作记录'),
    (WorkDisplayLocation.live, true, null, '等待下一步'),
  ]) {
    testWidgets('saved duration $location/$milliseconds does not run a clock', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CompletionRunView(
            id: 'saved',
            location: location,
            executionPresent: owner,
            summary: _summary(createdAt: null, elapsedMs: milliseconds),
            initiallyExpanded: false,
            childBuilder: (_) => const Text('body'),
          ),
        ),
      );
      expect(find.text(expected), findsOneWidget);
      expect(
        tester
            .widget<TimelineActivityClock>(find.byType(TimelineActivityClock))
            .running,
        isFalse,
      );
      if (location == WorkDisplayLocation.live && !owner) {
        expect(find.text('上次执行未收束，尚未恢复'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'historical expansion has no private vertical viewport and exposes terminal outcomes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          CompletionRunView(
            id: 'history',
            location: WorkDisplayLocation.history,
            summary: _summary(failed: 1, cancelled: 1, transferred: 1),
            initiallyExpanded: false,
            childBuilder: (_) => const SizedBox(
              key: ValueKey('history-members'),
              height: 500,
              child: Text('历史成员'),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      final header = find.byKey(
        const ValueKey('completion-run-header:history'),
      );
      final description = tester.getSemantics(header);
      expect(description.label, contains('1 项执行失败'));
      expect(description.label, contains('1 项已停止'));
      expect(description.label, contains('已交接 1 项'));
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(find.text('历史成员'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('history-members'))).height,
        500,
      );
      expect(
        tester.getSize(find.byType(CompletionRunView)).height,
        greaterThan(500),
      );
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  for (final (phase, running, waiting) in [
    ('running', 1, 0),
    ('waiting', 0, 1),
  ]) {
    testWidgets(
      'current Work absorbs only its normal notice, not critical notices or older Work: $phase',
      (tester) async {
        final h = _LiveHarness();
        addTearDown(h.dispose);
        h.blocks = [
          _work('older', state: DisplayBlockState.sealed, thought: '前段概要'),
          _work(
            'current',
            summary: _summary(
              createdAt: null,
              running: running,
              waiting: waiting,
              thought: '当前组概要',
            ),
          ),
        ];
        h.notices = [
          const ExecutionLiveNotice(
            ConversationActivityView(
              identity: 'thinking',
              turnId: 'turn',
              kind: ConversationActivityKind.thinking,
              summary: '普通提示不另起一行',
            ),
          ),
          const ExecutionLiveNotice(
            ConversationActivityView(
              identity: 'stopping',
              turnId: 'turn',
              kind: ConversationActivityKind.stopping,
            ),
          ),
          const ExecutionLiveNotice(
            ConversationActivityView(
              identity: 'approval',
              turnId: 'turn',
              kind: ConversationActivityKind.awaitingApproval,
            ),
          ),
          const ExecutionLiveNotice(
            ConversationActivityView(
              identity: 'storage',
              turnId: 'turn',
              kind: ConversationActivityKind.storageBlocked,
            ),
          ),
          const ExecutionLiveNotice(
            ConversationActivityView(
              identity: 'error',
              turnId: 'turn',
              kind: ConversationActivityKind.thinking,
              errorMessage: '真实错误',
            ),
          ),
        ];
        await tester.pumpWidget(h.host());
        // Sealed headers use the frozen worked-duration title in Timeline,
        // while the active open Work renders inside ConversationActivityBar.
        expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
        expect(find.text('当前组概要'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('timeline-current-work')),
            matching: find.byType(CompletionRunView),
          ),
          findsOneWidget,
        );
        expect(tester.getRect(find.byKey(const ValueKey('older'))).left, 24.0);
        expect(
          find.descendant(
            of: find.byType(ConversationActivityBar),
            matching: find.byType(CompletionRunView),
          ),
          findsOneWidget,
        );
        expect(find.text('普通提示不另起一行'), findsNothing);
        expect(find.byType(ConversationActivityStatus), findsNWidgets(4));
        expect(find.text('真实错误'), findsOneWidget);
        final header = find.byKey(
          const ValueKey('completion-run-header:current'),
        );
        expect(
          tester
              .widget<TimelineActivityIndicator>(
                find.descendant(
                  of: header,
                  matching: find.byType(TimelineActivityIndicator),
                ),
              )
              .active,
          isTrue,
        );
        expect(h.content.reads, 0);
        h.blocks = [
          _work('older', state: DisplayBlockState.sealed, thought: '前段概要'),
          LiveDisplayBlock(
            id: 'text',
            blockOrder: 3,
            state: DisplayBlockState.open,
            body: SingleDisplayBlock(
              record: DisplayRecord(
                atom: chatAtomMessage('text', body: '后继正文'),
                contentSource: const CurrentAtom(),
              ),
            ),
          ),
        ];
        await tester.pumpWidget(h.host());
        expect(find.text('工作了 2 分 5 秒'), findsOneWidget);
        expect(find.text('后继正文'), findsOneWidget);
        expect(find.text('普通提示不另起一行'), findsOneWidget);
        expect(find.byType(ConversationActivityStatus), findsNWidgets(5));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'completed open Work (group-idle) merges active Turn thinking notice in place while retaining its thinking summary',
    (tester) async {
      final h = _LiveHarness();
      addTearDown(h.dispose);
      final summary = _summary(total: 2, thought: '已结束成员的思考概要');
      h.blocks = [_work('work', summary: summary)];
      h.notices = [
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'thinking',
            turnId: 'turn',
            kind: ConversationActivityKind.thinking,
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(find.byType(ConversationActivityStatus), findsNothing);
      final workFinder = find.descendant(
        of: find.byType(ConversationActivityBar),
        matching: find.byType(CompletionRunView),
      );
      expect(workFinder, findsOneWidget);
      final work = tester.widget<CompletionRunView>(workFinder);
      expect(
        work.activity,
        same((h.notices.single as ExecutionLiveNotice).view),
      );
      final header = find.byKey(const ValueKey('completion-run-header:work'));
      expect(
        find.descendant(of: header, matching: find.text('已结束成员的思考概要')),
        findsOneWidget,
      );
      expect(find.text('思考中'), findsNothing);
      expect(
        tester
            .widget<TimelineActivityIndicator>(
              find.descendant(
                of: header,
                matching: find.byType(TimelineActivityIndicator),
              ),
            )
            .active,
        isTrue,
      );

      // Without a thinking summary on the open Work, group-idle falls back to 思考中.
      h.blocks = [_work('work', summary: _summary(total: 2))];
      await tester.pumpWidget(h.host());
      expect(
        find.descendant(of: header, matching: find.text('思考中')),
        findsOneWidget,
      );
      expect(h.content.reads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'open Work renders single-line Markdown thinking summary across thinking, exec, group-idle and same-group updates while Timeline keeps worked copy',
    (tester) async {
      final h = _LiveHarness();
      addTearDown(h.dispose);

      // 1. Open Work before any thinking summary arrives: shows 思考中.
      h.blocks = [_work('work-1', summary: _summary(total: 1, running: 1))];
      h.notices = [
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'act-0',
            turnId: 'turn',
            kind: ConversationActivityKind.thinking,
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      final barFinder = find.byKey(const ValueKey('conversation-activity'));
      final header1 = find.byKey(
        const ValueKey('completion-run-header:work-1'),
      );
      expect(
        timelineGroupTitleText(
          tester,
          timelineGroupTitleFinder(tester, header1),
        ),
        '思考中',
      );
      final baselineBarSize = tester.getRect(barFinder).size;

      // 2. Streaming first Markdown thinking summary: replaces 思考中, renders
      // bold + inline code + link label without gestures, and preserves height.
      const mdThoughtA =
          '梳理 **会话共享组件** 与 `LiveStatusBar` [锁定边界](https://example.com)';
      h.notices = [
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'act-1',
            turnId: 'turn',
            kind: ConversationActivityKind.thinking,
            thinkingSummary: mdThoughtA,
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      final titleA = timelineGroupTitleFinder(tester, header1);
      expect(tester.widget(titleA), isA<TimelineReasoningSummary>());
      expect(
        timelineGroupTitleText(tester, titleA),
        '梳理 会话共享组件 与 LiveStatusBar 锁定边界',
      );
      final paragraphA = timelineGroupTitleParagraph(tester, titleA);
      expect(paragraphA.maxLines, 1);
      expect(paragraphA.softWrap, isFalse);
      expect(paragraphA.overflow, TextOverflow.ellipsis);
      expect(
        tester.getRect(barFinder).size.height,
        closeTo(baselineBarSize.height, 0.001),
      );

      // Verify **会话共享组件** span is bold and raw delimiters are absent.
      TextStyle? boldSpanStyle;
      void findBold(InlineSpan span, TextStyle inherited) {
        final effective = inherited.merge(span.style);
        if (span is TextSpan) {
          if (span.text == '会话共享组件') boldSpanStyle = effective;
          for (final child in span.children ?? const <InlineSpan>[]) {
            findBold(child, effective);
          }
        }
      }

      findBold(paragraphA.text, const TextStyle());
      expect(boldSpanStyle?.fontWeight, FontWeight.bold);

      // 3. Exec command running: summary.thinkingSummary retains mdThoughtA,
      // replacing command line copy while leading icon switches to circularProgress.
      h.blocks = [
        _work(
          'work-1',
          summary: _summary(total: 2, running: 1, thought: mdThoughtA),
        ),
      ];
      h.notices = [
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'act-2',
            turnId: 'turn',
            kind: ConversationActivityKind.runningTool,
            summary: 'cargo flutter test',
            activeTools: [
              ThreadActivityToolEntry(
                callId: 'exec-1',
                name: 'exec',
                summary: 'cargo flutter test',
                arguments: ThreadActivityArgumentsKind.commandLine,
                state: ThreadActivityToolState.running,
                startedAt: 100,
              ),
            ],
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(
        timelineGroupTitleText(
          tester,
          timelineGroupTitleFinder(tester, header1),
        ),
        '梳理 会话共享组件 与 LiveStatusBar 锁定边界',
      );
      expect(find.text('cargo flutter test'), findsNothing);
      expect(
        find.descendant(
          of: header1,
          matching: find.byType(TimelineExecProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(barFinder).size.height,
        closeTo(baselineBarSize.height, 0.001),
      );

      // 4. group-idle: members completed, waiting for next step; retains mdThoughtA
      // instead of reverting to 思考中, while icon returns to resting cat.
      h.blocks = [
        _work(
          'work-1',
          summary: _summary(total: 2, running: 0, thought: mdThoughtA),
        ),
      ];
      h.notices = [
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'act-3',
            turnId: 'turn',
            kind: ConversationActivityKind.thinking,
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(
        timelineGroupTitleText(
          tester,
          timelineGroupTitleFinder(tester, header1),
        ),
        '梳理 会话共享组件 与 LiveStatusBar 锁定边界',
      );
      expect(
        find.descendant(of: header1, matching: find.byType(TimelineRestingCat)),
        findsOneWidget,
      );
      expect(
        tester.getRect(barFinder).size.height,
        closeTo(baselineBarSize.height, 0.001),
      );

      // 5. Same open Work receives a newer thinking summary with H1 heading:
      // immediately replaces older summary in-place without H1 divider or height jump.
      const mdThoughtB = '# 复核 `Timeline` 封存契约';
      h.blocks = [
        _work(
          'work-1',
          summary: _summary(total: 3, running: 1, thought: mdThoughtA),
        ),
      ];
      h.notices = [
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'act-4',
            turnId: 'turn',
            kind: ConversationActivityKind.thinking,
            thinkingSummary: mdThoughtB,
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(
        timelineGroupTitleText(
          tester,
          timelineGroupTitleFinder(tester, header1),
        ),
        '复核 Timeline 封存契约',
      );
      expect(
        find.descendant(of: header1, matching: find.byType(CustomDivider)),
        findsNothing,
      );
      expect(
        tester.getRect(barFinder).size.height,
        closeTo(baselineBarSize.height, 0.001),
      );

      // 6. Boundary seals work-1 into Timeline (kept as 工作了 2 分 5 秒) and opens
      // a new work-2 (no leaked thinkingSummary from work-1).
      h.blocks = [
        _work(
          'work-1',
          blockOrder: 1,
          state: DisplayBlockState.sealed,
          summary: _summary(total: 3, running: 0, thought: mdThoughtB),
        ),
        _work(
          'work-2',
          blockOrder: 2,
          summary: _summary(total: 1, running: 1, thought: null),
        ),
      ];
      h.notices = [
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'act-5',
            turnId: 'turn',
            kind: ConversationActivityKind.runningTool,
            summary: 'cargo flutter analyze',
            activeTools: [
              ThreadActivityToolEntry(
                callId: 'exec-2',
                name: 'exec',
                summary: 'cargo flutter analyze',
                arguments: ThreadActivityArgumentsKind.commandLine,
                state: ThreadActivityToolState.running,
                startedAt: 200,
              ),
            ],
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(
        timelineGroupTitleText(
          tester,
          timelineGroupTitleFinder(tester, header1),
        ),
        '工作了 2 分 5 秒',
      );
      expect(
        find.descendant(
          of: header1,
          matching: find.byType(TimelineReasoningSummary),
        ),
        findsNothing,
      );
      final header2 = find.byKey(
        const ValueKey('completion-run-header:work-2'),
      );
      expect(
        timelineGroupTitleText(
          tester,
          timelineGroupTitleFinder(tester, header2),
        ),
        'cargo flutter analyze',
      );
      expect(h.content.reads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'tapping Markdown link or inline code in live Work header toggles disclosure; history Work ignores thinkingSummary',
    (tester) async {
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CompletionRunView(
                id: 'live-md',
                location: WorkDisplayLocation.live,
                executionPresent: true,
                initiallyExpanded: false,
                summary: _summary(
                  createdAt: null,
                  running: 1,
                  thought:
                      '检查 `LiveStatusBar` 与 [设计文档](https://example.com) 契约',
                ),
                childBuilder: (_) => const Text('expanded member row'),
              ),
              CompletionRunView(
                id: 'history-md',
                location: WorkDisplayLocation.history,
                initiallyExpanded: false,
                summary: _summary(
                  createdAt: null,
                  running: 0,
                  thought:
                      '检查 `LiveStatusBar` 与 [设计文档](https://example.com) 契约',
                ),
                childBuilder: (_) => const Text('history member row'),
              ),
            ],
          ),
        ),
      );
      final liveHeader = find.byKey(
        const ValueKey('completion-run-header:live-md'),
      );
      final liveTitle = timelineGroupTitleFinder(tester, liveHeader);
      expect(
        timelineGroupTitleText(tester, liveTitle),
        '检查 LiveStatusBar 与 设计文档 契约',
      );
      expect(
        timelineWorkHeaderExpanded(tester, liveHeader, 'live-md'),
        isFalse,
      );
      await tester.tap(liveTitle);
      await tester.pump(const Duration(milliseconds: 300));
      expect(timelineWorkHeaderExpanded(tester, liveHeader, 'live-md'), isTrue);
      expect(find.text('expanded member row'), findsOneWidget);
      await tester.tap(liveTitle);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        timelineWorkHeaderExpanded(tester, liveHeader, 'live-md'),
        isFalse,
      );

      final historyHeader = find.byKey(
        const ValueKey('completion-run-header:history-md'),
      );
      expect(
        timelineGroupTitleText(
          tester,
          timelineGroupTitleFinder(tester, historyHeader),
        ),
        '工作了 2 分 5 秒',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final (outcome, icon, result) in [
    (ChatTerminalOutcome.failed, Icons.error_outline, '1 项执行失败'),
    (ChatTerminalOutcome.cancelled, Icons.stop_circle_outlined, '1 项已停止'),
    (ChatTerminalOutcome.transferred, Icons.call_made, '已交接 1 项'),
  ]) {
    testWidgets(
      'abnormal terminal ${outcome.name} Work keeps its result and independent Turn notice',
      (tester) async {
        final h = _LiveHarness();
        addTearDown(h.dispose);
        final semantics = tester.ensureSemantics();
        try {
          final summary = _summary(
            total: 1,
            failed: outcome == ChatTerminalOutcome.failed ? 1 : 0,
            cancelled: outcome == ChatTerminalOutcome.cancelled ? 1 : 0,
            transferred: outcome == ChatTerminalOutcome.transferred ? 1 : 0,
          );
          h.blocks = [_work('work', summary: summary)];
          h.notices = [
            const ExecutionLiveNotice(
              ConversationActivityView(
                identity: 'thinking',
                turnId: 'turn',
                kind: ConversationActivityKind.thinking,
                thinkingSummary: '有界思考概要',
                summary: '状态概要',
              ),
            ),
          ];
          await tester.pumpWidget(h.host());
          expect(find.byType(ConversationActivityStatus), findsOneWidget);
          expect(
            tester
                .widget<ConversationActivityStatus>(
                  find.byType(ConversationActivityStatus),
                )
                .view,
            same((h.notices.single as ExecutionLiveNotice).view),
          );
          expect(find.text('有界思考概要'), findsNothing);
          expect(find.text('状态概要'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(ConversationActivityStatus),
              matching: find.text('思考中'),
            ),
            findsOneWidget,
          );
          final header = find.byKey(
            const ValueKey('completion-run-header:work'),
          );
          void expectStaticResult() {
            final work = tester.widget<CompletionRunView>(
              find.byType(CompletionRunView),
            );
            expect(work.summary, same(summary));
            expect(work.state, DisplayBlockState.open);
            expect(work.activity, isNull);
            expect(
              find.descendant(of: header, matching: find.text('等待下一步')),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<TimelineActivityIndicator>(
                    find.descendant(
                      of: header,
                      matching: find.byType(TimelineActivityIndicator),
                    ),
                  )
                  .active,
              isFalse,
            );
            expect(
              find.descendant(of: header, matching: find.byIcon(icon)),
              findsOneWidget,
            );
            final description = tester.getSemantics(header).label;
            expect(description, contains(result));
            expect(description, isNot(contains('思考中')));
            expect(
              tester
                  .widget<TimelineActivityClock>(
                    find.descendant(
                      of: find.byType(CompletionRunView),
                      matching: find.byType(TimelineActivityClock),
                    ),
                  )
                  .running,
              isTrue,
            );
          }

          expectStaticResult();
          h.notices = [
            const ExecutionLiveNotice(
              ConversationActivityView(
                identity: 'thinking',
                turnId: 'turn',
                kind: ConversationActivityKind.thinking,
                summary: '状态概要',
              ),
            ),
          ];
          await tester.pumpWidget(h.host());
          expect(find.byType(ConversationActivityStatus), findsOneWidget);
          expect(find.text('状态概要'), findsOneWidget);
          expectStaticResult();
          expect(h.content.reads, 0);
          await tester.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'unproven Turn keeps its independent notice; cold Work keeps its unrestored message',
    (tester) async {
      final h = _LiveHarness();
      addTearDown(h.dispose);
      h.blocks = [_work('work', thought: '独立概要')];
      h.notices = [
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'different',
            turnId: 'other-turn',
            kind: ConversationActivityKind.thinking,
            summary: '另一来源提示',
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(find.text('另一来源提示'), findsOneWidget);
      h.executionPresent = false;
      h.notices = [const UnrestoredLiveNotice()];
      await tester.pumpWidget(h.host());
      expect(find.text('上次执行未收束，尚未恢复'), findsOneWidget);
      expect(h.content.reads, 0);
      expect(
        tester
            .widget<TimelineActivityClock>(find.byType(TimelineActivityClock))
            .running,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'open Work switches header indicator to circular progress while exec runs and returns to resting cat when exec completes',
    (tester) async {
      final h = _LiveHarness();
      addTearDown(h.dispose);
      h.blocks = [
        _work('work-exec', summary: _summary(running: 1, thought: '运行单元测试命令')),
      ];
      h.notices = [
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'exec-active',
            turnId: 'turn',
            kind: ConversationActivityKind.runningTool,
            activeTools: [
              ThreadActivityToolEntry(
                callId: 'call-exec',
                name: 'exec',
                summary: 'cargo flutter test',
                arguments: ThreadActivityArgumentsKind.commandLine,
                state: ThreadActivityToolState.running,
                startedAt: 1000,
              ),
            ],
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      final header = find.byKey(
        const ValueKey('completion-run-header:work-exec'),
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byType(TimelineExecProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: header, matching: find.byType(TimelineRestingCat)),
        findsNothing,
      );

      // exec 结束、工作组转入等待交接思考时立即恢复趴卧摇尾猫。
      h.blocks = [
        _work('work-exec', summary: _summary(running: 0, thought: '运行单元测试命令')),
      ];
      h.notices = [
        const ExecutionLiveNotice(
          ConversationActivityView(
            identity: 'thinking-after-exec',
            turnId: 'turn',
            kind: ConversationActivityKind.thinking,
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(
        find.descendant(
          of: header,
          matching: find.byType(TimelineExecProgressIndicator),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: header, matching: find.byType(TimelineRestingCat)),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

LiveDisplayBlock _work(
  String id, {
  int? blockOrder,
  DisplayBlockState state = DisplayBlockState.open,
  String? thought,
  WorkSummary? summary,
}) => LiveDisplayBlock(
  id: id,
  blockOrder: blockOrder ?? (id == 'older' ? 1 : 2),
  state: state,
  source: const ForegroundTurnChatSource(turnId: 'turn'),
  body: WorkDisplayBlock(
    summary: summary ?? _summary(createdAt: null, thought: thought),
    members: DisplayBlockRef(databaseId: 'db', blockId: id),
  ),
);

class _Session extends Fake implements ThreadSessionState {
  @override
  String get threadId => 'thread';
  @override
  ThreadActivityView? get activity => null;
  @override
  StudioTurnView get activeTurn => StudioTurnView(
    turnId: 'turn',
    threadId: 'thread',
    revision: 1,
    state: const RunningStudioTurnState(
      startedAt: 1000,
      activity: StudioTurnActivity.thinking,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1000000),
  );
}

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
  final live = ValueNotifier<LiveDisplayWindow?>(null);
  final images = TimelineImageResources(threadId: 'thread');
  final expansions = <String, TimelineExpansionIntent>{};
  List<LiveDisplayBlock> blocks = [];
  List<LiveStatusNotice> notices = [];
  bool executionPresent = true;
  int revision = 0;
  Widget host() {
    live.value = LiveDisplayWindow(
      revision: ++revision,
      historyThrough: 0,
      executionPresent: executionPresent,
      blocks: blocks,
    );
    final projected = LiveStatusStateMachine.projectSurfaceAndTimelineWork(
      effectiveOutputWindow: live.value,
      effectiveTimelineWindow: live.value,
      activeTurnId: 'turn',
      confirmingPlan: false,
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
          managedByViewModel: true,
          session: _Session(),
          content: content,
          live: live,
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
