import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _environment = 'ANYWORK_PRESENTATION_SCREENSHOTS';
final _safeFileName = RegExp(r'^[a-z0-9][a-z0-9-]*\.png$');

/// A paint-only boundary around the real integration application.
///
/// It does not provide business values, own application state or emulate a
/// native window. Captures show the official integration_test render surface.
const presentationCaptureKey = ValueKey('integration-presentation-surface');

Future<void> capturePresentation(WidgetTester tester, String fileName) async {
  final directory = Platform.environment[_environment];
  if (directory == null || directory.isEmpty) return;
  if (!Platform.isLinux) {
    throw UnsupportedError(
      '$_environment presentation capture is supported only on Linux',
    );
  }
  if (!_safeFileName.hasMatch(fileName)) {
    throw ArgumentError.value(fileName, 'fileName', 'unsafe screenshot name');
  }

  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(presentationCaptureKey),
  );
  final outputPath = '$directory${Platform.pathSeparator}$fileName';
  final captured = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError(
          'presentation surface could not be encoded: $fileName',
        );
      }
      await File(outputPath).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return true;
    } finally {
      image.dispose();
    }
  });
  if (captured != true) {
    // runAsync reports exceptions to the binding and returns null. Propagate
    // that failure here, before a scenario can publish a successful report.
    final error = tester.takeException();
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    throw StateError(
      'presentation surface capture did not complete: $fileName',
    );
  }
}
