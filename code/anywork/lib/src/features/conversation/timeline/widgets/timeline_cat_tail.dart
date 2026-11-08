import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 活动状态的竖尾图标；动画时钟由活动指示组件持有。
class TimelineCatTail extends StatelessWidget {
  const TimelineCatTail({
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
      child: CustomPaint(painter: _CatTailPainter(progress, color)),
    ),
  );
}

class _CatTailPainter extends CustomPainter {
  _CatTailPainter(this.progress, this.color) : super(repaint: progress);

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
    final points = <Offset>[const Offset(10, 20)];
    for (var i = 1; i <= segments; i++) {
      final position = (i - .5) / segments * 5;
      final joint = position.floor();
      final angle = _curve(
        directions[math.max(0, joint - 1)],
        directions[joint],
        directions[math.min(5, joint + 1)],
        directions[math.min(5, joint + 2)],
        position - joint,
      );
      points.add(
        points.last +
            Offset(math.cos(angle), math.sin(angle)) * (43 / segments),
      );
    }
    final left = <Offset>[];
    final right = <Offset>[];
    final normals = <Offset>[];
    for (var i = 0; i <= segments; i++) {
      final tangent =
          points[math.min(segments, i + 1)] - points[math.max(0, i - 1)];
      final normal = Offset(-tangent.dy, tangent.dx) / tangent.distance;
      final radius = 3.7 - 1.85 * math.pow(i / segments, 1.5);
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
      ...cap(points.last, normals.last, 1.85),
      ...right.reversed,
      ...cap(points.first, -normals.first, 3.7),
    ];
    final path = Path()..addPolygon(outline, true);
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    canvas.translate(29, 55);
    canvas.rotate(-115 * math.pi / 180);
    canvas.translate(-10, -20);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CatTailPainter oldDelegate) =>
      color != oldDelegate.color || progress != oldDelegate.progress;
}
