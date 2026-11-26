import 'package:anywork_client/models.dart';
import 'package:riverpod/riverpod.dart';

import '../../../../presentation/providers/thread_session_store.dart';

final threadTodoProvider = FutureProvider.autoDispose
    .family<TimelineTodoListUpdate?, String>(
      (ref, threadId) => ref.watch(
        threadSessionStoreProvider(threadId)
            .select((state) => state.meta?.runtime?.todo),
      ),
    );

final threadWorkflowRunProvider = FutureProvider.autoDispose
    .family<ThreadWorkflowRun?, String>(
      (ref, threadId) => ref.watch(
        threadSessionStoreProvider(threadId).select(
          (state) => _workflowRun(state.meta?.runtime?.workflow?.currentRun),
        ),
      ),
    );

ThreadWorkflowRun? _workflowRun(WorkflowRunView? run) =>
    run == null ? null : ThreadWorkflowRun(run);

/// Observes the original run, including fields its SDK equality omits that
/// are used by the graph query or status readout.
final class ThreadWorkflowRun {
  const ThreadWorkflowRun(this.run);

  final WorkflowRunView run;

  @override
  bool operator ==(Object other) =>
      other is ThreadWorkflowRun &&
      run == other.run &&
      run.modeId == other.run.modeId &&
      run.graphRevision == other.run.graphRevision &&
      run.graphHash == other.run.graphHash &&
      run.terminal == other.run.terminal;

  @override
  int get hashCode => Object.hash(
    run,
    run.modeId,
    run.graphRevision,
    run.graphHash,
    run.terminal,
  );
}
