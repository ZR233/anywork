import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/client_provider.dart';

/// 主会话代表直接 child 提交一次交互决议的绑定。
///
/// 交互事实仍由原子会话持有：这里只携带原请求身份与版本，并把结果交回主会话里
/// 展示卡片的宿主（design/18 §18.2、design/19 §19.11）。子会话详情没有这个绑定，
/// 因此不出现可提交控件。
final class HostedChildInteraction {
  const HostedChildInteraction({required this.summary, required this.onResult});

  final ChildInteractionSummary summary;

  /// 提交结束的唯一回调：`null` 表示受理成功，否则是未受理或未知结果的错误。
  final void Function(Object? error) onResult;
}

/// 经主会话提交一次 child 决议；host 固定为主会话，revision 原样透传。
void submitHostedChildDecision(
  WidgetRef ref,
  String hostThreadId,
  HostedChildInteraction hosted,
  InteractionResolutionCommand resolution,
) {
  unawaited(
    ref
        .read(anyworkClientProvider)
        .threadCommands
        .resolveChildInteraction(hostThreadId, hosted.summary, resolution)
        .then(
          (_) => hosted.onResult(null),
          onError: (Object error) => hosted.onResult(error),
        ),
  );
}
