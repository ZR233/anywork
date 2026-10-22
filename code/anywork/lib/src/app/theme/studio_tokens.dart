import 'package:flutter/material.dart';

import 'studio_semantic_colors.dart';

export 'studio_semantic_colors.dart';
export 'studio_typography.dart';

final class StudioRadii {
  const StudioRadii._();

  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 8.0;
  static const lg = 8.0;
  static const pill = 999.0;
}

final class StudioLayout {
  const StudioLayout._();

  static const sidebarWidth = 336.0;
  static const compactRailWidth = 60.0;

  /// 会话阅读列最大宽度：时间线、活动栏与输入区共享同一中心轴（design/19 §19.7）。
  static const conversationWidth = 1040.0;

  /// 用户与父代理消息的紧凑气泡上限：右对齐，但不占满整条阅读列。
  static const conversationPromptWidth = 680.0;
  static const settingsNavigationWidth = 196.0;
  static const compactBreakpoint = 960.0;
}

final class StudioShadows {
  const StudioShadows._();

  static List<BoxShadow> soft(Color color) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.07),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static List<BoxShadow> lifted(Color color) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.11),
        blurRadius: 26,
        offset: const Offset(0, 14),
      ),
    ];
  }
}

extension StudioThemeTokens on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;

  StudioSemanticColors get statusColors =>
      Theme.of(this).extension<StudioSemanticColors>()!;
}
