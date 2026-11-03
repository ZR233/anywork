import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/scheduler.dart';

import '../app/studio_host_lifecycle.dart';
import 'flutter_content_capture.dart';

const String kCaptureExtensionName = 'ext.anywork.capture';
const String kRequestExitExtensionName = 'ext.anywork.requestExit';

bool _registered = false;
Future<FlutterContentCaptureResult>? _inFlight;

/// Debug-only VM service extensions. Never registered in release.
///
/// `requestExit` is available in every debug/profile host so native-fault
/// assemblies can close without enabling capture. PNG capture stays gated on
/// `ANYWORK_CAPTURE`.
void maybeRegisterCaptureExtension() {
  if (_registered) return;
  developer.registerExtension(kRequestExitExtensionName, _handleRequestExit);
  if (const bool.fromEnvironment('ANYWORK_CAPTURE')) {
    developer.registerExtension(kCaptureExtensionName, _handleCapture);
  }
  _registered = true;
}

Future<developer.ServiceExtensionResponse> _handleCapture(
  String method,
  Map<String, String> parameters,
) async {
  try {
    if (_inFlight != null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'A capture is already in progress for this view',
      );
    }
    final ratio =
        double.tryParse(parameters['pixelRatio'] ?? '') ??
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
        developer.ServiceExtensionResponse.extensionError,
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
      developer.ServiceExtensionResponse.extensionError,
      error.toString(),
    );
  }
}

Future<developer.ServiceExtensionResponse> _handleRequestExit(
  String _,
  Map<String, String> _,
) async {
  unawaited(StudioExitCoordinator.requestExit());
  return developer.ServiceExtensionResponse.result(
    jsonEncode({'acknowledged': true}),
  );
}

Future<FlutterContentCaptureResult> _captureAfterFrame(
  double pixelRatio,
) async {
  await SchedulerBinding.instance.endOfFrame;
  return captureFlutterContent(pixelRatio: pixelRatio);
}
