import 'package:anywork/main.dart' as application;
import 'package:flutter/foundation.dart';
import 'package:flutter_driver/driver_extension.dart';

/// Official MCP/Driver inspection of the production application in debug mode.
/// Integration tests keep their own WidgetTester binding and entrypoints.
void main() {
  if (!kDebugMode) {
    throw StateError('The inspection entrypoint requires a debug build');
  }
  enableFlutterDriverExtension();
  application.main();
}
