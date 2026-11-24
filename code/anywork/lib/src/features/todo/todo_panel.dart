import 'package:material_ui/material_ui.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';

class TodoPanel extends StatelessWidget {
  const TodoPanel({required this.todo, super.key});

  final TimelineTodoListUpdate todo;

  @override
  Widget build(BuildContext context) {
    final total = todo.items.length;
    final completed = todo.items
        .where((item) => item.status == 'completed')
        .length;
    final allDone = total > 0 && completed == total;
    final progress = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;

    return Material(
      key: const ValueKey('todo-side-panel'),
      color: context.colors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total > 0)
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: context.colors.surfaceContainerHigh,
              color: allDone
                  ? context.statusColors.success
                  : context.colors.primary,
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: todo.items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 1),
              itemBuilder: (context, index) =>
                  _TodoStepTile(item: todo.items[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoStepTile extends StatelessWidget {
  const _TodoStepTile({required this.item});

  final TimelineTodoItem item;

  @override
  Widget build(BuildContext context) {
    final status = item.status;
    final completed = status == 'completed';
    final inProgress = status == 'inProgress';
    final pending = status == 'pending';
    final unknown = !completed && !inProgress && !pending;
    final icon = completed
        ? Icons.check_circle_outline
        : inProgress
        ? Icons.radio_button_checked
        : unknown
        ? Icons.help_outline
        : Icons.radio_button_unchecked;
    final color = completed
        ? context.statusColors.success
        : inProgress
        ? context.statusColors.activeIndicator
        : context.colors.onSurfaceVariant;
    final statusLabel = context.todoStatusLabel(status);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      minLeadingWidth: 24,
      leading: Tooltip(
        message: statusLabel,
        child: Icon(icon, size: 18, color: color, semanticLabel: statusLabel),
      ),
      title: Text(
        item.step,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: completed
              ? context.colors.onSurfaceVariant
              : context.colors.onSurface,
          fontWeight: inProgress ? FontWeight.w600 : FontWeight.w400,
          decoration: completed ? TextDecoration.lineThrough : null,
          decorationColor: context.colors.onSurfaceVariant,
        ),
      ),
      // 常规状态由图标、颜色与删除线直观表达；仅未知状态保留原始值以免丢失语义。
      trailing: unknown
          ? Text(
              statusLabel,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: color),
            )
          : null,
    );
  }
}
