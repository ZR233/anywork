import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../../shared/studio_context_usage_ring.dart';
import '../../../status/status_bar_item.dart';
import '../state/acp_view_state.dart';

/// Single-row layout with independently observed slots.
class AcpStatusBarView extends StatelessWidget {
  const AcpStatusBarView({
    super.key,
    required this.status,
    required this.contextUsage,
    required this.cost,
    this.throughput = const SizedBox.shrink(),
    required this.externalHistory,
  });

  final Widget status;
  final Widget contextUsage;
  final Widget cost;
  final Widget throughput;
  final Widget externalHistory;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      border: Border(top: BorderSide(color: context.colors.outlineVariant)),
    ),
    child: SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  status,
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [contextUsage, throughput, cost, externalHistory],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AcpConnectionStatusView extends StatelessWidget {
  const AcpConnectionStatusView({super.key, required this.state});

  final AcpStatusBarViewState state;

  @override
  Widget build(BuildContext context) {
    final (dotColor, statusText) = _statusPresentation(context);
    final provenanceLabel = switch (state.provenance) {
      AcpHistoryOriginKind.loadReplay => context.l10n.acpProvenanceReplay,
      AcpHistoryOriginKind.resumedWithoutHistory =>
        context.l10n.acpProvenanceResumed,
      _ => null,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 7),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: statusText,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall,
            ),
          ),
        ),
        if (provenanceLabel != null) ...[
          const SizedBox(width: 6),
          StudioCompactChip(
            icon: Icons.history_rounded,
            label: provenanceLabel,
            maxWidth: 140,
          ),
        ],
      ],
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

class AcpContextUsageView extends StatelessWidget {
  const AcpContextUsageView({super.key, required this.state});

  final AcpContextUsageViewState? state;

  @override
  Widget build(BuildContext context) {
    final usage = state;
    if (usage == null || usage.size <= BigInt.zero) {
      return const SizedBox.shrink();
    }
    final ratio = usage.used.toDouble() / usage.size.toDouble();
    // ACP uses unsigned 64-bit token counts; avoid integer overflow when
    // calculating the rounded accessibility percentage.
    final percentage =
        (usage.used * BigInt.from(100) + usage.size ~/ BigInt.from(2)) ~/
        usage.size;
    final percentageLabel =
        usage.used > BigInt.zero && percentage == BigInt.zero
        ? '<1'
        : usage.used < usage.size && percentage >= BigInt.from(100)
        ? '<100'
        : '$percentage';
    return Semantics(
      label: context.l10n.statusContextLabel,
      value:
          '${context.l10n.acpUsageReadout(usage.used.toString(), usage.size.toString())}, $percentageLabel%',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: ContextUsageRing(
          progress: ratio.clamp(0.0, 1.0),
          trackColor: context.colors.outlineVariant,
          progressColor: context.colors.primary,
        ),
      ),
    );
  }
}

class AcpCostReadoutView extends StatelessWidget {
  const AcpCostReadoutView({super.key, required this.state});

  final AcpCostViewState? state;

  @override
  Widget build(BuildContext context) {
    final cost = state;
    if (cost == null) {
      return const SizedBox.shrink();
    }
    final text = '${cost.amount} ${cost.currency}';
    return StatusBarItem(
      icon: Icons.payments_outlined,
      label: '${context.l10n.statusCost}: $text',
      text: text,
    );
  }
}

class AcpExternalHistoryButtonView extends StatelessWidget {
  const AcpExternalHistoryButtonView({
    super.key,
    required this.threadId,
    required this.state,
    required this.onOpen,
  });

  final String threadId;
  final AcpExternalHistoryButtonState state;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled =
        state.status == AcpExternalHistoryAvailability.available &&
        onOpen != null;
    final tooltip = switch (state.status) {
      AcpExternalHistoryAvailability.loading => l10n.acpHistoryOwnerLoading,
      AcpExternalHistoryAvailability.noOwner => l10n.acpHistoryNoOwner,
      AcpExternalHistoryAvailability.unknownCapability =>
        l10n.acpHistoryUnknownCapability,
      AcpExternalHistoryAvailability.unsupported => l10n.acpHistoryUnsupported,
      AcpExternalHistoryAvailability.notReady => l10n.acpHistoryNotReady,
      AcpExternalHistoryAvailability.available => l10n.acpHistoryOpenPanel,
    };
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        key: ValueKey(AcpViewKeyValues.externalHistoryButton(threadId)),
        onPressed: enabled ? onOpen : null,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.history_rounded, size: 15),
        label: Text(
          l10n.acpHistoryButton,
          style: context.text.labelSmall?.copyWith(
            color: enabled
                ? context.colors.onSurface
                : context.colors.onSurfaceVariant.withValues(alpha: 0.55),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
