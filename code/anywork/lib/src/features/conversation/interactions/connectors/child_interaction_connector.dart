import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../presentation/providers/client_provider.dart';
import 'hosted_child_interaction_connector.dart';
import '../state/interaction_payload.dart';
import '../view_models/interaction_command_view_model.dart';
import '../views/child_interaction_view.dart';
import '../../interactions/connectors/tool_approval_connector.dart';
import '../../interactions/connectors/user_input_connector.dart';

/// 主会话里的子任务待决交互卡片。
///
/// 事实仍由原子 child 会话持有：这里只展示 `ChildInteractions` 主题交付的只读
/// 投影，并把用户的决定经主会话提交（design/18 §18.2、design/25 §25.7）。
/// 挂载、决议完成或换代都不再发起查询刷新；失败来自该主题的真实同步状态，
/// 重试也走既有 topic retry，不退化为 query。
class ChildInteractionConnector extends ConsumerWidget {
  const ChildInteractionConnector({
    required this.hostThreadId,
    required this.items,
    required this.sync,
    required this.sources,
    super.key,
  });

  /// 主会话（host）编号；决定与列举都用它作为宿主身份。
  final String hostThreadId;

  /// 主会话可见的直接 child 待决交互，来自 Client 的只读投影。
  final List<ChildInteractionSummary> items;

  /// 该宿主子交互主题的局部同步状态；`null` 表示当前没有可借用的镜像。
  final DomainSyncStatus? sync;

  /// child 会话编号 → 来源成员说明。
  final Map<String, String> sources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostThreadId = this.hostThreadId;
    final commands =
        ref.watch(interactionCommandViewModelProvider(hostThreadId)).value ??
        InteractionCommandViewState();
    final notice = commands.childNotice;
    final cards = [
      for (final item in items)
        if (_isDecidable(item))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildCard(
              context,
              hostThreadId,
              item,
              commands.status(item.interactionId),
            ),
          ),
    ];
    final loadFailure = switch (sync?.phase) {
      DomainSyncPhase.failed => sync?.errorMessage ?? '',
      _ => null,
    };
    if (cards.isEmpty && loadFailure == null && notice == null) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loadFailure case final failure?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    context.l10n.childInteractionLoadFailed(failure),
                    key: const ValueKey('child-interaction-load-failure'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                TextButton(
                  key: const ValueKey('child-interaction-retry'),
                  onPressed: () => ref
                      .read(anyworkClientProvider)
                      .retryResource(
                        ChildInteractionsTopic(hostThreadId: hostThreadId),
                      ),
                  child: Text(context.l10n.childInteractionRetry),
                ),
              ],
            ),
          ),
        ...cards,
        if (notice != null) ChildInteractionNoticeView(notice: notice),
      ],
    );
  }

  Widget _buildCard(
    BuildContext context,
    String hostThreadId,
    ChildInteractionSummary item,
    InteractionActionStatus? action,
  ) {
    final pending = action?.pending == true;
    final accepted = action?.accepted == true;
    final blocked = action?.blocked == true;
    final enabled = !pending && !accepted && !blocked;
    final hosted = HostedChildInteraction(summary: item);
    final payload = InteractionPayloadSnapshot.from(item.interaction);
    final child = switch (item.kind) {
      InteractionKind.toolApproval => ToolApprovalConnector(
        threadId: hostThreadId,
        interactionId: item.interactionId,
        expectedRevision: item.revision,
        payload: payload,
        enabled: enabled,
        hostedChild: hosted,
      ),
      InteractionKind.userInput => UserInputConnector(
        threadId: hostThreadId,
        interactionId: item.interactionId,
        expectedRevision: item.revision,
        payload: payload,
        enabled: enabled,
        hostedChild: hosted,
      ),
    };
    final failure = action?.error;
    return ChildInteractionCardView(
      interactionId: item.interactionId,
      revision: item.revision,
      source: sources[item.childThreadId] ?? item.childThreadId,
      pending: pending,
      accepted: accepted,
      blocked: blocked,
      failure: failure == null ? null : _reasonText(context, failure),
      child: child,
    );
  }
}

/// 只有问题与权限请求可以在主会话决议。
///
/// child 的计划确认沿用通用 `UserInput` 载荷，但它是子会话自身的诊断事实：生产侧的目录与决议
/// 入口都按计划确认问题身份把它排除，界面据同一判据不渲染可决议卡片，避免把诊断事实转成决议。
bool _isDecidable(ChildInteractionSummary item) =>
    (item.kind == InteractionKind.userInput ||
        item.kind == InteractionKind.toolApproval) &&
    !item.interaction.isPlanConfirmation;

/// 决定失败的原因：typed 失败用其文案，未知结果不伪装成成功。
String _reasonText(BuildContext context, Object error) {
  final reason = studioFailureReason(error);
  if (reason != null) return context.composerFailureReasonLabel(reason);
  final failure = error is StudioFailure ? error : null;
  return failure?.message ?? error.toString();
}
