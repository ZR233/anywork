import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../app/theme/material3_theme.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../conversation_activity_bar.dart';

Widget _liveStatusPreviewHost(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    theme: pureStudioTheme(locale: const Locale('zh')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAF9F5),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: StudioLayout.conversationWidth,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

abstract final class ConversationLiveStatusPreviewFixtures {
  static final DateTime _baseClock = DateTime.utc(2026, 10, 28, 12, 0, 12);

  static ConversationLiveStatusController buildCompactingController() {
    final controller = ConversationLiveStatusController(
      clock: () => _baseClock,
    );
    controller.ingest(
      const ConversationLivePhaseMessage(
        identity: 'preview:turn-1:compacting',
        turnId: 'turn-1',
        phase: ConversationLivePhase.compacting,
        summary: '正在总结前序 28 条历史记录并释放上下文窗口…',
      ),
    );
    return controller;
  }

  static ConversationLiveStatusController
  buildStickySummaryWithToolsController({bool expanded = true}) {
    final controller = ConversationLiveStatusController(
      clock: () => _baseClock,
    );
    controller.ingestAll([
      const ConversationLivePhaseMessage(
        identity: 'preview:turn-2:running-tool',
        turnId: 'turn-2',
        phase: ConversationLivePhase.runningTool,
      ),
      const ConversationLiveThinkingSummaryMessage(
        turnId: 'turn-2',
        summaryMarkdown: '正在准备重构方案并核对 `LiveToolSpec<S, M>` 泛型契约',
        elapsedSeconds: 3,
      ),
      const ConversationLiveThinkingStreamMessage.replace(
        '首先梳理 `ConversationLiveStatusController` 的状态归约边界：\n'
        '1. 压缩上下文阶段独立映射为 `compacting`（展示“正在压缩”）；\n'
        '2. 思考摘要一旦出现即保持粘性作为最外层展示，直到新摘要替换；\n'
        '3. 内部正在执行的工具通过 `LiveToolSpec<S, M>` 抹除具体类型。',
      ),
      ConversationLiveToolStartedMessage<
        CommandLiveToolState,
        CommandLiveToolEvent
      >(
        callId: 'call-exec-1',
        toolName: 'exec',
        spec: const CommandLiveToolSpec(),
        initialState: const CommandLiveToolState(
          command: 'cargo test -p pl-core --test model_execution_phases',
          workingDirectory: 'code/pl-core',
          stdout: 'Compiling pl-core v0.1.0\nRunning tests/model_execution_phases.rs\ntest compacting_phase_published ... ok',
        ),
        startedAt: _baseClock.subtract(const Duration(seconds: 6)),
      ),
      ConversationLiveToolStartedMessage<FileLiveToolState, FileLiveToolEvent>(
        callId: 'call-edit-2',
        toolName: 'edit',
        spec: const FileLiveToolSpec(),
        initialState: const FileLiveToolState(
          operation: 'edit',
          path: 'code/anywork/lib/src/features/timeline/conversation_activity_bar.dart',
          lineRange: 'L1-240',
          diffPreview: '+ class ConversationActivityBar extends StatefulWidget {\n+   const ConversationActivityBar.fromController({required this.controller});',
        ),
        startedAt: _baseClock.subtract(const Duration(seconds: 3)),
      ),
      ConversationLiveToolStartedMessage<
        WebSearchLiveToolState,
        WebSearchLiveToolEvent
      >(
        callId: 'call-search-3',
        toolName: 'web_search',
        spec: const WebSearchLiveToolSpec(),
        initialState: const WebSearchLiveToolState(
          toolName: 'web_search',
          queries: [
            'Flutter Widget Preview @Preview annotation',
            'GptMarkdown',
          ],
          resultsPreview: 'Matched 4 official documentation entries.',
        ),
        startedAt: _baseClock.subtract(const Duration(seconds: 2)),
      ),
    ]);
    if (expanded) {
      controller.setExpanded(true);
      controller.setToolExpanded('call-exec-1', true);
    }
    return controller;
  }

  static ConversationLiveStatusController
  buildStreamingThinkingWithoutSummaryController({bool expanded = false}) {
    final controller = ConversationLiveStatusController(
      clock: () => _baseClock,
    );
    controller.ingestAll([
      const ConversationLivePhaseMessage(
        identity: 'preview:turn-3:thinking',
        turnId: 'turn-3',
        phase: ConversationLivePhase.thinking,
      ),
      const ConversationLiveThinkingStreamMessage.replace(
        '正在检查会话输入框上方状态栏在无思考摘要时的流式思考表现：外层只显示单行流式内容，随增量不断更新并截断前面部分，点击可展开查看完整推理正文与滚动条。',
      ),
    ]);
    if (expanded) {
      controller.setExpanded(true);
    }
    return controller;
  }

  static ConversationLiveStatusController buildRespondingStreamController() {
    final controller = ConversationLiveStatusController(
      clock: () => _baseClock,
    );
    controller.ingestAll([
      const ConversationLivePhaseMessage(
        identity: 'preview:turn-4:responding',
        turnId: 'turn-4',
        phase: ConversationLivePhase.responding,
      ),
      const ConversationLiveResponseStreamMessage.replace(
        '已完成会话实时状态栏的组件化重构：\n\n'
        '- **压缩阶段独立展示**：上下文压缩时明确展示 `正在压缩`；\n'
        '- **思考摘要粘性展示**：出现思考摘要后以 Markdown 渲染（如 `思考了 3 秒 · 正在准备计划`），后续工具执行阶段保持在外层，直到新摘要替换；\n'
        '- **泛型工具消息架构**：通过 `LiveToolSpec<S, M>` 支持任意工具与工具自定义流式事件，新增工具零修改状态栏组件。',
      ),
    ]);
    return controller;
  }
}

@Preview(
  name: 'Live Status / 1. Compacting Context (正在压缩)',
  group: 'Timeline · Live Status Bar',
  size: Size(760, 140),
)
Widget conversationLiveStatusCompactingPreview() => _liveStatusPreviewHost(
  ConversationActivityBar.fromController(
    controller:
        ConversationLiveStatusPreviewFixtures.buildCompactingController(),
  ),
);

@Preview(
  name: 'Live Status / 2. Sticky Thinking Summary + Running Tools (展开态)',
  group: 'Timeline · Live Status Bar',
  size: Size(760, 380),
)
Widget
conversationLiveStatusStickySummaryExpandedPreview() => _liveStatusPreviewHost(
  ConversationActivityBar.fromController(
    controller:
        ConversationLiveStatusPreviewFixtures.buildStickySummaryWithToolsController(
          expanded: true,
        ),
  ),
);

@Preview(
  name: 'Live Status / 3. Streaming Thinking Without Summary (单行前向截断)',
  group: 'Timeline · Live Status Bar',
  size: Size(760, 260),
)
Widget conversationLiveStatusThinkingStreamPreview() => _liveStatusPreviewHost(
  ConversationActivityBar.fromController(
    controller:
        ConversationLiveStatusPreviewFixtures.buildStreamingThinkingWithoutSummaryController(
          expanded: true,
        ),
  ),
);

@Preview(
  name: 'Live Status / 4. Streaming Text Output (动态增高 · 不可展开)',
  group: 'Timeline · Live Status Bar',
  size: Size(760, 280),
)
Widget conversationLiveStatusRespondingPreview() => _liveStatusPreviewHost(
  ConversationActivityBar.fromController(
    controller:
        ConversationLiveStatusPreviewFixtures.buildRespondingStreamController(),
  ),
);

@Preview(
  name: 'Live Status / 5. Interactive Sealed Message Feeder (交互式喂入台)',
  group: 'Timeline · Live Status Bar',
  size: Size(820, 520),
)
Widget conversationLiveStatusInteractivePreview() =>
    _liveStatusPreviewHost(const _InteractiveLiveStatusFeeder());

class _InteractiveLiveStatusFeeder extends StatefulWidget {
  const _InteractiveLiveStatusFeeder();

  @override
  State<_InteractiveLiveStatusFeeder> createState() =>
      _InteractiveLiveStatusFeederState();
}

class _InteractiveLiveStatusFeederState
    extends State<_InteractiveLiveStatusFeeder> {
  late final ConversationLiveStatusController _controller;
  int _summaryCounter = 1;
  int _chunkCounter = 1;

  @override
  void initState() {
    super.initState();
    _controller =
        ConversationLiveStatusPreviewFixtures.buildStickySummaryWithToolsController(
          expanded: true,
        );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('喂入：正在压缩'),
              onPressed: () {
                _controller.ingest(
                  const ConversationLivePhaseMessage(
                    identity: 'interactive:compacting',
                    turnId: 'turn-interactive',
                    phase: ConversationLivePhase.compacting,
                    summary: '正在压缩历史上下文…',
                  ),
                );
              },
            ),
            ActionChip(
              label: const Text('喂入：新思考摘要 (替换粘性摘要)'),
              onPressed: () {
                _summaryCounter++;
                _controller.ingestAll([
                  const ConversationLivePhaseMessage(
                    identity: 'interactive:running-tool',
                    turnId: 'turn-interactive',
                    phase: ConversationLivePhase.runningTool,
                  ),
                  ConversationLiveThinkingSummaryMessage(
                    turnId: 'turn-interactive',
                    summaryMarkdown:
                        '第 $_summaryCounter 阶段：正在验证 `LiveToolSpec<S, M>` 与 **无框纯文本导引线**',
                    elapsedSeconds: 2 + _summaryCounter,
                  ),
                ]);
              },
            ),
            ActionChip(
              label: const Text('喂入：流式思考 Delta (无摘要)'),
              onPressed: () {
                _chunkCounter++;
                _controller.ingestAll([
                  ConversationLivePhaseMessage(
                    identity: 'interactive:thinking-raw',
                    turnId: 'turn-raw-$_chunkCounter',
                    phase: ConversationLivePhase.thinking,
                  ),
                  ConversationLiveThinkingStreamMessage.append(
                    ' [片段 #$_chunkCounter: 正在推导前向截断与最大高度滚动条约束]',
                  ),
                ]);
              },
            ),
            ActionChip(
              label: const Text('喂入：工具流式 Stdout 事件'),
              onPressed: () {
                _chunkCounter++;
                _controller.ingest(
                  ConversationLiveToolEventMessage<CommandLiveToolEvent>(
                    callId: 'call-exec-1',
                    event: CommandStdoutAppendEvent(
                      '\n[chunk #$_chunkCounter] test live_tool_spec_reduction ... ok',
                    ),
                  ),
                );
              },
            ),
            ActionChip(
              label: const Text('喂入：流式文本回复 (不可展开)'),
              onPressed: () {
                _chunkCounter++;
                _controller.ingestAll([
                  const ConversationLivePhaseMessage(
                    identity: 'interactive:responding',
                    turnId: 'turn-interactive',
                    phase: ConversationLivePhase.responding,
                  ),
                  ConversationLiveResponseStreamMessage.append(
                    '\n- 新增流式输出行 #$_chunkCounter：状态栏随正文动态增高，达到上限后出现滚动条，无展开箭头。',
                  ),
                ]);
              },
            ),
          ],
        ),
        const Spacer(),
        ConversationActivityBar.fromController(controller: _controller),
      ],
    );
  }
}
