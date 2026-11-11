import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../status/status_bar_item.dart';
import '../state/acp_view_state.dart';

/// Pure `38px` bottom status bar for ACP sessions, aligned visually and
/// structurally with Native `ThreadStatusBar`.
class AcpStatusBarView extends StatelessWidget {
  const AcpStatusBarView({
    super.key,
    required this.threadId,
    required this.state,
    required this.externalHistoryButton,
    required this.onOpenExternalHistory,
  });

  final String threadId;
  final AcpStatusBarViewState state;
  final AcpExternalHistoryButtonState externalHistoryButton;
  final VoidCallback? onOpenExternalHistory;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final (dotColor, statusText) = _statusPresentation(context);
    final provenanceLabel = switch (state.provenance) {
      AcpHistoryOriginKind.loadReplay => l10n.acpProvenanceReplay,
      AcpHistoryOriginKind.resumedWithoutHistory => l10n.acpProvenanceResumed,
      _ => null,
    };
    final historyEnabled =
        externalHistoryButton.status ==
            AcpExternalHistoryAvailability.available &&
        onOpenExternalHistory != null;
    final historyTooltip = switch (externalHistoryButton.status) {
      AcpExternalHistoryAvailability.loading => l10n.acpHistoryOwnerLoading,
      AcpExternalHistoryAvailability.noOwner => l10n.acpHistoryNoOwner,
      AcpExternalHistoryAvailability.unknownCapability =>
        l10n.acpHistoryUnknownCapability,
      AcpExternalHistoryAvailability.unsupported => l10n.acpHistoryUnsupported,
      AcpExternalHistoryAvailability.notReady => l10n.acpHistoryNotReady,
      AcpExternalHistoryAvailability.available => l10n.acpHistoryOpenPanel,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SizedBox(
        height: 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 7),
              ),
              const SizedBox(width: 6),
              StatusBarItem(
                label: statusText,
                tooltip: statusText,
                maxWidth: 220,
              ),
              if (provenanceLabel != null) ...[
                const SizedBox(width: 6),
                StudioCompactChip(
                  icon: Icons.history_rounded,
                  label: provenanceLabel,
                  maxWidth: 140,
                ),
              ],
              const Spacer(),
              if (state.usage case final usage?) ...[
                StatusBarItem(
                  icon: Icons.data_usage_rounded,
                  label: l10n.acpUsageReadout(
                    usage.usedFormatted,
                    usage.sizeFormatted,
                  ),
                  tooltip: usage.costLabel == null
                      ? l10n.acpUsageReadout(
                          usage.usedFormatted,
                          usage.sizeFormatted,
                        )
                      : '${l10n.acpUsageReadout(usage.usedFormatted, usage.sizeFormatted)} · ${usage.costLabel}',
                  maxWidth: 200,
                ),
                const SizedBox(width: 6),
              ],
              Tooltip(
                message: historyTooltip,
                child: TextButton.icon(
                  key: ValueKey(
                    AcpViewKeyValues.externalHistoryButton(threadId),
                  ),
                  onPressed: historyEnabled ? onOpenExternalHistory : null,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.history_rounded, size: 15),
                  label: Text(
                    l10n.acpHistoryButton,
                    style: context.text.labelSmall?.copyWith(
                      color: historyEnabled
                          ? colors.onSurface
                          : colors.onSurfaceVariant.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (Color, String) _statusPresentation(BuildContext context) {
    final l10n = context.l10n;
    return switch (state.phase) {
      AcpSessionStatusPhase.connecting => (
        StudioTone.warning.indicator(context),
        l10n.acpStatusConnecting,
      ),
      AcpSessionStatusPhase.ready => (
        StudioTone.success.indicator(context),
        l10n.acpStatusReady,
      ),
      AcpSessionStatusPhase.running => (
        context.colors.primary,
        l10n.acpStatusRunning,
      ),
      AcpSessionStatusPhase.stopping => (
        StudioTone.warning.indicator(context),
        l10n.acpStatusStopping,
      ),
      AcpSessionStatusPhase.completed => (
        StudioTone.success.indicator(context),
        l10n.acpStatusCompleted(_stopReasonLabel(context)),
      ),
      AcpSessionStatusPhase.disconnected => (
        context.colors.error,
        l10n.acpStatusDisconnected,
      ),
      AcpSessionStatusPhase.ended => (
        context.colors.onSurfaceVariant,
        l10n.acpStatusObservationEnded,
      ),
    };
  }

  String _stopReasonLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (state.stopReason) {
      AcpStopReasonKind.endTurn => l10n.acpStopReasonEndTurn,
      AcpStopReasonKind.maxTokens => l10n.acpStopReasonMaxTokens,
      AcpStopReasonKind.maxTurnRequests => l10n.acpStopReasonMaxTurnRequests,
      AcpStopReasonKind.refusal => l10n.acpStopReasonRefusal,
      AcpStopReasonKind.cancelled => l10n.acpStopReasonCancelled,
      AcpStopReasonKind.other ||
      null => state.stopReasonRaw ?? l10n.acpStopReasonEndTurn,
    };
  }
}
