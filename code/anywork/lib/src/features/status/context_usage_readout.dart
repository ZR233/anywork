import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/studio_hover_detail.dart';
import 'status_detail_panel.dart';

/// 状态栏上下文读数。
///
/// footer 只画紧凑进度图形，不常驻百分比或 token 数字；读数留在悬浮详情和可访问性值里。图形
/// 以 runtime 已用 token 除以最终自动压缩阈值，填充有界；阈值未知时只画中性底轨，绝不用 `0%`
/// 冒充未知。用量达到阈值只说明需要准备压缩，不表示压缩已经发生。
class ContextUsageReadout extends StatefulWidget {
  const ContextUsageReadout({
    required this.projection,
    this.onCompact,
    this.compacting = false,
    this.compactionFailed = false,
    super.key,
  });

  final StudioContextProjection projection;
  final VoidCallback? onCompact;
  final bool compacting;
  final bool compactionFailed;

  @override
  State<ContextUsageReadout> createState() => _ContextUsageReadoutState();
}

class _ContextUsageReadoutState extends State<ContextUsageReadout> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final projection = widget.projection;
    return KeyedSubtree(
      key: StudioDriverKeys.contextUsage(),
      child: StudioHoverDetail(
        maxWidth: 356,
        semanticsLabel: context.l10n.statusContextLabel,
        semanticsValue: _contextSemanticsValue(projection),
        detailBuilder: (context) => KeyedSubtree(
          key: StudioDriverKeys.contextUsageDetail(),
          child: _ContextDetail(
            projection: projection,
            onCompact: widget.onCompact,
            compacting: widget.compacting,
            compactionFailed: widget.compactionFailed,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(right: 2),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: _hovering
                    ? context.colors.surface.withValues(alpha: 0.76)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(StudioRadii.xs),
              ),
              child: SizedBox.square(
                dimension: 16,
                child: CustomPaint(
                  painter: _ContextUsagePainter(
                    progress: _clampedProgress(projection),
                    trackColor: context.colors.outlineVariant,
                    progressColor: _progressColor(context, projection),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextDetail extends StatelessWidget {
  const _ContextDetail({
    required this.projection,
    this.onCompact,
    required this.compacting,
    required this.compactionFailed,
  });

  final StudioContextProjection projection;
  final VoidCallback? onCompact;
  final bool compacting;
  final bool compactionFailed;

  @override
  Widget build(BuildContext context) {
    final limit = compactLimitOf(projection);
    final maxWindow = _knownTokens(projection.maxContextWindow);
    final effectiveWindow = _knownTokens(projection.contextWindow);
    final percentLabel = _percentLabel(projection);
    final cache = projection.cacheUsage;
    // 没有任何有效样本时，累计计数保持未知而不是伪装成真实的零。
    final hasSamples = projection.hasUsage;
    final cacheRateLabel = cache.hitRate == null
        ? tokenCountUnknown
        : '${(cache.hitRate! * 100).round()}%';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusDetailPanel(
          title: context.l10n.statusContextLabel,
          children: [
            _ContextHero(
              used: projection.contextTokens,
              limit: limit,
              percentLabel: percentLabel,
              emphasize: limit != null && projection.contextTokens >= limit,
            ),
            const SizedBox(height: 8),
            _ContextProgressBar(
              progress: _clampedProgress(projection),
              color: _progressColor(context, projection),
              trackColor: context.colors.outlineVariant,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${context.l10n.statusContextRemainingLabel} ${_remainingLabel(context, projection, limit)}',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: StudioDriverKeys.compactContext(),
                  onPressed: onCompact,
                  icon: compacting
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.compress_rounded, size: 16),
                  label: Text(
                    compacting
                        ? context.l10n.statusCompacting
                        : context.l10n.statusCompactNow,
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
              ],
            ),
            if (compactionFailed)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.l10n.statusCompactionFailed,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const StatusDetailDivider(),
        StatusDetailPanel(
          title: context.l10n.statusModelLabel,
          children: [
            _ModelIdentityLine(modelId: projection.modelId),
            StatusDetailRow(
              label: context.l10n.statusAutoCompactLimitLabel,
              value: formatTokenCount(limit),
            ),
            StatusDetailRow(
              label: context.l10n.statusModelMaxContextLabel,
              value: formatTokenCount(maxWindow),
            ),
            if (effectiveWindow != null && effectiveWindow != maxWindow)
              StatusDetailRow(
                label: context.l10n.statusModelEffectiveWindowLabel,
                value: formatTokenCount(effectiveWindow),
              ),
          ],
        ),
        const StatusDetailDivider(),
        StatusDetailPanel(
          title: context.l10n.statusSessionUsageSection,
          children: [
            StatusDetailRow(
              label: context.l10n.statusInputTokensLabel,
              value: formatTokenCount(
                hasSamples ? projection.promptTokens : null,
              ),
            ),
            StatusDetailRow(
              label: context.l10n.statusOutputTokensLabel,
              value: formatTokenCount(
                hasSamples ? projection.completionTokens : null,
              ),
            ),
            StatusDetailRow(
              label: context.l10n.statusTotalTokensLabel,
              value: _withIncompleteMarker(
                context,
                formatTokenCount(hasSamples ? projection.totalTokens : null),
                projection.hasIncompleteUsage,
              ),
            ),
            if (hasSamples)
              StatusDetailRow(
                label: context.l10n.statusInferenceCountLabel,
                value: _formatCount(projection.inferenceCount),
              ),
            StatusDetailRow(
              label: context.l10n.statusCacheLabel,
              value: _withIncompleteMarker(
                context,
                cacheRateLabel,
                cache.hasIncompleteUsage,
              ),
            ),
            if (cache.hasPositiveDenominator) ...[
              StatusDetailRow(
                label: context.l10n.statusCacheHitTokensLabel,
                value: formatTokenCount(cache.cacheReadTokens),
              ),
              StatusDetailRow(
                label: context.l10n.statusCacheMissTokensLabel,
                value: formatTokenCount(cache.missTokens),
              ),
            ],
            if (projection.cacheWriteTokens > 0)
              StatusDetailRow(
                label: context.l10n.statusCacheWriteTokensLabel,
                value: formatTokenCount(projection.cacheWriteTokens),
              ),
            if (projection.reasoningTokens > 0)
              StatusDetailRow(
                label: context.l10n.statusReasoningTokensLabel,
                value: formatTokenCount(projection.reasoningTokens),
              ),
          ],
        ),
        const StatusDetailDivider(),
        StatusDetailPanel(
          title: context.l10n.statusCost,
          children: [
            _CostRows(
              label: context.l10n.statusCostEstimateLabel,
              costs: projection.estimatedCosts,
              unpricedMarker: projection.hasUnpricedUsage
                  ? context.l10n.statusUnpricedUsageLabel
                  : null,
            ),
            if (projection.estimatedCacheSavings.isNotEmpty)
              _CostRows(
                label: context.l10n.statusCacheSavingsLabel,
                costs: projection.estimatedCacheSavings,
              ),
          ],
        ),
      ],
    );
  }
}

/// 费用按币种分行：每个金额完整可见，不用 `+` 拼成可能被省略的一行。
///
/// 金额只来自 canonical 费用事实，这里只做格式化，不换算币种、不重算价格。
class _CostRows extends StatelessWidget {
  const _CostRows({
    required this.label,
    required this.costs,
    this.unpricedMarker,
  });

  final String label;
  final List<RuntimeCostView> costs;

  /// 存在未计价用量时附加在最后一行金额后的简短标记。
  final String? unpricedMarker;

  @override
  Widget build(BuildContext context) {
    final marker = unpricedMarker;
    if (costs.isEmpty) {
      return StatusDetailRow(
        label: label,
        value: marker == null
            ? tokenCountUnknown
            : '$tokenCountUnknown · $marker',
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, cost) in costs.indexed)
          StatusDetailRow(
            label: index == 0 ? label : '',
            value: [
              formatRuntimeCostAmount(cost.currency, cost.amount),
              if (marker != null && index == costs.length - 1) marker,
            ].join(' · '),
          ),
      ],
    );
  }
}

/// 首区读数：已用量 / 压缩阈值与百分比，是详情里唯一放大的一行。
class _ContextHero extends StatelessWidget {
  const _ContextHero({
    required this.used,
    required this.limit,
    required this.percentLabel,
    required this.emphasize,
  });

  final int used;
  final int? limit;
  final String percentLabel;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final amountStyle = context.text.titleLarge?.copyWith(
      fontSize: 23,
      height: 1.1,
      fontWeight: FontWeight.w600,
      color: context.colors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final percentStyle = context.text.titleMedium?.copyWith(
      fontSize: 20,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: limit == null
          ? context.colors.onSurfaceVariant
          : emphasize
          ? context.colors.error
          : context.colors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          // 窄窗口或放大文字下整体等比缩小，而不是裁掉数字。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${formatTokenCount(used)} / ${formatTokenCount(limit)}',
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

/// 横向进度条：填充按阈值有界，超过阈值时以整条满格的强调色表达。
class _ContextProgressBar extends StatelessWidget {
  const _ContextProgressBar({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double? progress;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(StudioRadii.pill),
      child: LinearProgressIndicator(
        value: progress ?? 0,
        minHeight: 4,
        backgroundColor: trackColor.withValues(alpha: 0.5),
        color: progress == null ? Colors.transparent : color,
      ),
    );
  }
}

/// 模型身份一行：长名称换行而不是裁切，未知时保留占位。
class _ModelIdentityLine extends StatelessWidget {
  const _ModelIdentityLine({required this.modelId});

  final String modelId;

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodySmall?.copyWith(
      color: context.colors.onSurface,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(modelId.isEmpty ? tokenCountUnknown : modelId, style: style),
    );
  }
}

class _ContextUsagePainter extends CustomPainter {
  const _ContextUsagePainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  /// `null` 表示阈值未知：只画中性底轨，不表达任何进度。
  final double? progress;
  final Color trackColor;
  final Color progressColor;

  static const _strokeWidth = 2.2;
  static const _radiusInset = 1.8;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - _radiusInset;
    final trackPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.74)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _strokeWidth;
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);
    final progress = this.progress;
    if (progress == null || progress <= 0) {
      return;
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ContextUsagePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        trackColor != oldDelegate.trackColor ||
        progressColor != oldDelegate.progressColor;
  }
}

/// 最终生效的压缩阈值；非正值与缺失都表示未知，不能当作零分母。
int? compactLimitOf(StudioContextProjection projection) {
  return _knownTokens(projection.autoCompactLimit);
}

int? _knownTokens(int? value) {
  return value != null && value > 0 ? value : null;
}

/// footer 图形的填充比例；阈值未知时为 `null`，超过阈值时截断为满格。
double? _clampedProgress(StudioContextProjection projection) {
  final limit = compactLimitOf(projection);
  if (limit == null) {
    return null;
  }
  return (projection.contextTokens / limit).clamp(0.0, 1.0);
}

Color _progressColor(BuildContext context, StudioContextProjection projection) {
  final progress = _clampedProgress(projection);
  if (progress == null) {
    return context.colors.onSurfaceVariant;
  }
  if (progress >= 1) {
    return context.colors.error;
  }
  if (progress >= 0.72) {
    return context.statusColors.warning;
  }
  return context.statusColors.activeIndicator;
}

/// 非零但不足 1% 的读数，避免与真实零的 `0%` 视觉混同。
const _belowOnePercentLabel = '<1%';

String _percentLabel(StudioContextProjection projection) {
  final limit = compactLimitOf(projection);
  if (limit == null) {
    return tokenCountUnknown;
  }
  final used = projection.contextTokens;
  if (used <= 0) {
    return '0%';
  }
  // 向下取整：不足 1% 显示 `<1%`；未达阈值不会因四舍五入提前显示 100%；
  // 达到或超过阈值时保留真实比例（例如 118%）。
  final percent = (used / limit * 100).floor();
  return percent == 0 ? _belowOnePercentLabel : '$percent%';
}

String _remainingLabel(
  BuildContext context,
  StudioContextProjection projection,
  int? limit,
) {
  if (limit == null) {
    return tokenCountUnknown;
  }
  final remaining = limit - projection.contextTokens;
  if (remaining < 0) {
    return context.l10n.statusContextOverLimitValue(
      formatTokenCount(-remaining),
    );
  }
  return formatTokenCount(remaining);
}

/// 可访问性读数：详情只在悬停时出现，因此触发控件自己报告已用与阈值。
String _contextSemanticsValue(StudioContextProjection projection) {
  final limit = compactLimitOf(projection);
  final used = formatTokenCount(projection.contextTokens);
  if (limit == null) {
    return '$used / $tokenCountUnknown';
  }
  return '$used / ${formatTokenCount(limit)} · ${_percentLabel(projection)}';
}

String _withIncompleteMarker(
  BuildContext context,
  String value,
  bool incomplete, {
  String? marker,
}) {
  if (!incomplete) {
    return value;
  }
  return '$value · ${marker ?? context.l10n.statusUsageIncompleteLabel}';
}

String _formatCount(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(text[index]);
  }
  return buffer.toString();
}
