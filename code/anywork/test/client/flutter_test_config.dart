import 'dart:async';

// The plugin exposes its native test transport through this internal library.
// ignore: implementation_imports
import 'package:desktop_drop/src/native_transport.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUpAll(() {
    // Client adapter contracts borrow the plugin's transport seam; native FFI
    // registration is exercised by the desktop manual acceptance journey.
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
