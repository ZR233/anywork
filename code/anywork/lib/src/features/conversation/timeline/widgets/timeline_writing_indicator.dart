import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 纸面与笔分层绘制，书写位移只作用于笔。
class TimelineWritingIndicator extends StatelessWidget {
  const TimelineWritingIndicator({
    required this.position,
    required this.color,
    required this.size,
    super.key,
  });

  final Animation<Offset> position;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            key: const ValueKey('writing-paper'),
            painter: _PaperPainter(color),
          ),
        ),
        Positioned.fill(
          child: SlideTransition(
            position: position,
            transformHitTests: false,
            child: RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('writing-pen'),
                painter: _PenPainter(color),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final ink = Paint()
      ..color = color.withValues(alpha: .6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(3, 6.5), const Offset(11, 6.5), ink);
    canvas.drawLine(const Offset(3, 12.5), const Offset(8, 12.5), ink);
    canvas.drawLine(const Offset(3, 20.5), const Offset(19, 20.5), ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaperPainter oldDelegate) => color != oldDelegate.color;
}

class _PenPainter extends CustomPainter {
  const _PenPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.translate(10, 18);
    canvas.rotate(-math.pi / 4);
    final ink = Paint()..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(3.3, -1.55)
        ..lineTo(3.3, 1.55)
        ..close(),
      ink,
    );
    for (final (start, end) in const [(4.1, 12.9), (13.6, 15.0)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(start, -1.55, end, 1.55),
          const Radius.circular(.6),
        ),
        ink,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PenPainter oldDelegate) => color != oldDelegate.color;
}
