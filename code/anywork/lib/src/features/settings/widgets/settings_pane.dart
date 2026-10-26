import 'package:flutter/material.dart';

import 'settings_layout.dart';

/// Settings page shell: fixed heading and actions over an independently
/// scrolling body.
///
/// The geometry itself lives in [SettingsPageLayout]/[SettingsHeader] so every
/// page shares one contract: centred `maxWidth`, responsive 16/28 horizontal
/// insets, 22 vertical header rhythm, 16 toolbar gap and a hairline footer.
/// This adapter exists only so a page can pass a plain title/subtitle pair; it
/// must not re-implement spacing.
class SettingsPane extends StatelessWidget {
  const SettingsPane({
    required this.title,
    required this.subtitle,
    required this.child,
    this.toolbar,
    this.trailing,
    this.footer,
    this.maxWidth = 1040,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? toolbar;
  final Widget? trailing;
  final Widget? footer;
  final double maxWidth;

  /// Section list variant: the body becomes the canonical scrolling list with
  /// the `settings-pane-scroll` identity and the 24 bottom padding, so driver
  /// journeys and tests keep addressing the same scrollable they did before the
  /// refactor.
  SettingsPane.scrolling({
    required this.title,
    required this.subtitle,
    required List<Widget> children,
    this.toolbar,
    this.trailing,
    this.footer,
    this.maxWidth = 1040,
    super.key,
  }) : child = ListView(
         key: const ValueKey('settings-pane-scroll'),
         padding: const EdgeInsets.only(bottom: 24),
         children: children,
       );

  @override
  Widget build(BuildContext context) => SettingsPageLayout(
    maxWidth: maxWidth,
    header: SettingsHeader(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
    ),
    toolbar: toolbar,
    footer: footer,
    child: child,
  );
}

/// One titled group of page content.
///
/// Delegates to [SettingsSectionPanel] so the section title style (titleSmall,
/// w600) and the 16 vertical rhythm stay identical across every page.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    this.trailing,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SettingsSectionPanel(
    title: title,
    trailing: trailing,
    children: children,
  );
}
