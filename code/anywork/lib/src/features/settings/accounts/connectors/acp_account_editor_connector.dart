import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../state/acp_account_editor_state.dart';
import '../state/acp_account_save_state.dart';
import '../state/acp_account_target.dart';
import '../state/acp_failure_labels.dart';
import '../view_models/acp_account_editor_view_model.dart';
import '../view_models/acp_account_save_view_model.dart';
import '../views/acp_account_editor_view.dart';

/// ACP 接入编辑的连接器：把草稿、受管安装观察、准备命令与保存编排接进纯 props 视图。
///
/// 保存走独立编排 VM（先结算配置写入，再重新取连接代次并检查）；本连接器只负责按钮语义与
/// 导航：保存失败保留草稿并就地说明，保存成功即离开表单，连接未完成以 typed 失败交回调用方
/// 显示“账号已保存，连接未完成”。可见需求只决定本表单的观察租约，不重启准备。
class AcpAccountEditorConnector extends ConsumerStatefulWidget {
  const AcpAccountEditorConnector({
    required this.target,
    required this.visible,
    required this.onCancel,
    required this.onOpenUrl,
    required this.onSaved,
    this.needsPreparation = false,
    super.key,
  });

  final AcpAccountEditorTarget target;

  /// 页面可见性：只决定本表单观察租约，不影响已受理的准备。
  final bool visible;

  final VoidCallback onCancel;

  /// 官方说明/条款入口的安全外链动作。
  final ValueChanged<String> onOpenUrl;

  /// 保存成功后的收束动作；`checkFailure` 非空表示“账号已保存，连接未完成”。
  final void Function(
    String accountId,
    StudioFailure? checkFailure,
    int connectionRevision,
  )
  onSaved;

  /// 已保存账号的 canonical 回执明确需要重新准备时，编辑表单也要给出准备动作。
  final bool needsPreparation;

  @override
  ConsumerState<AcpAccountEditorConnector> createState() =>
      _AcpAccountEditorConnectorState();
}

class _AcpAccountEditorConnectorState
    extends ConsumerState<AcpAccountEditorConnector> {
  @override
  Widget build(BuildContext context) {
    final provider = acpAccountEditorViewModelProvider(widget.target);
    final saveProvider = acpAccountSaveViewModelProvider(
      widget.target.accountId,
    );
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
                    onPressed: widget.onCancel,
                    child: Text(l10n.settingsCancel),
                  ),
                ],
              ),
            );
          },
          data: (state) {
            final vm = ref.read(provider.notifier);
            _scheduleVisibility(vm);
            final save = ref.watch(saveProvider).asData?.value;
            final errors = _errors(l10n, state, save);
            // typed 阶段：保存中 / 已保存检查中 / 检查失败可重试 / 已连接。
            final phase = save?.phase ?? AcpAccountSavePhase.editing;
            return AcpAccountEditorView(
              state: state,
              savePhase: phase,
              onCancel: () => _cancel(save),
              onPrepare: () => unawaited(vm.prepare()),
              onCancelPrepare: () => unawaited(vm.cancelPrepare()),
              onUsePrepared: vm.usePrepared,
              onName: vm.setName,
              onOpenUrl: widget.onOpenUrl,
              onSave: () => unawaited(_save(vm, state)),
              // 只有“已保存且检查失败”时才启用重试；检查在途由视图显示进度并禁用。
              onRetryConnect: phase == AcpAccountSavePhase.savedCheckFailed
                  ? () => unawaited(_retryConnect())
                  : null,
              needsPreparation: widget.needsPreparation,
              error: errors.isEmpty ? null : errors.join('\n'),
            );
          },
        );
  }

  /// 保存并连接：先结算配置写入，再提交连接检查；任何一步的失败都只显示各自的事实。
  Future<void> _save(
    AcpAccountEditorViewModel vm,
    AcpAccountEditorViewState state,
  ) async {
    if (state.create && state.prepared == null) return;
    final update = vm.toUpdate();
    final saveVm = ref.read(
      acpAccountSaveViewModelProvider(widget.target.accountId).notifier,
    );
    final outcome = await saveVm.save(update, create: state.create);
    if (!mounted || outcome.stale) return;
    // 保存失败：留在表单（saveError 就地显示）。连接未完成：同样留在表单，
    // 只提供“重试连接检查”，不再提交保存、也不清空草稿。
    if (acpSaveCompletesEditor(outcome)) {
      widget.onSaved(update.accountId, null, outcome.connectionRevision);
    }
  }

  /// 只重试连接检查：绝不重放保存。
  Future<void> _retryConnect() async {
    final saveVm = ref.read(
      acpAccountSaveViewModelProvider(widget.target.accountId).notifier,
    );
    final outcome = await saveVm.retryCheck();
    if (!mounted || outcome.stale) return;
    if (acpSaveCompletesEditor(outcome)) {
      widget.onSaved(widget.target.accountId, null, outcome.connectionRevision);
    }
  }

  /// 离开表单：账号已保存但连接未完成时，把失败交回调用方（进入详情并显示通知），
  /// 不留下一条用户看不见的不完整接入。
  void _cancel(AcpAccountSaveViewState? save) {
    if (save?.saved == true) {
      widget.onSaved(
        widget.target.accountId,
        save?.checkError,
        save?.connectionRevision ?? 0,
      );
      return;
    }
    widget.onCancel();
  }

  /// 就地说明：保存失败、准备/取消命令失败与观察失败各自只出现一次。
  List<String> _errors(
    AppLocalizations l10n,
    AcpAccountEditorViewState state,
    AcpAccountSaveViewState? save,
  ) => [
    if (save case final saved? when saved.saved)
      if (saved.checkError case final error?)
        l10n.acpAccountSavedConnectIncomplete(
          acpStudioFailureCodeText(l10n, error.code),
        ),
    if (save?.saveError case final error?)
      l10n.acpAccountSaveFailed(acpStudioFailureCodeText(l10n, error.code)),
    for (final action in [state.prepareAction, state.cancelAction]) ...[
      if (action?.error case final error?) _commandFailure(l10n, error),
      if (action?.observationError case final error?)
        _commandFailure(l10n, error),
      if (action?.operation?.error case final error?)
        _commandFailure(l10n, error),
      if (action?.operation?.evidenceError case final error?)
        _commandFailure(l10n, error),
    ],
    if (state.observationError case final error?) settingsFailureText(error),
  ];

  /// 准备命令的 typed 就地说明：只显示安全码值，不展示原始库错误。
  String _commandFailure(AppLocalizations l10n, Object error) =>
      l10n.acpInstallCommandFailed(
        error is StudioFailure
            ? acpStudioFailureCodeText(l10n, error.code)
            : l10n.acpAuthCommandUnavailable,
      );

  /// 可见需求在帧后提交：构建期不修改 provider 状态，重复提交由 VM 自身去重。
  void _scheduleVisibility(AcpAccountEditorViewModel vm) {
    final visible = widget.visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      vm.setVisible(visible);
    });
  }
}
