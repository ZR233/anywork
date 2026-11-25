import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';
import 'package:anywork_client/studio_client.dart'
    show DomainSyncPhase, DomainSyncStatus;

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/status/context_usage_readout.dart';
import 'package:anywork/src/features/status/status_bar_item.dart';
import 'package:anywork/src/features/status/started_items_panel.dart';
import 'package:anywork/src/features/status/started_items_state.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/features/status/views/workflow_graph_panel.dart';

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
  contextTokens: 28400,
  contextWindow: 128000,
  maxContextWindow: 128000,
  autoCompactLimit: 96000,
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

const _services = StartedItemsState(
  skills: ['frontend-design', 'flutter-add-widget-preview'],
  skillsTotal: 2,
  mcpStateTotal: 2,
  lspStateTotal: 2,
  mcpSync: DomainSyncStatus(phase: DomainSyncPhase.ready),
  lspSync: DomainSyncStatus(phase: DomainSyncPhase.ready),
  mcp: [
    StartedService(
      id: 'dart',
      name: 'Dart & Flutter',
      status: StartedServiceStatus.ready,
    ),
    StartedService(
      id: 'browser',
      name: 'Browser',
      status: StartedServiceStatus.failed,
      diagnostic: 'Connection closed',
    ),
  ],
  lsp: [
    StartedService(
      id: 'dart-analysis',
      name: 'Dart Analysis Server',
      status: StartedServiceStatus.ready,
    ),
    StartedService(
      id: 'rust-analyzer',
      name: 'rust-analyzer',
      status: StartedServiceStatus.indexing,
      percentage: 64,
    ),
  ],
);

Widget _threadStatusBarPreview({VoidCallback? onOpenPlan, bool dark = false}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      theme: dark
          ? ThemeData.dark(useMaterial3: true).copyWith(
              extensions: pureStudioTheme(locale: const Locale('zh'))
                  .extensions
                  .values,
            )
          : pureStudioTheme(locale: const Locale('zh')),
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
              throughputReadout: const TokenThroughputReadout(
                tokensPerSecond: 42,
              ),
              startedItemsEntry: StartedItemsMenu(
                panelBuilder: (context) => StartedItemsPanel(
                  state: _services,
                  onLoadMoreSkills: () {},
                  onLoadMoreMcpState: () {},
                  onLoadMoreLspState: () {},
                  onReconnectMcp: (_) {},
                  onReconnectLsp: (_) {},
                ),
              ),
              workflowReadout: WorkflowStatusPill(
                stateTitle: '规划',
                modeName: '任务流程',
                deleted: true,
                onTap: () {},
              ),
              showTodo: true,
              onToggleTodo: () {},
              showPlanEntry: true,
              onOpenPlan: onOpenPlan ?? () {},
              hasSidebarPanels: true,
              onToggleSidebar: () {},
            ),
          ],
        ),
      ),
    );

/// Test fixture can observe the production Plan action without a Client/provider.
Widget threadStatusBarLayoutFixture({VoidCallback? onOpenPlan}) =>
    _threadStatusBarPreview(onOpenPlan: onOpenPlan);

@Preview(name: '底部状态栏 / 宽屏', group: 'Status · 底部状态栏', size: Size(1000, 560))
Widget threadStatusBarWidePreview() => threadStatusBarLayoutFixture();

@Preview(name: '底部状态栏 / 窄屏可滚动', group: 'Status · 底部状态栏', size: Size(320, 560))
Widget threadStatusBarNarrowPreview() => threadStatusBarLayoutFixture();

@Preview(name: '底部状态栏 / 深色组件检查', group: 'Status · 底部状态栏', size: Size(800, 560))
Widget threadStatusBarDarkPreview() => _threadStatusBarPreview(dark: true);
