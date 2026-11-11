import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connectors/acp_content_block.dart';
import '../connectors/acp_permission_connector.dart';
import '../view_models/acp_conversation_view_model.dart';
import '../widgets/acp_plan_view.dart';
import '../widgets/acp_tool_view.dart';
import 'acp_conversation_status.dart';

/// Layout only. Each content item, Plan, permission panel and status borrows
/// its own selection, so one assistant chunk does not refresh the whole page.
class AcpConversationContent extends ConsumerWidget {
  const AcpConversationContent({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(acpContentCountProvider(threadId));
    return SelectionArea(
      child: ListView.builder(
        key: PageStorageKey(('acp-content', threadId)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        itemCount: count + 3,
        itemBuilder: (context, index) => switch (index) {
          0 => AcpConversationStatus(threadId: threadId),
          1 => _PlanConnector(threadId: threadId),
          2 => AcpPermissionConnector(threadId: threadId),
          _ => _ContentItem(
            key: ValueKey((threadId, index - 3)),
            threadId: threadId,
            index: index - 3,
          ),
        },
      ),
    );
  }
}

class _PlanConnector extends ConsumerWidget {
  const _PlanConnector({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(acpPlanProvider(threadId));
    return plan == null
        ? const SizedBox.shrink()
        : AcpPlanViewWidget(plan: plan);
  }
}

class _ContentItem extends ConsumerWidget {
  const _ContentItem({super.key, required this.threadId, required this.index});

  final String threadId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(acpContentItemProvider((threadId, index)));
    final id = '$threadId-acp-$index';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: switch (item) {
        final AcpConversationMessageItem message => _Message(
          id: id,
          message: message,
        ),
        AcpConversationToolItem(:final toolCallId, :final fields) =>
          AcpToolView(id: toolCallId, fields: fields),
        AcpConversationUpdateItem(
          update: AcpCompactionSummaryChunkView(:final content),
        ) =>
          AcpContentBlock(id: id, content: content),
        AcpConversationUpdateItem(:final update) => Text(
          acpUpdateSummary(update),
        ),
        null => const SizedBox.shrink(),
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.id, required this.message});

  final String id;
  final AcpConversationMessageItem message;

  @override
  Widget build(BuildContext context) {
    final blocks = acpMessageBlocks(message);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < blocks.length; index++)
          AcpContentBlock(id: '$id-$index', content: blocks[index]),
      ],
    );
    return switch (message.kind) {
      AcpConversationMessageKind.thought => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: const Icon(Icons.psychology_outlined),
        title: const Text('思考'),
        children: [body],
      ),
      AcpConversationMessageKind.user => Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: body,
        ),
      ),
      AcpConversationMessageKind.assistant => body,
    };
  }
}
