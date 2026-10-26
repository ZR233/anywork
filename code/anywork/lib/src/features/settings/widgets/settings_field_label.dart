import 'package:flutter/material.dart';

/// Quiet leading caption for compact controls that ship without their own field
/// decoration, such as the shared model selector.
class SettingsFieldLabel extends StatelessWidget {
  const SettingsFieldLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
