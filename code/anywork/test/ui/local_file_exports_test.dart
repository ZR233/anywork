import 'dart:async';
import 'dart:io';

import 'package:anywork/src/platform/local_file_dialogs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.github.zr233.anywork/file_dialogs');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('anywork-file-export-');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await temporary.delete(recursive: true);
  });

  test(
    'native cancel creates nothing and never reads archived bytes',
    () async {
      var reads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'saveFile');
        expect(call.arguments, 'original.bin');
        return null;
      });
      final saved = await saveArchivedFile(
        filename: 'original.bin',
        readBytes: () async {
          reads++;
          return Uint8List(0);
        },
        isActive: () => true,
      );
      expect(saved, isFalse);
      expect(reads, 0);
      expect(await temporary.list().toList(), isEmpty);
    },
  );

  test(
    'save writes exact original binary bytes to the user-selected destination',
    () async {
      final destination = File(p.join(temporary.path, 'chosen-name.bin'));
      final original = Uint8List.fromList([0, 255, 13, 10, 0, 128, 42]);
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'saveFile');
        expect(call.arguments, 'archived-name.bin');
        return destination.path;
      });
      expect(
        await saveArchivedFile(
          filename: 'archived-name.bin',
          readBytes: () async => original,
          isActive: () => true,
        ),
        isTrue,
      );
      expect(await destination.readAsBytes(), original);
    },
  );

  test(
    'retiring while choosing or reading prevents late file creation',
    () async {
      final destination = File(p.join(temporary.path, 'must-not-exist.bin'));
      var active = true;
      var reads = 0;
      final choice = Completer<String?>();
      messenger.setMockMethodCallHandler(channel, (_) => choice.future);
      final selecting = saveArchivedFile(
        filename: 'old.bin',
        readBytes: () async {
          reads++;
          return Uint8List(0);
        },
        isActive: () => active,
      );
      active = false;
      choice.complete(destination.path);
      expect(await selecting, isFalse);
      expect(reads, 0);
      expect(await destination.exists(), isFalse);

      active = true;
      final bytes = Completer<Uint8List>();
      final started = Completer<void>();
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => destination.path,
      );
      final reading = saveArchivedFile(
        filename: 'old.bin',
        readBytes: () {
          started.complete();
          return bytes.future;
        },
        isActive: () => active,
      );
      await started.future;
      active = false;
      bytes.complete(Uint8List.fromList([1, 2, 3]));
      expect(await reading, isFalse);
      expect(await destination.exists(), isFalse);
    },
  );

  test(
    'read failure preserves destination and can be explicitly retried',
    () async {
      final destination = File(p.join(temporary.path, 'existing.bin'));
      await destination.writeAsBytes([9, 8, 7]);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => destination.path,
      );
      await expectLater(
        saveArchivedFile(
          filename: 'archive.bin',
          readBytes: () => Future.error(StateError('archive unavailable')),
          isActive: () => true,
        ),
        throwsStateError,
      );
      expect(await destination.readAsBytes(), [9, 8, 7]);
      await saveArchivedFile(
        filename: 'archive.bin',
        readBytes: () async => Uint8List.fromList([0, 255]),
        isActive: () => true,
      );
      expect(await destination.readAsBytes(), [0, 255]);
    },
  );

  test(
    'reveal checks a real absolute local source and propagates system errors',
    () async {
      final file = File(p.join(temporary.path, 'original.txt'));
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'revealFile');
        expect(call.arguments, file.path);
        throw PlatformException(
          code: 'reveal_file_failed',
          message: 'file manager unavailable',
        );
      });
      await expectLater(
        revealLocalFile('relative.txt', isActive: () => true),
        throwsStateError,
      );
      await expectLater(
        revealLocalFile(file.path, isActive: () => true),
        throwsStateError,
      );
      expect(calls, 0);
      await file.writeAsString('original');
      await expectLater(
        revealLocalFile(file.path, isActive: () => true),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, 1);
    },
  );
}
