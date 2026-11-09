import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/previews/timeline_component_previews.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/completion_run_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_ui_controllers.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_plain_text.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../support/completion_fixtures.dart';

const _bodyRef = ContentRef(
  databaseId: 'body-database',
  target: BodyContentTarget(
    owner: ItemContentOwner(itemId: 'body-item'),
    key: 'body',
  ),
);

ChatAtom _atom(
  String text, {
  bool deferred = true,
  bool includePayload = true,
}) => ChatAtom(
  id: 'body-item',
  source: const ForegroundTurnChatSource(turnId: 'turn'),
  sourceOrder: 1,
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contents: const [
    ChatAtomContent(role: ChatContentRole.body, reference: _bodyRef),
  ],
  payload: includePayload
      ? InlinePayload(
          bytes: utf8.encode(
            jsonEncode({
              'contract': 'anywork.chat/1',
              'type': 'text',
              'data': {'channel': 'final', 'attachments': []},
              'bodies': [
                {
                  'key': 'body',
                  'byteLength': utf8.encode(text).length,
                  if (deferred)
                    'reference': {
                      'databaseId': 'body-database',
                      'target': {
                        'kind': 'body',
                        'owner': {'kind': 'item', 'itemId': 'body-item'},
                        'key': 'body',
                      },
                    }
                  else
                    'inline': utf8.encode(text),
                },
              ],
            }),
          ),
        )
      : null,
);

ContentWindow _window(String text, {int offset = 0, int? available}) =>
    ContentWindow(
      offset: offset,
      bytes: utf8.encode(text),
      generation: 'body-generation',
      availableThrough: available ?? offset + utf8.encode(text).length,
      sealed: true,
    );

Widget _app(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

final class _Controls implements TimelineUiControllers {
  _Controls(ChatAtom atom)
    : controller = InMemoryChatController(
        messages: [
          Message.custom(
            id: atom.id,
            authorId: 'assistant',
            metadata: {
              chatItemPresentationKey: atom.payload == null
                  ? ChatItemPresentation.forUnit(
                      TimelineDisplayUnit(
                        entry: CompletedEntry(
                          recordId: atom.id,
                          completionSeq: 1,
                          run: null,
                          mainPresentation: MainPresentation.single,
                          atom: atom,
                        ),
                      ),
                    )
                  : ChatItemPresentation.decode(atom),
            },
          ),
        ],
      );
  @override
  final chatKey = UniqueKey();
  @override
  final InMemoryChatController controller;
  @override
  final scrollController = ScrollController();
  @override
  bool get isRetired => false;
  @override
  void bind() {}
  @override
  Future<void> unbind() async {}
  void dispose() {
    for (final message in controller.messages) {
      chatItemPresentationOf(message)?.displayUnit?.expansion.dispose();
    }
    controller.dispose();
    scrollController.dispose();
  }
}

Widget _main(_Controls controls, ChatContentRead read) => TimelineView(
  threadId: 'thread',
  controls: controls,
  view: const TimelineSessionViewState(
    threadId: 'thread',
    generation: 1,
    mode: TimelineDisplayMode.history,
    connection: TimelineConnectionPhase.ready,
  ),
  onLoadOlder: () async {},
  onRetryOlder: () async {},
  onReturnLive: () async {},
  onEnterHistory: () {},
  onRetryConnection: () {},
  onLink: (_) {},
  isSafeLink: (_) => false,
  remoteImageBuilder: (_, _) => const Text('媒体需显式加载'),
  contentRangeBuilder: (id, key, label, reference, witness) =>
      TimelineContentRangeConnector(
        itemId: id,
        contentKey: key,
        label: label,
        reference: reference,
        witness: witness,
        readContent: read,
      ),
);

Future<String?> _copySelection(WidgetTester tester) async {
  String? copied;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied = (call.arguments as Map)['text'] as String;
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  final selection = tester.state<SelectableRegionState>(
    find.byType(SelectableRegion),
  );
  selection.selectAll(SelectionChangedCause.keyboard);
  await tester.pump();
  selection.contextMenuButtonItems
      .firstWhere((item) => item.type == ContextMenuButtonType.copy)
      .onPressed!();
  await tester.pump();
  return copied;
}

final class _Content extends Fake implements ConversationContent {
  _Content(this.read);
  final ChatContentRead read;
  @override
  ConversationQueryScope openScope({required int generation}) => _Scope(read);
}

final class _Scope extends Fake implements ConversationQueryScope {
  _Scope(this.read);
  final ChatContentRead read;
  @override
  bool get isActive => true;
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) => read(reference, range);
  @override
  void retire() {}
  @override
  Future<CloseReport> close({DateTime? deadline}) async => CloseReport();
}

void main() {
  for (final markdown in [false, true]) {
    for (final deferred in [false, true]) {
      testWidgets(
        'Main ${deferred ? 'Body 引用' : 'inline'} ${markdown ? 'Markdown' : '普通文字'}直接显示、换行并实际选择复制',
        (tester) async {
          final prose = '中文长行可以按照可用宽度自然换行，保持全部内容。' * 75;
          const code = 'void example() {\n  print("保留缩进");\n}';
          final text = markdown
              ? '# 正文标题\n\n**粗体内容**\n\n- 列表项目\n\n'
                    '| 项目 | 内容 |\n| --- | --- |\n| 正文 | 可复制 |\n\n'
                    '```dart\n$code\n```\n\n$prose'
              : '    原文缩进\n\n$prose\n末尾文字  \n';
          expect(utf8.encode(text).length, greaterThan(4096));
          final controls = _Controls(_atom(text, deferred: deferred));
          addTearDown(controls.dispose);
          var reads = 0;
          await tester.binding.setSurfaceSize(const Size(480, 720));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _app(
              _main(controls, (reference, range) async {
                reads++;
                expect(reference.target, isA<BodyContentTarget>());
                expect(range.offset, 0);
                expect(range.maxBytes, 64 * 1024);
                return _window(text);
              }),
            ),
          );
          await tester.pumpAndSettle();
          expect(reads, deferred ? 1 : 0);
          expect(find.byType(ExpansionTile), findsNothing);
          expect(find.textContaining('字节 '), findsNothing);
          expect(find.text('复制当前段'), findsNothing);
          expect(find.byType(TimelineMarkdown), findsOneWidget);
          expect(
            tester.widget<TimelineMarkdown>(find.byType(TimelineMarkdown)).text,
            text,
          );
          expect(
            find.byType(GptMarkdown),
            markdown ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(TimelinePlainText),
            markdown ? findsNothing : findsOneWidget,
          );
          final wideHeight = tester
              .getSize(find.byType(TimelineMarkdown))
              .height;
          await tester.binding.setSurfaceSize(const Size(240, 720));
          await tester.pumpAndSettle();
          expect(
            tester.getSize(find.byType(TimelineMarkdown)).height,
            greaterThan(wideHeight),
          );
          final copied = await _copySelection(tester);
          if (markdown) {
            expect(copied, contains('正文标题'));
            expect(copied, contains('粗体内容'));
            expect(copied, contains(code));
            expect(copied, contains(prose));
          } else {
            expect(copied, text);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('Main 的 typed Body 内容不依赖 payload 查看器读取正文', (tester) async {
    const text = '# 直接引用正文\n\n**无需正文加载按钮**';
    final controls = _Controls(_atom(text, includePayload: false));
    addTearDown(controls.dispose);
    var reads = 0;
    await tester.pumpWidget(
      _app(
        _main(controls, (reference, range) async {
          reads++;
          expect(reference.target, isA<BodyContentTarget>());
          expect(range.maxBytes, 64 * 1024);
          return _window(text);
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byType(GptMarkdown), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('复制当前段'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final deferred in [false, true]) {
    testWidgets('工作卡展开后成员的 ${deferred ? 'Body 引用' : 'inline'} 直接使用生产正文样式和选择区', (
      tester,
    ) async {
      const text =
          '# 成员正文\n\n**成员粗体**\n\n这段正文直接阅读。\n\n'
          '![外部图片](https://example.test/image.png)';
      var reads = 0;
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: CompletionRunView(
              id: 'work',
              presentation: CompletionRunPresentation.fromEntry(
                completionEntry('W', 1),
              ),
              initiallyExpanded: false,
              childBuilder: (_) => TimelineMemberAtom(
                atom: _atom(text, deferred: deferred),
                content: _Content((reference, range) async {
                  reads++;
                  expect(reference.target, isA<BodyContentTarget>());
                  expect(range.maxBytes, 64 * 1024);
                  return _window(text);
                }),
                isActive: () => true,
                images: images,
                readAttachment: null,
              ),
            ),
          ),
        ),
      );
      expect(reads, 0);
      await tester.tap(
        find.byKey(const ValueKey('completion-run-header:work')),
      );
      await tester.pumpAndSettle();
      expect(reads, deferred ? 1 : 0);
      expect(find.byType(GptMarkdown), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      final renderer = tester.widget<TimelineMarkdown>(
        find.byType(TimelineMarkdown),
      );
      expect(renderer.style, isNull, reason: '成员正文沿用普通正文的标准字号');
      expect(renderer.isSafeLink('javascript:alert(1)'), isFalse);
      expect(renderer.isSafeLink('https://example.test'), isTrue);
      expect(find.byType(TimelineRemoteImageConnector), findsOneWidget);
      expect(find.text('加载外部图片 · example.test'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(await _copySelection(tester), contains('成员正文'));
      expect(find.text('复制当前段'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('正文下一段替换当前窗口，保留范围导航而不累计全文', (tester) async {
    final controls = _Controls(_atom('first'));
    addTearDown(controls.dispose);
    final offsets = <int>[];
    await tester.pumpWidget(
      _app(
        _main(controls, (_, range) async {
          offsets.add(range.offset);
          expect(range.maxBytes, 64 * 1024);
          return range.offset == 0
              ? _window('first', available: 11)
              : _window('second', offset: 5);
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(offsets, [0]);
    expect(find.text('字节 0–5 / 11'), findsOneWidget);
    await tester.tap(find.text('下一段'));
    await tester.pumpAndSettle();
    expect(offsets, [0, 5]);
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('字节 5–11 / 11'), findsOneWidget);
    expect(find.text('复制当前段'), findsOneWidget);
    expect(find.text('下一段'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('原始 ItemPayload 仍按需打开并保留 Markdown 标记原文', (tester) async {
    const raw = '{"diagnostic":"**不是正文**"}';
    var reads = 0;
    await tester.pumpWidget(
      _app(
        SelectionArea(
          child: ChatItemView(
            item: ChatItemPresentation.decodePayload(
              'raw',
              const DeferredPayload(
                reference: ContentRef(
                  databaseId: 'body-database',
                  target: ItemPayloadTarget(itemId: 'raw'),
                ),
                byteLength: 100,
              ),
            ),
            contentRangeBuilder: (id, key, label, reference, witness) =>
                TimelineContentRangeConnector(
                  itemId: id,
                  contentKey: key,
                  label: label,
                  reference: reference,
                  witness: witness,
                  readContent: (_, _) async {
                    reads++;
                    return _window(raw);
                  },
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 0);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text(raw), findsOneWidget);
    expect(find.byType(GptMarkdown), findsNothing);
    expect(find.text('复制当前段'), findsOneWidget);
    expect(await _copySelection(tester), contains(raw));
  });

  testWidgets('长中文 Deferred 预览复用正文读取和 Markdown 组件', (tester) async {
    await tester.pumpWidget(timelineLongDeferredBodyPreview());
    await tester.pumpAndSettle();
    final markdown = tester.widget<TimelineMarkdown>(
      find.byType(TimelineMarkdown),
    );
    expect(utf8.encode(markdown.text).length, greaterThan(4096));
    expect(find.byType(TimelineContentRangeConnector), findsOneWidget);
    expect(find.byType(GptMarkdown), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('复制当前段'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
