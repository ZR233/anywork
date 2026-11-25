import 'package:anywork_client/models.dart';
import 'package:riverpod/riverpod.dart';

import '../../../presentation/providers/client_provider.dart';
import '../../conversation/acp/view_models/acp_session_view_model.dart';
import '../../conversation/timeline/view_models/thread_runtime_fields.dart';

typedef WorkflowGraphReadout = ({
  WorkflowRunView? run,
  AsyncValue<WorkflowRuntimeGraphSnapshotView?> graph,
  void Function()? retry,
});

// Only threadId goes to the RPC. The other keys isolate local observations;
// the response does not carry a graph revision or hash to verify.
typedef _WorkflowGraphRequest = ({
  String threadId,
  String? modeId,
  int? revision,
  String? hash,
});

final _workflowGraphQueryProvider = FutureProvider.autoDispose
    .family<WorkflowRuntimeGraphSnapshotView?, _WorkflowGraphRequest>(
      (ref, request) => ref
          .watch(anyworkClientProvider)
          .getThreadWorkflowGraph(request.threadId),
      retry: (_, _) => null,
    );

final threadWorkflowGraphProvider = Provider.autoDispose
    .family<WorkflowGraphReadout, String>((ref, threadId) {
      final runProvider = threadWorkflowRunProvider(threadId);
      final run = ref.watch(runProvider);
      if (run.isLoading) {
        return (run: null, graph: const AsyncLoading(), retry: null);
      }
      if (run.asError case final error?) {
        return (
          run: null,
          graph: AsyncError(error.error, error.stackTrace),
          retry: () {
            if (ref.mounted) ref.invalidate(runProvider);
          },
        );
      }
      return _observeRpcGraph(ref, threadId, run.asData?.value?.run);
    });

final acpWorkflowGraphProvider = Provider.autoDispose
    .family<WorkflowGraphReadout, String>((ref, threadId) {
      final workflow = ref.watch(
        acpConversationStateProvider(threadId).select(
          (value) => value.isLoading ? null : value.asData?.value.workflowState,
        ),
      );
      if (workflow == null) {
        return (run: null, graph: const AsyncData(null), retry: null);
      }
      if (workflow.graph case final graph?) {
        return (run: workflow.run, graph: AsyncData(graph), retry: null);
      }
      return _observeRpcGraph(
        ref,
        threadId,
        workflow.run,
        modeId: workflow.modeId,
      );
    });

WorkflowGraphReadout _observeRpcGraph(
  Ref ref,
  String threadId,
  WorkflowRunView? run, {
  String? modeId,
}) {
  final query = _workflowGraphQueryProvider((
    threadId: threadId,
    modeId: run?.modeId ?? modeId,
    revision: run?.graphRevision,
    hash: run?.graphHash,
  ));
  return (
    run: run,
    graph: ref.watch(query),
    retry: () {
      if (ref.mounted) ref.invalidate(query);
    },
  );
}
