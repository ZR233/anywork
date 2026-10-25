import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_keys.dart';
import '../view_models/interaction_view_model.dart';
import '../views/interaction_view.dart';

class InteractionConnector extends ConsumerStatefulWidget {
  const InteractionConnector({
    required this.target,
    required this.enabled,
    this.trailing,
    super.key,
  });
  final InteractionEditorKey target;
  final bool enabled;
  final Widget? trailing;

  @override
  ConsumerState<InteractionConnector> createState() =>
      _InteractionConnectorState();
}

class _InteractionConnectorState extends ConsumerState<InteractionConnector> {
  @override
  void initState() {
    super.initState();
    // 准入必须在本帧构建完成后发布：initState 期间改 provider 会触发
    // “Tried to modify a provider while the widget tree was building”，
    // 从而阻断真实挂载（Plan 反馈与提问都依赖该连接器）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(interactionViewModelProvider(widget.target).notifier)
          .setEnabled(widget.enabled);
    });
  }

  @override
  void didUpdateWidget(covariant InteractionConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.target != widget.target) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(interactionViewModelProvider(widget.target).notifier)
            .setEnabled(widget.enabled);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = interactionViewModelProvider(widget.target);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    // HEAD 的 dock 直接从 pending 数据驱动，不需要用户先手动"读取完整"。
    // 现役读取是分页的：一旦提交被判为 readIncomplete 且当前可见/启用，
    // 就自动驱动一次完整读取，避免用户面对禁用的提交按钮。
    return value.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) => InteractionView(
        state: state,
        onShowQuestion: vm.showQuestion,
        onLoadQuestions: vm.loadNextQuestions,
        onLoadOptions: vm.loadNextOptions,
        onLoadAnswerEntries: vm.loadNextAnswerEntries,
        onLoadAnswerValues: vm.loadNextAnswerValues,
        onLoadText: vm.loadText,
        onCompleteRead: vm.completeRead,
        onRetryRead: vm.retryRead,
        onQuestionText: vm.setQuestionText,
        onOption: vm.setOptionSelected,
        onFallback: vm.setFallbackText,
        onReason: vm.setApprovalReason,
        onPlanFeedback: vm.setPlanFeedback,
        onSubmitAnswers: vm.submitAnswers,
        onApproveTool: vm.approveTool,
        onDenyTool: vm.denyTool,
        onApprovePlan: vm.approvePlan,
        onRequestPlanRevision: vm.submitPlanFeedback,
        onRetrySubmissionRead: vm.retrySubmissionRead,
        trailing: widget.trailing,
      ),
    );
  }
}
