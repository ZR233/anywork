import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_pane.dart';

/// The original read-only fixed full-access policy. It does not expose a new
/// permission selector or relax workspace/worktree confined boundaries.
class SecurityView extends StatelessWidget {
  const SecurityView({super.key});

  @override
  Widget build(BuildContext context) => SettingsPane.scrolling(
    title: context.l10n.settingsSecurityTitle,
    subtitle: context.l10n.settingsSecurityModeSubtitle,
    // 只读说明页沿用原有的居中 880 上限，宽窗上不会铺满整幅。
    maxWidth: 880,
    children: [
      Text(
        context.l10n.settingsWorkspaceBoundary,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.colors.onSurfaceVariant),
      ),
    ],
  );
}
