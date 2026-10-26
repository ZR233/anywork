import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/todo_view_state.dart';

/// The one Todo surface.
///
/// It reads the already published Todo projection only: no toggle, filter or
/// local copy of the steps. [inDrawer] changes presentation (the drawer already
/// supplies its own surface), and [onClose] is the placement's close action.
class TodoView extends StatelessWidget {
  const TodoView({
    required this.state,
    required this.onLoadMore,
    required this.onLoadText,
    this.onClose,
    this.inDrawer = false,
    super.key,
  });
  final TodoViewState state;
  final VoidCallback onLoadMore;
  final ValueChanged<int> onLoadText;
  final VoidCallback? onClose;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final explanation = state.textOf(state.header?.explanation)?.trim();
    final title = explanation != null && explanation.isNotEmpty
        ? explanation
        : context.l10n.timelineTodoListFallback;
    return Material(
      color: context.colors.surfaceContainer,
      shape: inDrawer
          ? null
          : Border(left: BorderSide(color: context.colors.outlineVariant)),
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              dense: true,
              leading: Icon(
                Icons.checklist_outlined,
                color: context.colors.primary,
              ),
              title: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              trailing: onClose == null
                  ? null
                  : IconButton(
                      key: const ValueKey('todo-close-button'),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: onClose,
                    ),
            ),
            Divider(height: 1, color: context.colors.outlineVariant),
            if (state.loading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: state.items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 1),
                itemBuilder: (context, index) => _TodoStepTile(
                  item: state.items[index],
                  textOf: state.textOf,
                  onLoadText: onLoadText,
                ),
              ),
            ),
            if (state.nextOffset != null)
              TextButton(
                onPressed: state.loading ? null : onLoadMore,
                child: Text(context.l10n.timelineItemBodyLoad),
              ),
            if (state.error != null) ...[
              Text(state.error!.message),
              TextButton(
                onPressed: onLoadMore,
                child: Text(context.l10n.sidebarRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodoStepTile extends StatelessWidget {
  const _TodoStepTile({
    required this.item,
    required this.textOf,
    required this.onLoadText,
  });

  final TodoReadItem item;
  final String? Function(ReadText?) textOf;
  final ValueChanged<int> onLoadText;

  @override
  Widget build(BuildContext context) {
    final status = item.status;
    final completed = status == TodoItemStatus.completed;
    final inProgress = status == TodoItemStatus.inProgress;
    final icon = completed
        ? Icons.check_circle_outline
        : inProgress
        ? Icons.radio_button_checked
        : Icons.radio_button_unchecked;
    final color = completed
        ? context.statusColors.success
        : inProgress
        ? context.statusColors.activeIndicator
        : context.colors.onSurfaceVariant;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      minLeadingWidth: 24,
      leading: Icon(icon, size: 18, color: color),
      title: _text(
        context,
        item.step,
        completed: completed,
        emphasized: inProgress,
      ),
      trailing: Text(
        context.todoStatusLabel(status.name),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  Widget _text(
    BuildContext context,
    ReadText value, {
    required bool completed,
    required bool emphasized,
  }) {
    final text = textOf(value);
    if (text == null) {
      return TextButton(
        onPressed: () => onLoadText((value as DeferredReadText).fieldId),
        child: Text(context.l10n.timelineItemBodyLoad),
      );
    }
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: completed
            ? context.colors.onSurfaceVariant
            : context.colors.onSurface,
        fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
        decoration: completed ? TextDecoration.lineThrough : null,
        decorationColor: context.colors.onSurfaceVariant,
      ),
    );
  }
}
