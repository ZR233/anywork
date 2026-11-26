import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/app/theme/studio_tokens.dart';
import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart' as feed;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(LiveStatusGateState gate, {bool reducedMotion = false}) =>
    MaterialApp(
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
              gate: gate,
              liveWorkInitiallyExpanded: true,
              liveWorkChildBuilder: (_) => const Text('Open tool member'),
            ),
          ),
        ),
      ),
    );

LiveStatusGateState _gate(
  feed.LiveStatusPhase phase, {
  List<feed.LiveAttention> attentions = const [],
}) => LiveStatusMachine.project(
  'thread-1',
  feed.LiveStatusSnapshot(
    revision: 1,
    phase: phase,
    attentions: attentions,
    suppressedByInteraction: false,
  ),
  receivedAt: DateTime.utc(2026),
).gate;

void main() {
  testWidgets('reconnect replaces work and updates the existing retry row', (
    tester,
  ) async {
    final work = _gate(
      feed.LiveStatusWorking(items: const [], startedAtMs: 100000),
    );
    await tester.pumpWidget(_host(work));
    expect(find.byType(CompletionRunView), findsOneWidget);
    expect(find.text('Open tool member'), findsOneWidget);

    feed.LiveStatusReconnecting retry(String reason) =>
        feed.LiveStatusReconnecting(
          attemptId: 'retry',
          message: reason,
          attempt: 2,
        );
    final label = find.text('正在重连实时同步');
    final row = find.ancestor(
      of: label,
      matching: find.byType(TimelineActivityRow),
    );
    await tester.pumpWidget(_host(_gate(retry('first failure'))));
    expect(find.byType(CompletionRunView), findsNothing);
    expect(find.text('Open tool member'), findsNothing);
    final element = tester.element(row);
    expect(tester.widget<TimelineActivityRow>(row).tooltip, 'first failure');

    await tester.pumpWidget(_host(_gate(retry('second failure'))));
    expect(tester.element(row), same(element));
    expect(tester.widget<TimelineActivityRow>(row).tooltip, 'second failure');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(_host(work));
    expect(label, findsNothing);
    expect(find.byType(CompletionRunView), findsOneWidget);
  });

  testWidgets('stopping has a static alternative under reduced motion', (
    tester,
  ) async {
    final gate = _gate(
      const feed.LiveStatusIdle(),
      attentions: const [
        feed.LiveAttention(id: 'stop-1', kind: 'stopping', summary: ''),
      ],
    );
    await tester.pumpWidget(_host(gate));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(_host(gate, reducedMotion: true));
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('approval is a static warning', (tester) async {
    await tester.pumpWidget(
      _host(
        _gate(
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
    Future<void> show(feed.ThreadStorageStateView storage, String? error) =>
        tester.pumpWidget(
          _host(
            LiveStatusPresenting(
              presentation: LiveStatusPresentation(
                attentions: [
                  LiveStorageAttention(
                    activity: feed.ConversationActivityView(
                      identity: 'storage',
                      kind: feed.ConversationActivityKind.storageBlocked,
                      errorMessage: error,
                      storage: storage,
                    ),
                    storage: storage,
                    severity: LiveStorageSeverity.fromStorage(storage),
                  ),
                ],
              ),
            ),
          ),
        );
    await show(
      const feed.ThreadStorageStateView(resumeRequired: true, canResume: true),
      null,
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
      '写入失败',
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('写入失败'), findsOneWidget);
  });
}
