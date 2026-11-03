import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_current_views.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
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
    localizationsDelegates: AppLocalizations.localizationsDelegates,
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
    ConversationCurrentDetailsView(
      windows: [
        ConversationCurrentWindowView(id: id, label: label, text: text),
      ],
    );

const _longResponse = '''
## 当前回复

这是第一段实时 Markdown 回复，用于验证自然高度和内部滚动。

- 已完成的事实逐条进入历史；
- 当前正文仍由唯一 current owner 提供；
- 长中文、链接和 `行内代码` 在阅读列内正常换行。

第二段继续增长，达到高度上限后只滚动正文，不显示虚假的业务箭头。

第三段保留更多内容，确保测试确实产生可滚动范围，而不是仅找到 ScrollView。

第四段仍然属于同一个生产 `ConversationCurrentDetailsView` 子树。
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

void main() {
  group('ConversationActivityBar with production content', () {
    for (final responding in [false, true]) {
      testWidgets('有界状态栏将长正文限制在自身区域内 ($responding)', (tester) async {
        const frame = ValueKey('bounded-footer');
        Widget host(double height) => _wrapWithApp(
          SizedBox(
            key: frame,
            height: height,
            child: ConversationActivityBar(
              view: _view(
                identity: 'bounded-$responding',
                kind: responding
                    ? ConversationActivityKind.responding
                    : ConversationActivityKind.runningTool,
                expandable: !responding,
              ),
              content: const SizedBox(height: 400, child: Text('同一个生产正文插槽')),
            ),
          ),
        );
        await tester.pumpWidget(host(160));
        if (!responding) {
          await tester.tap(find.byKey(const ValueKey('conversation-activity')));
          await tester.pump();
        }

        expect(tester.takeException(), isNull);
        final scroll = find.byType(SingleChildScrollView);
        expect(scroll, findsOneWidget);
        final viewport = tester.getRect(scroll);
        final footer = tester.getRect(find.byKey(frame));
        expect(viewport.top, greaterThanOrEqualTo(footer.top));
        expect(viewport.bottom, lessThanOrEqualTo(footer.bottom));
        await tester.drag(scroll, const Offset(0, -100));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final state = tester.state(find.byType(ConversationActivityBar));
        for (final height in [17.4, 0.0, 160.0]) {
          await tester.pumpWidget(host(height));
          expect(tester.takeException(), isNull);
          expect(
            tester.state(find.byType(ConversationActivityBar)),
            same(state),
          );
          expect(tester.getSize(find.byKey(frame)).height, height);
          if (!responding) {
            expect(
              find.byIcon(Icons.keyboard_arrow_down_rounded),
              findsOneWidget,
            );
          }
        }
        final restoredHeader = tester.getRect(
          find.byKey(const ValueKey('conversation-activity')),
        );
        expect(restoredHeader.height, greaterThan(20));
        expect(
          restoredHeader.bottom,
          lessThanOrEqualTo(tester.getRect(find.byKey(frame)).bottom),
        );
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('思考中无 content 时不可展开，即使 view 声明 expandable', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'thinking-empty',
              kind: ConversationActivityKind.thinking,
              expandable: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('思考中'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('conversation-activity-details')),
        findsNothing,
      );
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('conversation-activity')),
        ),
        isSemantics(
          isButton: false,
          hasExpandedState: false,
          hasToggledState: false,
          hasTapAction: false,
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('conversation-activity')),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('压缩为单行且与思考互斥，不消费传入 content', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'compacting',
              kind: ConversationActivityKind.compacting,
              summary: '保留本轮关键事实',
              expandable: true,
            ),
            content: const Text('压缩态不应呈现的详情'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('正在压缩上下文'), findsOneWidget);
      expect(find.text('思考中'), findsNothing);
      expect(find.text('压缩态不应呈现的详情'), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    });

    testWidgets('唯一 content 决定详情能力，由 bar 自身展开并通知真实 demand', (tester) async {
      final demand = <bool>[];
      const reasoning = '第一段早期推理内容。\n\n第二段继续推进并保留 Markdown 原文。';
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'thinking-content',
              kind: ConversationActivityKind.thinking,
              thinkingSummary: '已收敛出最终架构设计方案',
              expandable: false,
            ),
            content: _currentText('thinking', reasoning, label: '当前思考'),
            onExpandedChanged: demand.add,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('已收敛出最终架构设计方案'), findsOneWidget);
      expect(find.text('思考中'), findsOneWidget);
      expect(find.textContaining('第一段早期推理内容'), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      final header = find.byKey(const ValueKey('conversation-activity'));
      void expectDisclosure({required bool expanded}) {
        expect(
          tester.getSemantics(header),
          isSemantics(
            isButton: true,
            hasExpandedState: true,
            isExpanded: expanded,
            hasToggledState: false,
            hasTapAction: true,
          ),
        );
      }

      expectDisclosure(expanded: false);

      await tester.tap(header);
      await tester.pump();

      expect(demand, [true]);
      expect(
        find.byKey(const ValueKey('conversation-activity-details')),
        findsOneWidget,
      );
      expect(find.textContaining('第一段早期推理内容'), findsOneWidget);
      expect(find.text('思考中'), findsOneWidget);
      expect(find.textContaining('已收敛出最终架构设计方案'), findsNothing);
      expect(find.text('当前思考'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      expectDisclosure(expanded: true);

      await tester.tap(header);
      await tester.pump();
      expect(demand, [true, false]);
      expect(find.textContaining('第一段早期推理内容'), findsNothing);
      expectDisclosure(expanded: false);
    });

    testWidgets('identity 改变时 bar 自身收起并通知 demand 关闭', (tester) async {
      final demand = <bool>[];
      Widget bar(String identity, String body) => _wrapWithApp(
        ConversationActivityBar(
          view: _view(
            identity: identity,
            kind: ConversationActivityKind.thinking,
            expandable: true,
          ),
          content: _currentText(identity, body),
          onExpandedChanged: demand.add,
        ),
      );

      await tester.pumpWidget(bar('turn-a', '第一轮正文'));
      await tester.tap(find.byKey(const ValueKey('conversation-activity')));
      await tester.pump();
      expect(find.text('第一轮正文'), findsOneWidget);

      await tester.pumpWidget(bar('turn-b', '第二轮正文'));
      await tester.pump();

      expect(demand, [true, false]);
      expect(
        find.byKey(const ValueKey('conversation-activity-details')),
        findsNothing,
      );
      expect(find.text('第二轮正文'), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('工具正文复用生产 TimelineToolDetails 和官方 ExpansionTile', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'tools',
              kind: ConversationActivityKind.runningTool,
              activeTools: const [
                ThreadActivityToolEntry(
                  callId: 'exec-1',
                  name: 'exec',
                  summary: 'rg --files',
                  arguments: ThreadActivityArgumentsKind.commandLine,
                  state: ThreadActivityToolState.running,
                ),
                ThreadActivityToolEntry(
                  callId: 'write-1',
                  name: 'write_file',
                  summary: 'write_file source.txt',
                  arguments: ThreadActivityArgumentsKind.opaque,
                  state: ThreadActivityToolState.running,
                ),
              ],
              activeToolCount: 2,
              expandable: true,
            ),
            content: Column(
              children: [
                for (final tool in _tools) TimelineToolDetails(item: tool),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('执行中'), findsOneWidget);
      expect(find.byType(TimelineToolDetails), findsNothing);

      await tester.tap(find.byKey(const ValueKey('conversation-activity')));
      await tester.pump();
      expect(find.byType(TimelineToolDetails), findsNWidgets(2));
      expect(find.byType(ExpansionTile), findsNWidgets(2));

      final toolDisclosure = find.descendant(
        of: find.byKey(const ValueKey('timeline-tool-details:tool-exec')),
        matching: find.byType(ExpansionTile),
      );
      expect(toolDisclosure, findsOneWidget);
      final toolTitle = find
          .descendant(of: toolDisclosure, matching: find.byType(InkWell))
          .first;
      final detailsScroll = find.descendant(
        of: find.byKey(const ValueKey('conversation-activity-details')),
        matching: find.byType(Scrollable),
      );
      expect(detailsScroll, findsOneWidget);
      await tester.scrollUntilVisible(
        toolTitle,
        -40,
        scrollable: detailsScroll,
      );
      expect(toolTitle.hitTestable(), findsOneWidget);
      await tester.tap(toolTitle);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('rg --files'), findsWidgets);
      expect(find.textContaining('tool output'), findsOneWidget);
    });

    testWidgets('回复 Markdown 自然增长到上限后内部滚动且无假箭头', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'responding-long',
              kind: ConversationActivityKind.responding,
              expandable: true,
            ),
            content: _currentText('response', _longResponse),
            maxResponseHeight: 120,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('回复中'), findsOneWidget);
      expect(find.textContaining('这是第一段实时 Markdown 回复'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('conversation-activity-response-stream')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('短回复保持自然高度而非强制撑到上限', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'responding-short',
              kind: ConversationActivityKind.responding,
            ),
            content: _currentText('short', '短回复。'),
            maxResponseHeight: 220,
          ),
        ),
      );
      await tester.pump();

      final stream = tester.getSize(
        find.byKey(const ValueKey('conversation-activity-response-stream')),
      );
      expect(stream.height, lessThan(220));
      expect(find.text('短回复。'), findsOneWidget);
    });

    testWidgets('reduceMotion 时等待/回复图标静止且不创建旋转节点', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'responding-static',
              kind: ConversationActivityKind.responding,
            ),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(TimelineActivityIndicator),
          matching: find.byType(RotationTransition),
        ),
        findsNothing,
      );
      expect(find.byType(TimelineActivityIndicator), findsOneWidget);
    });

    testWidgets('等待 current 使用 typed TimelineWaitDetails 并由 bar 展开', (
      tester,
    ) async {
      final wait = ThreadWaitPresentationView(
        intent: ThreadWaitEventsIntentView(
          targets: const [
            ThreadWaitTargetView(
              taskId: 'task:done',
              summary: '已完成的成员',
              status: ThreadWaitTargetStatusView.succeeded,
            ),
            ThreadWaitTargetView(
              taskId: 'task:running',
              summary: '仍在运行的成员',
              status: ThreadWaitTargetStatusView.running,
            ),
          ],
          timeoutMs: 300000,
        ),
        state: ThreadWaitStateView.waiting,
      );
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'typed-wait',
              kind: ConversationActivityKind.runningTool,
              activeTools: [
                ThreadActivityToolEntry(
                  callId: 'wait-1',
                  name: 'wait',
                  summary: '等待两个成员返回',
                  arguments: ThreadActivityArgumentsKind.opaque,
                  state: ThreadActivityToolState.running,
                  wait: wait,
                ),
              ],
              activeToolCount: 1,
              expandable: true,
              wait: wait,
            ),
            content: TimelineWaitDetails(
              presentation: wait,
              identity: 'typed-wait',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('等待工具完成'), findsOneWidget);
      expect(find.byType(TimelineWaitDetails), findsNothing);
      await tester.tap(find.byKey(const ValueKey('conversation-activity')));
      await tester.pump();
      expect(find.byType(TimelineWaitDetails), findsOneWidget);
      expect(find.textContaining('已完成的成员'), findsOneWidget);
      expect(find.textContaining('仍在运行的成员'), findsOneWidget);
    });

    testWidgets('标题耗时直接来自 current 投影', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'elapsed',
              kind: ConversationActivityKind.thinking,
              thinkingSeconds: 17,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('17s'), findsOneWidget);
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'unknown-elapsed',
              kind: ConversationActivityKind.thinking,
            ),
          ),
        ),
      );
      expect(find.text('0s'), findsNothing);
      expect(
        find.byKey(const ValueKey('conversation-activity-trailing-meta')),
        findsNothing,
      );
    });

    testWidgets('窄窗与 160% 字体缩放不裁切标题或回复正文', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'narrow-scaled',
              kind: ConversationActivityKind.responding,
            ),
            content: _currentText(
              'scaled-response',
              '较长的实时回复正文会自然换行，并在达到高度上限后内部滚动。',
            ),
            maxResponseHeight: 180,
          ),
          width: 320,
          textScaler: const TextScaler.linear(1.6),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('回复中'), findsOneWidget);
      expect(find.textContaining('较长的实时回复正文'), findsOneWidget);
      final header = tester.getSize(
        find.byKey(const ValueKey('conversation-activity')),
      );
      expect(header.height, greaterThanOrEqualTo(28));
    });
  });

  group('Conversation current pure views', () {
    testWidgets('有界窗口只通过同步动作翻页并保留原文', (tester) async {
      var first = 0;
      var next = 0;
      const text = '窗口原文\n\n- 第一项\n- 第二项';
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationCurrentDetailsView(
            windows: [
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
            ],
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

    testWidgets('集合纯组件转交展开、重读与下一页动作', (tester) async {
      final expansions = <bool>[];
      var reloads = 0;
      var nextPages = 0;
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationCurrentCollectionView(
            title: '当前工具',
            stale: true,
            onExpansionChanged: expansions.add,
            onReload: () => reloads++,
            onNextPage: () => nextPages++,
            entries: const [
              ConversationCurrentEntryView(
                title: 'exec · cargo flutter analyze',
                child: Text('合成参数原文'),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final collectionTile = tester.widget<ExpansionTile>(
        find.byType(ExpansionTile),
      );
      expect(collectionTile.showTrailingIcon, isFalse);
      final title = tester.getRect(find.text('当前工具'));
      final arrow = tester.getRect(find.byIcon(Icons.chevron_right_rounded));
      expect(arrow.left - title.right, inInclusiveRange(0, 8));
      await tester.tap(find.text('当前工具'));
      await tester.pumpAndSettle();

      expect(expansions, [true]);
      expect(find.text('当前集合已更新，原版本已失效'), findsOneWidget);
      await tester.tap(find.text('重新读取当前页'));
      await tester.pump();
      await tester.tap(find.text('下一页'));
      expect(reloads, 1);
      expect(nextPages, 1);
      await tester.tap(find.text('exec · cargo flutter analyze'));
      await tester.pumpAndSettle();
      expect(find.text('合成参数原文'), findsOneWidget);
      for (final tile in tester.widgetList<ExpansionTile>(
        find.byType(ExpansionTile),
      )) {
        expect(tile.showTrailingIcon, isFalse);
      }
    });
  });
}
