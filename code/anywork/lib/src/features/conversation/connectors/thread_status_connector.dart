import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/thread_status_view_model.dart';
import '../views/thread_status_view.dart';
import 'read_demand_mount.dart';

class ThreadStatusConnector extends ConsumerWidget {
  const ThreadStatusConnector({required this.threadId, super.key});
  final String threadId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = threadStatusViewModelProvider(threadId);
    final value = ref.watch(provider);
    return value.when(loading: () => const SizedBox.shrink(),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) => ThreadStatusView(state: state,
        detailsBuilder: (_) => _ThreadStatusDetailsConnector(threadId: threadId)));
  }
}

/// Overlay content observes its own provider value. Capturing the bar's value
/// would leave a newly opened details route permanently on its pre-read frame.
class _ThreadStatusDetailsConnector extends ConsumerWidget {
  const _ThreadStatusDetailsConnector({required this.threadId});
  final String threadId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = threadStatusViewModelProvider(threadId);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    return ReadDemandMount(identity: ('status', threadId), begin: vm.beginDetailsDemand,
      child: value.when(loading: () => const CircularProgressIndicator(),
        error: (error, stack) => const Icon(Icons.error_outline),
        data: (state) => ThreadStatusDetailView(state: state,
          onLoadMore: (section) => _load(vm, section).ignore(),
          onReadText: (section, field) => _text(vm, section, field).ignore(),
          onWaitTargets: (index) => vm.loadWaitTargets(index).ignore(),
          onWaitTargetText: (index, field) => vm.loadWaitTargetText(index, field).ignore())));
  }

  Future<void> _load(ThreadStatusViewModel vm, StatusReadSection section) => switch (section) {
    StatusReadSection.activity => vm.loadActivity(), StatusReadSection.storage => vm.loadStorage(),
    StatusReadSection.configuration => vm.loadConfiguration(), StatusReadSection.workflow => vm.loadWorkflow(),
    StatusReadSection.turn => vm.loadTurn(),
  };
  Future<void> _text(ThreadStatusViewModel vm, StatusReadSection section, int field) => switch (section) {
    StatusReadSection.activity => vm.loadActivityText(field), StatusReadSection.storage => vm.loadStorageText(field),
    StatusReadSection.configuration => vm.loadConfigurationText(field), StatusReadSection.workflow => vm.loadWorkflowText(field),
    StatusReadSection.turn => vm.loadTurnText(field),
  };
}
