import 'package:anywork_client/acp_sessions.dart';
import 'package:material_ui/material_ui.dart';

class AcpPlanViewWidget extends StatelessWidget {
  const AcpPlanViewWidget({super.key, required this.plan});

  final AcpPlanView plan;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    initiallyExpanded: true,
    tilePadding: EdgeInsets.zero,
    title: const Text('计划'),
    children: [
      for (final entry in plan.entries)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(switch (entry.status) {
            AcpPlanStatusView.completed => Icons.check_circle_outline,
            AcpPlanStatusView.inProgress => Icons.pending_outlined,
            AcpPlanStatusView.pending => Icons.circle_outlined,
          }),
          title: Text(entry.content),
          subtitle: Text('${entry.priority.name} · ${entry.status.name}'),
        ),
    ],
  );
}
