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

Widget _popoverCardFrame(
  BuildContext context, {
  double width = 344,
  required Widget child,
}) => Container(
  width: width,
  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
  decoration: BoxDecoration(
    color: context.colors.surfaceContainerLowest,
    border: Border.all(color: context.colors.outlineVariant),
    borderRadius: BorderRadius.circular(StudioRadii.sm),
    boxShadow: StudioShadows.soft(context.colors.shadow),
  ),
  child: child,
);

final _liveContextDetail = AcpContextDetailViewState(
  used: BigInt.from(64500),
  size: BigInt.from(200000),
  previousUsed: BigInt.from(50000),
  isLive: true,
  updatedAt: DateTime(2026, 11, 23, 10, 42, 18),
);

final _liveThroughputDetail = AcpThroughputDetailViewState(
  tokensPerSecond: 82.0,
  estimatedOutputTokens: 410,
  responseMillis: 5000,
  isLive: true,
  updatedAt: DateTime(2026, 11, 23, 10, 42, 18),
);

final _retainedCostDetail = AcpCostDetailViewState(
  amount: 0.42,
  currency: 'USD',
  isLive: false,
  updatedAt: DateTime(2026, 11, 23, 10, 41, 52),
);

final _sessionDetail = AcpSessionDetailViewState(
  phase: AcpSessionStatusPhase.completed,
  isLive: true,
  serviceName: 'Claude Code Proxy',
  serverName: 'claude-agent-acp',
  serverVersion: 'v1.4.2',
  remoteSessionId: 'sess_claude_09af24c',
  lastStopReason: AcpStopReasonKind.endTurn,
  completedTurns: 4,
  updatedAt: DateTime(2026, 11, 23, 10, 42, 18),
  configItems: const [
    AcpConfigReadoutItem(
      label: '',
      value: 'Architect Mode',
      useModeFallbackLabel: true,
    ),
    AcpConfigReadoutItem(label: '模型', value: 'Claude Sonnet 4'),
    AcpConfigReadoutItem(label: '自动批准只读', value: '', booleanValue: false),
  ],
  capabilities: const [
    AcpCapabilityKind.image,
    AcpCapabilityKind.audio,
    AcpCapabilityKind.loadSession,
    AcpCapabilityKind.resumeSession,
    AcpCapabilityKind.listSessions,
  ],
);

final _overCapacityContextDetail = AcpContextDetailViewState(
  used: BigInt.from(215000),
  size: BigInt.from(200000),
  previousUsed: BigInt.from(220000),
  isLive: false,
  updatedAt: DateTime(2026, 11, 23, 9, 18, 5),
);

const _coldUnknownContextDetail = AcpContextDetailViewState(isLive: true);

@Preview(name: 'ACP 状态栏与独立上下文弹层', group: 'ACP 状态栏', size: Size(740, 460))
Widget acpStatusBarContextPopoverPreview() => _acpStatusPreviewShell(
  Builder(
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AcpStatusBarView(
          status: AcpConnectionStatusView(
            state: const AcpStatusBarViewState(
              phase: AcpSessionStatusPhase.completed,
              stopReason: AcpStopReasonKind.endTurn,
              provenance: AcpHistoryOriginKind.loadReplay,
            ),
            detailBuilder: (_) => AcpSessionDetailView(state: _sessionDetail),
          ),
          contextUsage: AcpContextUsageView(
            state: (
              used: BigInt.from(64500),
              size: BigInt.from(200000),
              isLive: true,
            ),
            detailBuilder: (_) =>
                AcpContextDetailView(state: _liveContextDetail),
          ),
          throughput: TokenThroughputReadout(
            estimated: true,
            tokensPerSecond: 82.0,
            detailBuilder: (_) =>
                AcpThroughputDetailView(state: _liveThroughputDetail),
          ),
          cost: AcpCostReadoutView(
            state: const (amount: 0.42, currency: 'USD'),
            detailBuilder: (_) => AcpCostDetailView(state: _retainedCostDetail),
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
          width: 364,
          child: AcpContextDetailView(state: _liveContextDetail),
        ),
      ],
    ),
  ),
);

@Preview(name: 'ACP 速度与费用独立弹层', group: 'ACP 状态栏', size: Size(720, 380))
Widget acpSpeedAndCostPopoversPreview() => _acpStatusPreviewShell(
  Builder(
    builder: (context) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _popoverCardFrame(
          context,
          width: 320,
          child: AcpThroughputDetailView(state: _liveThroughputDetail),
        ),
        const SizedBox(width: 16),
        _popoverCardFrame(
          context,
          width: 312,
          child: AcpCostDetailView(state: _retainedCostDetail),
        ),
      ],
    ),
  ),
);

@Preview(name: 'ACP 会话信息与配置独立弹层', group: 'ACP 状态栏', size: Size(440, 500))
Widget acpSessionDetailPopoverPreview() => _acpStatusPreviewShell(
  Builder(
    builder: (context) => _popoverCardFrame(
      context,
      width: 368,
      child: AcpSessionDetailView(state: _sessionDetail),
    ),
  ),
);

@Preview(
  name: 'ACP 窄窗超限与未知空态 · 1.3×字号',
  group: 'ACP 状态栏',
  size: Size(760, 560),
  textScaleFactor: 1.3,
)
Widget acpContextEdgeStatesStressPreview() => _acpStatusPreviewShell(
  Builder(
    builder: (context) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _popoverCardFrame(
          context,
          width: 304,
          child: AcpContextDetailView(state: _overCapacityContextDetail),
        ),
        const SizedBox(width: 16),
        _popoverCardFrame(
          context,
          width: 304,
          child: const AcpContextDetailView(state: _coldUnknownContextDetail),
        ),
      ],
    ),
  ),
);
