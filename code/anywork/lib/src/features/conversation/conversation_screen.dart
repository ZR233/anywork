import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/studio_l10n.dart';
import 'connectors/composer_connector.dart';
import 'connectors/interaction_editor_close_connector.dart';
import 'connectors/thread_context_connector.dart';
import 'connectors/thread_metrics_connector.dart';
import 'connectors/thread_status_connector.dart';
import 'connectors/timeline_connector.dart';
import 'connectors/todo_connector.dart';
import 'view_models/conversation_view_model.dart';
import 'view_models/todo_view_model.dart';
import 'views/conversation_view.dart';

class ConversationScreen extends ConsumerWidget {
  const ConversationScreen({required this.threadId, super.key});
  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = conversationViewModelProvider(threadId);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final todoProvider = todoViewModelProvider(threadId);
    final todo = ref.watch(todoProvider).value;
    final todoVm = ref.read(todoProvider.notifier);
    return value.when(loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => const Center(child: Icon(Icons.error_outline)),
      data: (state) {
        final hasInteractions = state.visibleEditors.isNotEmpty ||
          (state.pendingInteractionCount ?? 0) > 0 || state.indexLoading ||
          state.interactions?.loading == true || state.indexError != null ||
          state.interactions?.error != null || state.interactions?.current?.nextOffset != null;
        return ConversationView(
          timeline: TimelineConnector(threadId: threadId),
          status: ThreadStatusConnector(threadId: threadId),
          contextUsage: ThreadContextConnector(threadId: threadId),
          metrics: ThreadMetricsConnector(threadId: threadId),
          onToggleTodo: todoVm.toggle,
          todo: todo?.expanded == true ? TodoConnector(threadId: threadId,
            onClose: () => todoVm.setExpanded(false)) : null,
          composer: state.visibleEditors.isNotEmpty ? const SizedBox.shrink() :
            state.retiredPlanner ? Text(context.l10n.agentRoleRetired) :
            state.runtimeDriven ? Text(context.l10n.timelineAgentSubagent) :
            state.currentEditors.isNotEmpty ? TextButton(onPressed: vm.reopenCurrentEditors,
              child: Text(context.l10n.timelineUserInputAwaiting)) :
            ComposerConnector(target: vm.composerTarget),
          interactions: !hasInteractions ? null : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .4),
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              if ((state.pendingInteractionCount ?? 0) > 0 && state.visibleEditors.isEmpty)
                Text(context.l10n.timelineUserInputAwaiting),
              for (final key in state.visibleEditors) InteractionEditorCloseConnector(key: ValueKey(key), target: key,
                enabled: state.currentEditors.contains(key) && state.executionCurrent,
                onDirty: (dirty) => vm.setEditorDirty(key, dirty), onClosed: () => vm.closeEditor(key)),
              if (state.indexLoading || state.interactions?.loading == true) const LinearProgressIndicator(),
              if (state.indexError != null) Text(state.indexError!.message),
              if (state.interactions?.error != null && state.interactions?.error != state.indexError)
                Text(state.interactions!.error!.message),
              if (state.interactions?.current?.nextOffset != null || state.indexError != null ||
                  state.interactions?.error != null ||
                  ((state.pendingInteractionCount ?? 0) > 0 && state.currentEditors.isEmpty))
                TextButton(onPressed: state.indexLoading || state.interactions?.loading == true
                    ? null : () => vm.loadInteractions().ignore(),
                  child: Text(context.l10n.timelineItemBodyLoad)),
            ]))),
        );
      });
  }
}
