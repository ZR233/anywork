import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/timeline_outcome_presentation.dart';
import 'timeline_activity_clock.dart';

enum TimelineErrorTone { error, warning }

/// Directly surfaces readable failure or budget-limit messages in the timeline
/// while keeping technical metadata and raw envelopes neatly tucked away.
class TimelineErrorCard extends StatefulWidget {
  const TimelineErrorCard({
    super.key,
    required this.itemId,
    required this.tone,
    required this.summary,
    this.rawRecord,
    this.initiallyDetailsExpanded = false,
    this.onCopyMessage,
  });

  factory TimelineErrorCard.failure({
    Key? key,
    required String itemId,
    required TimelineOutcomeSummary summary,
    Widget? rawRecord,
    bool initiallyDetailsExpanded = false,
    ValueChanged<String>? onCopyMessage,
  }) => TimelineErrorCard(
    key: key,
    itemId: itemId,
    tone: TimelineErrorTone.error,
    summary: summary,
    rawRecord: rawRecord,
    initiallyDetailsExpanded: initiallyDetailsExpanded,
    onCopyMessage: onCopyMessage,
  );

  factory TimelineErrorCard.budgetLimited({
    Key? key,
    required String itemId,
    required TimelineOutcomeSummary summary,
    Widget? rawRecord,
    bool initiallyDetailsExpanded = false,
    ValueChanged<String>? onCopyMessage,
  }) => TimelineErrorCard(
    key: key,
    itemId: itemId,
    tone: TimelineErrorTone.warning,
    summary: summary,
    rawRecord: rawRecord,
    initiallyDetailsExpanded: initiallyDetailsExpanded,
    onCopyMessage: onCopyMessage,
  );

  final String itemId;
  final TimelineErrorTone tone;
  final TimelineOutcomeSummary summary;
  final Widget? rawRecord;
  final bool initiallyDetailsExpanded;
  final ValueChanged<String>? onCopyMessage;

  @override
  State<TimelineErrorCard> createState() => _TimelineErrorCardState();
}

class _TimelineErrorCardState extends State<TimelineErrorCard> {
  static const int _collapseCharThreshold = 500;
  static const int _collapseLineThreshold = 8;

  late bool _detailsExpanded = widget.initiallyDetailsExpanded;
  bool _messageExpanded = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _copy(String text) {
    if (widget.onCopyMessage != null) {
      widget.onCopyMessage!(text);
    } else {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
    }
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  bool _isLongMessage(String text) =>
      text.length > _collapseCharThreshold ||
      '\n'.allMatches(text).length >= _collapseLineThreshold;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusColors = context.statusColors;
    final l10n = context.l10n;

    final accent = switch (widget.tone) {
      TimelineErrorTone.error => colors.error,
      TimelineErrorTone.warning => statusColors.warning,
    };
    final containerTint = switch (widget.tone) {
      TimelineErrorTone.error => colors.errorContainer,
      TimelineErrorTone.warning => statusColors.warningContainer,
    };
    final background = Color.alphaBlend(
      containerTint.withValues(alpha: 0.45),
      colors.surfaceContainerLowest,
    );
    final borderColor = accent.withValues(alpha: 0.24);
    final dividerColor = accent.withValues(alpha: 0.14);

    final failure = widget.summary.failure;
    final budget = widget.summary.budget;
    final isBudget = widget.tone == TimelineErrorTone.warning;
    final title = isBudget
        ? l10n.timelineTurnBudgetLimited
        : l10n.timelineTurnFailed;
    final icon = isBudget ? Icons.speed_rounded : Icons.error_outline_rounded;
    final durationSeconds = widget.summary.durationSeconds;

    final primaryMessage = isBudget
        ? (budget?.limitKind != null
              ? l10n.timelineBudgetLimitMessage(
                  localizedBudgetLimitKind(context, budget!.limitKind!),
                )
              : l10n.timelineTurnBudgetLimited)
        : failure?.message;

    final copyText = isBudget
        ? [
            ?primaryMessage,
            if (budget?.rolloverError case final err?)
              l10n.timelineBudgetRolloverFailed(err),
          ].join('\n')
        : failure?.message;

    final badges = _buildHeaderBadges(
      context,
      failure: failure,
      budget: budget,
    );
    final detailRows = _buildDetailRows(
      context,
      failure: failure,
      budget: budget,
      durationSeconds: durationSeconds,
    );
    final hasFooter = detailRows.isNotEmpty || widget.rawRecord != null;

    final cardContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 10, 10),
          child: SelectionContainer.disabled(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 17, color: accent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                title,
                                style: context.text.titleSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        ...badges,
                      ],
                    ),
                  ),
                ),
                if (durationSeconds != null ||
                    (copyText != null && copyText.isNotEmpty)) ...[
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (durationSeconds != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 4),
                          child: Text(
                            activityDurationLabel(context, durationSeconds),
                            style: context.text.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant.withValues(
                                alpha: 0.85,
                              ),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      if (copyText != null && copyText.isNotEmpty)
                        Tooltip(
                          message: _copied
                              ? l10n.timelineOutcomeCopied
                              : l10n.timelineOutcomeCopyMessage,
                          child: IconButton(
                            key: ValueKey(
                              'timeline-error-copy:${widget.itemId}',
                            ),
                            onPressed: () => _copy(copyText),
                            style: IconButton.styleFrom(
                              foregroundColor: _copied
                                  ? statusColors.success
                                  : colors.onSurfaceVariant,
                              minimumSize: const Size.square(28),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.standard,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: const CircleBorder(),
                            ),
                            icon: Icon(
                              _copied
                                  ? Icons.check_rounded
                                  : Icons.copy_rounded,
                              size: 14,
                              semanticLabel: _copied
                                  ? l10n.timelineOutcomeCopied
                                  : l10n.timelineOutcomeCopyMessage,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            16,
            0,
            16,
            hasFooter ? 12 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMessageBody(
                context,
                message: primaryMessage,
                isBudget: isBudget,
              ),
              if (isBudget && budget != null) ...[
                _buildBudgetMetrics(context, budget),
                if (budget.rolloverKind == 'succeeded')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.compress_outlined,
                          size: 14,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n.timelineBudgetRolloverSucceeded,
                            style: context.text.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (budget.rolloverKind == 'failed' &&
                    budget.rolloverError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.timelineBudgetRolloverFailed(budget.rolloverError!),
                      style: context.text.bodySmall?.copyWith(
                        color: colors.error,
                        height: 1.45,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (hasFooter) ...[
          Divider(height: 1, thickness: 1, color: dividerColor),
          SelectionContainer.disabled(
            child: InkWell(
              key: ValueKey('timeline-error-details-toggle:${widget.itemId}'),
              onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 14,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.timelineOutcomeTechnicalDetails,
                        style: context.text.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(
                      _detailsExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                      size: 16,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_detailsExpanded)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (detailRows.isNotEmpty)
                    _DetailKeyValueList(rows: detailRows),
                  if (widget.rawRecord != null) ...[
                    if (detailRows.isNotEmpty) const SizedBox(height: 6),
                    widget.rawRecord!,
                  ],
                ],
              ),
            ),
        ],
      ],
    );

    final framed = DecoratedBox(
      key: ValueKey('timeline-error-card:${widget.itemId}'),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          children: [
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: 3.5,
              child: ColoredBox(color: accent.withValues(alpha: 0.85)),
            ),
            cardContent,
          ],
        ),
      ),
    );

    return SelectionContainer.maybeOf(context) == null
        ? SelectionArea(child: framed)
        : framed;
  }

  Widget _buildMessageBody(
    BuildContext context, {
    required String? message,
    required bool isBudget,
  }) {
    final l10n = context.l10n;
    final colors = context.colors;
    if (message == null || message.isEmpty) {
      return Text(
        l10n.timelineOutcomeNoMessage,
        style: context.text.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
          height: 1.5,
        ),
      );
    }
    final long = !isBudget && _isLongMessage(message);
    final collapsed = long && !_messageExpanded;
    final messageStyle = context.text.bodyMedium?.copyWith(
      color: colors.onSurface,
      height: 1.55,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          maxLines: collapsed ? 6 : null,
          overflow: collapsed ? TextOverflow.ellipsis : null,
          style: messageStyle,
        ),
        if (long)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectionContainer.disabled(
              child: TextButton(
                key: ValueKey('timeline-error-expand-message:${widget.itemId}'),
                onPressed: () =>
                    setState(() => _messageExpanded = !_messageExpanded),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _messageExpanded
                      ? l10n.timelineOutcomeShowLess
                      : l10n.timelineOutcomeShowMore,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildHeaderBadges(
    BuildContext context, {
    required TimelineFailureDetails? failure,
    required TimelineBudgetLimitDetails? budget,
  }) {
    final colors = context.colors;
    final statusColors = context.statusColors;
    final l10n = context.l10n;
    final badges = <Widget>[];

    if (failure != null) {
      if (failure.category case final category?) {
        badges.add(
          _TagChip(
            label: localizedFailureCategory(context, category),
            foreground: colors.onErrorContainer,
            background: colors.errorContainer.withValues(alpha: 0.72),
            borderColor: colors.error.withValues(alpha: 0.18),
          ),
        );
      }
      if (failure.hasVisibleProviderKind) {
        badges.add(
          _TagChip(
            label: localizedProviderFailureKind(context, failure.providerKind!),
            foreground: colors.onSurfaceVariant,
            background: colors.surfaceContainerLow,
            borderColor: colors.outlineVariant,
          ),
        );
      }
      if (failure.code case final code?) {
        badges.add(
          _TagChip(
            label: code,
            monospace: true,
            foreground: colors.onSurfaceVariant,
            background: colors.surfaceContainerLow,
            borderColor: colors.outlineVariant,
          ),
        );
      }
      if (failure.httpStatus case final status?) {
        badges.add(
          _TagChip(
            label: 'HTTP $status',
            monospace: true,
            foreground: colors.onSurfaceVariant,
            background: colors.surfaceContainerLow,
            borderColor: colors.outlineVariant,
          ),
        );
      }
      if (failure.isRetryable) {
        final retrySeconds = failure.retryAfterSeconds;
        badges.add(
          _TagChip(
            icon: Icons.refresh_rounded,
            label: retrySeconds != null
                ? l10n.timelineRetryAfterSeconds(retrySeconds)
                : l10n.timelineRetryableHint,
            foreground: statusColors.warning,
            background: statusColors.warningContainer.withValues(alpha: 0.72),
            borderColor: statusColors.warning.withValues(alpha: 0.22),
          ),
        );
      }
    }

    if (budget != null && budget.limitKind != null) {
      badges.add(
        _TagChip(
          label: localizedBudgetLimitKind(context, budget.limitKind!),
          foreground: statusColors.warning,
          background: statusColors.warningContainer.withValues(alpha: 0.72),
          borderColor: statusColors.warning.withValues(alpha: 0.22),
        ),
      );
    }

    return badges;
  }

  Widget _buildBudgetMetrics(
    BuildContext context,
    TimelineBudgetLimitDetails budget,
  ) {
    final l10n = context.l10n;
    final colors = context.colors;
    final metrics = <String>[
      if (budget.modelSteps != null)
        l10n.timelineBudgetUsageModelSteps(budget.modelSteps!),
      if (budget.toolCalls != null && budget.toolCalls! > 0)
        l10n.timelineBudgetUsageToolCalls(budget.toolCalls!),
      if (budget.waitCalls != null && budget.waitCalls! > 0)
        l10n.timelineBudgetUsageWaitCalls(budget.waitCalls!),
    ];
    if (metrics.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final metric in metrics)
            _TagChip(
              label: metric,
              foreground: colors.onSurfaceVariant,
              background: colors.surfaceContainerLow,
              borderColor: colors.outlineVariant,
            ),
        ],
      ),
    );
  }

  List<({String label, String value, bool monospace})> _buildDetailRows(
    BuildContext context, {
    required TimelineFailureDetails? failure,
    required TimelineBudgetLimitDetails? budget,
    required int? durationSeconds,
  }) {
    final l10n = context.l10n;
    final rows = <({String label, String value, bool monospace})>[];

    if (failure != null) {
      if (failure.category case final category?) {
        rows.add((
          label: l10n.timelineDetailCategory,
          value: '${localizedFailureCategory(context, category)} ($category)',
          monospace: false,
        ));
      }
      if (failure.hasVisibleProviderKind) {
        final kind = failure.providerKind!;
        rows.add((
          label: l10n.timelineDetailProviderKind,
          value: '${localizedProviderFailureKind(context, kind)} ($kind)',
          monospace: false,
        ));
      }
      if (failure.code case final code?) {
        rows.add((
          label: l10n.timelineDetailCode,
          value: code,
          monospace: true,
        ));
      }
      if (failure.httpStatus case final status?) {
        rows.add((
          label: l10n.timelineDetailHttpStatus,
          value: '$status',
          monospace: true,
        ));
      }
      if (failure.retryKind case final retryKind?) {
        final retryText = retryKind == 'retryable'
            ? (failure.retryAfterSeconds != null
                  ? l10n.timelineRetryAfterSeconds(failure.retryAfterSeconds!)
                  : l10n.timelineRetryableHint)
            : (retryKind == 'permanent'
                  ? l10n.timelineRetryPermanent
                  : retryKind);
        rows.add((
          label: l10n.timelineDetailRetry,
          value: retryText,
          monospace: false,
        ));
      }
    }

    if (budget != null) {
      if (budget.limitKind case final limitKind?) {
        rows.add((
          label: l10n.timelineDetailBudgetKind,
          value: '${localizedBudgetLimitKind(context, limitKind)} ($limitKind)',
          monospace: false,
        ));
      }
      if (budget.rolloverKind case final rolloverKind?) {
        final rolloverText = switch (rolloverKind) {
          'succeeded' => l10n.timelineBudgetRolloverSucceeded,
          'failed' when budget.rolloverError != null =>
            l10n.timelineBudgetRolloverFailed(budget.rolloverError!),
          _ => rolloverKind,
        };
        rows.add((
          label: l10n.timelineDetailRollover,
          value: rolloverText,
          monospace: false,
        ));
      }
    }

    if (durationSeconds != null) {
      rows.add((
        label: l10n.timelineDetailDuration,
        value: activityDurationLabel(context, durationSeconds),
        monospace: false,
      ));
    }

    return rows;
  }
}

/// Compact structured outcome view for non-card disclosures (cancelled turns,
/// failed agents, failed inferences, or thinking blocks).
class TimelineOutcomeNotice extends StatelessWidget {
  const TimelineOutcomeNotice({
    super.key,
    required this.summary,
    this.isIssue = false,
  });

  final TimelineOutcomeSummary summary;
  final bool isIssue;

  @override
  Widget build(BuildContext context) {
    if (summary.isTerminalNormal) return const SizedBox.shrink();
    final colors = context.colors;
    final l10n = context.l10n;
    final failure = summary.failure;
    final cancellation = summary.cancellation;
    final primaryText = summary.primaryText;

    final chips = <Widget>[
      if (failure?.category case final category?)
        _TagChip(
          label: localizedFailureCategory(context, category),
          foreground: isIssue
              ? colors.onErrorContainer
              : colors.onSurfaceVariant,
          background: isIssue
              ? colors.errorContainer.withValues(alpha: 0.72)
              : colors.surfaceContainerLow,
          borderColor: isIssue
              ? colors.error.withValues(alpha: 0.18)
              : colors.outlineVariant,
        ),
      if (failure?.code case final code?)
        _TagChip(
          label: code,
          monospace: true,
          foreground: colors.onSurfaceVariant,
          background: colors.surfaceContainerLow,
          borderColor: colors.outlineVariant,
        ),
      if (failure?.httpStatus case final status?)
        _TagChip(
          label: 'HTTP $status',
          monospace: true,
          foreground: colors.onSurfaceVariant,
          background: colors.surfaceContainerLow,
          borderColor: colors.outlineVariant,
        ),
      if (cancellation?.causeKind case final causeKind?
          when causeKind != 'unspecified')
        _TagChip(
          label: localizedTurnCancellationCause(
            context,
            causeKind,
            targetTurnId: cancellation?.targetTurnId,
          ),
          foreground: colors.onSurfaceVariant,
          background: colors.surfaceContainerLow,
          borderColor: colors.outlineVariant,
        ),
    ];

    final statusLabel = summary.kind == null
        ? null
        : localizedOutcomeStatus(context, summary.kind!);

    if ((primaryText == null || primaryText.isEmpty) &&
        chips.isEmpty &&
        statusLabel == null) {
      return const SizedBox.shrink();
    }

    final borderColor = isIssue
        ? colors.error.withValues(alpha: 0.45)
        : colors.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isIssue
              ? Color.alphaBlend(
                  colors.errorContainer.withValues(alpha: 0.35),
                  colors.surfaceContainerLowest,
                )
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (chips.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: (primaryText != null && primaryText.isNotEmpty)
                        ? 8
                        : 0,
                  ),
                  child: Wrap(spacing: 6, runSpacing: 4, children: chips),
                ),
              if (primaryText != null && primaryText.isNotEmpty)
                Text(
                  primaryText,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurface,
                    height: 1.5,
                  ),
                )
              else if (statusLabel != null && chips.isEmpty)
                Text(
                  statusLabel,
                  style: context.text.bodySmall?.copyWith(
                    color: isIssue ? colors.error : colors.onSurfaceVariant,
                  ),
                ),
              if (summary.durationSeconds case final seconds?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${l10n.timelineDetailDuration}: ${activityDurationLabel(context, seconds)}',
                    style: context.text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailKeyValueList extends StatelessWidget {
  const _DetailKeyValueList({required this.rows});

  final List<({String label, String value, bool monospace})> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelStyle = context.text.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
      height: 1.4,
    );
    final valueStyle = context.text.bodySmall?.copyWith(
      color: colors.onSurface,
      height: 1.4,
    );
    final monoStyle = valueStyle?.copyWith(fontFamily: studioCodeFontFamily);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(rows[index].label, style: labelStyle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rows[index].value,
                      style: rows[index].monospace ? monoStyle : valueStyle,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.foreground,
    required this.background,
    required this.borderColor,
    this.icon,
    this.monospace = false,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color borderColor;
  final IconData? icon;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(StudioRadii.xs),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  color: foreground,
                  fontFamily: monospace ? studioCodeFontFamily : null,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String localizedFailureCategory(BuildContext context, String category) {
  final l10n = context.l10n;
  return switch (category) {
    'provider' => l10n.timelineFailureCategoryProvider,
    'providerCapacity' => l10n.timelineFailureCategoryProviderCapacity,
    'tool' => l10n.timelineFailureCategoryTool,
    'validation' => l10n.timelineFailureCategoryValidation,
    'protocol' => l10n.timelineFailureCategoryProtocol,
    'internal' => l10n.timelineFailureCategoryInternal,
    _ => category,
  };
}

String localizedProviderFailureKind(BuildContext context, String kind) {
  final l10n = context.l10n;
  return switch (kind) {
    'authentication' => l10n.timelineProviderKindAuth,
    'authorization' => l10n.timelineProviderKindAuthz,
    'capacity' => l10n.timelineProviderKindCapacity,
    'configuration' => l10n.timelineProviderKindConfig,
    'transport' => l10n.timelineProviderKindTransport,
    'protocol' => l10n.timelineProviderKindProtocol,
    _ => kind,
  };
}

String localizedBudgetLimitKind(BuildContext context, String kind) {
  final l10n = context.l10n;
  return switch (kind) {
    'modelStep' => l10n.timelineBudgetLimitModelStep,
    'toolCall' => l10n.timelineBudgetLimitToolCall,
    'wait' => l10n.timelineBudgetLimitWait,
    'wallClock' => l10n.timelineBudgetLimitWallClock,
    'agentCount' => l10n.timelineBudgetLimitAgentCount,
    'agentDepth' => l10n.timelineBudgetLimitAgentDepth,
    'finalization' => l10n.timelineBudgetLimitFinalization,
    _ => kind,
  };
}

String localizedTurnCancellationCause(
  BuildContext context,
  String? causeKind, {
  String? targetTurnId,
}) {
  final l10n = context.l10n;
  return switch (causeKind) {
    'runtimeShutdown' => l10n.timelineTurnRuntimeShutdown,
    'agentClosed' => l10n.timelineTurnAgentClosed,
    'recovery' => l10n.timelineTurnRecoveryStopped,
    'coalesced' => l10n.timelineTurnCoalesced,
    'userRequested' => l10n.timelineTurnCancelled,
    'interrupted' || 'unspecified' || null => l10n.timelineTurnStopped,
    _ => l10n.timelineTurnStopped,
  };
}

String localizedOutcomeStatus(BuildContext context, String status) {
  final l10n = context.l10n;
  return switch (status) {
    'failed' => l10n.timelineOutcomeStatusFailed,
    'denied' => l10n.timelineOutcomeStatusDenied,
    'cancelled' => l10n.timelineOutcomeStatusCancelled,
    'interrupted' => l10n.timelineTurnStopped,
    'completed' => l10n.timelineOutcomeStatusCompleted,
    'succeeded' => l10n.timelineOutcomeStatusSucceeded,
    'budgetLimited' => l10n.timelineTurnBudgetLimited,
    _ => status,
  };
}
