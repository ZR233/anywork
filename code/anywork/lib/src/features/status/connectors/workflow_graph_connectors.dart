import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/workflow_graph_query.dart';
import '../views/workflow_graph_panel.dart';

class ThreadWorkflowGraphPanelConnector extends ConsumerWidget {
  const ThreadWorkflowGraphPanelConnector({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _buildPanel(ref.watch(threadWorkflowGraphProvider(threadId)));
}

class AcpWorkflowGraphPanelConnector extends ConsumerWidget {
  const AcpWorkflowGraphPanelConnector({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _buildPanel(ref.watch(acpWorkflowGraphProvider(threadId)));
}

WorkflowGraphPanel _buildPanel(WorkflowGraphReadout state) {
  final (:run, :graph, :retry) = state;
  return WorkflowGraphPanel(
    graph: graph.isLoading ? null : graph.asData?.value,
    run: run,
    loading: graph.isLoading,
    error: graph.isLoading ? null : graph.asError?.error,
    onRetry: retry,
  );
}
