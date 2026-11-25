import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_timeline_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_content_view_model.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_timeline_view_model.dart';
import 'package:anywork/src/features/conversation/timeline/state/patch_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/tools/tool_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_patch_diff_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_work_group_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_chrome.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_previews/src/features/conversation/acp/previews/acp_process_group_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

Finder get _reading => find.byType(CustomScrollView);

ScrollPosition _readingPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _reading, matching: find.byType(Scrollable)).first,
    )
    .position;

Widget _app(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

AcpTimelineToolCallItem _tool({
  bool patch = false,
  String? kindLabel,
  String arguments = '完整参数不可隐藏',
  String output = '完整输出',
}) => AcpTimelineToolCallItem(
  id: 'tool',
  toolCallId: 'call',
  status: AcpToolStatusKind.completed,
  kindLabel: kindLabel,
  tool: TimelineToolPresentation(
    id: 'tool',
    toolCallId: 'call',
    name: '更新文件',
    presentationContract: kindLabel == null
        ? 'acp.tool'
        : 'acp.tool.$kindLabel',
    statusString: 'succeeded',
    arguments: arguments,
    output: output,
  ),
  diffs: patch
      ? [
          parseTimelinePatch(
            '*** Begin Patch\n*** Add File: sample.txt\n+new\n*** End Patch',
          )!,
        ]
      : const [],
);

void main() {
  for (final status in [
    AcpToolStatusKind.inProgress,
    AcpToolStatusKind.failed,
  ]) {
    testWidgets('过程组与组内工具颜色服从应用主题而非外层展开主题：$status', (tester) async {
      await tester.pumpWidget(
        ListTileTheme(
          data: const ListTileThemeData(
            tileColor: Colors.black,
            selectedTileColor: Colors.black,
            textColor: Colors.white,
            iconColor: Colors.white,
          ),
          child: ExpansionTileTheme(
            data: const ExpansionTileThemeData(
              backgroundColor: Colors.black,
              collapsedBackgroundColor: Colors.black,
              textColor: Colors.white,
              collapsedTextColor: Colors.white,
              iconColor: Colors.white,
              collapsedIconColor: Colors.white,
            ),
            child: _app(
              LiveStatusMotionHost(
                child: AcpTimelineProcessGroupView(
                  row: sampleAcpProcessRow(status: status),
                ),
              ),
            ),
          ),
        ),
      );
      final theme = pureStudioTheme();
      final colors = theme.colorScheme;
      final groupShell = find.byType(TimelineWorkGroupShell);
      expect(groupShell, findsOneWidget);

      void checkHeaderTextColor() {
        final headerRow = tester.widget<TimelineActivityRow>(
          find.byType(TimelineActivityRow).first,
        );
        final headerParagraph = tester.widget<RichText>(
          find
              .descendant(
                of: find.text(headerRow.label),
                matching: find.byType(RichText),
              )
              .first,
        );
        expect(headerParagraph.text.style?.color, isNot(Colors.white));
        if (!headerRow.active) {
          expect(headerParagraph.text.style?.color, colors.onSurfaceVariant);
        } else {
          expect(headerParagraph.text.style?.color, colors.onSurface);
        }
      }

      checkHeaderTextColor();
      await tester.tap(find.byType(TimelineActivityRow).first);
      await tester.pump(const Duration(milliseconds: 300));
      checkHeaderTextColor();

      final innerTiles = find.descendant(
        of: find.byType(AcpToolCard),
        matching: find.byType(ListTile),
      );
      expect(innerTiles, findsWidgets);
      for (final tileElement in tester.elementList(innerTiles)) {
        expect(
          ListTileTheme.of(tileElement).tileColor,
          theme.listTileTheme.tileColor,
        );
        expect(ListTileTheme.of(tileElement).tileColor, isNot(Colors.black));
        expect(ListTileTheme.of(tileElement).textColor, isNot(Colors.white));
        expect(
          ExpansionTileTheme.of(tileElement).backgroundColor,
          isNot(Colors.black),
        );
      }

      await tester.tap(find.byType(TimelineActivityRow).first);
      await tester.pump(const Duration(milliseconds: 300));
      checkHeaderTextColor();
    });
  }

  for (final scenario in [
    (
      label: '仅 sessionInfo',
      updates: <AcpSessionUpdateView>[const AcpSessionInfoUpdateView()],
      members: 0,
    ),
    (
      label: '仅空命令数组',
      updates: <AcpSessionUpdateView>[
        AcpAvailableCommandsUpdateView(commands: const []),
      ],
      members: 0,
    ),
    (
      label: '两工具之间的不可见通知',
      updates: <AcpSessionUpdateView>[
        _protocolTool('before-invisible'),
        const AcpSessionInfoUpdateView(),
        AcpAvailableCommandsUpdateView(commands: const []),
        _protocolTool('after-invisible'),
      ],
      members: 2,
    ),
  ]) {
    testWidgets('不可见通知不生成过程成员：${scenario.label}', (tester) async {
      final harness = await AcpComponentHarness.create(
        updates: scenario.updates,
      );
      addTearDown(() => harness.close(tester));
      await tester.pumpWidget(
        harness.scope(const AcpTimelineConnector(threadId: 'thread')),
      );
      await tester.pumpAndSettle();
      if (scenario.members == 0) {
        expect(find.byType(AcpTimelineProcessGroupView), findsNothing);
      } else {
        final group = tester.widget<AcpTimelineProcessGroupView>(
          find.byType(AcpTimelineProcessGroupView),
        );
        expect(group.row.toolCount, 2);
        expect(
          group.row.items,
          hasLength(scenario.members),
          reason: '摘要计数只能包含真实可见成员',
        );
        expect(find.text('执行了 2 个工具'), findsOneWidget);
      }
    });
  }

  for (final change in ['追加工具', '原位增长长输出']) {
    testWidgets('已展开组内$change且行数不变时继续跟随底部', (tester) async {
      final harness = await AcpComponentHarness.create(
        updates: [_protocolTool('follow', output: _longOutput('初始', 70))],
      );
      addTearDown(() => harness.close(tester));
      await tester.pumpWidget(
        harness.scope(const AcpTimelineConnector(threadId: 'thread')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TimelineActivityRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('工具 follow'));
      await tester.pumpAndSettle();
      final position = _readingPosition(tester);
      expect(position.maxScrollExtent, greaterThan(300));
      expect(position.extentBefore, lessThan(1));
      final oldCount = tester
          .widget<AcpConversationContentView>(
            find.byType(AcpConversationContentView),
          )
          .rows
          .length;
      final oldExtent = position.maxScrollExtent;
      harness.update(
        change == '追加工具'
            ? _protocolTool(
                'appended',
                diffText: List.generate(30, (i) => 'line $i').join('\n'),
              )
            : AcpToolCallChangedView(
                AcpToolCallUpdateView(
                  toolCallId: const AcpToolCallId('follow'),
                  fields: AcpToolCallUpdateFieldsView(
                    rawOutput: AcpJsonString(_longOutput('增长', 150)),
                  ),
                ),
              ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AcpConversationContentView>(
              find.byType(AcpConversationContentView),
            )
            .rows
            .length,
        oldCount,
      );
      expect(position.maxScrollExtent, greaterThan(oldExtent + 300));
      expect(
        position.extentBefore,
        lessThan(1),
        reason: '用户原本在底部时，同一过程组新增详情仍应跟随',
      );
    });
  }

  testWidgets('ACP 上翻可继续阅读，手动滚回或点击 Flyer 按钮恢复', (tester) async {
    final harness = await AcpComponentHarness.create(
      updates: [_protocolTool('reading', output: _longOutput('初始', 80))],
    );
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      harness.scope(const AcpTimelineConnector(threadId: 'thread')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TimelineActivityRow).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('工具 reading'));
    await tester.pumpAndSettle();
    final position = _readingPosition(tester);
    final returnButton = find.byKey(StudioDriverKeys.timelineReturnLatest);
    expect(returnButton.hitTestable(), findsNothing);
    expect(position.extentBefore, lessThan(1));

    await tester.drag(_reading, const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    final oldEnd = position.maxScrollExtent;
    expect(position.extentBefore, greaterThan(160));
    expect(returnButton.hitTestable(), findsOneWidget);
    harness.update(
      _protocolTool(
        'reading-appended',
        diffText: List.generate(40, (i) => 'diff line $i').join('\n'),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.maxScrollExtent, greaterThan(oldEnd));
    expect(position.extentBefore, greaterThan(160));
    expect(returnButton.hitTestable(), findsOneWidget);

    await tester.drag(_reading, Offset(0, -(position.extentBefore + 100)));
    await tester.pumpAndSettle();
    expect(position.extentBefore, lessThan(1));
    expect(returnButton.hitTestable(), findsNothing);

    final resumedEnd = position.maxScrollExtent;
    harness.update(_protocolTool('reading-resumed'));
    await tester.pumpAndSettle();
    expect(position.maxScrollExtent, greaterThan(resumedEnd));
    expect(position.extentBefore, lessThan(1));

    await tester.drag(_reading, const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(returnButton.hitTestable(), findsOneWidget);
    await tester.tap(returnButton);
    await tester.pumpAndSettle();
    expect(returnButton.hitTestable(), findsNothing);
    expect(position.extentBefore, lessThan(1));
  });

  for (final patch in [false, true]) {
    testWidgets('展开工具完整展示参数及输出，含补丁=$patch', (tester) async {
      await tester.pumpWidget(
        _app(
          AcpToolCard(
            item: _tool(patch: patch, kindLabel: patch ? 'edit' : 'execute'),
            initiallyExpanded: true,
          ),
        ),
      );
      expect(find.byType(TimelineToolItemView), findsOneWidget);
      expect(find.text('完整参数不可隐藏'), findsOneWidget);
      expect(find.text('完整输出'), findsOneWidget);
      expect(find.text(patch ? '编辑' : '执行'), findsOneWidget);
      for (final code in tester.widgetList<StudioCodeBlock>(
        find.byType(StudioCodeBlock),
      )) {
        expect(code.maxHeight, isNull, reason: '完整详情不能有内部高度上限');
        expect(code.horizontalScroll, isFalse, reason: '长参数与输出应在主滚动中换行');
      }
    });
  }

  testWidgets('无详情轻量工具不可展开且不显示箭头', (tester) async {
    await tester.pumpWidget(
      _app(
        AcpToolCard(
          item: _tool(kindLabel: 'think', arguments: '', output: ''),
        ),
      ),
    );
    final row = tester.widget<TimelineActivityRow>(
      find.byType(TimelineActivityRow),
    );
    expect(row.expandable, isFalse);
    expect(row.meta, '思考');
  });

  for (final status in [
    AcpToolStatusKind.completed,
    AcpToolStatusKind.failed,
  ]) {
    testWidgets('过程默认折叠，展开后复用共享组件且支持逐项折叠：$status', (tester) async {
      final row = sampleAcpProcessRow(status: status, longContent: true);
      await tester.pumpWidget(
        _app(
          LiveStatusMotionHost(child: AcpTimelineProcessGroupView(row: row)),
        ),
      );
      expect(find.byType(AcpToolCard), findsNothing);
      expect(find.text('过程 · 3 项活动 · 1 个工具'), findsOneWidget);
      expect(find.text('1 个工具失败'), findsNothing);
      expect(find.byIcon(Icons.work_outline), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      await tester.tap(find.byType(TimelineActivityRow).first);
      await tester.pumpAndSettle();

      expect(find.byType(TimelineActivityRail), findsWidgets);
      expect(find.byType(TimelineReasoningView), findsOneWidget);
      expect(find.byType(AcpToolCard), findsOneWidget);
      expect(find.byType(TimelineToolItemView), findsOneWidget);
      expect(find.text('检查记录已保存'), findsOneWidget);

      // 含 Diff 的编辑工具默认展开
      expect(find.byType(TimelinePatchDiffView), findsOneWidget);
      expect(
        tester
            .widget<TimelinePatchDiffView>(find.byType(TimelinePatchDiffView))
            .softWrap,
        isTrue,
      );
      expect(find.text('audio/wav'), findsOneWidget);
      expect(find.text('官方验证参考资料'), findsOneWidget);
      expect(
        find.text(status == AcpToolStatusKind.failed ? '编辑 · 失败' : '编辑'),
        findsOneWidget,
      );

      // 思考条默认折叠，点击后可在同一过程组内单独展开与收起
      expect(find.textContaining('思考正文：'), findsNothing);
      await tester.tap(find.text('核对接口与调用链'));
      await tester.pumpAndSettle();
      expect(find.textContaining('思考正文：'), findsOneWidget);
      await tester.tap(find.text('核对接口与调用链'));
      await tester.pumpAndSettle();
      expect(find.textContaining('思考正文：'), findsNothing);

      // 工具也可单独收起与重新展开
      await tester.tap(find.text('更新过程展示'));
      await tester.pumpAndSettle();
      expect(find.byType(TimelinePatchDiffView), findsNothing);
      await tester.tap(find.text('更新过程展示'));
      await tester.pumpAndSettle();
      expect(find.byType(TimelinePatchDiffView), findsOneWidget);

      final groupRow = tester.widget<TimelineActivityRow>(
        find.byType(TimelineActivityRow).first,
      );
      expect(groupRow.isIssue, isFalse);

      expect(
        find.descendant(
          of: find.byType(AcpTimelineProcessGroupView),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AcpTimelineProcessGroupView),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
        reason: '独立过程组不能引入嵌套 Scrollable 或 SelectableText 的隐式滚动位置',
      );
      for (final code in tester.widgetList<StudioCodeBlock>(
        find.byType(StudioCodeBlock),
      )) {
        expect(code.maxHeight, isNull);
        expect(code.horizontalScroll, isFalse);
      }
    });
  }

  testWidgets('过程组标题覆盖进行中与已完成各类诚实状态且不伪造耗时', (tester) async {
    // 1. 进行中：execute 工具用进度环、单行呈现工具名与计数，不再出现第二行“执行中”
    final execRow = AcpTimelineProcessRow(
      id: 'running-exec',
      items: const [
        AcpTimelineToolCallItem(
          id: 't1',
          toolCallId: 'c1',
          status: AcpToolStatusKind.inProgress,
          kindLabel: 'execute',
          tool: TimelineToolPresentation(
            id: 't1',
            toolCallId: 'c1',
            name: 'cargo test',
            presentationContract: 'acp.tool.execute',
            statusString: 'running',
            arguments: '',
            output: '',
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      _app(
        LiveStatusMotionHost(child: AcpTimelineProcessGroupView(row: execRow)),
      ),
    );
    expect(find.text('cargo test'), findsOneWidget);
    expect(find.text('1 个工具'), findsOneWidget);
    expect(find.text('执行中'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 2. 进行中：非 execute 工具与思考展示单行概要，不显示第二行
    final thoughtRunning = AcpTimelineProcessRow(
      id: 'running-thought',
      items: const [
        AcpTimelineThoughtItem(
          id: 'th1',
          summary: '正在分析依赖树',
          active: true,
          blocks: [AcpTextBlockPresentation(text: '正在分析依赖树')],
        ),
      ],
    );
    await tester.pumpWidget(
      _app(
        LiveStatusMotionHost(
          child: AcpTimelineProcessGroupView(row: thoughtRunning),
        ),
      ),
    );
    expect(find.text('正在分析依赖树'), findsOneWidget);
    expect(find.text('执行中'), findsNothing);
    final activeRow = tester.widget<TimelineActivityRow>(
      find.byType(TimelineActivityRow).first,
    );
    expect(activeRow.header, isTrue);
    expect(activeRow.indicatorStyle, TimelineActivityIndicatorStyle.restingCat);

    // 3. 已完成：纯思考、纯工具、纯更新分别展示诚实文案且无秒数
    final thoughtsDone = AcpTimelineProcessRow(
      id: 'done-thoughts',
      items: const [
        AcpTimelineThoughtItem(
          id: 'th1',
          summary: '思考一',
          blocks: [AcpTextBlockPresentation(text: '思考一')],
        ),
        AcpTimelineThoughtItem(
          id: 'th2',
          summary: '思考二',
          blocks: [AcpTextBlockPresentation(text: '思考二')],
        ),
      ],
    );
    await tester.pumpWidget(
      _app(AcpTimelineProcessGroupView(row: thoughtsDone)),
    );
    expect(find.text('思考了 2 段'), findsOneWidget);
    expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);

    final updatesDone = AcpTimelineProcessRow(
      id: 'done-updates',
      items: const [
        AcpTimelineSessionUpdateItem(
          id: 'u1',
          update: AcpSessionInfoUpdatePresentation(),
        ),
      ],
    );
    await tester.pumpWidget(
      _app(AcpTimelineProcessGroupView(row: updatesDone)),
    );
    expect(find.text('过程 · 1 项活动'), findsOneWidget);
  });

  testWidgets('失败工具保持类别图标、显示本地化失败状态且保留失败输出', (tester) async {
    final tool = sampleAcpProcessRow(status: AcpToolStatusKind.failed).items
        .whereType<AcpTimelineToolCallItem>()
        .single
        .copyWith(diffs: const []);
    await tester.pumpWidget(_app(AcpToolCard(item: tool)));
    expect(find.text('验证失败：权限不足，原文件未改动。'), findsNothing);
    expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('编辑 · 失败'), findsOneWidget);
    await tester.tap(find.byType(TimelineActivityRow));
    await tester.pumpAndSettle();
    expect(find.text('验证失败：权限不足，原文件未改动。'), findsOneWidget);
  });

  testWidgets('原位状态更新、成员追加和组身份替换不串展开状态', (tester) async {
    final source = ValueNotifier(
      sampleAcpProcessRow(status: AcpToolStatusKind.inProgress),
    );
    addTearDown(source.dispose);
    await tester.pumpWidget(
      _app(
        LiveStatusMotionHost(
          child: ValueListenableBuilder<AcpTimelineProcessRow>(
            valueListenable: source,
            builder: (context, row, _) =>
                AcpTimelineProcessGroupView(key: ValueKey(row.id), row: row),
          ),
        ),
      ),
    );
    expect(find.text('更新过程展示'), findsOneWidget);
    expect(find.text('1 个工具'), findsOneWidget);
    expect(find.text('执行中'), findsNothing);
    expect(find.byType(AcpToolCard), findsNothing);
    await tester.tap(find.byType(TimelineActivityRow).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AcpToolCard), findsOneWidget);
    final completed = sampleAcpProcessRow();
    source.value = AcpTimelineProcessRow(
      id: completed.id,
      items: [
        ...completed.items,
        const AcpTimelineSessionUpdateItem(
          id: 'extra',
          update: AcpNoticeUpdatePresentation(title: '追加通知'),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('过程 · 4 项活动 · 1 个工具'), findsOneWidget);
    expect(find.text('追加通知'), findsOneWidget);
    source.value = sampleAcpProcessRow(id: 'different:process');
    await tester.pumpAndSettle();
    expect(find.byType(AcpToolCard), findsNothing, reason: '新组不能继承旧组的展开选择');
    source.value = completed;
    await tester.pumpAndSettle();
    expect(
      find.byType(AcpToolCard),
      findsOneWidget,
      reason: '原组恢复时使用自己的 PageStorage 状态',
    );
  });

  testWidgets('生产内容列表滚出再返回保留当前观察的展开选择', (tester) async {
    final row = sampleAcpProcessRow();
    await tester.pumpWidget(
      acpTestApp(
        AcpConversationContentView(
          threadId: 'scroll',
          header: const AcpTimelineHeaderViewState(
            ready: true,
            loading: false,
            hasConversationalContent: true,
          ),
          rows: [
            row,
            for (var index = 1; index <= 50; index++)
              AcpTimelineMessageRow(
                AcpTimelineAssistantMessage(
                  id: 'message-$index',
                  blocks: [
                    AcpTextBlockPresentation(text: '后续独立消息 $index\n第二行\n第三行'),
                  ],
                ),
              ),
          ],
          itemBuilder: (context, row) => switch (row) {
            AcpTimelineMessageRow(:final item) => AcpTimelineEntryView(
              item: item,
            ),
            AcpTimelineProcessRow() => AcpTimelineProcessGroupView(row: row),
          },
        ),
      ),
    );
    final list = _reading;
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 6000));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TimelineActivityRow).first);
    await tester.pumpAndSettle();
    expect(find.byType(AcpToolCard), findsOneWidget);
    await tester.drag(list, const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(
      find.byType(AcpTimelineProcessGroupView),
      findsNothing,
      reason: '确实离开虚拟列表缓存范围',
    );
    await tester.drag(list, const Offset(0, 6000));
    await tester.pumpAndSettle();
    expect(find.byType(AcpToolCard), findsOneWidget);
    final header = find.byType(TimelineActivityRow).first;
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    expect(header.hitTestable(), findsOneWidget);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.byType(AcpToolCard), findsNothing);
    await tester.drag(list, const Offset(0, -6000));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 6000));
    await tester.pumpAndSettle();
    expect(find.byType(AcpToolCard), findsNothing, reason: '明确收起后也不能被滚动重新展开');
  });

  testWidgets('切换 ACP 会话后从新会话的最新位置开始跟随', (tester) async {
    final thread = ValueNotifier('previous');
    addTearDown(thread.dispose);
    await tester.pumpWidget(
      acpTestApp(
        ValueListenableBuilder(
          valueListenable: thread,
          builder: (context, threadId, _) => AcpConversationContentView(
            threadId: threadId,
            header: const AcpTimelineHeaderViewState(
              ready: true,
              loading: false,
              hasConversationalContent: true,
            ),
            rows: [
              for (var index = 0; index < 12; index++)
                AcpTimelineMessageRow(
                  AcpTimelineAssistantMessage(
                    id: '$threadId $index',
                    blocks: const [],
                  ),
                ),
            ],
            itemBuilder: (context, row) =>
                SizedBox(height: 100, child: Text(row.id)),
          ),
        ),
      ),
    );
    final list = _reading;
    final returnButton = find.byKey(StudioDriverKeys.timelineReturnLatest);
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(returnButton.hitTestable(), findsOneWidget);

    thread.value = 'next';
    await tester.pumpAndSettle();
    expect(returnButton.hitTestable(), findsNothing);
    expect(_readingPosition(tester).extentBefore, lessThan(1));
    expect(find.text('next 11').hitTestable(), findsOneWidget);
  });

  testWidgets('实际 connector 按可见消息分组并原位更新旧工具', (tester) async {
    final harness = await AcpComponentHarness.create(
      updates: [
        const AcpUserMessageChunkView(
          AcpContentChunkView(content: AcpTextContentView(text: '用户问题')),
        ),
        const AcpAgentMessageChunkView(
          AcpContentChunkView(content: AcpTextContentView(text: '可见阶段进展一')),
        ),
        const AcpAgentThoughtChunkView(
          AcpContentChunkView(content: AcpTextContentView(text: '完整思考')),
        ),
        _protocolTool('first'),
        const AcpAgentMessageChunkView(
          AcpContentChunkView(content: AcpTextContentView(text: '可见阶段进展二')),
        ),
        _protocolTool('second'),
      ],
    );
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      harness.scope(const AcpTimelineConnector(threadId: 'thread')),
    );
    await tester.pumpAndSettle();
    expect(find.text('用户问题'), findsOneWidget);
    expect(find.text('可见阶段进展一'), findsOneWidget);
    expect(find.text('可见阶段进展二'), findsOneWidget);
    expect(find.byType(AcpTimelineProcessGroupView), findsNWidgets(2));
    expect(find.byType(AcpToolCard), findsNothing);
    final firstGroup = find.byWidgetPredicate(
      (widget) =>
          widget is AcpTimelineProcessGroupView &&
          widget.row.items.whereType<AcpTimelineToolCallItem>().any(
            (item) => item.toolCallId == 'first',
          ),
    );
    await tester.tap(
      find
          .descendant(
            of: firstGroup,
            matching: find.byType(TimelineActivityRow),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('完整思考'), findsWidgets);
    expect(find.text('工具 first'), findsOneWidget);
    await tester.tap(find.text('工具 first'));
    await tester.pumpAndSettle();
    harness.update(
      AcpToolCallChangedView(
        AcpToolCallUpdateView(
          toolCallId: const AcpToolCallId('first'),
          fields: AcpToolCallUpdateFieldsView(
            status: AcpToolCallStatusView.failed,
            rawOutput: const AcpJsonString('原位更新的失败输出'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.widget<AcpTimelineProcessGroupView>(firstGroup);
    expect(
      first.row.items.whereType<AcpTimelineToolCallItem>().single.status,
      AcpToolStatusKind.failed,
    );
    expect(find.textContaining('原位更新的失败输出'), findsOneWidget);
    expect(find.text('工具 second'), findsNothing, reason: '其他组仍独立折叠');
  });

  for (final size in [const Size(340, 740), const Size(760, 800)]) {
    testWidgets('生产装配长内容在 $size 和大字下自然换行', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        acpTestApp(
          MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.8),
            ),
            child: sampleAcpConversation(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('本轮验证结束，失败详情保留在过程组中。').hitTestable(), findsOneWidget);
      await tester.drag(_reading, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_reading, findsOneWidget);
      expect(_readingPosition(tester).extentBefore, greaterThan(0));
      expect(
        find.byType(SingleChildScrollView),
        findsNothing,
        reason: '长代码、嵌入文本和补丁只使用会话主滚动',
      );
    });
  }

  for (final scenario in [
    (label: '没有可见消息', middle: <AcpSessionUpdateView>[], expectedGroups: 1),
    (
      label: '可见阶段进展切组',
      middle: <AcpSessionUpdateView>[
        const AcpAgentMessageChunkView(
          AcpContentChunkView(content: AcpTextContentView(text: '阶段进展')),
        ),
      ],
      expectedGroups: 2,
    ),
    (
      label: '隐藏及空白消息不切组',
      middle: <AcpSessionUpdateView>[
        AcpAgentMessageChunkView(
          AcpContentChunkView(
            content: AcpTextContentView(
              text: '不可见宿主上下文',
              annotations: AcpAnnotationsView(
                audience: [AcpContentRoleView.assistant],
              ),
            ),
          ),
        ),
        const AcpAgentMessageChunkView(
          AcpContentChunkView(content: AcpTextContentView(text: '  \n')),
        ),
      ],
      expectedGroups: 1,
    ),
  ]) {
    testWidgets('真实 Client 投影分组规则：${scenario.label}', (tester) async {
      final harness = await AcpComponentHarness.create(
        updates: [
          _protocolTool('before'),
          ...scenario.middle,
          _protocolTool('after'),
        ],
      );
      addTearDown(() => harness.close(tester));
      await tester.pumpWidget(
        harness.scope(const AcpTimelineConnector(threadId: 'thread')),
      );
      await tester.pumpAndSettle();
      final rows = mapAcpTimelineRows(
        threadId: 'thread',
        content: harness.owner.state.content,
        running: false,
      );
      final groups = rows.whereType<AcpTimelineProcessRow>().toList();
      expect(groups, hasLength(scenario.expectedGroups));
      expect(groups.fold<int>(0, (count, row) => count + row.toolCount), 2);
      expect(
        groups.first.items
            .whereType<AcpTimelineToolCallItem>()
            .first
            .toolCallId,
        'before',
      );
      expect(
        groups.last.items.whereType<AcpTimelineToolCallItem>().last.toolCallId,
        'after',
      );
      expect(
        rows.whereType<AcpTimelineMessageRow>().length,
        scenario.expectedGroups - 1,
      );
    });
  }

  test('formatAcpJsonText 保留多行字符串原文并缩进 JSON 对象', () {
    expect(formatAcpJsonText(const AcpJsonString('第一行\n第二行')), '第一行\n第二行');
    expect(
      formatAcpJsonText(
        AcpJsonObject({
          'path': const AcpJsonString('a.dart'),
          'line': AcpJsonInteger(BigInt.from(10)),
        }),
      ),
      '{\n  "path": "a.dart",\n  "line": 10\n}',
    );
  });
}

AcpToolCallSessionUpdateView _protocolTool(
  String id, {
  String? output,
  String? diffText,
}) => AcpToolCallSessionUpdateView(
  AcpToolCallView(
    toolCallId: AcpToolCallId(id),
    title: '工具 $id',
    kind: diffText == null ? AcpToolKindView.execute : AcpToolKindView.edit,
    status: AcpToolCallStatusView.completed,
    content: [
      if (diffText != null)
        AcpToolDiffView(path: 'lib/$id.dart', newText: diffText),
    ],
    rawInput: const AcpJsonString('工具完整参数'),
    rawOutput: AcpJsonString(output ?? '工具完整输出'),
  ),
);

String _longOutput(String prefix, int lines) => List.generate(
  lines,
  (index) => '$prefix $index：${List.filled(6, '完整保留的过程输出与状态信息。').join()}',
).join('\n');
