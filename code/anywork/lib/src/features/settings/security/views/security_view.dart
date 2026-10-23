import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_pane.dart';

/// The original read-only fixed full-access policy. It does not expose a new
/// permission selector or relax workspace/worktree confined boundaries.
class SecurityView extends StatelessWidget {
  const SecurityView({super.key});
  @override
  Widget build(BuildContext context) => SettingsPane(title: context.l10n.settingsSecurityTitle,
    subtitle: context.l10n.settingsSecurityModeSubtitle,
    child: ListView(children: [Text(context.l10n.settingsWorkspaceBoundary,
      style: Theme.of(context).textTheme.bodySmall)]));
}
