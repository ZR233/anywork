import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/platform/clipboard_image_reader.dart';
import 'package:anywork/src/platform/dropped_attachments.dart';
import 'package:anywork_client/studio_client.dart';
// Use the locked desktop_drop dependency's real dart:io implementation;
// Flutter tests do not run the native Dart plugin registrant.
// ignore: depend_on_referenced_packages
import 'package:cross_file_io/cross_file_io.dart';
// ignore: depend_on_referenced_packages
import 'package:cross_file_platform_interface/cross_file_platform_interface.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_statistics_feed.dart';

/// Only native admission responses are supplied. Platform method channels,
/// pixel decoding, staging I/O and Client input ownership are production.
final class _AttachmentTransport implements StudioTransport {
  int admissionCalls = 0;
  bool captureBytes = true;
  final paths = <String>[];
  final bytes = <Uint8List>[];
  final removed = <String>[];
  AttachmentModalityView modality = AttachmentModalityView.file;
  Completer<void>? admissionGate;
  final entered = Completer<void>();

  @override
  Future<List<AttachmentDraftView>> admitAttachmentDrafts(
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  ) async {
    admissionCalls += 1;
    final drafts = <AttachmentDraftView>[];
    for (final source in sources.cast<LocalFileAttachmentDraftSource>()) {
      final file = File(source.path);
      final contents = captureBytes ? await file.readAsBytes() : Uint8List(0);
      paths.add(file.path);
      bytes.add(contents);
      drafts.add(
        AttachmentDraftView(
          id: 'draft-${paths.length}',
          modality: modality,
          mediaType: modality == AttachmentModalityView.image
              ? 'image/png'
              : 'application/octet-stream',
          filename: file.uri.pathSegments.last,
          byteSize: contents.length,
        ),
      );
    }
    if (!entered.isCompleted) entered.complete();
    await admissionGate?.future;
    return drafts;
  }

  @override
  Future<Uint8List> readAttachmentDraft(String draftId) async =>
      bytes[int.parse(draftId.split('-').last) - 1];

  @override
  Future<bool> removeAttachmentDraft(String draftId) async {
    removed.add(draftId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused attachment test transport: ${invocation.memberName}',
  );
}

/// Only supplies provider streams; all copying, limits and cancellation remain
/// in the production platform adapter and Client input scope.
final class _ProviderPlatform extends CrossFilePlatform {
  final _io = CrossFileIO();
  final sources = <String, Stream<Uint8List> Function()>{};
  int opens = 0;

  @override
  PlatformFileSystemXFile createPlatformFileSystemXFile(
    PlatformFileSystemXFileCreationParams params,
  ) {
    final source = sources[params.path];
    if (source == null) return _io.createPlatformFileSystemXFile(params);
    return _ProviderFile(params, () {
      opens += 1;
      return source();
    });
  }
}

final class _ProviderFile extends PlatformFileSystemXFile {
  _ProviderFile(super.params, this.source) : super.implementation();
  final Stream<Uint8List> Function() source;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) => source();

  @override
  Future<int?> length() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused provider test capability: ${invocation.memberName}',
  );
}

Stream<Uint8List> _bytes(int length) async* {
  final chunk = Uint8List(1024 * 1024);
  while (length > 0) {
    final count = length < chunk.length ? length : chunk.length;
    yield Uint8List.sublistView(chunk, 0, count);
    length -= count;
  }
}

const _project = StudioProject(
  id: 'project',
  name: 'Project',
  path: '/project',
);

/// Canonical settings and the mode route. The new-thread admission resolves
/// this route before any platform I/O (main's route freeze), so a fixture
/// without configuration would never start the prepared operation.
void _seedSettings(AnyworkClient client) {
  client.settings.merge(
    SettingsStateSnapshot(
      revision: 1,
      modelCatalogRevision: 1,
      accounts: const [
        AccountSettingsView(
          id: 'account',
          name: 'Provider',
          baseUrl: 'http://local.invalid',
          defaultModelId: 'alpha',
          status: 'configured',
          usageLabel: '',
          models: [
            AccountModelView(
              modelId: 'alpha',
              displayName: 'Alpha',
              typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
              reasoningEfforts: ['medium'],
              defaultReasoningEffort: 'medium',
            ),
          ],
        ),
      ],
      modeModelRoutes: const [
        ModeModelRouteView(
          modeId: ThreadModeId.simple,
          accountId: 'account',
          modelId: 'alpha',
          effort: 'medium',
        ),
      ],
    ),
  );
}

AppGraph _graph(_AttachmentTransport transport) {
  final graph = AppGraph(
    transport: transport,
    // Statistics are an unrelated AppGraph owner; this suite never reads them.
    statisticsFeed: const TestStatisticsFeedPort(),
    clientId: 'attachment-platform',
  );
  graph.client.project.applyProjectDirectory(
    ProjectDirectoryState(values: [_project], revision: 1),
  );
  _seedSettings(graph.client);
  addTearDown(() async {
    if (transport.admissionGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    await graph.client.attachments.discardProject(_project.id);
    await graph.close(deadline: DateTime.now().add(const Duration(seconds: 5)));
    expect((await graph.client.retryCleanup()).complete, isTrue);
  });
  return graph;
}

Future<Directory> _fixtures() async {
  final directory = await Directory.systemTemp.createTemp(
    'attachment-input-test-',
  );
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousFilePlatform = CrossFilePlatform.instance;
  setUpAll(CrossFileIO.registerWith);
  tearDownAll(() => CrossFilePlatform.instance = previousFilePlatform);
  const pasteboard = MethodChannel('pasteboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(pasteboard, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('native clipboard file-list preserves original bytes without reading its pixel or text forms', () async {
    final directory = await _fixtures();
    final originalImage = await File('${directory.path}/photo.jpg')
        .writeAsBytes([0xff, 0xd8, 0, 255, 128, 42]);
    final unknownFile = await File('${directory.path}/report.unknown')
        .writeAsBytes([0, 1, 2, 255, 0]);
    final calls = <String>[];
    messenger.setMockMethodCallHandler(pasteboard, (call) async {
      calls.add(call.method);
      if (call.method == 'files') return [originalImage.path, unknownFile.path];
      throw StateError('File-list must not fall back to ${call.method}');
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      throw StateError('File-list must not fall back to Flutter Clipboard');
    });
    final transport = _AttachmentTransport();
    final graph = _graph(transport);
    await graph.client.attachments.prepareNewThread(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      prepare: (input) => input.paste(
        const SystemClipboardReader(),
        onText: (_) => fail('File-list was inserted as text'),
      ),
    );
    expect(calls, ['files']);
    expect(transport.paths, [originalImage.path, unknownFile.path]);
    expect(transport.bytes, [
      [0xff, 0xd8, 0, 255, 128, 42],
      [0, 1, 2, 255, 0],
    ]);
    expect(graph.client.attachments.state.newThread(_project.id).error, isNull);
    expect(
      graph.client.attachments.state.newThread(_project.id).attachments,
      hasLength(2),
    );
    await graph.client.attachments.discardProject(_project.id);
    expect(await originalImage.exists(), isTrue);
    expect(await unknownFile.exists(), isTrue);
  });

  test('native pixel clipboard uses owned PNG staging and Flutter text clipboard never reads paths', () async {
    final directory = await _fixtures();
    final original = await File('${directory.path}/keep.bin')
        .writeAsBytes([7, 8, 9]);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff3b82f6), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);
    final Uint8List pixels;
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      pixels = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
      picture.dispose();
    }
    final windowsPixels = await File('${directory.path}/native-pixels.png')
        .writeAsBytes(pixels);
    var hasPixels = true;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(pasteboard, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'files' => <String>[],
        'image' =>
          hasPixels ? (Platform.isWindows ? windowsPixels.path : pixels) : null,
        _ => throw StateError('Unexpected pasteboard method: ${call.method}'),
      };
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      if (call.method == 'Clipboard.getData') return {'text': original.path};
      throw StateError('Unexpected platform method: ${call.method}');
    });
    final transport = _AttachmentTransport()
      ..modality = AttachmentModalityView.image;
    final graph = _graph(transport);
    Future<void> paste() => graph.client.attachments.prepareNewThread(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      prepare: (input) => input.paste(
        const SystemClipboardReader(),
        onText: (text) =>
            graph.client.startDraft.updateDraft(_project.id, text),
      ),
    );
    await paste();
    expect(calls, ['files', 'image']);
    expect(transport.bytes.single.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final attachment = graph.client.attachments.state
        .newThread(_project.id)
        .attachments
        .single;
    expect(attachment.previewBytes, transport.bytes.single);
    expect(await File(transport.paths.single).exists(), isFalse);
    hasPixels = false;
    calls.clear();
    await paste();
    expect(calls, ['files', 'image', 'Clipboard.getData']);
    expect(
      graph.client.startDraft.state.forProject(_project.id).text,
      original.path,
    );
    expect(transport.paths, hasLength(1));
    expect(await original.readAsBytes(), [7, 8, 9]);
  });

  test('typed drops retain mixed originals and transfer staging through admission and close', () async {
    final directory = await _fixtures();
    final original = await File('${directory.path}/original.dat')
        .writeAsBytes([1, 2, 3]);
    final provider = await File('${directory.path}/provider.dat')
        .writeAsBytes([4, 5, 6]);
    final empty = await File('${directory.path}/empty.dat').writeAsBytes([]);
    final gate = Completer<void>();
    final transport = _AttachmentTransport()..admissionGate = gate;
    final graph = _graph(transport);
    final dropping = graph.client.attachments.prepareNewThread(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      prepare: (input) => admitDroppedAttachments([
        DropFileItem.fromPath(original.path),
        DropFileItem(
          file: XFile.fileSystem(path: provider.path),
          name: '../../transfer.dat',
        ),
        DropFileItem(
          file: XFile.fileSystem(path: empty.path),
          name: 'empty.dat',
        ),
      ], input),
    );
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      await dropping;
    });
    await Future.any([
      transport.entered.future,
      dropping.then((_) {
        fail(
          'Drop finished before admission: ${graph.client.attachments.state.newThread(_project.id).error}',
        );
      }),
    ]);
    expect(transport.paths.first, original.path);
    final staging = File(transport.paths[1]);
    final emptyStaging = File(transport.paths[2]);
    expect(staging.uri.pathSegments.last, 'transfer.dat');
    expect(await staging.exists(), isTrue);
    expect(transport.bytes, [
      [1, 2, 3],
      [4, 5, 6],
      <int>[],
    ]);
    final report = await graph.client.close(
      deadline: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    expect(report.complete, isFalse);
    expect(
      report.unresolved.map((entry) => entry.owner),
      contains('attachments'),
    );
    expect(await staging.exists(), isTrue);
    gate.complete();
    await dropping;
    expect(await staging.exists(), isFalse);
    expect(await emptyStaging.exists(), isFalse);
    expect(await original.readAsBytes(), [1, 2, 3]);
    expect(await provider.readAsBytes(), [4, 5, 6]);
    expect(await empty.exists(), isTrue);
    expect(transport.removed, ['draft-1', 'draft-2', 'draft-3']);
    expect(
      graph.client.attachments.state.newThread(_project.id).attachments,
      isEmpty,
    );
    expect((await graph.client.retryCleanup()).complete, isTrue);
  });

  test('drop transfer budgets reject whole oversized batches before native admission and clean partial staging', () async {
    const mib = 1024 * 1024;
    final platform = _ProviderPlatform();
    final previous = CrossFilePlatform.instance;
    CrossFilePlatform.instance = platform;
    addTearDown(() => CrossFilePlatform.instance = previous);
    var sourceId = 0;
    for (final scenario in [
      'stream-size',
      'mixed-total',
      'count',
      'local-size',
      'mixed-boundary',
      'count-boundary',
    ]) {
      final directory = await _fixtures();
      final local = File('${directory.path}/original.bin');
      final snapshots = <List<int>>[];
      DropFileItem provider(int size) {
        final id = 'provider-${sourceId++}';
        platform.sources[id] = () async* {
          try {
            yield* _bytes(size);
          } finally {
            // Source EOF/cancellation runs before adapter-owned cleanup. This
            // catches a check-after-writing implementation, not only whether
            // the final oversized batch was eventually rejected.
            final sizes = <int>[];
            await for (final entry in directory.list(recursive: true)) {
              if (entry is File && entry.path != local.path) {
                sizes.add(await entry.length());
              }
            }
            snapshots.add(sizes);
          }
        };
        return DropFileItem(
          file: XFile.fileSystem(path: id),
          name: '$id.bin',
        );
      }

      final output = await local.open(mode: FileMode.write);
      try {
        await output.truncate(switch (scenario) {
          'local-size' => 50 * mib + 1,
          'mixed-total' || 'mixed-boundary' => 50 * mib,
          _ => 0,
        });
      } finally {
        await output.close();
      }
      final items = switch (scenario) {
        'count' => [
          for (var index = 0; index < 32; index++)
            DropFileItem.fromPath(local.path),
          provider(0),
        ],
        'stream-size' => [provider(50 * mib + 1)],
        'local-size' => [DropFileItem.fromPath(local.path), provider(0)],
        'mixed-boundary' => [
          DropFileItem.fromPath(local.path),
          provider(50 * mib),
          provider(28 * mib),
        ],
        'count-boundary' => [
          for (var index = 0; index < 32; index++)
            DropFileItem.fromPath(local.path),
        ],
        _ => [
          DropFileItem.fromPath(local.path),
          provider(40 * mib),
          provider(39 * mib),
        ],
      };
      final transport = _AttachmentTransport()..captureBytes = false;
      final graph = _graph(transport);
      final opensBefore = platform.opens;
      await IOOverrides.runZoned(
        () => graph.client.attachments.prepareNewThread(
          projectId: _project.id,
          mode: ThreadModeId.simple,
          prepare: (input) => admitDroppedAttachments(items, input),
        ),
        getSystemTempDirectory: () => directory,
      );
      final accepted =
          scenario == 'mixed-boundary' || scenario == 'count-boundary';
      expect(transport.admissionCalls, accepted ? 1 : 0, reason: scenario);
      expect(
        graph.client.attachments.state.newThread(_project.id).attachments,
        hasLength(accepted ? items.length : 0),
        reason: scenario,
      );
      expect(
        graph.client.attachments.state.newThread(_project.id).error,
        accepted ? isNull : isNotNull,
        reason: scenario,
      );
      final borrowedBytes = await local.length();
      for (final sizes in snapshots) {
        expect(
          sizes,
          everyElement(lessThanOrEqualTo(50 * mib)),
          reason: scenario,
        );
        expect(
          sizes.fold<int>(borrowedBytes, (sum, bytes) => sum + bytes),
          lessThanOrEqualTo(128 * mib),
          reason: scenario,
        );
      }
      if (scenario == 'count' || scenario == 'local-size') {
        expect(
          platform.opens,
          opensBefore,
          reason: 'Preflight must precede provider I/O',
        );
      }
      expect(
        await directory.list().where((entry) => entry is Directory).toList(),
        isEmpty,
        reason: scenario,
      );
      expect(await local.exists(), isTrue, reason: scenario);
      await graph.client.attachments.discardProject(_project.id);
      expect(
        graph.client.budget.used(ResourceKind.attachment),
        0,
        reason: scenario,
      );
    }
  });

  test('discard and close cancel a suspended transfer without another chunk and join its cleanup ACK', () async {
    for (final retire in ['discard', 'close']) {
      final directory = await _fixtures();
      final nextRequested = Completer<void>();
      final cancelled = Completer<void>();
      final cancelAck = Completer<void>();
      late final StreamController<Uint8List> source;
      var resumes = 0;
      source = StreamController<Uint8List>(
        sync: true,
        onListen: () => source.add(Uint8List.fromList([1, 2, 3])),
        onResume: () {
          resumes += 1;
          if (!nextRequested.isCompleted) nextRequested.complete();
        },
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
          return cancelAck.future;
        },
      );
      final platform = _ProviderPlatform()
        ..sources['suspended'] = () => source.stream;
      final previous = CrossFilePlatform.instance;
      CrossFilePlatform.instance = platform;
      addTearDown(() => CrossFilePlatform.instance = previous);
      final transport = _AttachmentTransport();
      final graph = _graph(transport);
      var completed = false;
      final dropping = IOOverrides.runZoned(
        () => graph.client.attachments.prepareNewThread(
          projectId: _project.id,
          mode: ThreadModeId.simple,
          prepare: (input) => admitDroppedAttachments([
            DropFileItem(
              file: XFile.fileSystem(path: 'suspended'),
              name: 'partial.bin',
            ),
          ], input),
        ),
        getSystemTempDirectory: () => directory,
      ).then((_) => completed = true);
      addTearDown(() async {
        if (!cancelAck.isCompleted) cancelAck.complete();
        await source.close();
        await dropping;
      });
      await nextRequested.future;
      final partial =
          (await directory
                      .list(recursive: true)
                      .where((entry) => entry is File)
                      .toList())
                  .single
              as File;
      expect(await partial.length(), 3);
      final before = resumes;
      if (retire == 'discard') {
        await graph.client.attachments.discardProject(_project.id);
      } else {
        final report = await graph.client.close(
          deadline: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
        expect(report.complete, isFalse);
      }
      // The real stat request also yields through the I/O event queue, after
      // cancellation microtasks. No timer and no next source chunk is released.
      expect(await partial.length(), 3);
      expect(cancelled.isCompleted, isTrue, reason: retire);
      expect(completed, isFalse, reason: 'Provider cleanup has not ACKed');
      expect(
        resumes,
        before,
        reason: 'No further stream reads after retirement',
      );
      expect(transport.admissionCalls, 0);
      expect(graph.client.budget.used(ResourceKind.attachment), 1);
      cancelAck.complete();
      await dropping;
      expect(await partial.exists(), isFalse);
      expect(await directory.list().toList(), isEmpty);
      expect(graph.client.budget.used(ResourceKind.attachment), 0);
      expect(
        graph.client.attachments.state.newThread(_project.id).attachments,
        isEmpty,
      );
      if (retire == 'close') {
        expect((await graph.client.retryCleanup()).complete, isTrue);
      }
    }
  });
}
