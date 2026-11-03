import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

const double kCaptureDefaultPixelRatio = 1;
const double kCaptureMaxEdge = 4096;
const int kCaptureMaxPixels = 8 * 1024 * 1024;

/// Unique key for the production capture boundary above Router/Overlay.
final GlobalKey flutterContentCaptureKey = GlobalKey(
  debugLabel: 'anywork-flutter-content-capture',
);

final class FlutterContentCaptureMeta {
  const FlutterContentCaptureMeta({
    required this.pixelRatio,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.imageWidth,
    required this.imageHeight,
    required this.scope,
  });

  final double pixelRatio;
  final double logicalWidth;
  final double logicalHeight;
  final int imageWidth;
  final int imageHeight;
  final String scope;

  Map<String, Object?> toJson() => {
    'pixelRatio': pixelRatio,
    'logicalWidth': logicalWidth,
    'logicalHeight': logicalHeight,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'scope': scope,
  };
}

final class FlutterContentCaptureResult {
  const FlutterContentCaptureResult({required this.png, required this.meta});

  final Uint8List png;
  final FlutterContentCaptureMeta meta;
}

/// Shared capture core: a painted production subtree to PNG.
///
/// Callers advance frames. This function does not wait for [endOfFrame] and
/// does not start a second widget tree.
Future<FlutterContentCaptureResult> capturePaintedBoundary({
  required RenderRepaintBoundary boundary,
  double pixelRatio = kCaptureDefaultPixelRatio,
}) async {
  if (!(pixelRatio.isFinite && pixelRatio > 0)) {
    throw ArgumentError.value(
      pixelRatio,
      'pixelRatio',
      'must be a finite positive number',
    );
  }
  final size = boundary.size;
  if (!size.isFinite || size.width <= 0 || size.height <= 0) {
    throw StateError(
      'Capture boundary has no painted size: ${size.width}x${size.height}',
    );
  }
  final imageWidth = (size.width * pixelRatio).round();
  final imageHeight = (size.height * pixelRatio).round();
  if (imageWidth > kCaptureMaxEdge || imageHeight > kCaptureMaxEdge) {
    throw StateError(
      'Capture edge ${imageWidth}x$imageHeight exceeds $kCaptureMaxEdge',
    );
  }
  if (imageWidth * imageHeight > kCaptureMaxPixels) {
    throw StateError(
      'Capture pixels ${imageWidth * imageHeight} exceed $kCaptureMaxPixels',
    );
  }
  ui.Image? image;
  try {
    image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('PNG encoding returned no bytes');
    }
    return FlutterContentCaptureResult(
      png: bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      meta: FlutterContentCaptureMeta(
        pixelRatio: pixelRatio,
        logicalWidth: size.width,
        logicalHeight: size.height,
        imageWidth: image.width,
        imageHeight: image.height,
        scope: 'flutter-content',
      ),
    );
  } finally {
    image?.dispose();
  }
}

Future<FlutterContentCaptureResult> captureFlutterContent({
  GlobalKey? key,
  double pixelRatio = kCaptureDefaultPixelRatio,
}) {
  final boundaryKey = key ?? flutterContentCaptureKey;
  final context = boundaryKey.currentContext;
  if (context == null) {
    throw StateError('Capture boundary is not mounted');
  }
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    throw StateError('Capture key is not a RepaintBoundary');
  }
  return capturePaintedBoundary(boundary: renderObject, pixelRatio: pixelRatio);
}
