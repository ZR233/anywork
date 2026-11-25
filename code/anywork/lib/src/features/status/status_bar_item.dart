import 'package:material_ui/material_ui.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_hover_detail.dart';

/// A panel action in the conversation strip. Material owns its interaction state.
class StatusBarButton extends StatelessWidget {
  const StatusBarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.iconOnly = false,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool iconOnly;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: selected
          ? context.colors.primary
          : context.colors.onSurfaceVariant,
      disabledForegroundColor: context.colors.onSurfaceVariant,
      backgroundColor: selected
          ? context.colors.secondaryContainer
          : Colors.transparent,
      minimumSize: Size(iconOnly ? 30 : 0, 30),
      padding: iconOnly
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: context.text.labelMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
    );
    return Semantics(
      selected: selected,
      label: tooltip ?? label,
      excludeSemantics: true,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      child: Tooltip(
        message: tooltip ?? label,
        excludeFromSemantics: true,
        child: iconOnly
            ? IconButton(
                onPressed: onPressed,
                style: style,
                visualDensity: VisualDensity.standard,
                iconSize: 16,
                icon: Icon(icon),
              )
            : TextButton.icon(
                onPressed: onPressed,
                style: style,
                icon: Icon(icon, size: 16),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Compact readout with an optional short text and a complete explanation.
class StatusBarItem extends StatelessWidget {
  const StatusBarItem({
    required this.icon,
    required this.label,
    this.text,
    this.triggerKey,
    this.detailKey,
    this.detailBuilder,
    this.detailMaxWidth = 336,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? text;
  final Key? triggerKey;
  final Key? detailKey;
  final WidgetBuilder? detailBuilder;
  final double detailMaxWidth;

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(
      key: triggerKey,
      child: SizedBox(
        width: text == null ? 32 : null,
        height: 32,
        child: text == null
            ? Icon(icon, size: 15, color: context.colors.onSurfaceVariant)
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    text!,
                    maxLines: 1,
                    softWrap: false,
                    style: context.text.labelSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
      ),
    );
    if (detailBuilder != null) {
      return StudioHoverDetail(
        maxWidth: detailMaxWidth,
        semanticsLabel: label,
        detailBuilder: (context) {
          final detail = detailBuilder!(context);
          return detailKey == null
              ? detail
              : KeyedSubtree(key: detailKey, child: detail);
        },
        child: content,
      );
    }
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: content,
      ),
    );
  }
}

class TokenThroughputReadout extends StatelessWidget {
  const TokenThroughputReadout({
    required this.tokensPerSecond,
    this.estimated = false,
    this.triggerKey,
    this.detailKey,
    this.detailBuilder,
    this.detailMaxWidth = 336,
    super.key,
  });

  final double? tokensPerSecond;
  final bool estimated;
  final Key? triggerKey;
  final Key? detailKey;
  final WidgetBuilder? detailBuilder;
  final double detailMaxWidth;

  @override
  Widget build(BuildContext context) {
    final value = context.tokenThroughputLabel(tokensPerSecond);
    final text = estimated && tokensPerSecond != null ? '≈ $value' : value;
    return StatusBarItem(
      icon: Icons.speed_outlined,
      text: text,
      label:
          '${estimated ? context.l10n.acpEstimatedOutputSpeed : context.l10n.statusLastConfirmedAgentTokenSpeed}: $text',
      triggerKey: triggerKey,
      detailKey: detailKey,
      detailBuilder: detailBuilder,
      detailMaxWidth: detailMaxWidth,
    );
  }
}
