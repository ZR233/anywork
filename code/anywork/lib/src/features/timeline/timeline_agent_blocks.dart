part of 'timeline_view.dart';

class _AgentPart extends StatelessWidget {
  const _AgentPart({required this.agent});
  final ThreadAgentItemStateView agent;
  @override
  Widget build(BuildContext context) {
    final (status, detail) = switch (agent.lifecycle) {
      QueuedThreadAgentView() => ('queued', agent.identity.task),
      RunningThreadAgentView() => ('running', agent.identity.task),
      SucceededThreadAgentView(:final summary) => ('succeeded', summary),
      DeniedThreadAgentView(:final reason) => ('denied', reason),
      CancelledThreadAgentView(:final reason) => ('cancelled', reason),
      FailedThreadAgentView(:final error) => ('failed', error),
    };
    return _TimelineMetaRow(
      icon: Icons.account_tree_outlined,
      title:
          '${context.l10n.timelineAgentSubagent} · ${agent.identity.path} · ${context.toolStatusLabel(status)}',
      subtitle: detail,
    );
  }
}
