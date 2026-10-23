import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../state/todo_view_state.dart';

class TodoView extends StatelessWidget {
  const TodoView({required this.state, required this.onToggle, required this.onLoadMore,
    required this.onLoadText, this.onClose, super.key});
  final TodoViewState state;
  final VoidCallback onToggle;
  final VoidCallback onLoadMore;
  final ValueChanged<int> onLoadText;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(dense: true, onTap: onToggle, leading: const Icon(Icons.checklist),
        title: Text('${context.l10n.timelineTodoListFallback} · ${state.todo?.itemCount ?? 0}'),
        trailing: onClose == null
            ? Icon(state.expanded ? Icons.expand_less : Icons.expand_more)
            : IconButton(onPressed: onClose, icon: const Icon(Icons.close))),
      if (state.expanded) ...[
        if (state.loading) const LinearProgressIndicator(),
        if (state.header?.explanation case final explanation?) _text(context, explanation),
        for (final item in state.items)
          ListTile(dense: true, leading: Icon(switch (item.status) {
            TodoItemStatus.completed => Icons.check_circle_outline,
            TodoItemStatus.inProgress => Icons.pending_outlined,
            TodoItemStatus.pending => Icons.radio_button_unchecked,
          }), title: _text(context, item.step), subtitle: Text(context.todoStatusLabel(item.status.name))),
        if (state.nextOffset != null)
          TextButton(onPressed: state.loading ? null : onLoadMore, child: Text(context.l10n.timelineItemBodyLoad)),
        if (state.error != null) ...[
          Text(state.error!.message),
          TextButton(onPressed: onLoadMore, child: Text(context.l10n.sidebarRetry)),
        ],
      ],
    ]);

  Widget _text(BuildContext context, ReadText value) {
    final text = state.textOf(value);
    if (text != null) return Text(text);
    return TextButton(onPressed: () => onLoadText((value as DeferredReadText).fieldId),
      child: Text(context.l10n.timelineItemBodyLoad));
  }
}
