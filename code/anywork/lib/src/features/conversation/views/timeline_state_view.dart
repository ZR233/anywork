import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../state/timeline_view_state.dart';

class TimelineStateView extends StatelessWidget {
  const TimelineStateView({required this.state, required this.onRetry, super.key});
  final TimelineViewState state;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(16),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (state.connectionError != null) const Icon(Icons.error_outline)
        else const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      const SizedBox(width: 12),
      Flexible(child: Text(state.connectionError?.message ?? context.l10n.workspaceLoading)),
      if (state.connectionError != null) TextButton(onPressed: onRetry, child: Text(context.l10n.sidebarRetry)),
    ])));
}
