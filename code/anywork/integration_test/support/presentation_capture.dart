import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'window_control.dart';

const _environment = 'ANYWORK_PRESENTATION_SCREENSHOTS';
final _safeFileName = RegExp(r'^[a-z0-9][a-z0-9-]*\.png$');

/// A paint-only boundary around the real integration application.
///
/// It does not provide business values, own application state or emulate a
/// native window. Captures show the official integration_test render surface.
const presentationCaptureKey = ValueKey('integration-presentation-surface');

/// Requests the logical viewport through the existing PID-bound native window.
///
/// [requireNativeResize] fixes the real viewport for layout-sensitive scenarios
/// even without screenshot output. Never overrides test-view metrics or size.
Future<Map<String, Object?>> configurePresentationWindow(
  WidgetTester tester, {
  double logicalWidth = 1440,
  double logicalHeight = 1000,
  bool requireNativeResize = false,
}) async {
  if (!logicalWidth.isFinite ||
      !logicalHeight.isFinite ||
      logicalWidth <= 0 ||
      logicalHeight <= 0) {
    throw ArgumentError('Presentation viewport must be finite and positive');
  }
  final view = tester.view;
  WindowResizeResult? resized;
  final resizeRequested =
      requireNativeResize || Platform.environment.containsKey(_environment);
  if (resizeRequested) {
    final width = (logicalWidth * view.devicePixelRatio).round();
    final height = (logicalHeight * view.devicePixelRatio).round();
    ({Object error, StackTrace stackTrace})? readinessFailure;
    resized = await tester.runAsync<WindowResizeResult?>(() async {
      try {
        return await _resizePresentationWindowWhenReady(tester, width, height);
      } on Object catch (error, stackTrace) {
        // Return the failure through runAsync without replacing its original
        // stack with the call site's stack after the binding catches it.
        readinessFailure = (error: error, stackTrace: stackTrace);
        return null;
      }
    });
    final failure = readinessFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
    if (resized == null) {
      final error = tester.takeException();
      if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
      throw StateError('Native presentation readiness did not complete');
    }
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
    while ((view.physicalSize.width / view.devicePixelRatio - logicalWidth)
                .abs() >=
            1 ||
        (view.physicalSize.height / view.devicePixelRatio - logicalHeight)
                .abs() >=
            1) {
      if (deadline.elapsed > const Duration(seconds: 5)) {
        fail(
          'Native concept viewport did not reach ${logicalWidth}x$logicalHeight: '
          '${view.physicalSize} at ${view.devicePixelRatio}',
        );
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
  }
  return {
    'guiPid': pid,
    'platform': Platform.operatingSystem,
    'resizeMethod': 'PID-bound resizeOwnedWindow; no test-view metric override',
    'nativeResizeRequested': resizeRequested,
    'requestedLogicalWidth': logicalWidth,
    'requestedLogicalHeight': logicalHeight,
    'width': view.physicalSize.width / view.devicePixelRatio,
    'height': view.physicalSize.height / view.devicePixelRatio,
    'devicePixelRatio': view.devicePixelRatio,
    if (resized != null) 'appliedNativeGeometry': resized.applied?.toJson(),
  };
}

Future<WindowResizeResult> _resizePresentationWindowWhenReady(
  WidgetTester tester,
  int width,
  int height,
) async {
  final observations = <Map<String, Object?>>[];
  final elapsed = Stopwatch()..start();
  var firstFrameRasterized = false;
  Object? failure;
  StackTrace? failureStackTrace;
  try {
    // A pumped frame need not have reached the engine. GTK only shows the
    // toplevel in its first-frame callback; rasterization alone is not proof
    // that the native window is already viewable.
    await tester.binding.waitUntilFirstFrameRasterized.timeout(
      const Duration(seconds: 10),
    );
    firstFrameRasterized = true;
    // This is only a re-probe window, checked after synchronous calls return.
    // Existing X11 queries have no per-call timeout; a blocked call still relies
    // on the outer harness deadline. No async timeout can interrupt that call.
    final readiness = Stopwatch()..start();
    while (true) {
      final result = resizeOwnedWindow(
        guiPid: pid,
        width: width,
        height: height,
      );
      observations.add({
        'elapsedMs': elapsed.elapsedMilliseconds,
        'resized': result.resized,
        'windowId': result.windowId,
        'reason': result.reason,
        'original': result.original?.toJson(),
        'applied': result.applied?.toJson(),
        'diagnostics': result.diagnostics,
      });
      // The existing lookup refuses without touching any window when no unique
      // viewable PID-owned content window exists. Only those read-only refusals
      // may be observed again. Once a target is found, never replay a resize,
      // including a failed resize that may already have restored its geometry.
      if (result.resized ||
          result.windowId != null ||
          readiness.elapsed >= const Duration(seconds: 5)) {
        expect(
          result.resized,
          isTrue,
          reason: '${result.reason}\n${result.diagnostics.join('\n')}',
        );
        return result;
      }
      // Probe cadence, not a fixed delay assumed to make a hidden window ready.
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  } on Object catch (error, stackTrace) {
    failure = error;
    failureStackTrace = stackTrace;
    rethrow;
  } finally {
    final captureDirectory = Platform.environment[_environment];
    if (captureDirectory != null) {
      try {
        final directory = Directory(captureDirectory);
        await directory.create(recursive: true);
        final diagnostic = {
          'guiPid': pid,
          'firstFrameRasterized': firstFrameRasterized,
          'elapsedMs': elapsed.elapsedMilliseconds,
          'retryWindowMs': 5000,
          'deadlineScope':
              'Re-probe window checked after synchronous calls return; '
              'blocking X11 calls retain the outer harness deadline, '
              'not a per-call or strict total timeout.',
          if (failure != null) 'failure': '$failure',
          if (failureStackTrace != null)
            'failureStackTrace': '$failureStackTrace',
          'observations': observations,
        };
        await File(
          '${directory.path}${Platform.pathSeparator}window-readiness-$pid-${width}x$height.json',
        ).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(diagnostic)}\n',
          flush: true,
        );
      } on Object catch (diagnosticError, diagnosticStackTrace) {
        if (failure != null) {
          Error.throwWithStackTrace(
            _PresentationReadinessAndDiagnosticFailure(
              primaryError: failure,
              primaryStackTrace: failureStackTrace!,
              diagnosticError: diagnosticError,
              diagnosticStackTrace: diagnosticStackTrace,
            ),
            failureStackTrace,
          );
        }
        rethrow;
      }
    }
  }
}

final class _PresentationReadinessAndDiagnosticFailure implements Exception {
  const _PresentationReadinessAndDiagnosticFailure({
    required this.primaryError,
    required this.primaryStackTrace,
    required this.diagnosticError,
    required this.diagnosticStackTrace,
  });

  final Object primaryError;
  final StackTrace primaryStackTrace;
  final Object diagnosticError;
  final StackTrace diagnosticStackTrace;

  @override
  String toString() =>
      'Native presentation readiness failed: $primaryError\n'
      '$primaryStackTrace\n'
      'Readiness diagnostic persistence also failed: $diagnosticError\n'
      '$diagnosticStackTrace';
}

Future<void> capturePresentation(WidgetTester tester, String fileName) async {
  final directory = Platform.environment[_environment];
  if (directory == null || directory.isEmpty) return;
  if (!Platform.isLinux && !Platform.isWindows) {
    throw UnsupportedError(
      '$_environment presentation capture requires Linux or Windows',
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
