import 'dart:async';

import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../domain/models/composer_primary_action.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../../shared/studio_menu_label.dart';
import '../../../status/session_selectors.dart';
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
    required this.composer,
    this.targetDiagnostic,
    this.additionalDiagnostics = const [],
    required this.enabled,
    required this.onChanged,
    required this.onSubmit,
    required this.inputCapabilities,
    required this.onPasteImage,
    required this.onReportFailure,
    required this.onAddLocal,
    required this.onAddUrl,
    required this.onRemoveAttachment,
    required this.onPasteClipboard,
    required this.pasteTargetId,
    required this.onPickLocalAttachments,
    required this.onDropAttachments,
    this.onStop,
    this.onContinue,
    this.execution,
    this.continuation,
    this.continuationAccepted = false,
    this.continuationPending = false,
    this.blocker,
    this.failure,
    this.stopCommand,
    this.queuedStopStartedAtMs,
    this.selectorBar,
    this.settingsMenu,
    this.textController,
    this.compact = false,
    this.submissionLocked = false,
    super.key,
  });

  final ComposerThreadState composer;
  final ComposerTargetDiagnostic? targetDiagnostic;
  final List<ComposerTargetDiagnostic> additionalDiagnostics;
  final bool enabled;

  /// 会话自己的当前执行身份；主按钮据它决定停止 / 发送并继续。
  final AgentExecutionView? execution;

  /// 该会话唯一的继续点只读投影；没有未完成的中断工作时为空。
  final ContinuationView? continuation;

  /// 继续已受理但新轮次尚未出现。
  final bool continuationAccepted;

  /// 继续请求已发出、还没收到受理回执：在途不是已受理，不显示“正在继续”。
  final bool continuationPending;

  /// 阻塞主按钮的类型化原因；`null` 表示没有阻塞。
  final ComposerBlocker? blocker;

  /// 上一次操作被拒绝/结果未知的原因：只展示，不改变 canonical 阻塞的准入判定。
  final ComposerBlocker? failure;

  /// Client 命令板里的停止命令状态（键 `stop:<threadId>`）。
  ///
  /// 「请求是否还在进行」只能来自这里：它跨 widget 重建与切换会话存活，输入区
  /// 不再用本地标记描述在途。`target.label` 是本次请求固定的执行编号。
  final CommandStatus? stopCommand;

  /// 被 Client 排队的那次重试对应的命令登记时间：按「请求在途」渲染并保持禁用。
  final int? queuedStopStartedAtMs;

  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final List<ModelInputCapabilityView> inputCapabilities;
  final Future<void> Function(Uint8List pngBytes) onPasteImage;
  final ValueChanged<Object> onReportFailure;
  final Future<void> Function(List<String> paths) onAddLocal;
  final Future<void> Function(String url) onAddUrl;
  final Future<void> Function(String draftId) onRemoveAttachment;
  final Future<void> Function(
    void Function(String) pasteText,
    bool supportsImages,
    bool Function() isCurrent,
  )
  onPasteClipboard;
  final String? pasteTargetId;
  final Future<void> Function(List<ModelInputCapabilityView>, bool Function())
  onPickLocalAttachments;
  final Future<void> Function(DropDetails, bool Function()) onDropAttachments;
  final VoidCallback? onStop;
  final VoidCallback? onContinue;
  final Widget? selectorBar;
  final Widget? settingsMenu;

  /// 起始页正文由调用方持有。传入后不再用 [composer.draft] 覆盖输入框。
  final TextEditingController? textController;

  /// 矮窗口紧凑布局：收起面板留白与输入最小行数，操作按钮保持不变。
  final bool compact;

  /// 起始页在设置 lane 排空前就置位的提交哨兵。线程路径保持 false。
  final bool submissionLocked;

  @override
  State<PromptComposerView> createState() => PromptComposerViewState();
}

class PromptComposerViewState extends State<PromptComposerView> {
  TextEditingController? _ownedController;
  bool _dragging = false;
  bool _pasteInFlight = false;
  bool _syncingDraft = false;
  int _targetGeneration = 0;

  /// 命令板持续 pending 超过该阈值即视为「结果未确认」：不再无限锁死停止入口。
  ///
  /// 只适用于「请求已发出、尚未得到受理回执」这一段：受理后命令板仍会 pending
  /// （等待 canonical 身份观察），那属于「正在停止」，不是结果未确认。
  static const Duration _stopUnconfirmedAfter = Duration(seconds: 15);

  /// 只为「跨过 15s 阈值」触发一次重建。
  Timer? _stopUnconfirmedTimer;

  /// 计时器已经跨过阈值的那次登记时间（纯视觉信号）。
  ///
  /// 判定仍以命令板 `startedAtMs` 的 elapsed 为准：这里只把「计时器已到点」这一时刻
  /// 保留到下一次命令板更新；换了登记时间（重试）或不再等待回执时自动失效。
  int? _stopUnconfirmedStartedAtMs;

  TextEditingController get _controller =>
      widget.textController ?? _ownedController!;

  /// 命令板里本次执行是否仍有一条未结算的停止请求。
  ///
  /// 目标编号必须与当前渲染的执行一致：canonical 已换执行时，旧请求不再约束新执行。
  bool get _stopPending {
    final command = widget.stopCommand;
    final execution = widget.execution;
    return command != null &&
        command.isPending &&
        execution != null &&
        command.target.label == execution.id &&
        !command.accepted;
  }

  /// 该停止请求已收到需要身份观察的受理回执（命令板 `accepted`）。
  ///
  /// 它表示「已受理、仍在等 canonical 收敛」：界面显示「正在停止」，不再提供停止或
  /// 提交入口。这是命令板事实，重建与切换会话后读到的一致。
  bool get _stopAccepted {
    final command = widget.stopCommand;
    final execution = widget.execution;
    return command != null &&
        command.accepted &&
        execution != null &&
        command.target.label == execution.id;
  }

  /// canonical 是否已进入清理期：此时执行已经在停，谈不上「结果未确认」。
  bool get _stopCanonicalStopping =>
      widget.execution?.phase.isStopping ?? false;

  /// 停止请求已发出、尚未得到受理回执，且 canonical 也还没进入清理期。
  ///
  /// 受理或清理一旦成立，就由「正在停止 + canonical 收敛」表达，不再参与未确认判定：
  /// 受理、观察、生效分别表达，不能同时说「正在停止」和「请核对后重试」。
  bool get _stopAwaitingReceipt =>
      _stopPending && !_stopAccepted && !_stopCanonicalStopping;

  /// 在途请求已超过阈值且仍未被受理 → 结果未确认。
  ///
  /// elapsed 完全由命令板登记时间算出（`startedAtMs`，`0` 表示未记录），因此重建或
  /// 切换会话回来后立即按真实时长判定，不以 widget 生命周期为起点。
  bool get _stopUnconfirmed {
    if (!_stopAwaitingReceipt) return false;
    final startedAtMs = widget.stopCommand?.startedAtMs ?? 0;
    if (startedAtMs == 0) return false;
    // 用户已重试且被 Client 排队：按「请求在途」渲染，不显示未确认。
    if (widget.queuedStopStartedAtMs == startedAtMs) return false;
    if (_stopUnconfirmedStartedAtMs == startedAtMs) return true;
    return DateTime.now().millisecondsSinceEpoch - startedAtMs >=
        _stopUnconfirmedAfter.inMilliseconds;
  }

  /// 命令板记录的停止失败原因：它跨重建可见，优先于本地的即时原因。
  ///
  /// 它描述的是本会话最近一次停止尝试的结果，因此不随后续 canonical 执行变化消失：
  /// 「你点的那次执行已经结束或被替换」正是调用方需要看到的原因。下一次显式操作才会
  /// 取代它（命令板对该键开始新的请求）。
  ComposerBlocker? get _stopFailure {
    final command = widget.stopCommand;
    if (command == null || command.phase != CommandPhase.failed) return null;
    final error = command.error;
    return ComposerFailureBlocker(
      error?.reason,
      recoveryIssue: recoveryIssueFromFailure(error),
    );
  }

  @override
  void dispose() {
    _targetGeneration++;
    _stopUnconfirmedTimer?.cancel();
    widget.textController?.removeListener(_onDraftChanged);
    _ownedController?.removeListener(_onDraftChanged);
    _ownedController?.dispose();
    super.dispose();
  }

  /// 只安排「跨过阈值」的那一次重建。
  ///
  /// 判定与提示都是命令板 `startedAtMs` 的纯函数：这里不保存起点、不重发请求、不改
  /// 执行编号。受理、canonical 清理、条目消失或换了登记时间都会撤销它；已过阈值时本次
  /// build 直接显示未确认，不再安排计时。
  void _syncStopUnconfirmed() {
    _stopUnconfirmedTimer?.cancel();
    _stopUnconfirmedTimer = null;
    if (!_stopAwaitingReceipt) {
      _stopUnconfirmedStartedAtMs = null;
      return;
    }
    final startedAtMs = widget.stopCommand?.startedAtMs ?? 0;
    if (startedAtMs == 0) return;
    if (_stopUnconfirmedStartedAtMs != null &&
        _stopUnconfirmedStartedAtMs != startedAtMs) {
      // 换了登记时间（重试）：旧信号失效。
      _stopUnconfirmedStartedAtMs = null;
    }
    final remaining =
        startedAtMs +
        _stopUnconfirmedAfter.inMilliseconds -
        DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return;
    _stopUnconfirmedTimer = Timer(Duration(milliseconds: remaining), () {
      _stopUnconfirmedTimer = null;
      if (!mounted) return;
      setState(() => _stopUnconfirmedStartedAtMs = startedAtMs);
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.textController == null) {
      _ownedController = TextEditingController(text: widget.composer.draft);
    }
    _controller.addListener(_onDraftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncStopUnconfirmed();
    });
  }

  void _onDraftChanged() {
    if (!mounted || _syncingDraft) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant PromptComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pasteTargetId != widget.pasteTargetId ||
        oldWidget.textController != widget.textController) {
      _targetGeneration++;
      _pasteInFlight = false;
    }
    _syncStopUnconfirmed();
    if (oldWidget.textController != widget.textController) {
      oldWidget.textController?.removeListener(_onDraftChanged);
      widget.textController?.addListener(_onDraftChanged);
    }
    if (widget.textController != null) return;
    final nextText = widget.composer.draft;
    if (nextText != _controller.text) {
      _syncingDraft = true;
      _controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
      _syncingDraft = false;
    }
  }

  /// 主按钮与回车提交共享同一前置条件：启用、有内容且不在提交中。
  bool get _hasContent =>
      _controller.text.trim().isNotEmpty ||
      widget.composer.attachments.isNotEmpty;

  bool get _submissionPending =>
      widget.submissionLocked || widget.composer.isSubmissionPending;

  /// 主按钮语义：唯一由 canonical 执行/继续点、草稿内容与类型化阻塞推导。
  ComposerPrimaryAction get _action => ComposerPrimaryAction.resolve(
    // 子会话不经过本控件：详情只读面板没有任何输入操作。
    isChild: false,
    execution: widget.execution,
    continuation: widget.continuation,
    hasContent: _hasContent,
    // 停止请求在途是线程级事实，与当前主动作种类无关：运行中有草稿时主动作是
    // 「发送并继续」，但停止请求已发出、尚未受理期间同样不得提交，否则两者会竞态。
    submissionPending: _submissionPending || _stopPending,
    stopAccepted: _stopAccepted,
    continuationAccepted: widget.continuationAccepted,
    continuationPending: widget.continuationPending,
    blocker: widget.blocker,
  );

  /// 停止此刻是否真的可执行：有当前执行、尚未进入清理、也没有在途请求。
  ///
  /// 停止快捷键用它（与主动作种类无关），运行中有草稿时主动作是「发送并继续」，
  /// 但 Esc 仍应停止当前执行。
  ///
  /// 命令板仍 pending 时不再自动重发；只有在同一执行上被判定「结果未确认」后，
  /// 才允许用户显式再点一次（仍用同一执行编号，不换目标）。
  bool get _stopAvailable {
    final execution = widget.execution;
    return execution != null &&
        !execution.phase.isStopping &&
        !_stopAccepted &&
        (!_stopPending || _stopUnconfirmed) &&
        widget.onStop != null;
  }

  /// 提交的唯一入口：主按钮与 Enter 提交共用同一准入判定。
  ///
  /// 组词中的回车先由输入法确认候选，根本不会走到这里；因此这里不再需要
  /// 额外的组合状态检查，也不会因组合文本而误提交。
  void _submit() {
    // 空输入继续只能由点击按钮发起：Enter 不触发无内容的继续操作。
    if (!widget.enabled ||
        !_action.enterSubmits ||
        (widget.blocker?.blocksSubmission ?? false)) {
      return;
    }
    // 中文/日文输入法组词期间的回车由平台确认候选，框架不参与提交。
    if (_controller.value.composing.isValid) return;
    widget.onSubmit();
  }

  bool get _supportsPastedImages => widget.inputCapabilities.any(
    (capability) =>
        capability.modality == ModelModalityView.image &&
        capability.supportsSource(ModelInputSourceView.local),
  );

  bool Function() _captureOperationEligibility() {
    final generation = _targetGeneration;
    final targetId = widget.pasteTargetId;
    return () =>
        mounted &&
        generation == _targetGeneration &&
        targetId == widget.pasteTargetId;
  }

  Future<void> _pasteClipboard() async {
    final isCurrent = _captureOperationEligibility();
    final onPasteClipboard = widget.onPasteClipboard;
    final onReportFailure = widget.onReportFailure;

    _pasteInFlight = true;
    try {
      await onPasteClipboard(
        (text) => _pasteText(text, isCurrent: isCurrent),
        _supportsPastedImages,
        isCurrent,
      );
    } catch (error) {
      if (isCurrent()) onReportFailure(error);
    } finally {
      if (isCurrent()) _pasteInFlight = false;
    }
  }

  Future<void> _pickLocalAttachments(
    List<ModelInputCapabilityView> capabilities,
  ) {
    final isCurrent = _captureOperationEligibility();
    final onPick = widget.onPickLocalAttachments;
    return onPick(capabilities, isCurrent);
  }

  Future<void> _dropAttachments(DropDetails details) async {
    final isCurrent = _captureOperationEligibility();
    final onDrop = widget.onDropAttachments;
    final onReportFailure = widget.onReportFailure;
    try {
      await onDrop(details, isCurrent);
    } catch (error) {
      if (isCurrent()) onReportFailure(error);
    }
  }

  void _pasteText(String text, {required bool Function() isCurrent}) {
    if (!isCurrent()) return;
    final controller = _controller;
    final value = controller.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final collapsed = value.copyWith(
      selection: TextSelection.collapsed(offset: selection.end),
      composing: TextRange.empty,
    );
    controller.value = collapsed.replaced(selection, text);
    widget.onChanged(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final composer = widget.composer;
    final action = _action;
    final blocker = action.blocker;
    final continuation = widget.continuation;
    final continuationNote = continuation != null && widget.execution == null
        ? context.composerContinuationReasonLabel(continuation.reason)
        : null;
    // 三类原因各自独立可见：canonical 阻塞决定准入，typed 失败说明上一次尝试，
    // 中断原因说明为什么这里可以继续/为什么执行停了；任一条存在都不丢弃其他两条。
    final showContinuationNote = continuationNote != null;
    final localCapabilities = widget.inputCapabilities
        .where(
          (capability) =>
              capability.modality != ModelModalityView.text &&
              capability.supportsSource(ModelInputSourceView.local),
        )
        .toList();
    final remoteCapabilities = widget.inputCapabilities
        .where(
          (capability) =>
              capability.modality != ModelModalityView.text &&
              capability.supportsSource(ModelInputSourceView.remoteUrl),
        )
        .toList();
    final attachmentEnabled = widget.enabled;
    final panel = StudioPanel(
      backgroundColor: colors.surfaceContainerLowest,
      borderColor: _dragging
          ? colors.primary
          : colors.outlineVariant.withValues(alpha: 0.86),
      radius: StudioRadii.lg,
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
              onRemove: (id) => unawaited(widget.onRemoveAttachment(id)),
            ),
          Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.paste): _PasteComposerIntent(),
              SingleActivator(LogicalKeyboardKey.keyV, control: true):
                  _PasteComposerIntent(),
              SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                  _PasteComposerIntent(),
              SingleActivator(LogicalKeyboardKey.insert, shift: true):
                  _PasteComposerIntent(),
              SingleActivator(LogicalKeyboardKey.escape): _StopComposerIntent(),
            },
            child: Actions(
              actions: {
                _PasteComposerIntent: CallbackAction<_PasteComposerIntent>(
                  onInvoke: (_) {
                    if (widget.enabled && !_pasteInFlight) {
                      unawaited(_pasteClipboard());
                    }
                    return null;
                  },
                ),
                _StopComposerIntent: CallbackAction<_StopComposerIntent>(
                  onInvoke: (_) {
                    // 停止快捷键与主按钮同源判定，但不受主动作种类限制：运行中有草稿
                    // 时主动作是「发送并继续」，Esc 仍然要能停止当前执行。
                    if (_stopAvailable) {
                      widget.onStop!();
                    }
                    return null;
                  },
                ),
              },
              // Enter 提交由文本框的 `TextInputAction.send` 交给平台文本输入完成，
              // 与主按钮共用 [_submit] 的准入判定；Shift+Enter 是唯一的局部换行动作。
              child: MultilineEnterShortcuts(
                controller: _controller,
                onChanged: widget.onChanged,
                child: TextField(
                  key: StudioDriverKeys.composerInput,
                  controller: _controller,
                  enabled: widget.enabled,
                  minLines: widget.compact ? 2 : 3,
                  maxLines: 8,
                  textInputAction: TextInputAction.send,
                  // 提交后保留焦点：排队中的下一次输入不必重新点击输入区。
                  onEditingComplete: () {},
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: context.l10n.composerHint,
                    hintStyle: TextStyle(color: colors.onSurfaceVariant),
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: widget.onChanged,
                ),
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
          if (widget.targetDiagnostic case final diagnostic?)
            ComposerTargetDiagnosticView(diagnostic: diagnostic),
          for (final diagnostic in widget.additionalDiagnostics)
            ComposerTargetDiagnosticView(diagnostic: diagnostic),
          ?_reasonRegion(
            context,
            blocker: blocker,
            continuationNote: showContinuationNote ? continuationNote : null,
          ),
          Row(
            children: [
              AttachmentMenu(
                enabled: attachmentEnabled,
                localCapabilities: localCapabilities,
                remoteCapabilities: remoteCapabilities,
                onPickLocal: _pickLocalAttachments,
                onAddUrl: _showUrlDialog,
              ),
              if (widget.settingsMenu != null) widget.settingsMenu!,
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 2,
                  runSpacing: 4,
                  children: [?widget.selectorBar],
                ),
              ),
              const SizedBox(width: 8),
              ..._primaryActionButton(context, action),
            ],
          ),
        ],
      ),
    );
    return DropTarget(
      enabled: attachmentEnabled && localCapabilities.isNotEmpty,
      acceptedKinds: const {DropItemKind.file},
      onEnter: (_) => setState(() => _dragging = true),
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
      widget.composer,
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
      if (widget.failure case final failure?
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
  List<Widget> _primaryActionButton(
    BuildContext context,
    ComposerPrimaryAction action,
  ) {
    final colors = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: colors.onSurfaceVariant);
    final statusLabel = switch (action.kind) {
      ComposerPrimaryActionKind.stopping => Text(
        context.l10n.composerStopping,
        key: StudioDriverKeys.composerStopping,
        style: labelStyle,
      ),
      ComposerPrimaryActionKind.continuing => Text(
        context.l10n.composerContinuing,
        style: labelStyle,
      ),
      _ => null,
    };
    if (action.kind == ComposerPrimaryActionKind.continueConversation) {
      final enabled = action.enabled && widget.enabled;
      return [
        if (statusLabel != null) ...[statusLabel, const SizedBox(width: 8)],
        Tooltip(
          message: context.l10n.composerContinueTooltip,
          child: FilledButton.icon(
            key: StudioDriverKeys.composerContinue,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(context.l10n.composerContinue),
            onPressed: enabled ? widget.onContinue : null,
          ),
        ),
      ];
    }
    final stopping = action.kind == ComposerPrimaryActionKind.stopping;
    final sendKind =
        action.kind == ComposerPrimaryActionKind.send ||
        action.kind == ComposerPrimaryActionKind.sendAndContinue;
    final enabled =
        action.enabled &&
        widget.enabled &&
        // 请求在途只禁用按钮：结果尚未结算，不能声称正在停止。同一执行被判定
        // 「结果未确认」后按钮恢复可点，仍用同一目标编号，不换执行。
        !(action.kind == ComposerPrimaryActionKind.stop && !_stopAvailable) &&
        (action.kind != ComposerPrimaryActionKind.stop ||
            widget.onStop != null);
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
      ComposerPrimaryActionKind.continueConversation ||
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
    final busy =
        _submissionPending ||
        stopping ||
        action.kind == ComposerPrimaryActionKind.continuing ||
        // 停止请求在途：进度只表示「请求已发出」，不表示已进入清理。它与主动作
        // 种类无关——运行中有草稿时按钮是「发送并继续」，此刻同样禁用并显示进度。
        (_stopPending && !_stopUnconfirmed);
    return [
      if (statusLabel != null) ...[statusLabel, const SizedBox(width: 8)],
      IconButton.filled(
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
                    : Icons.arrow_upward_rounded,
              ),
        onPressed: !enabled
            ? null
            : action.kind == ComposerPrimaryActionKind.stop
            ? widget.onStop
            : sendKind
            ? _submit
            : null,
      ),
    ];
  }

  Future<void> _showUrlDialog() async {
    final isCurrent = _captureOperationEligibility();
    final onAddUrl = widget.onAddUrl;
    final onReportFailure = widget.onReportFailure;
    var draft = '';
    try {
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
      await onAddUrl(url);
    } catch (error) {
      if (isCurrent()) onReportFailure(error);
    }
  }
}

class _PasteComposerIntent extends Intent {
  const _PasteComposerIntent();
}

class _StopComposerIntent extends Intent {
  const _StopComposerIntent();
}

List<Widget> modelRouteSelectorChildren({
  required List<ModelSelectionAccount> accounts,
  required bool pending,
  bool enabled = true,
  required String unavailableReason,
  String? accountId,
  String? modelId,
  String? effort,
  bool available = true,
  String? routeUnavailableReason,
  String? blockedReason,
  ValueChanged<String>? onExplain,
  ModelSelectionChanged? onModelSelected,
  EffortSelectionChanged? onEffortSelected,
}) {
  final hasRoute =
      accountId != null &&
      modelId != null &&
      accountId.isNotEmpty &&
      modelId.isNotEmpty;
  if (!hasRoute) {
    return [
      RouteUnavailableNotice(reason: unavailableReason),
      ModelRoleSelector(
        accounts: accounts,
        accountId: accountId ?? '',
        modelId: modelId ?? '',
        effort: effort,
        enabled: enabled,
        pending: pending,
        available: false,
        unavailableReason: unavailableReason,
        blockedReason: blockedReason,
        onExplain: onExplain,
        onModelSelected: onModelSelected,
      ),
      UnavailableEffortSelector(reason: unavailableReason),
    ];
  }
  return [
    ModelRoleSelector(
      accounts: accounts,
      accountId: accountId,
      modelId: modelId,
      effort: effort,
      enabled: enabled,
      pending: pending,
      available: available,
      unavailableReason: routeUnavailableReason,
      blockedReason: blockedReason,
      onExplain: onExplain,
      onModelSelected: onModelSelected,
    ),
    ReasoningEffortSelector(
      accounts: accounts,
      accountId: accountId,
      modelId: modelId,
      effort: effort,
      enabled: enabled,
      pending: pending,
      blockedReason: blockedReason,
      onExplain: onExplain,
      onEffortSelected: onEffortSelected,
    ),
  ];
}

class RouteUnavailableNotice extends StatelessWidget {
  const RouteUnavailableNotice({required this.reason, super.key});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_outlined, size: 15, color: colors.error),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            reason,
            key: const ValueKey('model-route-unavailable'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.error),
          ),
        ),
      ],
    );
  }
}

class UnavailableEffortSelector extends StatelessWidget {
  const UnavailableEffortSelector({required this.reason, super.key});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: reason,
      child: StudioMenuLabel(
        key: const ValueKey('effort-route-unavailable'),
        label: reason,
        enabled: false,
        maxWidth: 160,
      ),
    );
  }
}
