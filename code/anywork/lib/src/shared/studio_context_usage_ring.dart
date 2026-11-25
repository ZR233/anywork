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
    child: ExcludeSemantics(
      child: CircularProgressIndicator(
        // Unknown usage remains an empty track, never a loading animation.
        // The readout owner supplies the metric's meaning and accessibility.
        value: progress ?? 0,
        backgroundColor: trackColor.withValues(alpha: 0.74),
        color: progressColor,
        strokeWidth: 2.2,
        strokeAlign: CircularProgressIndicator.strokeAlignInside,
        strokeCap: StrokeCap.round,
        trackGap: 0,
        padding: const EdgeInsets.all(0.7),
      ),
    ),
  );
}
