import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_timeline_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_timeline_view_model.dart';
import 'package:anywork/src/features/conversation/timeline/state/patch_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_patch_diff_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_chrome.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_previews/src/features/conversation/acp/previews/acp_process_group_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

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

AcpTimelineToolCallItem _tool({bool patch = false}) => AcpTimelineToolCallItem(
  id: 'tool',
  toolCallId: 'call',
  status: AcpToolStatusKind.completed,
  tool: const TimelineToolPresentation(
    id: 'tool',
    toolCallId: 'call',
    name: '更新文件',
    presentationContract: 'acp.tool',
    statusString: 'succeeded',
    arguments: '完整参数不可隐藏',
    output: '完整输出',
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
    testWidgets('过程组颜色服从应用主题而非外层展开主题：$status', (tester) async {
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
              AcpTimelineProcessGroupView(
                row: sampleAcpProcessRow(status: status),
              ),
            ),
          ),
        ),
      );
      final colors = pureStudioTheme().colorScheme;
      void expectAppColors() {
        final material = find
            .descendant(
              of: find.byType(ExpansionTile),
              matching: find.byWidgetPredicate(
                (widget) => widget is Material && widget.shape is Border,
              ),
            )
            .first;
        expect(tester.widget<Material>(material).color, colors.surface);
        final ink = find
            .descendant(
              of: find.byType(ListTile).first,
              matching: find.byType(Ink),
            )
            .first;
        expect(
          (tester.widget<Ink>(ink).decoration as ShapeDecoration).color,
          colors.surface,
          reason: '最终绘制标题底色的 Ink 不能继承外层 ListTileTheme 黑底',
        );
        final title = find.text('过程 · 3 项活动 · 1 个工具');
        final paragraph = tester.widget<RichText>(
          find.descendant(of: title, matching: find.byType(RichText)),
        );
        expect(
          paragraph.text.style?.color,
          pureStudioTheme().textTheme.bodySmall!.color,
        );
        final tileContext = tester.element(find.byType(ListTile).first);
        expect(
          ListTileTheme.of(tileContext).textColor,
          colors.onSurfaceVariant,
        );
        expect(
          ListTileTheme.of(tileContext).iconColor,
          colors.onSurfaceVariant,
        );
      }

      expectAppColors();
      await tester.tap(find.byType(ListTile).first);
      await tester.pump(const Duration(milliseconds: 400));
      expectAppColors();
      await tester.tap(find.byType(ListTile).first);
      await tester.pump(const Duration(milliseconds: 400));
      expectAppColors();
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
        expect(find.text('过程 · 2 项活动 · 2 个工具'), findsOneWidget);
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
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      expect(controller.position.maxScrollExtent, greaterThan(300));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final oldCount = tester
          .widget<AcpConversationContentView>(
            find.byType(AcpConversationContentView),
          )
          .header
          .itemCount;
      final oldExtent = controller.position.maxScrollExtent;
      harness.update(
        change == '追加工具'
            ? _protocolTool('appended', output: _longOutput('追加', 60))
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
            .header
            .itemCount,
        oldCount,
      );
      expect(controller.position.maxScrollExtent, greaterThan(oldExtent + 300));
      expect(
        controller.position.extentAfter,
        lessThan(1),
        reason: '用户原本在底部时，同一过程组新增详情仍应跟随',
      );
    });
  }

  testWidgets('已展开组内追加时不强拉主动上滚的用户', (tester) async {
    final harness = await AcpComponentHarness.create(
      updates: [_protocolTool('reading', output: _longOutput('初始', 80))],
    );
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      harness.scope(const AcpTimelineConnector(threadId: 'thread')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    final oldPixels = controller.position.pixels;
    expect(controller.position.extentAfter, greaterThan(160));
    harness.update(
      _protocolTool('reading-appended', output: _longOutput('新内容', 80)),
    );
    await tester.pumpAndSettle();
    expect(controller.position.pixels, closeTo(oldPixels, 1));
    expect(controller.position.extentAfter, greaterThan(160));
  });

  for (final patch in [false, true]) {
    testWidgets('展开工具完整展示参数及输出，含补丁=$patch', (tester) async {
      await tester.pumpWidget(
        _app(AcpToolCard(item: _tool(patch: patch), initiallyExpanded: true)),
      );
      expect(find.text('完整参数不可隐藏'), findsOneWidget);
      expect(find.text('完整输出'), findsOneWidget);
      for (final code in tester.widgetList<StudioCodeBlock>(
        find.byType(StudioCodeBlock),
      )) {
        expect(code.maxHeight, isNull, reason: '完整详情不能有内部高度上限');
        expect(code.horizontalScroll, isFalse, reason: '长参数与输出应在主滚动中换行');
      }
    });
  }

  for (final status in [
    AcpToolStatusKind.completed,
    AcpToolStatusKind.failed,
  ]) {
    testWidgets('过程默认折叠，一次展开全部详情：$status', (tester) async {
      final row = sampleAcpProcessRow(status: status, longContent: true);
      await tester.pumpWidget(_app(AcpTimelineProcessGroupView(row: row)));
      expect(find.byType(AcpToolCard), findsNothing);
      expect(find.text('过程 · 3 项活动 · 1 个工具'), findsOneWidget);
      expect(find.text('1 个工具失败'), findsNothing);
      expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(find.byType(AcpToolCard), findsOneWidget);
      expect(find.textContaining('思考正文：'), findsOneWidget);
      expect(find.textContaining('嵌入文本结束'), findsOneWidget);
      expect(find.text('检查记录已保存'), findsOneWidget);
      expect(find.byType(TimelinePatchDiffView), findsOneWidget);
      expect(find.text('audio/wav'), findsOneWidget);
      expect(find.text('官方验证参考资料'), findsOneWidget);
      final members = tester.widgetList<TimelineActivityRow>(
        find.descendant(
          of: find.byType(AcpTimelineEntryView),
          matching: find.byType(TimelineActivityRow),
        ),
      );
      expect(members, isNotEmpty);
      expect(members.every((row) => !row.isIssue), isTrue);
      expect(
        members.every((row) => !row.expandable),
        isTrue,
        reason: '工具、思考、嵌入文本不应存在二级折叠',
      );
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
        reason: '独立过程组也不能引入 SelectableText 的隐式滚动位置',
      );
      for (final code in tester.widgetList<StudioCodeBlock>(
        find.byType(StudioCodeBlock),
      )) {
        expect(code.maxHeight, isNull);
        expect(code.horizontalScroll, isFalse);
      }
    });
  }

  testWidgets('失败工具保持类别图标且保留失败输出', (tester) async {
    final tool = sampleAcpProcessRow(status: AcpToolStatusKind.failed).items
        .whereType<AcpTimelineToolCallItem>()
        .single
        .copyWith(diffs: const []);
    await tester.pumpWidget(_app(AcpToolCard(item: tool)));
    expect(find.text('验证失败：权限不足，原文件未改动。'), findsNothing);
    expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
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
        ValueListenableBuilder<AcpTimelineProcessRow>(
          valueListenable: source,
          builder: (context, row, _) =>
              AcpTimelineProcessGroupView(key: ValueKey(row.id), row: row),
        ),
      ),
    );
    expect(find.text('执行中'), findsOneWidget);
    expect(find.byType(AcpToolCard), findsNothing);
    await tester.tap(find.byType(ListTile).first);
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
    expect(find.text('执行中'), findsNothing);
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
            itemCount: 51,
          ),
          itemBuilder: (context, index) => index == 0
              ? AcpTimelineProcessGroupView(key: ValueKey(row.id), row: row)
              : AcpTimelineEntryView(
                  item: AcpTimelineAssistantMessage(
                    id: 'message-$index',
                    blocks: [
                      AcpTextBlockPresentation(text: '后续独立消息 $index\n第二行\n第三行'),
                    ],
                  ),
                ),
        ),
      ),
    );
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(AcpToolCard), findsOneWidget);
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      find.byType(AcpTimelineProcessGroupView),
      findsNothing,
      reason: '确实离开虚拟列表缓存范围',
    );
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.byType(AcpToolCard), findsOneWidget);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.byType(AcpToolCard), findsNothing, reason: '明确收起后也不能被滚动重新展开');
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
    final firstId = tester
        .widgetList<AcpTimelineProcessGroupView>(
          find.byType(AcpTimelineProcessGroupView),
        )
        .first
        .row
        .id;
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('完整思考'), findsWidgets);
    expect(find.text('工具 first'), findsOneWidget);
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
    final first = tester
        .widgetList<AcpTimelineProcessGroupView>(
          find.byType(AcpTimelineProcessGroupView),
        )
        .first;
    expect(first.row.id, firstId);
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
              textScaler: TextScaler.linear(1.8),
            ),
            child: sampleAcpConversation(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      final controller = list.controller!;
      for (var index = 0; index < 4; index++) {
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsOneWidget);
      expect(
        find.byType(SingleChildScrollView),
        findsNothing,
        reason: '长代码、嵌入文本和补丁只使用会话主滚动',
      );
      expect(find.text('本轮验证结束，失败详情保留在过程组中。'), findsOneWidget);
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
}

AcpToolCallSessionUpdateView _protocolTool(String id, {String? output}) =>
    AcpToolCallSessionUpdateView(
      AcpToolCallView(
        toolCallId: AcpToolCallId(id),
        title: '工具 $id',
        kind: AcpToolKindView.execute,
        status: AcpToolCallStatusView.completed,
        rawInput: const AcpJsonString('工具完整参数'),
        rawOutput: AcpJsonString(output ?? '工具完整输出'),
      ),
    );

String _longOutput(String prefix, int lines) => List.generate(
  lines,
  (index) => '$prefix $index：${List.filled(6, '完整保留的过程输出与状态信息。').join()}',
).join('\n');
