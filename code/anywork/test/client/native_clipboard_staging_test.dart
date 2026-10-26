import 'dart:io';
import 'dart:typed_data';

import 'package:anywork/src/app/composition/native_clipboard_staging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clipboard directory deletion failure propagates through cleanup and retains the original lease for retry', () async {
    final directory = await Directory.systemTemp.createTemp(
      'clipboard-cleanup-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final failure = FileSystemException(
      'The original directory deletion failed.',
      directory.path,
    );
    final controlled = _ControlledDirectory(directory, failure);
    final staging = NativeClipboardStaging();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final path = (await IOOverrides.runZoned(
      () => staging.stage(bytes),
      getSystemTempDirectory: () => controlled,
    ))!;
    expect(await File(path).readAsBytes(), bytes);

    await expectLater(staging.cleanup(path), throwsA(same(failure)));
    expect(controlled.deletions, 1);
    expect(await File(path).exists(), isTrue);

    controlled.failDelete = false;
    await staging.cleanup(path);
    expect(
      controlled.deletions,
      2,
      reason: 'Failed cleanup must keep the original staging lease, not report Clean or restage the image.',
    );
    expect(await File(path).exists(), isFalse);
  });
}

/// Only the OS deletion result is scripted. File writing, platform staging and
/// the composition lease/cleanup path all run their production implementations.
final class _ControlledDirectory implements Directory {
  _ControlledDirectory(this.directory, this.failure);
  final Directory directory;
  final FileSystemException failure;
  bool failDelete = true;
  int deletions = 0;

  @override
  String get path => directory.path;

  @override
  Future<Directory> createTemp([String? prefix]) async => this;

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    deletions++;
    if (failDelete) throw failure;
    return directory.delete(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted directory operation: ${invocation.memberName}',
  );
}
