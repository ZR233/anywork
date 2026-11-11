import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../view_models/acp_conversation_view_model.dart';
import '../widgets/acp_tool_view.dart';

class AcpPermissionConnector extends ConsumerWidget {
  const AcpPermissionConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(acpPermissionsProvider(threadId));
    final actions = ref.watch(acpConversationActionsProvider(threadId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final permission in permissions)
          Card(
            key: ValueKey(permission.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('权限请求'),
                  AcpToolView(
                    id: permission.request.toolCall.toolCallId,
                    fields: permission.request.toolCall.fields,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in permission.request.options)
                        OutlinedButton(
                          key: ValueKey((permission.id, option.optionId)),
                          onPressed: () => unawaited(
                            actions.answerPermission(
                              permission.id,
                              option.optionId,
                            ),
                          ),
                          child: Text(option.name),
                        ),
                      TextButton(
                        onPressed: () => unawaited(
                          actions.answerPermission(permission.id, null),
                        ),
                        child: const Text('取消权限请求'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
