import 'package:anywork_client/acp.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/feedback/studio_messages.dart';
import '../../widgets/settings_feedback.dart';
import '../state/acp_auth_labels.dart';
import '../state/acp_failure_labels.dart';
import 'acp_auth_presentation.dart';

/// ACP 认证状态区。
///
/// 每个阶段只突出一个下一步主操作，并把取消入口保持在可达位置；状态标签同时使用图标与
/// 文本，不只依赖颜色。这里只呈现后端 canonical 状态与命令在途事实，不推测登录结果：
/// [busy] 是“命令已提交、canonical 尚未回应”，不是业务状态。
class AcpAuthPanel extends StatefulWidget {
  const AcpAuthPanel({
    required this.state,
    required this.busy,
    required this.cancelBusy,
    required this.onCheck,
    required this.onCancel,
    required this.onLogin,
    this.onDone,
    this.onEditConfig,
    super.key,
  });

  final AcpAuthState state;

  /// start/check/login 命令在途（尚未收到 canonical 回应），不是业务状态。
  final bool busy;

  /// 取消命令自身在途；取消**不受** [busy] 影响，否则迟到 start 会锁死取消。
  final bool cancelBusy;

  final Future<void> Function() onCheck;
  final Future<void> Function() onCancel;
  final Future<void> Function(String methodId) onLogin;

  /// 认证通过后的收束动作；为空时收起该入口（例如编辑页）。
  final VoidCallback? onDone;

  /// 失败后的配置入口；为空时不显示。
  final VoidCallback? onEditConfig;

  @override
  State<AcpAuthPanel> createState() => _AcpAuthPanelState();
}

class _AcpAuthPanelState extends State<AcpAuthPanel> {
  /// 多方法时必须显式选择；未选择前不启用登录，也不替用户挑第一个。
  String? _methodId;

  @override
  void didUpdateWidget(covariant AcpAuthPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _methodId;
    if (selected == null) return;
    final state = widget.state;
    final stillOffered =
        state is AcpAuthRequired &&
        state.methods.any((method) => method.isAgent && method.id == selected);
    if (!stillOffered) _methodId = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l10n = context.l10n;
    return Column(
      key: StudioDriverKeys.acpAccountAuthState,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioNotice(
          key: StudioDriverKeys.acpAccountAuthPhase(acpAuthPhaseToken(state)),
          icon: acpAuthIcon(state),
          tone: acpAuthNoticeTone(state),
          title: acpAuthTitle(l10n, state),
          message: acpAuthBody(l10n, state),
        ),
        if (state is AcpAuthRequired) _requiredActions(context, state),
        if (state case AcpAuthClosing(:final failure?)) ...[
          const SizedBox(height: 8),
          // 就地错误卡只给本地化摘要；后端安全原文放在下面的技术详情里。
          SettingsInlineError(message: acpAuthFailureSummary(l10n, failure)),
        ],
        _actions(context, state),
        if (state case AcpAuthFailed(:final failure)) ...[
          const SizedBox(height: 8),
          _diagnostics(context, failure),
        ],
        if (state case AcpAuthClosing(:final failure?)) ...[
          const SizedBox(height: 8),
          _diagnostics(context, failure),
        ],
        const SizedBox(height: 4),
        Text(
          l10n.acpAccountScopeNotice,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 需要登录时的选择器与主操作。
  ///
  /// 单 Agent 方法可直接登录；多方法必须显式选择后才启用；空/terminal/unsupported 三种
  /// “不可登录”原因分别说明，绝不把未知方式当作 terminal 使用。
  Widget _requiredActions(BuildContext context, AcpAuthRequired state) {
    final l10n = context.l10n;
    final methods = state.agentMethods;
    if (methods.isEmpty) return const SizedBox.shrink();
    final selected = methods
        .where((method) => method.id == _methodId)
        .firstOrNull;
    final single = methods.length == 1;
    final effective = single ? methods.single : selected;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!single)
            DropdownMenu<String>(
              key: StudioDriverKeys.acpAccountLoginMethod,
              initialSelection: selected?.id,
              label: Text(l10n.acpAuthMethodLabel),
              hintText: l10n.acpAuthMethodSelectHint,
              expandedInsets: EdgeInsets.zero,
              dropdownMenuEntries: [
                for (final method in methods)
                  DropdownMenuEntry<String>(
                    value: method.id,
                    label: method.name,
                  ),
              ],
              onSelected: widget.busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _methodId = value);
                    },
            ),
          if (effective?.description case final description?
              when description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                description,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          if (!single && selected == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.acpAuthMethodRequired,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: StudioDriverKeys.acpAccountLogin,
              icon: const Icon(Icons.login),
              label: Text(l10n.acpAuthLogin),
              onPressed: widget.busy || effective == null
                  ? null
                  : () => widget.onLogin(effective.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, AcpAuthState state) {
    final l10n = context.l10n;
    final actions = <Widget>[];
    // 收束中（protocol 结束、物理清理进行）不提供重新 start / 完成，只说明仍在收束。
    if (state is AcpAuthClosing) return const SizedBox.shrink();
    if (state.isBusy && state is! AcpAuthCancelling) {
      // 进行中阶段只有取消可达；只要 canonical 观察已给出 operation 身份就立即可用，
      // 不等 start 命令回执（否则迟到的 start 会让取消被本地 busy 锁住）。
      final canCancel = state.operationId != null && !widget.cancelBusy;
      actions.add(
        OutlinedButton.icon(
          key: StudioDriverKeys.acpAccountCancelAuth,
          icon: const Icon(Icons.stop_circle_outlined),
          label: Text(
            state is AcpAuthChecking
                ? l10n.acpAuthCancelCheck
                : l10n.acpAuthCancel,
          ),
          onPressed: canCancel ? () => widget.onCancel() : null,
        ),
      );
    }
    if (state is AcpAuthVerified) {
      if (widget.onDone case final done?) {
        actions.add(
          FilledButton.icon(
            key: StudioDriverKeys.acpAccountDone,
            icon: const Icon(Icons.check),
            label: Text(l10n.acpAuthDone),
            onPressed: done,
          ),
        );
      }
      actions.add(
        TextButton.icon(
          key: StudioDriverKeys.acpAccountCheck,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.acpAuthRecheck),
          onPressed: widget.busy ? null : () => widget.onCheck(),
        ),
      );
    }
    if (state is AcpAuthUnchecked ||
        state is AcpAuthCancelled ||
        state is AcpAuthRequired ||
        state is AcpAuthFailed) {
      final label = switch (state) {
        AcpAuthFailed() => l10n.acpAuthRetry,
        AcpAuthCancelled() => l10n.acpAuthRecheck,
        _ => l10n.acpAuthCheck,
      };
      final icon = Icon(state is AcpAuthFailed ? Icons.refresh : Icons.link);
      final onPressed = widget.busy ? null : () => widget.onCheck();
      // 需要登录时登录才是唯一主操作；重新检查退为次级入口。
      actions.add(
        state is AcpAuthRequired
            ? TextButton.icon(
                key: StudioDriverKeys.acpAccountCheck,
                icon: icon,
                label: Text(label),
                onPressed: onPressed,
              )
            : FilledButton.icon(
                key: StudioDriverKeys.acpAccountCheck,
                icon: icon,
                label: Text(label),
                onPressed: onPressed,
              ),
      );
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: actions),
    );
  }

  Widget _diagnostics(BuildContext context, AcpAuthFailure failure) {
    final l10n = context.l10n;
    final edit = widget.onEditConfig;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (edit != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.tune),
              label: Text(l10n.acpAuthEditConfig),
              onPressed: edit,
            ),
          ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(
              l10n.acpAuthDiagnostics,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  [
                    l10n.acpAuthCodeLabel(failure.code.name),
                    l10n.acpAuthStageLabel(failure.stage.name),
                    // 后端安全 message 只作次级技术详情（不是 raw stderr）。
                    if (failure.message.isNotEmpty) failure.message,
                  ].join('\n'),
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
