import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/workspace.dart' show ThreadStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/studio_l10n.dart';
import '../presentation/model_route_presentation.dart';
import '../view_models/conversation_view_model.dart';
import '../view_models/thread_status_view_model.dart';
import '../views/agent_read_only_panel.dart';
import 'read_demand_mount.dart';

/// Borrows the already mounted status VM's bounded configuration reader. It
/// creates no Session, draft, route authority or writable child capability.
class AgentReadOnlyConnector extends ConsumerWidget {
  const AgentReadOnlyConnector({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref
        .watch(conversationViewModelProvider(threadId))
        .value;
    final provider = threadStatusViewModelProvider(threadId);
    final status = ref.watch(provider).value;
    final vm = ref.read(provider.notifier);
    final thread = currentRouteThread(conversation?.metadata, threadId);
    final executionSource = conversation?.execution;
    final executionCurrent =
        conversation?.executionCurrent == true &&
        executionSource?.stamp?.facet == ThreadFacet.execution;
    final baseline = executionCurrent ? executionSource?.value : null;
    final execution = baseline?.execution;
    final continuation = baseline?.continuation;
    final configuration = conversation?.configuration;
    final route =
        status != null &&
            configuration?.sync.phase == FacetSyncPhase.ready &&
            status.configuration?.stamp == configuration?.stamp &&
            configuration?.stamp?.runtimeEpoch ==
                executionSource?.stamp?.runtimeEpoch &&
            configuration?.stamp?.incarnation ==
                executionSource?.stamp?.incarnation
        ? currentModelRoute(status)
        : null;
    final path = thread?.workspacePath;
    return ReadDemandMount(
      identity: ('agent-readonly-route', threadId, vm),
      begin: vm.beginModelRouteDemand,
      child: AgentReadOnlyPanel(
        waitingForScheduling:
            baseline != null &&
            execution == null &&
            continuation != null &&
            !continuation.claimed,
        pendingInteraction: (baseline?.interactions.pending ?? 0) > 0,
        statusLabel: thread == null
            ? '—'
            : context.threadStatusLabel(thread.status),
        executionLabel: execution == null
            ? null
            : context.threadStatusLabel(
                execution.phase == AgentExecutionPhase.stopping
                    ? ThreadStatus.cancelling
                    : ThreadStatus.running,
              ),
        modelLabel: route?.modelId,
        workspacePath: path != null && path.trim().isNotEmpty ? path : null,
        retiredPlanner: conversation?.retiredPlanner == true,
      ),
    );
  }
}
