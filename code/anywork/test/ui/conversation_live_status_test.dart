import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state_machine.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_current_views.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_section.dart';

import '../support/display_fixtures.dart';

import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_compacting_zip_icon.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_clock.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_resting_cat.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_writing_indicator.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork_previews/src/features/conversation/timeline/previews/conversation_live_status_previews.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrapWithApp(
  Widget child, {
  bool disableAnimations = false,
  double width = 720,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    locale: const Locale('zh'),
    theme: pureStudioTheme(locale: const Locale('zh')),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations, textScaler: textScaler),
      child: appChild!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

ConversationActivityView _view({
  required String identity,
  required ConversationActivityKind kind,
  String? summary,
  String? thinkingSummary,
  int? thinkingSeconds,
  List<ThreadActivityToolEntry> activeTools = const [],
  int activeToolCount = 0,
  bool expandable = false,
  ThreadWaitPresentationView? wait,
}) {
  return ConversationActivityView(
    identity: identity,
    kind: kind,
    summary: summary,
    thinkingSummary: thinkingSummary,
    thinkingSeconds: thinkingSeconds,
    activeTools: activeTools,
    activeToolCount: activeToolCount,
    expandable: expandable,
    wait: wait,
  );
}

Widget _currentText(String id, String text, {String? label}) =>
    ConversationCurrentWindowView(id: id, label: label, text: text);

const _longResponse = '''
## 当前回复

这是第一段实时 Markdown 回复，用于验证自然高度和内部滚动。

- 已完成的事实逐条进入历史；
- 当前正文仍由唯一 current owner 提供；
- 长中文、链接和 `行内代码` 在阅读列内正常换行。

第二段继续增长，达到高度上限后只滚动正文，不显示虚假的业务箭头。

第三段保留更多内容，确保测试确实产生可滚动范围，而不是仅找到 ScrollView。

第四段仍然属于同一个生产 `ConversationCurrentWindowView` 子树。
''';

const _tools = [
  TimelineToolPresentation(
    id: 'tool-exec',
    toolCallId: 'exec-1',
    name: 'exec',
    presentationContract: 'builtin.exec@2',
    statusString: 'running',
    arguments: '  rg --files  \n',
    output: '\n  tool output  \n',
    workingDirectory: '.',
  ),
  TimelineToolPresentation(
    id: 'tool-write',
    toolCallId: 'write-1',
    name: 'write_file',
    presentationContract: 'builtin.write_file@1',
    statusString: 'running',
    arguments: '{"path":"source.txt"}',
    output: '',
  ),
];

Widget _group({Widget? content, bool live = true, String? thinkingSummary}) {
  if (!live) {
    return CompletionRunView(
      id: 'test-group',
      summary: displaySummary(82),
      location: WorkDisplayLocation.history,
      initiallyExpanded: false,
      childBuilder: (_) => content ?? const Text('成员正文'),
    );
  }
  return TimelineActivitySection(
    header: TimelineActivityRow(
      key: const ValueKey('activity-test-header'),
      label: thinkingSummary ?? '工作中',
      labelWidget: thinkingSummary == null
          ? null
          : TimelineReasoningSummary(text: thinkingSummary),
      header: true,
      active: true,
      expandable: false,
    ),
    body: content ?? const Text('成员正文'),
  );
}

void main() {
  group('统一实时状态栏', () {
    testWidgets('窄图标槽在父级裁剪时仍完整显示趴卧猫', (tester) async {
      const boundaryKey = ValueKey('clipped-activity-row');
      Widget scene(Clip clip) => _wrapWithApp(
        RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            height: 60,
            child: Center(
              child: SizedBox(
                width: 120,
                child: ClipRect(
                  clipBehavior: clip,
                  child: const TimelineActivityRow(
                    label: '思考中',
                    active: true,
                    header: true,
                    expandable: false,
                  ),
                ),
              ),
            ),
          ),
        ),
        width: 160,
      );
      Future<List<int>> pixels() async => (await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final image = await boundary.toImage(pixelRatio: 3);
        try {
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return bytes!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      }))!;
      for (final elapsed in [0, 800, 1000, 1200]) {
        await tester.pumpWidget(scene(Clip.none));
        await tester.pump(Duration(milliseconds: elapsed));
        final full = await pixels();
        await tester.pumpWidget(scene(Clip.hardEdge));
        final clipped = await pixels();
        expect(
          clipped.indexed.every((entry) => entry.$2 == full[entry.$1]),
          isTrue,
          reason: '父级裁剪不应切掉猫头、前爪或摆动中的尾巴的任何像素',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('趴卧猫逐帧保持身体像素固定，只有台沿以下的尾巴摆动', (tester) async {
      final progress = AnimationController(vsync: tester);
      addTearDown(progress.dispose);
      const boundaryKey = ValueKey('resting-cat-frame');
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: TimelineRestingCat(
              progress: progress,
              color: Colors.black,
              size: 128,
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      Future<List<int>> pixels() async => (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return bytes!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      }))!;
      final rest = await pixels();
      // 图标上部包含身体、前爪与台沿；尾巴从台沿下方开始。
      const bodyBytes = 128 * 70 * 4;
      for (final phase in [.2, .36, .5]) {
        progress.value = phase;
        await tester.pump();
        final frame = await pixels();
        expect(frame.take(bodyBytes), orderedEquals(rest.take(bodyBytes)));
        expect(
          frame.skip(bodyBytes),
          isNot(orderedEquals(rest.skip(bodyBytes))),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('输出显示书写图标、压缩显示动态拉链图标、exec 运行显示圆形进度，其余等待显示趴卧猫，故障保留错误图标', (
      tester,
    ) async {
      for (final kind in [
        ConversationActivityKind.preparing,
        ConversationActivityKind.compacting,
        ConversationActivityKind.thinking,
        ConversationActivityKind.planning,
        ConversationActivityKind.runningTool,
        ConversationActivityKind.responding,
        ConversationActivityKind.awaitingApproval,
        ConversationActivityKind.awaitingInput,
        ConversationActivityKind.stopping,
      ]) {
        await tester.pumpWidget(
          _wrapWithApp(
            ConversationActivityStatus(
              view: _view(identity: kind.name, kind: kind),
            ),
          ),
        );
        if (kind == ConversationActivityKind.responding) {
          expect(find.byType(TimelineRestingCat), findsNothing);
          expect(find.byType(TimelineWritingIndicator), findsOneWidget);
        } else if (kind == ConversationActivityKind.compacting) {
          expect(find.byType(TimelineRestingCat), findsNothing);
          expect(find.byType(TimelineCompactingZipIcon), findsOneWidget);
        } else {
          expect(
            find.byType(TimelineRestingCat),
            findsOneWidget,
            reason: kind.name,
          );
        }
      }
      final progress = tester
          .widget<TimelineRestingCat>(find.byType(TimelineRestingCat))
          .progress;
      final before = progress.value;
      await tester.pump(const Duration(milliseconds: 700));
      expect(progress.value, isNot(before));

      // 前台正在执行 exec 命令时，顶栏切换为圆形进度，不再显示趴卧猫。
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityStatus(
            view: _view(
              identity: 'running-exec',
              kind: ConversationActivityKind.runningTool,
              activeTools: const [
                ThreadActivityToolEntry(
                  callId: 'exec-call-1',
                  name: 'exec',
                  summary: 'cargo flutter test',
                  arguments: ThreadActivityArgumentsKind.commandLine,
                  state: ThreadActivityToolState.running,
                  startedAt: 100,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(TimelineRestingCat), findsNothing);
      expect(find.byType(TimelineExecProgressIndicator), findsOneWidget);

      // 减少动态效果时，圆形进度与动态拉链图标均保持确定性静止帧，不挂载循环帧回调。
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityStatus(
            view: _view(
              identity: 'running-exec-static',
              kind: ConversationActivityKind.runningTool,
              activeTools: const [
                ThreadActivityToolEntry(
                  callId: 'exec-call-1',
                  name: 'exec',
                  summary: 'cargo flutter test',
                  arguments: ThreadActivityArgumentsKind.commandLine,
                  state: ThreadActivityToolState.running,
                  startedAt: 100,
                ),
              ],
            ),
          ),
          disableAnimations: true,
        ),
      );
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        0.72,
      );
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityStatus(
            view: _view(
              identity: 'compacting-static',
              kind: ConversationActivityKind.compacting,
            ),
          ),
          disableAnimations: true,
        ),
      );
      final zipStatic = tester
          .widget<TimelineCompactingZipIcon>(
            find.byType(TimelineCompactingZipIcon),
          )
          .progress;
      expect(zipStatic.value, 0.0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(zipStatic.value, 0.0);

      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityStatus(
            view: _view(
              identity: 'storage-failure',
              kind: ConversationActivityKind.storageBlocked,
            ),
          ),
        ),
      );
      expect(find.byType(TimelineRestingCat), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('书写时纸面固定且只有笔移动，减少动态效果时停止移动', (tester) async {
      for (final disabled in [false, true]) {
        await tester.pumpWidget(
          _wrapWithApp(
            const ConversationResponseView(child: Text('正在增长的正文')),
            disableAnimations: disabled,
          ),
        );
        expect(find.byType(TimelineRestingCat), findsNothing);
        expect(find.byType(TimelineWritingIndicator), findsOneWidget);
        final paper = find.byKey(const ValueKey('writing-paper'));
        final pen = find.byKey(const ValueKey('writing-pen'));
        await tester.pump();
        final paperBefore = tester.getRect(paper);
        final penBefore = tester.getRect(pen);
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.getRect(paper), paperBefore);
        expect(tester.getRect(pen), disabled ? penBefore : isNot(penBefore));
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pumpWidget(
        _wrapWithApp(
          const ConversationResponseView(active: false, child: Text('已结束的正文')),
        ),
      );
      expect(find.byType(TimelineWritingIndicator), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('官方预览直接装配生产组件且各工况可渲染', (tester) async {
      for (final preview in [
        conversationRestingCatPreview,
        conversationCompactingZipPreview,
        conversationFourStatesComparisonPreview,
        conversationLiveStatusWaitingPreview,
        conversationLiveStatusCompactingPreview,
        conversationLiveStatusToolsPreview,
        conversationLiveStatusIdleGroupPreview,
        conversationLiveStatusCompletedGroupPreview,
        conversationLiveStatusNextGroupPreview,
        conversationLiveStatusThinkingPreview,
        conversationLiveStatusLongToolPreview,
        conversationReasoningVariantsPreview,
        conversationLiveStatusRespondingPreview,
        conversationLiveStatusShortResponsePreview,
        conversationLiveStatusWaitPreview,
        conversationLiveStatusNarrowScaledPreview,
        conversationLiveStatusWidePreview,
        conversationLiveStatusStoppingPreview,
        conversationLiveStatusStorageFailurePreview,
      ]) {
        await tester.pumpWidget(preview());
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('无内容状态不可展开，压缩仅显示真实单行状态', (tester) async {
      for (final kind in [
        ConversationActivityKind.thinking,
        ConversationActivityKind.compacting,
      ]) {
        await tester.pumpWidget(
          _wrapWithApp(
            ConversationActivityBar(
              children: [
                ConversationActivityStatus(
                  view: _view(
                    identity: kind.name,
                    kind: kind,
                    expandable: true,
                    thinkingSeconds: 125,
                    summary: '压缩不应消费的详情',
                  ),
                ),
              ],
            ),
          ),
        );
        expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(
          find.text(
            kind == ConversationActivityKind.thinking ? '思考中' : '正在压缩上下文',
          ),
          findsOneWidget,
        );
        if (kind == ConversationActivityKind.compacting) {
          expect(find.text('压缩不应消费的详情'), findsNothing);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final width in [360.0, 760.0, 1040.0]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('标题、统计与箭头在宽度 $width 和字号 $scale 下完整可读', (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrapWithApp(
              ConversationActivityBar(children: [_group(live: false)]),
              width: width,
              textScaler: TextScaler.linear(scale),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          final l10n = AppLocalizations.of(
            tester.element(find.byType(Scaffold)),
          );
          final label = find.text(l10n.timelineGroupRecord);
          expect(label, findsOneWidget);
          final card = tester.getRect(
            find.byKey(const ValueKey('conversation-activity')),
          );
          final title = tester.getRect(label);
          expect(find.textContaining('执行失败'), findsNothing);
          expect(title.left, greaterThanOrEqualTo(card.left));
          expect(title.right, lessThanOrEqualTo(card.right));
          expect(tester.widget<Text>(label).maxLines, 1);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }

    testWidgets('思考概要在窄窗和文字缩放下保持一行，正文保持独立展开', (tester) async {
      for (final width in [360.0, 760.0, 1040.0]) {
        await tester.binding.setSurfaceSize(Size(width, 600));
        for (final scale in [1.0, 1.6]) {
          Widget scene(String summary) => _wrapWithApp(
            ConversationActivityBar(
              children: [
                _group(
                  thinkingSummary: summary,
                  content: TimelineReasoningView(
                    summary: summary,
                    body: const Text('按需展开的正文'),
                  ),
                ),
              ],
            ),
            width: width,
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          );
          await tester.pumpWidget(scene('短概要'));
          await tester.pump();
          final shortHeight = tester
              .getSize(find.byType(TimelineReasoningView))
              .height;
          await tester.pumpWidget(
            scene('**第一段概要很长，必须在有限宽度内省略而不换行。**' * 8 + '\n\n第二段概要也不能使折叠成员增高。'),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          final headerParagraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byKey(const ValueKey('activity-test-header')),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is RichText &&
                    widget.text.toPlainText().contains('第一段概要很长'),
              ),
            ),
          );
          expect(headerParagraph.maxLines, 1);
          expect(headerParagraph.didExceedMaxLines, isTrue);
          expect(
            tester.getSize(find.byType(TimelineReasoningView)).height,
            closeTo(shortHeight, .1),
          );
          expect(find.text('按需展开的正文'), findsNothing);
          final row = find.descendant(
            of: find.byType(TimelineReasoningView),
            matching: find.byType(TimelineActivityRow),
          );
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(find.text('按需展开的正文'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
      await tester.binding.setSurfaceSize(null);
    });

    for (final response in [false, true]) {
      testWidgets('正文自然增长并服从父级高度，标题不滚动 ($response)', (tester) async {
        Widget scene(double height) => _wrapWithApp(
          SizedBox(
            height: height,
            child: ConversationActivityBar(
              children: [
                if (response)
                  ConversationResponseView(
                    child: _currentText('long', _longResponse),
                  )
                else
                  _group(
                    content: const SizedBox(height: 400, child: Text('长成员正文')),
                  ),
              ],
            ),
          ),
        );
        for (final height in [160.0, 17.4, 0.0, 160.0]) {
          await tester.pumpWidget(scene(height));
          await tester.pump();
          expect(tester.takeException(), isNull);
          final scroll = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          expect(scroll.position.viewportDimension, lessThanOrEqualTo(height));
        }
        final title = find.text(response ? '正在输出' : '工作中');
        final before = tester.getRect(title);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -80),
        );
        await tester.pump();
        expect(tester.getRect(title), before);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('短回复保留自然高度', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            children: [
              ConversationResponseView(child: _currentText('short', '短回复。')),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('conversation-activity')))
            .height,
        lessThan(120),
      );
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .maxScrollExtent,
        0,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('用户上滚暂停跟随，内容增加不跳动，显式操作恢复跟随', (tester) async {
      Widget scene(String text) => _wrapWithApp(
        ConversationActivityBar(
          children: [
            ConversationResponseView(child: _currentText('follow', text)),
          ],
        ),
      );
      await tester.pumpWidget(scene(_longResponse * 3));
      await tester.pump();
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(scroll.maxScrollExtent, greaterThan(0));
      expect(scroll.pixels, scroll.maxScrollExtent);
      final cardHeight = tester
          .getSize(find.byKey(const ValueKey('conversation-activity')))
          .height;
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 120),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('跟随输出'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('conversation-activity')))
            .height,
        cardHeight,
      );
      final before = scroll.pixels;
      await tester.pumpWidget(scene(_longResponse * 4));
      await tester.pump();
      expect(scroll.pixels, before);
      await tester.tap(find.text('跟随输出'));
      await tester.pump();
      expect(scroll.pixels, scroll.maxScrollExtent);
      expect(find.text('跟随输出'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('工具与等待详情仍使用生产组件和官方展开控件', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            children: [
              _group(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final tool in _tools) TimelineToolDetails(item: tool),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TimelineToolDetails), findsNWidgets(2));
      expect(find.byType(ExpansionTile), findsNWidgets(2));
      // _tools[0] 为 exec 命令，展开行使用圆形进度；_tools[1] 为 write_file，保持趴卧猫。
      final toolRows = tester
          .widgetList<TimelineToolDetails>(find.byType(TimelineToolDetails))
          .toList();
      expect(
        find.descendant(
          of: find.byWidget(toolRows[0]),
          matching: find.byType(TimelineExecProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byWidget(toolRows[0]),
          matching: find.byType(TimelineRestingCat),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byWidget(toolRows[1]),
          matching: find.byType(TimelineRestingCat),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(conversationLiveStatusWaitPreview());
      await tester.pump(const Duration(milliseconds: 300));
      final group = tester.widget<CompletionRunView>(
        find.byType(CompletionRunView),
      );
      final disclosure = find.byKey(
        ValueKey('completion-run-disclosure:${group.id}'),
      );
      expect(
        tester.widget<Expansible>(disclosure).controller.isExpanded,
        isFalse,
      );
      expect(find.byType(TimelineWaitDetails), findsNothing);
      await tester.tap(
        find.byKey(ValueKey('completion-run-header:${group.id}')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<Expansible>(disclosure).controller.isExpanded,
        isTrue,
      );
      expect(find.byType(TimelineWaitDetails), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('展开的长工具输出完整增高，窄窗换行并仅由外层滚动到末行', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const lastLine = '末行检查完成';
      final output = [
        for (var i = 0; i < 60; i++) '检查第 $i 项：通过。',
        '需要检查的连续长路径/' * 12,
        lastLine,
      ].join('\n');
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            children: [
              _group(
                content: TimelineToolDetails(
                  initiallyExpanded: true,
                  item: TimelineToolPresentation(
                    id: 'long-output',
                    toolCallId: 'long-output',
                    name: 'exec',
                    presentationContract: 'builtin.exec@2',
                    statusString: 'succeeded',
                    arguments: '{"command":"cargo flutter analyze"}',
                    output: output,
                  ),
                ),
              ),
            ],
          ),
          width: 360,
          textScaler: TextScaler.linear(1.6),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final positions = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .map((state) => state.position);
      final outer = positions.singleWhere(
        (position) => position.maxScrollExtent > 0,
      );
      expect(
        positions.where((position) => position.maxScrollExtent > 0),
        hasLength(1),
      );
      expect(
        positions.every((position) => position.axis == Axis.vertical),
        isTrue,
      );
      expect(outer.maxScrollExtent, greaterThan(280));
      final header = tester.getRect(find.text('工作中'));
      outer.jumpTo(outer.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('工作中')), header);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == output,
        ),
      );
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: output.indexOf(lastLine),
          extentOffset: output.length,
        ),
      );
      expect(boxes, hasLength(1));
      final glyph = boxes.single.toRect().shift(
        paragraph.localToGlobal(Offset.zero),
      );
      final viewport = tester
          .getRect(find.byType(SingleChildScrollView).first)
          .inflate(1);
      expect(viewport.contains(glyph.topLeft), isTrue);
      expect(viewport.contains(glyph.bottomRight), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('耗时取真实投影，未知时不补零；减少动态效果保留静止趴卧猫', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            children: [
              ConversationActivityStatus(
                view: _view(
                  identity: 'elapsed',
                  kind: ConversationActivityKind.thinking,
                  thinkingSeconds: 125,
                ),
              ),
            ],
          ),
          disableAnimations: true,
        ),
      );
      expect(find.text('用时 2 分 5 秒'), findsOneWidget);
      expect(find.byType(TimelineRestingCat), findsOneWidget);
      final progress = tester
          .widget<TimelineRestingCat>(find.byType(TimelineRestingCat))
          .progress;
      final still = progress.value;
      await tester.pump(const Duration(milliseconds: 700));
      expect(progress.value, still);
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            children: [
              ConversationActivityStatus(
                view: _view(
                  identity: 'unknown',
                  kind: ConversationActivityKind.thinking,
                ),
              ),
            ],
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('conversation-activity-trailing-meta')),
        findsNothing,
      );
      await tester.pump();
      final resumed = tester
          .widget<TimelineRestingCat>(find.byType(TimelineRestingCat))
          .progress;
      final resumedBefore = resumed.value;
      await tester.pump(const Duration(milliseconds: 700));
      expect(resumed.value, isNot(resumedBefore));
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('有界窗口只通过同步动作翻页并保留原文', (tester) async {
      var first = 0;
      var next = 0;
      const text = '窗口原文\n\n- 第一项\n- 第二项';
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationCurrentWindowView(
            id: 'window-1',
            label: '当前计划文档',
            text: text,
            offset: 32,
            end: 64,
            availableThrough: 96,
            onFirst: () => first++,
            onNext: () => next++,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('当前计划文档'), findsOneWidget);
      expect(find.textContaining('窗口原文'), findsOneWidget);
      expect(find.text('字节 32–64 / 96'), findsOneWidget);
      await tester.tap(find.text('第一段'));
      await tester.tap(find.text('下一段'));
      expect(first, 1);
      expect(next, 1);
    });

    test('compaction 仅接管合格的当前轮次活动原子', () {
      final activeCompaction = ChatAtom(
        id: 'compact-1',
        source: const ForegroundTurnChatSource(turnId: 'turn-1'),
        sourceOrder: null,
        kind: ChatAtomKind.compaction,
        delivery: ChatDeliveryKind.foreground,
        lifecycle: const ActiveChatAtom(
          started: null,
          status: ChatActiveStatus.running,
        ),
        startedAt: 200,
        contents: const [],
      );
      LiveDisplayBlock block({
        DisplayBlockState state = DisplayBlockState.open,
        ChatAtom? atom,
        DisplayContentSource contentSource = const CurrentAtom(),
      }) => LiveDisplayBlock(
        id: 'compact-1',
        blockOrder: 1,
        state: state,
        source: const ForegroundTurnChatSource(turnId: 'turn-1'),
        body: SingleDisplayBlock(
          record: DisplayRecord(
            atom: atom ?? activeCompaction,
            contentSource: contentSource,
          ),
        ),
      );
      LiveDisplayWindow window(
        List<LiveDisplayBlock> blocks, {
        bool executionPresent = true,
      }) => LiveDisplayWindow(
        revision: 1,
        historyThrough: 0,
        executionPresent: executionPresent,
        blocks: blocks,
      );
      ExecutionLiveNotice notice({
        String? turnId = 'turn-1',
        ConversationActivityKind kind = ConversationActivityKind.compacting,
        String? errorMessage,
      }) => ExecutionLiveNotice(
        ConversationActivityView(
          identity: 'compaction-status',
          kind: kind,
          turnId: turnId,
          errorMessage: errorMessage,
        ),
      );
      bool owns(LiveDisplayWindow? live, {ExecutionLiveNotice? activity}) =>
          LiveStatusStateMachine.hasCurrentOutputRenderer(
            live: live,
            activeTurnId: 'turn-1',
            notice: activity ?? notice(),
          );

      expect(owns(window([block()])), isTrue);
      expect(owns(window([])), isFalse, reason: '缺少记录时状态提示仍需呈现');
      expect(
        owns(window([block()]), activity: notice(turnId: 'turn-2')),
        isFalse,
        reason: '不得接管其他轮次的提示',
      );
      expect(
        owns(
          window([
            block(
              atom: ChatAtom(
                id: 'compact-1',
                source: const ForegroundTurnChatSource(turnId: 'turn-1'),
                sourceOrder: null,
                kind: ChatAtomKind.compaction,
                delivery: ChatDeliveryKind.foreground,
                lifecycle: const TerminalChatAtom(
                  started: null,
                  ended: null,
                  outcome: ChatTerminalOutcome.completed,
                ),
                startedAt: 200,
                contents: const [],
              ),
            ),
          ]),
        ),
        isFalse,
        reason: '终态原子不再接管实时提示',
      );
      expect(
        owns(
          window([
            block(
              atom: ChatAtom(
                id: 'compact-1',
                source: const ForegroundTurnChatSource(turnId: 'turn-2'),
                sourceOrder: null,
                kind: ChatAtomKind.compaction,
                delivery: ChatDeliveryKind.foreground,
                lifecycle: const ActiveChatAtom(
                  started: null,
                  status: ChatActiveStatus.running,
                ),
                startedAt: 200,
                contents: const [],
              ),
            ),
          ]),
        ),
        isFalse,
        reason: '原子的前台来源必须属于当前轮次',
      );
      expect(
        owns(
          window([
            block(contentSource: const FrozenObservation(available: true)),
          ]),
        ),
        isFalse,
        reason: '冷读记录不接管实时提示',
      );
      expect(
        owns(
          window([
            block(
              atom: ChatAtom(
                id: 'text-1',
                source: const ForegroundTurnChatSource(turnId: 'turn-1'),
                sourceOrder: null,
                kind: ChatAtomKind.text,
                delivery: ChatDeliveryKind.foreground,
                lifecycle: const ActiveChatAtom(
                  started: null,
                  status: ChatActiveStatus.running,
                ),
                contents: const [],
              ),
            ),
          ]),
        ),
        isFalse,
        reason: '仅 compaction 原子可接管压缩提示',
      );
      expect(
        owns(
          window([block()]),
          activity: notice(kind: ConversationActivityKind.stopping),
        ),
        isFalse,
        reason: '停止提示始终独立呈现',
      );
      expect(
        owns(window([block()]), activity: notice(errorMessage: '存储失败')),
        isFalse,
        reason: '错误提示始终独立呈现',
      );
      expect(
        owns(window([block()], executionPresent: false)),
        isFalse,
        reason: '执行缺席时不接管冷读窗口',
      );
    });

    testWidgets('跨全工况切换固定 Logo 槽与单行文案零抖动，且趴卧猫摆尾连续不归零', (tester) async {
      final harness = _ZeroJitterHarness();
      addTearDown(harness.dispose);
      const longThought =
          '这是一段超长的实时思考概要文案，用于验证从思考中切换到开启新工作组及待交接状态时绝不会折双行跳高或推动文案起点偏移';

      LiveDisplayBlock workBlock(
        String id, {
        required int order,
        DisplayBlockState state = DisplayBlockState.open,
        int total = 2,
        int running = 1,
        int failed = 0,
        int transferred = 0,
        String? thought,
      }) => LiveDisplayBlock(
        id: id,
        blockOrder: order,
        state: state,
        source: const ForegroundTurnChatSource(turnId: 'turn-1'),
        body: WorkDisplayBlock(
          summary: WorkSummary(
            unavailable: 0,
            total: total,
            terminal: total - running,
            running: running,
            waiting: 0,
            failed: failed,
            cancelled: 0,
            transferred: transferred,
            createdAt: 100,
            elapsedMs: 125000,
            thinkingSummary: thought,
          ),
          members: DisplayBlockRef(databaseId: 'db', blockId: id),
        ),
      );

      final stages =
          <
            ({
              String name,
              bool collapsedSingleRow,
              TimelineActivityIndicatorStyle expectedStyle,
              String expectedTitle,
              List<LiveDisplayBlock> blocks,
              ThreadActivityView? status,
            })
          >[
            (
              name: 'preparing',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: '准备中',
              blocks: const [],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-1',
                revision: 1,
                turnId: 'turn-1',
                kind: ThreadActivityKind.preparing,
                summary: '',
              ),
            ),
            (
              name: 'thinking',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: '思考中',
              blocks: const [],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-2',
                revision: 2,
                turnId: 'turn-1',
                kind: ThreadActivityKind.thinking,
                summary: '',
                thinkingSeconds: 17,
              ),
            ),
            (
              name: 'old-sealed-before-new-model-request',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: '思考中',
              blocks: [
                workBlock(
                  'old-work',
                  order: 0,
                  state: DisplayBlockState.sealed,
                  running: 0,
                  thought: '旧组摘要不得带入新组',
                ),
              ],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-new-request',
                revision: 3,
                turnId: 'turn-1',
                kind: ThreadActivityKind.waitingApi,
                summary: '',
                thinkingSeconds: 17,
              ),
            ),
            (
              name: 'new-work-waiting-api-without-result-or-summary',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: '思考中',
              blocks: [
                workBlock(
                  'old-work',
                  order: 0,
                  state: DisplayBlockState.sealed,
                  running: 0,
                  thought: '旧组摘要不得带入新组',
                ),
                workBlock('work-1', order: 1, total: 1),
              ],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-new-request',
                revision: 4,
                turnId: 'turn-1',
                kind: ThreadActivityKind.waitingApi,
                summary: '',
                thinkingSeconds: 17,
              ),
            ),
            (
              name: 'new-work-thinking-before-exec',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: '思考中',
              blocks: [workBlock('work-1', order: 1, total: 1)],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-thinking-before-exec',
                revision: 5,
                turnId: 'turn-1',
                kind: ThreadActivityKind.thinking,
                summary: '',
                thinkingSeconds: 18,
              ),
            ),
            (
              name: 'workgroup',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: longThought,
              blocks: [
                workBlock('work-1', order: 1, running: 2, thought: longThought),
              ],
              status: ThreadActivityView(
                threadId: 'thread',
                identity: 'act-3',
                revision: 3,
                turnId: 'turn-1',
                kind: ThreadActivityKind.runningTool,
                summary: '',
                tools: ThreadActivityTools(
                  count: 1,
                  background: 0,
                  active: const [
                    ThreadActivityToolEntry(
                      callId: 'exec-1',
                      name: 'exec',
                      summary: 'cargo flutter analyze',
                      arguments: ThreadActivityArgumentsKind.commandLine,
                      state: ThreadActivityToolState.running,
                      startedAt: 100,
                    ),
                  ],
                ),
              ),
            ),
            (
              name: 'all-members-terminal-transferred-waiting-api-again',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: longThought,
              blocks: [
                workBlock(
                  'work-1',
                  order: 1,
                  running: 0,
                  transferred: 1,
                  thought: longThought,
                ),
              ],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-4',
                revision: 4,
                turnId: 'turn-1',
                kind: ThreadActivityKind.waitingApi,
                summary: '',
                thinkingSeconds: 19,
              ),
            ),
            (
              name: 'failed-call-thinking',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: '思考中',
              blocks: [workBlock('work-1', order: 1, running: 0, failed: 1)],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-failed-call-thinking',
                revision: 5,
                turnId: 'turn-1',
                kind: ThreadActivityKind.thinking,
                summary: '',
              ),
            ),
            (
              name: 'failed-call-with-thought',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: longThought,
              blocks: [
                workBlock(
                  'work-1',
                  order: 1,
                  running: 0,
                  failed: 1,
                  thought: longThought,
                ),
              ],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-failed-call-thought',
                revision: 6,
                turnId: 'turn-1',
                kind: ThreadActivityKind.thinking,
                summary: '',
              ),
            ),
            (
              name: 'text',
              collapsedSingleRow: false,
              expectedStyle: TimelineActivityIndicatorStyle.writing,
              expectedTitle: '正在输出',
              blocks: [
                workBlock(
                  'work-1',
                  order: 1,
                  state: DisplayBlockState.sealed,
                  running: 0,
                  thought: longThought,
                ),
                LiveDisplayBlock(
                  id: 'text-1',
                  blockOrder: 2,
                  state: DisplayBlockState.open,
                  source: const ForegroundTurnChatSource(turnId: 'turn-1'),
                  body: SingleDisplayBlock(
                    record: DisplayRecord(
                      atom: ChatAtom(
                        id: 'text-1',
                        source: const ForegroundTurnChatSource(
                          turnId: 'turn-1',
                        ),
                        sourceOrder: null,
                        kind: ChatAtomKind.text,
                        delivery: ChatDeliveryKind.foreground,
                        lifecycle: const ActiveChatAtom(
                          started: null,
                          status: ChatActiveStatus.running,
                        ),
                        startedAt: 120,
                        contents: const [],
                        payload: InlinePayload(
                          bytes: utf8.encode(
                            jsonEncode({
                              'contract': 'anywork.chat/1',
                              'type': 'text',
                              'data': {'channel': 'final', 'attachments': []},
                              'bodies': [
                                {
                                  'key': 'body',
                                  'byteLength': utf8
                                      .encode('流式输出第一段正文。')
                                      .length,
                                  'inline': utf8.encode('流式输出第一段正文。'),
                                },
                              ],
                            }),
                          ),
                        ),
                      ),
                      contentSource: const CurrentAtom(),
                    ),
                  ),
                ),
              ],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-5',
                revision: 5,
                turnId: 'turn-1',
                kind: ThreadActivityKind.responding,
                summary: '',
              ),
            ),
            (
              name: 'after-text',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: '思考中',
              blocks: [
                workBlock(
                  'work-1',
                  order: 1,
                  state: DisplayBlockState.sealed,
                  running: 0,
                ),
              ],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-6',
                revision: 6,
                turnId: 'turn-1',
                kind: ThreadActivityKind.thinking,
                summary: '',
                thinkingSeconds: 4,
              ),
            ),
            (
              name: 'next-group-exec-only',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.circularProgress,
              expectedTitle: '工作中',
              blocks: [
                workBlock(
                  'work-1',
                  order: 1,
                  state: DisplayBlockState.sealed,
                  running: 0,
                ),
                workBlock('work-2', order: 3, running: 1),
              ],
              status: ThreadActivityView(
                threadId: 'thread',
                identity: 'act-7a',
                revision: 7,
                turnId: 'turn-1',
                kind: ThreadActivityKind.runningTool,
                summary: '',
                tools: ThreadActivityTools(
                  count: 1,
                  background: 0,
                  active: const [
                    ThreadActivityToolEntry(
                      callId: 'exec-2',
                      name: 'exec',
                      summary: 'cargo flutter test',
                      arguments: ThreadActivityArgumentsKind.commandLine,
                      state: ThreadActivityToolState.running,
                      startedAt: 150,
                    ),
                  ],
                ),
              ),
            ),
            (
              name: 'next-group',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: '运行测试并核对布局',
              blocks: [
                workBlock(
                  'work-1',
                  order: 1,
                  state: DisplayBlockState.sealed,
                  running: 0,
                ),
                workBlock('work-2', order: 3, running: 1, thought: '运行测试并核对布局'),
              ],
              status: ThreadActivityView(
                threadId: 'thread',
                identity: 'act-7b',
                revision: 8,
                turnId: 'turn-1',
                kind: ThreadActivityKind.runningTool,
                summary: '',
                tools: ThreadActivityTools(
                  count: 1,
                  background: 0,
                  active: const [
                    ThreadActivityToolEntry(
                      callId: 'exec-2',
                      name: 'exec',
                      summary: 'cargo flutter test',
                      arguments: ThreadActivityArgumentsKind.commandLine,
                      state: ThreadActivityToolState.running,
                      startedAt: 150,
                    ),
                  ],
                ),
              ),
            ),
            (
              name: 'compacting',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.compactingZip,
              expectedTitle: '正在压缩上下文',
              blocks: [
                LiveDisplayBlock(
                  id: 'compact-1',
                  blockOrder: 4,
                  state: DisplayBlockState.open,
                  source: const ForegroundTurnChatSource(turnId: 'turn-1'),
                  body: SingleDisplayBlock(
                    record: DisplayRecord(
                      atom: ChatAtom(
                        id: 'compact-1',
                        source: const ForegroundTurnChatSource(
                          turnId: 'turn-1',
                        ),
                        sourceOrder: null,
                        kind: ChatAtomKind.compaction,
                        delivery: ChatDeliveryKind.foreground,
                        lifecycle: const ActiveChatAtom(
                          started: null,
                          status: ChatActiveStatus.running,
                        ),
                        startedAt: 200,
                        contents: const [],
                      ),
                      contentSource: const CurrentAtom(),
                    ),
                  ),
                ),
              ],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-compacting',
                revision: 10,
                turnId: 'turn-1',
                kind: ThreadActivityKind.compacting,
                summary: '',
              ),
            ),
            (
              name: 'compacting-without-record',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.compactingZip,
              expectedTitle: '正在压缩上下文',
              blocks: const [],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-compacting-no-record',
                revision: 11,
                turnId: 'turn-1',
                kind: ThreadActivityKind.compacting,
                summary: '',
              ),
            ),
            (
              name: 'stopping',
              collapsedSingleRow: true,
              expectedStyle: TimelineActivityIndicatorStyle.restingCat,
              expectedTitle: '停止中',
              blocks: const [],
              status: const ThreadActivityView(
                threadId: 'thread',
                identity: 'act-9',
                revision: 9,
                turnId: 'turn-1',
                kind: ThreadActivityKind.stopping,
                summary: '',
              ),
            ),
          ];

      Size? baselineCardSize;
      Offset? baselineLogoOffset;
      Offset? baselineTitleOffset;
      double? previousCatPhase;

      for (final stage in stages) {
        harness.blocks = stage.blocks;
        harness.status = stage.status;
        await tester.pumpWidget(harness.build());
        await tester.pump();

        final barFinder = find.byKey(const ValueKey('conversation-activity'));
        expect(barFinder, findsOneWidget, reason: stage.name);
        final barRect = tester.getRect(barFinder);

        if (stage.name == 'compacting') {
          expect(
            find.descendant(of: barFinder, matching: find.text('正在压缩上下文')),
            findsOneWidget,
            reason: '当前 compaction 原子和提示不得形成两行标题',
          );
        }
        final indicatorFinder = find.descendant(
          of: barFinder,
          matching: find.byType(TimelineActivityIndicator),
        );
        expect(indicatorFinder, findsOneWidget, reason: stage.name);
        final currentWork = find.descendant(
          of: barFinder,
          matching: find.byType(CompletionRunView),
        );
        if (currentWork.evaluate().isNotEmpty) {
          expect(find.byType(ConversationActivityStatus), findsNothing);
          expect(
            find.byKey(const ValueKey('conversation-activity-trailing-meta')),
            findsNothing,
          );
          expect(
            find.descendant(of: barFinder, matching: find.text('执行了 7 分 8 秒')),
            findsOneWidget,
            reason: '${stage.name}: group elapsed is never the phase timer',
          );
          expect(
            find.descendant(
              of: barFinder,
              matching: find.textContaining('思考了'),
            ),
            findsNothing,
          );
        }
        expect(find.text('等待下一步'), findsNothing);
        final slotFinder = find
            .ancestor(
              of: indicatorFinder,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is SizedBox &&
                    w.width == TimelineActivityRow.headerLogoSlotSize &&
                    w.height == TimelineActivityRow.headerLogoSlotSize,
              ),
            )
            .first;
        final slotRect = tester.getRect(slotFinder);
        expect(slotRect.size, const Size(32, 32), reason: stage.name);

        final titleFinder = find.descendant(
          of: barFinder,
          matching: find.text(stage.expectedTitle),
        );
        expect(titleFinder, findsOneWidget, reason: stage.name);
        if (stage.name == 'compacting') {
          expect(
            find.descendant(
              of: barFinder,
              matching: find.byType(TimelineCompactingZipIcon),
            ),
            findsOneWidget,
            reason: '当前 compaction 原子与状态提示共用一个拉链指示器',
          );
          expect(
            tester
                .widget<TimelineActivityClock>(
                  find.descendant(
                    of: barFinder,
                    matching: find.byType(TimelineActivityClock),
                  ),
                )
                .startedAt,
            200,
            reason: '去重状态提示不得替代原记录计时',
          );
        }
        final titleRect = tester.getRect(titleFinder);

        final logoRelative = slotRect.topLeft - barRect.topLeft;
        final titleRelative = titleRect.topLeft - barRect.topLeft;

        baselineLogoOffset ??= logoRelative;
        baselineTitleOffset ??= titleRelative;
        expect(
          logoRelative.dx,
          closeTo(baselineLogoOffset.dx, 0.001),
          reason: '${stage.name} Logo 槽水平位置不得偏移',
        );
        expect(
          logoRelative.dy,
          closeTo(baselineLogoOffset.dy, 0.001),
          reason: '${stage.name} Logo 槽垂直位置不得偏移',
        );
        expect(
          titleRelative.dx,
          closeTo(baselineTitleOffset.dx, 0.001),
          reason: '${stage.name} 文案起点水平位置不得偏移',
        );
        expect(
          titleRelative.dy,
          closeTo(baselineTitleOffset.dy, 0.001),
          reason: '${stage.name} 文案起点垂直位置不得偏移',
        );

        if (stage.collapsedSingleRow) {
          baselineCardSize ??= barRect.size;
          expect(
            barRect.size.height,
            closeTo(baselineCardSize.height, 0.001),
            reason: '${stage.name} 折叠单行外框高度不得跳变',
          );
          expect(
            barRect.size.width,
            closeTo(baselineCardSize.width, 0.001),
            reason: '${stage.name} 折叠单行外框宽度不得跳变',
          );
        }

        switch (stage.expectedStyle) {
          case TimelineActivityIndicatorStyle.restingCat:
            final cat = tester.widget<TimelineRestingCat>(
              find.descendant(
                of: barFinder,
                matching: find.byType(TimelineRestingCat),
              ),
            );
            if (previousCatPhase != null) {
              expect(
                cat.progress.value,
                closeTo(previousCatPhase, 0.001),
                reason: '${stage.name} 连续猫态切换时趴卧猫相位不得跳回 0',
              );
            }
            await tester.pump(const Duration(milliseconds: 260));
            expect(cat.progress.value, isNot(previousCatPhase ?? -1));
            previousCatPhase = cat.progress.value;
          case TimelineActivityIndicatorStyle.circularProgress:
            previousCatPhase = null;
            expect(
              find.descendant(
                of: barFinder,
                matching: find.byType(TimelineExecProgressIndicator),
              ),
              findsOneWidget,
              reason: '${stage.name} exec 运行时顶栏必须显示圆形进度',
            );
            expect(
              find.descendant(
                of: barFinder,
                matching: find.byType(TimelineRestingCat),
              ),
              findsNothing,
            );
            await tester.pump(const Duration(milliseconds: 120));
          case TimelineActivityIndicatorStyle.writing:
            previousCatPhase = null;
            expect(
              find.descendant(
                of: barFinder,
                matching: find.byType(TimelineWritingIndicator),
              ),
              findsOneWidget,
              reason: '${stage.name} 输出阶段顶栏必须显示书写图标',
            );
            await tester.pump(const Duration(milliseconds: 120));
          case TimelineActivityIndicatorStyle.compactingZip:
            previousCatPhase = null;
            expect(
              find.descendant(
                of: barFinder,
                matching: find.byType(TimelineCompactingZipIcon),
              ),
              findsOneWidget,
              reason: '${stage.name} 压缩阶段顶栏必须显示动态拉链图标',
            );
            expect(
              find.descendant(
                of: barFinder,
                matching: find.byType(TimelineRestingCat),
              ),
              findsNothing,
            );
            await tester.pump(const Duration(milliseconds: 120));
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

class _ZeroJitterSession extends Fake implements ThreadSessionState {
  @override
  String get threadId => 'thread';
  @override
  ThreadActivityView? get activity => null;
  @override
  StudioTurnView get activeTurn => StudioTurnView(
    turnId: 'turn-1',
    threadId: 'thread',
    revision: 1,
    state: const RunningStudioTurnState(
      startedAt: 100,
      activity: StudioTurnActivity.thinking,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(225000),
  );
}

class _ZeroJitterContent extends Fake implements ConversationContent {
  final source = LatestValue<ChatUiState<bool>>(
    const ChatReady('thread', true),
  );
  @override
  bool get isClosed => false;
  @override
  ValueObservation<ChatUiState<bool>> get state => source;
  @override
  AttemptId get currentAttemptId => const AttemptId(1);
}

class _ZeroJitterHarness {
  final content = _ZeroJitterContent();
  final live = ValueNotifier<LiveDisplayWindow?>(null);
  final images = TimelineImageResources(threadId: 'thread');
  final expansions = <String, TimelineExpansionIntent>{};
  List<LiveDisplayBlock> blocks = const [];
  ThreadActivityView? status;
  int revision = 0;

  Widget build() {
    final window = LiveDisplayWindow(
      revision: ++revision,
      historyThrough: 0,
      executionPresent: true,
      blocks: blocks,
    );
    live.value = window;
    final aggregate = LiveStatusStateMachine.transition(
      LiveStatusAggregate.initial('thread'),
      LiveStatusObserved(
        LiveStatusObservation(
          cut: LiveWindowCut(
            revision: window.revision,
            historyThrough: window.historyThrough,
            executionPresent: window.executionPresent,
            attemptId: 1,
            isDisplayActive: true,
          ),
          activeTurnId: 'turn-1',
          activity: status,
          latestLive: window,
          hasContentOwner: true,
        ),
      ),
    ).state;
    final presenting = aggregate.barState as LiveStatusPresenting;
    Widget section(ConversationLiveSection s) => ConversationCurrentConnector(
      section: s,
      managedByViewModel: true,
      session: _ZeroJitterSession(),
      content: content,
      live: live,
      presenting: s == ConversationLiveSection.output ? presenting : null,
      workSlice: s == ConversationLiveSection.work
          ? aggregate.timelineWork
          : null,
      images: images,
      readAttachment: (_) async => Uint8List(0),
      now: () => DateTime.fromMillisecondsSinceEpoch(528000),
      isDisplayActive: () => true,
      liveUnit: (block, executionPresent) => TimelineDisplayUnit.live(
        block: block,
        executionPresent: executionPresent,
        expansion: expansions.putIfAbsent(
          block.id,
          TimelineExpansionIntent.new,
        ),
      ),
    );
    return _wrapWithApp(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section(ConversationLiveSection.work),
          section(ConversationLiveSection.output),
        ],
      ),
      width: 560,
    );
  }

  void dispose() {
    for (final intent in expansions.values) {
      intent.retire();
      intent.dispose();
    }
    images.release();
    content.source.close();
    live.dispose();
  }
}
