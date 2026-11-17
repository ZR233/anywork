import 'package:material_ui/material_ui.dart';

/// A presentation entry with an inline control and an equivalent menu item.
///
/// Owners provide the same current value, eligibility and action in both forms.
/// A missing [inline] keeps the entry in the overflow menu at every width.
final class ComposerConfigurationEntry {
  const ComposerConfigurationEntry({
    required this.id,
    required this.menuItem,
    this.inline,
    this.measureInlineWidth,
  }) : assert((inline == null) == (measureInlineWidth == null));

  final Object id;
  final Widget? inline;
  final Widget menuItem;
  final double Function(BuildContext context)? measureInlineWidth;
}

/// Keeps configuration on one row, moving complete entries into a native menu.
class ComposerConfigurationBar extends StatelessWidget {
  const ComposerConfigurationBar({
    required this.entries,
    required this.moreTooltip,
    super.key,
  });

  static const moreKey = ValueKey('composer-more-options');
  static const double _gap = 2;
  static const double _moreWidth = 32;

  final List<ComposerConfigurationEntry> entries;
  final String moreTooltip;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final candidates = entries
            .where((item) => item.inline != null)
            .toList();
        final widths = {
          for (final item in candidates)
            item: item.measureInlineWidth!(context),
        };
        final completeWidth =
            widths.values.fold<double>(0, (sum, width) => sum + width) +
            (candidates.isEmpty ? 0 : (candidates.length - 1) * _gap);
        final needsMore =
            candidates.length < entries.length ||
            completeWidth > constraints.maxWidth;
        final availableWidth =
            constraints.maxWidth - (needsMore ? _moreWidth + _gap : 0);
        final visible = <ComposerConfigurationEntry>[];
        var usedWidth = 0.0;
        for (final item in candidates) {
          final width = widths[item]! + (visible.isEmpty ? 0 : _gap);
          if (usedWidth + width > availableWidth) continue;
          visible.add(item);
          usedWidth += width;
        }
        final visibleEntries = visible.toSet();
        final hidden = entries.where((item) => !visibleEntries.contains(item));
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in visible) ...[
              if (item != visible.first) const SizedBox(width: _gap),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widths[item]!),
                child: item.inline,
              ),
            ],
            if (hidden.isNotEmpty) ...[
              if (visible.isNotEmpty) const SizedBox(width: _gap),
              MenuAnchor(
                menuChildren: [for (final item in hidden) item.menuItem],
                builder: (context, controller, _) => SizedBox.square(
                  dimension: _moreWidth,
                  child: IconButton(
                    key: moreKey,
                    tooltip: moreTooltip,
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                    icon: const Icon(Icons.more_horiz),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
