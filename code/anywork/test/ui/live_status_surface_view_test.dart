import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/app/theme/studio_tokens.dart';
import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/work_group_member_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart' as feed;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(
  LiveStatusState state, {
  bool reducedMotion = false,
  bool expanded = true,
}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 760,
        child: LiveStatusSurfaceView(
          state: state,
          liveWorkInitiallyExpanded: expanded,
        ),
      ),
    ),
  ),
);

LiveStatusState _project(
  feed.LiveStatusPhase phase, {
  List<feed.LiveAttention> attentions = const [],
  feed.ThreadStorageStateView? storageState,
}) => LiveStatusMachine.project(
  'thread-1',
  feed.LiveStatusSnapshot(
    revision: 1,
    phase: phase,
    attentions: attentions,
    suppressedByInteraction: false,
  ),
  receivedAt: DateTime.utc(2026),
  storageState: storageState,
).state;

void main() {
  testWidgets('streaming owns one header, clock, and growing response body', (
    tester,
  ) async {
    LiveStatusState streaming(String text) => _project(
      feed.LiveStatusStreamingText(
        attemptId: 'attempt-1',
        itemId: 'response-1',
        text: text,
        startedAtMs: DateTime.utc(2026).millisecondsSinceEpoch,
      ),
    );
    final title = find.text('正在输出');
    final body = find.byType(ConversationCurrentWindowView);

    await tester.pumpWidget(_host(streaming('')));
    expect(title, findsOneWidget);
    final titleElement = tester.element(title);
    expect(tester.widget<ConversationCurrentWindowView>(body).text, isEmpty);

    await tester.pumpWidget(_host(streaming('Beacon')));
    expect(title, findsOneWidget);
    expect(tester.element(title), same(titleElement));
    final header = find.ancestor(
      of: title,
      matching: find.byType(TimelineActivityRow),
    );
    expect(tester.widget<TimelineActivityRow>(header).meta, isNotEmpty);
    expect(tester.widget<ConversationCurrentWindowView>(body).text, 'Beacon');

    await tester.pumpWidget(_host(_project(const feed.LiveStatusIdle())));
    expect(title, findsNothing);
    expect(body, findsNothing);
  });

  testWidgets(
    'working empty shows thinking without disclosure and items fold cleanly without ListTile',
    (tester) async {
      await tester.pumpWidget(
        _host(
          _project(
            feed.LiveStatusWorking(items: const [], startedAtMs: 100000),
          ),
        ),
      );
      expect(find.text('思考中'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live-work-disclosure:thread-1')),
        findsNothing,
      );

      await tester.pumpWidget(
        _host(
          _project(
            feed.LiveStatusWorking(
              items: [
                const feed.WorkGroupReasoning(
                  id: 'reasoning:1',
                  seq: 1,
                  text: '推理正文 **Markdown**',
                  summary: '**梳理依赖**',
                  outcome: 'completed',
                  startedAtMs: 100000,
                  finishedAtMs: 102000,
                ),
                feed.WorkGroupToolCall(
                  id: 'call:1',
                  seq: 2,
                  callId: '1',
                  toolName: 'exec',
                  presentationContract: 'builtin.exec@2',
                  status: 'running',
                  summary: 'exec',
                  arguments: '{"command":"cargo test"}',
                  payloadJson: '{}',
                  bodies: const [],
                  startedAtMs: 102000,
                ),
              ],
              reasoningPreview: '**Header****Summary**',
              startedAtMs: 100000,
            ),
          ),
          expanded: true,
        ),
      );
      expect(
        find.byKey(const ValueKey('live-work-disclosure:thread-1')),
        findsOneWidget,
      );
      expect(find.byType(WorkGroupMemberView), findsNWidgets(2));
      expect(find.text('思考 · 梳理依赖'), findsNothing);
      expect(find.text('梳理依赖', findRichText: true), findsOneWidget);
      expect(find.text('正在运行 cargo test'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('live-work-header:thread-1')),
          matching: find.byType(ListTile),
        ),
        findsNothing,
      );

      final headerRow = tester.widget<TimelineActivityRow>(
        find.byKey(const ValueKey('live-work-header:thread-1')),
      );
      expect(headerRow.label, 'Header Summary');
      expect(headerRow.semanticsLabel, isNot(contains('**')));
      expect(find.byType(Tooltip), findsNothing);
    },
  );

  testWidgets(
    'working header falls back to active tool headline without reasoningPreview',
    (tester) async {
      await tester.pumpWidget(
        _host(
          _project(
            feed.LiveStatusWorking(
              items: [
                feed.WorkGroupToolCall(
                  id: 'call:1',
                  seq: 1,
                  callId: '1',
                  toolName: 'exec',
                  presentationContract: 'builtin.exec@2',
                  status: 'running',
                  summary: 'exec',
                  arguments: '{"command":"flutter analyze"}',
                  payloadJson: '{}',
                  bodies: const [],
                  startedAtMs: 100000,
                ),
              ],
              startedAtMs: 100000,
            ),
          ),
          expanded: false,
        ),
      );
      expect(find.text('正在运行 flutter analyze'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets('reconnect replaces work and updates the existing retry row', (
    tester,
  ) async {
    final work = _project(
      feed.LiveStatusWorking(items: const [], startedAtMs: 100000),
    );
    await tester.pumpWidget(_host(work));
    expect(find.text('思考中'), findsOneWidget);

    feed.LiveStatusReconnecting retry(String reason) =>
        feed.LiveStatusReconnecting(
          attemptId: 'retry',
          message: reason,
          attempt: 2,
          maxAttempts: 5,
        );
    final label = find.text('模型连接断开，正在重连（2/5）');
    final row = find.ancestor(
      of: label,
      matching: find.byType(TimelineActivityRow),
    );
    await tester.pumpWidget(_host(_project(retry('first failure'))));
    expect(find.text('思考中'), findsNothing);
    final element = tester.element(row);
    expect(
      tester.widget<TimelineActivityRow>(row).semanticsLabel,
      contains('first failure'),
    );
    expect(find.byType(Tooltip), findsNothing);

    await tester.pumpWidget(_host(_project(retry('second failure'))));
    expect(tester.element(row), same(element));
    expect(
      tester.widget<TimelineActivityRow>(row).semanticsLabel,
      contains('second failure'),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      _host(_project(retry('second failure')), reducedMotion: true),
    );
    expect(find.byIcon(Icons.sync_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(_host(work));
    expect(label, findsNothing);
    expect(find.text('思考中'), findsOneWidget);
  });

  testWidgets('stopping has a static alternative under reduced motion', (
    tester,
  ) async {
    final stopping = _project(
      const feed.LiveStatusStopping(startedAtMs: 100000),
    );
    await tester.pumpWidget(_host(stopping));
    expect(find.text('停止中'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(_host(stopping, reducedMotion: true));
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('approval is a static warning', (tester) async {
    await tester.pumpWidget(
      _host(
        _project(
          const feed.LiveStatusIdle(),
          attentions: const [
            feed.LiveAttention(
              id: 'approval',
              kind: 'approval',
              summary: 'exec',
            ),
          ],
        ),
      ),
    );
    final icon = find.byIcon(Icons.verified_outlined);
    expect(
      tester.widget<Icon>(icon).color,
      StudioTone.warning.indicator(tester.element(icon)),
    );
    expect(
      tester
          .widget<TimelineActivityRow>(find.byType(TimelineActivityRow))
          .active,
      isFalse,
    );
  });

  testWidgets('storage ready and fault show their distinct status', (
    tester,
  ) async {
    Future<void> show(feed.ThreadStorageStateView storage) => tester.pumpWidget(
      _host(_project(const feed.LiveStatusIdle(), storageState: storage)),
    );

    await show(
      const feed.ThreadStorageStateView(resumeRequired: true, canResume: true),
    );
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.text('已保存，等待继续执行'), findsOneWidget);

    await show(
      const feed.ThreadStorageStateView(
        fault: feed.ThreadHistoryFault.writeFailed,
        faultGeneration: 2,
        execution: feed.ThreadStorageExecution.paused,
        lastError: '写入失败',
      ),
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('写入失败'), findsOneWidget);
  });
}
