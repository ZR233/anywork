import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/window_control.dart';

const _environment = 'ANYWORK_PRESENTATION_SCREENSHOTS';
final _safeFileName = RegExp(r'^[a-z0-9][a-z0-9-]*\.png$');

/// A paint-only boundary around the real integration application.
///
/// It does not provide business values, own application state or emulate a
/// native window. Captures show the official integration_test render surface.
const presentationCaptureKey = ValueKey('integration-presentation-surface');

/// Request the concept's logical viewport through the existing PID-bound native
/// window support. Never override the test view's metrics or surface size.
Future<Map<String, Object?>> configurePresentationWindow(
  WidgetTester tester,
) async {
  final view = tester.view;
  WindowResizeResult? resized;
  if (Platform.environment.containsKey(_environment)) {
    final width = (1440 * view.devicePixelRatio).round();
    final height = (1000 * view.devicePixelRatio).round();
    resized = await tester.runAsync(
      () async => resizeOwnedWindow(guiPid: pid, width: width, height: height),
    );
    expect(resized!.resized, isTrue, reason: resized.reason);
    await tester.pump(const Duration(milliseconds: 300));
    // GTK may include its native header in the client rectangle. Account for
    // that measured difference once; do not pretend the render surface resized.
    if (view.physicalSize.width.round() != width ||
        view.physicalSize.height.round() != height) {
      final applied = resized.applied!;
      resized = await tester.runAsync(
        () async => resizeOwnedWindow(
          guiPid: pid,
          width: applied.width + width - view.physicalSize.width.round(),
          height: applied.height + height - view.physicalSize.height.round(),
        ),
      );
      expect(resized!.resized, isTrue, reason: resized.reason);
    }
    final deadline = Stopwatch()..start();
    while ((view.physicalSize.width / view.devicePixelRatio - 1440).abs() >=
            1 ||
        (view.physicalSize.height / view.devicePixelRatio - 1000).abs() >= 1) {
      if (deadline.elapsed > const Duration(seconds: 5)) {
        fail(
          'Native concept viewport did not reach 1440x1000: '
          '${view.physicalSize} at ${view.devicePixelRatio}',
        );
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
  }
  return {
    'width': view.physicalSize.width / view.devicePixelRatio,
    'height': view.physicalSize.height / view.devicePixelRatio,
    'devicePixelRatio': view.devicePixelRatio,
    if (resized != null) 'appliedNativeGeometry': resized.applied?.toJson(),
  };
}

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
