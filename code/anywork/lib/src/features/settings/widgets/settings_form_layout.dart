import 'package:flutter/material.dart';

/// Vertical form rhythm shared by bounded editors.
class SettingsFieldStack extends StatelessWidget {
  const SettingsFieldStack({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final child in children)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
    ],
  );
}

/// Two-column field grid at >= 620 width, one column below with a 10 gap.
class SettingsResponsiveFieldGrid extends StatelessWidget {
  const SettingsResponsiveFieldGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 620;
        if (!twoColumns) {
          return Column(
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: child,
                ),
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final child in children)
              SizedBox(width: (constraints.maxWidth - 12) / 2, child: child),
          ],
        );
      },
    );
  }
}

/// Bounded search input (max 380) with the established leading search icon.
class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
  });

  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: TextField(
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search, size: 18),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
