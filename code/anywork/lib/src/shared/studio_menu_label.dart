import 'package:material_ui/material_ui.dart';

/// Quiet menu label shared by the start page and the active agent composer.
/// The owning menu supplies focus, hover, semantics and activation behavior.
class StudioMenuLabel extends StatelessWidget {
  const StudioMenuLabel({
    required this.label,
    this.leading,
    this.enabled = true,
    this.maxWidth = 180,
    super.key,
  });

  final String label;
  final Widget? leading;
  final bool enabled;
  final double maxWidth;

  static const _horizontalPadding = 8.0;
  static const _leadingGap = 6.0;
  static const _labelGap = 5.0;
  static const _arrowSize = 14.0;

  double measureWidth(BuildContext context, {double leadingWidth = 0}) {
    assert(leading == null || leadingWidth > 0);
    final textWidth = TextPainter.computeWidth(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style
            .merge(Theme.of(context).textTheme.labelMedium),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    );
    return _horizontalPadding * 2 +
        (leading == null ? 0 : leadingWidth + _leadingGap) +
        (textWidth + _labelGap).clamp(0.0, maxWidth) +
        _arrowSize;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = colors.onSurfaceVariant.withValues(alpha: enabled ? 1 : 0.5);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading case final leadingWidget?)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: _leadingGap),
                child: IconTheme.merge(
                  data: IconThemeData(size: 15, color: color),
                  child: leadingWidget,
                ),
              ),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: _labelGap),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: color),
                  ),
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: _arrowSize, color: color),
          ],
        ),
      ),
    );
  }
}
