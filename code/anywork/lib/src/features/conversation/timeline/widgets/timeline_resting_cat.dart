import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 趴卧猫活动图标：身体固定，只有垂落的尾巴摆动；时钟由活动行持有。
class TimelineRestingCat extends StatelessWidget {
  const TimelineRestingCat({
    required this.progress,
    required this.color,
    required this.size,
    super.key,
  });

  static const duration = Duration(milliseconds: 4520);

  final Animation<double> progress;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _RestingCatBodyPainter(color)),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _RestingTailPainter(progress, color)),
            ),
          ),
        ],
      ),
    ),
  );
}

// 身体与尾巴各自绘制，动画只触发尾巴重绘，不移动身体或整枚图标。
class _RestingCatBodyPainter extends CustomPainter {
  const _RestingCatBodyPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final body = Path()
      ..moveTo(10.8, 29.6)
      ..cubicTo(9.5, 27.6, 9.6, 25.6, 11.6, 22.6)
      ..cubicTo(11.1, 20.5, 11.7, 16.5, 12.9, 15.2)
      ..cubicTo(15.3, 15.3, 17.3, 17.2, 18.9, 19)
      ..quadraticBezierTo(20.7, 18.6, 22.1, 19)
      ..cubicTo(23.9, 16.7, 25.6, 15, 27.1, 14.7)
      ..cubicTo(28.5, 16.8, 29, 19.3, 29.1, 21.5)
      ..cubicTo(34.8, 16.3, 41.3, 15.7, 46.3, 18.6)
      ..cubicTo(51.8, 21.6, 53.8, 27, 53.8, 36)
      ..moveTo(7.5, 34)
      ..lineTo(46.6, 34)
      ..quadraticBezierTo(49, 34, 49, 36)
      ..moveTo(53.8, 34)
      ..lineTo(56.8, 34)
      // 前爪、闭合的眼睛和后腿轮廓。
      ..moveTo(9.3, 33.8)
      ..cubicTo(8.8, 28.6, 16.4, 28.3, 16.8, 33.8)
      ..moveTo(15.3, 27.6)
      ..quadraticBezierTo(17.1, 29, 18.7, 27.6)
      ..moveTo(22.3, 27.6)
      ..quadraticBezierTo(24.2, 29, 25.8, 27.6)
      ..moveTo(24.7, 33.8)
      ..cubicTo(24.5, 29.5, 30.3, 28.2, 32, 31.4)
      ..moveTo(39.7, 33.8)
      ..cubicTo(36.9, 32.7, 38.1, 28.8, 42.2, 27.4);
    canvas.drawPath(body, ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RestingCatBodyPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _RestingTailPainter extends CustomPainter {
  _RestingTailPainter(this.progress, this.color) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  // 原创轮廓的六段方向关键姿态，按真实猫尾巴参考作视觉设计：
  // https://www.pexels.com/video/a-white-cat-swinging-its-tail-6853336/
  // 中段先转向、尾尖稍后翻卷；每段长度不变，不靠拉伸制造摆动。
  static const _rest = [.58, .58, .45, .20, -.16, -.42];
  static const _poses = <(double, List<double>)>[
    (0, _rest),
    (.7, _rest),
    (1.03, [.58, .59, .39, -.03, -.86, -1.62]),
    (1.43, [.58, .59, .43, .18, -.12, -.42]),
    (1.78, [.58, .60, .55, .56, .68, .82]),
    (2.00, [.58, .60, .57, .63, 1.10, 1.72]),
    (2.23, [.58, .59, .48, .32, .72, 1.78]),
    (2.54, [.58, .57, .35, -.12, -.57, -.10]),
    (2.87, [.58, .57, .31, -.23, -.95, -1.41]),
    (3.20, [.58, .58, .40, .12, -.29, -.70]),
    (3.55, _rest),
    (4.35, _rest),
    (4.55, [.58, .58, .45, .20, -.18, -.72]),
    (4.85, _rest),
    (6.6, _rest),
  ];

  // 仅裁短静止区间，保持已经确认的摆动速度与尾尖跟随时差。
  double _poseTime(double seconds) => switch (seconds) {
    < .32 => seconds,
    < 3.56 => seconds + .4,
    < 4.24 => seconds + .8,
    _ => seconds + 2.08,
  };

  double _direction(double time, int joint) {
    if (time <= 0) return _rest[joint];
    var index = 0;
    while (index < _poses.length - 2 && time > _poses[index + 1].$1) {
      index++;
    }
    final (start, from) = _poses[index];
    final (end, to) = _poses[index + 1];
    final (beforeTime, before) = _poses[math.max(0, index - 1)];
    final (afterTime, after) = _poses[math.min(_poses.length - 1, index + 2)];
    final u = ((time - start) / (end - start)).clamp(0.0, 1.0);
    final a = from[joint];
    final b = to[joint];
    final tangentA = a == before[joint] || a == b
        ? 0.0
        : (b - before[joint]) / (end - beforeTime);
    final tangentB = a == b || b == after[joint]
        ? 0.0
        : (after[joint] - a) / (afterTime - start);
    final square = u * u;
    final cube = square * u;
    return (2 * cube - 3 * square + 1) * a +
        (cube - 2 * square + u) * (end - start) * tangentA +
        (-2 * cube + 3 * square) * b +
        (cube - square) * (end - start) * tangentB;
  }

  double _curve(double a, double b, double c, double d, double u) =>
      .5 *
      (2 * b +
          (-a + c) * u +
          (2 * a - 5 * b + 4 * c - d) * u * u +
          (-a + 3 * b - 3 * c + d) * u * u * u);

  @override
  void paint(Canvas canvas, Size size) {
    final time = _poseTime(progress.value * 4.52);
    final directions = List.generate(
      6,
      (joint) => _direction(time - .13 * math.pow(joint / 5, 1.5), joint),
    );
    const segments = 56;
    final points = <Offset>[const Offset(51.4, 36)];
    for (var i = 1; i <= segments; i++) {
      final position = (i - .5) / segments * 5;
      final joint = position.floor();
      final swing = _curve(
        directions[math.max(0, joint - 1)] - _rest[math.max(0, joint - 1)],
        directions[joint] - _rest[joint],
        directions[math.min(5, joint + 1)] - _rest[math.min(5, joint + 1)],
        directions[math.min(5, joint + 2)] - _rest[math.min(5, joint + 2)],
        position - joint,
      );
      // 垂尾从固定根部向下摆动，沿用旧姿态的节奏与尾尖跟随时差。
      final angle = math.pi / 2 + swing * .48;
      points.add(
        points.last +
            Offset(math.cos(angle), math.sin(angle)) * (15.4 / segments),
      );
    }
    final left = <Offset>[];
    final right = <Offset>[];
    final normals = <Offset>[];
    for (var i = 0; i <= segments; i++) {
      final tangent =
          points[math.min(segments, i + 1)] - points[math.max(0, i - 1)];
      final normal = Offset(-tangent.dy, tangent.dx) / tangent.distance;
      final radius = 2.4 - .4 * math.pow(i / segments, 1.5);
      normals.add(normal);
      left.add(points[i] + normal * radius);
      right.add(points[i] - normal * radius);
    }
    Iterable<Offset> cap(Offset point, Offset normal, double radius) sync* {
      final start = math.atan2(normal.dy, normal.dx);
      for (var i = 1; i < 10; i++) {
        final angle = start - math.pi * i / 10;
        yield point + Offset(math.cos(angle), math.sin(angle)) * radius;
      }
    }

    final outline = [
      ...left,
      ...cap(points.last, normals.last, 2.0),
      ...right.reversed,
    ];
    // 根部不封口，与静止身体和台沿的轮廓连续相接。
    final path = Path()..addPolygon(outline, false);
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RestingTailPainter oldDelegate) =>
      color != oldDelegate.color || progress != oldDelegate.progress;
}
