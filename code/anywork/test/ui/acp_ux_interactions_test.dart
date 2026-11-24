import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_composer_connector.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_timeline_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_content_view_model.dart';
import 'package:anywork/src/features/conversation/workspace/conversation_workspace.dart';
import 'package:anywork/src/features/conversation/timeline/state/patch_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_patch_diff_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

Widget _zhApp(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('diff 统计徽标、工具 meta 统计与路径一键复制', (tester) async {
    String? copiedText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final doc = mapAcpDiffPresentation(
      const AcpToolDiffView(
        path: 'lib/src/sample.dart',
        oldText: 'line 1\nline 2\nline 3',
        newText: 'line 1\nline two\nline 3\nline 4',
      ),
    );

    final row = AcpTimelineProcessRow(
      id: 'proc-diff',
      items: [
        AcpTimelineToolCallItem(
          id: 'tool-edit',
          toolCallId: 'call-edit',
          status: AcpToolStatusKind.completed,
          kindLabel: 'edit',
          locations: const ['lib/src/sample.dart:2'],
          diffs: [doc],
          tool: const TimelineToolPresentation(
            id: 'tool-edit',
            toolCallId: 'call-edit',
            name: '修改 sample.dart',
            presentationContract: 'acp.tool.edit',
            statusString: 'succeeded',
            arguments: '',
            output: '',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      _zhApp(
        SingleChildScrollView(
          child: AcpTimelineProcessGroupView(row: row, initiallyExpanded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimelineDiffStatBadge), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);

    await tester.tap(find.byTooltip('复制路径').first);
    await tester.pump();
    expect(copiedText, anyOf('lib/src/sample.dart', 'lib/src/sample.dart:2'));
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
    // Drain the 1600ms checkmark timer cleanly.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('执行步骤接入统一右侧边栏，滚动主时间线不遮挡步骤列表', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const plan = AcpPlanCardViewState(
      completedCount: 1,
      entries: [
        AcpPlanEntryPresentation(
          content: '步骤一 · 已完成',
          priority: AcpPlanPriorityKind.low,
          status: AcpPlanStatusKind.completed,
        ),
        AcpPlanEntryPresentation(
          content: '步骤二 · 正在执行 Diff 优化',
          priority: AcpPlanPriorityKind.high,
          status: AcpPlanStatusKind.inProgress,
        ),
        AcpPlanEntryPresentation(
          content: '步骤三 · 待开始',
          priority: AcpPlanPriorityKind.medium,
          status: AcpPlanStatusKind.pending,
        ),
      ],
    );

    var showSteps = false;
    await tester.pumpWidget(
      _zhApp(
        StatefulBuilder(
          builder: (context, setState) => AcpWorkspaceView(
            readingArea: AcpConversationContentView(
              threadId: 'plan-thread',
              header: const AcpTimelineHeaderViewState(
                ready: true,
                loading: false,
                hasPlan: true,
                hasConversationalContent: true,
                itemCount: 40,
              ),
              itemBuilder: (context, index) => AcpTimelineEntryView(
                item: AcpTimelineAssistantMessage(
                  id: 'msg-$index',
                  blocks: [AcpTextBlockPresentation(text: '内容第 $index 条')],
                ),
              ),
            ),
            composerBuilder: (_, compact) => AcpConversationComposerView(
              state: const AcpComposerViewState(
                threadId: 'plan-thread',
                canSend: true,
              ),
              compact: compact,
              onDraftChanged: (_) {},
              onSubmit: () {},
              onInterrupt: () {},
              onPickLocalAttachments: (_) async {},
              onAddRemoteAttachment: (_) async {},
              onRemoveAttachment: (_) {},
            ),
            sidebarBuilder: !showSteps
                ? null
                : (_, presentation) => ConversationRightSidebar(
                    entries: [
                      ConversationSidebarPanelEntry(
                        kind: ConversationSidebarPanelKind.todo,
                        icon: Icons.checklist_outlined,
                        label: '执行步骤',
                        builder: (_) => const AcpPlanPanel(state: plan),
                      ),
                    ],
                    activeKind: ConversationSidebarPanelKind.todo,
                    presentation: presentation,
                    onSelectKind: (_) {},
                    onCollapse: () => setState(() => showSteps = false),
                  ),
            statusBar: AcpStatusBarView(
              status: const AcpConnectionStatusView(
                state: AcpStatusBarViewState(
                  phase: AcpSessionStatusPhase.running,
                ),
              ),
              steps: InkWell(
                key: const ValueKey('acp-plan-status-pill'),
                onTap: () => setState(() => showSteps = !showSteps),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text('1/3'),
                ),
              ),
              contextUsage: const SizedBox.shrink(),
              cost: const SizedBox.shrink(),
              externalHistory: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AcpPlanPanel), findsNothing);
    expect(find.text('1/3'), findsOneWidget);

    // Open steps sidebar via status bar pill.
    await tester.tap(find.byKey(const ValueKey('acp-plan-status-pill')));
    await tester.pumpAndSettle();
    expect(find.byType(AcpPlanPanel), findsOneWidget);
    expect(find.text('步骤一 · 已完成'), findsOneWidget);
    expect(find.text('步骤二 · 正在执行 Diff 优化'), findsOneWidget);
    expect(find.text('步骤三 · 待开始'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);
    expect(find.text('中'), findsNothing);
    expect(find.text('低'), findsNothing);

    // Scroll timeline to bottom; sidebar panel stays mounted alongside.
    final list = tester.widget<ListView>(
      find.descendant(
        of: find.byKey(const ValueKey('acp-reading-area')),
        matching: find.byType(ListView),
      ),
    );
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byType(AcpPlanPanel), findsOneWidget);
    expect(find.text('步骤二 · 正在执行 Diff 优化'), findsOneWidget);
  });

  testWidgets('斜杠命令输入打开浮层，上下/回车填入草稿而不直接发送，Esc 收起', (tester) async {
    const commands = [
      AcpSlashCommandPresentation(name: 'compact', description: '整理上下文'),
      AcpSlashCommandPresentation(
        name: 'review',
        description: '审查当前改动',
        inputHint: 'target',
      ),
      AcpSlashCommandPresentation(name: 'clear', description: '清空上下文'),
    ];

    var draft = '/c';
    var submitCount = 0;

    await tester.pumpWidget(
      _zhApp(
        StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.bottomCenter,
            child: AcpConversationComposerView(
              state: AcpComposerViewState(
                threadId: 'slash-thread',
                draftText: draft,
                canSend: true,
                availableCommands: commands,
              ),
              onDraftChanged: (next) => setState(() => draft = next),
              onSubmit: () => submitCount++,
              onInterrupt: () {},
              onPickLocalAttachments: (_) async {},
              onAddRemoteAttachment: (_) async {},
              onRemoveAttachment: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('acp-slash-menu')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('acp-slash-item:compact')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('acp-slash-item:clear')), findsOneWidget);
    expect(find.byKey(const ValueKey('acp-slash-item:review')), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // Move selection from 'compact' (0) down to 'clear' (1) and confirm with Enter.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(draft, '/clear ');
    expect(submitCount, 0);
    expect(find.byKey(const ValueKey('acp-slash-menu')), findsNothing);

    // Re-trigger with `/re` and dismiss with Escape.
    await tester.enterText(find.byType(TextField), '/re');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acp-slash-menu')), findsOneWidget);
    expect(find.text('target'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acp-slash-menu')), findsNothing);
    expect(draft, '/re');
  });

  testWidgets('就绪空态渲染能力与可点击斜杠命令芯片', (tester) async {
    String? inserted;
    await tester.pumpWidget(
      _zhApp(
        AcpConversationContentView(
          threadId: 'empty-thread',
          header: const AcpTimelineHeaderViewState(
            ready: true,
            loading: false,
            capabilities: [AcpCapabilityKind.image],
            availableCommands: [
              AcpSlashCommandPresentation(name: 'review', description: '审查改动'),
            ],
          ),
          onInsertSlashCommand: (cmd) => inserted = cmd,
          itemBuilder: (_, _) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('图片输入'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('acp-empty-cmd:review')));
    await tester.pump();
    expect(inserted, 'review');
  });

  testWidgets('超长用户消息自动折叠与展开，消息复制及状态感知跳到最新', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final longPrompt = List.generate(
      30,
      (i) => '长消息行 #$i：用于验证超过高度阈值后默认收起并可手动展开。',
    ).join('\n');

    final rows = [
      AcpTimelineMessageRow(
        AcpTimelineUserMessage(
          id: 'u-short',
          blocks: const [AcpTextBlockPresentation(text: '短消息不折叠')],
        ),
      ),
      AcpTimelineMessageRow(
        AcpTimelineUserMessage(
          id: 'u-long',
          blocks: [AcpTextBlockPresentation(text: longPrompt)],
        ),
      ),
      for (var i = 0; i < 20; i++)
        AcpTimelineMessageRow(
          AcpTimelineAssistantMessage(
            id: 'a-$i',
            blocks: [AcpTextBlockPresentation(text: '助手回复条目 $i\n正文补充行')],
          ),
        ),
    ];

    await tester.pumpWidget(
      _zhApp(
        SizedBox(
          height: 500,
          child: AcpConversationContentView(
            threadId: 'msg-thread',
            header: AcpTimelineHeaderViewState(
              ready: true,
              loading: false,
              running: true,
              hasConversationalContent: true,
              itemCount: rows.length,
            ),
            itemBuilder: (context, index) => AcpTimelineEntryView(
              key: ValueKey(rows[index].id),
              item: rows[index].item,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    expect(controller.position.extentAfter, lessThan(1));
    final messageList = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.controller == controller,
    );
    await tester.scrollUntilVisible(
      find.text('短消息不折叠'),
      -300,
      scrollable: messageList,
      maxScrolls: 20,
    );
    await tester.pumpAndSettle();

    // Long user bubble is auto-folded while short user bubble has no toggle.
    expect(
      find.byKey(const ValueKey('acp-user-bubble-toggle:u-short')),
      findsNothing,
    );
    final toggleFinder = find.byKey(
      const ValueKey('acp-user-bubble-toggle:u-long'),
    );
    expect(toggleFinder, findsOneWidget);
    expect(find.text('展开全部'), findsOneWidget);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('acp-copy-message:u-short')));
    await tester.pump();
    expect(copied, '短消息不折叠');

    expect(find.byKey(StudioDriverKeys.timelineReturnLatest), findsOneWidget);
    expect(find.text('跳到最新 · 运行中'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('权限审批栏展示本地化类别标签与保留原按钮顺序', (tester) async {
    await tester.pumpWidget(
      _zhApp(
        AcpPermissionDock(
          state: const AcpPermissionDockViewState(
            pendingCount: 2,
            activeRequest: AcpPermissionRequestPresentation(
              id: 'perm-1',
              title: '编辑文件 lib/a.dart',
              kindLabel: 'edit',
              options: [
                AcpPermissionOptionPresentation(
                  optionId: 'allow-1',
                  name: '允许一次',
                  tone: AcpPermissionOptionTone.allowOnce,
                ),
                AcpPermissionOptionPresentation(
                  optionId: 'deny-1',
                  name: '拒绝',
                  tone: AcpPermissionOptionTone.rejectOnce,
                ),
              ],
            ),
          ),
          onSelectOption: (_, _) {},
          onCancel: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('edit'), findsNothing);
    expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
    expect(find.text('允许一次'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);
  });

  testWidgets('外部历史会话支持按标题、路径和会话 ID 即时搜索过滤', (tester) async {
    await tester.pumpWidget(
      _zhApp(
        AcpExternalHistoryDialog(
          state: const AcpExternalHistoryDialogState(
            availability: AcpExternalHistoryAvailability.available,
            canLoad: true,
            canResume: true,
            sessions: [
              AcpExternalSessionRowPresentation(
                sessionId: 'sess-alpha',
                title: '修复 Diff 行级比对',
                cwd: '/workspace/alpha',
              ),
              AcpExternalSessionRowPresentation(
                sessionId: 'sess-beta',
                title: '设计计划条交互',
                cwd: '/workspace/beta-app',
              ),
              AcpExternalSessionRowPresentation(
                sessionId: 'sess-gamma',
                title: '排查超时日志',
                cwd: '/workspace/gamma',
              ),
            ],
          ),
          onRefresh: () {},
          onLoadMore: () {},
          onLoadSession: (_) {},
          onResumeSession: (_) {},
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find.byKey(const ValueKey('acp-history-search'));
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'beta');
    await tester.pumpAndSettle();
    expect(find.text('设计计划条交互'), findsOneWidget);
    expect(find.text('修复 Diff 行级比对'), findsNothing);
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.enterText(searchField, 'nonexistent-keyword');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的外部会话'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('修复 Diff 行级比对'), findsOneWidget);
    expect(find.text('设计计划条交互'), findsOneWidget);
    expect(find.text('排查超时日志'), findsOneWidget);
  });

  testWidgets('端到端 AvailableCommandsUpdate 从连接器流入空态芯片与斜杠浮层', (tester) async {
    final harness = await AcpComponentHarness.create(
      updates: [
        AcpAvailableCommandsUpdateView(
          commands: const [
            AcpAvailableCommandView(
              name: 'review',
              description: 'Review diff',
              input: AcpUnstructuredCommandInputView(hint: 'scope'),
            ),
            AcpAvailableCommandView(name: 'compact', description: '压缩上下文'),
          ],
        ),
      ],
    );
    addTearDown(() => harness.close(tester));

    await tester.pumpWidget(
      harness.scope(
        const Column(
          children: [
            Expanded(child: AcpTimelineConnector(threadId: 'thread')),
            AcpComposerConnector(threadId: 'thread'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('acp-empty-cmd:review')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('acp-empty-cmd:review')));
    await tester.pumpAndSettle();

    expect(harness.client.drafts.composer('thread').state.draft, '/review ');
    expect(find.byKey(const ValueKey('acp-slash-menu')), findsNothing);

    await tester.enterText(find.byType(TextField), '/re');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acp-slash-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('acp-slash-item:review')), findsOneWidget);
  });

  testWidgets('窄窗 360x760 @ 1.6x 缩放下展开计划卡与含长路径 Diff 的权限审批栏零溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const planState = AcpPlanCardViewState(
      completedCount: 1,
      entries: [
        AcpPlanEntryPresentation(
          content: '重构 ACP 过程分组与工具行，统一复用工作组外壳',
          priority: AcpPlanPriorityKind.low,
          status: AcpPlanStatusKind.completed,
        ),
        AcpPlanEntryPresentation(
          content: '上线 Myers 行级 Diff、变更统计与斜杠命令自动补全',
          priority: AcpPlanPriorityKind.high,
          status: AcpPlanStatusKind.inProgress,
        ),
      ],
    );
    const dockDiff = TimelinePatchDocument(
      files: [
        TimelinePatchFile(
          op: TimelinePatchFileOp.update,
          path: 'code/anywork/lib/src/features/conversation/acp/acp_views.dart',
          chunks: [
            TimelinePatchChunk(
              context: null,
              lines: [
                TimelinePatchLine(
                  kind: TimelinePatchLineKind.addition,
                  text: "export 'widgets/acp_message_actions.dart';",
                ),
                TimelinePatchLine(
                  kind: TimelinePatchLineKind.context,
                  text: "export 'widgets/acp_plan_card.dart';",
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _zhApp(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: AcpWorkspaceView(
              readingArea: AcpConversationContentView(
                threadId: 'narrow-overflow-thread',
                header: const AcpTimelineHeaderViewState(
                  ready: true,
                  loading: false,
                  hasPlan: true,
                  hasConversationalContent: true,
                  itemCount: 1,
                ),
                itemBuilder: (context, index) => const AcpTimelineEntryView(
                  item: AcpTimelineAssistantMessage(
                    id: 'a-narrow',
                    blocks: [AcpTextBlockPresentation(text: '窄屏自适应渲染内容。')],
                  ),
                ),
              ),
              sidebarBuilder: (_, presentation) => ConversationRightSidebar(
                entries: [
                  ConversationSidebarPanelEntry(
                    kind: ConversationSidebarPanelKind.todo,
                    icon: Icons.checklist_outlined,
                    label: '执行步骤',
                    builder: (_) => const AcpPlanPanel(state: planState),
                  ),
                ],
                activeKind: ConversationSidebarPanelKind.todo,
                presentation: presentation,
                onSelectKind: (_) {},
                onCollapse: () {},
              ),
              permissionDock: AcpPermissionDock(
                state: const AcpPermissionDockViewState(
                  pendingCount: 2,
                  activeRequest: AcpPermissionRequestPresentation(
                    id: 'perm-narrow',
                    title: '应用代码修改到 acp_views.dart',
                    kindLabel: 'edit',
                    locations: [
                      'code/anywork/lib/src/features/conversation/acp/acp_views.dart:11',
                    ],
                    diffs: [dockDiff],
                    options: [
                      AcpPermissionOptionPresentation(
                        optionId: 'allow-once',
                        name: '仅此次允许',
                        tone: AcpPermissionOptionTone.allowOnce,
                      ),
                      AcpPermissionOptionPresentation(
                        optionId: 'reject-once',
                        name: '拒绝',
                        tone: AcpPermissionOptionTone.rejectOnce,
                      ),
                    ],
                  ),
                ),
                onSelectOption: (_, _) {},
                onCancel: (_) {},
              ),
              composerBuilder: (_, compact) => AcpConversationComposerView(
                state: const AcpComposerViewState(
                  threadId: 'narrow-overflow-thread',
                  canSend: true,
                  isRunning: true,
                  canInterrupt: true,
                ),
                compact: compact,
                onDraftChanged: (_) {},
                onSubmit: () {},
                onInterrupt: () {},
                onPickLocalAttachments: (_) async {},
                onAddRemoteAttachment: (_) async {},
                onRemoveAttachment: (_) {},
              ),
              statusBar: const AcpStatusBarView(
                status: AcpConnectionStatusView(
                  state: AcpStatusBarViewState(
                    phase: AcpSessionStatusPhase.running,
                  ),
                ),
                contextUsage: SizedBox.shrink(),
                cost: SizedBox.shrink(),
                externalHistory: SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AcpPlanPanel), findsOneWidget);
    expect(find.byType(AcpPermissionDock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
