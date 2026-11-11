import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../platform/local_file_dialogs.dart';
import '../../composer/widgets/composer_attachments.dart';
import '../connectors/acp_configuration_connector.dart';
import '../view_models/acp_conversation_view_model.dart';
import '../widgets/acp_prompt_input.dart';

class AcpConversationComposer extends ConsumerWidget {
  const AcpConversationComposer({
    super.key,
    required this.threadId,
    this.compact = false,
  });

  final String threadId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(acpDraftViewModelProvider(threadId));
    final readiness = ref.watch(acpComposerReadinessProvider(threadId));
    final actions = ref.watch(acpConversationActionsProvider(threadId));
    final submitting = draft.isSubmissionPending;
    final hasInput =
        draft.draft.trim().isNotEmpty || draft.attachments.isNotEmpty;
    return Padding(
      padding: EdgeInsets.all(compact ? 8 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AcpConfigurationConnector(threadId: threadId),
          if (draft.attachments.isNotEmpty)
            AttachmentDraftRail(
              attachments: draft.attachments,
              enabled: !submitting,
              onRemove: (id) => unawaited(actions.removeAttachment(id)),
            ),
          AcpPromptInput(
            key: ValueKey(('acp-input', threadId)),
            text: draft.draft,
            enabled: true,
            compact: compact,
            onChanged: actions.updateDraft,
          ),
          if (readiness.reason != null) Text(readiness.reason!),
          if (draft.error != null) Text(draft.error!),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              IconButton(
                tooltip: readiness.canAttach ? '添加附件' : '服务端初始化或附件能力不可用',
                onPressed: readiness.canAttach && !submitting
                    ? () => unawaited(
                        actions.pickLocalAttachments(pickLocalAttachmentPaths),
                      )
                    : null,
                icon: const Icon(Icons.attach_file),
              ),
              if (readiness.active)
                OutlinedButton.icon(
                  onPressed: () => unawaited(actions.interrupt()),
                  icon: const Icon(Icons.stop),
                  label: const Text('中断'),
                ),
              FilledButton.icon(
                onPressed: readiness.canSend && !submitting && hasInput
                    ? () => unawaited(actions.submit())
                    : null,
                icon: const Icon(Icons.arrow_upward),
                label: Text(submitting ? '正在发送' : '发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
