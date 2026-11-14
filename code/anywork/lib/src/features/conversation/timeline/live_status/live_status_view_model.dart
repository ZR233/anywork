import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../../../shared/studio_driver_state.dart';
import '../view_models/timeline_view_model.dart';
import 'live_status_state.dart';
import 'live_status_state_machine.dart';

part 'live_status_view_model.g.dart';

/// 实时状态栏组件专属 ViewModel：
/// 在组件内部统一观察 FRB 驱动的会话状态流（`threadSessionStoreProvider`）与
/// 时间线实时展示窗口流（`TimelineDisplayLease.live`），驱动纯领域状态机并执行外部副作用，
/// 使外壳页脚与时间线连接器不再承担外围数据拼装与业务判断。
@riverpod
class LiveStatusViewModel extends _$LiveStatusViewModel {
  LiveStatusAggregate? _aggregate;

  @override
  LiveStatusAggregate? build(String threadId) {
    final session = ref.watch(threadSessionStoreProvider(threadId));
    final conversations = ref.read(anyworkClientProvider).conversations;
    final visibleThreadId = observeClient(ref, conversations.visibleThreadId, (
      _,
    ) {
      if (ref.mounted) ref.invalidateSelf();
    });
    if (visibleThreadId != threadId) {
      if (_aggregate?.hasPublishedDriver == true &&
          _aggregate?.publishedDriverActivity != null) {
        StudioDriverState.publishConversationActivity(null);
      }
      _aggregate = null;
      return null;
    }

    ref.watch(timelineViewModelProvider(threadId));
    final timeline = ref.read(timelineSessionOwnerProvider);
    final lease = timeline.lease(threadId);
    if (lease != null) {
      void onLeaseUpdated() {
        if (!ref.mounted) return;
        _reobserveCurrentSources();
      }

      lease.live.addListener(onLeaseUpdated);
      lease.retirement.addListener(onLeaseUpdated);
      ref.onDispose(() {
        lease.live.removeListener(onLeaseUpdated);
        lease.retirement.removeListener(onLeaseUpdated);
      });
    }

    final live = lease?.live.value;
    if (session.workspace == null && !session.hasSnapshot && live == null) {
      _aggregate = null;
      return null;
    }

    final observation = _buildObservation(
      threadId: threadId,
      session: session,
      conversations: conversations,
      timeline: timeline,
    );
    final transition = LiveStatusStateMachine.transition(
      _aggregate ?? LiveStatusAggregate.initial(threadId),
      LiveStatusObserved(observation),
    );
    _aggregate = transition.state;
    _runEffects(transition.effects);
    return transition.state;
  }

  /// 请求加载底部实时状态栏的更早实时窗口片段。
  void loadOlderOutput(String before) {
    _dispatch(
      LiveStatusLoadOlderRequested(
        target: LiveStatusSectionTarget.outputBar,
        before: before,
      ),
    );
  }

  /// 从更早实时窗口返回最新底部实时状态栏片段。
  void returnToLatestOutput() {
    _dispatch(
      const LiveStatusReturnToLatestRequested(
        target: LiveStatusSectionTarget.outputBar,
      ),
    );
  }

  /// 请求加载上方时间线实时工作区的更早实时窗口片段。
  void loadOlderTimelineWork(String before) {
    _dispatch(
      LiveStatusLoadOlderRequested(
        target: LiveStatusSectionTarget.timelineWork,
        before: before,
      ),
    );
  }

  /// 从更早实时窗口返回最新时间线实时工作区片段。
  void returnToLatestTimelineWork() {
    _dispatch(
      const LiveStatusReturnToLatestRequested(
        target: LiveStatusSectionTarget.timelineWork,
      ),
    );
  }

  void _reobserveCurrentSources() {
    final conversations = ref.read(anyworkClientProvider).conversations;
    if (conversations.visibleThreadId.value != threadId) {
      if (state != null) {
        StudioDriverState.publishConversationActivity(null);
        _aggregate = null;
        state = null;
      }
      return;
    }
    final session = ref.read(threadSessionStoreProvider(threadId));
    final timeline = ref.read(timelineSessionOwnerProvider);
    final lease = timeline.lease(threadId);
    if (session.workspace == null &&
        !session.hasSnapshot &&
        lease?.live.value == null) {
      if (state != null) {
        _aggregate = null;
        state = null;
      }
      return;
    }
    final observation = _buildObservation(
      threadId: threadId,
      session: session,
      conversations: conversations,
      timeline: timeline,
    );
    _dispatch(LiveStatusObserved(observation));
  }

  LiveStatusObservation _buildObservation({
    required String threadId,
    required ThreadSessionState session,
    required ConversationRepository conversations,
    required Object timeline,
  }) {
    final owner = ref.read(timelineSessionOwnerProvider);
    final lease = owner.lease(threadId);
    final activeLease = lease != null && !lease.retirement.value;
    final live = activeLease ? lease.live.value : null;
    final cut = activeLease && live != null
        ? LiveWindowCut(
            revision: live.revision,
            readyFrontier: live.readyFrontier,
            executionPresent: live.executionPresent,
            attemptId: lease.content.currentAttemptId,
            isDisplayActive: true,
          )
        : const LiveWindowCut.inactive();
    return LiveStatusObservation(
      cut: cut,
      storage: session.storage,
      interactions: session.interactions,
      businessRefs: session.businessRefs,
      activeTurnId: session.activeTurn?.turnId,
      activity: session.activity,
      latestLive: live,
      hasContentOwner: conversations.existingSession(threadId)?.content != null,
    );
  }

  void _dispatch(LiveStatusEvent event) {
    if (!ref.mounted) return;
    final base = _aggregate ?? LiveStatusAggregate.initial(threadId);
    final transition = LiveStatusStateMachine.transition(base, event);
    _aggregate = transition.state;
    state = transition.state;
    _runEffects(transition.effects);
  }

  void _runEffects(List<LiveStatusEffect> effects) {
    for (final effect in effects) {
      switch (effect) {
        case SyncStudioDriverActivityEffect(:final view):
          StudioDriverState.publishConversationActivity(view);
        case ReadOlderLiveWindowEffect(
          :final target,
          :final before,
          :final cut,
        ):
          unawaited(
            _fetchOlderWindow(target: target, before: before, cut: cut),
          );
      }
    }
  }

  Future<void> _fetchOlderWindow({
    required LiveStatusSectionTarget target,
    required String before,
    required LiveWindowCut cut,
  }) async {
    final lease = ref.read(timelineSessionOwnerProvider).lease(threadId);
    if (lease == null || lease.retirement.value) return;
    try {
      final window = await lease.loadLiveOlder(before: before);
      if (!ref.mounted) return;
      _dispatch(
        LiveStatusOlderLoaded(
          target: target,
          before: before,
          window: window,
          cut: cut,
        ),
      );
    } catch (error) {
      if (!ref.mounted) return;
      _dispatch(
        LiveStatusOlderFailed(
          target: target,
          before: before,
          error: error,
          cut: cut,
        ),
      );
    }
  }
}
