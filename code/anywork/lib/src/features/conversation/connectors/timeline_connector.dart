import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_bindings.dart';
import '../state/timeline_view_state.dart';
import '../view_models/timeline_view_model.dart';
import '../views/timeline_state_view.dart';
import '../views/timeline_view.dart';
import 'timeline_row_connector.dart';

class TimelineConnector extends ConsumerWidget {
  const TimelineConnector({required this.threadId, super.key});
  final String threadId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = timelineViewModelProvider(threadId);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final coordinator = ref.read(timelineCoordinatorProvider);
    return value.when(
      loading: () => TimelineStateView(
        state: TimelineViewState(threadId: threadId),
        onRetry: () => vm.retryConnection().ignore(),
      ),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) {
        final display = coordinator.display(threadId);
        if (display == null ||
            display.retired ||
            display.generation != state.generation) {
          return TimelineStateView(
            state: state,
            onRetry: () => vm.retryConnection().ignore(),
          );
        }
        return TimelineView(
          threadId: threadId,
          state: state,
          binding: display.canvas,
          onLoadOlder: vm.loadOlder,
          onRetryOlder: vm.retryOlder,
          onReturnLive: vm.returnLive,
          onEnterHistory: vm.enterHistory,
          onRetryConnection: vm.retryConnection,
          messageBuilder: (context, message) => TimelineRowConnector(
            key: ValueKey((display.generation, message.id)),
            message: message,
            display: display,
          ),
        );
      },
    );
  }
}
