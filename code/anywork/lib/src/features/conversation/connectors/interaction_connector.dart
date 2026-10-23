import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_keys.dart';
import '../view_models/interaction_view_model.dart';
import '../views/interaction_view.dart';

class InteractionConnector extends ConsumerStatefulWidget {
  const InteractionConnector({required this.target, required this.enabled, this.trailing, super.key});
  final InteractionEditorKey target;
  final bool enabled;
  final Widget? trailing;

  @override
  ConsumerState<InteractionConnector> createState() => _InteractionConnectorState();
}

class _InteractionConnectorState extends ConsumerState<InteractionConnector> {
  @override
  void initState() {
    super.initState();
    ref.read(interactionViewModelProvider(widget.target).notifier).setEnabled(widget.enabled);
  }

  @override
  void didUpdateWidget(covariant InteractionConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled || oldWidget.target != widget.target) {
      ref.read(interactionViewModelProvider(widget.target).notifier).setEnabled(widget.enabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = interactionViewModelProvider(widget.target);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    return value.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) => InteractionView(state: state,
        onShowQuestion: vm.showQuestion, onLoadQuestions: vm.loadNextQuestions,
        onLoadOptions: vm.loadNextOptions, onLoadAnswerEntries: vm.loadNextAnswerEntries,
        onLoadAnswerValues: vm.loadNextAnswerValues, onLoadText: vm.loadText,
        onCompleteRead: vm.completeRead, onRetryRead: vm.retryRead,
        onQuestionText: vm.setQuestionText, onOption: vm.setOptionSelected,
        onFallback: vm.setFallbackText, onReason: vm.setApprovalReason,
        onPlanFeedback: vm.setPlanFeedback, trailing: widget.trailing),
    );
  }
}
