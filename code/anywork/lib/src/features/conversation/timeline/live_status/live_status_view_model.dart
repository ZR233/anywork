import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../view_models/timeline_view_model.dart';
import 'live_status_state.dart';
import 'live_status_projection.dart';

part 'live_status_view_model.g.dart';

/// 只保留两处局部分页意图；每次从当前规范尾部和业务状态计算实际展示。
@riverpod
class LiveStatusViewModel extends _$LiveStatusViewModel {
  LiveWindowPagingState _output = const LatestLiveWindow();
  LiveWindowPagingState _work = const LatestLiveWindow();
  Object? _outputRequest;
  Object? _workRequest;

  @override
  LiveStatusView? build(String threadId) {
    ref.watch(threadSessionStoreProvider(threadId));
    final conversations = ref.read(anyworkClientProvider).conversations;
    final visible = observeClient(ref, conversations.visibleThreadId, (_) {
      if (ref.mounted) ref.invalidateSelf();
    });
    if (visible != threadId) return null;
    ref.watch(timelineViewModelProvider(threadId));
    final lease = ref.read(timelineSessionOwnerProvider).lease(threadId);
    if (lease != null) {
      void changed() {
        if (ref.mounted) state = _project();
      }

      lease.live.addListener(changed);
      lease.retirement.addListener(changed);
      ref.onDispose(() {
        lease.live.removeListener(changed);
        lease.retirement.removeListener(changed);
      });
    }
    return _project();
  }

  LiveStatusView? _project() {
    final conversations = ref.read(anyworkClientProvider).conversations;
    if (conversations.visibleThreadId.value != threadId) return null;
    final session = ref.read(threadSessionStoreProvider(threadId));
    final lease = ref.read(timelineSessionOwnerProvider).lease(threadId);
    final active = lease != null && !lease.retirement.value;
    final live = active ? lease.live.value : null;
    if (session.workspace == null && !session.hasSnapshot && live == null) {
      return null;
    }
    final cut = active && live != null
        ? LiveWindowCut(
            revision: live.layoutRevision,
            readyFrontier: live.readyFrontier,
            executionPresent: live.executionPresent,
            attemptId: lease.reader.metadata.readerId,
            isDisplayActive: true,
          )
        : const LiveWindowCut.inactive();
    _output = _output.reconcile(cut);
    _work = _work.reconcile(cut);
    final view = LiveStatusProjection.project(
      threadId: threadId,
      observation: LiveStatusInputs(
        cut: cut,
        storage: session.storage,
        interactions: session.interactions,
        businessRefs: session.businessRefs,
        activeTurnId: session.activeTurn?.turnId,
        activity: session.activity,
        latestLive: live,
        hasContentOwner: active,
      ),
      outputPaging: _output,
      timelineWorkPaging: _work,
    );
    // Diagnostics borrow the very object rendered by this component, not a second projection.
    if (active) lease.liveStatus = view;
    return view;
  }

  void loadOlderOutput(String before) =>
      unawaited(_load(LiveStatusSectionTarget.outputBar, before));
  void loadOlderTimelineWork(String before) =>
      unawaited(_load(LiveStatusSectionTarget.timelineWork, before));
  void returnToLatestOutput() {
    _outputRequest = null;
    _output = const LatestLiveWindow();
    state = _project();
  }

  void returnToLatestTimelineWork() {
    _workRequest = null;
    _work = const LatestLiveWindow();
    state = _project();
  }

  Future<void> _load(LiveStatusSectionTarget target, String before) async {
    final current = state;
    final lease = ref.read(timelineSessionOwnerProvider).lease(threadId);
    if (current == null ||
        !current.cut.hasWindow ||
        lease == null ||
        lease.retirement.value) {
      return;
    }
    final output = target == LiveStatusSectionTarget.outputBar;
    final previous = output ? _output : _work;
    if (previous.isLoading) return;
    final request = Object();
    final cut = current.cut;
    void install(LiveWindowPagingState value) {
      if (output) {
        _output = value;
      } else {
        _work = value;
      }
    }

    if (output) {
      _outputRequest = request;
    } else {
      _workRequest = request;
    }
    install(
      LoadingOlderLiveWindow(
        before: before,
        cut: cut,
        previousOlder: previous.olderWindow,
      ),
    );
    state = _project();
    bool eligible() =>
        ref.mounted &&
        !lease.retirement.value &&
        identical(
          ref.read(timelineSessionOwnerProvider).lease(threadId),
          lease,
        ) &&
        identical(output ? _outputRequest : _workRequest, request) &&
        state?.cut == cut;
    try {
      final page = await lease.loadLiveOlder(before: before);
      if (!eligible()) return;
      if (!cut.matchesWindow(page)) throw const StaleConversationScope();
      install(ViewingOlderLiveWindow(before: before, window: page, cut: cut));
    } catch (error) {
      if (!eligible()) return;
      install(
        OlderLiveWindowFailed(
          before: before,
          error: error,
          cut: cut,
          previousOlder: previous.olderWindow,
        ),
      );
    }
    if (eligible()) state = _project();
  }
}
