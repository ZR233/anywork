import 'package:anywork/src/features/conversation/acp/state/acp_view_state.dart';

// Synthetic Antigravity protocol-shaped presentation, not user configuration.
List<AcpConfigControlPresentation> agyConfigurationFixture({
  bool flash = false,
}) => [
  const AcpConfigControlPresentation.select(
    id: 'mode',
    name: '模式',
    category: AcpConfigCategoryKind.mode,
    currentValue: 'agent',
    currentLabel: '执行',
    flatOptions: [
      AcpSelectChoicePresentation(value: 'agent', name: '执行'),
      AcpSelectChoicePresentation(value: 'plan', name: '规划'),
      AcpSelectChoicePresentation(value: 'ask', name: '仅问答'),
    ],
  ),
  AcpConfigControlPresentation.select(
    id: 'model',
    name: '模型',
    category: AcpConfigCategoryKind.model,
    currentValue: flash ? 'gemini-3-flash' : 'gemini-3.1-pro',
    currentLabel: flash ? 'Gemini 3 Flash' : 'Gemini 3.1 Pro',
    groups: const [
      AcpSelectGroupPresentation(
        id: 'gemini',
        name: 'Gemini 系列',
        options: [
          AcpSelectChoicePresentation(
            value: 'gemini-3.1-pro',
            name: 'Gemini 3.1 Pro',
          ),
          AcpSelectChoicePresentation(
            value: 'gemini-3-flash',
            name: 'Gemini 3 Flash',
          ),
        ],
      ),
      AcpSelectGroupPresentation(
        id: 'partners',
        name: 'Claude 与合作模型',
        options: [
          AcpSelectChoicePresentation(
            value: 'claude-sonnet-4.6',
            name: 'Claude Sonnet 4.6',
          ),
          AcpSelectChoicePresentation(
            value: 'claude-opus-4.6',
            name: 'Claude Opus 4.6',
          ),
        ],
      ),
    ],
  ),
  AcpConfigControlPresentation.select(
    id: 'thought_level',
    name: '思考强度',
    category: AcpConfigCategoryKind.thoughtLevel,
    currentValue: flash ? 'medium' : 'high',
    currentLabel: flash ? 'medium' : 'high',
    flatOptions: [
      if (flash)
        const AcpSelectChoicePresentation(value: 'minimal', name: 'minimal'),
      const AcpSelectChoicePresentation(value: 'low', name: 'low'),
      if (flash)
        const AcpSelectChoicePresentation(value: 'medium', name: 'medium'),
      const AcpSelectChoicePresentation(value: 'high', name: 'high'),
    ],
  ),
  const AcpConfigControlPresentation.boolean(
    id: 'use_ai_credits',
    name: '超额自动启用 AI Credits',
    category: AcpConfigCategoryKind.other,
    currentValue: false,
  ),
  const AcpConfigControlPresentation.select(
    id: 'terminal_policy',
    name: '终端命令放行策略',
    category: AcpConfigCategoryKind.other,
    currentValue: 'workspace_safe',
    currentLabel: '工作区安全命令',
    flatOptions: [
      AcpSelectChoicePresentation(value: 'ask_all', name: '逐次询问确认'),
      AcpSelectChoicePresentation(value: 'workspace_safe', name: '工作区安全命令'),
      AcpSelectChoicePresentation(value: 'turbo_auto', name: '自动放行'),
    ],
  ),
];
