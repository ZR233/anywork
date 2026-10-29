import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/timeline/conversation_activity_bar.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CustomDeployState {
  const _CustomDeployState({
    required this.environment,
    this.stepsCompleted = 0,
    this.logs = const <String>[],
  });

  final String environment;
  final int stepsCompleted;
  final List<String> logs;
}

sealed class _CustomDeployEvent {
  const _CustomDeployEvent();
}

final class _CustomDeployStepAdvanced extends _CustomDeployEvent {
  const _CustomDeployStepAdvanced(this.logLine);
  final String logLine;
}

final class _CustomDeployToolSpec
    implements LiveToolSpec<_CustomDeployState, _CustomDeployEvent> {
  const _CustomDeployToolSpec();

  @override
  _CustomDeployState reduce(
    _CustomDeployState state,
    _CustomDeployEvent message,
  ) {
    return switch (message) {
      _CustomDeployStepAdvanced(:final logLine) => _CustomDeployState(
        environment: state.environment,
        stepsCompleted: state.stepsCompleted + 1,
        logs: <String>[...state.logs, logLine],
      ),
    };
  }

  @override
  String buildSummaryLabel(BuildContext context, _CustomDeployState state) =>
      'Deploy(${state.environment}) · step ${state.stepsCompleted}';

  @override
  String? buildSubtitleLabel(BuildContext context, _CustomDeployState state) =>
      null;

  @override
  Widget buildLeading(BuildContext context, _CustomDeployState state) =>
      const Text('⚡');

  @override
  bool isExpandable(_CustomDeployState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    _CustomDeployState state, {
    required int elapsedSeconds,
  }) {
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: [for (final line in state.logs) Text(line)],
    );
  }
}

Widget _wrapWithApp(Widget child) {
  return MaterialApp(
    locale: const Locale('zh'),
    theme: pureStudioTheme(locale: const Locale('zh')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(child: SizedBox(width: 720, child: child)),
    ),
  );
}

void main() {
  group(
    'ConversationLiveStatusController & ConversationActivityBar (Pure Dart)',
    () {
      testWidgets('压缩阶段显示“正在压缩”而非“准备中”，并支持从 ThreadActivityKind.compacting 映射', (
        tester,
      ) async {
        final controller = ConversationLiveStatusController();
        addTearDown(controller.dispose);

        controller.ingest(
          const ConversationLivePhaseMessage(
            identity: 'activity:turn-1:preparing:preparing',
            turnId: 'turn-1',
            phase: ConversationLivePhase.preparing,
          ),
        );

        await tester.pumpWidget(
          _wrapWithApp(
            ConversationActivityBar.fromController(controller: controller),
          ),
        );
        await tester.pump();

        expect(find.text('准备中'), findsOneWidget);
        expect(find.text('正在压缩'), findsNothing);

        controller.ingest(
          const ConversationLivePhaseMessage(
            identity: 'activity:turn-1:preparing:compacting',
            turnId: 'turn-1',
            phase: ConversationLivePhase.compacting,
            summary: '正在归纳历史上下文',
          ),
        );
        await tester.pump();

        expect(find.text('正在压缩'), findsOneWidget);
        expect(find.text('准备中'), findsNothing);
        expect(find.text('正在归纳历史上下文'), findsOneWidget);

        final projected = projectConversationActivity(
          activity: const ThreadActivityView(
            threadId: 'thread-1',
            identity: 'activity:turn-1:preparing:compacting',
            revision: 1,
            turnId: 'turn-1',
            kind: ThreadActivityKind.compacting,
            summary: '',
          ),
        );
        expect(projected?.kind, ConversationActivityKind.compacting);
      });

      testWidgets(
        '思考摘要以 Markdown 显示并在后续工具执行阶段保持粘性，直到新摘要替换；展开后可查看正在执行的工具及秒数详情',
        (tester) async {
          var now = DateTime.utc(2026, 10, 28, 12, 0, 0);
          final controller = ConversationLiveStatusController(clock: () => now);
          addTearDown(controller.dispose);

          controller.ingestAll([
            const ConversationLivePhaseMessage(
              identity: 'activity:turn-1:step-1:thinking',
              turnId: 'turn-1',
              phase: ConversationLivePhase.thinking,
            ),
            const ConversationLiveThinkingSummaryMessage(
              turnId: 'turn-1',
              summaryMarkdown: '正在准备计划并检查 `LiveToolSpec`',
              elapsedSeconds: 3,
            ),
          ]);

          await tester.pumpWidget(
            _wrapWithApp(
              ConversationActivityBar.fromController(controller: controller),
            ),
          );
          await tester.pump();

          expect(find.text('思考了 3 秒'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('conversation-activity-sticky-summary')),
            findsOneWidget,
          );

          // 进入工具执行阶段（不带新思考摘要）：外层仍然保持上一步的思考摘要作为最外部展示。
          final toolStart = now;
          now = now.add(const Duration(seconds: 4));
          controller.ingestAll([
            const ConversationLivePhaseMessage(
              identity: 'activity:turn-1:step-1:runningTool',
              turnId: 'turn-1',
              phase: ConversationLivePhase.runningTool,
            ),
            ConversationLiveToolStartedMessage<
              CommandLiveToolState,
              CommandLiveToolEvent
            >(
              callId: 'call-exec-1',
              toolName: 'exec',
              spec: const CommandLiveToolSpec(),
              initialState: const CommandLiveToolState(
                command: 'cargo test --workspace',
                workingDirectory: 'code/pl-core',
                stdout: 'running 12 tests',
              ),
              startedAt: toolStart,
            ),
          ]);
          await tester.pump();

          // 最外层依旧展示粘性思考摘要，并提示有工具在执行。
          expect(find.text('思考了 3 秒'), findsOneWidget);
          expect(find.text('1 项工具执行中'), findsOneWidget);

          // 点击展开状态栏，内部展示正在执行的工具及已执行秒数（4s）。
          await tester.tap(find.byKey(const ValueKey('conversation-activity')));
          await tester.pump();

          expect(
            find.byKey(const ValueKey('conversation-activity-details')),
            findsOneWidget,
          );
          expect(
            find.text('cargo test --workspace  code/pl-core'),
            findsOneWidget,
          );
          expect(find.text('4s'), findsOneWidget);

          // 点击工具行二次展开详情，看到已执行秒数与流式 stdout。
          await tester.tap(
            find.byKey(const ValueKey('live-tool-row-call-exec-1')),
          );
          await tester.pump();

          expect(
            find.byKey(const ValueKey('live-tool-details-call-exec-1')),
            findsOneWidget,
          );
          expect(find.text('已执行 4s'), findsOneWidget);
          expect(find.text('running 12 tests'), findsOneWidget);

          // 时钟推进 3 秒并喂入工具流式事件：秒数更新为 7s，stdout 追加新行。
          now = now.add(const Duration(seconds: 3));
          controller.ingest(
            const ConversationLiveToolEventMessage<CommandLiveToolEvent>(
              callId: 'call-exec-1',
              event: CommandStdoutAppendEvent('\ntest result: ok.'),
            ),
          );
          await tester.pump();

          expect(find.text('7s'), findsOneWidget);
          expect(find.text('已执行 7s'), findsOneWidget);
          expect(find.textContaining('test result: ok.'), findsOneWidget);

          // 出现新的思考摘要时，外层立即替换为新摘要。
          controller.ingest(
            const ConversationLiveThinkingSummaryMessage(
              turnId: 'turn-1',
              summaryMarkdown: '正在整理测试结果并生成变更报告',
              elapsedSeconds: 6,
            ),
          );
          await tester.pump();

          expect(find.text('思考了 6 秒'), findsOneWidget);
          expect(find.text('思考了 3 秒'), findsNothing);
        },
      );

      testWidgets('泛型 LiveToolSpec<S, M> 支持外部自定义工具状态与消息，无需修改状态栏组件', (
        tester,
      ) async {
        var now = DateTime.utc(2026, 10, 28, 12, 0, 0);
        final controller = ConversationLiveStatusController(clock: () => now);
        addTearDown(controller.dispose);

        controller.ingestAll([
          const ConversationLivePhaseMessage(
            identity: 'activity:turn-custom:runningTool',
            turnId: 'turn-custom',
            phase: ConversationLivePhase.runningTool,
          ),
          ConversationLiveToolStartedMessage<
            _CustomDeployState,
            _CustomDeployEvent
          >(
            callId: 'call-deploy-1',
            toolName: 'custom_deploy',
            spec: const _CustomDeployToolSpec(),
            initialState: const _CustomDeployState(environment: 'staging'),
            startedAt: now,
          ),
        ]);

        // 喂入自定义工具事件
        now = now.add(const Duration(seconds: 5));
        controller.ingest(
          const ConversationLiveToolEventMessage<_CustomDeployEvent>(
            callId: 'call-deploy-1',
            event: _CustomDeployStepAdvanced('Uploaded bundle artifact'),
          ),
        );
        controller.ingest(
          const ConversationLiveToolEventMessage<_CustomDeployEvent>(
            callId: 'call-deploy-1',
            event: _CustomDeployStepAdvanced('Healthcheck passed'),
          ),
        );

        await tester.pumpWidget(
          _wrapWithApp(
            ConversationActivityBar.fromController(controller: controller),
          ),
        );
        await tester.pump();

        expect(find.text('Deploy(staging) · step 2'), findsOneWidget);

        // 展开顶层与自定义工具详情
        controller.setExpanded(true);
        controller.setToolExpanded('call-deploy-1', true);
        await tester.pump();

        expect(find.text('已执行 5s'), findsOneWidget);
        expect(find.text('Uploaded bundle artifact'), findsOneWidget);
        expect(find.text('Healthcheck passed'), findsOneWidget);
      });

      testWidgets('流式思考内容：有摘要只显示摘要；无摘要显示一行流式更新并前向截断，可展开查看完整思考正文', (
        tester,
      ) async {
        final controller = ConversationLiveStatusController();
        addTearDown(controller.dispose);

        controller.ingest(
          const ConversationLivePhaseMessage(
            identity: 'activity:turn-stream:thinking',
            turnId: 'turn-stream',
            phase: ConversationLivePhase.thinking,
          ),
        );
        controller.ingest(
          const ConversationLiveThinkingStreamMessage.append(
            '第一段早期推理内容会被截断在最前面，只保留最新流式追加的尾部文字供单行预览阅读。',
          ),
        );
        controller.ingest(
          const ConversationLiveThinkingStreamMessage.append(
            '第二段新增的流式思考内容持续推进，确保尾部始终可见：TAIL_MARKER_99',
          ),
        );

        expect(controller.hasStickyThinkingSummary, isFalse);
        expect(controller.hasStreamingThinkingWithoutSummary, isTrue);
        final truncated = controller.frontTruncatedThinkingLine(maxChars: 32);
        expect(truncated.startsWith('…'), isTrue);
        expect(truncated.endsWith('TAIL_MARKER_99'), isTrue);

        await tester.pumpWidget(
          _wrapWithApp(
            ConversationActivityBar.fromController(controller: controller),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(
            const ValueKey('conversation-activity-thinking-stream-single-line'),
          ),
          findsOneWidget,
        );

        // 点击展开查看完整思考内容
        await tester.tap(find.byKey(const ValueKey('conversation-activity')));
        await tester.pump();

        expect(
          find.byKey(const ValueKey('conversation-activity-thinking-full')),
          findsOneWidget,
        );
        expect(controller.thinkingStreamText, contains('第一段早期推理内容会被截断在最前面'));

        // 一旦喂入思考摘要，外层立即只显示思考摘要，不再显示单行流式思考正文
        controller.ingest(
          const ConversationLiveThinkingSummaryMessage(
            turnId: 'turn-stream',
            summaryMarkdown: '已收敛出最终架构设计方案',
            elapsedSeconds: 4,
          ),
        );
        await tester.pump();

        expect(
          find.byKey(
            const ValueKey('conversation-activity-thinking-stream-single-line'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('conversation-activity-sticky-summary')),
          findsOneWidget,
        );
      });

      testWidgets('文本输出（responding）直接流式展示全部内容，随内容动态增高，达最大高度可滚动，且不可展开', (
        tester,
      ) async {
        final controller = ConversationLiveStatusController();
        addTearDown(controller.dispose);

        controller.ingestAll([
          const ConversationLivePhaseMessage(
            identity: 'activity:turn-resp:responding',
            turnId: 'turn-resp',
            phase: ConversationLivePhase.responding,
          ),
          const ConversationLiveResponseStreamMessage.replace('第一行回复正文。'),
        ]);

        await tester.pumpWidget(
          _wrapWithApp(
            ConversationActivityBar.fromController(
              controller: controller,
              maxResponseHeight: 120,
            ),
          ),
        );
        await tester.pump();

        expect(controller.isExpandable, isFalse);
        expect(controller.expanded, isFalse);
        expect(
          find.byKey(const ValueKey('conversation-activity-response-stream')),
          findsOneWidget,
        );

        final initialHeight = tester
            .getSize(find.byKey(const ValueKey('conversation-activity')))
            .height;

        // 追加多行文本，状态栏高度动态增长
        controller.ingest(
          const ConversationLiveResponseStreamMessage.append(
            '\n\n第二行新增流式文本。\n\n第三行新增流式文本。',
          ),
        );
        await tester.pump();

        final grownHeight = tester
            .getSize(find.byKey(const ValueKey('conversation-activity')))
            .height;
        expect(grownHeight, greaterThan(initialHeight));

        // 继续追加大量文本，受限于 maxResponseHeight 封顶并可滚动
        for (var i = 0; i < 20; i++) {
          controller.ingest(
            ConversationLiveResponseStreamMessage.append(
              '\n- 第 $i 条详细输出说明，验证达到最大高度上限后不再无限撑高状态栏。',
            ),
          );
        }
        await tester.pump();

        final streamBoxSize = tester.getSize(
          find.byKey(const ValueKey('conversation-activity-response-stream')),
        );
        expect(streamBoxSize.height, lessThanOrEqualTo(120.0));

        // 尝试点击状态栏不会触发任何展开行为，也不存在展开详情区
        await tester.tap(find.byKey(const ValueKey('conversation-activity')));
        await tester.pump();
        expect(controller.expanded, isFalse);
        expect(
          find.byKey(const ValueKey('conversation-activity-details')),
          findsNothing,
        );
      });
    },
  );
}
