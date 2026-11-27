import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/timeline_file_download.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/file_reading_panel.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_file_download.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_feed_body_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_feed_projection.dart';
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
import 'package:material_ui/material_ui.dart';
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
  'origin': {'kind': origin, if (origin == 'local') 'path': '/workspace/$name'},
};

Map<String, Object?> deferredFile(String filename, int size) => {
  'status': 'deferred',
  'filename': filename,
  'target': {
    'canonicalPath': '/workspace/$filename',
    'size': size,
    'modifiedAt': null,
    'executorInstance': 'executor-instance',
    'workspaceRoot': '/workspace',
    'workspaceBinding': null,
    'hostWorkspaceAccess': true,
  },
};

Map<String, Object?> fileDisplayArtifact(List<Map<String, Object?>> files) => {
  'fileDisplay': {'caption': '交付文件', 'files': files},
};

String artifacts(List<Map<String, Object?>> files) =>
    jsonEncode([fileDisplayArtifact(files)]);

ChatItemPresentation fileItem(String receipts, {BodyRef? reference}) {
  final item = chatPresentation(
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
      if (reference == null) inlineBody('tool.output-artifacts', receipts),
    ],
  );
  return chatItemPresentationOf(
    timelineFeedMessage(
      TimelineStandaloneTool(
        id: 'files-call',
        seq: 5,
        callId: 'files-call',
        toolName: 'show_files',
        presentationContract: 'builtin.show_files@1',
        state: 'succeeded',
        summary: 'Show files',
        bodies: [?reference],
        payloadJson: item.raw!,
      ),
    ),
  )!;
}

Widget app(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: pureStudioTheme(locale: const Locale('zh')),
    locale: const Locale('zh'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

class _Download implements TimelineFileDownload {
  final written = StreamController<int>();
  final result = Completer<void>();
  final cleanup = Completer<void>();
  int pauses = 0;
  int resumes = 0;
  int stops = 0;

  @override
  Stream<int> get progress => written.stream;

  @override
  Future<void> get finished => result.future;

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> stop() {
    stops++;
    return cleanup.future;
  }

  void close() => unawaited(written.close());
}

Finder _downloadButton(String label) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == label,
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
    'direct fileDisplay receipt preserves order, failures and source authority',
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
        () => TimelineFilesPresentation.fromArtifacts('[]'),
        throwsFormatException,
      );
      expect(
        () => TimelineFilesPresentation.fromArtifacts(
          jsonEncode([
            {'fileDisplay': 'not-an-object'},
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => TimelineFilesPresentation.fromArtifacts(
          jsonEncode([
            fileDisplayArtifact([readyFile('a', 'a.md', 'archive')]),
            fileDisplayArtifact([readyFile('b', 'b.md', 'archive')]),
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => TimelineFilesPresentation.fromArtifacts(
          jsonEncode([
            {
              'kind': 'opaque',
              'payload': {
                'format': 'pl.tool.files',
                'version': 2,
                'content': jsonEncode({'caption': '旧格式', 'files': []}),
              },
            },
          ]),
        ),
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

  test('receipt accepts deferred size and HTTPS-image descriptor in original order', () {
    final entries = [
      readyFile('a', 'first.md', 'archive'),
      deferredFile('large.tar', 360),
      {
        'status': 'networkImage',
        'filename': 'image.png',
        'url': 'https://example.invalid/image.png',
      },
      {'status': 'failed', 'filename': 'missing.zip', 'message': 'denied'},
    ];
    final files = TimelineFilesPresentation.fromArtifacts(artifacts(entries))
        .files;
    expect(files.map((file) => file.filename), [
      'first.md',
      'large.tar',
      'image.png',
      'missing.zip',
    ]);
    expect(files.map((file) => file.attachment?.id), ['a', null, null, null]);
    expect(files[1].deferredSize, 360);
    expect(files[1].localPath, isNull);
    expect(files[2].networkImageUrl, 'https://example.invalid/image.png');
    expect(files[3].error, 'denied');
    expect(
      () => TimelineFilesPresentation.fromArtifacts(
        artifacts([deferredFile('invalid.tar', -1)]),
      ),
      throwsFormatException,
    );
  });

  test(
    'Rust production receipt parses all file states and deferred target fields',
    () {
      final artifacts = jsonDecode(
        File('test/fixtures/file_display_rust.json').readAsStringSync(),
      );
      final receipt = TimelineFilesPresentation.fromArtifacts(
        jsonEncode(artifacts),
      );
      expect(receipt.caption, '交付文件');
      expect(receipt.files.map((file) => file.filename), [
        'first.md',
        'download.tar',
        'image.png',
        'network-image',
      ]);

      final ready = receipt.files[0];
      expect(ready.attachment, isNotNull);
      expect(ready.attachment!.modality, AttachmentModalityView.file);
      expect(ready.origin, TimelineFileOrigin.local);
      expect(ready.localPath, startsWith('/tmp/'));

      final deferred = receipt.files[1];
      expect(deferred.deferredSize, 360);
      expect(deferred.localPath, isNull);
      final artifact =
          (artifacts as List<Object?>).single as Map<String, Object?>;
      final fileDisplay = artifact['fileDisplay'] as Map<String, Object?>;
      final entries = fileDisplay['files'] as List<Object?>;
      final deferredSource = entries[1] as Map<String, Object?>;
      final target = deferredSource['target'] as Map<String, Object?>;
      expect(deferredSource['status'], 'deferred');
      expect(deferredSource['filename'], deferred.filename);
      expect(target['canonicalPath'], startsWith('/tmp/'));
      expect(target['size'], deferred.deferredSize);
      expect(target['modifiedAt'], isA<int>());
      expect(target['executorInstance'], isA<String>());
      expect(target['workspaceRoot'], startsWith('/tmp/'));
      expect(target['workspaceBinding'], isA<String>());
      expect(target['hostWorkspaceAccess'], isA<bool>());

      expect(
        receipt.files[2].networkImageUrl,
        'https://example.invalid/image.png',
      );
      expect(
        receipt.files[3].error,
        'network image URL requires HTTPS, a host and no credentials',
      );
    },
  );

  testWidgets(
    'download picks a destination first, retains progress and waits for file commit',
    (tester) async {
      const channel = MethodChannel('io.github.zr233.anywork/file_dialogs');
      final messenger = tester.binding.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final choices = [for (var i = 0; i < 3; i++) Completer<String?>()];
      var chosen = 0;
      final name = 'long-deferred-release-archive.tar.gz';
      messenger.setMockMethodCallHandler(channel, (call) {
        expect(call.method, 'saveFile');
        expect(call.arguments, name);
        return choices[chosen++].future;
      });
      final downloads = <_Download>[];
      addTearDown(() {
        for (final download in downloads) {
          download.close();
        }
      });
      final resources = TimelineImageResources(threadId: 'thread');
      addTearDown(resources.release);
      final item = fileItem(
        artifacts([
          readyFile('a', 'first.md', 'archive'),
          {
            'status': 'failed',
            'filename': 'missing.tgz',
            'message': 'Unavailable',
          },
          deferredFile(name, 800),
        ]),
      );

      await tester.pumpWidget(
        app(
          TimelineFileDownloadScope(
            start: ({required itemId, required index, required destination}) {
              expect(
                (itemId, index, destination),
                ('call:files-call', 2, '/picked/renamed.tar.gz'),
              );
              final download = _Download();
              downloads.add(download);
              return download;
            },
            child: TimelineAttachmentsConnector(
              item: item,
              resources: resources,
              readAttachment: (_) async =>
                  throw StateError('must not read archived bytes'),
              isActive: () => true,
            ),
          ),
        ),
      );
      expect(find.byTooltip(name), findsOneWidget);
      expect(tester.widget<Text>(find.text(name)).maxLines, 1);
      expect(find.text('无内置预览'), findsNothing);

      final button = _downloadButton('下载');
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<IconButton>(button).onPressed, isNull);
      expect(downloads, isEmpty);
      choices[0].complete(null);
      await pumpClientUntil(
        tester,
        () => tester.widget<IconButton>(button).onPressed != null,
        'native chooser cancellation restores download',
      );
      expect(downloads, isEmpty);
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      choices[1].complete('/picked/renamed.tar.gz');
      await pumpClientUntil(
        tester,
        () => downloads.isNotEmpty,
        'native chooser starts transfer',
      );
      final first = downloads.single;
      first.written.add(200);
      await tester.pump();
      final progress = find.byType(CircularProgressIndicator);
      expect(tester.widget<CircularProgressIndicator>(progress).value, 0.25);
      expect(find.text('25%'), findsOneWidget);
      await tester.tap(find.byTooltip('暂停下载'));
      await tester.pump();
      expect(first.pauses, 1);
      expect(tester.widget<CircularProgressIndicator>(progress).value, 0.25);
      expect(find.text('25%'), findsOneWidget);
      await tester.tap(find.byTooltip('继续下载'));
      await tester.pump();
      expect(first.resumes, 1);
      first.written.add(800);
      await tester.pump();
      expect(tester.widget<CircularProgressIndicator>(progress).value, 1);
      expect(find.byTooltip('下载完成'), findsNothing);
      first.result.completeError(StateError('disk full'));
      await tester.pump();
      expect(find.textContaining('disk full'), findsOneWidget);

      await tester.tap(button);
      choices[2].complete('/picked/renamed.tar.gz');
      await pumpClientUntil(
        tester,
        () => downloads.length == 2,
        'native chooser starts retry',
      );
      expect(downloads, hasLength(2));
      expect(find.textContaining('disk full'), findsNothing);
      downloads.last.result.complete();
      await tester.pump();
      expect(find.byTooltip('下载完成'), findsOneWidget);
      expect(first.stops, 0);
      expect(downloads.last.stops, 0);
    },
  );

  testWidgets(
    'stop awaits cleanup and scope replacement retires choices and transfers',
    (tester) async {
      final resources = TimelineImageResources(threadId: 'thread');
      addTearDown(resources.release);
      final item = fileItem(artifacts([deferredFile('remote.zip', 600)]));
      final retired = _Download();
      final current = _Download();
      final disposed = _Download();
      final lateChoice = Completer<String?>();
      addTearDown(retired.close);
      addTearDown(current.close);
      addTearDown(disposed.close);
      var selections = 0;
      var oldStarts = 0;
      TimelineFileDownload startOld({
        required String itemId,
        required int index,
        required String destination,
      }) {
        oldStarts++;
        return retired;
      }

      var newStarts = 0;
      TimelineFileDownload startNew({
        required String itemId,
        required int index,
        required String destination,
      }) => newStarts++ == 0 ? current : disposed;

      Future<String?> pick(String _) async =>
          ++selections == 2 ? lateChoice.future : '/picked/remote.zip';
      Widget scene(TimelineFileDownloadStart start) => app(
        TimelineFileDownloadScope(
          start: start,
          pickSavePath: pick,
          child: TimelineAttachmentsConnector(
            item: item,
            resources: resources,
            readAttachment: null,
            isActive: () => true,
          ),
        ),
      );

      await tester.pumpWidget(scene(startOld));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        oldStarts,
        1,
        reason: 'the direct download button is keyboard actionable',
      );
      await tester.pumpWidget(scene(startNew));
      expect(retired.stops, 1);
      retired.result.completeError(StateError('stale transfer'));
      retired.cleanup.complete();
      await tester.pump();
      expect(find.textContaining('stale transfer'), findsNothing);

      await tester.tap(find.byTooltip('下载'));
      await tester.pump();
      await tester.pumpWidget(scene(startOld));
      lateChoice.complete('/picked/must-not-start.zip');
      await tester.pump();
      expect(oldStarts, 1);
      expect(newStarts, 0);

      await tester.pumpWidget(scene(startNew));
      await tester.tap(find.byTooltip('下载'));
      await tester.pump();
      await tester.tap(find.byTooltip('停止下载'));
      current.result.completeError(StateError('expected cancellation'));
      await tester.pump();
      expect(current.stops, 1);
      expect(find.byTooltip('下载'), findsNothing);
      expect(
        tester.widget<IconButton>(_downloadButton('停止下载')).onPressed,
        isNull,
      );
      current.cleanup.complete();
      await tester.pump();
      expect(find.textContaining('expected cancellation'), findsNothing);

      await tester.tap(find.byTooltip('下载'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(disposed.stops, 1);
      disposed.result.completeError(StateError('disposed'));
      disposed.cleanup.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'HTTPS images start loading directly and explicit image opens zoom',
    (tester) async {
      const url = 'https://example.invalid/large-photo.png';
      const badUrl = 'https://example.invalid/missing-photo.png';
      final cache = PaintingBinding.instance.imageCache;
      final frame = Completer<ImageInfo>();
      final failure = Completer<ImageInfo>();
      cache.putIfAbsent(
        const NetworkImage(url),
        () => OneFrameImageStreamCompleter(frame.future),
      );
      cache.putIfAbsent(
        const NetworkImage(badUrl),
        () => OneFrameImageStreamCompleter(failure.future),
      );
      addTearDown(() {
        cache.evict(const NetworkImage(url));
        cache.evict(const NetworkImage(badUrl));
      });
      final resources = TimelineImageResources(threadId: 'thread');
      addTearDown(resources.release);
      await tester.pumpWidget(
        app(
          Column(
            children: [
              TimelineAttachmentsConnector(
                item: fileItem(
                  artifacts([
                    {
                      'status': 'networkImage',
                      'filename': 'large-photo.png',
                      'url': url,
                    },
                    {
                      'status': 'networkImage',
                      'filename': 'unsafe.png',
                      'url': 'http://example.invalid/unsafe.png',
                    },
                  ]),
                ),
                resources: resources,
                readAttachment: null,
                isActive: () => true,
              ),
              const TimelineRemoteImageConnector(url: badUrl),
            ],
          ),
        ),
      );
      expect(find.text('正在加载图片'), findsNWidgets(2));
      expect(find.text('无法加载此外部图片。'), findsOneWidget);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const Color(0xff336677), ui.BlendMode.src);
      final drawing = recorder.endRecording();
      frame.complete(ImageInfo(image: drawing.toImageSync(20, 10)));
      drawing.dispose();
      failure.completeError(StateError('image missing'));
      await tester.pumpAndSettle();
      expect(find.text('正在加载图片'), findsNothing);
      expect(find.text('无法加载此图片。'), findsOneWidget);
      await tester.tap(find.image(const NetworkImage(url)));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
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
    });
  }

  testWidgets(
    'deferred receipt failure retries locally and retired read cannot replace new file',
    (tester) async {
      final resources = TimelineImageResources(threadId: 'thread');
      addTearDown(resources.release);
      final receipt = artifacts([readyFile('a', 'old.md', 'archive')]);
      final reference = BodyRef(
        databaseId: 'db',
        ownerEventId: 'files-call',
        bodyKey: 'tool.output-artifacts',
        bodyId: 'files-call:tool.output-artifacts',
        role: 'attachment',
        byteLength: utf8.encode(receipt).length,
      );
      final late = Completer<BodyWindow>();
      var count = 0;
      final identity = Object();
      Widget build(ChatItemPresentation item) => app(
        TimelineFeedContent(
          identity: identity,
          isActive: () => true,
          readBodyWindow:
              (actualReference, {required offset, required maxBytes}) {
                expect(actualReference, reference);
                expect(offset, 0);
                count++;
                if (count == 1) return Future.error(StateError('read denied'));
                return late.future;
              },
          child: TimelineAttachmentsConnector(
            key: const ValueKey('same-connector'),
            item: item,
            resources: resources,
            readAttachment: (_) async => Uint8List(0),
            isActive: () => true,
          ),
        ),
      );
      await tester.pumpWidget(build(fileItem(receipt, reference: reference)));
      await pumpClientUntil(
        tester,
        () => find.textContaining('read denied').evaluate().isNotEmpty,
        'deferred receipt failure',
      );
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(count, 2);
      await tester.pumpWidget(build(fileItem(receipt, reference: reference)));
      expect(count, 2, reason: '相同不可变回执的重建不重启在途读取');
      await tester.pumpWidget(
        build(fileItem(artifacts([readyFile('b', 'new.md', 'archive')]))),
      );
      late.complete(
        BodyWindow(
          offset: 0,
          text: receipt,
          totalBytes: utf8.encode(receipt).length,
          eof: true,
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
    Widget panel(FileReadingRequest value) =>
        app(FileReadingPanel(key: const ValueKey('panel'), request: value));
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
                  ? PlanDetailView(identity: 'plan', body: body())
                  : FileDocumentView(identity: 'file', body: body()),
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
