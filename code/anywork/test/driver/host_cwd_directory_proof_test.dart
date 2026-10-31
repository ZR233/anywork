import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/realtime_journey.dart' as journey;

Future<Directory> _createTemp(String prefix) async {
  final root = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });
  return root;
}

Matcher _throwsHostCwd(String messageFragment) => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    contains(messageFragment),
  ),
);

void main() {
  test('accepts the same real directory outside a similar-prefix workspace sibling', () async {
    final root = await _createTemp('host-cwd-proof-same-');
    final workspace = await Directory('${root.path}/ws').create();
    final cwd = await Directory('${root.path}/ws-extra').create();

    final evidence = await journey.hostCwdDirectoryProof(
      requestedPath: cwd.path,
      actualPath: cwd.path,
      workspacePath: workspace.path,
    );

    expect(evidence['requestedPath'], cwd.path);
    expect(evidence['actualPath'], cwd.path);
    expect(evidence['workspacePath'], workspace.path);
    expect(evidence['requestedCanonical'], isA<String>());
    expect(evidence['actualCanonical'], isA<String>());
    expect(evidence['workspaceCanonical'], isA<String>());
    expect(evidence['identical'], isTrue);
    expect(evidence['insideWorkspace'], isFalse);
    expect(evidence.containsKey('sameCanonical'), isFalse);
  });

  test('rejects a different directory, workspace itself or descendant, relative and missing paths', () async {
    final root = await _createTemp('host-cwd-proof-reject-');
    final workspace = await Directory('${root.path}/workspace').create();
    final cwd = await Directory('${root.path}/cwd').create();
    final other = await Directory('${root.path}/other').create();
    final nested = await Directory('${workspace.path}/nested').create();
    final missing = Directory('${root.path}/missing').path;

    await expectLater(
      journey.hostCwdDirectoryProof(
        requestedPath: cwd.path,
        actualPath: other.path,
        workspacePath: workspace.path,
      ),
      _throwsHostCwd('directory proof failed'),
    );
    await expectLater(
      journey.hostCwdDirectoryProof(
        requestedPath: workspace.path,
        actualPath: workspace.path,
        workspacePath: workspace.path,
      ),
      _throwsHostCwd('directory proof failed'),
    );
    await expectLater(
      journey.hostCwdDirectoryProof(
        requestedPath: nested.path,
        actualPath: nested.path,
        workspacePath: workspace.path,
      ),
      _throwsHostCwd('directory proof failed'),
    );
    await expectLater(
      journey.hostCwdDirectoryProof(
        requestedPath: 'relative-cwd',
        actualPath: cwd.path,
        workspacePath: workspace.path,
      ),
      _throwsHostCwd('is not absolute'),
    );
    await expectLater(
      journey.hostCwdDirectoryProof(
        requestedPath: missing,
        actualPath: cwd.path,
        workspacePath: workspace.path,
      ),
      _throwsHostCwd('does not exist'),
    );
  });

  test(
    'accepts a Windows drive-letter cwd identical to an extended path',
    () async {
      final root = await _createTemp('host-cwd-proof-win-');
      final workspace = await Directory('${root.path}/workspace').create();
      final cwd = await Directory('${root.path}/cwd').create();
      final drivePath = Directory(cwd.path).absolute.path;
      final extendedPath = '\\\\?\\$drivePath';

      expect(
        drivePath,
        matches(RegExp(r'^[A-Za-z]:[\\/]')),
        reason: 'Windows fixture requires an ordinary drive-letter absolute path, not an extended prefix',
      );
      expect(
        extendedPath,
        isNot(equals(drivePath)),
        reason: 'extended and drive-letter forms must be different representations of the same directory',
      );

      final evidence = await journey.hostCwdDirectoryProof(
        requestedPath: extendedPath,
        actualPath: drivePath,
        workspacePath: workspace.path,
      );

      expect(evidence['requestedPath'], extendedPath);
      expect(evidence['actualPath'], drivePath);
      expect(evidence['identical'], isTrue);
      expect(evidence['insideWorkspace'], isFalse);
    },
    skip: Platform.isWindows
        ? false
        : 'Windows-only drive-letter vs \\\\?\\ path identity',
  );
}
