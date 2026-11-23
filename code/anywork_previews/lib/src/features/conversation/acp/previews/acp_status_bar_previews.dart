import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/app/theme/studio_tokens.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/status/status_bar_item.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

Widget _acpStatusPreviewShell(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  ),
);

Widget _popoverCardFrame(BuildContext context, {required Widget child}) =>
    Container(
      width: 344,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        boxShadow: StudioShadows.soft(context.colors.shadow),
      ),
      child: child,
    );

final _liveDetailState = AcpContextDetailViewState(
  used: BigInt.from(64500),
  size: BigInt.from(200000),
  previousUsed: BigInt.from(50000),
  isLive: true,
  tokensPerSecond: 82.0,
  estimatedOutputTokens: 410,
  responseMillis: 5000,
  cost: (amount: 0.42, currency: 'USD'),
  serviceName: 'Workstation Codex Agent',
  serverName: 'codex-acp',
  serverVersion: '0.9.4',
  remoteSessionId: 'sess_01JQ9W7M2K8N4R5T',
  phase: AcpSessionStatusPhase.completed,
  lastStopReason: AcpStopReasonKind.endTurn,
  completedTurns: 4,
  updatedAt: DateTime(2026, 11, 23, 10, 42, 18),
  configItems: const [
    AcpConfigReadoutItem(label: '模型', value: 'GPT-5 Codex'),
    AcpConfigReadoutItem(label: '推理强度', value: 'High'),
    AcpConfigReadoutItem(label: '允许网络访问', value: '', booleanValue: true),
  ],
  capabilities: const [
    AcpCapabilityKind.image,
    AcpCapabilityKind.embeddedContext,
    AcpCapabilityKind.loadSession,
    AcpCapabilityKind.resumeSession,
    AcpCapabilityKind.listSessions,
  ],
);

final _retainedHighUsageState = AcpContextDetailViewState(
  used: BigInt.from(168000),
  size: BigInt.from(200000),
  previousUsed: BigInt.from(180000),
  isLive: false,
  tokensPerSecond: 46.8,
  estimatedOutputTokens: 281,
  responseMillis: 6000,
  serviceName: 'Claude Code Proxy',
  serverName: 'claude-agent-acp',
  serverVersion: 'v1.4.2',
  remoteSessionId: 'sess_claude_09af24c',
  phase: AcpSessionStatusPhase.disconnected,
  lastStopReason: AcpStopReasonKind.maxTokens,
  completedTurns: 7,
  updatedAt: DateTime(2026, 11, 23, 9, 18, 5),
  configItems: const [
    AcpConfigReadoutItem(
      label: '',
      value: 'Architect Mode',
      useModeFallbackLabel: true,
    ),
    AcpConfigReadoutItem(label: '自动批准只读', value: '', booleanValue: false),
  ],
  capabilities: const [
    AcpCapabilityKind.image,
    AcpCapabilityKind.audio,
    AcpCapabilityKind.loadSession,
  ],
);

const _coldUnknownState = AcpContextDetailViewState(
  isLive: true,
  serviceName: 'Local Gemini CLI',
  serverName: 'gemini-acp',
  serverVersion: '0.3.1',
  remoteSessionId: 'sess_cold_boot_01',
  phase: AcpSessionStatusPhase.ready,
  capabilities: [
    AcpCapabilityKind.image,
    AcpCapabilityKind.embeddedContext,
    AcpCapabilityKind.listSessions,
  ],
);

final _overCapacityStressState = AcpContextDetailViewState(
  used: BigInt.from(215000),
  size: BigInt.from(200000),
  previousUsed: BigInt.from(192000),
  isLive: false,
  tokensPerSecond: 62.5,
  estimatedOutputTokens: 250,
  responseMillis: 4000,
  cost: (amount: 12.85, currency: 'CNY'),
  serviceName: 'Enterprise Gateway Long Agent Name',
  serverName: 'opencode-enterprise-acp-adapter',
  serverVersion: 'v2.4.1',
  remoteSessionId: 'session_01JXYZLONGIDENTIFIER9988776655',
  phase: AcpSessionStatusPhase.disconnected,
  lastStopReason: AcpStopReasonKind.maxTurnRequests,
  completedTurns: 12,
  updatedAt: DateTime(2026, 11, 23, 8, 15, 30),
  configItems: const [
    AcpConfigReadoutItem(
      label: '',
      value: 'Plan Mode',
      useModeFallbackLabel: true,
    ),
    AcpConfigReadoutItem(label: '审批沙箱', value: '', booleanValue: true),
  ],
  capabilities: const [
    AcpCapabilityKind.image,
    AcpCapabilityKind.loadSession,
    AcpCapabilityKind.resumeSession,
    AcpCapabilityKind.listSessions,
  ],
);

@Preview(name: 'ACP 状态栏与实时上下文详情弹层', group: 'ACP 状态栏', size: Size(720, 670))
Widget acpStatusBarLiveAndPopoverPreview() => _acpStatusPreviewShell(
  Builder(
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AcpStatusBarView(
          status: const AcpConnectionStatusView(
            state: AcpStatusBarViewState(
              phase: AcpSessionStatusPhase.completed,
              stopReason: AcpStopReasonKind.endTurn,
              provenance: AcpHistoryOriginKind.loadReplay,
            ),
          ),
          contextUsage: AcpContextUsageView(
            state: (
              used: BigInt.from(64500),
              size: BigInt.from(200000),
              isLive: true,
            ),
            detailBuilder: (_) => AcpContextDetailView(state: _liveDetailState),
          ),
          throughput: const TokenThroughputReadout(
            estimated: true,
            tokensPerSecond: 82.0,
          ),
          cost: const AcpCostReadoutView(
            state: (amount: 0.42, currency: 'USD'),
          ),
          externalHistory: AcpExternalHistoryButtonView(
            threadId: 'preview-live',
            state: const AcpExternalHistoryButtonState(
              status: AcpExternalHistoryAvailability.available,
            ),
            onOpen: () {},
          ),
        ),
        const SizedBox(height: 12),
        _popoverCardFrame(
          context,
          child: AcpContextDetailView(state: _liveDetailState),
        ),
      ],
    ),
  ),
);

@Preview(name: 'ACP 断连后保持上次快照（高水位警告）', group: 'ACP 状态栏', size: Size(720, 650))
Widget acpStatusBarRetainedSnapshotPreview() => _acpStatusPreviewShell(
  Builder(
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AcpStatusBarView(
          status: const AcpConnectionStatusView(
            state: AcpStatusBarViewState(
              phase: AcpSessionStatusPhase.disconnected,
              provenance: AcpHistoryOriginKind.resumedWithoutHistory,
            ),
          ),
          contextUsage: AcpContextUsageView(
            state: (
              used: BigInt.from(168000),
              size: BigInt.from(200000),
              isLive: false,
            ),
            detailBuilder: (_) =>
                AcpContextDetailView(state: _retainedHighUsageState),
          ),
          throughput: const TokenThroughputReadout(
            estimated: true,
            tokensPerSecond: 46.8,
          ),
          cost: const AcpCostReadoutView(state: null),
          externalHistory: AcpExternalHistoryButtonView(
            threadId: 'preview-retained',
            state: const AcpExternalHistoryButtonState(
              status: AcpExternalHistoryAvailability.notReady,
            ),
            onOpen: null,
          ),
        ),
        const SizedBox(height: 12),
        _popoverCardFrame(
          context,
          child: AcpContextDetailView(state: _retainedHighUsageState),
        ),
      ],
    ),
  ),
);

@Preview(name: 'ACP 未知上下文默认空轨与信息弹层', group: 'ACP 状态栏', size: Size(420, 440))
Widget acpStatusBarUnknownContextPreview() => _acpStatusPreviewShell(
  Builder(
    builder: (context) => _popoverCardFrame(
      context,
      child: const AcpContextDetailView(state: _coldUnknownState),
    ),
  ),
);

@Preview(
  name: 'ACP 详情窄窗超限 · 1.3×字号',
  group: 'ACP 状态栏',
  size: Size(360, 760),
  textScaleFactor: 1.3,
)
Widget acpContextDetailNarrowStressPreview() => _acpStatusPreviewShell(
  Builder(
    builder: (context) => _popoverCardFrame(
      context,
      child: AcpContextDetailView(state: _overCapacityStressState),
    ),
  ),
);
