import 'package:material_ui/material_ui.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_hover_detail.dart';

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
