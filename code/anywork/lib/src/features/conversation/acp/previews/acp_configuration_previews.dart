import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/material3_theme.dart';
import '../widgets/acp_configuration_panel.dart';

@Preview(name: 'ACP 服务端配置 · 窄窗', group: 'ACP', size: Size(320, 480))
Widget acpConfigurationPreview() => MaterialApp(
  theme: pureStudioTheme(),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: AcpConfigurationPanel(
        options: [
          AcpSessionConfigOptionView(
            id: const AcpConfigId('server-quality'),
            name: '回答方式',
            description: '来自智能体服务的配置说明，不依赖固定的模型或 effort',
            kind: AcpSelectConfigView(
              currentValue: const AcpConfigValueId('careful'),
              options: AcpGroupedOptionsView([
                AcpSelectGroupView(
                  group: const AcpConfigGroupId('quality'),
                  name: '质量',
                  options: const [
                    AcpSelectOptionView(
                      value: AcpConfigValueId('careful'),
                      name: '仔细分析',
                    ),
                    AcpSelectOptionView(
                      value: AcpConfigValueId('quick'),
                      name: '快速回答',
                    ),
                  ],
                ),
              ]),
            ),
          ),
          const AcpSessionConfigOptionView(
            id: AcpConfigId('citations'),
            name: '引用来源',
            kind: AcpBooleanConfigView(currentValue: true),
          ),
        ],
        modes: null,
        pending: false,
        onConfigure: (_, _) {},
        onMode: (_) {},
      ),
    ),
  ),
);
