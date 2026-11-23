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

enum _ActivityToolsDirection { first, next, previous }

/// Current state and business facts are projected directly; the only local
/// paging state is the explicitly requested activity-tools page.
@riverpod
class LiveStatusViewModel extends _$LiveStatusViewModel {
  CollectionCurrentStateField? _activityToolsField;
  List<ThreadActivityToolEntry> _activityToolsPage = const [];
  String? _activityToolsCursor;
  String? _activityToolsContinuation;
  final List<String?> _activityToolsPrevious = [];
  bool _activityToolsExpanded = false;
  bool _loadingActivityTools = false;
  bool _activityToolsLoadScheduled = false;
  Object? _activityToolsError;
  CurrentReadScope? _activityToolsScope;
  int _activityToolsGeneration = 0;

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
      lease.liveOpenWork.addListener(changed);
      lease.retirement.addListener(changed);
      lease.currentCollectionError.addListener(changed);
      lease.renderedCurrentAtoms.addListener(changed);
      ref.onDispose(() {
        lease.live.removeListener(changed);
        lease.liveOpenWork.removeListener(changed);
        lease.retirement.removeListener(changed);
        lease.currentCollectionError.removeListener(changed);
        lease.renderedCurrentAtoms.removeListener(changed);
        final scope = _activityToolsScope;
        _activityToolsScope = null;
        // The original load task and display lease retain asynchronous cleanup.
        // Provider disposal only revokes this view's demand; it cannot detach a
        // second close attempt or swallow that owner's cleanup failure.
        scope?.retire();
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
    final field = session.activity?.deferredField('tools.active');
    final activityField = field is CollectionCurrentStateField ? field : null;
    final resetActivityTools = _activityToolsField != activityField;
    if (resetActivityTools) {
      _activityToolsGeneration++;
      _activityToolsField = activityField;
      _activityToolsPage = const [];
      _activityToolsCursor = null;
      _activityToolsContinuation = null;
      _activityToolsPrevious.clear();
      _activityToolsError = null;
    }
    final view = LiveStatusProjection.project(
      threadId: threadId,
      observation: LiveStatusInputs(
        storage: session.storage,
        interactions: session.interactions,
        businessRefs: session.businessRefs,
        activeTurnId: session.activeTurn?.turnId,
        activity: session.activity,
        current: live,
        liveOpenWork: active ? lease.liveOpenWork.value : null,
        renderedCurrentAtomIds:
            lease?.renderedCurrentAtomIds ?? const <String>{},
        hasContentOwner: active,
      ),
      currentAtomsError: lease?.currentCollectionError.value,
      activityTools: _activityToolsView(),
    );
    if (resetActivityTools &&
        _activityToolsExpanded &&
        activityField != null &&
        !_loadingActivityTools) {
      _scheduleFirstActivityTools();
    }
    // Diagnostics borrow the very object rendered by this component, not a second projection.
    if (active) lease.liveStatus = view;
    return view;
  }

  void openActivityTools() {
    if (_activityToolsExpanded) return;
    _activityToolsExpanded = true;
    _activityToolsGeneration++;
    state = _project();
    unawaited(_loadActivityTools(direction: _ActivityToolsDirection.first));
  }

  void closeActivityTools() {
    if (!_activityToolsExpanded) return;
    _activityToolsExpanded = false;
    _activityToolsGeneration++;
    _activityToolsPage = const [];
    _activityToolsCursor = null;
    _activityToolsPrevious.clear();
    _activityToolsContinuation = null;
    _activityToolsError = null;
    state = _project();
  }

  void loadNextActivityTools() {
    unawaited(_loadActivityTools(direction: _ActivityToolsDirection.next));
  }

  void loadPreviousActivityTools() {
    unawaited(_loadActivityTools(direction: _ActivityToolsDirection.previous));
  }

  void loadFirstActivityTools() {
    unawaited(_loadActivityTools(direction: _ActivityToolsDirection.first));
  }

  void _scheduleFirstActivityTools() {
    if (_activityToolsLoadScheduled || _loadingActivityTools) return;
    _activityToolsLoadScheduled = true;
    unawaited(
      Future<void>.microtask(() async {
        _activityToolsLoadScheduled = false;
        await _loadActivityTools(direction: _ActivityToolsDirection.first);
      }),
    );
  }

  LiveActivityToolsWindow? _activityToolsView() {
    final field = _activityToolsField;
    if (field == null) return null;
    return LiveActivityToolsWindow(
      reference: field.reference,
      totalCount: field.count.toInt(),
      entries: _activityToolsPage,
      expanded: _activityToolsExpanded,
      loading: _loadingActivityTools,
      hasPrevious: _activityToolsPrevious.isNotEmpty,
      hasNext: _activityToolsContinuation != null,
      error: _activityToolsError,
    );
  }

  Future<void> _loadActivityTools({
    required _ActivityToolsDirection direction,
  }) async {
    await Future<void>.value();
    if (!ref.mounted) return;
    final activity = ref.read(threadSessionStoreProvider(threadId)).activity;
    final field = activity?.deferredField('tools.active');
    if (field is! CollectionCurrentStateField || _loadingActivityTools) {
      return;
    }
    final lease = ref.read(timelineSessionOwnerProvider).lease(threadId);
    if (lease == null || lease.isRetired) return;
    if (_activityToolsField != field) {
      _activityToolsGeneration++;
      _activityToolsField = field;
      _activityToolsPage = const [];
      _activityToolsCursor = null;
      _activityToolsContinuation = null;
      _activityToolsPrevious.clear();
      _activityToolsError = null;
    }
    final requestGeneration = _activityToolsGeneration;
    final targetCursor = switch (direction) {
      _ActivityToolsDirection.first => null,
      _ActivityToolsDirection.next => _activityToolsContinuation,
      _ActivityToolsDirection.previous =>
        _activityToolsPrevious.isEmpty ? null : _activityToolsPrevious.last,
    };
    if ((direction == _ActivityToolsDirection.next &&
            _activityToolsContinuation == null) ||
        (direction == _ActivityToolsDirection.previous &&
            _activityToolsPrevious.isEmpty)) {
      return;
    }
    final previousCursor = _activityToolsCursor;
    _loadingActivityTools = true;
    _activityToolsError = null;
    state = _project();
    final scope = lease.openCurrentScope(generation: lease.generation);
    _activityToolsScope = scope;
    try {
      final page = await scope.pageStateCollection(
        field,
        continuation: targetCursor,
        demand: const ReadDemand(maxItems: 20, maxBytes: 64 * 1024),
      );
      if (!ref.mounted ||
          lease.isRetired ||
          _activityToolsField != field ||
          !_activityToolsExpanded ||
          _activityToolsGeneration != requestGeneration ||
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
        final bytes = switch (payload) {
          InlineCurrentPayload(:final bytes) => bytes,
          DeferredCurrentPayload() =>
            throw const ConversationStateFieldDiscontinuity(),
        };
        loaded.add(
          decodeCurrentActivityToolState(jsonDecode(utf8.decode(bytes))),
        );
      }
      _activityToolsPage = List.unmodifiable(loaded);
      _activityToolsCursor = targetCursor;
      _activityToolsContinuation = page.continuation;
      switch (direction) {
        case _ActivityToolsDirection.first:
          _activityToolsPrevious.clear();
        case _ActivityToolsDirection.next:
          _activityToolsPrevious.add(previousCursor);
          if (_activityToolsPrevious.length > 16) {
            _activityToolsPrevious.removeAt(0);
          }
        case _ActivityToolsDirection.previous:
          if (_activityToolsPrevious.isNotEmpty) {
            _activityToolsPrevious.removeLast();
          }
      }
    } catch (error) {
      if (ref.mounted &&
          !lease.isRetired &&
          _activityToolsField == field &&
          _activityToolsExpanded &&
          _activityToolsGeneration == requestGeneration &&
          identical(
            ref.read(timelineSessionOwnerProvider).lease(threadId),
            lease,
          )) {
        _activityToolsError = error;
      }
    } finally {
      _loadingActivityTools = false;
      if (identical(_activityToolsScope, scope)) _activityToolsScope = null;
      scope.retire();
      try {
        await scope.close();
      } catch (error) {
        if (ref.mounted &&
            _activityToolsField == field &&
            _activityToolsExpanded &&
            _activityToolsGeneration == requestGeneration) {
          _activityToolsError ??= error;
        }
      }
      if (ref.mounted) {
        state = _project();
        final currentField = ref
            .read(threadSessionStoreProvider(threadId))
            .activity
            ?.deferredField('tools.active');
        if (_activityToolsExpanded &&
            currentField is CollectionCurrentStateField &&
            _activityToolsField == currentField &&
            _activityToolsPage.isEmpty &&
            currentField.count > 0 &&
            _activityToolsError == null) {
          _scheduleFirstActivityTools();
        }
      }
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
