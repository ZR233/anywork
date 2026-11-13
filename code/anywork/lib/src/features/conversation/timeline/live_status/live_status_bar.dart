import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../../../shared/studio_driver_state.dart';
import '../connectors/conversation_current_connector.dart';
import '../connectors/interaction_details_connector.dart';
import '../view_models/timeline_view_model.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_activity_viewport.dart';
import 'live_status_state.dart';
import 'live_status_view_model.dart';

/// 自包含的会话底部实时状态栏组件唯一挂载入口：
/// 外层外壳只需传入 `threadId`，所有 FRB 源状态监听、状态机转换、分页与驱动状态同步
/// 均收敛于组件专属 `LiveStatusViewModel` 与 `LiveStatusStateMachine` 内部。
class LiveStatusBar extends ConsumerWidget {
  const LiveStatusBar({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aggregate = ref.watch(liveStatusViewModelProvider(threadId));
    if (aggregate == null) return const SizedBox.shrink();

    final barState = aggregate.barState;
    if (barState is LiveStatusHidden) return const SizedBox.shrink();

    final client = ref.read(anyworkClientProvider);
    final conversations = client.conversations;
    final session = conversations.existingSession(threadId);
    final content = session?.content;
    if (content == null) return const SizedBox.shrink();

    final sessionState = ref.watch(threadSessionStoreProvider(threadId));
    final children = <Widget>[];

    final presenting = switch (barState) {
      LiveStatusPresenting() => barState,
      LiveStatusDockMasked(:final obscured) => obscured,
      LiveStatusHidden() => null,
    };
    final masked = barState is LiveStatusDockMasked;
    if (presenting != null) {
      final timeline = ref.read(timelineSessionOwnerProvider);
      final lease = timeline.lease(threadId);
      if (lease != null && identical(lease.content, content)) {
        final notifier = ref.read(
          liveStatusViewModelProvider(threadId).notifier,
        );
        children.add(
          Offstage(
            offstage: masked,
            child: TickerMode(
              enabled: !masked,
              child: ConversationCurrentConnector(
                section: ConversationLiveSection.output,
                key: ValueKey((threadId, content, lease.generation)),
                presenting: presenting,
                onLoadOlder: notifier.loadOlderOutput,
                onReturnToLatest: notifier.returnToLatestOutput,
                threadId: threadId,
                turnId: sessionState.activeTurn?.turnId,
                activityId: sessionState.activity?.identity,
                content: content,
                liveUnit: lease.liveUnit,
                onExpandedChanged: StudioDriverState.publishActivityExpanded,
                registerDisplay: lease.registerCurrentDisplay,
                images: lease.imageResources,
                readAttachment: (id) =>
                    client.readAttachmentBytes(threadId, id),
                isDisplayActive: () =>
                    !lease.retirement.value &&
                    identical(timeline.lease(threadId), lease) &&
                    identical(lease.content, content),
              ),
            ),
          ),
        );
      } else if (!masked && presenting.surface.standaloneNotices.isNotEmpty) {
        children.add(
          ConversationActivityBar(
            children: [
              ConversationRealtimeNotices(
                notices: presenting.surface.standaloneNotices,
              ),
            ],
          ),
        );
      }
    }

    final reference = sessionState.businessRefs?.interactions;
    if (barState.showInteractionDetails && reference != null) {
      children.add(
        InteractionDetailsConnector(
          key: ValueKey((
            'interaction-details',
            content,
            content.currentAttemptId,
          )),
          content: content,
          reference: reference,
          isCurrent: () =>
              identical(conversations.existingSession(threadId), session) &&
              conversations.visibleThreadId.value == threadId &&
              session?.state.businessRefs?.interactions == reference,
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
