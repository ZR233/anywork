import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../domain/models/composer_primary_action.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/desktop_drop_adapter.dart';
import '../../../../platform/dropped_file.dart';
import '../../../../shared/studio_panel.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../state/composer_input_state.dart';
import '../view_models/composer_actions.dart';
import '../widgets/composer_attachments.dart';
import '../widgets/multiline_enter_shortcuts.dart';
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

class PromptComposerView extends StatefulWidget {
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

  @override
  State<PromptComposerView> createState() => PromptComposerViewState();
}

class PromptComposerViewState extends State<PromptComposerView> {
  late final TextEditingController _controller;
  bool _dragging = false;
  int _targetGeneration = 0;

  ComposerPrimaryAction get _action => widget.state.action;
  bool get _stopUnconfirmed => widget.state.stopUnconfirmed;
  ComposerBlocker? get _stopFailure => widget.state.stopFailure;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.text);
  }

  @override
  void dispose() {
    _targetGeneration++;
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PromptComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targetChanged = oldWidget.targetKey != widget.targetKey;
    if (targetChanged) _targetGeneration++;
    final nextText = widget.state.text;
    if (targetChanged || nextText != _controller.text) {
      _controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
    }
  }

  /// 提交的唯一入口：主按钮与 Enter 提交共用同一准入判定。
  ///
  /// 编辑器持有输入法组词状态；未完成的组词不交给业务动作入口。
  void _submit() {
    // 空输入继续只能由点击按钮发起：Enter 不触发无内容的继续操作。
    if (!widget.state.enterSubmits) return;
    // 中文/日文输入法组词期间的回车由平台确认候选，框架不参与提交。
    if (_controller.value.composing.isValid) return;
    widget.actions.submit();
  }

  bool Function() _captureOperationEligibility() {
    final generation = _targetGeneration;
    final targetKey = widget.targetKey;
    return () =>
        mounted &&
        generation == _targetGeneration &&
        targetKey == widget.targetKey;
  }

  void _pasteClipboard(Future<void> Function() pasteText) {
    widget.actions.paste(
      ComposerTextPaste(
        invoke: pasteText,
        isCurrent: _captureOperationEligibility(),
      ),
    );
  }

  Future<void> _pickLocalAttachments(
    List<ModelInputCapabilityView> capabilities,
  ) {
    widget.actions.pickAttachments(
      capabilities,
      _captureOperationEligibility(),
    );
    return Future<void>.value();
  }

  Future<void> _dropAttachments(List<DroppedFileTransfer> files) {
    return widget.actions.dropAttachments(
      files,
      _captureOperationEligibility(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final composer = widget.state.composer;
    final action = _action;
    final blocker = action.blocker;
    final continuation = widget.state.continuation;
    final continuationNote =
        continuation != null && widget.state.execution == null
        ? context.composerContinuationReasonLabel(continuation.reason)
        : null;
    // 三类原因各自独立可见：canonical 阻塞决定准入，typed 失败说明上一次尝试，
    // 中断原因说明为什么这里可以继续/为什么执行停了；任一条存在都不丢弃其他两条。
    final showContinuationNote = continuationNote != null;
    final localCapabilities = widget.state.inputCapabilities
        .where(
          (capability) =>
              capability.modality != ModelModalityView.text &&
              capability.supportsSource(ModelInputSourceView.local),
        )
        .toList();
    final remoteCapabilities = widget.state.inputCapabilities
        .where(
          (capability) =>
              capability.modality != ModelModalityView.text &&
              capability.supportsSource(ModelInputSourceView.remoteUrl),
        )
        .toList();
    final attachmentEnabled = widget.state.enabled;
    final panel = StudioPanel(
      backgroundColor: colors.surfaceContainerLowest,
      borderColor: _dragging
          ? colors.primary
          : colors.outlineVariant.withValues(alpha: 0.86),
      radius: widget.creationCard ? 12 : 14,
      shadow: false,
      padding: widget.compact
          ? const EdgeInsets.fromLTRB(12, 6, 10, 6)
          : const EdgeInsets.fromLTRB(12, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (composer.attachments.isNotEmpty)
            AttachmentDraftRail(
              attachments: composer.attachments,
              enabled: attachmentEnabled,
              onRemove: (id) => widget.actions.removeAttachment(id),
            ),
          Actions(
            actions: {
              PasteTextIntent: _ComposerPasteAction(
                canPaste: () => widget.state.enabled,
                paste: _pasteClipboard,
              ),
            },
            // Enter 提交由文本框的 `TextInputAction.send` 交给平台文本输入完成，
            // 与主按钮共用 [_submit] 的准入判定；Shift+Enter 是唯一的局部换行动作。
            child: MultilineEnterShortcuts(
              controller: _controller,
              child: TextField(
                key: StudioDriverKeys.composerInput,
                controller: _controller,
                enabled: widget.state.enabled,
                minLines: widget.compact ? 2 : 3,
                maxLines: 8,
                textInputAction: TextInputAction.send,
                // 提交后保留焦点：排队中的下一次输入不必重新点击输入区。
                onEditingComplete: () {},
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: context.l10n.composerHint,
                ),
                onChanged: widget.actions.updateText,
              ),
            ),
          ),
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
          if (widget.state.targetDiagnostic case final diagnostic?)
            ComposerTargetDiagnosticView(diagnostic: diagnostic),
          for (final diagnostic in widget.state.additionalDiagnostics)
            ComposerTargetDiagnosticView(diagnostic: diagnostic),
          ?_reasonRegion(
            context,
            blocker: blocker,
            continuationNote: showContinuationNote ? continuationNote : null,
          ),
          if (_primaryActionStatus(context, action) case final status?)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: status,
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (constraints.maxWidth < 540 && widget.selectorBar != null)
                  widget.selectorBar!,
                Row(
                  children: [
                    AttachmentMenu(
                      enabled: attachmentEnabled,
                      localCapabilities: localCapabilities,
                      remoteCapabilities: remoteCapabilities,
                      onPickLocal: _pickLocalAttachments,
                      onAddUrl: _showUrlDialog,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 2,
                        runSpacing: 4,
                        children: [
                          if (constraints.maxWidth >= 540) ?widget.selectorBar,
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _primaryActionButton(context, action),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return DesktopFileDropTarget(
      enabled: attachmentEnabled && localCapabilities.isNotEmpty,
      onEnter: () => setState(() => _dragging = true),
      onLeave: () {
        if (_dragging) setState(() => _dragging = false);
      },
      onDrop: _dropAttachments,
      child: panel,
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
    final composerRecoveryIssue = _composerFailureRecoveryIssue(
      widget.state.composer,
    );
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
      if (widget.state.failure case final failure?
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

  /// 唯一主按钮：停止、发送并继续、继续、正在停止、正在继续或普通发送。
  ///
  /// 中断态与清理态用可见文字表达，不依赖 tooltip；空输入继续只由这里的按钮发起。
  Widget? _primaryActionStatus(
    BuildContext context,
    ComposerPrimaryAction action,
  ) {
    final colors = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: colors.onSurfaceVariant);
    return switch (action.kind) {
      ComposerPrimaryActionKind.stopping => Text(
        context.l10n.composerStopping,
        key: StudioDriverKeys.composerStopping,
        style: labelStyle,
      ),
      ComposerPrimaryActionKind.continuing => Text(
        context.l10n.composerContinuing,
        style: labelStyle,
      ),
      ComposerPrimaryActionKind.continueConversation => Text(
        context.l10n.composerContinue,
        style: labelStyle,
      ),
      _ => null,
    };
  }

  /// 每种主动作占用同一个圆按钮槽，状态说明不挤占配置工具栏。
  Widget _primaryActionButton(
    BuildContext context,
    ComposerPrimaryAction action,
  ) {
    final colors = Theme.of(context).colorScheme;
    final sendKind =
        action.kind == ComposerPrimaryActionKind.send ||
        action.kind == ComposerPrimaryActionKind.sendAndContinue;
    final enabled = widget.state.primaryEnabled;
    final key = switch (action.kind) {
      ComposerPrimaryActionKind.stop => StudioDriverKeys.composerStop,
      ComposerPrimaryActionKind.sendAndContinue ||
      ComposerPrimaryActionKind.send =>
        enabled
            ? StudioDriverKeys.composerSubmit
            : const ValueKey('composer-submit-disabled'),
      // 停止状态由旁边的可见文字拥有稳定键，按钮只是禁用态。
      ComposerPrimaryActionKind.stopping => const ValueKey(
        'composer-stopping-disabled',
      ),
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
      ComposerPrimaryActionKind.readOnly => context.l10n.composerStopping,
    };
    final busy = widget.state.primaryBusy;
    return IconButton.filled(
      key: key,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(40),
        shape: const CircleBorder(),
        backgroundColor: action.kind == ComposerPrimaryActionKind.stop
            ? colors.surfaceContainerHighest
            : colors.primary,
        foregroundColor: action.kind == ComposerPrimaryActionKind.stop
            ? colors.onSurface
            : colors.onPrimary,
        disabledBackgroundColor: colors.surfaceContainerHighest,
        disabledForegroundColor: colors.onSurface.withValues(alpha: 0.32),
      ),
      icon: busy
          ? const SizedBox.square(
              key: StudioDriverKeys.composerPending,
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              action.kind == ComposerPrimaryActionKind.stop
                  ? Icons.stop_rounded
                  : action.kind ==
                        ComposerPrimaryActionKind.continueConversation
                  ? Icons.play_arrow_rounded
                  : Icons.arrow_upward_rounded,
            ),
      onPressed: !enabled
          ? null
          : action.kind == ComposerPrimaryActionKind.stop
          ? () => widget.actions.stop(widget.state.execution!.id)
          : action.kind == ComposerPrimaryActionKind.continueConversation
          ? widget.actions.continueConversation
          : sendKind
          ? _submit
          : null,
    );
  }

  Future<void> _showUrlDialog() async {
    final isCurrent = _captureOperationEligibility();
    var draft = '';
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        key: StudioDriverKeys.attachmentUrlDialog,
        title: Text(context.l10n.composerAddUrlTitle),
        content: TextField(
          key: StudioDriverKeys.attachmentUrlInput,
          autofocus: true,
          onChanged: (value) => draft = value,
          decoration: const InputDecoration(hintText: 'https://…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            key: StudioDriverKeys.attachmentUrlSubmit,
            onPressed: () => Navigator.pop(context, draft.trim()),
            child: Text(context.l10n.composerAddUrlConfirm),
          ),
        ],
      ),
    );
    if (!isCurrent() || url == null || url.isEmpty) return;
    widget.actions.addUrl(url);
  }
}

class _ComposerPasteAction extends Action<PasteTextIntent> {
  _ComposerPasteAction({required this.canPaste, required this.paste});

  final bool Function() canPaste;
  final void Function(Future<void> Function()) paste;

  @override
  bool isEnabled(PasteTextIntent intent) => canPaste();

  @override
  Object? invoke(PasteTextIntent intent) {
    // EditableText supplies the original overridable action only during invoke.
    // Capture it before the asynchronous image read, rather than looking it up
    // later or duplicating platform shortcuts and text selection edits.
    final defaultPaste = callingAction!;
    paste(() async {
      final result = defaultPaste.invoke(intent);
      if (result is Future) {
        await result;
      }
    });
    return null;
  }
}
