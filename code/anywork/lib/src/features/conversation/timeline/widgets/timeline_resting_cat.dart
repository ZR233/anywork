import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 趴卧猫活动图标：身体固定，只有垂落的尾巴大幅摆动；时钟由活动行或状态栏宿主持有。
class TimelineRestingCat extends StatelessWidget {
  const TimelineRestingCat({
    required this.progress,
    required this.color,
    required this.size,
    super.key,
  });

  static const duration = Duration(milliseconds: 2600);

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

  static double _liftY(double y) => 34.0 - (34.0 - y) * 1.22;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const dx = -3.2;
    final body = Path()
      ..moveTo(10.8 + dx, _liftY(29.6))
      ..cubicTo(
        9.5 + dx,
        _liftY(27.6),
        9.6 + dx,
        _liftY(25.6),
        11.6 + dx,
        _liftY(22.6),
      )
      ..cubicTo(
        11.1 + dx,
        _liftY(20.5),
        11.7 + dx,
        _liftY(16.5),
        12.9 + dx,
        _liftY(15.2),
      )
      ..cubicTo(
        15.3 + dx,
        _liftY(15.3),
        17.3 + dx,
        _liftY(17.2),
        18.9 + dx,
        _liftY(19.0),
      )
      ..quadraticBezierTo(20.7 + dx, _liftY(18.6), 22.1 + dx, _liftY(19.0))
      ..cubicTo(
        23.9 + dx,
        _liftY(16.7),
        25.6 + dx,
        _liftY(15.0),
        27.1 + dx,
        _liftY(14.7),
      )
      ..cubicTo(
        28.5 + dx,
        _liftY(16.8),
        29.0 + dx,
        _liftY(19.3),
        29.1 + dx,
        _liftY(21.5),
      )
      ..cubicTo(
        34.8 + dx,
        _liftY(16.3),
        41.3 + dx,
        _liftY(15.7),
        46.3 + dx,
        _liftY(18.6),
      )
      ..cubicTo(51.8 + dx, _liftY(21.6), 53.8 + dx, _liftY(27.0), 50.6, 36.2)
      ..moveTo(4.3, 34.0)
      ..lineTo(43.4, 34.0)
      ..quadraticBezierTo(45.8, 34.0, 45.8, 36.2)
      ..moveTo(50.6, 34.0)
      ..lineTo(54.2, 34.0)
      // 前爪、闭合的眼睛和后腿轮廓。
      ..moveTo(9.3 + dx, _liftY(33.8))
      ..cubicTo(
        8.8 + dx,
        _liftY(28.6),
        16.4 + dx,
        _liftY(28.3),
        16.8 + dx,
        _liftY(33.8),
      )
      ..moveTo(15.3 + dx, _liftY(27.6))
      ..quadraticBezierTo(17.1 + dx, _liftY(29.0), 18.7 + dx, _liftY(27.6))
      ..moveTo(22.3 + dx, _liftY(27.6))
      ..quadraticBezierTo(24.2 + dx, _liftY(29.0), 25.8 + dx, _liftY(27.6))
      ..moveTo(24.7 + dx, _liftY(33.8))
      ..cubicTo(
        24.5 + dx,
        _liftY(29.5),
        30.3 + dx,
        _liftY(28.2),
        32.0 + dx,
        _liftY(31.4),
      )
      ..moveTo(39.7 + dx, _liftY(33.8))
      ..cubicTo(
        36.9 + dx,
        _liftY(32.7),
        38.1 + dx,
        _liftY(28.8),
        42.2 + dx,
        _liftY(27.4),
      );
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

  // 六段方向关键姿态（相对竖直下垂的偏角，正值向猫腹左侧大幅摆动并勾尾，负值向台沿右侧大幅舒展）：
  // 根部锚定不越过台沿，中上段先带动大幅钟摆，尾尖滞后甩出灵动 J/S 形弧线，整周期连贯循环。
  static const _rest = [0.0, .14, .28, .42, .54, .62];
  static const _poses = <(double, List<double>)>[
    (0.00, _rest),
    (0.24, [0.0, .58, 1.04, 1.42, 1.72, 1.94]),
    (0.50, [0.0, -.06, -.14, -.10, .08, .30]),
    (0.74, [0.0, -.38, -.64, -.82, -.94, -1.02]),
    (1.00, _rest),
  ];

  double _direction(double phase, int joint) {
    if (joint == 0) return 0.0;
    final cycle = phase - phase.floorToDouble();
    if (cycle <= 0) return _rest[joint];
    final count = _poses.length - 1;
    var index = 0;
    while (index < count - 1 && cycle > _poses[index + 1].$1) {
      index++;
    }
    final (start, from) = _poses[index];
    final (end, to) = _poses[index + 1];
    final prevIndex = index == 0 ? count - 1 : index - 1;
    final nextIndex = index + 2 > count ? 1 : index + 2;
    final beforeTime = index == 0
        ? _poses[prevIndex].$1 - 1.0
        : _poses[prevIndex].$1;
    final afterTime = index + 2 > count
        ? _poses[nextIndex].$1 + 1.0
        : _poses[nextIndex].$1;
    final before = _poses[prevIndex].$2;
    final after = _poses[nextIndex].$2;
    final u = ((cycle - start) / (end - start)).clamp(0.0, 1.0);
    final a = from[joint];
    final b = to[joint];
    final tangentA = (b - before[joint]) / (end - beforeTime);
    final tangentB = (after[joint] - a) / (afterTime - start);
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
    final phase = progress.value;
    final directions = List.generate(
      6,
      (joint) => phase == 0
          ? _rest[joint]
          : _direction(phase - .055 * math.pow(joint / 5, 1.3), joint),
    );
    const segments = 56;
    final points = <Offset>[const Offset(48.2, 37.2)];
    for (var i = 1; i <= segments; i++) {
      final position = (i - .5) / segments * 5;
      final joint = position.floor();
      final swing = _curve(
        directions[math.max(0, joint - 1)],
        directions[joint],
        directions[math.min(5, joint + 1)],
        directions[math.min(5, joint + 2)],
        position - joint,
      );
      final rootBlend = (position / .70).clamp(0.0, 1.0);
      final angle = (math.pi / 2 + swing * rootBlend).clamp(
        math.pi * .14,
        math.pi * 1.12,
      );
      points.add(
        points.last +
            Offset(math.cos(angle), math.sin(angle)) * (20.8 / segments),
      );
    }
    final left = <Offset>[];
    final right = <Offset>[];
    final normals = <Offset>[];
    for (var i = 0; i <= segments; i++) {
      final tangent =
          points[math.min(segments, i + 1)] - points[math.max(0, i - 1)];
      final normal = Offset(-tangent.dy, tangent.dx) / tangent.distance;
      final radius = 2.4 - .45 * math.pow(i / segments, 1.5);
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
      ...cap(points.last, normals.last, 1.95),
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
        ..strokeWidth = 2.25
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RestingTailPainter oldDelegate) =>
      color != oldDelegate.color || progress != oldDelegate.progress;
}
