import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../state/plan_view_state.dart';

/// No feedback/approve/revise callbacks: those belong to Interaction exclusively.
class PlanView extends StatelessWidget {
  const PlanView({required this.state, required this.onToggle, required this.onRetry,
    required this.documentBuilder, super.key});
  final PlanViewState state;
  final VoidCallback onToggle;
  final VoidCallback onRetry;
  final Widget Function(BuildContext, String) documentBuilder;

  @override
  Widget build(BuildContext context) {
    if (state.plan == null) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(dense: true, onTap: onToggle, leading: const Icon(Icons.description_outlined),
          title: Text(context.l10n.statusPlanEntry),
          trailing: Icon(state.expanded ? Icons.expand_less : Icons.expand_more)),
        if (state.expanded) ...[
          if (state.loading) const LinearProgressIndicator(),
          if (state.error != null)
            Row(children: [Expanded(child: Text(state.error!.message)),
              TextButton(onPressed: onRetry, child: Text(context.l10n.sidebarRetry))]),
          if (state.document case final document?)
            Padding(padding: const EdgeInsets.all(12), child: documentBuilder(context, document.markdown)),
        ],
      ]);
  }
}
