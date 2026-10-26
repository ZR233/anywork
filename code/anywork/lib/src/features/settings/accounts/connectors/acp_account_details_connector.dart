import 'dart:async';

import 'package:anywork_client/acp.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../state/acp_account_target.dart';
import '../state/acp_command_notice.dart';
import '../view_models/acp_account_auth_view_model.dart';
import '../views/acp_account_details_view.dart';

/// ACP 接入详情的连接器：把 canonical 认证观察与命令接进纯 props 视图。
///
/// 业务状态只来自 `acpAuth` 观察；本连接器不推断登录结果，也不在离页时取消已受理的检查。
/// 可见需求由外层传入：`visible` 变化只驱动本页观察租约的取得/释放，不重启检查。
class AcpAccountDetailsConnector extends ConsumerStatefulWidget {
  const AcpAccountDetailsConnector({
    required this.account,
    required this.visible,
    required this.onBack,
    required this.onEdit,
    required this.onRemove,
    this.template,
    super.key,
  });

  final AcpAccountSettings account;

  /// 目录里仍可解析的模板；目录未加载时为 null。
  final AcpAccountTemplate? template;

  /// 页面可见性：只决定本页观察租约，不影响已受理的业务操作。
  final bool visible;

  final VoidCallback onBack;
  final VoidCallback onEdit;
  final Future<void> Function() onRemove;

  @override
  ConsumerState<AcpAccountDetailsConnector> createState() =>
      _AcpAccountDetailsConnectorState();
}

class _AcpAccountDetailsConnectorState
    extends ConsumerState<AcpAccountDetailsConnector> {
  AcpAccountTarget get _target => AcpAccountTarget(
    accountId: widget.account.accountId,
    connectionRevision: widget.account.connectionRevision,
    provider: widget.account.provider,
  );

  @override
  Widget build(BuildContext context) {
    final provider = acpAccountAuthViewModelProvider(_target);
    final l10n = context.l10n;
    return ref
        .watch(provider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) {
            if (error is! StudioFailure) {
              Error.throwWithStackTrace(error, stack);
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(settingsFailureText(error)),
                  TextButton(
                    onPressed: () => ref.invalidate(provider),
                    child: Text(l10n.runtimeFatalRetry),
                  ),
                  TextButton(
                    onPressed: widget.onBack,
                    child: Text(l10n.settingsAccountsTitle),
                  ),
                ],
              ),
            );
          },
          data: (state) {
            final vm = ref.read(provider.notifier);
            _scheduleVisibility(vm);
            final notice = state.visibleNotice;
            return AcpAccountDetailsView(
              account: widget.account,
              template: widget.template,
              auth: state.auth,
              busy: state.busy,
              cancelBusy: state.cancelBusy,
              noticeSummary: notice == null
                  ? null
                  : acpCommandNoticeSummary(l10n, notice),
              noticeDetail: notice?.detail,
              errors: [
                if (state.observationError case final error?)
                  settingsFailureText(error),
                for (final action in [
                  state.checkAction,
                  state.cancelAction,
                ]) ...[
                  if (action?.observationError case final error?)
                    settingsFailureText(error),
                  if (action?.operation?.error case final error?)
                    settingsFailureText(error),
                  if (action?.operation?.evidenceError case final error?)
                    settingsFailureText(error),
                ],
              ],
              onRetry: vm.retryObservation,
              onBack: widget.onBack,
              onEdit: widget.onEdit,
              onRemove: widget.onRemove,
              onCheck: vm.check,
              onCancel: vm.cancel,
              onLogin: vm.login,
            );
          },
        );
  }

  /// 可见需求在帧后提交：构建期不修改 provider 状态，重复提交由 VM 自身去重。
  void _scheduleVisibility(AcpAccountAuthViewModel vm) {
    final visible = widget.visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      vm.setVisible(visible);
    });
  }
}
