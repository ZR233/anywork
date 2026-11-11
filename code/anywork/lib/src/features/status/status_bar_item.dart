import 'package:material_ui/material_ui.dart';

import '../../app/theme/studio_tokens.dart';

/// Icon-only readout. Its complete value remains available to assistive
/// technology and the official tooltip without consuming footer width.
class StatusBarItem extends StatelessWidget {
  const StatusBarItem({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(icon, size: 15, color: context.colors.onSurfaceVariant),
      ),
    ),
  );
}
