import 'package:flutter/material.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../widgets/timeline_activity_group_views.dart';

Widget timelineActivityGroupPreviewHost(
  Widget Function(ValueChanged<String> record) builder, {
  required Object scenarioIdentity,
  double textScale = 1,
}) => _ActivityGroupPreviewHost(
  builder: builder,
  scenarioIdentity: scenarioIdentity,
  textScale: textScale,
);

class _ActivityGroupPreviewHost extends StatefulWidget {
  const _ActivityGroupPreviewHost({
    required this.builder,
    required this.scenarioIdentity,
    required this.textScale,
  });

  final Widget Function(ValueChanged<String> record) builder;
  final Object scenarioIdentity;
  final double textScale;

  @override
  State<_ActivityGroupPreviewHost> createState() =>
      _ActivityGroupPreviewHostState();
}

class _ActivityGroupPreviewHostState extends State<_ActivityGroupPreviewHost> {
  static const _initialAction =
      '合成已完成数据 · 组件仅接受自有 sealed TimelineActivityGroupMessage，轮次与新建组由上层决定';
  String _lastAction = _initialAction;

  @override
  void didUpdateWidget(covariant _ActivityGroupPreviewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scenarioIdentity != widget.scenarioIdentity ||
        oldWidget.textScale != widget.textScale) {
      _lastAction = _initialAction;
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    theme: pureStudioTheme(locale: const Locale('zh')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(widget.textScale)),
      child: ListTileTheme(
        data: Theme.of(context).listTileTheme,
        child: child!,
      ),
    ),
    home: Scaffold(
      body: SelectionArea(
        child: widget.builder((action) => setState(() => _lastAction = action)),
      ),
      bottomNavigationBar: Material(
        color: const Color(0xFFF6F5F2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            _lastAction,
            key: const ValueKey('timeline-preview-last-action'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF5F5E5B)),
          ),
        ),
      ),
    ),
  );
}

abstract final class TimelineActivityGroupPreviewFixtures {
  static final DateTime _baseTime = DateTime.utc(2026, 10, 28, 4, 0, 0);

  static TimelineThinkingGroupMessage completedThinking({
    required String id,
    required int sequence,
    required int startOffsetSeconds,
    required int endOffsetSeconds,
    required String summary,
    String content = '',
    bool rolledBack = false,
  }) => TimelineThinkingGroupMessage(
    id: id,
    order: sequence,
    createdAt: _baseTime.add(Duration(seconds: startOffsetSeconds)),
    completedAt: _baseTime.add(Duration(seconds: endOffsetSeconds)),
    summary: summary,
    content: content,
    rolledBack: rolledBack,
  );

  static TimelineToolGroupMessage completedTool({
    required String id,
    required int sequence,
    required int startOffsetSeconds,
    required int endOffsetSeconds,
    required String toolName,
    required String arguments,
    required String output,
    bool rolledBack = false,
  }) => TimelineToolGroupMessage(
    id: id,
    order: sequence,
    createdAt: _baseTime.add(Duration(seconds: startOffsetSeconds)),
    completedAt: _baseTime.add(Duration(seconds: endOffsetSeconds)),
    toolCallId: 'call-$id',
    name: toolName,
    arguments: arguments,
    output: output,
    rolledBack: rolledBack,
  );

  static TimelineActivityGroupController buildMixedGroup({
    String id = 'preview-mixed-group',
    bool expanded = false,
  }) {
    final controller = TimelineActivityGroupController(
      id: id,
      initiallyExpanded: expanded,
    );
    controller.add(
      completedThinking(
        id: 'think-summary-only',
        sequence: 1,
        startOffsetSeconds: 0,
        endOffsetSeconds: 2,
        summary: '正在梳理 **`TimelineActivityGroupMessage`** 封闭类型与折叠契约',
      ),
    );
    controller.add(
      completedTool(
        id: 'tool-read-file',
        sequence: 2,
        startOffsetSeconds: 2,
        endOffsetSeconds: 5,
        toolName: 'read_file',
        arguments: '{"path":"code/anywork/lib/src/features/timeline/timeline_activity_group_models.dart"}',
        output: 'Read 320 lines from timeline_activity_group_models.dart',
      ),
    );
    controller.add(
      completedThinking(
        id: 'think-with-content',
        sequence: 3,
        startOffsetSeconds: 5,
        endOffsetSeconds: 7,
        summary: '正在设计 **零轮次感知控制器** 与 `add` 持续追加接口',
        content:
            '1. 顶层折叠行移除左侧图标，保持展示 `工作了 8 秒 · 2 个工具`。\n'
            '2. 展开后，仅含 `summary` 的思考行不渲染展开箭头；含 `content` 的思考行支持二次展开查看思考内容。\n'
            '3. 轮次切换与新建工作组由上层决定，组件无需感知 `turnId`。',
      ),
    );
    controller.add(
      completedTool(
        id: 'tool-edit-file',
        sequence: 4,
        startOffsetSeconds: 7,
        endOffsetSeconds: 8,
        toolName: 'edit_file',
        arguments: '{"path":"code/anywork/lib/src/features/timeline/timeline_activity_group_views.dart"}',
        output: 'Updated TimelineActivityGroupBlock to consume TimelineActivityGroupController',
      ),
    );
    return controller;
  }

  static TimelineActivityGroupController buildPureThinkingGroup({
    String id = 'preview-pure-thinking-group',
    bool expanded = false,
  }) {
    final controller = TimelineActivityGroupController(
      id: id,
      initiallyExpanded: expanded,
    );
    controller.add(
      completedThinking(
        id: 'think-pure-1',
        sequence: 1,
        startOffsetSeconds: 0,
        endOffsetSeconds: 3,
        summary: '正在设计方案并核对 `TimelineThinkingGroupMessage` 仅含概要时的非展开约束',
      ),
    );
    return controller;
  }
}

class TimelineActivityGroupInteractivePreview extends StatefulWidget {
  const TimelineActivityGroupInteractivePreview({
    required this.record,
    super.key,
  });

  final ValueChanged<String> record;

  @override
  State<TimelineActivityGroupInteractivePreview> createState() =>
      _TimelineActivityGroupInteractivePreviewState();
}

class _TimelineActivityGroupInteractivePreviewState
    extends State<TimelineActivityGroupInteractivePreview> {
  late TimelineActivityGroupController _controller =
      TimelineActivityGroupPreviewFixtures.buildMixedGroup(
        id: 'preview-interactive-group',
        expanded: true,
      );
  int _nextSeq = 5;
  int _nextSeconds = 8;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _appendMessage(TimelineActivityGroupMessage message, String label) {
    _controller.add(message);
    setState(() {
      widget.record('已追加 $label · 当前共 ${_controller.length} 条成员');
    });
  }

  void _addSummaryOnlyThinking() {
    final start = _nextSeconds;
    final end = start + 2;
    _nextSeconds = end;
    final seq = _nextSeq++;
    _appendMessage(
      TimelineActivityGroupPreviewFixtures.completedThinking(
        id: 'think-summary-$seq',
        sequence: seq,
        startOffsetSeconds: start,
        endOffsetSeconds: end,
        summary: '第 $seq 步：已完成 **`widget-preview`** 纯组件校验（仅概要，不可展开）',
      ),
      '仅概要思考',
    );
  }

  void _addFullThinking() {
    final start = _nextSeconds;
    final end = start + 3;
    _nextSeconds = end;
    final seq = _nextSeq++;
    _appendMessage(
      TimelineActivityGroupPreviewFixtures.completedThinking(
        id: 'think-full-$seq',
        sequence: seq,
        startOffsetSeconds: start,
        endOffsetSeconds: end,
        summary: '第 $seq 步：整理 **Markdown 概要** 与可展开详细思考正文',
        content:
            '详细思考内容（第 $seq 步）：\n- 含 `content` 字段时显示右侧 `>` 箭头\n- 点击可展开阅读完整推理过程',
      ),
      '含正文思考',
    );
  }

  void _addCompletedTool() {
    final start = _nextSeconds;
    final end = start + 2;
    _nextSeconds = end;
    final seq = _nextSeq++;
    _appendMessage(
      TimelineActivityGroupPreviewFixtures.completedTool(
        id: 'tool-call-$seq',
        sequence: seq,
        startOffsetSeconds: start,
        endOffsetSeconds: end,
        toolName: 'search_code',
        arguments: '{"query":"TimelineActivityGroupMessage","step":$seq}',
        output: 'Found 4 matches in code/anywork/lib/src/features/timeline/',
      ),
      '工具调用',
    );
  }

  void _resetGroup() {
    final old = _controller;
    setState(() {
      _controller = TimelineActivityGroupPreviewFixtures.buildMixedGroup(
        id: 'preview-interactive-group-${DateTime.now().millisecondsSinceEpoch}',
        expanded: true,
      );
      _nextSeq = 5;
      _nextSeconds = 8;
    });
    old.dispose();
    widget.record('已重置思考与工具组');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('preview-add-summary-thinking'),
              onPressed: _addSummaryOnlyThinking,
              icon: const Icon(Icons.psychology_alt_outlined, size: 16),
              label: const Text('+ 仅概要思考 (无展开)'),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('preview-add-full-thinking'),
              onPressed: _addFullThinking,
              icon: const Icon(Icons.notes_outlined, size: 16),
              label: const Text('+ 含正文思考 (可展开)'),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('preview-add-tool'),
              onPressed: _addCompletedTool,
              icon: const Icon(Icons.build_outlined, size: 16),
              label: const Text('+ 已完成工具'),
            ),
            TextButton.icon(
              key: const ValueKey('preview-reset-group'),
              onPressed: _resetGroup,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重置'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: StudioLayout.conversationWidth,
          ),
          child: TimelineActivityGroupBlock(
            controller: _controller,
            onOpenDetail: (itemId, field) =>
                widget.record('打开截断详情: $itemId / ${field.runtimeType}'),
          ),
        ),
      ],
    );
  }
}
