import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_graph.dart';
import '../app/studio_host_lifecycle.dart';
import 'capture_protocol.dart';
import 'flutter_content_capture.dart';

bool _registered = false;
Future<FlutterContentCaptureResult>? _inFlight;

/// Debug/profile VM service extensions. Never registered in release.
///
/// `requestExit` is available in every debug/profile host so native-fault
/// assemblies can close without enabling capture. PNG capture stays gated on
/// `ANYWORK_CAPTURE`.
void maybeRegisterCaptureExtension() {
  if (kReleaseMode || _registered) return;
  developer.registerExtension(kRequestExitExtensionName, _handleRequestExit);
  if (const bool.fromEnvironment('ANYWORK_CAPTURE')) {
    developer.registerExtension(kCaptureExtensionName, _handleCapture);
    developer.registerExtension(
      kTimelineLayoutExtensionName,
      _handleTimelineLayout,
    );
  }
  _registered = true;
}

Future<developer.ServiceExtensionResponse> _handleTimelineLayout(
  String _,
  Map<String, String> parameters,
) async {
  if (parameters.keys.any((key) => key != 'isolateId')) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.invalidParams,
      'The timeline layout observation accepts no arguments',
    );
  }
  try {
    final context = flutterContentCaptureKey.currentContext;
    final snapshot = context == null || !context.mounted
        ? null
        : ProviderScope.containerOf(
            context,
            listen: false,
          ).read(appGraphProvider).timeline.visibleLayoutSnapshot;
    final layout = snapshot?.firstContentLayout;
    if (snapshot != null &&
        layout != null &&
        (layout.selectionId != snapshot.selectionId ||
            layout.generation != snapshot.generation)) {
      throw StateError('The content layout belongs to another selection');
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'schemaVersion': 1,
        'buildMode': kProfileMode ? 'profile' : 'debug',
        'status': snapshot == null
            ? 'unavailable'
            : layout == null
            ? 'pending'
            : 'observed',
        'threadId': snapshot?.threadId,
        'selectionId': snapshot?.selectionId,
        'generation': snapshot?.generation,
        'firstContentLayout': layout == null
            ? null
            : {
                'selectionId': layout.selectionId,
                'generation': layout.generation,
                'itemId': layout.itemId,
                'selectionStartedMicros': layout.selectionStartedMicros,
                'layoutCompletedMicros': layout.layoutCompletedMicros,
                'elapsedMicros': layout.elapsedMicros,
              },
      }),
    );
  } catch (error) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      error.toString(),
    );
  }
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
