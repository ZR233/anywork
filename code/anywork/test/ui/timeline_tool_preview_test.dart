import 'dart:convert';

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_patch_diff_view.dart';
import 'package:anywork/src/features/conversation/timeline/tools/tool_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_previews/src/features/conversation/timeline/previews/expanded_work_timeline_fixture.dart';
import 'package:anywork_previews/src/features/conversation/timeline/previews/timeline_preview_fixtures.dart';
import 'package:anywork_previews/src/features/conversation/timeline/previews/tool_detail_preview_fixtures.dart';
import 'package:anywork_previews/src/features/conversation/timeline/previews/tool_detail_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _expectedReadableText = <String, String>{
  'builtin.exec@2': 'cargo test -p pl-core',
  'builtin.write_stdin@1': 'continue',
  'builtin.read_session_note@1': '会话约定：先验证调用方，再更新行为。',
  'builtin.search_session_note@1': '时间线工具详情由生产组件渲染。',
  'builtin.write_session_note@1': '下一步：核对窄屏布局。',
  'builtin.apply_session_note_patch@1': '核对窄屏布局',
  'builtin.stat_path@1': 'main.dart',
  'builtin.write_file@1': '验证了搜索结果与返回路径。',
  'builtin.apply_patch@1': '核验后的结果',
  'builtin.create_directory@1': '/workspace/sample-project/reports',
  'builtin.delete_path@1': 'old-index.json',
  'builtin.copy_path@1': 'input.txt',
  'builtin.move_path@1': 'drafts/report.md',
  'builtin.spawn_agent@1': '核对离线搜索结果的标题',
  'builtin.send_message@1': '已确认失败状态与错误正文均可见。',
  'builtin.wait@1': '已成功',
  'builtin.sleep@1': '1.2 秒',
  'builtin.view_image@1': '/workspace/sample-project/assets/chart.png',
  'builtin.show_files@1': '搜索结果摘要附件',
  'builtin.lsp_query@1': 'code/pl-lsp/src/runtime/registry.rs',
  'builtin.lsp_capabilities@1': 'Dart 分析服务',
  'builtin.lsp_status@1': 'rust-analyzer',
  'builtin.plan_current@1': '# 检查搜索详情',
  'builtin.plan_next@1':
      'The user approves the exact pending plan Interaction.',
  'builtin.plan_history@1': '提交计划',
  'builtin.plan_submit@1': '# 检查搜索详情',
  'builtin.plan_transition@1': '# 检查搜索详情',
  'builtin.plan_restart@1': '补充窄屏错误状态验证',
  'builtin.workflow_current@1': '校验结构化工具输出',
  'builtin.workflow_next@1': '确认实现已完成且所有 fixture 使用生产回执对象。',
  'builtin.workflow_graph@1': '工具展示契约验证',
  'builtin.workflow_history@1': '已完成工具输入输出对齐。',
  'builtin.workflow_transition@1': '实现已完成，开始定向验证',
  'builtin.workflow_restart@1': '发现遗漏的错误显示场景',
  'builtin.web_search@1': 'Flutter Widget Previewer',
  'builtin.deepseek_web_search@1': 'Flutter Widget Previewer',
  'builtin.deepseek_web_fetch@1': '官方预览器通过注解展示可组合的 Flutter 组件。',
  'generic@1': '通用工具的独立结果正文。',
};

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, appChild) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: ListTileTheme(
      data: Theme.of(context).listTileTheme,
      child: appChild!,
    ),
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('暗色工具代码与面板维持可读对比度', (tester) async {
    await tester.pumpWidget(darkToolDetailPreview());
    await tester.pumpAndSettle();
    final command = find.text('cargo test -p pl-core');
    final text = tester.widget<Text>(command);
    final scheme = Theme.of(tester.element(command)).colorScheme;
    expect(text.style?.color, scheme.onSurface);
    final foreground = text.style!.color!.computeLuminance();
    final background = scheme.surfaceContainerLow.computeLuminance();
    final ratio = foreground > background
        ? (foreground + .05) / (background + .05)
        : (background + .05) / (foreground + .05);
    expect(ratio, greaterThanOrEqualTo(4.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏搜索说明正文换行完整呈现而非代码横向裁切', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(narrowToolDetailPreview());
    await tester.pumpAndSettle();
    final output = toolDetailPreviewFixtures
        .singleWhere((fixture) => fixture.contract == 'builtin.web_search@1')
        .output;
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(output), matching: find.byType(RichText)),
    );
    expect(paragraph.size.width, lessThan(330));
    expect(
      paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: output.length),
          )
          .length,
      greaterThan(1),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工作组预览完整自然展开，仅 Main 滚动即可读到尾部工具正文', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 760);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(collapsedWorkGroupToolPreview());
    await tester.pumpAndSettle();
    expect(find.byType(TimelineToolItemView), findsNothing);
    await tester.pumpWidget(expandedWorkGroupScrollToolPreview());
    await tester.pumpAndSettle();
    expect(find.byType(TimelineToolItemView), findsNWidgets(3));
    final group = find.byType(CompletionRunView);
    expect(tester.getSize(group).height, greaterThan(420));
    final originalGroup = tester.widget<CompletionRunView>(group);
    final previewHost = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final tail = tester
        .widgetList<TimelineToolItemView>(find.byType(TimelineToolItemView))
        .last;
    final tailText = _expectedReadableText[tail.item.presentationContract]!;

    // Keep the exact preview members and theme, but replace its generic outer
    // scroll host with the production Main timeline and its borrowed controls.
    final controls = ExpandedWorkPreviewControls();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controls.dispose();
    });
    await controls.controller.insertMessage(
      TimelinePreviewFixtures.messages().first,
      animated: false,
    );
    tester.view.physicalSize = const Size(960, 420);
    await tester.pumpWidget(
      MaterialApp(
        locale: previewHost.locale,
        theme: previewHost.theme,
        localizationsDelegates: previewHost.localizationsDelegates,
        supportedLocales: previewHost.supportedLocales,
        builder: previewHost.builder,
        home: Scaffold(
          body: TimelineView(
            threadId: 'tool-preview-main',
            view: const TimelineSessionViewState(
              threadId: 'tool-preview-main',
              generation: 1,
              mode: TimelineDisplayMode.live,
              connection: TimelineConnectionPhase.ready,
            ),
            controls: controls,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async => true,
            onEnterHistory: () {},
            onRetryConnection: () {},
            onLink: (_) {},
            isSafeLink: (_) => false,
            remoteImageBuilder: (_, _) => const SizedBox.shrink(),
            canonicalPresentationBuilder: (_, _) => Column(
              children: [
                const Text('工作组之前：相邻内容'),
                originalGroup,
                const Text('工作组之后：相邻内容'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TimelineToolItemView), findsNWidgets(3));
    expect(tester.getSize(group).height, greaterThan(420));
    expect(controls.scrollController.positions, hasLength(1));
    final position = controls.scrollController.position;
    expect(position.maxScrollExtent, greaterThan(0));
    final verticalScroll = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
    );
    final mainScroll = find.ancestor(of: group, matching: verticalScroll);
    expect(mainScroll, findsOneWidget);
    expect(tester.state<ScrollableState>(mainScroll).position, same(position));
    for (final element in find.byType(TimelineToolItemView).evaluate()) {
      final member = find.byElementPredicate(
        (value) => identical(value, element),
      );
      // Inspect only ancestors: tool-body range readers and horizontal code
      // scrolling below a member are not group-level scroll ownership.
      final parents = find.ancestor(of: member, matching: verticalScroll);
      expect(parents, findsOneWidget);
      expect(tester.state<ScrollableState>(parents).position, same(position));
      final bounds = tester.getRect(member);
      expect(bounds.top, greaterThanOrEqualTo(tester.getRect(group).top));
      expect(bounds.bottom, lessThanOrEqualTo(tester.getRect(group).bottom));
    }

    // Main is reversed. Begin at the older edge, then reach the last member by
    // an actual upward drag; do not use ensureVisible to simulate reachability.
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final before = position.pixels;
    final tailBody = find
        .descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is TimelineToolItemView &&
                widget.item.id == tail.item.id,
          ),
          matching: find.textContaining(tailText),
        )
        .last;
    expect(tailBody.hitTestable(), findsNothing);
    await tester.drag(mainScroll, Offset(0, -position.maxScrollExtent - 100));
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(before));
    expect(tailBody.hitTestable(), findsOneWidget);
    final viewport = tester.getRect(mainScroll);
    final tailBounds = tester.getRect(tailBody);
    expect(tailBounds.top, greaterThanOrEqualTo(viewport.top));
    expect(tailBounds.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(find.text('工作组之后：相邻内容').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长搜索文本预览滚动后可访问末条正文', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 640);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(longToolResultPreview());
    await tester.pumpAndSettle();
    expect(find.textContaining('结构化结果不可用'), findsNothing);
    const lastText = '第 24 条结果：在合成文档中找到与查询相关的段落，并保留来源标题。';
    final lastResult = find.textContaining(lastText);
    expect(lastResult, findsOneWidget);
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: lastResult, matching: find.byType(RichText)),
    );
    final text = paragraph.text.toPlainText();
    final start = text.indexOf(lastText);
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + lastText.length),
    );
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      final rect = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
      expect(rect.bottom, lessThanOrEqualTo(640));
      expect(rect.top, greaterThanOrEqualTo(0));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('具体工具详情展开后显示可读正文且不泄漏原始参数或内部任务标识', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final fixture in toolDetailPreviewFixtures) {
      final item = fixture.toPresentation('test-${fixture.name}');
      await tester.pumpWidget(
        _host(
          TimelineToolItemView(
            item: item,
            initiallyExpanded: true,
            additionalContentBuilder:
                item.attachments.isEmpty && item.outputArtifacts.isEmpty
                ? null
                : (_) => toolDetailPreviewMediaSlot(item),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(TimelineToolItemView),
        findsOneWidget,
        reason: fixture.contract,
      );
      expect(
        find.textContaining('工具展开'),
        findsNothing,
        reason: fixture.contract,
      );
      expect(
        find.textContaining('task:internal-preview'),
        findsNothing,
        reason: fixture.contract,
      );
      expect(
        find.textContaining('task:preview-child'),
        findsNothing,
        reason: '${fixture.contract} 不应泄漏 wait result 的内部任务标识',
      );
      expect(
        find.textContaining(jsonEncode(fixture.arguments)),
        findsNothing,
        reason: '${fixture.contract} 不应显示原始参数信封',
      );
      if (fixture.output.startsWith('{')) {
        expect(
          find.text(fixture.output),
          findsNothing,
          reason: '${fixture.contract} 应呈现结构化语义字段而不是原始 JSON 回执',
        );
      }
      final expected = _expectedReadableText[fixture.contract];
      expect(expected, isNotNull, reason: '每个工具都要有独立正文期望：${fixture.contract}');
      expect(
        find.textContaining(expected!),
        findsWidgets,
        reason: '${fixture.contract} 应呈现对应的合成输入或结果',
      );
      expect(
        find.textContaining('"arguments"'),
        findsNothing,
        reason: fixture.contract,
      );
      expect(
        find.textContaining('"command"'),
        findsNothing,
        reason: fixture.contract,
      );
      expect(
        find.textContaining('"search_query"'),
        findsNothing,
        reason: fixture.contract,
      );
      if (fixture.contract == 'builtin.exec@2') {
        expect(find.textContaining('cargo test -p pl-core'), findsWidgets);
        expect(
          find.textContaining('Finished unit tests: 18 passed'),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull, reason: fixture.contract);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('apply_patch 使用当前 input envelope 并呈现新旧 diff', (tester) async {
    final fixture = toolDetailPreviewFixtures.singleWhere(
      (value) => value.contract == 'builtin.apply_patch@1',
    );
    await tester.pumpWidget(
      _host(
        TimelineToolItemView(
          item: fixture.toPresentation('test-valid-apply-patch'),
          initiallyExpanded: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TimelinePatchUnavailableHint), findsNothing);
    expect(find.textContaining('旧结果'), findsOneWidget);
    expect(find.textContaining('核验后的结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view_image 与 show_files 预览通过生产 attachment slot 呈现合成图片', (
    tester,
  ) async {
    for (final contract in ['builtin.view_image@1', 'builtin.show_files@1']) {
      final fixture = toolDetailPreviewFixtures.singleWhere(
        (value) => value.contract == contract,
      );
      final item = fixture.toPresentation('test-media-${fixture.name}');
      await tester.pumpWidget(
        _host(
          TimelineToolItemView(
            item: item,
            initiallyExpanded: true,
            additionalContentBuilder: (_) => toolDetailPreviewMediaSlot(item),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget, reason: contract);
      expect(
        find.textContaining('synthetic-landscape-320x180.png'),
        findsWidgets,
        reason: contract,
      );
      expect(tester.takeException(), isNull, reason: contract);
    }
  });

  testWidgets('搜索失败与命令超时的可理解错误正文在窄屏大字下可见', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final (fixture, message) in [
      (failedToolPreviewFixture, '搜索服务暂时不可用，请稍后重试。'),
      (timedOutToolPreviewFixture, '命令执行超时。'),
    ]) {
      await tester.pumpWidget(
        _host(
          TimelineToolItemView(
            item: fixture.toPresentation('test-error'),
            initiallyExpanded: true,
          ),
          scale: 1.6,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('task:internal-preview'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('新增协作工具与后台命令状态在展开与窄屏下可读且无原始线程哈希泄漏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cases = [
      (
        contract: 'builtin.read_agent_session@1',
        name: 'read_agent_session',
        status: 'succeeded',
        arguments: jsonEncode({
          'target': 'thread-66137cebcce11-a',
          'cursor': 'cursor-1',
          'limit': 20,
        }),
        output: jsonEncode({
          'items': [
            {'summary': '子智能体读取完成', 'status': 'completed'},
          ],
          'nextCursor': 'cursor-2',
        }),
        rowShouldNotContain: 'thread-66137cebcce11-a',
        expandedExpected: '子智能体读取完成',
      ),
      (
        contract: 'builtin.evaluate_agent@1',
        name: 'evaluate_agent',
        status: 'succeeded',
        arguments: jsonEncode({
          'target': 'thread-66137cebcce11-b',
          'role': 'verifier',
          'outcome': 'passed',
          'quality': 5,
          'instructionFollowing': 4,
          'comment': '验证结构清晰，单测覆盖完整',
        }),
        output: '{}',
        rowShouldNotContain: 'thread-66137cebcce11-b',
        expandedExpected: '验证结构清晰，单测覆盖完整',
      ),
      (
        contract: 'builtin.list_agents@1',
        name: 'list_agents',
        status: 'succeeded',
        arguments: '{}',
        output: jsonEncode([
          {'id': 'worker-a', 'role': 'builder', 'status': 'running'},
        ]),
        rowShouldNotContain: 'worker-a',
        expandedExpected: 'builder',
      ),
      (
        contract: 'builtin.interrupt_agent@1',
        name: 'interrupt_agent',
        status: 'succeeded',
        arguments: jsonEncode({
          'target': 'thread-66137cebcce11-c',
          'reason': '切换执行方案',
        }),
        output: jsonEncode({'interrupted': true}),
        rowShouldNotContain: 'thread-66137cebcce11-c',
        expandedExpected: '切换执行方案',
      ),
      (
        contract: 'builtin.close_agent@1',
        name: 'close_agent',
        status: 'succeeded',
        arguments: jsonEncode({'target': 'thread-66137cebcce11-d'}),
        output: jsonEncode({
          'target': 'thread-66137cebcce11-d',
          'agents': [
            {'agentId': 'worker-d', 'executionClosed': true},
          ],
        }),
        rowShouldNotContain: 'thread-66137cebcce11-d',
        expandedExpected: 'worker-d',
      ),
      (
        contract: 'builtin.wait_agent@1',
        name: 'wait_agent',
        status: 'succeeded',
        arguments: jsonEncode({
          'target': 'thread-66137cebcce11-e',
          'timeoutMs': 5000,
        }),
        output: jsonEncode({
          'target': 'thread-66137cebcce11-e',
          'report': '构建与分析通过',
          'timedOut': false,
        }),
        rowShouldNotContain: 'thread-66137cebcce11-e',
        expandedExpected: '构建与分析通过',
      ),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(
        _host(
          TimelineToolItemView(
            initiallyExpanded: true,
            item: ToolDetailPreviewFixture(
              name: testCase.name,
              contract: testCase.contract,
              arguments: jsonDecode(testCase.arguments) as Map<String, Object?>,
              output: testCase.output,
              status: testCase.status,
            ).toPresentation('preview-${testCase.name}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = tester.widget<TimelineActivityRow>(
        find.byType(TimelineActivityRow),
      );
      expect(
        row.label,
        isNot(contains(testCase.rowShouldNotContain)),
        reason: testCase.contract,
      );
      expect(
        find.textContaining(testCase.expandedExpected),
        findsWidgets,
        reason: testCase.contract,
      );
      expect(tester.takeException(), isNull, reason: testCase.contract);
    }
  });
}
