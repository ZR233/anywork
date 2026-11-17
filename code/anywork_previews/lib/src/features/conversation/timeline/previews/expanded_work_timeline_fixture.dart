import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_ui_controllers.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:material_ui/material_ui.dart';

import 'timeline_preview_fixtures.dart';

/// Synthetic immutable rows and UI-only controls. No native or query assembly.
/// Both historical messages and the live bottomSliver use production TimelineView
/// and CompletionRunView. Member 001 / 060 / 120 are the screenshot landmarks.
class ExpandedWorkTimelineFixture extends StatefulWidget {
  const ExpandedWorkTimelineFixture({
    this.location = WorkDisplayLocation.history,
    this.textScale = 1,
    this.initiallyExpanded = true,
    this.initialCount = 120,
    super.key,
  });
  final WorkDisplayLocation location;
  final double textScale;
  final bool initiallyExpanded;
  final int initialCount;
  @override
  State<ExpandedWorkTimelineFixture> createState() =>
      ExpandedWorkTimelineFixtureState();
}

class ExpandedWorkTimelineFixtureState
    extends State<ExpandedWorkTimelineFixture> {
  late final controls = ExpandedWorkPreviewControls();
  late final TimelineDisplayUnit unit;
  late int count = widget.initialCount;
  bool grown = false;
  TimelineDisplayMode mode = TimelineDisplayMode.live;
  bool get isHistory => widget.location == WorkDisplayLocation.history;
  int get middle => (widget.initialCount / 2).ceil();

  @override
  void initState() {
    super.initState();
    unit = TimelineDisplayUnit(
      block: DisplayBlock(
        id: 'expanded-preview-work',
        blockOrder: 2,
        body: WorkDisplayBlock(
          timing: WorkTiming(
            startedAt: isHistory ? 100 : null,
            finishedAt: isHistory ? 225 : null,
          ),
          executionPresent: !isHistory,
          memberCount: 120,
          unfinishedCount: isHistory ? 0 : 120,
          groupClosed: isHistory,
          members: const DisplayBlockRef(
            cut: HistoryCut('preview'),
            anchorSeq: 1,
            headSeq: 1,
            blockId: 'expanded-preview-work',
          ),
        ),
      ),
      expansion: TimelineExpansionIntent()..expanded = widget.initiallyExpanded,
    );
    controls.controller.setMessages([
      _textMessage('before-work', '工作组之前：先核对代码、接口与验证范围。'),
      _workMessage(),
      _textMessage('after-work', '工作组之后：所有成员沿主时间线自然阅读。'),
    ], animated: false);
  }

  Message _textMessage(String id, String text) {
    final item = TimelinePreviewFixtures.item(
      id,
      'text',
      const {'channel': 'final', 'attachments': []},
      bodies: [TimelinePreviewFixtures.body('body', text)],
    );
    return Message.custom(
      id: id,
      authorId: 'assistant',
      metadata: {chatItemPresentationKey: item},
    );
  }

  Message _workMessage() => Message.custom(
    id: unit.id,
    authorId: 'assistant',
    metadata: {chatItemPresentationKey: ChatItemPresentation.forUnit(unit)},
  );

  void appendMember() => setState(() => count++);
  Future<void> growMiddle() async {
    // An explicit asynchronous UI action, not polling or a layout timer.
    await Future<void>.value();
    if (mounted) {
      setState(() => grown = true);
    }
  }

  @override
  void dispose() {
    unit.expansion.retire();
    unit.expansion.dispose();
    controls.dispose();
    super.dispose();
  }

  Widget _markdown(String id, String text) => TimelineMarkdown(
    id: id,
    text: text,
    onLink: (_) {},
    isSafeLink: (_) => false,
    imageBuilder: (_, _) => const SizedBox.shrink(),
  );

  Widget _rows() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (var i = 1; i <= count; i++) _row(i)],
  );
  Widget _row(int i) {
    final number = i.toString().padLeft(3, '0');
    final title =
        '成员 $number · ${i == 1
            ? '首项'
            : i == middle
            ? '中段'
            : i == count
            ? '尾项'
            : '检查'}';
    final tool = i.isEven;
    final lines = i % 7 == 0 ? 12 : 1 + i % 3;
    final long = grown && i == middle;
    final text = [
      for (var line = 1; line <= (long ? 30 : lines); line++)
        '第 $number 项第 $line 行：核对生产组件、自然换行、完整结果与租约生命周期。',
    ].join('\n\n');
    return Padding(
      key: ValueKey('expanded-member-$number'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, key: ValueKey('expanded-marker-$number')),
          if (tool)
            TimelineToolDetails(
              key: ValueKey('expanded-tool-$number'),
              initiallyExpanded: i == 1 || i == middle || i == count,
              item: TimelineToolPresentation(
                id: 'preview-tool-$number',
                toolCallId: 'preview-call-$number',
                name: 'exec',
                presentationContract: 'builtin.exec@2',
                statusString: 'succeeded',
                arguments: jsonEncode({'command': '检查第 $number 项接口'}),
                output: jsonEncode({
                  'stdout': {'content': text},
                  'stderr': {'content': ''},
                  'exitCode': 0,
                }),
              ),
            )
          else
            TimelineReasoningView(
              key: ValueKey('expanded-reasoning-$number'),
              summary: '第 $number 项：理解调用链与边界',
              initiallyExpanded: i == 1 || i == middle || i == count,
              body: _markdown('preview-reasoning-$number', text),
            ),
          if (long) _markdown('async-height-$number', '异步详情已完成\n\n$text'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    theme: pureStudioTheme(locale: const Locale('zh')),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
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
      body: Column(
        children: [
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                key: const ValueKey('expanded-append'),
                onPressed: appendMember,
                child: const Text('追加成员'),
              ),
              TextButton(
                key: const ValueKey('expanded-grow'),
                onPressed: growMiddle,
                child: Text('异步加高中段第 $middle 项'),
              ),
              Text('完整 $count 项 · ${isHistory ? '历史消息行' : '当前消息行'}'),
            ],
          ),
          Expanded(
            child: TimelineView(
              threadId: 'expanded-work-preview',
              controls: controls,
              view: TimelineSessionViewState(
                threadId: 'expanded-work-preview',
                generation: 1,
                mode: mode,
                connection: TimelineConnectionPhase.ready,
              ),
              onLoadOlder: () async {},
              onRetryOlder: () async {},
              onReturnLive: () async {
                if (mounted) {
                  setState(() => mode = TimelineDisplayMode.live);
                }
              },
              onEnterHistory: () {
                if (mounted && mode != TimelineDisplayMode.history) {
                  setState(() => mode = TimelineDisplayMode.history);
                }
              },
              onRetryConnection: () {},
              onLink: (_) {},
              isSafeLink: (_) => false,
              remoteImageBuilder: (_, _) => const SizedBox.shrink(),
              groupMembersBuilder: (_) => _rows(),
            ),
          ),
        ],
      ),
    ),
  );
}

final class ExpandedWorkPreviewControls implements TimelineUiControllers {
  @override
  final Key chatKey = const ValueKey('expanded-work-preview-chat');
  @override
  final InMemoryChatController controller = InMemoryChatController();
  @override
  final ScrollController scrollController = ScrollController();
  @override
  bool get isRetired => false;
  @override
  void bind() {}
  @override
  Future<void> unbind() async {}
  void dispose() {
    controller.dispose();
    scrollController.dispose();
  }
}
