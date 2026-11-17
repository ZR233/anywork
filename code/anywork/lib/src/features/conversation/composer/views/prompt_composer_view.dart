import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../domain/models/composer_primary_action.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../../shared/composer_action_button.dart';
import '../../../../shared/conversation_composer.dart';
import '../state/composer_input_state.dart';
import '../view_models/composer_actions.dart';
import 'composer_support_views.dart';

/// 原因区的最大高度：三行文案在窄矮窗口里换行时改在区内滚动，不撑破底栏。
const double _composerReasonMaxHeight = 84;

/// 非 Recovery 原因的最大行数；Recovery 诊断在受限滚动区域内完整展示。
const int _composerReasonMaxLines = 3;

StudioRecoveryIssue? _recoveryIssueForBlocker(ComposerBlocker? blocker) {
  if (blocker is ComposerRecoveryBlocker) return blocker.issue;
  if (blocker is ComposerFailureBlocker) return blocker.recoveryIssue;
  return null;
}

/// 草稿 owner 记录的提交失败里提取 typed Recovery issue。
StudioRecoveryIssue? _composerFailureRecoveryIssue(
  ComposerThreadState composer,
) {
  final failure = composer.failure;
  return recoveryIssueFromFailure(failure is StudioFailure ? failure : null);
}

/// 完整语义相等才把两条 Recovery 诊断视为同一事实；id 相同或文案相同都不够。
bool _sameRecoveryDiagnostic(
  StudioRecoveryIssue left,
  StudioRecoveryIssue right,
) {
  if (left.id != right.id ||
      left.scope != right.scope ||
      left.category != right.category ||
      left.impact != right.impact ||
      left.workspaceId != right.workspaceId ||
      left.threadId != right.threadId ||
      left.detail != right.detail ||
      left.availableActions.length != right.availableActions.length) {
    return false;
  }
  for (var index = 0; index < left.availableActions.length; index += 1) {
    if (left.availableActions[index] != right.availableActions[index]) {
      return false;
    }
  }
  return true;
}

/// Recovery 拒绝的失败走本地化诊断行，不再重复渲染原始 SDK 文本。
bool _showRawComposerError(ComposerThreadState composer) =>
    _composerFailureRecoveryIssue(composer) == null;

class PromptComposerView extends StatelessWidget {
  const PromptComposerView({
    required this.state,
    required this.actions,
    required this.targetKey,
    this.selectorBar,
    this.creationCard = false,
    this.compact = false,
    super.key,
  });

  final ComposerInputState state;
  final ComposerActions actions;
  final Object targetKey;
  final Widget? selectorBar;
  final bool creationCard;
  final bool compact;

  ComposerPrimaryAction get _action => state.action;
  bool get _stopUnconfirmed => state.stopUnconfirmed;
  ComposerBlocker? get _stopFailure => state.stopFailure;

  void _submit() {
    if (state.enterSubmits) actions.submit();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final composer = state.composer;
    final action = _action;
    final blocker = action.blocker;
    final continuation = state.continuation;
    final continuationNote = continuation != null && state.execution == null
        ? context.composerContinuationReasonLabel(continuation.reason)
        : null;
    // 三类原因各自独立可见：canonical 阻塞决定准入，typed 失败说明上一次尝试，
    // 中断原因说明为什么这里可以继续/为什么执行停了；任一条存在都不丢弃其他两条。
    final showContinuationNote = continuationNote != null;
    final localCapabilities = state.inputCapabilities
        .where(
          (capability) =>
              capability.modality != ModelModalityView.text &&
              capability.supportsSource(ModelInputSourceView.local),
        )
        .toList();
    final remoteCapabilities = state.inputCapabilities
        .where(
          (capability) =>
              capability.modality != ModelModalityView.text &&
              capability.supportsSource(ModelInputSourceView.remoteUrl),
        )
        .toList();
    final attachmentEnabled = state.enabled;
    return ConversationComposer(
      identity: targetKey,
      text: state.text,
      inputKey: StudioDriverKeys.composerInput,
      enabled: state.enabled,
      autofocus: creationCard,
      creationCard: creationCard,
      compact: compact,
      configuration: selectorBar,
      onTextChanged: actions.updateText,
      onSubmit: state.enterSubmits ? actions.submit : null,
      attachments: composer.attachments,
      canAttach: attachmentEnabled,
      localCapabilities: localCapabilities,
      remoteCapabilities: remoteCapabilities,
      onRemoveAttachment: attachmentEnabled ? actions.removeAttachment : null,
      onPickLocal: (capabilities, isCurrent) async {
        actions.pickAttachments(capabilities, isCurrent);
      },
      onAddUrl: (url, isCurrent) async {
        if (isCurrent()) actions.addUrl(url);
      },
      onDropFiles: actions.dropAttachments,
      onPaste: (pasteText, isCurrent) => actions.paste(
        ComposerTextPaste(
          invoke: () async {
            if (isCurrent()) await pasteText();
          },
          isCurrent: isCurrent,
        ),
      ),
      primaryAction: _primaryActionButton(context, action),
      diagnostics: [
        if (composer.error != null && _showRawComposerError(composer))
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
              child: Text(
                composer.error!,
                key: StudioDriverKeys.composerError,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.error),
              ),
            ),
          ),
        if (state.targetDiagnostic case final diagnostic?)
          ComposerTargetDiagnosticView(diagnostic: diagnostic),
        for (final diagnostic in state.additionalDiagnostics)
          ComposerTargetDiagnosticView(diagnostic: diagnostic),
        ?_reasonRegion(
          context,
          blocker: blocker,
          continuationNote: showContinuationNote ? continuationNote : null,
        ),
      ],
    );
  }

  /// 原因区：canonical 阻塞、typed 失败与中断原因集中一处；同一 Recovery 事实
  /// 多来源出现只渲染第一处，独特诊断不丢。
  ///
  /// 整体套在受高度约束的滚动容器内：普通原因限制行数，Recovery 诊断则完整保留
  /// 长度（含 detail/actions），通过区内滚动访问，不撑破外层 footer。
  Widget? _reasonRegion(
    BuildContext context, {
    required ComposerBlocker? blocker,
    required String? continuationNote,
  }) {
    final stopFailure = _stopFailure;
    final composerRecoveryIssue = _composerFailureRecoveryIssue(state.composer);
    // 仅本次 build 内去重：完整语义相等的 Recovery issue 只渲染一次
    // （id/scope/category/impact/project/thread/detail/actions 全比较）；
    // 普通（非 Recovery）原因即使文案相同也各自保留，不做字符串去重。
    final seen = <StudioRecoveryIssue>[];
    bool claim(StudioRecoveryIssue? issue) {
      if (issue == null) return true;
      if (seen.any((other) => _sameRecoveryDiagnostic(other, issue))) {
        return false;
      }
      seen.add(issue);
      return true;
    }

    final lines = <Widget>[
      if (blocker != null && claim(_recoveryIssueForBlocker(blocker)))
        _reasonLine(
          context,
          context.composerBlockerLabel(blocker),
          StudioDriverKeys.composerBlocker,
          emphasized: true,
          maxLines: _recoveryIssueForBlocker(blocker) == null
              ? _composerReasonMaxLines
              : null,
        ),
      // 上一次继续/提交被拒绝或结果未知的原因保留展示：它不改变 canonical 阻塞的
      // 准入判定；同一 Recovery 事实已被前一行认领时不再重复。
      if (state.failure case final failure?
          when claim(_recoveryIssueForBlocker(failure)))
        _reasonLine(
          context,
          context.composerBlockerLabel(failure),
          const ValueKey('composer-failure'),
          emphasized: true,
          maxLines: _recoveryIssueForBlocker(failure) == null
              ? _composerReasonMaxLines
              : null,
        ),
      // 停止被拒绝的原因来自 Client 命令板：它跨重建与切换会话可见，独特诊断
      // 不被上面任何一行掩盖；同一 Recovery 事实已认领时不再重复。
      if (stopFailure != null && claim(_recoveryIssueForBlocker(stopFailure)))
        _reasonLine(
          context,
          context.composerBlockerLabel(stopFailure),
          const ValueKey('composer-stop-failure'),
          emphasized: true,
          maxLines: _recoveryIssueForBlocker(stopFailure) == null
              ? _composerReasonMaxLines
              : null,
        ),
      if (composerRecoveryIssue != null && claim(composerRecoveryIssue))
        _reasonLine(
          context,
          context.recoveryIssueLabel(composerRecoveryIssue),
          const ValueKey('composer-recovery-failure'),
          emphasized: true,
          maxLines: null,
        ),
      // 命令板长时间未结算：说明结果未确认，不再无限锁死停止入口。
      if (_stopUnconfirmed)
        _reasonLine(
          context,
          context.l10n.composerBlockerUnknown,
          const ValueKey('composer-stop-unconfirmed'),
          emphasized: false,
        ),
      if (continuationNote != null)
        _reasonLine(
          context,
          continuationNote,
          const ValueKey('composer-continuation-reason'),
          emphasized: false,
        ),
    ];
    if (lines.isEmpty) return null;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
        child: ConstrainedBox(
          key: const ValueKey('composer-reasons'),
          constraints: const BoxConstraints(
            maxHeight: _composerReasonMaxHeight,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
          ),
        ),
      ),
    );
  }

  Widget _reasonLine(
    BuildContext context,
    String text,
    Key key, {
    required bool emphasized,
    int? maxLines = _composerReasonMaxLines,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      text,
      key: key,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: emphasized ? colors.error : colors.onSurfaceVariant,
      ),
    );
  }

  /// 每种主动作占用同一个圆按钮槽，状态说明不挤占配置工具栏。
  ComposerActionPresentation _primaryActionButton(
    BuildContext context,
    ComposerPrimaryAction action,
  ) {
    final sendKind =
        action.kind == ComposerPrimaryActionKind.send ||
        action.kind == ComposerPrimaryActionKind.sendAndContinue;
    final enabled = action.enabled;
    final key = switch (action.kind) {
      ComposerPrimaryActionKind.stop => StudioDriverKeys.composerStop,
      ComposerPrimaryActionKind.sendAndContinue ||
      ComposerPrimaryActionKind.send =>
        enabled
            ? StudioDriverKeys.composerSubmit
            : const ValueKey('composer-submit-disabled'),
      ComposerPrimaryActionKind.stopping => StudioDriverKeys.composerStopping,
      ComposerPrimaryActionKind.continuing =>
        StudioDriverKeys.composerContinuing,
      ComposerPrimaryActionKind.continueConversation =>
        StudioDriverKeys.composerContinue,
      ComposerPrimaryActionKind.readOnly => const ValueKey(
        'composer-submit-disabled',
      ),
    };
    final tooltip = switch (action.kind) {
      ComposerPrimaryActionKind.stop => context.l10n.composerStop,
      ComposerPrimaryActionKind.sendAndContinue =>
        context.l10n.composerSendAndContinue,
      ComposerPrimaryActionKind.send => context.l10n.composerSend,
      ComposerPrimaryActionKind.stopping => context.l10n.composerStopping,
      ComposerPrimaryActionKind.continuing => context.l10n.composerContinuing,
      ComposerPrimaryActionKind.continueConversation =>
        context.l10n.composerContinueTooltip,
      ComposerPrimaryActionKind.readOnly =>
        context.l10n.composerAgentReadOnlyTitle,
    };
    return ComposerActionPresentation(
      buttonKey: key,
      progressKey: StudioDriverKeys.composerPending,
      tooltip: tooltip,
      state: action.busy
          ? ComposerActionButtonState.busy
          : switch (action.kind) {
              ComposerPrimaryActionKind.send => ComposerActionButtonState.send,
              ComposerPrimaryActionKind.sendAndContinue =>
                ComposerActionButtonState.sendAndContinue,
              ComposerPrimaryActionKind.stop => ComposerActionButtonState.stop,
              ComposerPrimaryActionKind.continueConversation =>
                ComposerActionButtonState.continueConversation,
              ComposerPrimaryActionKind.stopping ||
              ComposerPrimaryActionKind.continuing =>
                ComposerActionButtonState.busy,
              ComposerPrimaryActionKind.readOnly =>
                ComposerActionButtonState.readOnly,
            },
      onPressed: !enabled
          ? null
          : action.kind == ComposerPrimaryActionKind.stop
          ? () => actions.stop(state.execution!.id)
          : action.kind == ComposerPrimaryActionKind.continueConversation
          ? actions.continueConversation
          : sendKind
          ? _submit
          : null,
    );
  }
}
