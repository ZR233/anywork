import 'package:material_ui/material_ui.dart';

import '../../app/theme/studio_tokens.dart';

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
