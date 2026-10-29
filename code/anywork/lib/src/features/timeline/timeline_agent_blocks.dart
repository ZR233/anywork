part of 'timeline_activity_group_views.dart';

class TimelineAgentPart extends StatelessWidget {
  const TimelineAgentPart({required this.agent, super.key});
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
    return TimelineMetaRow(
      icon: Icons.account_tree_outlined,
      title:
          '${context.l10n.timelineAgentSubagent} · ${agent.identity.path} · ${context.toolStatusLabel(status)}',
      subtitle: detail,
    );
  }
}
