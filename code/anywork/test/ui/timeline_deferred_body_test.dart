import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/previews/timeline_component_previews.dart';
import 'package:anywork/src/features/conversation/timeline/previews/timeline_preview_fixtures.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/content_reference_identity.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_ui_controllers.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_attachments_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_plain_text.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/external_url_launcher.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../support/display_fixtures.dart';

const _bodyRef = ContentRef(
  databaseId: 'body-database',
  target: BodyContentTarget(
    owner: ItemContentOwner(itemId: 'body-item'),
    key: 'body',
  ),
);
const _secret = 'RAW_REQUEST_SECRET_MARKER';
const _retainedRef = ContentRef(
  databaseId: 'body-database',
  target: BodyContentTarget(
    owner: ItemContentOwner(itemId: 'body-item'),
    key: 'accepted.payload',
  ),
);

ChatAtom _atom(
  String text, {
  String id = 'body-item',
  String? completionItemId,
  bool deferred = true,
  bool includePayload = true,
  bool input = false,
  bool outerDeferred = false,
  List<ChatAtomContent>? contents,
  ChatAtomKind? kind,
  PayloadData? payloadOverride,
}) => ChatAtom(
  id: id,
  completionItemId: completionItemId,
  source: input
      ? const InputChatSource(inputId: 'user-input')
      : const ForegroundTurnChatSource(turnId: 'turn'),
  sourceOrder: 1,
  kind: kind ?? (input ? ChatAtomKind.input : ChatAtomKind.text),
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contents:
      contents ??
      const [ChatAtomContent(role: ChatContentRole.body, reference: _bodyRef)],
  payload:
      payloadOverride ??
      (includePayload
          ? outerDeferred
                ? const DeferredPayload(
                    reference: ContentRef(
                      databaseId: 'body-database',
                      target: ItemPayloadTarget(itemId: 'body-item'),
                    ),
                    byteLength: 90000,
                  )
                : InlinePayload(
                    bytes: utf8.encode(
                      jsonEncode({
                        'contract': 'anywork.chat/1',
                        'type': 'text',
                        'data': {
                          'channel': input ? 'user' : 'final',
                          'attachments': [
                            if (input)
                              {
                                'id': 'file',
                                'modality': 'file',
                                'mediaType': 'text/plain',
                                'filename': 'public-file.txt',
                                'byteSize': 12,
                              },
                          ],
                        },
                        'bodies': [
                          {
                            'key': 'body',
                            'byteLength': utf8.encode(text).length,
                            if (deferred)
                              'reference': {
                                'databaseId': 'body-database',
                                'target': {
                                  'kind': 'body',
                                  'owner': {
                                    'kind': 'item',
                                    'itemId': 'body-item',
                                  },
                                  'key': 'body',
                                },
                              }
                            else
                              'inline': utf8.encode(text),
                          },
                          if (input)
                            {
                              'key': 'accepted.payload',
                              'byteLength': _secret.length,
                              'inline': utf8.encode(_secret),
                            },
                        ],
                      }),
                    ),
                  )
          : null),
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
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

final class _Controls implements TimelineUiControllers {
  _Controls(ChatAtom? atom, {String? displayId})
    : controller = InMemoryChatController(
        messages: [
          if (atom != null)
            Message.custom(
              id: displayId ?? atom.id,
              authorId: atom.source is InputChatSource ? 'user' : 'assistant',
              metadata: {
                chatItemPresentationKey: ChatItemPresentation.forUnit(
                  TimelineDisplayUnit(
                    block: DisplayBlock(
                      id: displayId ?? atom.id,
                      historyPos: 1,
                      body: SingleDisplayBlock(
                        record: DisplayRecord(
                          atom: atom,
                          contentSource: CompletedOriginal(
                            completionId: atom.completionItemId ?? atom.id,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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

Widget _main(
  _Controls controls,
  ChatContentRead read, {
  List<ComposerSubmission> submissions = const [],
}) => TimelineView(
  threadId: 'thread',
  controls: controls,
  submissions: submissions,
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
  isSafeLink: (url) => safeExternalWebUrl(url) != null,
  remoteImageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
  attachmentBuilder: (item) => SelectionContainer.disabled(
    child: TimelineAttachmentsView(
      attachments: item.attachments,
      imageBuilder: (_) => throw StateError('此场景只有文件附件'),
    ),
  ),
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

Widget _submissionBody(String id, String text) => TimelineMarkdown(
  id: id,
  text: text,
  onLink: (_) => throw StateError('测试未请求打开外链'),
  isSafeLink: (url) => safeExternalWebUrl(url) != null,
  imageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
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
  for (final standalone in [false, true]) {
    for (final phase in ComposerSubmissionPhase.values) {
      testWidgets(
        '用户长输入 ${standalone ? '独立' : 'Main'} 回显 $phase 选择复制、附件和窄宽换行',
        (tester) async {
          final prose = '中文长输入按照可用宽度完整换行，原始文本不截断。' * 100;
          final text = '# 冻结标题\n\n**中文强调**\n\n- 列表项目\n\n$prose';
          expect(utf8.encode(text).length, greaterThan(4096));
          final submission = ComposerSubmission(
            inputId: 'pending',
            text: text,
            attachments: const [
              AttachmentDraftView(
                id: 'file',
                modality: AttachmentModalityView.file,
                mediaType: 'text/plain',
                filename: 'echo-file.txt',
                byteSize: 12,
              ),
            ],
            phase: phase,
          );
          final controls = _Controls(null);
          addTearDown(controls.dispose);
          await tester.binding.setSurfaceSize(const Size(480, 720));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _app(
              standalone
                  ? SingleChildScrollView(
                      child: ComposerSubmissionList(
                        submissions: [submission],
                        bodyBuilder: _submissionBody,
                      ),
                    )
                  : _main(
                      controls,
                      (_, _) async => throw StateError('回显不应读取历史'),
                      submissions: [submission],
                    ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SelectionArea), findsOneWidget);
          expect(find.byType(GptMarkdown), findsOneWidget);
          expect(find.text('echo-file.txt'), findsOneWidget);
          final status = switch (phase) {
            ComposerSubmissionPhase.sending => '正在发送',
            ComposerSubmissionPhase.accepted => '已收到，等待同步',
            ComposerSubmissionPhase.unknownOutcome => '发送结果待确认',
          };
          expect(find.text(status), findsOneWidget);
          final wideHeight = tester
              .getSize(find.byType(TimelineMarkdown))
              .height;
          await tester.binding.setSurfaceSize(const Size(260, 720));
          await tester.pumpAndSettle();
          expect(
            tester.getSize(find.byType(TimelineMarkdown)).height,
            greaterThan(wideHeight),
          );
          final copied = await _copySelection(tester);
          expect(copied, contains('冻结标题'));
          expect(copied, contains('中文强调'));
          expect(copied, contains('列表项目'));
          expect(copied, contains(prose));
          expect(copied, isNot(contains(status)));
          expect(copied, isNot(contains('echo-file.txt')));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
    testWidgets('用户 ${standalone ? '独立' : 'Main'} 回显纯文本完整复制并拒绝危险链接、图片等待显式加载', (
      tester,
    ) async {
      final controls = _Controls(null);
      addTearDown(controls.dispose);
      Widget surface(String text) {
        final submissions = [
          ComposerSubmission(
            inputId: 'safe',
            text: text,
            attachments: const [],
            phase: ComposerSubmissionPhase.sending,
          ),
        ];
        return _app(
          standalone
              ? SingleChildScrollView(
                  child: ComposerSubmissionList(
                    submissions: submissions,
                    bodyBuilder: _submissionBody,
                  ),
                )
              : _main(
                  controls,
                  (_, _) async => throw StateError('不读取'),
                  submissions: submissions,
                ),
        );
      }

      const plain = '    原始缩进\n\n中文纯文本  \n';
      await tester.pumpWidget(surface(plain));
      await tester.pumpAndSettle();
      expect(find.byType(TimelinePlainText), findsOneWidget);
      expect(await _copySelection(tester), plain);
      await tester.pumpWidget(
        surface(
          '[危险链接](javascript:alert(1))\n\n![外部图片](https://example.test/picture.png)',
        ),
      );
      await tester.pumpAndSettle();
      bool interactive(InlineSpan span) =>
          span is TextSpan &&
          (span.recognizer != null ||
              (span.children?.any(interactive) ?? false));
      for (final rich in tester.widgetList<RichText>(
        find.descendant(
          of: find.byType(TimelineMarkdown),
          matching: find.byType(RichText),
        ),
      )) {
        expect(interactive(rich.text), isFalse);
      }
      await tester.tap(find.text('危险链接', findRichText: true));
      expect(find.text('加载外部图片 · example.test'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final transport in ['Inline', 'BodyRef', 'outerDeferred']) {
    testWidgets('用户 Input $transport 公开正文与附件不公开保全域', (tester) async {
      final prose = '中文用户消息完整展示并支持选择复制。' * 110;
      final text = '# 用户标题\n\n**用户强调**\n\n$prose';
      expect(utf8.encode(text).length, greaterThan(4096));
      final controls = _Controls(
        _atom(
          text,
          input: true,
          deferred: transport != 'Inline',
          outerDeferred: transport == 'outerDeferred',
          contents: const [
            ChatAtomContent(role: ChatContentRole.body, reference: _bodyRef),
            ChatAtomContent(
              role: ChatContentRole.toolArguments,
              reference: _retainedRef,
            ),
          ],
        ),
      );
      addTearDown(controls.dispose);
      await tester.binding.setSurfaceSize(const Size(480, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var reads = 0;
      await tester.pumpWidget(
        _app(
          _main(controls, (reference, range) async {
            reads++;
            expect(
              contentReferenceIdentity(reference),
              contentReferenceIdentity(_bodyRef),
            );
            expect(range.maxBytes, 64 * 1024);
            return _window(text);
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, transport == 'Inline' ? 0 : 1);
      final wideHeight = tester.getSize(find.byType(TimelineMarkdown)).height;
      await tester.binding.setSurfaceSize(const Size(260, 720));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(TimelineMarkdown)).height,
        greaterThan(wideHeight),
      );
      final copied = await _copySelection(tester);
      expect(copied, contains('用户标题'));
      expect(copied, contains(prose));
      expect(copied, isNot(contains(_secret)));
      expect(find.textContaining(_secret), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(
        find.text('public-file.txt'),
        transport == 'outerDeferred' ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('用户 Input outer Deferred 超过 64KiB 下一段替换并隔离原始请求', (tester) async {
    final first = '甲' * (64 * 1024 ~/ 3);
    const second = '第二段用户正文';
    final controls = _Controls(_atom(first, input: true, outerDeferred: true));
    addTearDown(controls.dispose);
    final offsets = <int>[];
    final firstLength = utf8.encode(first).length;
    final total = firstLength + utf8.encode(second).length;
    await tester.pumpWidget(
      _app(
        _main(controls, (reference, range) async {
          expect(reference, same(_bodyRef));
          expect(range.maxBytes, 64 * 1024);
          offsets.add(range.offset);
          return range.offset == 0
              ? _window(first, available: total)
              : _window(second, offset: firstLength, available: total);
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(await _copySelection(tester), contains(first));
    await tester.ensureVisible(find.text('下一段'));
    await tester.tap(find.text('下一段'));
    await tester.pumpAndSettle();
    expect(offsets, [0, firstLength]);
    expect(find.text(first), findsNothing);
    expect(find.text(second), findsOneWidget);
    final copied = await _copySelection(tester);
    expect(copied, contains(second));
    expect(copied, isNot(contains(first)));
    expect(copied, isNot(contains(_secret)));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('用户 Input outer Deferred owner 使用完成项身份而非展示身份', (tester) async {
    const text = '# 正确归属\n\n完成项与展示身份不同仍能读取正文。';
    final controls = _Controls(
      _atom(
        text,
        id: 'display-atom',
        completionItemId: 'body-item',
        input: true,
        outerDeferred: true,
      ),
      displayId: 'display-card',
    );
    addTearDown(controls.dispose);
    var reads = 0;
    await tester.pumpWidget(
      _app(
        _main(controls, (reference, range) async {
          reads++;
          expect(reference, _bodyRef);
          expect(range.maxBytes, 64 * 1024);
          return _window(text);
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(GptMarkdown), findsOneWidget);
    expect(
      tester.widget<TimelineMarkdown>(find.byType(TimelineMarkdown)).text,
      text,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  final lazyCases = <String, ChatAtom>{
    '缺正文声明': _atom('', input: true, outerDeferred: true, contents: const []),
    '保全域冒充正文': _atom(
      '',
      input: true,
      outerDeferred: true,
      contents: const [
        ChatAtomContent(role: ChatContentRole.body, reference: _retainedRef),
      ],
    ),
    '角色不是正文': _atom(
      '',
      input: true,
      outerDeferred: true,
      contents: const [
        ChatAtomContent(
          role: ChatContentRole.toolArguments,
          reference: _bodyRef,
        ),
      ],
    ),
    '目标不是Body': _atom(
      '',
      input: true,
      outerDeferred: true,
      contents: const [
        ChatAtomContent(
          role: ChatContentRole.body,
          reference: ContentRef(
            databaseId: 'body-database',
            target: ItemPayloadTarget(itemId: 'body-item'),
          ),
        ),
      ],
    ),
    '其他完成项owner': _atom(
      '',
      input: true,
      outerDeferred: true,
      contents: const [
        ChatAtomContent(
          role: ChatContentRole.body,
          reference: ContentRef(
            databaseId: 'body-database',
            target: BodyContentTarget(
              owner: ItemContentOwner(itemId: 'other-item'),
              key: 'body',
            ),
          ),
        ),
      ],
    ),
    'CurrentContentOwner冒充owner': _atom(
      '',
      input: true,
      outerDeferred: true,
      contents: const [
        ChatAtomContent(
          role: ChatContentRole.body,
          reference: ContentRef(
            databaseId: 'body-database',
            target: BodyContentTarget(
              owner: CurrentContentOwner(
                domain: 'test',
                id: 'body-item',
                revision: 1,
              ),
              key: 'body',
            ),
          ),
        ),
      ],
    ),
    '展示atom的owner不是完成项owner': _atom(
      '',
      id: 'display-atom',
      completionItemId: 'body-item',
      input: true,
      outerDeferred: true,
      contents: const [
        ChatAtomContent(
          role: ChatContentRole.body,
          reference: ContentRef(
            databaseId: 'body-database',
            target: BodyContentTarget(
              owner: ItemContentOwner(itemId: 'display-atom'),
              key: 'body',
            ),
          ),
        ),
      ],
    ),
    '非用户来源': _atom('', kind: ChatAtomKind.input, outerDeferred: true),
    '非Input种类': _atom(
      '',
      input: true,
      kind: ChatAtomKind.text,
      outerDeferred: true,
    ),
    '非用户generic': _atom('', outerDeferred: true),
  };
  for (final entry in lazyCases.entries) {
    testWidgets('Deferred ${entry.key} 保留原始诊断懒查看', (tester) async {
      final controls = _Controls(entry.value);
      addTearDown(controls.dispose);
      var reads = 0;
      await tester.pumpWidget(
        _app(
          _main(controls, (reference, range) async {
            reads++;
            expect(reference.target, isA<ItemPayloadTarget>());
            return _window('{"diagnostic":"**保持原文**"}');
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(find.byType(ExpansionTile), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(find.byType(GptMarkdown), findsNothing);
      expect(find.text('{"diagnostic":"**保持原文**"}'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final raw in ['{"contract":', '{"contract":"future.chat/2"}']) {
    testWidgets('用户 Input 无效信封 $raw 不推断正文', (tester) async {
      final controls = _Controls(
        _atom(
          '',
          input: true,
          payloadOverride: InlinePayload(bytes: utf8.encode(raw)),
        ),
      );
      addTearDown(controls.dispose);
      await tester.pumpWidget(
        _app(
          _main(controls, (_, _) async {
            fail('无效信封不得通过声明绕过错误');
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TimelineMarkdown), findsNothing);
      expect(
        find.text(
          raw.startsWith('{"contract":') && raw.endsWith(':')
              ? '内容格式错误'
              : '未知内容格式',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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
              summary: displaySummary(1),
              location: WorkDisplayLocation.history,
              initiallyExpanded: false,
              childBuilder: (_) => TimelineMemberAtom(
                content: _Content((reference, range) async {
                  reads++;
                  expect(reference.target, isA<BodyContentTarget>());
                  expect(range.maxBytes, 64 * 1024);
                  return _window(text);
                }),
                isActive: () => true,
                images: images,
                readAttachment: null,
                record: DisplayRecord(
                  atom: _atom(text, deferred: deferred),
                  contentSource: const CurrentAtom(),
                ),
                displayId: "fixture-current",
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

  for (final (label, preview) in [
    ('临时回显', timelineLongUserSubmissionPreview),
    ('正式外层 Deferred', timelineLongUserDeferredPreview),
  ]) {
    testWidgets('用户长输入 $label 官方预览使用实际组件并可滚动至末尾', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(GptMarkdown), findsOneWidget);
      final body = tester.widget<TimelineMarkdown>(
        find.byType(TimelineMarkdown),
      );
      expect(body.text, TimelinePreviewFixtures.longUserInput);
      expect(utf8.encode(body.text).length, greaterThan(4096));
      expect(find.byType(ExpansionTile), findsNothing);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      final copied = await _copySelection(tester);
      expect(copied, contains('末尾内容保持可读。'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
