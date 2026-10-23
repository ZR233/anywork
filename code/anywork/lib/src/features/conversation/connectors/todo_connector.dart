import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/todo_view_model.dart';
import '../views/todo_view.dart';

class TodoConnector extends ConsumerWidget {
  const TodoConnector({required this.threadId, this.inDrawer = false, this.onClose, super.key});
  final String threadId;
  final bool inDrawer;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = todoViewModelProvider(threadId);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    return value.when(loading: () => const SizedBox.shrink(),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) => TodoView(state: state, onToggle: vm.toggle,
        onLoadMore: () => vm.loadMore().ignore(),
        onLoadText: (field) => vm.loadText(field).ignore(),
        onClose: onClose == null ? null : () { vm.setExpanded(false); onClose!(); }));
  }
}
