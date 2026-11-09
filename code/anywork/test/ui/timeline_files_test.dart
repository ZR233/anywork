import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/file_reading_panel.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_file_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/views/markdown_document_body.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_detail_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_attachments_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_image_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';

Map<String, Object?> readyFile(String id, String name, String origin) => {
  'status': 'ready',
  'filename': name,
  'modality': 'file',
  'resource': {
    'id': id,
    'contentDigest': 'sha256:${'0' * 64}',
    'byteLen': 8,
    'mediaType': 'text/markdown',
  },
  'origin': {
    'kind': origin,
    if (origin == 'local') 'path': '/workspace/$name',
    if (origin == 'remote') 'path': '/never-a-local-path/$name',
  },
};

String artifacts(List<Map<String, Object?>> files, {int version = 1}) =>
    jsonEncode([
      {
        'kind': 'opaque',
        'payload': {
          'format': 'pl.tool.files',
          'version': version,
          'content': jsonEncode({'caption': '交付文件', 'files': files}),
        },
      },
    ]);

ChatItemPresentation fileItem(String receipts, {ContentRef? reference}) =>
    ChatItemPresentation.decode(
      chatEnvelope(
        'files-call',
        type: 'tool',
        data: {
          'invocation': {
            'toolCallId': 'files-call',
            'name': 'show_files',
            'presentationContract': 'builtin.show_files@1',
          },
          'state': {
            'kind': 'succeeded',
            'output': {'attachments': <Object?>[]},
          },
        },
        bodies: [
          inlineBody('tool.arguments', '{"files":[]}'),
          if (reference == null)
            inlineBody('tool.output-artifacts', receipts)
          else
            {
              'key': 'tool.output-artifacts',
              'byteLength': utf8.encode(receipts).length,
              'reference': {
                'databaseId': reference.databaseId,
                'target': {
                  'kind': 'body',
                  'owner': {'kind': 'item', 'itemId': 'files-call'},
                  'key': 'tool.output-artifacts',
                },
              },
            },
        ],
      ),
    );

Widget app(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: pureStudioTheme(locale: const Locale('zh')),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets(
    'late image decoder failure stays local and offers explicit retry',
    (tester) async {
      const attachment = ThreadAttachmentView(
        id: 'corrupt-image',
        modality: AttachmentModalityView.image,
        mediaType: 'image/png',
        byteSize: 3,
        filename: 'broken.png',
      );
      var retries = 0;
      await tester.pumpWidget(
        app(
          TimelineAttachmentsView(
            attachments: const [attachment],
            imageBuilder: (value) => TimelineImageView(
              itemId: 'file-call',
              attachment: value,
              isTool: true,
              active: true,
              imageIdentity: 'corrupt-image',
              bytes: Uint8List.fromList([1, 2, 3]),
              width: 1,
              height: 1,
              onRetry: () => retries++,
            ),
          ),
        ),
      );
      await pumpClientUntil(
        tester,
        () => find.text('图片解码失败，重试').evaluate().isNotEmpty,
        'image decoder failure',
      );
      await tester.tap(find.text('图片解码失败，重试'));
      expect(retries, 1);
      expect(find.text('broken.png'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'explicit opaque format preserves order, failures and source authority',
    () {
      final value = TimelineFilesPresentation.fromArtifacts(
        artifacts([
          readyFile('a', 'first.md', 'remote'),
          {
            'status': 'failed',
            'filename': 'missing.zip',
            'message': 'permission denied',
          },
          readyFile('b', 'last.MARKDOWN', 'local'),
        ]),
      );
      expect(value.files.map((file) => file.filename), [
        'first.md',
        'missing.zip',
        'last.MARKDOWN',
      ]);
      expect(value.files.first.localPath, isNull);
      expect(value.files[1].error, 'permission denied');
      expect(value.files.last.localPath, '/workspace/last.MARKDOWN');
      expect(value.files.last.isMarkdown, isTrue);
      expect(value.files.first.attachment!.id, 'a');
      expect(
        () =>
            TimelineFilesPresentation.fromArtifacts(artifacts([], version: 2)),
        throwsFormatException,
      );
      final invalid = readyFile('c', 'invalid.md', 'local');
      invalid['origin'] = {'kind': 'local', 'path': 'relative.md'};
      expect(
        () => TimelineFilesPresentation.fromArtifacts(artifacts([invalid])),
        throwsFormatException,
      );
    },
  );

  test('opaque content rejects non-string values and malformed JSON', () {
    for (final content in <Object?>[
      {'caption': '不能兼容对象封装', 'files': <Object?>[]},
      null,
      42,
      '{"files":',
    ]) {
      final text = jsonEncode([
        {
          'kind': 'opaque',
          'payload': {
            'format': 'pl.tool.files',
            'version': 1,
            'content': content,
          },
        },
      ]);
      expect(
        () => TimelineFilesPresentation.fromArtifacts(text),
        throwsFormatException,
        reason: 'content 必须是有效的 JSON 字符串，不接受其他类型：$content',
      );
    }
  });

  testWidgets(
    'file receipt renders mixed rows without generic JSON or binary reads',
    (tester) async {
      final resources = TimelineImageResources(threadId: 'thread');
      addTearDown(resources.release);
      var reads = 0;
      FileReadingRequest? opened;
      final item = fileItem(
        artifacts([
          readyFile('a', 'notes.md', 'archive'),
          {
            'status': 'failed',
            'filename': 'missing.pdf',
            'message': 'file missing',
          },
          readyFile('b', 'report.pdf', 'remote'),
        ]),
      );
      await tester.pumpWidget(
        app(
          FileReadingScope(
            onOpen: (request) => opened = request,
            child: SizedBox(
              width: 320,
              child: ChatItemView(
                item: item,
                attachmentBuilder: (value) => TimelineAttachmentsConnector(
                  item: value,
                  resources: resources,
                  readAttachment: (_) async {
                    reads++;
                    return Uint8List(0);
                  },
                  isActive: () => true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('notes.md'), findsOneWidget);
      expect(find.text('file missing'), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.textContaining('"files"'), findsNothing);
      expect(reads, 0);
      expect(
        tester.getTopLeft(find.text('report.pdf')).dy,
        greaterThan(tester.getBottomLeft(find.text('notes.md')).dy),
      );
      await tester.tap(find.byIcon(Icons.article_outlined));
      expect(opened!.filename, 'notes.md');
      expect(reads, 0, reason: 'opening emits a reading intent, not eager IO');
      expect(tester.takeException(), isNull);
    },
  );

  for (final origin in ['local', 'remote', 'archive']) {
    testWidgets('$origin menu exposes only authorized operations', (
      tester,
    ) async {
      final files = TimelineFilesPresentation.fromArtifacts(
        artifacts([readyFile('a', 'notes.md', origin)]),
      );
      var saves = 0;
      var reveals = 0;
      await tester.pumpWidget(
        app(
          TimelineAttachmentsView(
            attachments: const [],
            files: files.files,
            imageBuilder: (_) => const SizedBox(),
            onSave: (_) => saves++,
            onReveal: (_) => reveals++,
          ),
        ),
      );
      if (origin == 'remote') {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.article_outlined)),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
      } else {
        await tester.tap(find.byTooltip('文件操作'));
      }
      await tester.pumpAndSettle();
      final save = origin == 'local'
          ? '另存为'
          : origin == 'remote'
          ? '下载'
          : '保存';
      expect(find.text(save), findsOneWidget);
      expect(
        find.text('在文件管理器中显示'),
        origin == 'local' ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text(save));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(reveals, 0);
      await tester.tap(find.byTooltip('文件操作'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      expect(
        find.text(save),
        findsOneWidget,
        reason: 'the focused file menu is accessible with Shift+F10',
      );
    });
  }

  testWidgets(
    'deferred receipt failure retries locally and retired read cannot replace new file',
    (tester) async {
      final resources = TimelineImageResources(threadId: 'thread');
      addTearDown(resources.release);
      final receipt = artifacts([readyFile('a', 'old.md', 'archive')]);
      const reference = ContentRef(
        databaseId: 'db',
        target: BodyContentTarget(
          owner: ItemContentOwner(itemId: 'files-call'),
          key: 'tool.output-artifacts',
        ),
      );
      final late = Completer<ContentWindow>();
      var count = 0;
      Widget build(ChatItemPresentation item) => app(
        TimelineAttachmentsConnector(
          key: const ValueKey('same-connector'),
          item: item,
          resources: resources,
          readAttachment: (_) async => Uint8List(0),
          isActive: () => true,
          readContent: (_, range) {
            count++;
            if (count == 1) return Future.error(StateError('read denied'));
            return late.future;
          },
        ),
      );
      await tester.pumpWidget(build(fileItem(receipt, reference: reference)));
      await tester.pump();
      expect(find.textContaining('read denied'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(count, 2);
      await tester.pumpWidget(build(fileItem(receipt, reference: reference)));
      expect(count, 2, reason: '相同不可变回执的重建不重启在途读取');
      await tester.pumpWidget(
        build(fileItem(artifacts([readyFile('b', 'new.md', 'archive')]))),
      );
      late.complete(
        ContentWindow(
          offset: 0,
          bytes: utf8.encode(receipt),
          generation: 'g',
          availableThrough: utf8.encode(receipt).length,
          sealed: true,
        ),
      );
      await tester.pump();
      expect(find.text('new.md'), findsOneWidget);
      expect(find.text('old.md'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Markdown switch, retry and close isolate late results', (
    tester,
  ) async {
    final first = Completer<Uint8List>();
    var currentReads = 0;
    FileReadingRequest request(String id, Future<Uint8List> Function() read) =>
        FileReadingRequest(
          identity: id,
          filename: '$id.md',
          readBytes: read,
          isActive: () => true,
        );
    Widget panel(FileReadingRequest value) => app(
      FileReadingPanel(
        key: const ValueKey('panel'),
        request: value,
        onClose: () {},
      ),
    );
    await tester.pumpWidget(panel(request('old', () => first.future)));
    final current = request('new', () async {
      currentReads++;
      if (currentReads == 1) throw StateError('read unavailable');
      return Uint8List.fromList(utf8.encode('# Current document'));
    });
    await tester.pumpWidget(panel(current));
    await tester.pump();
    expect(find.textContaining('read unavailable'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Current document'), findsWidgets);
    first.complete(
      Uint8List.fromList(utf8.encode('old result must not appear')),
    );
    await tester.pump();
    expect(find.textContaining('old result must not appear'), findsNothing);
    final closing = Completer<Uint8List>();
    await tester.pumpWidget(panel(request('closing', () => closing.future)));
    await tester.pumpWidget(app(const SizedBox()));
    closing.complete(Uint8List.fromList(utf8.encode('closed')));
    await tester.pump();
    expect(find.byType(FileReadingPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final plan in [false, true]) {
    testWidgets(
      '${plan ? 'Plan' : 'Markdown'} uses actual reading width and preserves copied code',
      (tester) async {
        const code =
            '  long_identifier_abcdefghijklmnopqrstuvwxyz0123456789_abcdefghijklmnopqrstuvwxyz();';
        const text = 'Before\n\n```dart\n$code\n```\n\nAfter';
        String? copied;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        Widget body() => TimelineMarkdown(
          id: 'width-test',
          text: text,
          onLink: (_) {},
          isSafeLink: (_) => false,
          imageBuilder: (_, _) => const SizedBox(),
        );
        Widget view(double width) => app(
          Center(
            child: SizedBox(
              width: width,
              child: plan
                  ? PlanDetailView(
                      identity: 'plan',
                      title: 'Plan',
                      status: PlanDetailStatus.approved,
                      onClose: () {},
                      body: body(),
                    )
                  : FileDocumentView(
                      identity: 'file',
                      filename: 'notes.md',
                      onClose: () {},
                      body: body(),
                    ),
            ),
          ),
        );
        await tester.binding.setSurfaceSize(const Size(1200, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(view(1100));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(TimelineMarkdown)).width,
          closeTo(1052, 1),
        );
        await tester.pumpWidget(view(300));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(TimelineMarkdown)).width,
          closeTo(260, 1),
        );
        expect(find.byType(MarkdownDocumentBody), findsOneWidget);
        expect(tester.takeException(), isNull);
        final selection = tester.state<SelectableRegionState>(
          find.byType(SelectableRegion),
        );
        selection.selectAll(SelectionChangedCause.keyboard);
        await tester.pump();
        selection.contextMenuButtonItems
            .firstWhere((item) => item.type == ContextMenuButtonType.copy)
            .onPressed!();
        await tester.pump();
        expect(copied, contains(code));
        expect(copied, isNot(contains('\u200b')));
      },
    );
  }
}
