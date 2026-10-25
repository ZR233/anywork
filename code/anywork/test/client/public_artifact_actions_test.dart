import 'dart:async';
import 'dart:io';

import 'package:anywork/src/app/public_artifact_actions.dart';
import 'package:anywork/src/platform/local_file_dialogs.dart';
import 'package:anywork/src/platform/public_artifact_platform.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ResourceTransport extends StudioTransport {
  int reads = 0;
  final List<(String, String)> identities = [];
  Uint8List bytes = Uint8List(0);
  Object? failure;
  Completer<Uint8List>? pending;
  @override
  Future<Uint8List> readThreadAttachment(
    String threadId,
    String attachmentId,
  ) async {
    reads++;
    identities.add((threadId, attachmentId));
    if (failure case final error?) throw error;
    return pending == null ? bytes : await pending!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused ${invocation.memberName}');
}

final class _Platform implements PublicArtifactPlatform {
  String? target;
  Completer<String?>? chooser;
  final List<String> names = [];
  final List<String> opens = [];
  final List<Uint8List> writes = [];
  final enteredWrite = Completer<void>();
  Completer<void>? writeGate;
  bool opened = true;
  Object? openError;
  @override
  Future<String?> chooseSavePath(String suggestedName) async {
    names.add(suggestedName);
    return chooser == null ? target : await chooser!.future;
  }

  @override
  Future<void> writeBytes(String destination, Uint8List bytes) async {
    writes.add(Uint8List.fromList(bytes));
    if (!enteredWrite.isCompleted) enteredWrite.complete();
    await writeGate?.future;
    await const SystemPublicArtifactPlatform().writeBytes(destination, bytes);
  }

  @override
  Future<bool> openFile(String destination) async {
    opens.add(destination);
    if (openError case final error?) throw error;
    return opened;
  }
}

ThreadItemView _artifact({
  int length = 0,
  String name = '原件 无后缀',
  int revision = 4,
}) => ThreadItemView(
  id: 'canonical-artifact',
  threadId: 'thread',
  turnId: 'turn',
  ordinal: 3,
  revision: revision,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  saved: false,
  state: ThreadPublicArtifactItemStateView(
    publicationId: 'publication-is-not-resource',
    toolCallId: 'tool-call',
    displayName: name,
    resource: ThreadArtifactResource(
      id: 'exact-resource-identity',
      contentDigest: 'sha256:${'0' * 64}',
      byteLen: length,
      mediaType: 'application/x-unknown',
    ),
    publishedAt: DateTime.utc(2026),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.github.zr233.anywork/file_dialogs');

  test('save chooser rejects non-basenames before dispatch and preserves cancel/error without fallback', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    for (final invalid in ['', '.', '..', 'a/b', r'a\b', 'a\u0000b', 'a\nb']) {
      await expectLater(
        chooseLocalArtifactSavePath(invalid),
        throwsArgumentError,
      );
    }
    expect(calls, isEmpty);
    expect(await chooseLocalArtifactSavePath('报告 未知后缀'), isNull);
    expect(calls.single.method, 'chooseSavePath');
    expect(calls.single.arguments, '报告 未知后缀');
    messenger.setMockMethodCallHandler(channel, (_) async => 'relative/path');
    await expectLater(
      chooseLocalArtifactSavePath('合法'),
      throwsA(isA<PlatformException>()),
    );
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'native-error'),
    );
    await expectLater(
      chooseLocalArtifactSavePath('合法'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('cancel does not read or write; resource failure and length mismatch do not truncate old target', () async {
    final directory = await Directory.systemTemp.createTemp(
      'artifact-contract-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/用户 目标');
    await file.writeAsString('existing user bytes');
    final transport = _ResourceTransport();
    final client = AnyworkClient(transport: transport, clientId: 'artifact');
    addTearDown(client.close);
    final platform = _Platform();
    final actions = PublicArtifactActions(client: client, platform: platform);
    addTearDown(actions.close);
    final cancelled = await actions.save(
      _artifact(),
      openAfterSave: true,
      isCurrent: () => true,
    );
    expect(cancelled.outcome, PublicArtifactSaveOutcome.cancelled);
    expect(transport.reads, 0);
    expect(platform.writes, isEmpty);
    expect(platform.opens, isEmpty);
    platform.target = file.path;
    transport.failure = const StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'canonical read rejected',
      retryable: false,
      correlationId: 'test',
    );
    final failed = await actions.save(
      _artifact(),
      openAfterSave: false,
      isCurrent: () => true,
    );
    expect(failed.outcome, PublicArtifactSaveOutcome.failed);
    expect(await file.readAsString(), 'existing user bytes');
    transport.failure = null;
    transport.bytes = Uint8List.fromList([1, 2]);
    final mismatch = await actions.save(
      _artifact(length: 3),
      openAfterSave: false,
      isCurrent: () => true,
    );
    expect(mismatch.outcome, PublicArtifactSaveOutcome.failed);
    expect(platform.writes, isEmpty);
    expect(await file.readAsString(), 'existing user bytes');
  });

  test('0B and arbitrary original bytes use resource ID; saved and system-open failure stay independent', () async {
    final directory = await Directory.systemTemp.createTemp('artifact-bytes-');
    addTearDown(() => directory.delete(recursive: true));
    final transport = _ResourceTransport();
    final client = AnyworkClient(transport: transport, clientId: 'artifact');
    addTearDown(client.close);
    final platform = _Platform()..target = '${directory.path}/空 文件';
    final actions = PublicArtifactActions(client: client, platform: platform);
    addTearDown(actions.close);
    final zero = await actions.save(
      _artifact(),
      openAfterSave: false,
      isCurrent: () => true,
    );
    expect(zero.outcome, PublicArtifactSaveOutcome.saved);
    expect(await File(platform.target!).length(), 0);
    expect(transport.identities.single, ('thread', 'exact-resource-identity'));
    transport.bytes = Uint8List.fromList([0, 255, 128, 13, 10, 42]);
    platform.target = '${directory.path}/用户改名.anything';
    platform.opened = false;
    final failedOpen = await actions.save(
      _artifact(length: 6),
      openAfterSave: true,
      isCurrent: () => true,
    );
    expect(failedOpen.outcome, PublicArtifactSaveOutcome.savedNotOpened);
    expect(await File(platform.target!).readAsBytes(), transport.bytes);
    platform.openError = PlatformException(code: 'no-association');
    final exceptionOpen = await actions.save(
      _artifact(length: 6),
      openAfterSave: true,
      isCurrent: () => true,
    );
    expect(exceptionOpen.outcome, PublicArtifactSaveOutcome.savedNotOpened);
    expect(await File(platform.target!).readAsBytes(), transport.bytes);
    expect(platform.names, everyElement('原件 无后缀'));
    expect(platform.opens, everyElement(platform.target));
  });

  test('AppGraph action owner bounds duplicate clicks, joins real write and suppresses retired open/publication', () async {
    final directory = await Directory.systemTemp.createTemp('artifact-join-');
    addTearDown(() => directory.delete(recursive: true));
    final transport = _ResourceTransport()..bytes = Uint8List.fromList([3]);
    final client = AnyworkClient(transport: transport, clientId: 'artifact');
    addTearDown(client.close);
    final platform = _Platform()
      ..target = '${directory.path}/chosen'
      ..writeGate = Completer<void>();
    final actions = PublicArtifactActions(client: client, platform: platform);
    var current = true;
    final item = _artifact(length: 1);
    final key = actions.keyOf(item);
    final pending = actions.save(
      item,
      openAfterSave: true,
      isCurrent: () => current,
    );
    await platform.enteredWrite.future;
    await expectLater(
      actions.save(item, openAfterSave: false, isCurrent: () => true),
      throwsStateError,
    );
    current = false;
    var joined = false;
    final close = actions.close().then((report) {
      joined = true;
      return report;
    });
    await Future<void>.value();
    expect(joined, isFalse);
    await expectLater(
      actions.save(item, openAfterSave: false, isCurrent: () => true),
      throwsStateError,
    );
    platform.writeGate!.complete();
    expect((await pending).outcome, PublicArtifactSaveOutcome.savedNotOpened);
    expect((await close).complete, isTrue);
    expect(platform.opens, isEmpty);
    expect(await File(platform.target!).readAsBytes(), [3]);
    expect(
      actions.state[key]?.result,
      isNull,
      reason: 'retired/closed UI cannot publish a late result',
    );
    expect(client.budget.used(ResourceKind.pendingOperation), 0);
  });

  test(
    'ordinary File and user/tool attachments cannot become public save actions',
    () async {
      final client = AnyworkClient(
        transport: _ResourceTransport(),
        clientId: 'artifact',
      );
      addTearDown(client.close);
      final platform = _Platform();
      final actions = PublicArtifactActions(client: client, platform: platform);
      addTearDown(actions.close);
      final input = _artifact().copyWith(
        state: ThreadFileItemStateView(
          '/model/says/public-artifact',
          null,
          DateTime.utc(2026),
        ),
      );
      await expectLater(
        actions.save(input, openAfterSave: false, isCurrent: () => true),
        throwsArgumentError,
      );
      expect(platform.names, isEmpty);
    },
  );
}
