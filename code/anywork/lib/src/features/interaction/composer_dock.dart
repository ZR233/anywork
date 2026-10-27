import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../app/app_graph.dart';
import '../../app/theme/studio_tokens.dart';

import '../../l10n/studio_l10n.dart';
import '../../platform/clipboard_image_reader.dart';
import '../../platform/dropped_attachments.dart';
import '../../platform/local_file_dialogs.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/thread_session_store.dart';
import '../../shared/studio_chrome.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/studio_menu_label.dart';
import '../status/session_selectors.dart';
import '../settings/settings_bots_tab.dart' show BotDetailsPage;
import '../../domain/models/composer_primary_action.dart';
import 'composer_view.dart';
import 'child_interaction_dock.dart';
import 'interaction_widgets.dart';
import 'session_settings_menu.dart';
import 'interaction_payload.dart';
import 'multiline_enter_shortcuts.dart';
import '../../presentation/providers/start_session_controller.dart';
import 'plan_confirmation_dock.dart';
import 'tool_approval_dock.dart';
import 'user_input_dock.dart';

part 'composer_attachments.dart';

class ComposerDock extends ConsumerWidget {
  const ComposerDock({required this.threadId, this.compact = false, super.key});

  final String threadId;

  /// 矮窗口紧凑布局：收起留白与输入行数，但发送/停止等操作保持不变。
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(threadSessionStoreProvider(threadId));
    final view = ref.watch(composerDockViewProvider(threadId));
    final thread = view.thread;
    if (thread == null) return const SizedBox.shrink();
    if (thread.status.blocksNewExecution ||
        session.workspace?.thread.status.blocksNewExecution == true) {
      return const SizedBox.shrink();
    }
    final interaction = view.activeInteraction;
    final additionalDiagnostics = [
      for (final diagnostic in view.additionalDiagnostics)
        if (diagnostic != view.targetDiagnostic) diagnostic,
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(12, 4, 12, 6)
            : const EdgeInsets.fromLTRB(12, 7, 12, 12),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: StudioLayout.conversationWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final diagnostic in additionalDiagnostics)
                  _ComposerTargetDiagnosticView(diagnostic: diagnostic),
                // 主会话中展示来源为直接 child 的待决交互；子会话详情不出现这张卡。
                if (!thread.isAgent)
                  ChildInteractionDock(
                    hostThreadId: thread.id,
                    items: view.childInteractions,
                    sources: view.childInteractionSources,
                  ),
                thread.isRetiredAgent
                    ? Text(
                        context.l10n.agentRoleRetired,
                        key: const ValueKey('retired-agent-notice'),
                      )
                    : thread.isAgent
                    // 子会话详情只读：没有输入、停止、继续、答题或审批入口。
                    ? _AgentReadOnlyDock(view: view)
                    : interaction == null
                    ? _PromptComposer(
                        // 输入区是线程级界面：切换会话必须换成新状态，不能把上一个
                        // 会话的失败原因、在途停止/继续标记或模型提示带过去。
                        key: ValueKey('composer-${thread.id}'),
                        thread: thread,
                        view: view,
                        enabled: true,
                        compact: compact,
                      )
                    : _InteractionDock(
                        threadId: thread.id,
                        interaction: interaction,
                        isBusy: view.isBusy,
                        // 活动交互与消息提交仅依赖内存会话。
                        enabled: true,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StartPageComposerDock extends ConsumerWidget {
  const StartPageComposerDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只按项目重建正文状态；键击不重建外层，避免切项目时把上一个正文带过去。
    final projectId = ref.watch(
      startPageComposerViewProvider.select(
        (projection) => projection.project?.id,
      ),
    );
    return _StartPageComposerBody(
      key: ValueKey<String>(projectId ?? ''),
      projectId: projectId,
    );
  }
}

class _StartPageComposerBody extends ConsumerStatefulWidget {
  const _StartPageComposerBody({required this.projectId, super.key});

  final String? projectId;

  @override
  ConsumerState<_StartPageComposerBody> createState() =>
      _StartPageComposerBodyState();
}

class _StartPageComposerBodyState
    extends ConsumerState<_StartPageComposerBody> {
  late final TextEditingController _draft;

  @override
  void initState() {
    super.initState();
    final projectId = widget.projectId;
    final text = projectId == null
        ? ''
        : ref.read(startSessionControllerProvider).forProject(projectId).text;
    _draft = TextEditingController(text: text);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projection = ref.watch(startPageComposerViewProvider);
    final projectId = projection.project?.id;
    final mode = projection.mode;
    // 会话配置与能否提交是两件事：还没有项目或者暂不能提交时，用户仍然可以先选模式和模型，
    // 否则控件看似可点却毫无响应。只有配置未加载完成或提交正在进行时才锁定。
    final selectorsEnabled =
        projection.settingsLoaded && !projection.submitting;
    final route = projection.displayRoute(mode);
    final pending = projection.routePending(mode);
    final model = route == null
        ? null
        : modelForRoute(projection.accounts, route.accountId, route.modelId);
    final composer = projectId == widget.projectId
        ? projection.composer
        : const ComposerThreadState.idle();
    final target = projectId == widget.projectId
        ? projection.targetDiagnostic
        : null;
    final additional = [
      for (final diagnostic in projection.diagnostics)
        if (diagnostic != target) diagnostic,
    ];
    final failure = projection.routeFailure(mode);
    final unavailableReason = failure != null && failure.isNotEmpty
        ? failure
        : context.l10n.statusModelRouteUnavailableFallback;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 12),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: StudioLayout.conversationWidth,
            ),
            child: _PromptComposerPanel(
              composer: composer,
              textController: _draft,
              targetDiagnostic: target,
              additionalDiagnostics: additional,
              enabled: projection.canEdit,
              blocker: projection.recoveryIssue == null
                  ? null
                  : ComposerRecoveryBlocker(projection.recoveryIssue!),
              clipboard: ref.read(clipboardImageReaderProvider),
              selectorBar: Wrap(
                key: StudioDriverKeys.startPageSelectors,
                spacing: 6,
                runSpacing: 4,
                children: [
                  SessionModeSelector(
                    mode: mode,
                    // 草稿模式按项目保存：没有项目就没有可写的落点，先禁用并说明原因，
                    // 不能让它看起来可点却丢掉选择。
                    enabled: selectorsEnabled && projectId != null,
                    lockedHint: projectId == null
                        ? context.l10n.statusModeNeedsProject
                        : context.l10n.statusSelectorsNotReady,
                    onSelected: (next) => _setMode(next),
                  ),
                  ..._modelRouteSelectorChildren(
                    accounts: projection.accounts,
                    accountId: route?.accountId,
                    modelId: route?.modelId,
                    effort: route?.effort,
                    // Unknown capabilities keep selectors disabled until the
                    // Client catalog arrives; no model is admitted by fallback.
                    pending: pending,
                    enabled: selectorsEnabled,
                    unavailableReason: unavailableReason,
                    onModelSelected: (accountId, modelId) {
                      ref
                          .read(anyworkClientProvider)
                          .startDraft
                          .setModelIntent(mode, accountId, modelId);
                    },
                    onEffortSelected: (effort) {
                      ref
                          .read(anyworkClientProvider)
                          .startDraft
                          .setEffortIntent(mode, effort);
                    },
                  ),
                ],
              ),
              submissionLocked: projection.submitting,
              settingsMenu: projectId == null
                  ? null
                  : SessionSettingsMenu(
                      projectId: projectId,
                      enabled: selectorsEnabled,
                    ),
              onChanged: _updateDraft,
              onSubmit: () => unawaited(_submit()),
              inputCapabilities: model?.inputCapabilities ?? const [],
              onPasteImage: _pasteImage,
              onReportFailure: _reportFailure,
              onAddLocal: _addLocal,
              onAddUrl: _addUrl,
              onRemoveAttachment: _removeAttachment,
            ),
          ),
        ),
      ),
    );
  }

  void _updateDraft(String value) {
    final projectId = widget.projectId;
    if (projectId == null) return;
    ref.read(anyworkClientProvider).startDraft.updateDraft(projectId, value);
  }

  void _setMode(ThreadModeId mode) {
    final projectId = widget.projectId;
    if (projectId == null) return;
    ref.read(anyworkClientProvider).startDraft.setMode(projectId, mode);
  }

  Future<void> _submit() async {
    final projectId = widget.projectId;
    if (projectId == null) return;
    final controller = ref.read(anyworkClientProvider).startDraft;
    controller.updateDraft(projectId, _draft.text);
    final accepted = await controller.submit(projectId);
    if (!mounted || !accepted) return;
    final latest = ref
        .read(startSessionControllerProvider)
        .forProject(projectId)
        .text;
    if (_draft.text != latest) {
      _draft.value = TextEditingValue(
        text: latest,
        selection: TextSelection.collapsed(offset: latest.length),
      );
    }
  }

  String? get _projectId => widget.projectId;

  ThreadModeId get _mode {
    final projectId = widget.projectId;
    if (projectId == null) return ThreadModeId.simple;
    return ref.read(startSessionControllerProvider).forProject(projectId).mode;
  }

  Future<void> _pasteImage(Uint8List bytes) {
    final projectId = _projectId;
    if (projectId == null) return Future<void>.value();
    return ref
        .read(anyworkClientProvider)
        .attachments
        .addNewThreadClipboard(
          projectId: projectId,
          mode: _mode,
          pngBytes: bytes,
        );
  }

  void _reportFailure(Object error) {
    final projectId = _projectId;
    if (projectId == null) return;
    ref
        .read(anyworkClientProvider)
        .attachments
        .reportNewThreadFailure(projectId, error);
  }

  Future<void> _addLocal(List<String> paths) {
    final projectId = _projectId;
    if (projectId == null || paths.isEmpty) return Future<void>.value();
    return ref
        .read(anyworkClientProvider)
        .attachments
        .admitNewThread(
          projectId: projectId,
          mode: _mode,
          sources: [
            for (final path in paths) AttachmentDraftSource.localFile(path),
          ],
        );
  }

  Future<void> _addUrl(String url) {
    final projectId = _projectId;
    if (projectId == null) return Future<void>.value();
    return ref
        .read(anyworkClientProvider)
        .attachments
        .addNewThreadRemote(projectId: projectId, mode: _mode, url: url);
  }

  Future<void> _removeAttachment(String draftId) {
    final projectId = _projectId;
    if (projectId == null) return Future<void>.value();
    return ref
        .read(anyworkClientProvider)
        .attachments
        .removeNewThreadDraft(projectId, draftId);
  }
}

/// 子会话详情的只读说明。
///
/// 用户对子智能体的运行控制只有列表行内的停止；详情只展示历史、进展、模型、工作区与
/// 待决状态，等待主智能体调度（design/19 §19.6.1、design/25 §25.8）。
class _AgentReadOnlyDock extends StatelessWidget {
  const _AgentReadOnlyDock({required this.view});

  final ComposerDockView view;

  @override
  Widget build(BuildContext context) {
    final thread = view.thread;
    final secondaryStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: context.colors.onSurfaceVariant);
    final route = view.displayRoute;
    final execution = view.execution;
    final pending = view.activeInteraction;
    final continuation = view.continuation;
    // 只有在 canonical 确实等待调度（有未认领继续点且没有当前执行）时才说明；
    // 执行中的成员不能同时显示「正在运行」和「等待调度」。
    final waitingForScheduling =
        execution == null && continuation != null && !continuation.claimed;
    return StudioPanel(
      key: StudioDriverKeys.agentReadOnlyPanel,
      backgroundColor: context.colors.surfaceContainer,
      borderColor: context.colors.outlineVariant,
      radius: StudioRadii.lg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 18,
                color: context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  context.l10n.composerAgentReadOnlyTitle,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (waitingForScheduling)
            Text(
              context.l10n.composerAgentReadOnlyWaiting,
              key: const ValueKey('agent-readonly-waiting'),
              style: secondaryStyle,
            ),
          Text(
            context.l10n.composerAgentReadOnlyScope,
            key: const ValueKey('agent-readonly-scope'),
            style: secondaryStyle,
          ),
          if (pending != null)
            Text(
              context.l10n.composerAgentReadOnlyPending,
              key: const ValueKey('agent-readonly-pending'),
              style: secondaryStyle,
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              InfoChip(
                icon: Icons.timeline_outlined,
                label: context.threadStatusLabel(thread!.status),
              ),
              if (execution != null)
                InfoChip(
                  icon: Icons.bolt_outlined,
                  label: context.threadStatusLabel(
                    execution.phase == AgentExecutionPhase.stopping
                        ? ThreadStatusView.cancelling
                        : ThreadStatusView.running,
                  ),
                ),
              if (route != null)
                InfoChip(icon: Icons.memory_outlined, label: route.modelId),
              if (thread.workspacePath.trim().isNotEmpty)
                InfoChip(
                  icon: Icons.folder_outlined,
                  label: thread.workspacePath,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PromptComposer extends ConsumerStatefulWidget {
  const _PromptComposer({
    required this.thread,
    required this.view,
    required this.enabled,
    this.compact = false,
    super.key,
  });

  final StudioThread thread;
  final ComposerDockView view;
  final bool enabled;
  final bool compact;

  @override
  ConsumerState<_PromptComposer> createState() => _PromptComposerState();
}

class _PromptComposerState extends ConsumerState<_PromptComposer> {
  String? _modelNotice;

  /// 已受理、尚未观察到继续生效的继续点身份。
  String? _continueAcceptedId;

  /// 已发出、尚未收到受理回执的继续点身份：在途不等于已受理。
  String? _continueInFlightId;

  /// 被明确拒绝或结果未知的最近一次继续/停止原因。
  ComposerBlocker? _failureBlocker;

  /// 用户重试被 Client 排队的那个命令登记时间（纯视觉信号）。
  ///
  /// `StopQueued` 表示这次点击已排在当前在途请求之后、尚未发出：界面按「请求在途」
  /// 渲染（隐藏未确认提示、保持禁用），也不新建计时；排队重试真正发出时会换登记
  /// 时间，该信号自动失效。
  int? _queuedStopStartedAtMs;

  @override
  void didUpdateWidget(covariant _PromptComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 会话身份变化：线程级本地状态一律清空。迟到的异步回调即使仍然 mounted，也只
    // 属于发起它的那个会话，由回调内的 threadId 校验丢弃。
    if (oldWidget.thread.id != widget.thread.id) {
      _modelNotice = null;
      _failureBlocker = null;
      _continueAcceptedId = null;
      _continueInFlightId = null;
      return;
    }
    if (oldWidget.thread.id != widget.thread.id ||
        oldWidget.thread.status != widget.thread.status ||
        oldWidget.view.displayRoute != widget.view.displayRoute) {
      _modelNotice = null;
    }
    if (oldWidget.view.continuation?.id != widget.view.continuation?.id ||
        oldWidget.view.execution?.id != widget.view.execution?.id) {
      _continueAcceptedId = null;
      _continueInFlightId = null;
    }
    // 失败原因保留到下一次显式操作：它可能与同一帧到达的进度事实一起出现，
    // 这时清掉会把「刚被拒绝」静默变成「什么都没发生」。
  }

  /// 主会话精确停止：目标取该会话 canonical 执行身份，切换选中会话不会重定向。
  ///
  /// 点击时把**渲染这一帧的**执行编号作为 `expectedExecutionId` 交给 Client：命令排队
  /// 期间不会改选别的执行，过时由服务端以 typed `staleExecution` 拒绝，界面不重试成
  /// 新编号。
  ///
  /// 停止三态（在途 / 已受理在停止 / 无）完全由 Client 命令板派生：`_stopExecution`
  /// 只把 `CommandStatus.accepted` 置位来表示「已收到需身份观察的受理回执」。因此这
  /// 里不再记任何受理标记，重建或切换会话回来读到的仍是同一事实。
  ///
  /// 请求序号只用于让「结果未确认」提示在重试后重新计时，不参与判定停止状态。
  void _requestStop() {
    final execution = widget.view.execution;
    if (execution == null) return;
    final threadId = widget.thread.id;
    final commands = ref.read(anyworkClientProvider).threadCommands;
    // 本次点击之前该键的登记时间：被排队时用它标记「这次重试尚未发出」。
    final queuedAtMs = widget.view.stopCommand?.startedAtMs;
    setState(() => _failureBlocker = null);
    unawaited(
      commands
          .stop(threadId, expectedExecutionId: execution.id)
          .then(
            (outcome) {
              // 受理与否由命令板表达（`accepted` / 条目消失），界面不再另记一份；
              // 这里只做一次跨会话校验，迟到结果不落到别的会话。
              if (!_ownsLateCallback(threadId)) return;
              switch (outcome) {
                // 已受理：命令板随即将 `accepted` 置位，界面据此显示「正在停止」。
                case StopRequested():
                // 没有产生请求：命令板不会出现条目，界面按 canonical 渲染。
                case StopNoExecution():
                case StopNotQualified():
                  break;
                // 排队重试：这次点击尚未发出（Client 至多一个在途 + 一个排队）。
                // 界面继续按「请求在途」渲染、保持禁用，不当作成功、不清草稿、
                // 也不新建计时。
                case StopQueued():
                  setState(() => _queuedStopStartedAtMs = queuedAtMs);
              }
            },
            onError: (Object error) {
              if (!_ownsLateCallback(threadId)) return;
              // 未被受理：回到可停止状态，草稿不受影响。原因通常由命令板承载
              // （`stop:<threadId>` 的 failed 状态），命令板没记到时才用本地回退，
              // 避免同一原因显示两行。
              final board = ref
                  .read(anyworkClientProvider)
                  .threadCommands
                  .state
                  .commands['stop:$threadId'];
              setState(() {
                _failureBlocker = board?.phase == CommandPhase.failed
                    ? null
                    : ComposerFailureBlocker(
                        studioFailureReason(error),
                        recoveryIssue: recoveryIssueFromFailure(
                          error is StudioFailure ? error : null,
                        ),
                      );
              });
            },
          ),
    );
  }

  /// 迟到回调是否仍属于当前会话。
  ///
  /// 输入区是线程级界面：请求在途时切换会话，旧会话的受理或失败不得写进新会话的
  /// 状态。这种情况下只请一次 canonical 重读，让旧会话的事实自己收敛。
  bool _ownsLateCallback(String threadId) {
    if (!mounted) return false;
    if (widget.thread.id == threadId) return true;
    ref.read(anyworkClientProvider).retrySession(threadId);
    return false;
  }

  /// 无内容继续：显式点击才发起，携带已观察的模型路由版本。
  void _requestContinue() {
    final continuation = widget.view.continuation;
    if (continuation == null) return;
    final revision = widget.view.modelRoute?.revision;
    if (revision == null) {
      setState(() => _failureBlocker = const ComposerModelBlocker());
      return;
    }
    final threadId = widget.thread.id;
    final commands = ref.read(anyworkClientProvider).threadCommands;
    setState(() {
      // 请求在途不是已受理：受理状态只在拿到回执后设置。
      _continueInFlightId = continuation.id;
      _failureBlocker = null;
    });
    unawaited(
      commands
          .continueThread(
            threadId,
            continuation,
            expectedModelRouteRevision: revision,
          )
          .then(
            (_) {
              if (!_ownsLateCallback(threadId)) return;
              setState(() {
                _continueInFlightId = null;
                _continueAcceptedId = continuation.id;
              });
            },
            onError: (Object error) {
              if (!_ownsLateCallback(threadId)) return;
              setState(() {
                _continueInFlightId = null;
                _continueAcceptedId = null;
                _failureBlocker = ComposerFailureBlocker(
                  studioFailureReason(error),
                  recoveryIssue: recoveryIssueFromFailure(
                    error is StudioFailure ? error : null,
                  ),
                );
              });
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final view = widget.view;
    final route = view.displayRoute;
    final model = route == null
        ? null
        : modelForRoute(view.accounts, route.accountId, route.modelId);
    final blockedReason = switch (thread.status) {
      // Turn 真正结束后的 canonical idle 即可换路由：workflow run/阶段保持 active
      // 不再阻塞，新路由在下一次输入生效，也不重置 workflow/Plan（design/19 §19.2）。
      ThreadStatusView.idle => null,
      ThreadStatusView.closing ||
      ThreadStatusView.closed ||
      ThreadStatusView.faulted => context.l10n.statusModelSwitchWhileInactive,
      _ => context.l10n.statusModelSwitchWhileRunning,
    };
    final failure = view.routeFailure;
    final unavailableReason = failure != null && failure.isNotEmpty
        ? failure
        : context.l10n.statusModelRouteUnavailableFallback;
    final draftController = ref
        .read(anyworkClientProvider)
        .existingComposer(thread.id);
    if (draftController == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (view.composer.error case final error?) Text(error),
          TextButton(
            onPressed: () =>
                ref.read(anyworkClientProvider).retrySession(thread.id),
            child: Text(context.l10n.runtimeFatalRetry),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_modelNotice case final message?)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: StudioPanel(
              backgroundColor: context.colors.surfaceContainer,
              borderColor: context.colors.outlineVariant,
              radius: StudioRadii.lg,
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 80),
                      child: SingleChildScrollView(child: Text(message)),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('model-notice-dismiss'),
                    tooltip: context.l10n.statusModelNoticeDismiss,
                    onPressed: () => setState(() => _modelNotice = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
        _PromptComposerPanel(
          composer: view.composer,
          targetDiagnostic: view.targetDiagnostic,
          enabled: widget.enabled,
          execution: view.execution,
          continuation: view.continuation,
          continuationAccepted:
              _continueAcceptedId != null &&
              _continueAcceptedId == view.continuation?.id,
          continuationPending:
              _continueInFlightId != null &&
              _continueInFlightId == view.continuation?.id,
          // canonical 阻塞决定准入；上一次被拒绝的原因单独展示，不能盖掉它。
          blocker: view.canonicalBlocker,
          failure: _failureBlocker,
          stopCommand: view.stopCommand,
          queuedStopStartedAtMs: _queuedStopStartedAtMs,
          compact: widget.compact,
          clipboard: ref.read(clipboardImageReaderProvider),
          selectorBar: thread.isRoot
              ? Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 2,
                  runSpacing: 4,
                  children: [
                    SessionModeSelector(
                      mode: thread.mode,
                      usesSnapshot: true,
                      snapshotDisplayName:
                          view.workflow?.currentRun?.modeDisplayName,
                      enabled:
                          !view.hasActiveWorkflow &&
                          thread.status == ThreadStatusView.idle &&
                          view.activeInteraction == null,
                      onExplain: (message) =>
                          setState(() => _modelNotice = message),
                      onSelected: (mode) => unawaited(
                        ref
                            .read(anyworkClientProvider)
                            .threadCommands
                            .setThreadMode(mode),
                      ),
                    ),
                    if (view.modelRoute?.botId case final botId?)
                      TextButton.icon(
                        key: const ValueKey('bot-model-settings'),
                        icon: const Icon(Icons.smart_toy_outlined, size: 16),
                        label: Text(
                          '${route?.modelId ?? ''} · ${context.l10n.botsManagedModel}',
                        ),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => BotDetailsPage(botId: botId),
                          ),
                        ),
                      )
                    else
                      ..._modelRouteSelectorChildren(
                        accounts: view.accounts,
                        accountId: route?.accountId,
                        modelId: route?.modelId,
                        effort: route?.effort,
                        enabled: view.settingsLoaded,
                        pending: view.routePending,
                        available: route?.available ?? false,
                        routeUnavailableReason: route?.unavailableReason,
                        unavailableReason: unavailableReason,
                        blockedReason: blockedReason,
                        onExplain: (message) =>
                            setState(() => _modelNotice = message),
                        onModelSelected: (accountId, modelId) {
                          unawaited(
                            ref
                                .read(anyworkClientProvider)
                                .threadCommands
                                .setThreadModelRoute(
                                  threadId: thread.id,
                                  accountId: accountId,
                                  modelId: modelId,
                                  effort:
                                      ModelRouteQueries.effortAfterModelSelection(
                                        ModelRouteQueries.model(
                                          view.accounts,
                                          accountId,
                                          modelId,
                                        ),
                                        route?.effort,
                                      ),
                                ),
                          );
                        },
                        onEffortSelected: (effort) {
                          if (route == null) return;
                          unawaited(
                            ref
                                .read(anyworkClientProvider)
                                .threadCommands
                                .setThreadModelRoute(
                                  threadId: thread.id,
                                  accountId: route.accountId,
                                  modelId: route.modelId,
                                  effort: effort,
                                ),
                          );
                        },
                      ),
                  ],
                )
              : null,
          onChanged: draftController.updateDraft,
          onSubmit: () {
            // 草案 owner 先同步冻结目标、payload、route 与 operation，再等待展示准备；
            // 这里只捕当前 Thread 身份，不改动已冻结的目标（design/26 §26.8）。
            final target = thread.id;
            unawaited(
              draftController.submit(
                beforeSubmit: () =>
                    ref.read(appGraphProvider).timeline.prepareSend(target),
              ),
            );
          },
          onStop: _requestStop,
          onContinue: _requestContinue,
          inputCapabilities: model?.inputCapabilities ?? const [],
          onPasteImage: draftController.addClipboardImage,
          onReportFailure: draftController.reportFailure,
          onAddLocal: draftController.addLocalAttachments,
          onAddUrl: draftController.addRemoteAttachment,
          onRemoveAttachment: draftController.removeAttachment,
        ),
      ],
    );
  }
}

/// 原因区的最大高度：三行文案在窄矮窗口里换行时改在区内滚动，不撑破底栏。
const double _composerReasonMaxHeight = 84;

/// 非 Recovery 原因的最大行数；Recovery 诊断在受限滚动区域内完整展示。
const int _composerReasonMaxLines = 3;

StudioRecoveryIssue? _recoveryIssueForBlocker(ComposerBlocker? blocker) {
  if (blocker is ComposerRecoveryBlocker) return blocker.issue;
  if (blocker is ComposerFailureBlocker) return blocker.recoveryIssue;
  return null;
}

StudioRecoveryIssue? _composerFailureRecoveryIssue(
  ComposerThreadState composer,
) {
  final failure = composer.failure;
  return recoveryIssueFromFailure(failure is StudioFailure ? failure : null);
}

bool _sameRecoveryDiagnostic(
  StudioRecoveryIssue left,
  StudioRecoveryIssue right,
) {
  if (left.id != right.id ||
      left.scope != right.scope ||
      left.category != right.category ||
      left.impact != right.impact ||
      left.projectId != right.projectId ||
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

bool _showRawComposerError(ComposerThreadState composer) =>
    _composerFailureRecoveryIssue(composer) == null;

class _PromptComposerPanel extends StatefulWidget {
  const _PromptComposerPanel({
    required this.composer,
    this.targetDiagnostic,
    this.additionalDiagnostics = const [],
    required this.enabled,
    required this.clipboard,
    required this.onChanged,
    required this.onSubmit,
    required this.inputCapabilities,
    required this.onPasteImage,
    required this.onReportFailure,
    required this.onAddLocal,
    required this.onAddUrl,
    required this.onRemoveAttachment,
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

  final ClipboardImageReader clipboard;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final List<ModelInputCapabilityView> inputCapabilities;
  final Future<void> Function(Uint8List pngBytes) onPasteImage;
  final ValueChanged<Object> onReportFailure;
  final Future<void> Function(List<String> paths) onAddLocal;
  final Future<void> Function(String url) onAddUrl;
  final Future<void> Function(String draftId) onRemoveAttachment;
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
  State<_PromptComposerPanel> createState() => _PromptComposerPanelState();
}

class _ComposerTargetDiagnosticView extends StatelessWidget {
  const _ComposerTargetDiagnosticView({required this.diagnostic});

  final ComposerTargetDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 17,
                color: colors.error,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    diagnostic.message,
                    key: ValueKey(
                      'composer-target-diagnostic-${diagnostic.targetKey}',
                    ),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.error),
                  ),
                  if (diagnostic.cleanupFailureDraftIds.isNotEmpty)
                    Text(
                      'Cleanup failed draft IDs: '
                      '${diagnostic.cleanupFailureDraftIds.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.error),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptComposerPanelState extends State<_PromptComposerPanel> {
  TextEditingController? _ownedController;
  bool _dragging = false;
  bool _pasteInFlight = false;
  bool _syncingDraft = false;

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
        command.target.label == execution.id;
  }

  /// 该停止请求已收到需要身份观察的受理回执（命令板 `accepted`）。
  ///
  /// 它表示「已受理、仍在等 canonical 收敛」：界面显示「正在停止」，不再提供停止或
  /// 提交入口。这是命令板事实，重建与切换会话后读到的一致。
  bool get _stopAccepted =>
      _stopPending && (widget.stopCommand?.accepted ?? false);

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
    return ComposerFailureBlocker(
      command.error?.reason,
      recoveryIssue: recoveryIssueFromFailure(command.error),
    );
  }

  @override
  void dispose() {
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
  void didUpdateWidget(covariant _PromptComposerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  Future<void> _pasteClipboard() async {
    _pasteInFlight = true;
    try {
      final image = await widget.clipboard.readImage();
      if (!mounted) return;
      if (image != null) {
        if (!_supportsPastedImages) {
          widget.onReportFailure(
            StateError(context.l10n.composerClipboardImageUnsupported),
          );
          return;
        }
        await widget.onPasteImage(image);
        return;
      }
      final text = await widget.clipboard.readText();
      if (!mounted || text == null || text.isEmpty) return;
      _pasteText(text);
    } catch (_) {
      if (mounted) {
        widget.onReportFailure(
          StateError(context.l10n.composerClipboardReadFailed),
        );
      }
    } finally {
      _pasteInFlight = false;
    }
  }

  void _pasteText(String text) {
    final value = _controller.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final collapsed = value.copyWith(
      selection: TextSelection.collapsed(offset: selection.end),
      composing: TextRange.empty,
    );
    _controller.value = collapsed.replaced(selection, text);
    widget.onChanged(_controller.text);
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
            _AttachmentDraftRail(
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
            _ComposerTargetDiagnosticView(diagnostic: diagnostic),
          for (final diagnostic in widget.additionalDiagnostics)
            _ComposerTargetDiagnosticView(diagnostic: diagnostic),
          ?_reasonRegion(
            context,
            blocker: blocker,
            continuationNote: showContinuationNote ? continuationNote : null,
          ),
          Row(
            children: [
              _AttachmentMenu(
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

  /// 原因区：canonical 阻塞、typed 失败与中断原因各自成行，一处也不丢弃。
  ///
  /// 整体套在受高度约束的滚动容器内：普通原因限制行数，Recovery 诊断则完整保留四行
  /// 及长 detail/actions，通过区内滚动访问，不撑破外层 footer。
  Widget? _reasonRegion(
    BuildContext context, {
    required ComposerBlocker? blocker,
    required String? continuationNote,
  }) {
    final stopFailure = _stopFailure;
    final composerRecoveryIssue = _composerFailureRecoveryIssue(
      widget.composer,
    );
    final recoveryAlreadyDisplayed =
        composerRecoveryIssue != null &&
        [
          _recoveryIssueForBlocker(blocker),
          _recoveryIssueForBlocker(widget.failure),
          _recoveryIssueForBlocker(stopFailure),
        ].whereType<StudioRecoveryIssue>().any(
          (issue) => _sameRecoveryDiagnostic(issue, composerRecoveryIssue),
        );
    final lines = <Widget>[
      if (blocker != null)
        _reasonLine(
          context,
          context.composerBlockerLabel(blocker),
          StudioDriverKeys.composerBlocker,
          emphasized: true,
          maxLines: _recoveryIssueForBlocker(blocker) == null
              ? _composerReasonMaxLines
              : null,
        ),
      // 上一次继续/提交被拒绝或结果未知的原因单独成行：它不改变 canonical 阻塞的
      // 准入判定，也不会因为 canonical 阻塞出现而消失。
      if (widget.failure case final failure?)
        _reasonLine(
          context,
          context.composerBlockerLabel(failure),
          const ValueKey('composer-failure'),
          emphasized: true,
          maxLines: _recoveryIssueForBlocker(failure) == null
              ? _composerReasonMaxLines
              : null,
        ),
      // 停止被拒绝的原因来自 Client 命令板：它跨重建与切换会话可见，因此单独成行，
      // 既不会掩盖上面的原因，也不会被上面掩盖。
      if (stopFailure != null)
        _reasonLine(
          context,
          context.composerBlockerLabel(stopFailure),
          const ValueKey('composer-stop-failure'),
          emphasized: true,
          maxLines: _recoveryIssueForBlocker(stopFailure) == null
              ? _composerReasonMaxLines
              : null,
        ),
      if (composerRecoveryIssue != null && !recoveryAlreadyDisplayed)
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
        key: StudioDriverKeys.composerContinuing,
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
      // 状态本身由旁边的可见文字拥有稳定键，按钮只是禁用态。
      ComposerPrimaryActionKind.stopping => const ValueKey(
        'composer-stopping-disabled',
      ),
      ComposerPrimaryActionKind.continuing => const ValueKey(
        'composer-continuing-disabled',
      ),
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

  Future<void> _dropAttachments(DropDetails details) async {
    final admit = widget.onAddLocal;
    final reportFailure = widget.onReportFailure;
    try {
      await admitDroppedAttachments(
        details.items.whereType<DropFileItem>(),
        admit,
      );
    } catch (error) {
      reportFailure(error);
    }
  }

  Future<void> _pickLocalAttachments(
    List<ModelInputCapabilityView> capabilities,
  ) async {
    final admit = widget.onAddLocal;
    final reportFailure = widget.onReportFailure;
    try {
      const driverFixture = String.fromEnvironment(
        'ANYWORK_DRIVER_ATTACHMENT_PATH',
      );
      if (const bool.fromEnvironment('ANYWORK_DRIVER') &&
          driverFixture.isNotEmpty) {
        await admit([driverFixture]);
        return;
      }
      final modalities = capabilities
          .map((capability) => capability.modality)
          .toSet();
      final acceptsFiles = modalities.contains(ModelModalityView.file);
      final paths = await pickLocalAttachmentPaths(
        extensions: acceptsFiles
            ? const []
            : [
                if (modalities.contains(ModelModalityView.image)) ...[
                  'png',
                  'jpg',
                  'jpeg',
                  'gif',
                  'webp',
                ],
                if (modalities.contains(ModelModalityView.video)) ...[
                  'mp4',
                  'mov',
                  'webm',
                  'mkv',
                ],
              ],
      );
      if (paths.isNotEmpty) await admit(paths);
    } catch (error) {
      reportFailure(error);
    }
  }

  Future<void> _showUrlDialog() async {
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
    if (url != null && url.isNotEmpty) await widget.onAddUrl(url);
  }
}

class _PasteComposerIntent extends Intent {
  const _PasteComposerIntent();
}

class _StopComposerIntent extends Intent {
  const _StopComposerIntent();
}

class _InteractionDock extends StatelessWidget {
  const _InteractionDock({
    required this.threadId,
    required this.interaction,
    required this.isBusy,
    required this.enabled,
  });

  final String threadId;
  final PendingInteraction interaction;
  final bool isBusy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final trailing = isBusy ? _StopButton(threadId: threadId) : null;
    final plan = interaction.planConfirmation;
    if (plan != null) {
      return PlanConfirmationDock(
        threadId: threadId,
        plan: plan,
        enabled: enabled,
        trailing: trailing,
      );
    }
    final payload = InteractionPayloadSnapshot.from(interaction);
    return switch (interaction.kind) {
      InteractionKind.toolApproval => ToolApprovalDock(
        threadId: threadId,
        interactionId: interaction.id,
        payload: payload,
        enabled: enabled,
        trailing: trailing,
      ),
      InteractionKind.userInput => UserInputDock(
        threadId: threadId,
        interactionId: interaction.id,
        payload: payload,
        enabled: enabled,
        trailing: trailing,
      ),
    };
  }
}

class _StopButton extends ConsumerWidget {
  const _StopButton({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton.filledTonal(
      tooltip: context.l10n.composerStop,
      icon: const Icon(Icons.stop),
      onPressed: () => unawaited(
        ref.read(anyworkClientProvider).threadCommands.stop(threadId),
      ),
    );
  }
}

/// route 为空时仍保留模型选择器，并显示不可用原因，避免静默隐藏。
List<Widget> _modelRouteSelectorChildren({
  required List<AccountSettingsView> accounts,
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
      _RouteUnavailableNotice(reason: unavailableReason),
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
      _UnavailableEffortSelector(reason: unavailableReason),
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

class _RouteUnavailableNotice extends StatelessWidget {
  const _RouteUnavailableNotice({required this.reason});

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

class _UnavailableEffortSelector extends StatelessWidget {
  const _UnavailableEffortSelector({required this.reason});

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
