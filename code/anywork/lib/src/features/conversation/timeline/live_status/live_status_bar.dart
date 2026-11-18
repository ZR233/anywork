import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../connectors/interaction_details_connector.dart';
import '../view_models/timeline_view_model.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_activity_viewport.dart';
import 'live_status_state.dart';
import 'live_status_view_model.dart';

/// 自包含的会话底部实时状态栏组件唯一挂载入口：
/// 外层外壳只需传入 `threadId`，所有 FRB 源状态监听、状态机转换、分页与驱动状态同步
/// 均收敛于组件专属 `LiveStatusViewModel` 与 `LiveStatusProjection` 内部。
class LiveStatusBar extends ConsumerWidget {
  const LiveStatusBar({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aggregate = ref.watch(liveStatusViewModelProvider(threadId));
    if (aggregate == null) return const SizedBox.shrink();

    final barState = aggregate.barState;
    final client = ref.read(anyworkClientProvider);
    final conversations = client.conversations;
    final session = conversations.existingSession(threadId);
    if (session == null) return const SizedBox.shrink();

    final sessionState = ref.watch(threadSessionStoreProvider(threadId));
    final children = <Widget>[];

    final presenting = switch (barState) {
      LiveStatusPresenting() => barState,
      LiveStatusDockMasked(:final obscured) => obscured,
      LiveStatusHidden() => null,
    };
    final masked = barState is LiveStatusDockMasked;
    if (presenting != null) {
      if (!masked && presenting.surface.notices.isNotEmpty) {
        children.add(
          ConversationActivityBar(
            children: [
              ConversationRealtimeNotices(notices: presenting.surface.notices),
            ],
          ),
        );
      }
    }

    if (aggregate.currentAtomsError case final error?) {
      children.add(ConversationActivityBar(children: [Text(error.toString())]));
    }

    final tools = aggregate.activityTools;
    if (tools != null && !masked) {
      final notifier = ref.read(liveStatusViewModelProvider(threadId).notifier);
      children.add(
        ConversationActivityBar(
          children: [
            if (!tools.expanded)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('live-activity-tools-open'),
                  onPressed: notifier.openActivityTools,
                  icon: const Icon(Icons.build_outlined, size: 16),
                  label: Text('活动工具 ${tools.totalCount}'),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '活动工具 ${tools.loadedCount}/${tools.totalCount}',
                      key: const ValueKey('live-activity-tools-count'),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('live-activity-tools-close'),
                    onPressed: notifier.closeActivityTools,
                    child: const Text('收起'),
                  ),
                ],
              ),
              if (tools.error case final error?) Text(error.toString()),
              if (tools.loading)
                const LinearProgressIndicator()
              else
                for (final tool in tools.entries)
                  Text('${tool.name} · ${tool.summary} · ${tool.state.name}'),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    key: const ValueKey('live-activity-tools-first'),
                    onPressed: tools.hasPrevious
                        ? notifier.loadFirstActivityTools
                        : null,
                    child: const Text('第一页'),
                  ),
                  TextButton(
                    key: const ValueKey('live-activity-tools-previous'),
                    onPressed: tools.hasPrevious
                        ? notifier.loadPreviousActivityTools
                        : null,
                    child: const Text('上一页'),
                  ),
                  TextButton(
                    key: const ValueKey('live-activity-tools-next'),
                    onPressed: tools.hasNext
                        ? notifier.loadNextActivityTools
                        : null,
                    child: const Text('下一页'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    final reference = sessionState.businessRefs?.interactions;
    final detailLease = ref.read(timelineSessionOwnerProvider).lease(threadId);
    if (barState.showInteractionDetails &&
        reference != null &&
        detailLease != null) {
      children.add(
        InteractionDetailsConnector(
          key: ValueKey((
            'interaction-details',
            detailLease,
            detailLease.generation,
          )),
          openCurrent: () =>
              detailLease.openCurrentScope(generation: detailLease.generation),
          reference: reference,
          isCurrent: () =>
              identical(conversations.existingSession(threadId), session) &&
              conversations.visibleThreadId.value == threadId &&
              session.state.businessRefs?.interactions == reference &&
              !detailLease.isRetired &&
              identical(
                ref.read(timelineSessionOwnerProvider).lease(threadId),
                detailLease,
              ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return ConversationActivityViewport(
      key: ValueKey(threadId),
      children: children,
    );
  }
}
