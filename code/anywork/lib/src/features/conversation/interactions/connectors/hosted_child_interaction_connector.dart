import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/interaction_command_view_model.dart';

/// 主会话代表直接 child 提交一次交互决议的绑定。
///
/// 交互事实仍由原子会话持有：这里只携带原请求身份与版本并经主会话提交
/// （design/18 §18.2、design/19 §19.11）。提交结果只落在 SDK 命令事实与
/// canonical 投影上，不提供 UI 回查回调。子会话详情没有这个绑定，因此不
/// 出现可提交控件。
final class HostedChildInteraction {
  const HostedChildInteraction({required this.summary});

  final ChildInteractionSummary summary;
}

/// 经主会话提交一次 child 决议；host 固定为主会话，revision 原样透传。
///
/// 结果与失败由 SDK 命令状态和子交互主题投影呈现，本入口不另设第二结果通道。
void submitHostedChildDecision(
  WidgetRef ref,
  String hostThreadId,
  HostedChildInteraction hosted,
  InteractionResolutionCommand resolution,
) {
  unawaited(
    ref
        .read(interactionCommandViewModelProvider(hostThreadId).notifier)
        .resolveChild(hostThreadId, hosted.summary, resolution)
        .then<void>((_) {}, onError: (Object _) {}),
  );
}
