import 'dart:async';

// The plugin exposes its native test transport through this internal library.
// ignore: implementation_imports
import 'package:desktop_drop/src/native_transport.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUpAll(() {
    // Production composer still mounts DesktopFileDropTarget. This override
    // stays inside test/ui so unit tests never load the plugin, and it is
    // not a package-wide flutter_test_config.
    NativeTransport.debugOverride = NativeTransport.testing()
      ..invokeHandler = (call) async {
        if (call.method != 'initialize') {
          throw StateError('Unexpected native drop operation: ${call.method}');
        }
        return {'view': (call.arguments as Map)['view'], 'generation': 1};
      };
  });
  tearDownAll(() => NativeTransport.debugOverride = null);
  await testMain();
}
