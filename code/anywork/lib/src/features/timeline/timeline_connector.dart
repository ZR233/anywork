import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import 'timeline_session_view.dart';
import 'timeline_view.dart';

/// 把只读展示元数据、当前展示 lease 与界面意图接到唯一 Timeline 列表。
///
/// 它不创建订阅、业务 demand 或第二份正文缓存：元数据来自
/// [timelineDisplayStateProvider]，controller 与滚动控制器只从
/// [TimelineSessionOwner.lease] 借出（design/26 §26.8）。
class TimelineSessionConnector extends ConsumerWidget {
  const TimelineSessionConnector({
    super.key,
    required this.threadId,
    this.planConfirmation,
    this.planExpanded = true,
    this.onPlanToggle,
  });

  final String threadId;
  final PlanConfirmationView? planConfirmation;
  final bool planExpanded;
  final VoidCallback? onPlanToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timelineDisplayStateProvider);
    final owner = ref.read(timelineSessionOwnerProvider);
    final matched = state != null && state.threadId == threadId ? state : null;
    final lease = owner.lease(threadId);
    if (matched == null || lease == null) {
      return TimelineStateView(
        phase: _phaseOf(matched),
        error: matched?.connectionError,
        onRetry: () {
          ref.read(anyworkClientProvider).retrySession(threadId);
          ref.invalidate(timelineDisplayStateProvider);
        },
      );
    }
    return TimelineView(
      threadId: threadId,
      view: matched,
      lease: lease,
      onLoadOlder: () => owner.loadOlder(threadId),
      onRetryOlder: () => owner.retryOlder(threadId),
      onReturnLive: () => owner.returnToLive(threadId),
      onEnterHistory: () =>
          unawaited(owner.dispatch(threadId, const TimelineEnterHistory())),
      // 连接重试：只重试内容连接，保持当前 History 冻结，不改代次。
      onRetryConnection: () async {
        ref.read(anyworkClientProvider).retrySession(threadId);
      },
      planConfirmation: planConfirmation,
      planExpanded: planExpanded,
      onPlanToggle: onPlanToggle,
    );
  }

  TimelineChatPhase _phaseOf(TimelineSessionViewState? state) {
    final connection = state?.connection ?? TimelineConnectionPhase.idle;
    return switch (connection) {
      TimelineConnectionPhase.ready => TimelineChatPhase.ready,
      TimelineConnectionPhase.opening ||
      TimelineConnectionPhase.idle => TimelineChatPhase.opening,
      TimelineConnectionPhase.reconnecting => TimelineChatPhase.reconnecting,
      TimelineConnectionPhase.failed ||
      TimelineConnectionPhase.closed => TimelineChatPhase.failed,
    };
  }
}

enum TimelineChatPhase { opening, ready, reconnecting, failed }

/// 展示建立之前的加载与失败：没有展示就没有内容可保留，只给 loading 或可见错误与重试。
class TimelineStateView extends StatelessWidget {
  const TimelineStateView({
    super.key,
    required this.phase,
    required this.error,
    required this.onRetry,
  });

  final TimelineChatPhase phase;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = phase == TimelineChatPhase.failed;
    final error = this.error;
    final message = error?.toString() ?? context.l10n.workspaceLoading;
    final notice = Padding(
      key: ValueKey(('timeline-chat-state', phase)),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (failed)
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            )
          else
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          if (error != null)
            TextButton.icon(
              key: const ValueKey('timeline-chat-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.sidebarRetry),
            ),
        ],
      ),
    );
    return Center(child: notice);
  }
}
