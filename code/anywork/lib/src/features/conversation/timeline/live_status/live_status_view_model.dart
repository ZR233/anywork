import 'dart:async';
import 'dart:convert';

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
  bool _loadingCurrentAtoms = false;
  Object? _currentAtomsError;
  CollectionCurrentStateField? _activityToolsField;
  List<ThreadActivityToolEntry> _activityTools = const [];
  String? _activityToolsContinuation;
  bool _loadingActivityTools = false;

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
      lease.currentCollectionError.addListener(changed);
      ref.onDispose(() {
        lease.live.removeListener(changed);
        lease.retirement.removeListener(changed);
        lease.currentCollectionError.removeListener(changed);
      });
    }
    return _project();
  }

  LiveStatusView? _project() {
    final conversations = ref.read(anyworkClientProvider).conversations;
    if (conversations.visibleThreadId.value != threadId) return null;
    final session = ref.read(threadSessionStoreProvider(threadId));
    unawaited(_loadActivityTools(session.activity));
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
            attemptId: lease.current.metadata.readerId,
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
        activity: _activityWithLoadedTools(session.activity),
        latestLive: live,
        hasContentOwner: active,
      ),
      outputPaging: _output,
      timelineWorkPaging: _work,
      hasMoreCurrentAtoms: lease?.hasMoreCurrentAtoms ?? false,
      loadingCurrentAtoms: _loadingCurrentAtoms,
      currentAtomsError:
          _currentAtomsError ?? lease?.currentCollectionError.value,
      hasMoreActivityTools: _activityToolsContinuation != null,
      loadingActivityTools: _loadingActivityTools,
    );
    // Diagnostics borrow the very object rendered by this component, not a second projection.
    if (active) lease.liveStatus = view;
    return view;
  }

  void returnToLatestOutput() {
    _output = const LatestLiveWindow();
    state = _project();
  }

  void returnToLatestTimelineWork() {
    _work = const LatestLiveWindow();
    state = _project();
  }

  void loadNextCurrentAtoms() {
    final lease = ref.read(timelineSessionOwnerProvider).lease(threadId);
    if (lease == null || _loadingCurrentAtoms || !lease.hasMoreCurrentAtoms) {
      return;
    }
    _loadingCurrentAtoms = true;
    _currentAtomsError = null;
    state = _project();
    unawaited(() async {
      bool eligible() =>
          ref.mounted &&
          !lease.isRetired &&
          identical(
            ref.read(timelineSessionOwnerProvider).lease(threadId),
            lease,
          );
      try {
        await lease.loadNextCurrentAtoms();
        if (!eligible()) return;
      } catch (error) {
        if (!eligible()) return;
        _currentAtomsError = error;
      } finally {
        _loadingCurrentAtoms = false;
        if (eligible()) {
          state = _project();
        }
      }
    }());
  }

  void loadNextActivityTools() {
    unawaited(
      _loadActivityTools(
        ref.read(threadSessionStoreProvider(threadId)).activity,
        nextPage: true,
      ),
    );
  }

  ThreadActivityView? _activityWithLoadedTools(ThreadActivityView? activity) {
    final field = activity?.deferredField('tools.active');
    if (field is! CollectionCurrentStateField) return activity;
    if (_activityToolsField != field) return activity;
    return ThreadActivityView(
      threadId: activity!.threadId,
      identity: activity.identity,
      revision: activity.revision,
      turnId: activity.turnId,
      executionId: activity.executionId,
      inputId: activity.inputId,
      attemptId: activity.attemptId,
      kind: activity.kind,
      summary: activity.summary,
      summaryTruncated: activity.summaryTruncated,
      thinkingSummary: activity.thinkingSummary,
      thinkingSeconds: activity.thinkingSeconds,
      tools: ThreadActivityTools(
        count: field.count.toInt(),
        background: activity.tools.background,
        active: _activityTools,
        latestStarted: activity.tools.latestStarted,
      ),
      deferred: activity.deferred,
    );
  }

  Future<void> _loadActivityTools(
    ThreadActivityView? activity, {
    bool nextPage = false,
  }) async {
    await Future<void>.value();
    if (!ref.mounted) return;
    final field = activity?.deferredField('tools.active');
    if (field is! CollectionCurrentStateField ||
        _activityToolsField == field && !nextPage ||
        _loadingActivityTools) {
      return;
    }
    final lease = ref.read(timelineSessionOwnerProvider).lease(threadId);
    if (lease == null || lease.isRetired) return;
    if (_activityToolsField != field) {
      _activityToolsField = field;
      _activityTools = const [];
      _activityToolsContinuation = null;
    }
    _loadingActivityTools = true;
    state = _project();
    final scope = lease.openCurrentScope(generation: lease.generation);
    try {
      final page = await scope.pageStateCollection(
        field,
        continuation: nextPage ? _activityToolsContinuation : null,
        demand: const ReadDemand(maxItems: 20, maxBytes: 64 * 1024),
      );
      if (!ref.mounted ||
          lease.isRetired ||
          _activityToolsField != field ||
          page.revision != field.reference.revision) {
        return;
      }
      final loaded = <ThreadActivityToolEntry>[];
      for (final entry in page.entries) {
        final payload = switch (entry.payload) {
          InlineCurrentPayload() => entry.payload,
          DeferredCurrentPayload(:final reference, :final byteLength) =>
            InlineCurrentPayload(
              bytes: await _readActivityPayload(scope, reference, byteLength),
            ),
        };
        loaded.add(
          decodeCurrentActivityToolState(
            jsonDecode(utf8.decode(payload.bytes)),
          ),
        );
      }
      _activityTools = List.unmodifiable(
        nextPage ? [..._activityTools, ...loaded] : loaded,
      );
      _activityToolsContinuation = page.continuation;
    } finally {
      _loadingActivityTools = false;
      scope.retire();
      unawaited(scope.close());
      if (ref.mounted) state = _project();
    }
  }

  Future<List<int>> _readActivityPayload(
    CurrentQueryScope scope,
    CurrentContentRef reference,
    int byteLength,
  ) async {
    final bytes = <int>[];
    while (bytes.length < byteLength) {
      final remaining = byteLength - bytes.length;
      final window = await scope.readBody(
        reference: reference,
        range: ContentRange(
          offset: bytes.length,
          maxBytes: remaining < 64 * 1024 ? remaining : 64 * 1024,
        ),
      );
      if (window.offset != bytes.length ||
          window.generation != reference.generation ||
          window.availableThrough != byteLength ||
          window.bytes.isEmpty) {
        throw const ConversationStateFieldDiscontinuity();
      }
      bytes.addAll(window.bytes);
    }
    return bytes;
  }
}
