import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_acp_failure_labels.dart';
import 'settings_common.dart';

/// 紧凑的“服务器准备”面板。
///
/// 它只呈现 canonical `acpInstall` 事实：产品固定的受管版本（来自后端模板）、
/// 真实阶段与字节进度。面板不推断就绪、不合成未知总量或速度，不展示程序路径或
/// argv（那是产品固定发行与安装事实，不是表单配置），也不把下载完成讲成账号已保存。
class AcpServerPreparationPanel extends StatelessWidget {
  const AcpServerPreparationPanel({
    super.key,
    required this.template,
    required this.state,
    required this.prepared,
    required this.availableElsewhere,
    required this.admissionPending,
    required this.cancelPending,
    required this.preparePending,
    required this.onUsePrepared,
    required this.onCancel,
  });

  final AcpAccountTemplateView template;
  final AcpInstallStateView state;

  /// 属于本草稿意图的就绪结果（provider + operation 都匹配）。
  final AcpInstalledServerView? prepared;

  /// 同一 provider 已就绪、但属于另一个操作的结果；只能显式认领。
  final AcpInstalledServerView? availableElsewhere;

  final bool admissionPending;
  final bool cancelPending;

  /// 本表单的 start 请求是否仍在途：期间禁止认领另一操作的就绪结果，避免
  /// 迟到的 start 覆盖用户刚显式选中的 Ready。
  final bool preparePending;

  final VoidCallback onUsePrepared;
  final VoidCallback onCancel;

  /// 产品固定的受管版本：来自后端模板，客户端不硬编码、不提供选择。
  String get _version => template.supportedVersion;

  bool get _supported => template.automaticInstall.isAvailable;

  String? get _target => switch (template.automaticInstall) {
    AcpInstallAvailableView(:final target) => target,
    AcpInstallUnsupportedPlatformView() => null,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      key: StudioDriverKeys.acpInstallPanel,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(StudioRadii.md),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const SizedBox(height: 12),
          _facts(context),
          if (state.progress case final progress?) ...[
            const SizedBox(height: 14),
            _progress(context, progress),
          ],
          if (state.failure case final failure?) ...[
            const SizedBox(height: 12),
            _failure(context, failure),
          ],
          if (prepared != null) ...[
            const SizedBox(height: 14),
            _ready(context, prepared!),
          ] else if (availableElsewhere != null) ...[
            const SizedBox(height: 12),
            _elsewhere(context, availableElsewhere!),
          ],
          if (_statusLine(context) case final status?) ...[
            const SizedBox(height: 10),
            status,
          ],
          if (_actions(context) case final actions?) ...[
            const SizedBox(height: 12),
            actions,
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                template.displayName,
                style: context.text.titleSmall?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  Text(
                    '${l10n.acpInstallFactVersion} · $_version',
                    key: StudioDriverKeys.acpInstallVersion,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  if (_target case final target?)
                    Text(
                      '${l10n.acpInstallFactTarget} · $target',
                      key: StudioDriverKeys.acpInstallTarget,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _facts(BuildContext context) {
    final l10n = context.l10n;
    if (!_supported) {
      return SettingsInlineError(
        key: StudioDriverKeys.acpInstallFailure,
        message: l10n.acpInstallUnsupportedPlatform(_version),
      );
    }
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.acpInstallTrustOfficialHttps,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _progress(BuildContext context, AcpInstallProgressView progress) {
    final l10n = context.l10n;
    final fraction = progress.fraction;
    final percent = fraction == null ? null : (fraction * 100).round();
    final total = progress.totalBytes;
    final done = _formatBytes(progress.completedBytes);
    // 阶段进度是“本阶段实际已处理字节 + 可选总量”：下载说已下载、校验说已校验、
    // 解压说已解压，未知总量按不定呈现、不给百分比。
    final text = switch (state) {
      AcpDownloadingState() =>
        total == null
            ? l10n.acpInstallProgressUnknown(done)
            : l10n.acpInstallProgressDownloaded(done, _formatBytes(total)),
      AcpInstallVerifyingState() =>
        total == null
            ? l10n.acpInstallProgressVerifiedUnknown(done)
            : l10n.acpInstallProgressVerified(done, _formatBytes(total)),
      AcpExtractingState() =>
        total == null
            ? l10n.acpInstallProgressExtractedUnknown(done)
            : l10n.acpInstallProgressExtracted(done, _formatBytes(total)),
      _ =>
        total == null
            ? l10n.acpInstallProgressProcessedUnknown(done)
            : l10n.acpInstallProgressProcessed(done, _formatBytes(total)),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(StudioRadii.pill),
          child: LinearProgressIndicator(
            key: StudioDriverKeys.acpInstallProgress,
            value: fraction,
            minHeight: 6,
            backgroundColor: context.colors.surfaceContainerHigh,
            color: context.colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              text,
              key: StudioDriverKeys.acpInstallProgressText,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (percent != null)
              Text(
                l10n.acpInstallProgressPercent(percent),
                key: StudioDriverKeys.acpInstallPercent,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            // 速率只属于下载阶段：校验/解压不合成速度语义。
            if (state is AcpDownloadingState)
              if (progress.effectiveBytesPerSecond case final speed?)
                Text(
                  l10n.acpInstallSpeed(_formatBytes(speed)),
                  key: StudioDriverKeys.acpInstallSpeed,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
          ],
        ),
      ],
    );
  }

  Widget _failure(BuildContext context, AcpInstallFailureView failure) {
    final l10n = context.l10n;
    return SettingsInlineError(
      key: StudioDriverKeys.acpInstallFailure,
      message: acpInstallFailureSummary(l10n, failure),
    );
  }

  Widget _ready(BuildContext context, AcpInstalledServerView server) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.acpInstallReadyTitle,
                key: StudioDriverKeys.acpInstallReadyBadge,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.acpInstallReadyBody,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (server.reused)
          Container(
            key: StudioDriverKeys.acpInstallReusedBadge,
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(StudioRadii.pill),
            ),
            child: Text(
              l10n.acpInstallReusedBadge,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _elsewhere(BuildContext context, AcpInstalledServerView server) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.acpInstallUsePreparedHint(
              server.release.version,
              server.release.target,
            ),
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: StudioDriverKeys.acpInstallUsePrepared,
          onPressed: preparePending ? null : onUsePrepared,
          child: Text(l10n.acpInstallUsePrepared),
        ),
      ],
    );
  }

  Widget? _statusLine(BuildContext context) {
    final l10n = context.l10n;
    if (state is AcpInstallIdleState) return null;
    final retries = state.retryCount;
    final stage = state.stage;
    final parts = <Widget>[
      // 只有真的处于某个阶段时才显示阶段事实：Ready/Cancelled/Failed 没有活动
      // stage，不能 fallback 成“收束中”这种伪造阶段（终态自身即事实）。
      if (stage != null)
        Text(
          '${l10n.acpInstallFactStage} · ${acpInstallStageText(l10n, stage)}',
          key: StudioDriverKeys.acpInstallStage,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      if (retries > 0)
        Text(
          '${l10n.acpInstallFactRetries}: '
          '${l10n.acpInstallRetryValue(retries)}',
          key: StudioDriverKeys.acpInstallRetryCount,
          style: context.text.bodySmall?.copyWith(
            color: context.statusColors.warning,
          ),
        ),
      if (state is AcpInstallCancellingState)
        Text(
          l10n.acpInstallCancelling,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      if (state is AcpInstallCancelledState)
        Text(
          l10n.acpAuthCancelled,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      if (admissionPending && state.isSettled)
        Text(
          l10n.acpInstallPendingAdmission,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
    ];
    if (parts.isEmpty) return null;
    return Wrap(spacing: 12, runSpacing: 4, children: parts);
  }

  Widget? _actions(BuildContext context) {
    final l10n = context.l10n;
    final busy = state.isBusy;
    final canCancel = state.operationId != null && busy;
    if (!busy) return null;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          key: StudioDriverKeys.acpInstallCancel,
          icon: const Icon(Icons.stop_circle_outlined, size: 16),
          label: Text(
            cancelPending ? l10n.acpInstallCancelling : l10n.acpInstallCancel,
          ),
          onPressed: canCancel && !cancelPending ? onCancel : null,
        ),
        Text(
          l10n.acpInstallCancelSharedHint,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    final text = unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(value >= 100 ? 0 : 1);
    return '$text ${units[unit]}';
  }
}
