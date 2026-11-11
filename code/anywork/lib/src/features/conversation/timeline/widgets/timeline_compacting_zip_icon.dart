import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

/// 上下文压缩专用经典动态 ZIP 图标：
/// 圆角压缩档案包 + 中轴交错咬合拉链齿 + 滑动拉链头与拉环 + 纵向紧缩脉冲。
///
/// 周期起点 `0.0`（亦为减少动态效果时的静止帧）固定在经典半拉合关键帧：
/// 上半段拉链齿紧密咬合、拉链头与拉环悬垂于中下部，静态一眼可识别为 ZIP 压缩包。
class TimelineCompactingZipIcon extends StatelessWidget {
  const TimelineCompactingZipIcon({
    required this.progress,
    required this.color,
    required this.size,
    this.accentColor,
    super.key,
  });

  static const duration = Duration(milliseconds: 1800);

  final Animation<double> progress;
  final Color color;
  final Color? accentColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _CompactingZipPainter(
            progress: progress,
            color: color,
            accentColor: accent,
          ),
        ),
      ),
    );
  }
}

class _CompactingZipPainter extends CustomPainter {
  _CompactingZipPainter({
    required this.progress,
    required this.color,
    required this.accentColor,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final Color accentColor;

  static const List<double> _toothRows = [14.5, 19.0, 23.5, 28.0, 32.5, 37.0];

  /// 连续循环相位（0.0 与 1.0 均落在经典半拉合位 y=32.5，首尾无缝衔接）：
  /// - `0.00..0.34`：拉链头下拉至底端（32.5 -> 40.5），剩余拉链齿逐对咬合；
  /// - `0.34..0.64`：整包执行纵向压紧回弹脉冲（scaleY 1.0 -> 0.88 -> 1.0）；
  /// - `0.64..0.82`：拉链头平滑回升至上段（40.5 -> 19.5）；
  /// - `0.82..1.00`：重新下拉咬合回经典半拉合位（19.5 -> 32.5）。
  ({double sliderY, double squeeze}) _pose(double rawPhase) {
    final phase = rawPhase - rawPhase.floorToDouble();
    if (phase <= 0) {
      return (sliderY: 32.5, squeeze: 0.0);
    }
    if (phase < 0.34) {
      final t = Curves.easeInOutCubic.transform(phase / 0.34);
      return (sliderY: lerpDouble(32.5, 40.5, t)!, squeeze: 0.0);
    }
    if (phase < 0.64) {
      final u = (phase - 0.34) / 0.30;
      final pulse = math.sin(math.pi * Curves.easeInOut.transform(u));
      return (sliderY: 40.5, squeeze: pulse);
    }
    if (phase < 0.82) {
      final t = Curves.easeInOutCubic.transform((phase - 0.64) / 0.18);
      return (sliderY: lerpDouble(40.5, 19.5, t)!, squeeze: 0.0);
    }
    final t = Curves.easeInOutCubic.transform((phase - 0.82) / 0.18);
    return (sliderY: lerpDouble(19.5, 32.5, t)!, squeeze: 0.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (:sliderY, :squeeze) = _pose(progress.value);
    canvas.save();
    canvas.scale(size.width / 64.0, size.height / 64.0);

    // 围绕画布中心做体积守恒的轻柔纵向紧缩，外层布局槽位保持零位移。
    final scaleY = 1.0 - 0.115 * squeeze;
    final scaleX = 1.0 + 0.035 * squeeze;
    canvas.translate(32.0, 32.0);
    canvas.scale(scaleX, scaleY);
    canvas.translate(-32.0, -32.0);

    final boxRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(10.5, 7.5, 43.0, 49.0),
      const Radius.circular(9.5),
    );

    // 1. 档案包浅底填充与主轮廓
    canvas.drawRRect(
      boxRect,
      Paint()
        ..color = accentColor.withValues(alpha: 0.09 + 0.05 * squeeze)
        ..style = PaintingStyle.fill,
    );
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(boxRect, borderPaint);

    // 2. 上下压板折边细节（强化“压缩归档”语义）
    final clampPaint = Paint()
      ..color = color.withValues(alpha: 0.55 + 0.30 * squeeze)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(17.5, 12.2),
      const Offset(24.0, 12.2),
      clampPaint,
    );
    canvas.drawLine(
      const Offset(40.0, 12.2),
      const Offset(46.5, 12.2),
      clampPaint,
    );
    canvas.drawLine(
      const Offset(18.5, 51.8),
      const Offset(45.5, 51.8),
      clampPaint,
    );

    // 3. 拉链中轴导槽（已拉合段实线，未拉合段微张 V 形导轨）
    final seamPaint = Paint()
      ..color = color.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(32.0, 9.0), Offset(32.0, sliderY), seamPaint);
    if (sliderY < 41.5) {
      final openBottom = 43.0;
      canvas.drawLine(
        Offset(32.0, sliderY),
        Offset(28.8, openBottom),
        seamPaint,
      );
      canvas.drawLine(
        Offset(32.0, sliderY),
        Offset(35.2, openBottom),
        seamPaint,
      );
    }

    // 4. 经典左右交错拉链齿：拉链头上方紧密咬合，下方随距离自然微张
    final toothFillClosed = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final toothFillOpen = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < _toothRows.length; i++) {
      final rowY = _toothRows[i];
      final isLeft = i.isEven;
      final delta = rowY - sliderY;
      final openAmount = delta <= 0 ? 0.0 : (delta / 11.0).clamp(0.0, 1.0);
      final spread = 3.2 * openAmount;
      const toothWidth = 6.2;
      const toothHeight = 3.0;
      // 闭合时左右齿在中轴交错咬合 1.1px；微张时向两侧分开。
      final centerX = isLeft ? (32.0 - 2.0 - spread) : (32.0 + 2.0 + spread);
      final toothRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, rowY),
          width: toothWidth,
          height: toothHeight,
        ),
        const Radius.circular(1.1),
      );
      canvas.drawRRect(
        toothRect,
        openAmount < 0.15 ? toothFillClosed : toothFillOpen,
      );
    }

    // 5. 经典拉链滑块（Slider Body）与下垂拉环（Pull Tab）
    final sliderBody = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(32.0, sliderY + 1.2),
        width: 9.6,
        height: 7.4,
      ),
      const Radius.circular(2.4),
    );
    canvas.drawRRect(
      sliderBody,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      sliderBody,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // 拉环圆孔手柄（随紧缩轻微摆动）
    final pullRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(32.0, sliderY + 8.0),
        width: 5.8,
        height: 6.4,
      ),
      const Radius.circular(2.6),
    );
    canvas.drawRRect(
      pullRect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompactingZipPainter oldDelegate) =>
      color != oldDelegate.color ||
      accentColor != oldDelegate.accentColor ||
      progress != oldDelegate.progress;
}
