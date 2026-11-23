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
      'error attention retry works at 360px 1.6x without overflow and respects header tool rules',
      (tester) async {
        var retried = false;

        final errorOnly = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(currentAtomsError: 'Page failed'),
        );
        await tester.pumpWidget(
          _host(
            LiveStatusSurfaceView(
              gate: errorOnly.gate,
              onRetryError: () => retried = true,
            ),
            width: 360,
            scale: 1.6,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('重试'));
        expect(retried, isTrue);

        // 1. Running exec tool shows command summary directly with circularProgress (no "工作中").
        final runningExec = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            activity: ThreadActivityView(
              threadId: 'thread-1',
              identity: 'act-exec',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.runningTool,
              summary: '',
              tools: ThreadActivityTools(
                count: 1,
                active: const [
                  ThreadActivityToolEntry(
                    callId: 'c-exec',
                    name: 'exec',
                    summary: 'cargo flutter test test/ui',
                    arguments: ThreadActivityArgumentsKind.commandLine,
                    state: ThreadActivityToolState.running,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          _host(LiveStatusSurfaceView(gate: runningExec.gate)),
        );
        expect(find.text('cargo flutter test test/ui'), findsOneWidget);
        expect(find.textContaining('工作中'), findsNothing);
        expect(
          tester
              .widget<TimelineActivityIndicator>(
                find.byType(TimelineActivityIndicator),
              )
              .style,
          TimelineActivityIndicatorStyle.circularProgress,
        );

        // 2. Running non-command tool shows tool summary directly with restingCat.
        final runningWrite = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            activity: ThreadActivityView(
              threadId: 'thread-1',
              identity: 'act-write',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.runningTool,
              summary: '',
              tools: ThreadActivityTools(
                count: 1,
                active: const [
                  ThreadActivityToolEntry(
                    callId: 'c-write',
                    name: 'write_file',
                    summary: '写入 design/19-studio-ui.md',
                    arguments: ThreadActivityArgumentsKind.opaque,
                    state: ThreadActivityToolState.running,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          _host(LiveStatusSurfaceView(gate: runningWrite.gate)),
        );
        expect(find.text('写入 design/19-studio-ui.md'), findsOneWidget);
        expect(find.textContaining('工作中'), findsNothing);
        expect(
          tester
              .widget<TimelineActivityIndicator>(
                find.byType(TimelineActivityIndicator),
              )
              .style,
          TimelineActivityIndicatorStyle.restingCat,
        );

        // 3. RunningTool without summary falls back to "思考中" + restingCat.
        final runningWithoutSummary = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            activity: const ThreadActivityView(
              threadId: 'thread-1',
              identity: 'act-empty-tool',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.runningTool,
              summary: '',
              tools: ThreadActivityTools.empty,
            ),
          ),
        );
        await tester.pumpWidget(
          _host(LiveStatusSurfaceView(gate: runningWithoutSummary.gate)),
        );
        expect(find.text('思考中'), findsOneWidget);
        expect(find.textContaining('工作中'), findsNothing);
        expect(
          tester
              .widget<TimelineActivityIndicator>(
                find.byType(TimelineActivityIndicator),
              )
              .style,
          TimelineActivityIndicatorStyle.restingCat,
        );

        // 4. Open work with thinkingSummary keeps thought label + restingCat even when exec runs.
        final workWithThought = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            currentAtomsError: 'Paged fetch timed out',
            liveOpenWork: DisplayBlock(
              id: 'work-thought',
              blockOrder: 1,
              body: const WorkDisplayBlock(
                timing: WorkTiming(startedAtMillis: 100_000),
                summary: '优先梳理状态机投影边界',
                members: DisplayBlockRef(
                  blockId: 'work-thought',
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
            activity: ThreadActivityView(
              threadId: 'thread-1',
              identity: 'act-work-exec',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.runningTool,
              summary: '',
              tools: ThreadActivityTools(
                count: 1,
                active: const [
                  ThreadActivityToolEntry(
                    callId: 'c-exec-2',
                    name: 'exec',
                    summary: 'cargo flutter analyze',
                    arguments: ThreadActivityArgumentsKind.commandLine,
                    state: ThreadActivityToolState.running,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          _host(LiveStatusSurfaceView(gate: workWithThought.gate), width: 760),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('优先梳理状态机投影边界'), findsOneWidget);
        expect(
          tester
              .widget<TimelineActivityIndicator>(
                find.descendant(
                  of: find.byType(CompletionRunView),
                  matching: find.byType(TimelineActivityIndicator),
                ),
              )
              .style,
          TimelineActivityIndicatorStyle.restingCat,
        );
      },
    );

    testWidgets(
      'open work absorbs approval on header and hides long trailing meta at 360px 1.6x',
      (tester) async {
        final projected = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            activity: const ThreadActivityView(
              threadId: 'thread-1',
              identity: 'appr-narrow',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.awaitingApproval,
              summary: 'exec: cargo flutter test',
              tools: ThreadActivityTools.empty,
            ),
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
              liveWorkChildBuilder: (_) => const Text('member details'),
              now: () => DateTime.fromMillisecondsSinceEpoch(
                100_000 + (3600 + 15 * 60 + 8) * 1000,
              ),
            ),
            width: 360,
            scale: 1.6,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(CompletionRunView), findsOneWidget);
        expect(find.byType(ConversationActivityStatus), findsNothing);
        expect(find.text('工作记录'), findsNothing);
        final titleFinder = find.textContaining('等待工具授权');
        expect(titleFinder, findsOneWidget);
        expect(tester.getSize(titleFinder).width, greaterThanOrEqualTo(40));
        expect(find.text('执行了 1 小时 15 分 8 秒'), findsNothing);

        await tester.tap(find.byType(CompletionRunView));
        await tester.pumpAndSettle();
        expect(find.text('member details'), findsOneWidget);
      },
    );

    testWidgets(
      'stopping is absorbed by open work group and shows alongside streaming response',
      (tester) async {
        final workStopping = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            activity: const ThreadActivityView(
              threadId: 'thread-1',
              identity: 'stop-work',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.stopping,
              summary: '',
              tools: ThreadActivityTools.empty,
            ),
            liveOpenWork: DisplayBlock(
              id: 'work-stop',
              blockOrder: 1,
              body: const WorkDisplayBlock(
                timing: WorkTiming(startedAtMillis: 100_000),
                members: DisplayBlockRef(
                  blockId: 'work-stop',
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
          ),
        );
        await tester.pumpWidget(
          _host(LiveStatusSurfaceView(gate: workStopping.gate)),
        );
        expect(find.byType(CompletionRunView), findsOneWidget);
        expect(find.byType(ConversationActivityStatus), findsNothing);
        expect(find.text('停止中'), findsOneWidget);

        final responseStopping = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            activity: const ThreadActivityView(
              threadId: 'thread-1',
              identity: 'stop-resp',
              revision: 1,
              turnId: 'turn-1',
              kind: ThreadActivityKind.stopping,
              summary: '',
              tools: ThreadActivityTools.empty,
            ),
            previewResponseText: '正在终止当前输出',
            previewResponseStartedAt: 100,
          ),
        );
        await tester.pumpWidget(
          _host(LiveStatusSurfaceView(gate: responseStopping.gate)),
        );
        expect(find.byType(CompletionRunView), findsNothing);
        expect(find.byType(ConversationResponseView), findsOneWidget);
        expect(find.byType(ConversationActivityStatus), findsOneWidget);
        expect(find.text('停止中'), findsOneWidget);
      },
    );
  });
}
