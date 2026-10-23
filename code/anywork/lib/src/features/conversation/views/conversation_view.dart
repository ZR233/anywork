import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';

/// Screen geometry only. Child slots are Smart connectors; this view has no
/// provider, domain owner, selected-thread lookup or mutation admission logic.
class ConversationView extends StatelessWidget {
  const ConversationView({required this.timeline, required this.composer,
    required this.status, required this.contextUsage, required this.metrics,
    required this.onToggleTodo, this.todo, this.interactions, super.key});
  final Widget timeline;
  final Widget composer;
  final Widget status;
  final Widget contextUsage;
  final Widget metrics;
  final VoidCallback onToggleTodo;
  final Widget? todo;
  final Widget? interactions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final compact = constraints.maxHeight < 620;
    final sidebar = todo != null && constraints.maxWidth >= 1000;
    return Column(children: [
      Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: timeline),
        if (sidebar) SizedBox(width: 320, child: todo),
      ])),
      if (todo != null && !sidebar)
        ConstrainedBox(constraints: BoxConstraints(maxHeight: constraints.maxHeight * .3),
          child: SingleChildScrollView(child: todo)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
        Expanded(child: status), contextUsage, metrics,
        IconButton(onPressed: onToggleTodo, tooltip: context.l10n.timelineTodoListFallback,
          icon: const Icon(Icons.checklist_outlined)),
      ])),
      Padding(padding: compact ? const EdgeInsets.fromLTRB(12, 4, 12, 6) :
        const EdgeInsets.fromLTRB(12, 7, 12, 12),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: StudioLayout.conversationWidth),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [?interactions, composer]))),
    ]);
  });
}
