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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = colors.onSurfaceVariant.withValues(alpha: enabled ? 1 : 0.5);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading case final leadingWidget?)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: IconTheme.merge(
                  data: IconThemeData(size: 15, color: color),
                  child: leadingWidget,
                ),
              ),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 5),
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
            Icon(Icons.keyboard_arrow_down, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}
