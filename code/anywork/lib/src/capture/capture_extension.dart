import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'flutter_content_capture.dart';

const String kCaptureExtensionName = 'ext.anywork.capture';

bool _registered = false;
Future<FlutterContentCaptureResult>? _inFlight;

/// Debug-only, read-only VM service extension. Never registered in release.
void maybeRegisterCaptureExtension() {
  if (_registered) return;
  developer.registerExtension(kCaptureExtensionName, _handleCapture);
  _registered = true;
}

Future<developer.ServiceExtensionResponse> _handleCapture(
  String method,
  Map<String, String> parameters,
) async {
  try {
    if (_inFlight != null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.kInvalidParams,
        'A capture is already in progress for this view',
      );
    }
    final ratio = double.tryParse(parameters['pixelRatio'] ?? '') ??
        kCaptureDefaultPixelRatio;
    final task = _captureAfterFrame(ratio);
    _inFlight = task;
    try {
      final result = await task.timeout(const Duration(seconds: 8));
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'pngBase64': base64Encode(result.png),
          'meta': result.meta.toJson(),
        }),
      );
    } on TimeoutException {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.kExtensionError,
        'Capture timed out',
      );
    } finally {
      // Keep the original task until it releases the ui.Image.
      unawaited(
        task.whenComplete(() {
          if (identical(_inFlight, task)) _inFlight = null;
        }),
      );
    }
  } catch (error) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.kExtensionError,
      error.toString(),
    );
  }
}

Future<FlutterContentCaptureResult> _captureAfterFrame(double pixelRatio) async {
  await SchedulerBinding.instance.endOfFrame;
  return captureFlutterContent(pixelRatio: pixelRatio);
}
