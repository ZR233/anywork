import 'package:anywork/main.dart' as application;
import 'package:flutter/foundation.dart';
import 'package:flutter_driver/driver_extension.dart';

/// Official Driver observation of the non-release production application.
/// Debug supports MCP inspection; profile uses Driver's ordinary UI commands.
/// Integration tests keep their own WidgetTester binding and entrypoints.
void main() {
  if (kReleaseMode) {
    throw StateError('The inspection entrypoint is unavailable in release');
  }
  enableFlutterDriverExtension();
  application.main();
}
