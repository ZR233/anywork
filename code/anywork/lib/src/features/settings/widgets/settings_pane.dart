import 'package:flutter/material.dart';

/// Settings-specific fixed header / scrolling body / stable action area.
class SettingsPane extends StatelessWidget {
  const SettingsPane({required this.title, required this.subtitle,
    required this.child, this.toolbar, this.trailing, this.footer, super.key});

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? toolbar;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (subtitle.isNotEmpty) Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ])),
        if (trailing != null) trailing!,
      ]),
      if (toolbar != null) Padding(padding: const EdgeInsets.only(top: 16), child: toolbar!),
      const SizedBox(height: 16),
      Expanded(child: child),
      if (footer != null) ...[const Divider(), footer!],
    ]),
  );
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({required this.title, required this.children, super.key});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      ...children,
    ]),
  );
}
