import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/overlays/studio_hover_detail.dart';
import '../view_models/thread_context_view_model.dart';
import '../views/thread_context_view.dart';
import 'read_demand_mount.dart';

class ThreadContextConnector extends ConsumerWidget {
  const ThreadContextConnector({required this.threadId, super.key});
  final String threadId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = threadContextViewModelProvider(threadId);
    final value = ref.watch(provider);
    return value.when(
      loading: () => const SizedBox(width: 36, height: 10),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) => StudioHoverDetail(
        key: StudioDriverKeys.contextUsage(),
        maxWidth: 360,
        semanticsLabel: context.l10n.statusContextLabel,
        semanticsValue: state.fraction == null
            ? '—'
            : '${(state.fraction! * 100).toStringAsFixed(1)}%',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          child: ContextUsageGraphic(fraction: state.fraction),
        ),
        detailBuilder: (_) =>
            _ThreadContextDetailsConnector(threadId: threadId),
      ),
    );
  }
}

class _ThreadContextDetailsConnector extends ConsumerWidget {
  const _ThreadContextDetailsConnector({required this.threadId});
  final String threadId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = threadContextViewModelProvider(threadId);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    return ReadDemandMount(
      identity: ('context', threadId),
      begin: vm.beginDetailsDemand,
      child: value.when(
        loading: () => const CircularProgressIndicator(),
        error: (error, stack) => const Icon(Icons.error_outline),
        data: (state) => ThreadContextDetailView(
          key: StudioDriverKeys.contextUsageDetail(),
          state: state,
          onRetry: () => vm.loadDetails().ignore(),
          onLoadCosts: () => vm.loadCosts().ignore(),
          onLoadSavings: () => vm.loadCacheSavings().ignore(),
          onLoadText: (field) => vm.loadText(field).ignore(),
        ),
      ),
    );
  }
}
