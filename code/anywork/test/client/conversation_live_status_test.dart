import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

Widget _wrapWithApp(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    locale: const Locale('zh'),
    theme: pureStudioTheme(locale: const Locale('zh')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, appChild) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: appChild!,
      );
    },
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 720, child: child),
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
  List<ThreadActivityContentPart> reasoningParts = const [],
  List<ThreadActivityContentPart> responseParts = const [],
  List<ThreadActivityToolEntry> activeTools = const [],
  List<ThreadActivityToolDetail> toolDetails = const [],
  int activeToolCount = 0,
  String? errorMessage,
  List<ConversationActivityDetail> details = const [],
  bool expandable = false,
}) {
  return ConversationActivityView(
    identity: identity,
    kind: kind,
    summary: summary,
    thinkingSummary: thinkingSummary,
    thinkingSeconds: thinkingSeconds,
    reasoningParts: reasoningParts,
    responseParts: responseParts,
    activeTools: activeTools,
    toolDetails: toolDetails,
    activeToolCount: activeToolCount,
    errorMessage: errorMessage,
    details: details,
    expandable: expandable,
  );
}

ThreadActivityContentPart _part({
  required String itemId,
  required String text,
  bool complete = false,
}) {
  return ThreadActivityContentPart(
    itemId: itemId,
    complete: complete,
    text: text,
  );
}

ThreadActivityToolEntry _toolEntry({
  required String callId,
  required String name,
  String? summary,
  int? startedAt,
}) {
  return ThreadActivityToolEntry(
    callId: callId,
    name: name,
    summary: summary ?? name,
    arguments: ThreadActivityArgumentsKind.opaque,
    state: ThreadActivityToolState.running,
    startedAt: startedAt,
  );
}

ThreadActivityToolDetail _toolDetail({
  required String callId,
  required String name,
  String? arguments,
  List<ThreadActivityToolOutputPart>? outputParts,
}) {
  return ThreadActivityToolDetail(
    callId: callId,
    name: name,
    state: ThreadActivityToolState.running,
    arguments: arguments,
    outputParts: outputParts,
  );
}

void main() {
  group('ConversationActivityBar (direct ConversationActivityView)', () {
    testWidgets('思考中且无正文时只显示不可展开的「思考中」', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'activity:thinking-empty',
              kind: ConversationActivityKind.thinking,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('思考中'), findsOneWidget);
      expect(find.text('正在压缩'), findsNothing);
      expect(
        find.byKey(const ValueKey('conversation-activity-details')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('conversation-activity')),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('压缩阶段显示「正在压缩」，与思考中互斥且不可展开', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'activity:compacting',
              kind: ConversationActivityKind.compacting,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('正在压缩'), findsOneWidget);
      expect(find.text('思考中'), findsNothing);
      expect(
        find.byKey(const ValueKey('conversation-activity-details')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('conversation-activity')),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('有真实推理正文才可展开，展开后完整阅读且摘要保持单行', (tester) async {
      const reasoning = '第一段早期推理内容会被完整保留。\n\n第二段继续推进，确认展开区不是单行截断。';
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'activity:thinking-full',
              kind: ConversationActivityKind.thinking,
              thinkingSummary: '已收敛出最终架构设计方案',
              reasoningParts: [
                _part(itemId: 'think-1', text: reasoning),
              ],
              expandable: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('已收敛出最终架构设计方案'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('conversation-activity-thinking-full')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('conversation-activity')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('conversation-activity-details')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('conversation-activity-thinking-full')),
        findsOneWidget,
      );
      expect(find.textContaining('第一段早期推理内容会被完整保留'), findsWidgets);
    });

    testWidgets('思考摘要本身不可展开；多段正文各自增长且不拼接', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'activity:thinking-summary-only',
              kind: ConversationActivityKind.thinking,
              thinkingSummary: '已收敛出最终架构设计方案',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('已收敛出最终架构设计方案'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('conversation-activity')),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );

      const firstA = '模型甲第一段。';
      const firstB = '模型乙第一段。';
      const grownA = '模型甲第一段。续写甲。';
      const grownB = '模型乙第一段。续写乙。';
      Widget bar({required String a, required String b}) {
        return _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'activity:thinking-parts',
              kind: ConversationActivityKind.thinking,
              thinkingSummary: '摘要不是完整正文',
              reasoningParts: [
                _part(itemId: 'model-a', text: a),
                _part(itemId: 'model-b', text: b),
              ],
              expandable: true,
            ),
          ),
        );
      }

      await tester.pumpWidget(bar(a: firstA, b: firstB));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('conversation-activity')));
      await tester.pump();

      final keyA = find.byKey(
        const ValueKey('conversation-activity-thinking-part-model-a'),
      );
      final keyB = find.byKey(
        const ValueKey('conversation-activity-thinking-part-model-b'),
      );
      expect(keyA, findsOneWidget);
      expect(keyB, findsOneWidget);
      expect(tester.getTopLeft(keyA).dy, lessThan(tester.getTopLeft(keyB).dy));
      expect(find.text(firstA), findsOneWidget);
      expect(find.text(firstB), findsOneWidget);
      expect(find.text(firstA + firstB), findsNothing);

      await tester.pumpWidget(bar(a: grownA, b: grownB));
      await tester.pump();
      expect(keyA, findsOneWidget);
      expect(keyB, findsOneWidget);
      expect(tester.getTopLeft(keyA).dy, lessThan(tester.getTopLeft(keyB).dy));
      expect(find.text(grownA), findsOneWidget);
      expect(find.text(grownB), findsOneWidget);
      expect(find.text(firstA), findsNothing);
      expect(find.text(grownA + grownB), findsNothing);
    });

    testWidgets('多工具用 ExpansionTile 真实展开，参数与输出原文保留', (tester) async {
      const firstArgs = '  rg --files  \n';
      const firstOut = '\n  tool output  \n';
      const secondArgs = '{"path":"source.txt"}';
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'activity:tools',
              kind: ConversationActivityKind.runningTool,
              activeTools: [
                _toolEntry(
                  callId: 'exec-1',
                  name: 'exec',
                  summary: 'rg --files',
                ),
                _toolEntry(
                  callId: 'write-1',
                  name: 'write_file',
                  summary: 'write_file source.txt',
                ),
              ],
              toolDetails: [
                _toolDetail(
                  callId: 'exec-1',
                  name: 'exec',
                  arguments: firstArgs,
                  outputParts: [
                    const ThreadActivityToolOutputPart(
                      partId: 'stdout',
                      text: firstOut,
                    ),
                  ],
                ),
                _toolDetail(
                  callId: 'write-1',
                  name: 'write_file',
                  arguments: secondArgs,
                ),
              ],
              activeToolCount: 2,
              expandable: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('执行中'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('conversation-activity')));
      await tester.pump();

      expect(find.textContaining('rg --files'), findsWidgets);
      expect(find.byType(ExpansionTile), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('live-tool-details-exec-1')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('live-tool-row-exec-1')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('live-tool-details-exec-1')),
        findsOneWidget,
      );
      expect(find.text(firstArgs), findsOneWidget);
      expect(find.text(firstOut), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('live-tool-row-write-1')));
      await tester.pump();
      expect(find.text(secondArgs), findsOneWidget);
    });

    testWidgets('多段工具输出按 part 顺序各自更新，原文可完整阅读', (tester) async {
      const first = 'stdout line 1\n';
      const secondStart = 'stderr start';
      const secondUpdated = 'stderr start\nstderr continued  \n';
      Widget bar({
        required String partA,
        required String partB,
      }) {
        return _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'activity:tool-parts',
              kind: ConversationActivityKind.runningTool,
              activeTools: [
                _toolEntry(callId: 'exec-parts', name: 'exec', summary: 'exec'),
              ],
              toolDetails: [
                _toolDetail(
                  callId: 'exec-parts',
                  name: 'exec',
                  outputParts: [
                    ThreadActivityToolOutputPart(partId: 'stdout', text: partA),
                    ThreadActivityToolOutputPart(partId: 'stderr', text: partB),
                  ],
                ),
              ],
              activeToolCount: 1,
              expandable: true,
            ),
          ),
        );
      }

      await tester.pumpWidget(bar(partA: first, partB: secondStart));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('conversation-activity')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('live-tool-row-exec-parts')));
      await tester.pump();

      final stdoutKey = find.byKey(
        const ValueKey('live-tool-output-exec-parts-stdout'),
      );
      final stderrKey = find.byKey(
        const ValueKey('live-tool-output-exec-parts-stderr'),
      );
      expect(stdoutKey, findsOneWidget);
      expect(stderrKey, findsOneWidget);
      expect(
        tester.getTopLeft(stdoutKey).dy,
        lessThan(tester.getTopLeft(stderrKey).dy),
      );
      expect(find.text(first), findsOneWidget);
      expect(find.text(secondStart), findsOneWidget);
      expect(find.text(first + secondStart), findsNothing);

      await tester.pumpWidget(bar(partA: first, partB: secondUpdated));
      await tester.pump();

      expect(stdoutKey, findsOneWidget);
      expect(stderrKey, findsOneWidget);
      expect(
        tester.getTopLeft(stdoutKey).dy,
        lessThan(tester.getTopLeft(stderrKey).dy),
      );
      expect(find.text(first), findsOneWidget);
      expect(find.text(secondUpdated), findsOneWidget);
      expect(find.text(secondStart), findsNothing);
      expect(find.text(first + secondUpdated), findsNothing);
    });

    testWidgets('回复正文有界滚动且不可展开，保留原文且不加载外部图片', (tester) async {
      const url = 'https://fixture.invalid/status-image.png';
      const body = '\n![external]($url)\n\n正常文字。\n';
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'activity:responding',
              kind: ConversationActivityKind.responding,
              responseParts: [
                _part(itemId: 'resp-1', text: body),
              ],
            ),
            maxResponseHeight: 120,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('回复中'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('conversation-activity-response-stream')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('live-response-part-resp-1')),
        findsOneWidget,
      );
      expect(tester.widget<GptMarkdown>(find.byType(GptMarkdown)).data, body);
      expect(find.text(url), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      final longBody = StringBuffer(body);
      for (var i = 0; i < 20; i++) {
        longBody.writeln('- 第 $i 条详细输出说明，验证达到最大高度上限后不再无限撑高状态栏。');
      }
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'activity:responding',
              kind: ConversationActivityKind.responding,
              responseParts: [
                _part(itemId: 'resp-1', text: longBody.toString()),
              ],
            ),
            maxResponseHeight: 120,
          ),
        ),
      );
      await tester.pump();

      final streamBoxSize = tester.getSize(
        find.byKey(const ValueKey('conversation-activity-response-stream')),
      );
      expect(streamBoxSize.height, lessThanOrEqualTo(120.0));
      expect(
        find.byKey(const ValueKey('conversation-activity-details')),
        findsNothing,
      );
    });

    testWidgets('disableAnimations 时前导图标不旋转', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ConversationActivityBar(
            view: _view(
              identity: 'activity:thinking-static',
              kind: ConversationActivityKind.thinking,
            ),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('conversation-activity-leading-spin')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('conversation-activity-leading')),
        findsOneWidget,
      );
    });
  });
}
