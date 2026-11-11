import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../composer/widgets/composer_attachments.dart';
import '../view_models/acp_start_view_model.dart';
import '../widgets/acp_prompt_input.dart';

class AcpStartComposer extends ConsumerWidget {
  const AcpStartComposer({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(acpStartViewModelProvider(workspaceId));
    final actions = ref.watch(acpStartActionsProvider(workspaceId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.remote) const Text('ACP 会话暂不支持 SSH 项目，请选择本地项目'),
          if (state.attachments.attachments.isNotEmpty)
            AttachmentDraftRail(
              attachments: state.attachments.attachments,
              enabled: false,
              onRemove: (_) {},
            ),
          AcpPromptInput(
            key: ValueKey(('acp-start-input', workspaceId)),
            text: state.text,
            enabled: !state.submitting,
            onChanged: actions.updateDraft,
            hint: '可选：创建会话后发送的首条消息',
          ),
          const SizedBox(height: 8),
          const Text('创建并初始化后，按服务端实际能力添加附件'),
          if (state.failure != null) Text('创建失败：${state.failure}'),
          if (state.attachments.error != null) Text(state.attachments.error!),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              // Empty text is a valid session/new; do not borrow Native gates.
              onPressed:
                  !state.submitting && !state.remote && state.accountId != null
                  ? () => unawaited(_submit(context, actions))
                  : null,
              child: Text(state.submitting ? '正在创建 ACP 会话' : '创建 ACP 会话'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context, AcpStartActions actions) async {
    try {
      await actions.submit();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建 ACP 会话失败：$error')));
    }
  }
}
