import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/app/theme/studio_tokens.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_models.dart';
import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(
  Widget child, {
  Locale locale = const Locale('zh'),
  double width = 760,
  double scale = 1,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: pureStudioTheme(locale: locale),
  locale: locale,
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, appChild) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: disableAnimations,
    ),
    child: appChild!,
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  group('LiveStatusSurfaceView', () {
    testWidgets(
      'stopping renders neutral spinner and static icon under reduced motion',
      (tester) async {
        final projected = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            activity: const ThreadActivityView(
              threadId: 'thread-1',
              identity: 'stop-1',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.stopping,
              summary: '',
              tools: ThreadActivityTools.empty,
            ),
          ),
        );

        await tester.pumpWidget(
          _host(LiveStatusSurfaceView(gate: projected.gate)),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final context = tester.element(find.byType(ConversationActivityStatus));
        final indicator = tester.widget<TimelineActivityIndicator>(
          find.byType(TimelineActivityIndicator),
        );
        expect(indicator.active, isTrue);
        expect(indicator.color, StudioTone.neutral.indicator(context));

        await tester.pumpWidget(
          _host(
            LiveStatusSurfaceView(gate: projected.gate),
            disableAnimations: true,
          ),
        );
        expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'awaitingApproval shows warning verified_outlined static icon',
      (tester) async {
        final projected = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            activity: const ThreadActivityView(
              threadId: 'thread-1',
              identity: 'appr-1',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.awaitingApproval,
              summary: 'exec',
              tools: ThreadActivityTools.empty,
            ),
          ),
        );

        await tester.pumpWidget(
          _host(LiveStatusSurfaceView(gate: projected.gate)),
        );

        final icon = tester.widget<Icon>(find.byIcon(Icons.verified_outlined));
        final context = tester.element(find.byIcon(Icons.verified_outlined));
        expect(icon.color, StudioTone.warning.indicator(context));
        final row = tester.widget<TimelineActivityRow>(
          find.byType(TimelineActivityRow),
        );
        expect(row.active, isFalse);
      },
    );

    testWidgets(
      'storage resumeReady shows green check_circle_outline while fault shows red error_outline',
      (tester) async {
        final resumeReady = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            storage: const ThreadStorageStateView(
              fault: ThreadHistoryFault.writeFailed,
              faultGeneration: 1,
              execution: ThreadStorageExecution.paused,
              resumeRequired: true,
              canResume: true,
            ),
          ),
        );
        await tester.pumpWidget(
          _host(LiveStatusSurfaceView(gate: resumeReady.gate)),
        );

        final readyContext = tester.element(
          find.byIcon(Icons.check_circle_outline),
        );
        final readyIcon = tester.widget<Icon>(
          find.byIcon(Icons.check_circle_outline),
        );
        expect(readyIcon.color, StudioTone.success.indicator(readyContext));
        expect(find.text('已保存，等待继续执行'), findsOneWidget);

        final fault = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            storage: const ThreadStorageStateView(
              fault: ThreadHistoryFault.writeFailed,
              faultGeneration: 2,
              execution: ThreadStorageExecution.paused,
              resumeRequired: true,
              canResume: false,
              lastError: '写入失败',
            ),
          ),
        );
        await tester.pumpWidget(_host(LiveStatusSurfaceView(gate: fault.gate)));

        final faultContext = tester.element(find.byIcon(Icons.error_outline));
        final faultIcon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
        expect(faultIcon.color, faultContext.colors.error);
        expect(find.text('写入失败'), findsOneWidget);
      },
    );

    testWidgets(
      'formats duration >= 60m with hours and >= 24h with days in zh and en',
      (tester) async {
        final hourly = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            liveOpenWork: DisplayBlock(
              id: 'work-h',
              blockOrder: 1,
              body: WorkDisplayBlock(
                timing: const WorkTiming(startedAtMillis: 100_000),
                members: const DisplayBlockRef(
                  blockId: 'work-h',
                  cut: HistoryCut(''),
                  anchorSeq: 1,
                  headSeq: 1,
                ),
                executionPresent: true,
                memberCount: 1,
                unfinishedCount: 1,
                groupClosed: false,
              ),
            ),
            activity: const ThreadActivityView(
              threadId: 'thread-1',
              identity: 'act-h',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.thinking,
              summary: '',
              tools: ThreadActivityTools.empty,
            ),
          ),
        );

        DateTime hourlyNow() =>
            DateTime.fromMillisecondsSinceEpoch(100_000 + (3600 + 125) * 1000);
        await tester.pumpWidget(
          _host(
            LiveStatusSurfaceView(gate: hourly.gate, now: hourlyNow),
            locale: const Locale('zh'),
          ),
        );
        expect(find.text('执行了 1 小时 2 分 5 秒'), findsOneWidget);

        await tester.pumpWidget(
          _host(
            LiveStatusSurfaceView(gate: hourly.gate, now: hourlyNow),
            locale: const Locale('en'),
          ),
        );
        expect(find.text('Running for 1h 2min 5s'), findsOneWidget);

        DateTime dailyNow() => DateTime.fromMillisecondsSinceEpoch(
          100_000 + (86400 + 3 * 3600 + 120) * 1000,
        );
        await tester.pumpWidget(
          _host(
            LiveStatusSurfaceView(gate: hourly.gate, now: dailyNow),
            locale: const Locale('zh'),
          ),
        );
        expect(find.text('执行了 1 日 3 小时 2 分'), findsOneWidget);

        await tester.pumpWidget(
          _host(
            LiveStatusSurfaceView(gate: hourly.gate, now: dailyNow),
            locale: const Locale('en'),
          ),
        );
        expect(find.text('Running for 1d 3h 2min'), findsOneWidget);
      },
    );

    testWidgets(
      'activity tools disclosure, paging callbacks and 360px 1.6x scale work without overflow',
      (tester) async {
        var opened = false;
        var closed = false;
        var nextTapped = false;
        var retried = false;

        final collapsed = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(currentAtomsError: 'Page failed'),
          activityTools: LiveActivityToolsWindow(
            reference: const CurrentCollectionRef(
              ownerId: 'o1',
              collection: 'tools.active',
              revision: 1,
            ),
            totalCount: 5,
            entries: const [],
            expanded: false,
            loading: false,
            hasPrevious: false,
            hasNext: true,
          ),
        );
        await tester.pumpWidget(
          _host(
            LiveStatusSurfaceView(
              gate: collapsed.gate,
              onOpenActivityTools: () => opened = true,
              onRetryError: () => retried = true,
            ),
            width: 360,
            scale: 1.6,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byKey(const ValueKey('live-activity-tools-open')),
        );
        await tester.tap(find.text('重试'));
        expect(opened, isTrue);
        expect(retried, isTrue);

        final expanded = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: const LiveStatusInputs.empty(),
          activityTools: LiveActivityToolsWindow(
            reference: const CurrentCollectionRef(
              ownerId: 'o1',
              collection: 'tools.active',
              revision: 1,
            ),
            totalCount: 5,
            entries: const [
              ThreadActivityToolEntry(
                callId: 'call-1',
                name: 'exec',
                summary: 'cargo flutter analyze',
                arguments: ThreadActivityArgumentsKind.commandLine,
                state: ThreadActivityToolState.running,
              ),
            ],
            expanded: true,
            loading: false,
            hasPrevious: false,
            hasNext: true,
          ),
        );
        await tester.pumpWidget(
          _host(
            LiveStatusSurfaceView(
              gate: expanded.gate,
              onCloseActivityTools: () => closed = true,
              onNextActivityTools: () => nextTapped = true,
            ),
            width: 360,
            scale: 1.6,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('live-activity-tools-count')),
          findsOneWidget,
        );
        expect(find.text('cargo flutter analyze'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('live-activity-tools-next')),
        );
        await tester.tap(
          find.byKey(const ValueKey('live-activity-tools-close')),
        );
        expect(nextTapped, isTrue);
        expect(closed, isTrue);

        // Bounded height with open workgroup + error + expanded activity tools must scroll instead of overflowing.
        final stacked = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            currentAtomsError: 'Paged fetch timed out',
            liveOpenWork: DisplayBlock(
              id: 'work-stacked',
              blockOrder: 1,
              body: WorkDisplayBlock(
                timing: const WorkTiming(startedAtMillis: 100_000),
                members: const DisplayBlockRef(
                  blockId: 'work-stacked',
                  cut: HistoryCut(''),
                  anchorSeq: 1,
                  headSeq: 1,
                ),
                executionPresent: true,
                memberCount: 2,
                unfinishedCount: 1,
                groupClosed: false,
              ),
            ),
            activity: const ThreadActivityView(
              threadId: 'thread-1',
              identity: 'act-stacked',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.runningTool,
              summary: '',
              tools: ThreadActivityTools.empty,
            ),
          ),
          activityTools: LiveActivityToolsWindow(
            reference: const CurrentCollectionRef(
              ownerId: 'o1',
              collection: 'tools.active',
              revision: 2,
            ),
            totalCount: 8,
            entries: const [
              ThreadActivityToolEntry(
                callId: 'call-1',
                name: 'exec',
                summary: 'cargo flutter analyze',
                arguments: ThreadActivityArgumentsKind.commandLine,
                state: ThreadActivityToolState.running,
              ),
              ThreadActivityToolEntry(
                callId: 'call-2',
                name: 'read_file',
                summary: 'design/19-studio-ui.md',
                arguments: ThreadActivityArgumentsKind.opaque,
                state: ThreadActivityToolState.finished,
              ),
            ],
            expanded: true,
            loading: false,
            hasPrevious: false,
            hasNext: true,
          ),
        );
        await tester.pumpWidget(
          _host(
            SizedBox(
              height: 220,
              child: LiveStatusSurfaceView(gate: stacked.gate),
            ),
            width: 760,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('已完成'), findsOneWidget);
      },
    );

    testWidgets(
      'hides long trailing meta on 360px 1.6x layout so work title stays readable',
      (tester) async {
        final projected = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            liveOpenWork: DisplayBlock(
              id: 'work-narrow',
              blockOrder: 1,
              body: WorkDisplayBlock(
                timing: const WorkTiming(startedAtMillis: 100_000),
                members: const DisplayBlockRef(
                  blockId: 'work-narrow',
                  cut: HistoryCut(''),
                  anchorSeq: 1,
                  headSeq: 1,
                ),
                executionPresent: true,
                memberCount: 2,
                unfinishedCount: 1,
                groupClosed: false,
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          _host(
            LiveStatusSurfaceView(
              gate: projected.gate,
              now: () => DateTime.fromMillisecondsSinceEpoch(
                100_000 + (3600 + 15 * 60 + 8) * 1000,
              ),
            ),
            width: 360,
            scale: 1.6,
          ),
        );
        expect(tester.takeException(), isNull);
        final titleFinder = find.text('工作记录');
        expect(titleFinder, findsOneWidget);
        expect(tester.getSize(titleFinder).width, greaterThanOrEqualTo(40));
        expect(find.text('执行了 1 小时 15 分 8 秒'), findsNothing);
      },
    );
  });
}
