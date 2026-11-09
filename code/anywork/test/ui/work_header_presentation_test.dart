import 'dart:typed_data';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/conversation_realtime_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_clock.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/contracts/stamps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

WorkSummary _summary({
  int? createdAt = 1000,
  int? elapsedMs = 125000,
  int running = 0,
  int waiting = 0,
  int failed = 0,
  int cancelled = 0,
  int transferred = 0,
  String? thought,
}) => WorkSummary(
  total: 4,
  terminal: 4 - running - waiting,
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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
            childBuilder: (_) =>
                const SizedBox(height: 500, child: Text('历史成员')),
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
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets(
    'current Work absorbs only its normal notice, not critical notices or older Work',
    (tester) async {
      final h = _LiveHarness();
      addTearDown(h.dispose);
      h.blocks = [
        _work('older', closing: true, thought: '前段概要'),
        _work('current', thought: '当前组概要'),
      ];
      h.notices = [
        const ExecutionRealtimeNotice(
          ConversationActivityView(
            identity: 'thinking',
            turnId: 'turn',
            kind: ConversationActivityKind.thinking,
            summary: '普通提示不另起一行',
          ),
        ),
        const ExecutionRealtimeNotice(
          ConversationActivityView(
            identity: 'stopping',
            kind: ConversationActivityKind.stopping,
          ),
        ),
        const ExecutionRealtimeNotice(
          ConversationActivityView(
            identity: 'approval',
            kind: ConversationActivityKind.awaitingApproval,
          ),
        ),
        const ExecutionRealtimeNotice(
          ConversationActivityView(
            identity: 'storage',
            kind: ConversationActivityKind.storageBlocked,
          ),
        ),
        const ExecutionRealtimeNotice(
          ConversationActivityView(
            identity: 'error',
            kind: ConversationActivityKind.thinking,
            errorMessage: '真实错误',
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(find.text('前段概要'), findsOneWidget);
      expect(find.text('当前组概要'), findsOneWidget);
      expect(find.text('普通提示不另起一行'), findsNothing);
      expect(find.byType(ConversationActivityStatus), findsNWidgets(4));
      expect(find.text('真实错误'), findsOneWidget);
      expect(h.content.reads, 0);
      h.blocks = [
        _work('older', closing: true, thought: '前段概要'),
        LiveDisplayBlock(
          id: 'text',
          blockOrder: 3,
          closing: false,
          body: SingleDisplayBlock(atom: chatAtomMessage('text', body: '后继正文')),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(find.text('前段概要'), findsOneWidget);
      expect(find.text('后继正文'), findsOneWidget);
      expect(find.text('普通提示不另起一行'), findsOneWidget);
      expect(find.byType(ConversationActivityStatus), findsNWidgets(5));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'merged current notice retains its bounded overview without reading members',
    (tester) async {
      final h = _LiveHarness();
      addTearDown(h.dispose);
      h.blocks = [_work('work')];
      h.notices = [
        const ExecutionRealtimeNotice(
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
      expect(find.byType(ConversationActivityStatus), findsNothing);
      expect(find.text('有界思考概要'), findsOneWidget);
      h.notices = [
        const ExecutionRealtimeNotice(
          ConversationActivityView(
            identity: 'thinking',
            turnId: 'turn',
            kind: ConversationActivityKind.thinking,
            summary: '状态概要',
          ),
        ),
      ];
      await tester.pumpWidget(h.host());
      expect(find.byType(ConversationActivityStatus), findsNothing);
      expect(find.text('状态概要'), findsOneWidget);
      expect(h.content.reads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unproven Turn keeps its independent notice; cold Work keeps its unrestored message',
    (tester) async {
      final h = _LiveHarness();
      addTearDown(h.dispose);
      h.blocks = [_work('work', thought: '独立概要')];
      h.notices = [
        const ExecutionRealtimeNotice(
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
      h.notices = [const UnrestoredRealtimeNotice()];
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
}

LiveDisplayBlock _work(String id, {bool closing = false, String? thought}) =>
    LiveDisplayBlock(
      id: id,
      blockOrder: id == 'older' ? 1 : 2,
      closing: closing,
      source: const ForegroundTurnChatSource(turnId: 'turn'),
      body: WorkDisplayBlock(
        summary: _summary(createdAt: null, thought: thought),
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
  List<RealtimeNotice> notices = [];
  bool executionPresent = true;
  int revision = 0;
  Widget host() {
    live.value = LiveDisplayWindow(
      revision: ++revision,
      historyThrough: 0,
      executionPresent: executionPresent,
      blocks: blocks,
    );
    return _host(
      ConversationCurrentConnector(
        session: _Session(),
        content: content,
        live: live,
        region: ContentRealtimeRegion(live: live.value, notices: notices),
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
