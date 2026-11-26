import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../domain/models/timeline_commands.dart';
import '../../features/conversation/timeline/live_status/live_status_state.dart'
    show LiveStatusView;
import '../../features/conversation/timeline/state/timeline_display_diagnostics.dart';
import '../../features/conversation/timeline/state/timeline_display_unit.dart';
import '../../features/conversation/timeline/state/timeline_feed_projection.dart';
import '../../features/conversation/timeline/state/timeline_image_resources.dart';
import '../../features/conversation/timeline/state/timeline_ui_controllers.dart';
import '../../features/conversation/timeline/state/timeline_view_state.dart';

export '../../features/conversation/timeline/state/timeline_view_state.dart';

const _maxPausedItems = 64;

ClientResourceId _resourceId() {
  final random = Random.secure();
  return ClientResourceId(
    List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join(),
    0,
  );
}

/// A mounted presentation borrows the controller until its view unbinds.
final class TimelineDisplayLease implements TimelineUiControllers {
  TimelineDisplayLease._(
    this._read,
    this.selectionId,
    this.selectionStartedMicros,
  ) : imageResources = TimelineImageResources(threadId: _read.threadId);

  final _FeedRead _read;
  final ClientResourceId resourceId = _resourceId();
  int generation = 0;
  final int selectionId;
  final int? selectionStartedMicros;
  final TimelineImageResources imageResources;
  final retirement = ValueNotifier(false);
  final _controller = InMemoryChatController();
  final _scrollController = ScrollController(keepScrollOffset: false);
  final _released = Completer<void>();
  final _expansions = <String, TimelineExpansionIntent>{};
  final _groups = <TimelineGroupDisplay>{};
  final _pausedItems = <String, TimelineItem>{};
  bool _overflow = false;
  bool _mounted = false;
  bool _disposing = false;
  int _mutations = 0;
  int _resetCount = 0;
  int _historyIntent = 0;
  TimelineDisplayMode mode = TimelineDisplayMode.live;
  String? olderCursor;
  bool hasOlder = false;
  int appliedPrepends = 0;
  int appliedAppends = 0;
  TimelineContentLayout? firstContentLayout;
  LiveStatusView? liveStatus;

  String get threadId => _read.threadId;
  int get loadedCount => _controller.messages.length;
  int get appliedSets => _resetCount;
  bool get isMounted => _mounted;
  bool get isReleased => _released.isCompleted;
  Future<void> get released => _released.future;
  bool get hasNewOutput => _overflow || _pausedItems.isNotEmpty;
  bool get canRead => !isRetired && !_read.cancelled;

  @override
  Key get chatKey => ValueKey((threadId, generation, _resetCount));
  @override
  ChatController get controller => _controller;
  @override
  ScrollController get scrollController => _scrollController;
  @override
  bool get isRetired => retirement.value;

  @override
  void bind() {
    if (!isRetired) _mounted = true;
  }

  @override
  Future<void> unbind() async {
    _mounted = false;
    _releaseIfUnused();
    if (isRetired) await released;
  }

  void _retire() {
    if (isRetired) return;
    retirement.value = true;
    imageResources.retire();
    for (final expansion in _expansions.values) {
      expansion.retire();
    }
    _expansions.clear();
    _clearPaused();
    _releaseIfUnused();
  }

  void _releaseIfUnused() {
    if (!isRetired || _disposing || _mounted || _mutations != 0) return;
    _disposing = true;
    _controller.operationsStream.listen((_) {}, onDone: _released.complete);
    _controller.dispose();
    _scrollController.dispose();
    imageResources.release();
    retirement.dispose();
  }

  Future<void> _mutate(Future<void> Function() operation) async {
    if (!canRead) throw StateError('Timeline display retired');
    _mutations++;
    try {
      await operation();
    } finally {
      _mutations--;
      _releaseIfUnused();
    }
  }

  Iterable<TimelineGroupDisplay> get groupDisplays =>
      _groups.where((display) => display.isCurrent);

  VoidCallback registerGroupDisplay(TimelineGroupDisplay display) {
    if (canRead) _groups.add(display);
    return () => _groups.remove(display);
  }

  Future<List<WorkGroupMember>> loadWorkGroupMembers(TimelineWorkGroup group) =>
      _query(
        (feed) => feed.loadWorkGroupMembers(
          afterSeq: group.afterBoundarySeq,
          beforeSeq: group.beforeBoundarySeq,
        ),
      );

  Future<BodyWindow> readBodyWindow(
    BodyRef reference, {
    required int offset,
    required int maxBytes,
  }) => _query(
    (feed) => feed.readBodyWindow(
      reference: reference,
      offset: offset,
      maxBytes: maxBytes,
    ),
  );

  Future<T> _query<T>(Future<T> Function(ConversationFeedHandle) run) async {
    if (!canRead) throw StateError('Timeline display retired');
    final generation = this.generation;
    final value = await run(_read.feed!);
    if (!canRead || this.generation != generation) {
      throw StateError('Timeline display retired');
    }
    return value;
  }

  Message? _message(String id) =>
      _controller.messages.where((message) => message.id == id).firstOrNull;

  Message _project(TimelineItem item) => timelineFeedMessage(
    item,
    expansion: item is TimelineWorkGroup
        ? _expansions.putIfAbsent(item.id, TimelineExpansionIntent.new)
        : null,
  );

  void _bindExpansion(Message message) {
    final unit = message.metadata?[timelineDisplayUnitKey];
    if (unit is TimelineDisplayUnit) unit.expansion.current = unit;
  }

  void _discardExpansion(String id) => _expansions.remove(id)?.retire();

  void _clearPaused() {
    _pausedItems.clear();
    _overflow = false;
  }

  void _pauseAppend(List<TimelineItem> items) {
    if (_overflow) return;
    if (_pausedItems.length + items.length > _maxPausedItems) {
      _clearPaused();
      _overflow = true;
      return;
    }
    for (final item in items) {
      _pausedItems[item.id] = item;
    }
  }

  Future<void> _reset(TimelineReset patch) => _mutate(() async {
    final retained = {for (final item in patch.items) item.id};
    final messages = patch.items.map(_project).toList();
    await _controller.setMessages(messages, animated: false);
    if (!canRead) return;
    for (final id in _expansions.keys.toList()) {
      if (!retained.contains(id)) _discardExpansion(id);
    }
    messages.forEach(_bindExpansion);
    _resetCount++;
    olderCursor = patch.olderCursor;
    hasOlder = patch.hasMoreOlder;
    _clearPaused();
  });

  Future<void> _insert(List<TimelineItem> items, {bool prepend = false}) =>
      _mutate(() async {
        if (items.isEmpty) return;
        final messages = items.map(_project).toList();
        await _controller.insertAllMessages(
          messages,
          index: prepend ? 0 : null,
          animated: false,
        );
        if (!canRead) return;
        messages.forEach(_bindExpansion);
        if (prepend) {
          appliedPrepends++;
        } else {
          appliedAppends++;
        }
        _recordApplied(prepend ? 'prepend' : 'append', messages.length);
      });

  void _recordApplied(String placement, int count) {
    developer.Timeline.instantSync(
      'conversation.applied',
      arguments: {
        'generation': generation,
        'placement': placement,
        'acceptedBlocks': count,
        'controllerMessages': loadedCount,
      },
    );
  }

  Future<void> _update(TimelineItem item) => _mutate(() async {
    if (_pausedItems.containsKey(item.id)) {
      _pausedItems[item.id] = item;
      return;
    }
    final previous = _message(item.id);
    if (previous == null || timelineFeedItemOf(previous) == item) return;
    final message = _project(item);
    await _controller.updateMessage(previous, message);
    if (canRead) _bindExpansion(message);
  });

  Future<void> _remove(String id) => _mutate(() async {
    if (_pausedItems.remove(id) != null) {
      return;
    }
    final message = _message(id);
    if (message == null) return;
    await _controller.removeMessage(message, animated: false);
    if (canRead) _discardExpansion(id);
  });
}

final class TimelineSessionOwner {
  TimelineSessionOwner({required this.client});

  final AnyworkClient client;
  final source = LatestValue<TimelineSessionViewState?>(null);
  final liveStatus =
      LatestValue<
        ({String threadId, LiveStatusSnapshot snapshot, DateTime receivedAt})?
      >(null);
  final _reads = <_FeedRead>{};
  final _retiring = <TimelineDisplayLease>{};
  final _clock = Stopwatch()..start();
  Future<void> _commits = Future.value();
  TimelineDisplayLease? _lease;
  _FeedRead? _read;
  String? _selectedThread;
  String? _selectionTarget;
  int _selectionId = 0;
  int _selectionSerial = 0;
  int? _selectionStarted;
  int _generation = 0;
  int _displayGeneration = 0;
  int? _pageLimit;
  bool _closed = false;
  Future<CloseReport>? _closing;
  Future<CloseReport>? _retrying;

  int get monotonicMicros => _clock.elapsedMicroseconds;

  TimelineDisplayLease? lease(String threadId) {
    final lease = _lease;
    return lease != null && lease.threadId == threadId && !lease.isRetired
        ? lease
        : null;
  }

  void noteVisibleSelection(String? threadId) {
    if (_closed || _selectionTarget == threadId) return;
    _selectionTarget = threadId;
    _selectionId++;
    _selectionStarted = threadId == null ? null : monotonicMicros;
  }

  void recordContentLayout(
    TimelineDisplayLease lease,
    String itemId,
    int micros,
  ) {
    final started = lease.selectionStartedMicros;
    if (_closed ||
        !identical(_lease, lease) ||
        lease.isRetired ||
        !lease.isMounted ||
        lease.firstContentLayout != null ||
        lease.threadId != _selectionTarget ||
        lease.selectionId != _selectionId ||
        started == null ||
        micros < started ||
        micros > monotonicMicros ||
        lease._message(itemId) == null) {
      return;
    }
    lease.firstContentLayout = TimelineContentLayout(
      selectionId: lease.selectionId,
      generation: lease.generation,
      itemId: itemId,
      selectionStartedMicros: started,
      layoutCompletedMicros: micros,
    );
  }

  ({
    String threadId,
    int selectionId,
    int generation,
    TimelineContentLayout? firstContentLayout,
  })?
  get visibleLayoutSnapshot {
    final lease = _lease;
    if (_closed ||
        lease == null ||
        lease.isRetired ||
        !lease.isMounted ||
        lease.threadId != _selectionTarget ||
        lease.selectionId != _selectionId) {
      return null;
    }
    return (
      threadId: lease.threadId,
      selectionId: lease.selectionId,
      generation: lease.generation,
      firstContentLayout: lease.firstContentLayout,
    );
  }

  void updateReadDemand(int pageLimit) {
    if (_closed) return;
    _pageLimit = pageLimit;
    final threadId = _selectedThread;
    if (_read == null && threadId != null) _start(threadId);
  }

  void select(String? threadId) {
    if (_closed || _selectedThread == threadId) return;
    final serial = ++_selectionSerial;
    _selectedThread = threadId;
    final previous = _read;
    final display = _lease;
    _read = null;
    _lease = null;
    previous?.cancel();
    if (display != null) _retireDisplay(display);
    if (_closed || serial != _selectionSerial) return;
    liveStatus.publish(null);
    if (_closed || serial != _selectionSerial) return;
    source.publish(
      threadId == null
          ? null
          : TimelineSessionViewState(
              threadId: threadId,
              generation: 0,
              mode: TimelineDisplayMode.live,
              connection: TimelineConnectionPhase.idle,
            ),
    );
    if (threadId != null && serial == _selectionSerial && _read == null) {
      _start(threadId);
    }
  }

  void refresh(String threadId) {
    if (_closed || _selectedThread != threadId) return;
    _start(threadId, retry: true);
  }

  bool _owns(_FeedRead read) =>
      !_closed && !read.cancelled && identical(_read, read);

  void _start(String threadId, {bool retry = false, bool recovering = false}) {
    final limit = _pageLimit;
    if (_closed || _selectedThread != threadId || limit == null) return;
    final previous = _reads.toList();
    final read = _FeedRead(threadId, ++_generation);
    final ready = Completer<void>();
    read.task = ready.future;
    _read = read;
    _reads.add(read);
    for (final item in previous) {
      item.cancel();
    }
    ready.complete(
      _run(read, previous, limit, retry: retry, recovering: recovering),
    );
  }

  Future<void> _run(
    _FeedRead read,
    List<_FeedRead> previous,
    int limit, {
    required bool retry,
    required bool recovering,
  }) async {
    try {
      _publish(
        read,
        recovering
            ? TimelineConnectionPhase.reconnecting
            : TimelineConnectionPhase.opening,
      );
      for (final retired in previous) {
        await retired.task;
        if (retry && retired.closeError != null) await retired.joinClose();
        _forgetClosedRead(retired);
        if (retired.closeError case final failure?) throw failure.$1;
      }
      if (!_owns(read)) return;
      if (liveStatus.value != null) liveStatus.publish(null);
      if (!_owns(read)) return;
      final feed = await client.conversations.openConversationFeed(
        read.threadId,
        initialLimit: limit,
      );
      read.feed = feed;
      if (!_owns(read)) return;
      if (feed.threadId != read.threadId) {
        throw StateError('Conversation feed thread identity mismatch');
      }
      final events = read.events = StreamIterator(feed.events);
      while (_owns(read) && await events.moveNext()) {
        if (!_owns(read)) break;
        switch (events.current) {
          case ConversationLiveStatus(:final snapshot):
            liveStatus.publish((
              threadId: read.threadId,
              snapshot: snapshot,
              receivedAt: DateTime.now(),
            ));
          case ConversationSessionMeta():
            // The Client publishes this event through its existing Session store.
            break;
          case ConversationTimeline(:final patch):
            try {
              await _serialize(() async {
                if (_owns(read)) await _apply(read, patch);
              });
            } catch (error) {
              if (_owns(read) && !recovering) {
                _start(read.threadId, recovering: true);
                return;
              }
              rethrow;
            }
          case ConversationInputPresented(:final inputId):
            _markPresented(read.threadId, [inputId]);
          case ConversationResyncRequired(:final reason):
            if (recovering) throw StateError(reason);
            _start(read.threadId, recovering: true);
            return;
        }
      }
      if (_owns(read)) throw StateError('Conversation feed ended');
    } catch (error) {
      if (_owns(read)) {
        liveStatus.publish(null);
        _publish(read, TimelineConnectionPhase.failed, error: error);
      }
    } finally {
      await read.joinClose();
      _forgetClosedRead(read);
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    final queued = Stopwatch()..start();
    final result = _commits.then((_) {
      developer.Timeline.instantSync(
        'conversation.admission',
        arguments: {
          'owner': 'timeline',
          'threadId': _selectedThread ?? '',
          'queueWaitMicros': queued.elapsedMicroseconds,
        },
      );
      return action();
    });
    _commits = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _publish(
    _FeedRead read,
    TimelineConnectionPhase phase, {
    Object? error,
  }) {
    if (!_owns(read)) return;
    final display = _lease;
    final next = TimelineSessionViewState(
      threadId: read.threadId,
      generation: display?.generation ?? 0,
      mode: display?.mode ?? TimelineDisplayMode.live,
      connection: phase,
      connectionError: error,
      olderCursor: display?.olderCursor,
      hasOlder: display?.hasOlder ?? false,
      isLoadingOlder: read.older != null,
      olderError: read.olderError,
      hasNewOutput: display?.hasNewOutput ?? false,
    );
    if (source.value != next) source.publish(next);
  }

  Future<void> _apply(_FeedRead read, TimelinePatch patch) async {
    if (patch is TimelineReset) {
      final previous = _lease;
      final replacing = !identical(previous?._read, read);
      final display = replacing
          ? TimelineDisplayLease._(read, _selectionId, _selectionStarted)
          : previous!;
      try {
        await display._reset(patch);
      } catch (_) {
        if (replacing) _retireDisplay(display);
        rethrow;
      }
      if (!_owns(read)) {
        if (replacing) _retireDisplay(display);
        return;
      }
      display.generation = ++_displayGeneration;
      _lease = display;
      display._recordApplied('set', patch.items.length);
      if (replacing && previous != null) _retireDisplay(previous);
      if (!_owns(read)) return;
      if (read.resetWaiter case final waiter?) {
        display.mode = display._historyIntent == read.returnIntent
            ? TimelineDisplayMode.live
            : TimelineDisplayMode.history;
        if (!waiter.isCompleted) {
          waiter.complete(display.mode == TimelineDisplayMode.live);
        }
      }
      _markPresented(
        read.threadId,
        patch.items
            .whereType<TimelineUserMessage>()
            .map((item) => item.inputId)
            .nonNulls,
      );
    } else {
      final display = _lease;
      if (display == null || !identical(display._read, read)) {
        throw StateError('Timeline patch arrived before Reset');
      }
      switch (patch) {
        case TimelineReset():
          throw StateError('Unexpected timeline reset');
        case TimelinePrependOlder(
          :final items,
          :final olderCursor,
          :final hasMoreOlder,
        ):
          await display._insert(items, prepend: true);
          if (!_owns(read)) return;
          display.olderCursor = olderCursor;
          display.hasOlder = hasMoreOlder;
        case TimelineAppend(:final items):
          if (display.mode == TimelineDisplayMode.history) {
            display._pauseAppend(items);
          } else {
            await display._insert(items);
          }
        case TimelineUpdate(:final item):
          await display._update(item);
        case TimelineRemove(:final itemId):
          await display._remove(itemId);
      }
    }
    _publish(read, TimelineConnectionPhase.ready);
  }

  void _markPresented(String threadId, Iterable<String> inputIds) {
    final ids = inputIds.toList(growable: false);
    if (ids.isEmpty) return;
    client.drafts.existingComposer(threadId)?.markInputsPresented(ids);
    client.drafts.startDraft.markInputsPresented(ids);
  }

  Future<void> enterHistory(String threadId) {
    final display = lease(threadId);
    if (display == null) return Future.value();
    return _serialize(() async {
      if (!_owns(display._read)) return;
      display._historyIntent++;
      if (display.mode == TimelineDisplayMode.history) return;
      display.mode = TimelineDisplayMode.history;
      _publish(display._read, TimelineConnectionPhase.ready);
    });
  }

  Future<bool> returnToLive(String threadId) async {
    final display = lease(threadId);
    if (display == null || !_owns(display._read)) return false;
    final read = display._read;
    var reset = false;
    try {
      await _serialize(() async {
        if (!_owns(read) || display.mode == TimelineDisplayMode.live) return;
        if (display._overflow) {
          reset = true;
          return;
        }
        await display._insert(display._pausedItems.values.toList());
        if (!_owns(read)) return;
        display._clearPaused();
        display.mode = TimelineDisplayMode.live;
        _publish(read, TimelineConnectionPhase.ready);
      });
      if (!_owns(read)) return false;
      if (!reset) return display.mode == TimelineDisplayMode.live;
      if (read.resetWaiter case final pending?) return await pending.future;
      final waiter = read.resetWaiter = Completer<bool>();
      read.returnIntent = display._historyIntent;
      try {
        // The event stream is the sole admission point for Reset.
        await read.feed!.resetToLatest(limit: _pageLimit!);
        return await waiter.future &&
            _owns(read) &&
            display.mode == TimelineDisplayMode.live;
      } finally {
        if (identical(read.resetWaiter, waiter)) read.resetWaiter = null;
      }
    } catch (_) {
      if (_owns(read)) _start(threadId, recovering: true);
      return false;
    }
  }

  Future<void> loadOlder(String threadId, {required int generation}) =>
      _requestOlder(threadId, generation, retry: false);
  Future<void> retryOlder(String threadId, {required int generation}) =>
      _requestOlder(threadId, generation, retry: true);

  Future<void> _requestOlder(
    String threadId,
    int generation, {
    required bool retry,
  }) {
    final display = lease(threadId);
    final cursor = display?.olderCursor;
    if (display == null ||
        display.generation != generation ||
        !_owns(display._read) ||
        !display.hasOlder ||
        cursor == null) {
      return Future.value();
    }
    final read = display._read;
    if (read.older case final pending?) return pending;
    if (!retry && read.olderError != null) return Future.value();
    final done = Completer<void>();
    read.older = done.future;
    read.olderError = null;
    _publish(read, TimelineConnectionPhase.ready);
    final resetCount = display.appliedSets;
    done.complete(_loadOlder(display, cursor, resetCount));
    return done.future;
  }

  Future<void> _loadOlder(
    TimelineDisplayLease display,
    String cursor,
    int resetCount,
  ) async {
    final read = display._read;
    try {
      if (!_owns(read)) return;
      final patch = await read.feed!.loadOlder(
        cursor: cursor,
        limit: _pageLimit!,
      );
      await _serialize(() async {
        if (!_owns(read) || display.appliedSets != resetCount) return;
        if (patch is! TimelinePrependOlder ||
            (patch.hasMoreOlder &&
                (patch.olderCursor == null || patch.olderCursor == cursor))) {
          throw StateError('Older timeline page did not advance its cursor');
        }
        try {
          await _apply(read, patch);
        } catch (_) {
          if (_owns(read)) _start(read.threadId, recovering: true);
          rethrow;
        }
      });
    } catch (error) {
      if (_owns(read) && display.appliedSets == resetCount) {
        read.olderError = error;
      }
    } finally {
      read.older = null;
      if (_owns(read)) _publish(read, TimelineConnectionPhase.ready);
    }
  }

  void _retireDisplay(TimelineDisplayLease display) {
    if (!_retiring.add(display)) return;
    display._retire();
    unawaited(display.released.then((_) => _retiring.remove(display)));
  }

  void _forgetClosedRead(_FeedRead read) {
    if (read.closeError == null) _reads.remove(read);
  }

  Future<CloseReport> close({ClientCloseBudget? budget}) {
    if (_closing case final existing?) return existing;
    final done = Completer<CloseReport>();
    _closing = done.future;
    _closed = true;
    final read = _read;
    final display = _lease;
    _read = null;
    _lease = null;
    read?.cancel();
    if (display != null) _retireDisplay(display);
    liveStatus.publish(null);
    source.publish(null);
    done.complete(_join(budget, retry: false));
    return done.future;
  }

  Future<CloseReport> retryCleanup({required ClientCloseBudget budget}) {
    if (_retrying case final existing?) return existing;
    final done = Completer<CloseReport>();
    _retrying = done.future;
    done.complete(
      _join(budget, retry: true).whenComplete(() => _retrying = null),
    );
    return done.future;
  }

  Future<CloseReport> _join(
    ClientCloseBudget? budget, {
    required bool retry,
  }) async {
    final reads = _reads.where((read) => read.cancelled).toList();
    final pending = Future.wait<void>([
      _commits,
      for (final display in _retiring.toList()) display.released,
      for (final read in reads) _joinRead(read, retry: retry),
    ]);
    if (budget == null) {
      await pending;
    } else {
      try {
        await pending.timeout(budget.remaining);
      } on TimeoutException {
        // The original tasks remain owned and joinable.
      }
    }
    return CloseReport(
      unresolved: [
        for (final read in reads)
          if (_reads.contains(read))
            _unresolved(
              read.resourceId,
              read.threadId,
              read.generation,
              'timeline-feed',
              read.closeError,
            ),
        for (final display in _retiring)
          if (!display.isReleased)
            _unresolved(
              display.resourceId,
              display.threadId,
              display.generation,
              'timeline-display',
              null,
            ),
      ],
    );
  }

  Future<void> _joinRead(_FeedRead read, {required bool retry}) async {
    await read.task;
    if (retry && read.closeError != null) await read.joinClose();
    _forgetClosedRead(read);
  }

  UnresolvedResource _unresolved(
    ClientResourceId id,
    String threadId,
    int generation,
    String stage,
    (Object, StackTrace)? failure,
  ) {
    final owner = '$stage:$threadId';
    return UnresolvedResource(
      resourceId: id,
      owner: owner,
      attemptId: AttemptId(generation),
      reason: failure?.$1 ?? StateError('Resource is still closing'),
      ownership: ClientOwnership.owned,
      stages: [
        ClientResourceStage(
          owner: owner,
          phase: ClientClosePhase.close,
          ownership: ClientOwnership.owned,
          pending: failure == null,
          error: failure?.$1,
          stackTrace: failure?.$2,
        ),
      ],
    );
  }
}

final class _FeedRead {
  _FeedRead(this.threadId, this.generation);

  final String threadId;
  final int generation;
  final ClientResourceId resourceId = _resourceId();
  late final Future<void> task;
  ConversationFeedHandle? feed;
  StreamIterator<ConversationFeedEvent>? events;
  Future<void>? older;
  Object? olderError;
  Completer<bool>? resetWaiter;
  int? returnIntent;
  bool cancelled = false;
  (Object, StackTrace)? closeError;
  Future<void>? _closing;
  Future<void>? _eventCancellation;

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    if (resetWaiter case final waiter? when !waiter.isCompleted) {
      waiter.complete(false);
    }
    try {
      feed?.requestClose();
    } catch (error, stack) {
      closeError = (error, stack);
    }
    final iterator = events;
    if (iterator != null) {
      _eventCancellation = iterator.cancel().then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          closeError ??= (error, stack);
        },
      );
    }
  }

  Future<void> joinClose() {
    if (_closing case final current?) return current;
    final done = Completer<void>();
    _closing = done.future;
    done.complete(_close().whenComplete(() => _closing = null));
    return done.future;
  }

  Future<void> _close() async {
    cancel();
    final iterator = events;
    events = null;
    final handle = feed;
    try {
      handle?.requestClose();
    } catch (error, stack) {
      closeError = (error, stack);
    }
    try {
      await Future.wait<void>([
        if (iterator != null) _eventCancellation ?? iterator.cancel(),
        if (handle != null) Future.sync(handle.close),
        ?older,
      ]);
      feed = null;
      closeError = null;
    } catch (error, stack) {
      closeError = (error, stack);
    }
  }
}
