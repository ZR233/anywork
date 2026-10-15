import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import 'settings_common.dart';

/// 只读安全说明页。
///
/// 产品策略把工具执行固定为 `full-access`，Composer 与设置页都不再暴露权限
/// 模式选择；本页只说明固定的执行权限策略与工作区边界。固定策略仅改变策略层
/// 的放行判断，不影响 workspace/worktree 的 confined 边界。
class SecurityTab extends StatelessWidget {
  const SecurityTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPane(
      header: SettingsHeader(
        title: context.l10n.settingsSecurityTitle,
        subtitle: context.l10n.settingsSecurityModeSubtitle,
      ),
      maxWidth: 880,
      children: [
        Text(
          context.l10n.settingsWorkspaceBoundary,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
