import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../view_models/acp_conversation_view_model.dart';

class AcpConversationStatus extends ConsumerWidget {
  const AcpConversationStatus({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(acpStatusViewModelProvider(threadId));
    final history = switch (state.history) {
      AcpConversationHistory.newSession => null,
      AcpConversationHistory.loadReplay => '以下内容由 ACP 服务端回放；本地不保存会话历史',
      AcpConversationHistory.resumedWithoutHistory =>
        '已恢复会话，但服务端未回放历史；不能据此认为历史完整',
      AcpConversationHistory.residentWithoutObservation =>
        '此会话驻留但没有可用观察，历史内容不可得',
      AcpConversationHistory.incomplete => '会话观察不完整，当前内容可能缺失',
      null => null,
    };
    final completed = state.completed;
    final messages = [
      if (state.loading) '正在打开 ACP 会话',
      if (state.disconnected) 'ACP 连接已断开',
      if (state.ended) 'ACP 观察已结束，停止接收会话更新',
      if (state.gap != null) 'ACP 观察出现缺口：${state.gap!.name}，内容可能不完整',
      ?history,
      if (state.error != null) 'ACP 错误：${state.error}',
      if (state.run != null) '运行 ${state.run!.sequence} 进行中',
      if (state.run == null && completed != null)
        '运行已结束 · ${completed.summary}',
    ];
    if (messages.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
