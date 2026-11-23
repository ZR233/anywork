import 'package:material_ui/material_ui.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';

/// Compact readout with an optional short text and a complete explanation.
class StatusBarItem extends StatelessWidget {
  const StatusBarItem({
    required this.icon,
    required this.label,
    this.text,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? text;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: Tooltip(
      message: label,
      excludeFromSemantics: true,
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
    ),
  );
}

class TokenThroughputReadout extends StatelessWidget {
  const TokenThroughputReadout({
    required this.tokensPerSecond,
    this.estimated = false,
    super.key,
  });

  final double? tokensPerSecond;
  final bool estimated;

  @override
  Widget build(BuildContext context) {
    final value = context.tokenThroughputLabel(tokensPerSecond);
    final text = estimated && tokensPerSecond != null ? '≈ $value' : value;
    return StatusBarItem(
      icon: Icons.speed_outlined,
      text: text,
      label:
          '${estimated ? context.l10n.acpEstimatedOutputSpeed : context.l10n.statusLastConfirmedAgentTokenSpeed}: $text',
    );
  }
}
