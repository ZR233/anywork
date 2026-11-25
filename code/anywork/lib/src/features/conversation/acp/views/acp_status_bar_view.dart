import 'package:anywork_client/models.dart'
    show formatRuntimeCostAmount, formatTokenCount, tokenCountUnknown;
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/status_detail_panel.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../../shared/studio_context_usage_ring.dart';
import '../../../../shared/studio_hover_detail.dart';
import '../../../status/status_bar_item.dart';
import '../state/acp_view_state.dart';

/// Single-row layout with independently observed slots.
class AcpStatusBarView extends StatelessWidget {
  const AcpStatusBarView({
    super.key,
    required this.status,
    this.workflow = const SizedBox.shrink(),
    this.plan = const SizedBox.shrink(),
    this.steps = const SizedBox.shrink(),
    required this.contextUsage,
    required this.cost,
    this.throughput = const SizedBox.shrink(),
    required this.externalHistory,
    this.sidebarToggle = const SizedBox.shrink(),
  });

  final Widget status;
  final Widget workflow;
  final Widget plan;
  final Widget steps;
  final Widget contextUsage;
  final Widget cost;
  final Widget throughput;
  final Widget externalHistory;
  final Widget sidebarToggle;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      border: Border(top: BorderSide(color: context.colors.outlineVariant)),
    ),
    child: SizedBox(
      width: double.infinity,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [status, workflow, plan, steps],
                  ),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      contextUsage,
                      throughput,
                      cost,
                      externalHistory,
                      sidebarToggle,
                    ],
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
  const AcpConnectionStatusView({
    super.key,
    required this.state,
    this.threadId,
    this.detailBuilder,
  });

  final AcpStatusBarViewState state;
  final String? threadId;
  final WidgetBuilder? detailBuilder;

  @override
  Widget build(BuildContext context) {
    final (dotColor, statusText) = _statusPresentation(context);
    final provenanceLabel = switch (state.provenance) {
      AcpHistoryOriginKind.loadReplay => context.l10n.acpProvenanceReplay,
      AcpHistoryOriginKind.resumedWithoutHistory =>
        context.l10n.acpProvenanceResumed,
      _ => null,
    };
    final textChild = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(
        statusText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.labelSmall,
      ),
    );
    final triggerRow = KeyedSubtree(
      key: threadId == null
          ? null
          : ValueKey(AcpViewKeyValues.status(threadId!)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            child: const SizedBox.square(dimension: 7),
          ),
          const SizedBox(width: 6),
          if (detailBuilder == null)
            Tooltip(message: statusText, child: textChild)
          else
            textChild,
          if (provenanceLabel != null) ...[
            const SizedBox(width: 6),
            StudioCompactChip(
              icon: Icons.history_rounded,
              label: provenanceLabel,
              maxWidth: 140,
            ),
          ],
        ],
      ),
    );
    if (detailBuilder == null) {
      return triggerRow;
    }
    return StudioHoverDetail(
      maxWidth: 368,
      semanticsLabel: statusText,
      detailBuilder: (context) {
        final detail = detailBuilder!(context);
        return threadId == null
            ? detail
            : KeyedSubtree(
                key: ValueKey(AcpViewKeyValues.statusDetail(threadId!)),
                child: detail,
              );
      },
      child: triggerRow,
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

  String _stopReasonLabel(BuildContext context) =>
      _stopReasonText(context.l10n, state.stopReason, state.stopReasonRaw);
}

class AcpContextUsageView extends StatelessWidget {
  const AcpContextUsageView({
    super.key,
    required this.state,
    this.threadId,
    this.detailBuilder,
  });

  final AcpContextUsageViewState? state;
  final String? threadId;
  final WidgetBuilder? detailBuilder;

  @override
  Widget build(BuildContext context) {
    final usage = state;
    if (usage == null) {
      return const SizedBox.shrink();
    }
    final size = usage.size;
    final used = usage.used;
    final hasCapacity = size != null && size > BigInt.zero;
    final double? progress = hasCapacity
        ? ((used ?? BigInt.zero).toDouble() / size.toDouble()).clamp(0.0, 1.0)
        : null;
    final Color progressColor;
    final String semanticsValue;
    if (!hasCapacity) {
      progressColor = context.colors.onSurfaceVariant;
      semanticsValue = used != null
          ? '${_formatCompactBigInt(used)} / $tokenCountUnknown'
          : context.l10n.acpContextNotReported;
    } else {
      final resolvedUsed = used ?? BigInt.zero;
      final percentageLabel = _contextPercentageLabel(resolvedUsed, size);
      progressColor = _contextProgressColor(
        context,
        used: resolvedUsed,
        size: size,
        clampedProgress: progress!,
      );
      semanticsValue =
          '${context.l10n.acpUsageReadout(resolvedUsed.toString(), size.toString())}, $percentageLabel';
    }

    final triggerKey = threadId == null
        ? null
        : ValueKey(AcpViewKeyValues.contextUsage(threadId!));
    final ring = KeyedSubtree(
      key: triggerKey,
      child: SizedBox(
        height: 26,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Center(
            child: ContextUsageRing(
              progress: progress,
              trackColor: context.colors.outlineVariant,
              progressColor: progressColor,
            ),
          ),
        ),
      ),
    );

    if (detailBuilder == null) {
      return Semantics(
        container: true,
        label: context.l10n.statusContextLabel,
        value: semanticsValue,
        child: ring,
      );
    }

    return StudioHoverDetail(
      maxWidth: 372,
      semanticsLabel: context.l10n.statusContextLabel,
      semanticsValue: semanticsValue,
      detailBuilder: (context) {
        final detail = detailBuilder!(context);
        return threadId == null
            ? detail
            : KeyedSubtree(
                key: ValueKey(AcpViewKeyValues.contextUsageDetail(threadId!)),
                child: detail,
              );
      },
      child: ring,
    );
  }
}

class AcpContextDetailView extends StatelessWidget {
  const AcpContextDetailView({super.key, required this.state});

  final AcpContextDetailViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = state.size;
    final used = state.used;
    final hasCapacity = size != null && size > BigInt.zero;
    final double? progress = hasCapacity
        ? ((used ?? BigInt.zero).toDouble() / size.toDouble()).clamp(0.0, 1.0)
        : null;
    final resolvedUsed = used ?? BigInt.zero;
    final progressColor = hasCapacity
        ? _contextProgressColor(
            context,
            used: resolvedUsed,
            size: size,
            clampedProgress: progress!,
          )
        : context.colors.onSurfaceVariant;
    final percentLabel = hasCapacity
        ? _contextPercentageLabel(resolvedUsed, size)
        : tokenCountUnknown;
    final emphasizePercent =
        hasCapacity && (resolvedUsed > size || progress! >= 0.95);
    final warningPercent =
        hasCapacity && !emphasizePercent && progress! >= 0.72;
    final previousUsed = state.previousUsed;
    final BigInt? delta =
        previousUsed != null && used != null && used != previousUsed
        ? used - previousUsed
        : null;

    final detailRows = <Widget>[
      if (used != null)
        StatusDetailRow(
          label: l10n.acpContextUsedLabel,
          value: _formatGroupedBigInt(used),
          valueMaxLines: 1,
        ),
      if (hasCapacity)
        StatusDetailRow(
          label: l10n.acpContextCapacityLabel,
          value: _formatGroupedBigInt(size),
          valueMaxLines: 1,
        ),
      if (delta != null)
        StatusDetailRow(
          label: l10n.acpContextDeltaLabel,
          value:
              '${delta > BigInt.zero ? '+' : '-'}${_formatGroupedBigInt(delta.abs())}',
          valueMaxLines: 1,
        ),
      if (state.updatedAt != null)
        StatusDetailRow(
          label: l10n.acpDetailUpdatedAt,
          value: _formatLocalTime(state.updatedAt!),
          valueMaxLines: 1,
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailHeaderRow(
          title: l10n.acpContextWindowTitle,
          badgeLabel: state.isLive
              ? l10n.acpSnapshotLiveBadge
              : l10n.acpSnapshotRetainedBadge,
          badgeTone: state.isLive ? StudioTone.success : StudioTone.neutral,
        ),
        const SizedBox(height: 8),
        if (hasCapacity)
          _HeroUsageNumbers(
            usedLabel: _formatCompactBigInt(resolvedUsed),
            sizeLabel: _formatCompactBigInt(size),
            percentLabel: percentLabel,
            percentColor: emphasizePercent
                ? context.colors.error
                : warningPercent
                ? context.statusColors.warning
                : context.colors.onSurface,
          )
        else if (used != null)
          _HeroUsageNumbers(
            usedLabel: _formatCompactBigInt(used),
            sizeLabel: tokenCountUnknown,
            percentLabel: tokenCountUnknown,
            percentColor: context.colors.onSurfaceVariant,
          )
        else
          Text(
            l10n.acpContextNotReported,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(StudioRadii.pill),
          child: LinearProgressIndicator(
            value: progress ?? 0,
            minHeight: 6,
            backgroundColor: context.colors.outlineVariant.withValues(
              alpha: 0.45,
            ),
            color: progress == null ? Colors.transparent : progressColor,
          ),
        ),
        if (hasCapacity || used != null || delta != null) ...[
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  hasCapacity
                      ? (resolvedUsed > size
                            ? l10n.acpContextOverCapacityLabel(
                                _formatCompactBigInt(resolvedUsed - size),
                              )
                            : l10n.acpContextRemainingLabel(
                                _formatCompactBigInt(size - resolvedUsed),
                              ))
                      : l10n.acpContextNotReported,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: hasCapacity && resolvedUsed > size
                        ? context.colors.error
                        : context.colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (delta != null) ...[
                const SizedBox(width: 8),
                _DeltaBadge(delta: delta),
              ],
            ],
          ),
        ],
        if (detailRows.isNotEmpty) ...[
          const StatusDetailDivider(),
          StatusDetailPanel(
            title: l10n.acpContextDetailSection,
            children: detailRows,
          ),
        ],
      ],
    );
  }
}

class AcpThroughputDetailView extends StatelessWidget {
  const AcpThroughputDetailView({super.key, required this.state});

  final AcpThroughputDetailViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final speed = state.tokensPerSecond;
    final hasSpeed = speed != null;
    final hasSample =
        state.estimatedOutputTokens != null &&
        state.responseMillis != null &&
        state.responseMillis! > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailHeaderRow(
          title: l10n.acpMetricSpeedTitle,
          badgeLabel: state.isLive
              ? l10n.acpSnapshotLiveBadge
              : l10n.acpSnapshotRetainedBadge,
          badgeTone: state.isLive ? StudioTone.success : StudioTone.neutral,
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            hasSpeed
                ? '≈ ${context.tokenThroughputLabel(speed)}'
                : tokenCountUnknown,
            maxLines: 1,
            style: context.text.titleLarge?.copyWith(
              fontSize: 22,
              height: 1.15,
              fontWeight: FontWeight.w600,
              color: hasSpeed
                  ? context.colors.onSurface
                  : context.colors.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.acpThroughputFormulaNote,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.3,
          ),
        ),
        const StatusDetailDivider(),
        StatusDetailPanel(
          title: l10n.acpThroughputDetailSection,
          children: [
            StatusDetailRow(
              label: l10n.acpThroughputTokensLabel,
              value: hasSample
                  ? '≈ ${_formatGroupedInt(state.estimatedOutputTokens!)}'
                  : tokenCountUnknown,
              valueMaxLines: 1,
            ),
            StatusDetailRow(
              label: l10n.acpThroughputDurationLabel,
              value: hasSample
                  ? _formatDuration(state.responseMillis!)
                  : tokenCountUnknown,
              valueMaxLines: 1,
            ),
            if (state.updatedAt != null)
              StatusDetailRow(
                label: l10n.acpDetailUpdatedAt,
                value: _formatLocalTime(state.updatedAt!),
                valueMaxLines: 1,
              ),
          ],
        ),
      ],
    );
  }
}

class AcpCostDetailView extends StatelessWidget {
  const AcpCostDetailView({super.key, required this.state});

  final AcpCostDetailViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailHeaderRow(
          title: l10n.acpMetricCostTitle,
          badgeLabel: state.isLive
              ? l10n.acpSnapshotLiveBadge
              : l10n.acpSnapshotRetainedBadge,
          badgeTone: state.isLive ? StudioTone.success : StudioTone.neutral,
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatRuntimeCostAmount(state.currency, state.amount),
            maxLines: 1,
            style: context.text.titleLarge?.copyWith(
              fontSize: 22,
              height: 1.15,
              fontWeight: FontWeight.w600,
              color: context.colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const StatusDetailDivider(),
        StatusDetailPanel(
          title: l10n.acpCostDetailSection,
          children: [
            StatusDetailRow(
              label: l10n.acpCostCurrencyLabel,
              value: state.currency,
              valueMaxLines: 1,
            ),
            StatusDetailRow(
              label: l10n.acpCostRawLabel,
              value: '${state.amount} ${state.currency}',
              valueMaxLines: 1,
            ),
            StatusDetailRow(
              label: l10n.acpCostScopeLabel,
              value: l10n.acpMetricCostSubtitle,
              valueMaxLines: 1,
            ),
            if (state.updatedAt != null)
              StatusDetailRow(
                label: l10n.acpDetailUpdatedAt,
                value: _formatLocalTime(state.updatedAt!),
                valueMaxLines: 1,
              ),
          ],
        ),
      ],
    );
  }
}

class AcpSessionDetailView extends StatelessWidget {
  const AcpSessionDetailView({super.key, required this.state});

  final AcpSessionDetailViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final primaryIdentity = _primaryIdentityLabel(state);
    final secondaryIdentity = _secondaryIdentityLabel(state);
    final stopReasonLabel =
        state.lastStopReason == null && state.lastStopReasonRaw == null
        ? null
        : _stopReasonText(l10n, state.lastStopReason, state.lastStopReasonRaw);

    final sessionRows = <Widget>[
      if (primaryIdentity != null || state.serverVersion != null)
        _ServerIdentityRow(
          primary: primaryIdentity,
          secondary: secondaryIdentity,
          version: state.serverVersion,
        ),
      for (final item in state.configItems)
        StatusDetailRow(
          label: item.useModeFallbackLabel
              ? l10n.acpConfigModeFallbackLabel
              : item.label,
          value: item.booleanValue == null
              ? item.value
              : (item.booleanValue!
                    ? l10n.acpConfigBooleanOn
                    : l10n.acpConfigBooleanOff),
          valueMaxLines: 1,
        ),
      if (state.completedTurns != null)
        StatusDetailRow(
          label: l10n.acpMetricTurnsTitle,
          value: l10n.acpMetricTurnsValue(state.completedTurns!),
          valueMaxLines: 1,
        ),
      if (stopReasonLabel != null)
        StatusDetailRow(
          label: l10n.acpDetailLastStopReason,
          value: stopReasonLabel,
          valueMaxLines: 1,
        ),
      if (state.updatedAt != null)
        StatusDetailRow(
          label: l10n.acpDetailUpdatedAt,
          value: _formatLocalTime(state.updatedAt!),
          valueMaxLines: 1,
        ),
    ];

    final hasCapabilities = state.capabilities.isNotEmpty;
    final hasRemoteId =
        state.remoteSessionId != null && state.remoteSessionId!.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailHeaderRow(
          title: l10n.acpSessionDetailTitle,
          badgeLabel: _phaseLabel(l10n, state.phase),
          badgeTone: _phaseTone(state.phase),
        ),
        if (sessionRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          StatusDetailPanel(
            title: l10n.acpDetailSessionSection,
            children: sessionRows,
          ),
        ],
        if (hasCapabilities || hasRemoteId) ...[
          const StatusDetailDivider(),
          StatusDetailPanel(
            title: l10n.acpDetailCapabilitiesSection,
            children: [
              if (hasCapabilities)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final capability in state.capabilities)
                      StudioCompactChip(
                        icon: _capabilityIcon(capability),
                        label: _capabilityLabel(l10n, capability),
                        maxWidth: 160,
                      ),
                  ],
                ),
              if (hasCapabilities && hasRemoteId) const SizedBox(height: 6),
              if (hasRemoteId)
                StatusDetailRow(
                  label: l10n.acpDetailSessionId,
                  value: state.remoteSessionId!,
                  valueMaxLines: 2,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DetailHeaderRow extends StatelessWidget {
  const _DetailHeaderRow({
    required this.title,
    required this.badgeLabel,
    required this.badgeTone,
  });

  final String title;
  final String badgeLabel;
  final StudioTone badgeTone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        StudioPill(label: badgeLabel, tone: badgeTone),
      ],
    );
  }
}

class _HeroUsageNumbers extends StatelessWidget {
  const _HeroUsageNumbers({
    required this.usedLabel,
    required this.sizeLabel,
    required this.percentLabel,
    required this.percentColor,
  });

  final String usedLabel;
  final String sizeLabel;
  final String percentLabel;
  final Color percentColor;

  @override
  Widget build(BuildContext context) {
    final amountStyle = context.text.titleLarge?.copyWith(
      fontSize: 22,
      height: 1.1,
      fontWeight: FontWeight.w600,
      color: context.colors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final percentStyle = context.text.titleMedium?.copyWith(
      fontSize: 19,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: percentColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$usedLabel / $sizeLabel',
              maxLines: 1,
              style: amountStyle,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(percentLabel, maxLines: 1, style: percentStyle),
      ],
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta});

  final BigInt delta;

  @override
  Widget build(BuildContext context) {
    final prefix = delta > BigInt.zero ? '+' : '-';
    final label = '$prefix${_formatCompactBigInt(delta.abs())}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(StudioRadii.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          maxLines: 1,
          style: context.text.labelSmall?.copyWith(
            color: delta > BigInt.zero
                ? context.colors.onSurface
                : context.statusColors.success,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

String? _primaryIdentityLabel(AcpSessionDetailViewState state) {
  final service = state.serviceName?.trim();
  if (service != null && service.isNotEmpty) return service;
  final server = state.serverName?.trim();
  return server != null && server.isNotEmpty ? server : null;
}

String? _secondaryIdentityLabel(AcpSessionDetailViewState state) {
  final service = state.serviceName?.trim();
  final server = state.serverName?.trim();
  if (service == null ||
      service.isEmpty ||
      server == null ||
      server.isEmpty ||
      service.toLowerCase() == server.toLowerCase()) {
    return null;
  }
  return server;
}

StudioTone _phaseTone(AcpSessionStatusPhase phase) {
  return switch (phase) {
    AcpSessionStatusPhase.connecting ||
    AcpSessionStatusPhase.stopping => StudioTone.warning,
    AcpSessionStatusPhase.ready ||
    AcpSessionStatusPhase.completed => StudioTone.success,
    AcpSessionStatusPhase.running => StudioTone.active,
    AcpSessionStatusPhase.disconnected => StudioTone.error,
    AcpSessionStatusPhase.ended => StudioTone.neutral,
  };
}

class _ServerIdentityRow extends StatelessWidget {
  const _ServerIdentityRow({this.primary, this.secondary, this.version});

  final String? primary;
  final String? secondary;
  final String? version;

  @override
  Widget build(BuildContext context) {
    final titleText = secondary == null
        ? primary
        : primary == null
        ? secondary
        : '$primary · $secondary';
    final versionLabel = version == null
        ? null
        : (version!.startsWith('v') || version!.startsWith('V')
              ? version!
              : 'v$version');
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (titleText != null)
            Expanded(
              child: Text(
                titleText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            )
          else
            const Spacer(),
          if (versionLabel != null) ...[
            const SizedBox(width: 8),
            StudioCompactChip(label: versionLabel, maxWidth: 110),
          ],
        ],
      ),
    );
  }
}

Color _contextProgressColor(
  BuildContext context, {
  required BigInt used,
  required BigInt size,
  required double clampedProgress,
}) {
  if (used > size || clampedProgress >= 0.95) {
    return context.colors.error;
  }
  if (clampedProgress >= 0.72) {
    return context.statusColors.warning;
  }
  return context.statusColors.activeIndicator;
}

/// Computes an overflow-safe rounded percentage label using 64-bit-safe `BigInt` math.
String _contextPercentageLabel(BigInt used, BigInt size) {
  final percentage = (used * BigInt.from(100) + size ~/ BigInt.from(2)) ~/ size;
  if (used > BigInt.zero && percentage == BigInt.zero) {
    return '<1%';
  }
  if (used < size && percentage >= BigInt.from(100)) {
    return '<100%';
  }
  return '$percentage%';
}

String _formatCompactBigInt(BigInt? value) {
  if (value == null) return tokenCountUnknown;
  final sign = value.isNegative ? '-' : '';
  final abs = value.abs();
  if (abs <= BigInt.from(999999999)) {
    return '$sign${formatTokenCount(abs.toInt())}';
  }
  final hundredths = (abs + BigInt.from(5000000)) ~/ BigInt.from(10000000);
  final whole = hundredths ~/ BigInt.from(100);
  final frac = hundredths.remainder(BigInt.from(100)).toInt();
  if (frac == 0) return '$sign${whole}b';
  if (frac % 10 == 0) return '$sign$whole.${frac ~/ 10}b';
  return '$sign$whole.${frac.toString().padLeft(2, '0')}b';
}

String _formatGroupedInt(int value) => _formatGroupedBigInt(BigInt.from(value));

String _formatGroupedBigInt(BigInt value) {
  final sign = value.isNegative ? '-' : '';
  final digits = value.abs().toString();
  if (digits.length <= 3) return '$sign$digits';
  final buffer = StringBuffer(sign);
  final firstGroup = digits.length % 3;
  var index = firstGroup == 0 ? 3 : firstGroup;
  buffer.write(digits.substring(0, index));
  while (index < digits.length) {
    buffer
      ..write(',')
      ..write(digits.substring(index, index + 3));
    index += 3;
  }
  return buffer.toString();
}

String _formatDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  if (ms < 10000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final seconds = (ms / 1000).round();
  if (seconds < 60) return '${seconds}s';
  final mins = seconds ~/ 60;
  final rem = seconds % 60;
  return rem == 0 ? '${mins}m' : '${mins}m ${rem}s';
}

String _formatLocalTime(DateTime timestamp) {
  final local = timestamp.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final ss = local.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

String _phaseLabel(AppLocalizations l10n, AcpSessionStatusPhase phase) {
  return switch (phase) {
    AcpSessionStatusPhase.connecting => l10n.acpStatusConnecting,
    AcpSessionStatusPhase.ready => l10n.acpStatusReady,
    AcpSessionStatusPhase.running => l10n.acpStatusRunning,
    AcpSessionStatusPhase.stopping => l10n.acpStatusStopping,
    AcpSessionStatusPhase.completed => l10n.acpStopReasonEndTurn,
    AcpSessionStatusPhase.disconnected => l10n.acpStatusDisconnected,
    AcpSessionStatusPhase.ended => l10n.acpStatusObservationEnded,
  };
}

String _stopReasonText(
  AppLocalizations l10n,
  AcpStopReasonKind? kind,
  String? raw,
) {
  return switch (kind) {
    AcpStopReasonKind.endTurn => l10n.acpStopReasonEndTurn,
    AcpStopReasonKind.maxTokens => l10n.acpStopReasonMaxTokens,
    AcpStopReasonKind.maxTurnRequests => l10n.acpStopReasonMaxTurnRequests,
    AcpStopReasonKind.refusal => l10n.acpStopReasonRefusal,
    AcpStopReasonKind.cancelled => l10n.acpStopReasonCancelled,
    AcpStopReasonKind.other || null => raw ?? l10n.acpStopReasonEndTurn,
  };
}

IconData _capabilityIcon(AcpCapabilityKind capability) {
  return switch (capability) {
    AcpCapabilityKind.image => Icons.image_outlined,
    AcpCapabilityKind.audio => Icons.graphic_eq_rounded,
    AcpCapabilityKind.embeddedContext => Icons.attach_file_rounded,
    AcpCapabilityKind.loadSession => Icons.history_rounded,
    AcpCapabilityKind.resumeSession => Icons.play_circle_outline_rounded,
    AcpCapabilityKind.listSessions => Icons.list_alt_rounded,
  };
}

String _capabilityLabel(AppLocalizations l10n, AcpCapabilityKind capability) {
  return switch (capability) {
    AcpCapabilityKind.image => l10n.acpCapabilityImage,
    AcpCapabilityKind.audio => l10n.acpCapabilityAudio,
    AcpCapabilityKind.embeddedContext => l10n.acpCapabilityEmbeddedContext,
    AcpCapabilityKind.loadSession => l10n.acpCapabilityLoadSession,
    AcpCapabilityKind.resumeSession => l10n.acpCapabilityResumeSession,
    AcpCapabilityKind.listSessions => l10n.acpCapabilityListSessions,
  };
}

class AcpCostReadoutView extends StatelessWidget {
  const AcpCostReadoutView({
    super.key,
    required this.state,
    this.threadId,
    this.detailBuilder,
  });

  final AcpCostViewState? state;
  final String? threadId;
  final WidgetBuilder? detailBuilder;

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
      triggerKey: threadId == null
          ? null
          : ValueKey(AcpViewKeyValues.cost(threadId!)),
      detailKey: threadId == null
          ? null
          : ValueKey(AcpViewKeyValues.costDetail(threadId!)),
      detailMaxWidth: 320,
      detailBuilder: detailBuilder,
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
