import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/material3_theme.dart';
import '../../../domain/models/studio_models.dart';
import '../../../l10n/app_localizations.dart';
import '../context_usage_readout.dart';
import '../status_bar_item.dart';
import '../thread_status_bar.dart';

final _statusFixture = StatusBarView(
  row: SessionDirectoryRow(
    sessionId: 'preview-session',
    agentId: 'preview-agent',
    threadId: 'preview-thread',
    workspaceId: 'preview-workspace',
    title: '底部状态栏预览',
    mode: null,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    workspacePath: '.',
    backend: const NativeAgentBackendView(
      config: NativeAgentConfigView(),
      status: ThreadStatusView.running,
    ),
    updatedAt: DateTime.utc(2025),
  ),
  accounts: const [],
  roles: const [],
  isBusy: true,
);

const _contextProjection = StudioContextProjection(
  threadId: 'preview-thread',
  modelId: 'preview-model',
  contextTokens: 4200,
  contextWindow: 32000,
  maxContextWindow: 64000,
  autoCompactLimit: 48000,
  totalTokens: 9200,
  costLabel: '',
  promptTokens: 5800,
  completionTokens: 3400,
  cachedPromptTokens: 0,
  cacheWriteTokens: 0,
  reasoningTokens: 0,
  inferenceCount: 2,
  cacheUsage: CacheUsageView(),
  estimatedCosts: [],
  estimatedCacheSavings: [],
  hasUnpricedUsage: false,
  hasIncompleteUsage: false,
);

Widget _threadStatusBarPreview({VoidCallback? onOpenPlan}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Column(
      children: [
        const Spacer(),
        ThreadStatusBar(
          key: const ValueKey('thread-status-bar-preview'),
          status: _statusFixture,
          contextReadout: const ContextUsageReadout(
            projection: _contextProjection,
          ),
          throughputReadout: const TokenThroughputReadout(tokensPerSecond: 42),
          startedItemsEntry: const StatusBarItem(
            icon: Icons.tune_outlined,
            label: '能力与已启动项目（合成图标槽位，无 Provider）',
          ),
          workflowReadout: const WorkflowStatusReadout(
            stateTitle: '规划',
            modeName: '任务流程',
            deleted: true,
          ),
          showTodo: true,
          onToggleTodo: () {},
          showPlanEntry: true,
          onOpenPlan: onOpenPlan ?? () {},
        ),
      ],
    ),
  ),
);

/// Test fixture can observe the production Plan action without a Client/provider.
Widget threadStatusBarLayoutFixture({VoidCallback? onOpenPlan}) =>
    _threadStatusBarPreview(onOpenPlan: onOpenPlan);

@Preview(name: '底部状态栏 / 宽屏', group: 'Status · 底部状态栏', size: Size(1000, 180))
Widget threadStatusBarWidePreview() => threadStatusBarLayoutFixture();

@Preview(name: '底部状态栏 / 窄屏可滚动', group: 'Status · 底部状态栏', size: Size(320, 180))
Widget threadStatusBarNarrowPreview() => threadStatusBarLayoutFixture();
