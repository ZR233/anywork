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
import '../../shared/studio_chrome.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/studio_menu_label.dart';
import '../status/session_selectors.dart';
import 'composer_view.dart';
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
    final view = ref.watch(composerDockViewProvider(threadId));
    final thread = view.thread;
    if (thread == null) return const SizedBox.shrink();
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
                thread.isRetiredAgent
                    ? Text(
                        context.l10n.agentRoleRetired,
                        key: const ValueKey('retired-agent-notice'),
                      )
                    : interaction == null
                    ? thread.isAgent
                          ? _RuntimeDrivenAgentDock(
                              threadId: thread.id,
                              isBusy: view.isBusy,
                            )
                          : _PromptComposer(
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
    final requiresFunctionCalling = projection.requiresFunctionCalling(mode);
    final selectorsEnabled =
        projection.canSubmit &&
        projection.settingsLoaded &&
        requiresFunctionCalling != null;
    final route = projection.displayRoute(mode);
    final pending = projection.routePending(mode);
    final model = route == null
        ? null
        : modelForRoute(projection.providers, route.providerId, route.model);
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
              enabled: projection.canSubmit,
              isBusy: false,
              clipboard: ref.read(clipboardImageReaderProvider),
              selectorBar: Wrap(
                key: StudioDriverKeys.startPageSelectors,
                spacing: 6,
                runSpacing: 4,
                children: [
                  SessionModeSelector(
                    mode: mode,
                    enabled: selectorsEnabled,
                    onSelected: (next) => _setMode(next),
                  ),
                  SessionWorkspaceModeSelector(
                    mode: projection.workspaceMode,
                    enabled: selectorsEnabled,
                    onSelected: _setWorkspaceMode,
                  ),
                  ..._modelRouteSelectorChildren(
                    providers: projection.providers,
                    providerId: route?.providerId,
                    model: route?.model,
                    effort: route?.effort,
                    // Unknown capabilities keep selectors disabled until the
                    // Client catalog arrives; no model is admitted by fallback.
                    requiresFunctionCalling: requiresFunctionCalling ?? false,
                    pending: pending,
                    enabled: selectorsEnabled,
                    unavailableReason: unavailableReason,
                    onModelSelected: (providerId, model) {
                      ref
                          .read(anyworkClientProvider)
                          .startDraft
                          .setModelIntent(mode, providerId, model);
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

  void _setWorkspaceMode(ThreadWorkspaceMode mode) {
    final projectId = widget.projectId;
    if (projectId == null) return;
    ref
        .read(anyworkClientProvider)
        .startDraft
        .setWorkspaceMode(projectId, mode);
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

class _RuntimeDrivenAgentDock extends StatelessWidget {
  const _RuntimeDrivenAgentDock({required this.threadId, required this.isBusy});

  final String threadId;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      backgroundColor: context.colors.surfaceContainer,
      borderColor: context.colors.outlineVariant,
      radius: StudioRadii.lg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Icon(
            Icons.lock_clock_outlined,
            size: 18,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              context.l10n.composerAgentRuntimeDriven,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
          if (isBusy) _StopButton(threadId: threadId),
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

  @override
  void didUpdateWidget(covariant _PromptComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thread.id != widget.thread.id ||
        oldWidget.thread.status != widget.thread.status ||
        oldWidget.view.hasActiveWorkflow != widget.view.hasActiveWorkflow ||
        oldWidget.view.displayRoute != widget.view.displayRoute) {
      _modelNotice = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final view = widget.view;
    final route = view.displayRoute;
    final model = route == null
        ? null
        : modelForRoute(view.providers, route.providerId, route.model);
    final blockedReason = switch (thread.status) {
      ThreadStatusView.idle =>
        view.hasActiveWorkflow
            ? context.l10n.statusModelSwitchWhileWorkflowActive
            : null,
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
          isBusy: view.isBusy,
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
                      enabled:
                          !view.hasActiveWorkflow &&
                          thread.status == ThreadStatusView.idle &&
                          view.activeInteraction == null,
                      onSelected: (mode) => unawaited(
                        ref
                            .read(anyworkClientProvider)
                            .threadCommands
                            .setThreadMode(mode),
                      ),
                    ),
                    ..._modelRouteSelectorChildren(
                      providers: view.providers,
                      providerId: route?.providerId,
                      model: route?.model,
                      effort: route?.effort,
                      requiresFunctionCalling:
                          view.requiresFunctionCalling ?? false,
                      enabled: view.requiresFunctionCalling != null,
                      pending: view.routePending,
                      available: route?.available ?? false,
                      routeUnavailableReason: route?.unavailableReason,
                      unavailableReason: unavailableReason,
                      blockedReason: blockedReason,
                      onExplain: (message) =>
                          setState(() => _modelNotice = message),
                      onModelSelected: (providerId, model) {
                        unawaited(
                          ref
                              .read(anyworkClientProvider)
                              .threadCommands
                              .setThreadModelRoute(
                                threadId: thread.id,
                                providerId: providerId,
                                model: model,
                                effort:
                                    ModelRouteQueries.effortAfterModelSelection(
                                      ModelRouteQueries.model(
                                        view.providers,
                                        providerId,
                                        model,
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
                                providerId: route.providerId,
                                model: route.model,
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
          onStop: () => unawaited(
            ref.read(anyworkClientProvider).threadCommands.stop(thread.id),
          ),
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

class _PromptComposerPanel extends StatefulWidget {
  const _PromptComposerPanel({
    required this.composer,
    this.targetDiagnostic,
    this.additionalDiagnostics = const [],
    required this.enabled,
    required this.isBusy,
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
    this.selectorBar,
    this.textController,
    this.compact = false,
    this.submissionLocked = false,
  });

  final ComposerThreadState composer;
  final ComposerTargetDiagnostic? targetDiagnostic;
  final List<ComposerTargetDiagnostic> additionalDiagnostics;
  final bool enabled;
  final bool isBusy;
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
  final Widget? selectorBar;

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

  TextEditingController get _controller =>
      widget.textController ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    if (widget.textController == null) {
      _ownedController = TextEditingController(text: widget.composer.draft);
    }
    _controller.addListener(_onDraftChanged);
  }

  void _onDraftChanged() {
    if (!mounted || _syncingDraft) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _PromptComposerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  @override
  void dispose() {
    widget.textController?.removeListener(_onDraftChanged);
    _ownedController?.removeListener(_onDraftChanged);
    _ownedController?.dispose();
    super.dispose();
  }

  /// 主按钮与回车提交共享同一前置条件：启用、有内容且不在提交中。
  bool get _hasContent =>
      _controller.text.trim().isNotEmpty ||
      widget.composer.attachments.isNotEmpty;

  bool get _submissionPending =>
      widget.submissionLocked || widget.composer.isSubmissionPending;

  bool get _canSubmit => widget.enabled && _hasContent && !_submissionPending;

  /// 提交的唯一入口：主按钮与 Enter 提交共用同一准入判定。
  ///
  /// 组词中的回车先由输入法确认候选，根本不会走到这里；因此这里不再需要
  /// 额外的组合状态检查，也不会因组合文本而误提交。
  void _submit() {
    if (!_canSubmit) return;
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
    final showStop = widget.isBusy && !_hasContent && !_submissionPending;
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
                    if (widget.isBusy &&
                        !_submissionPending &&
                        widget.onStop != null) {
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
          if (composer.error case final error?)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
                child: Text(
                  error,
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
          Row(
            children: [
              _AttachmentMenu(
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
                  children: [?widget.selectorBar],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: showStop
                    ? StudioDriverKeys.composerStop
                    : !_canSubmit
                    ? const ValueKey('composer-submit-disabled')
                    : StudioDriverKeys.composerSubmit,
                tooltip: showStop
                    ? context.l10n.composerStop
                    : widget.isBusy
                    ? context.l10n.composerSendAndContinue
                    : context.l10n.composerSend,
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(40),
                  shape: const CircleBorder(),
                  backgroundColor: showStop
                      ? colors.surfaceContainerHighest
                      : colors.primary,
                  foregroundColor: showStop
                      ? colors.onSurface
                      : colors.onPrimary,
                  disabledBackgroundColor: colors.surfaceContainerHighest,
                  disabledForegroundColor: colors.onSurface.withValues(
                    alpha: 0.32,
                  ),
                ),
                icon: _submissionPending
                    ? const SizedBox.square(
                        key: StudioDriverKeys.composerPending,
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        showStop
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                      ),
                onPressed: showStop
                    ? widget.onStop
                    : _canSubmit
                    ? _submit
                    : null,
              ),
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
  required List<ProviderSettingsView> providers,
  required bool requiresFunctionCalling,
  required bool pending,
  bool enabled = true,
  required String unavailableReason,
  String? providerId,
  String? model,
  String? effort,
  bool available = true,
  String? routeUnavailableReason,
  String? blockedReason,
  ValueChanged<String>? onExplain,
  ModelSelectionChanged? onModelSelected,
  EffortSelectionChanged? onEffortSelected,
}) {
  final hasRoute =
      providerId != null &&
      model != null &&
      providerId.isNotEmpty &&
      model.isNotEmpty;
  if (!hasRoute) {
    return [
      _RouteUnavailableNotice(reason: unavailableReason),
      ModelRoleSelector(
        providers: providers,
        providerId: providerId ?? '',
        model: model ?? '',
        effort: effort,
        requiresFunctionCalling: requiresFunctionCalling,
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
      providers: providers,
      providerId: providerId,
      model: model,
      effort: effort,
      requiresFunctionCalling: requiresFunctionCalling,
      enabled: enabled,
      pending: pending,
      available: available,
      unavailableReason: routeUnavailableReason,
      blockedReason: blockedReason,
      onExplain: onExplain,
      onModelSelected: onModelSelected,
    ),
    ReasoningEffortSelector(
      providers: providers,
      providerId: providerId,
      model: model,
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
