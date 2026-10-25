import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../view_models/thread_metrics_view_model.dart';
import '../views/thread_metrics_view.dart';

class ThreadMetricsConnector extends ConsumerWidget {
  const ThreadMetricsConnector({required this.threadId, super.key});
  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = threadMetricsViewModelProvider(threadId);
    final value = ref.watch(provider);
    return KeyedSubtree(
      key: StudioDriverKeys.threadThroughput,
      child: value.when(
        loading: () => const SizedBox(width: 54, height: 26),
        // A failed observation is not a fabricated zero-speed healthy state.
        error: (error, stack) => const Text('—'),
        data: (state) => ThreadMetricsView(
          state: state,
          onRetry: () => ref.read(provider.notifier).retry().ignore(),
        ),
      ),
    );
  }
}
