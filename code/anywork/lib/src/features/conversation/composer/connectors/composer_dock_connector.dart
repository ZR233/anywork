import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../../../app/theme/studio_tokens.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/clipboard_image_reader.dart';
import '../../../../platform/dropped_attachments.dart';
import '../../../../platform/local_file_dialogs.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../status/session_selectors.dart';
import '../../../../shared/studio_routes.dart';
import '../view_models/composer_view_model.dart';
import '../state/composer_view_state.dart';
import '../../interactions/connectors/child_interaction_connector.dart';
import 'session_settings_connector.dart';
import '../views/composer_support_views.dart';
import '../views/composer_dock_view.dart';
import '../views/start_page_composer_view.dart';
import '../../interactions/state/interaction_payload.dart';
import '../../../../presentation/providers/start_session_controller.dart';
import '../../../../presentation/providers/selection_store.dart';
import '../../interactions/connectors/plan_confirmation_connector.dart';
import '../../interactions/connectors/tool_approval_connector.dart';
import '../../interactions/connectors/user_input_connector.dart';
import '../views/prompt_composer_view.dart';

class ComposerDockConnector extends ConsumerWidget {
  const ComposerDockConnector({
    required this.threadId,
    this.compact = false,
    super.key,
  });

  final String threadId;

  /// 矮窗口紧凑布局：收起留白与输入行数，但发送/停止等操作保持不变。
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewAsync = ref.watch(composerDockViewModelProvider(threadId));
    if (viewAsync.isLoading) {
      return const SafeArea(child: LinearProgressIndicator());
    }
    if (viewAsync.hasError) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('${viewAsync.error}'),
        ),
      );
    }
    final view = viewAsync.requireValue;
    final thread = view.thread;
    if (thread == null) return const SizedBox.shrink();
    final interaction = view.activeInteraction;
    final additionalDiagnostics = [
      for (final diagnostic in view.additionalDiagnostics)
        if (diagnostic != view.targetDiagnostic) diagnostic,
    ];
    return ComposerDockView(
      compact: compact,
      additionalDiagnostics: [
        for (final diagnostic in additionalDiagnostics)
          ComposerTargetDiagnosticView(diagnostic: diagnostic),
      ],
      childInteractions: thread.isAgent
          ? null
          : ChildInteractionConnector(
              key: ValueKey((thread.id, view.childInteractionGeneration)),
              hostThreadId: thread.id,
              displayGeneration: view.childInteractionGeneration,
              items: view.childInteractions,
              sources: view.childInteractionSources,
            ),
      content: thread.isRetiredAgent
          ? Text(
              context.l10n.agentRoleRetired,
              key: const ValueKey('retired-agent-notice'),
            )
          : thread.isAgent
          ? AgentReadOnlyDockView(view: view)
          : interaction == null
          ? _PromptComposer(
              key: ValueKey('composer-${thread.id}'),
              thread: thread,
              view: view,
              enabled: true,
              compact: compact,
            )
          : _InteractionDock(
              threadId: thread.id,
              interaction: interaction,
              stop: view.interactionStop,
              enabled: true,
            ),
    );
  }
}

class StartPageComposerDockConnector extends ConsumerWidget {
  const StartPageComposerDockConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只按项目重建正文状态；键击不重建外层，避免切项目时把上一个正文带过去。
    final projectId = ref.watch(selectionStoreProvider).selectedProjectId;
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
    final projectionAsync = ref.watch(startPageComposerViewModelProvider);
    if (projectionAsync.isLoading) {
      return const SafeArea(child: LinearProgressIndicator());
    }
    if (projectionAsync.hasError) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('${projectionAsync.error}'),
        ),
      );
    }
    final projection = projectionAsync.requireValue;
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
    final selectorBar = Wrap(
      key: StudioDriverKeys.startPageSelectors,
      spacing: 6,
      runSpacing: 4,
      children: [
        SessionModeSelector(
          mode: mode,
          enabled: selectorsEnabled && projectId != null,
          lockedHint: projectId == null
              ? context.l10n.statusModeNeedsProject
              : context.l10n.statusSelectorsNotReady,
          onSelected: _setMode,
        ),
        ...modelRouteSelectorChildren(
          accounts: projection.accounts,
          accountId: route?.accountId,
          modelId: route?.modelId,
          effort: route?.effort,
          pending: pending,
          enabled: selectorsEnabled,
          unavailableReason: unavailableReason,
          onModelSelected: (accountId, modelId) => ref
              .read(startPageComposerViewModelProvider.notifier)
              .setModelIntent(mode, accountId, modelId),
          onEffortSelected: (effort) => ref
              .read(startPageComposerViewModelProvider.notifier)
              .setEffortIntent(mode, effort),
        ),
      ],
    );
    return StartPageComposerView(
      composer: composer,
      controller: _draft,
      pasteTargetId: widget.projectId,
      targetDiagnostic: target,
      additionalDiagnostics: additional,
      enabled: projection.canSubmit,
      submissionLocked: projection.submitting,
      showSubmissionError:
          projection.preparation?.failure?.toString() != composer.error,
      inputCapabilities: model?.inputCapabilities ?? const [],
      selectorBar: selectorBar,
      settingsMenu: projectId == null
          ? null
          : SessionSettingsConnector(
              projectId: projectId,
              enabled: selectorsEnabled,
            ),
      onChanged: _updateDraft,
      onSubmit: () => unawaited(_submit()),
      onPasteClipboard: (pasteText, supportsImages, isCurrent) =>
          _pasteClipboardFromConnector(
            context,
            ref.read(clipboardImageReaderProvider),
            pasteText,
            supportsImages,
            isCurrent: isCurrent,
            onPasteImage: _pasteImage,
            onReportFailure: _reportFailure,
          ),
      onPasteImage: _pasteImage,
      onReportFailure: _reportFailure,
      onPickLocalAttachments: (capabilities, isCurrent) =>
          _pickAttachmentsFromConnector(
            capabilities,
            _addLocal,
            _reportFailure,
            isCurrent: () =>
                context.mounted && isCurrent() && widget.projectId == projectId,
          ),
      onDropAttachments: (details, isCurrent) => _dropAttachmentsFromConnector(
        details,
        _addLocal,
        _reportFailure,
        isCurrent: () =>
            context.mounted && isCurrent() && widget.projectId == projectId,
      ),
      onAddLocal: _addLocal,
      onAddUrl: _addUrl,
      onRemoveAttachment: _removeAttachment,
    );
  }

  void _updateDraft(String value) {
    final projectId = widget.projectId;
    if (projectId == null) return;
    ref
        .read(startPageComposerViewModelProvider.notifier)
        .updateDraft(projectId, value);
  }

  void _setMode(ThreadModeId mode) {
    final projectId = widget.projectId;
    if (projectId == null) return;
    ref
        .read(startPageComposerViewModelProvider.notifier)
        .setMode(projectId, mode);
  }

  Future<void> _submit() async {
    final projectId = widget.projectId;
    if (projectId == null) return;
    final controller = ref.read(startPageComposerViewModelProvider.notifier);
    controller.updateDraft(projectId, _draft.text);
    final accepted = await controller.submitStart(projectId);
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
        .read(startPageComposerViewModelProvider.notifier)
        .pasteImage(projectId, _mode, bytes);
  }

  void _reportFailure(Object error) {
    final projectId = _projectId;
    if (projectId == null) return;
    ref
        .read(startPageComposerViewModelProvider.notifier)
        .reportAttachmentFailure(projectId, error);
  }

  Future<void> _addLocal(List<String> paths) {
    final projectId = _projectId;
    if (projectId == null || paths.isEmpty) return Future<void>.value();
    return ref
        .read(startPageComposerViewModelProvider.notifier)
        .admitAttachments(
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
        .read(startPageComposerViewModelProvider.notifier)
        .addRemoteAttachment(projectId, _mode, url);
  }

  Future<void> _removeAttachment(String draftId) {
    final projectId = _projectId;
    if (projectId == null) return Future<void>.value();
    return ref
        .read(startPageComposerViewModelProvider.notifier)
        .removeAttachment(projectId, draftId);
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
  final ComposerDockViewState view;
  final bool enabled;
  final bool compact;

  @override
  ConsumerState<_PromptComposer> createState() => _PromptComposerState();
}

class _PromptComposerState extends ConsumerState<_PromptComposer> {
  String? _modelNotice;

  @override
  void didUpdateWidget(covariant _PromptComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 会话身份变化：线程级本地状态一律清空。迟到的异步回调即使仍然 mounted，也只
    // 属于发起它的那个会话，由回调内的 threadId 校验丢弃。
    if (oldWidget.thread.id != widget.thread.id) {
      _modelNotice = null;
      return;
    }
    if (oldWidget.thread.id != widget.thread.id ||
        oldWidget.thread.status != widget.thread.status ||
        oldWidget.view.displayRoute != widget.view.displayRoute) {
      _modelNotice = null;
    }
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
    final viewModel = ref.read(
      composerDockViewModelProvider(threadId).notifier,
    );
    unawaited(
      viewModel
          .stop(threadId, expectedExecutionId: execution.id)
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  /// 无内容继续：显式点击才发起，携带已观察的模型路由版本。
  void _requestContinue() {
    final continuation = widget.view.continuation;
    if (continuation == null) return;
    final revision = widget.view.modelRoute?.revision;
    if (revision == null) {
      setState(
        () => _modelNotice = context.l10n.statusModelRouteUnavailableFallback,
      );
      return;
    }
    final threadId = widget.thread.id;
    final viewModel = ref.read(
      composerDockViewModelProvider(threadId).notifier,
    );
    unawaited(
      viewModel
          .continueExecution(
            threadId,
            continuation,
            expectedModelRouteRevision: revision,
          )
          .then<void>((_) {}, onError: (Object _) {}),
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
        .drafts
        .existingComposer(thread.id);
    if (draftController == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (view.composer.error case final error?) Text(error),
          TextButton(
            onPressed: () => ref
                .read(composerDockViewModelProvider(thread.id).notifier)
                .refreshSession(thread.id),
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
        PromptComposerView(
          composer: view.composer,
          pasteTargetId: thread.id,
          targetDiagnostic: view.targetDiagnostic,
          enabled: widget.enabled,
          execution: view.execution,
          continuation: view.continuation,
          continuationAccepted: view.continuationAccepted,
          continuationPending: view.continuationPending,
          // canonical 阻塞决定准入；上一次被拒绝的原因单独展示，不能盖掉它。
          blocker: view.canonicalBlocker,
          failure: view.operationFailure,
          stopCommand: view.stopCommand,
          queuedStopStartedAtMs: view.queuedStopStartedAtMs,
          compact: widget.compact,
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
                            .read(
                              composerDockViewModelProvider(thread.id).notifier,
                            )
                            .setThreadMode(mode, threadId: thread.id),
                      ),
                    ),
                    if (view.modelRoute?.botId case final botId?)
                      TextButton.icon(
                        key: const ValueKey('bot-model-settings'),
                        icon: const Icon(Icons.smart_toy_outlined, size: 16),
                        label: Text(
                          '${route?.modelId ?? ''} · ${context.l10n.botsManagedModel}',
                        ),
                        onPressed: () =>
                            StudioRoutes.openBotDetails(context, botId),
                      )
                    else
                      ...modelRouteSelectorChildren(
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
                                .read(
                                  composerDockViewModelProvider(thread.id)
                                      .notifier,
                                )
                                .setThreadRoute(
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
                                .read(
                                  composerDockViewModelProvider(thread.id)
                                      .notifier,
                                )
                                .setThreadRoute(
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
          onChanged: (text) => ref
              .read(composerDockViewModelProvider(thread.id).notifier)
              .updateDraft(thread.id, text),
          onSubmit: () {
            // 草案 owner 先同步冻结目标、payload、route 与 operation，再等待展示准备；
            // 这里只捕当前 Thread 身份，不改动已冻结的目标（design/26 §26.8）。
            final target = thread.id;
            unawaited(
              ref
                  .read(composerDockViewModelProvider(target).notifier)
                  .submit(target),
            );
          },
          onStop: _requestStop,
          onContinue: _requestContinue,
          inputCapabilities: model?.inputCapabilities ?? const [],
          onPasteImage: (bytes) => ref
              .read(composerDockViewModelProvider(thread.id).notifier)
              .pasteImage(thread.id, bytes),
          onReportFailure: (error) => ref
              .read(composerDockViewModelProvider(thread.id).notifier)
              .reportDraftFailure(thread.id, error),
          onAddLocal: (paths) => ref
              .read(composerDockViewModelProvider(thread.id).notifier)
              .addLocalAttachments(thread.id, paths),
          onAddUrl: (url) => ref
              .read(composerDockViewModelProvider(thread.id).notifier)
              .addRemoteAttachment(thread.id, url),
          onRemoveAttachment: (id) => ref
              .read(composerDockViewModelProvider(thread.id).notifier)
              .removeAttachment(thread.id, id),
          onPasteClipboard: (pasteText, supportsImages, isCurrent) =>
              _pasteClipboardFromConnector(
                context,
                ref.read(clipboardImageReaderProvider),
                pasteText,
                supportsImages,
                isCurrent: () => context.mounted && isCurrent(),
                onPasteImage: (bytes) => ref
                    .read(composerDockViewModelProvider(thread.id).notifier)
                    .pasteImage(thread.id, bytes),
                onReportFailure: (error) => ref
                    .read(composerDockViewModelProvider(thread.id).notifier)
                    .reportDraftFailure(thread.id, error),
              ),
          onPickLocalAttachments: (capabilities, isCurrent) =>
              _pickAttachmentsFromConnector(
                capabilities,
                (paths) => ref
                    .read(composerDockViewModelProvider(thread.id).notifier)
                    .addLocalAttachments(thread.id, paths),
                (error) => ref
                    .read(composerDockViewModelProvider(thread.id).notifier)
                    .reportDraftFailure(thread.id, error),
                isCurrent: () => context.mounted && isCurrent(),
              ),
          onDropAttachments: (details, isCurrent) =>
              _dropAttachmentsFromConnector(
                details,
                (paths) => ref
                    .read(composerDockViewModelProvider(thread.id).notifier)
                    .addLocalAttachments(thread.id, paths),
                (error) => ref
                    .read(composerDockViewModelProvider(thread.id).notifier)
                    .reportDraftFailure(thread.id, error),
                isCurrent: () => context.mounted && isCurrent(),
              ),
        ),
      ],
    );
  }
}

class _InteractionDock extends ConsumerWidget {
  const _InteractionDock({
    required this.threadId,
    required this.interaction,
    required this.stop,
    required this.enabled,
  });

  final String threadId;
  final PendingInteraction interaction;
  final InteractionStopViewState stop;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final executionId = stop.executionId;
    void requestStop() {
      if (executionId == null) return;
      unawaited(
        ref
            .read(composerDockViewModelProvider(threadId).notifier)
            .stop(threadId, expectedExecutionId: executionId)
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }

    final plan = interaction.planConfirmation;
    final payload = InteractionPayloadSnapshot.from(interaction);
    final content = plan != null
        ? PlanConfirmationConnector(
            threadId: threadId,
            plan: plan,
            enabled: enabled,
          )
        : switch (interaction.kind) {
            InteractionKind.toolApproval => ToolApprovalConnector(
              threadId: threadId,
              interactionId: interaction.id,
              expectedRevision: interaction.revision,
              payload: payload,
              enabled: enabled,
            ),
            InteractionKind.userInput => UserInputConnector(
              threadId: threadId,
              interactionId: interaction.id,
              expectedRevision: interaction.revision,
              payload: payload,
              enabled: enabled,
            ),
          };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        InteractionStopView(state: stop, onStop: requestStop),
      ],
    );
  }
}

Future<void> _pasteClipboardFromConnector(
  BuildContext context,
  ClipboardImageReader clipboard,
  void Function(String) pasteText,
  bool supportsImages, {
  required bool Function() isCurrent,
  required Future<void> Function(Uint8List) onPasteImage,
  required ValueChanged<Object> onReportFailure,
}) async {
  bool allowed() => context.mounted && isCurrent();
  try {
    final image = await clipboard.readImage();
    if (!context.mounted || !isCurrent()) return;
    if (image != null) {
      if (!supportsImages) {
        onReportFailure(
          StateError(context.l10n.composerClipboardImageUnsupported),
        );
        return;
      }
      try {
        await onPasteImage(image);
      } catch (error) {
        if (allowed()) onReportFailure(error);
      }
      return;
    }
    final text = await clipboard.readText();
    if (!context.mounted || !isCurrent()) return;
    if (text != null && text.isNotEmpty) pasteText(text);
  } catch (_) {
    if (!context.mounted || !isCurrent()) return;
    onReportFailure(StateError(context.l10n.composerClipboardReadFailed));
  }
}

Future<void> _pickAttachmentsFromConnector(
  List<ModelInputCapabilityView> capabilities,
  Future<void> Function(List<String>) admit,
  ValueChanged<Object> reportFailure, {
  required bool Function() isCurrent,
}) async {
  try {
    const driverFixture = String.fromEnvironment(
      'ANYWORK_DRIVER_ATTACHMENT_PATH',
    );
    if (const bool.fromEnvironment('ANYWORK_DRIVER') &&
        driverFixture.isNotEmpty) {
      if (!isCurrent()) return;
      await admit([driverFixture]);
      return;
    }
    final modalities = capabilities.map((item) => item.modality).toSet();
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
    if (!isCurrent()) return;
    if (paths.isNotEmpty) await admit(paths);
  } catch (error) {
    if (isCurrent()) reportFailure(error);
  }
}

Future<void> _dropAttachmentsFromConnector(
  DropDetails details,
  Future<void> Function(List<String>) admit,
  ValueChanged<Object> reportFailure, {
  required bool Function() isCurrent,
}) async {
  try {
    await admitDroppedAttachments(details.items.whereType<DropFileItem>(), (
      paths,
    ) {
      if (!isCurrent()) return Future<void>.value();
      return admit(paths);
    });
  } catch (error) {
    if (isCurrent()) reportFailure(error);
  }
}
