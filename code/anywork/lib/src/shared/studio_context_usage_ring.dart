import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Shared ring geometry without metric-specific meaning or accessibility.
class ContextUsageRing extends StatelessWidget {
  const ContextUsageRing({
    super.key,
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double? progress;
  final Color trackColor;
  final Color progressColor;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: CustomPaint(
      painter: _ContextUsagePainter(
        progress: progress,
        trackColor: trackColor,
        progressColor: progressColor,
      ),
    ),
  );
}

class _ContextUsagePainter extends CustomPainter {
  const _ContextUsagePainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double? progress;
  final Color trackColor;
  final Color progressColor;

  static const _strokeWidth = 2.2;
  static const _radiusInset = 1.8;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - _radiusInset;
    final trackPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.74)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _strokeWidth;
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);
    final progress = this.progress;
    if (progress == null || progress <= 0) {
      return;
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ContextUsagePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        trackColor != oldDelegate.trackColor ||
        progressColor != oldDelegate.progressColor;
  }
}
