import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show Key, ValueKey, ValueNotifier;
import 'package:flutter/widgets.dart' show ScrollController;
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../domain/models/timeline_commands.dart';
import '../../features/conversation/timeline/state/timeline_image_resources.dart';
import '../../features/conversation/timeline/state/timeline_display_diagnostics.dart';
import '../../features/conversation/timeline/state/timeline_view_state.dart';
import '../../features/conversation/timeline/state/timeline_ui_controllers.dart';
import '../../features/conversation/timeline/view_models/timeline_message_controller.dart';

export '../../features/conversation/timeline/state/timeline_view_state.dart';

const Object _unset = Object();

/// One presentation generation. Only its component controller owns loaded messages.
final class TimelineDisplayLease implements TimelineUiControllers {
  TimelineDisplayLease({
    required this.threadId,
    required this.generation,
    required this.demand,
    required this.content,
    this.selectionId,
    this.selectionStartedMicros,
  }) : _controller = InMemoryChatController(),
       imageResources = TimelineImageResources(threadId: threadId) {
    _presentation = TimelineMessageController(
      _controller!,
      generation: generation,
      imageResources: imageResources,
    );
  }

  final String threadId;
  final int generation;
  final ReadDemand demand;
  final ConversationContent content;
  final int? selectionId;
  final int? selectionStartedMicros;
  final TimelineImageResources imageResources;
  InMemoryChatController? _controller;
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );
  TimelineMessageController? _presentation;
  final Completer<void> _released = Completer<void>();
  final ValueNotifier<bool> retirement = ValueNotifier(false);
  final Set<ConversationQueryScope> _ownedQueries = {};
  final Map<ConversationQueryScope, Future<void>> _closingQueries = {};
  ConversationQueryScope? _queries;
  String? _before;
  TimelineDisplayMode _mode = TimelineDisplayMode.live;
  bool _hasOlder = false;
  bool _mounted = false;
  bool _retired = false;
  bool _disposed = false;
  int _mutations = 0;
  Object? queryCleanupError;
  final Set<TimelineChildrenDisplay> _childrenDisplays = {};
  TimelineCurrentDisplay? _currentDisplay;
  TimelineContentLayout? _firstContentLayout;
  int _appliedSets = 0;
  int _appliedPrepends = 0;
  int _appliedAppends = 0;

  TimelineContentLayout? get firstContentLayout => _firstContentLayout;
  int get appliedSets => _appliedSets;
  int get appliedPrepends => _appliedPrepends;
  int get appliedAppends => _appliedAppends;

  Iterable<TimelineChildrenDisplay> get childrenDisplays sync* {
    if (_retired) return;
    for (final display in _childrenDisplays) {
      if (display.isCurrent) yield display;
    }
  }

  /// Registers only a resource borrow. It neither opens a Children scope nor copies messages.
  void Function() registerChildrenDisplay(TimelineChildrenDisplay display) {
    if (_retired) return () {};
    _childrenDisplays.add(display);
    return () => _childrenDisplays.remove(display);
  }

  TimelineCurrentDisplay? get currentDisplay {
    if (_retired) return null;
    final display = _currentDisplay;
    return display != null && display.isCurrent ? display : null;
  }

  /// Borrows only the current mounted resource. Querying never opens its read scope.
  void Function() registerCurrentDisplay(TimelineCurrentDisplay display) {
    if (_retired) return () {};
    _currentDisplay = display;
    return () {
      if (identical(_currentDisplay, display)) _currentDisplay = null;
    };
  }

  void _recordBatch(ChatPlacement placement) {
    switch (placement) {
      case ChatPlacement.set:
        _appliedSets++;
      case ChatPlacement.prepend:
        _appliedPrepends++;
      case ChatPlacement.append:
        _appliedAppends++;
    }
  }

  @override
  Key get chatKey => ValueKey('timeline-chat:$threadId:$generation');
  @override
  ChatController get controller =>
      _controller ?? (throw StateError('Timeline display is released'));
  @override
  ScrollController get scrollController => _scrollController;
  @override
  bool get isRetired => _retired;
  bool get isMounted => _mounted;
  bool get isReleased => _released.isCompleted;
  TimelineDisplayMode get mode => _mode;
  String? get olderCursor => _before;
  bool get hasOlder => _hasOlder;
  int get loadedCount => _controller?.messages.length ?? 0;
  Future<void> get released => _released.future;

  ConversationQueryScope? get queries {
    if (_retired) return null;
    final existing = _queries;
    if (existing != null && existing.isActive) return existing;
    if (existing != null) unawaited(_settleQueries(existing));
    final scope = content.openScope(generation: generation);
    _ownedQueries.add(scope);
    return _queries = scope;
  }

  ConversationQueryScope? openDetailQueries() {
    if (_retired) return null;
    final scope = content.openScope(generation: generation);
    _ownedQueries.add(scope);
    return scope;
  }

  Future<void> closeDetailQueries(ConversationQueryScope scope) async {
    await _settleQueries(scope);
    if (_ownedQueries.contains(scope)) {
      throw StateError('History reader has not closed: $queryCleanupError');
    }
  }

  @override
  void bind() {
    if (_disposed) throw StateError('Timeline display was already released');
    _mounted = true;
  }

  @override
  Future<void> unbind() {
    _mounted = false;
    _releaseIfReady();
    return _released.future;
  }

  /// The controller cannot be disposed while an accepted public operation is
  /// settling, including a selection change re-entered from an operation stream.
  Future<T> _mutate<T>(Future<T> Function() operation) async {
    if (_retired) throw StateError('Timeline display is retired');
    _mutations++;
    try {
      return await operation();
    } finally {
      _mutations--;
      _releaseIfReady();
    }
  }

  Future<void> retire() {
    if (!_retired) {
      _retired = true;
      _childrenDisplays.clear();
      _currentDisplay = null;
      imageResources.retire();
      retirement.value = true;
      _queries = null;
    }
    for (final scope in _ownedQueries.toList()) {
      scope.retire();
      unawaited(_settleQueries(scope));
    }
    _releaseIfReady();
    return _released.future;
  }

  Future<void> _settleQueries(ConversationQueryScope scope) {
    if (!_ownedQueries.contains(scope)) return Future.value();
    final existing = _closingQueries[scope];
    if (existing != null) return existing;
    final task = _closeQuery(scope);
    _closingQueries[scope] = task;
    return task;
  }

  Future<void> _closeQuery(ConversationQueryScope scope) async {
    scope.retire();
    try {
      final report = await scope.close();
      if (report.complete) {
        _ownedQueries.remove(scope);
        if (_ownedQueries.isEmpty) queryCleanupError = null;
      } else {
        queryCleanupError = report;
      }
    } catch (error) {
      queryCleanupError = error;
    } finally {
      _closingQueries.remove(scope);
      _releaseIfReady();
    }
  }

  void _releaseIfReady() {
    if (_disposed ||
        !_retired ||
        _mounted ||
        _mutations != 0 ||
        _ownedQueries.isNotEmpty) {
      return;
    }
    _disposed = true;
    final controller = _controller!;
    controller.operationsStream.listen(
      (_) {},
      onDone: () {
        if (!_released.isCompleted) _released.complete();
      },
    );
    _presentation?.dispose();
    _presentation = null;
    imageResources.release();
    retirement.dispose();
    controller.dispose();
    _controller = null;
    _scrollController.dispose();
  }
}

/// The only completion consumer. Page results and completion batches commit
/// serially; network reads stay outside that commit chain and never hold credit.
final class TimelineSessionOwner {
  TimelineSessionOwner({required this.client});

  final AnyworkClient client;
  final LatestValue<TimelineSessionViewState?> source = LatestValue(null);
  Observation? _connectionObservation;
  Observation? _consumerObservation;
  ConversationSession? _observedSession;
  String? _observedThread;
  TimelineDisplayLease? _current;
  final Set<TimelineDisplayLease> _retiring = {};
  final Set<TimelineDisplayLease> _preparingDisplays = {};
  Future<void> _commits = Future.value();
  Future<void>? _olderInFlight;
  int _selection = 0;
  int _generation = 0;
  bool _bindingConsumer = false;
  bool _closed = false;
  Future<CloseReport>? _closing;
  ReadDemand? _readDemand;
  final Stopwatch _layoutClock = Stopwatch()..start();
  String? _selectionTarget;
  int _visibleSelectionId = 0;
  int? _selectionStartedMicros;

  int get monotonicMicros => _layoutClock.elapsedMicroseconds;

  /// Called at AppGraph's accepted visible selection boundary, before opening its read demand.
  void noteVisibleSelection(String? threadId) {
    if (_closed || _selectionTarget == threadId) return;
    _selectionTarget = threadId;
    _visibleSelectionId++;
    _selectionStartedMicros = threadId == null ? null : monotonicMicros;
  }

  /// Receives a timestamp captured after a real nonempty content subtree completed layout.
  /// The witness must check actual visibility at frame end; this owner rechecks original identity.
  void recordContentLayout(
    TimelineDisplayLease lease,
    String itemId,
    int layoutCompletedMicros,
  ) {
    final started = lease.selectionStartedMicros;
    final selectionId = lease.selectionId;
    if (_closed ||
        !identical(_current, lease) ||
        lease.isRetired ||
        !lease.isMounted ||
        lease.firstContentLayout != null ||
        _selectionTarget != lease.threadId ||
        selectionId != _visibleSelectionId ||
        started == null ||
        selectionId == null ||
        layoutCompletedMicros < started ||
        layoutCompletedMicros > monotonicMicros ||
        !lease.controller.messages.any((message) => message.id == itemId)) {
      return;
    }
    lease._firstContentLayout = TimelineContentLayout(
      selectionId: selectionId,
      generation: lease.generation,
      itemId: itemId,
      selectionStartedMicros: started,
      layoutCompletedMicros: layoutCompletedMicros,
    );
  }

  /// Updated from the actual viewport before the first consumer is attached.
  void updateReadDemand(ReadDemand demand) {
    if (_closed) return;
    _readDemand = demand;
    final session = _observedSession;
    if (session != null && _consumerObservation == null) {
      _attachConsumer(_selection, session);
    }
  }

  TimelineDisplayLease? lease(String threadId) {
    final value = _current;
    return value?.threadId == threadId && !value!.isRetired ? value : null;
  }

  bool _selected(int selection, ConversationSession session) =>
      !_closed &&
      _selection == selection &&
      identical(_observedSession, session);

  Future<void> _serialize(Future<void> Function() commit) {
    final result = _commits.then((_) => commit());
    // A failed frame remains visible to its consumer. It does not poison a later
    // independent reset/page commit or discard the real in-flight operation.
    _commits = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void select(String? threadId, {ResourceBudgetExceeded? admissionFailure}) {
    if (_closed) return;
    final session = threadId == null || admissionFailure != null
        ? null
        : client.conversations.existingSession(threadId);
    if (_observedThread == threadId &&
        identical(_observedSession, session) &&
        _consumerObservation != null) {
      return;
    }
    final selection = ++_selection;
    final previousConsumer = _consumerObservation;
    final previousConnection = _connectionObservation;
    final previous = _current;
    final preparing = _preparingDisplays.toList();
    _consumerObservation = null;
    _connectionObservation = null;
    _current = null;
    _olderInFlight = null;
    _observedThread = threadId;
    _observedSession = session;
    if (previous != null) _trackRetirement(previous);
    for (final display in preparing) {
      _trackRetirement(display);
    }
    // Publish ownership before invoking cancellation or retirement callbacks.
    // Reentry owns a new selection and may only be followed by cleanup of these
    // captured old handles, never by writing into the new selection.
    previousConnection?.cancel();
    previousConsumer?.cancel();
    if (previous != null) _retire(previous);
    for (final display in preparing) {
      _retire(display);
    }
    if (_closed || _selection != selection) return;
    if (threadId == null) {
      source.publish(null);
      return;
    }
    source.publish(
      TimelineSessionViewState(
        threadId: threadId,
        generation: 0,
        mode: TimelineDisplayMode.live,
        connection: admissionFailure == null
            ? TimelineConnectionPhase.idle
            : TimelineConnectionPhase.failed,
        connectionError: admissionFailure,
      ),
    );
    if (session == null || !_selected(selection, session)) return;
    final watched = session.content.state.watchLatest((state) {
      if (_selected(selection, session)) _onConnection(state);
    });
    if (!_selected(selection, session)) {
      watched.observation.cancel();
      return;
    }
    _connectionObservation = watched.observation;
    _onConnection(watched.value);
    if (_selected(selection, session)) _attachConsumer(selection, session);
  }

  void _attachConsumer(int selection, ConversationSession session) {
    // attachConsumer may synchronously open a feed and notify SDK observers
    // before returning its lease. A nested selection waits for this one local
    // acquisition to return, so A -> B -> A cannot bind over its provisional A.
    final demand = _readDemand;
    if (_bindingConsumer || !_selected(selection, session) || demand == null) {
      return;
    }
    _bindingConsumer = true;
    try {
      final observation = session.content.attachConsumer(
        _TimelineConsumer(this, selection, session),
        demand: demand,
      );
      if (_selected(selection, session)) {
        _consumerObservation = observation;
      } else {
        observation.cancel();
      }
    } catch (error) {
      if (_selected(selection, session)) {
        _publishState(
          connection: TimelineConnectionPhase.failed,
          connectionError: error,
        );
      }
    } finally {
      _bindingConsumer = false;
      final selected = _observedSession;
      if (!_closed &&
          _selection != selection &&
          selected != null &&
          _consumerObservation == null) {
        _attachConsumer(_selection, selected);
      }
    }
  }

  void _detach() {
    final consumer = _consumerObservation;
    final connection = _connectionObservation;
    _consumerObservation = null;
    _connectionObservation = null;
    _observedSession = null;
    connection?.cancel();
    consumer?.cancel();
  }

  void _onConnection(ChatUiState<bool> state) {
    final phase = switch (state) {
      ChatIdle<bool>() => TimelineConnectionPhase.idle,
      ChatOpening<bool>() => TimelineConnectionPhase.opening,
      ChatReady<bool>() => TimelineConnectionPhase.ready,
      ChatReconnecting<bool>() => TimelineConnectionPhase.reconnecting,
      ChatFailed<bool>() => TimelineConnectionPhase.failed,
      ChatClosed<bool>() => TimelineConnectionPhase.closed,
    };
    final error = switch (state) {
      ChatReconnecting<bool>(:final error) ||
      ChatFailed<bool>(:final error) => error,
      _ => null,
    };
    _publishState(connection: phase, connectionError: error);
  }

  Future<void> _accept(
    int selection,
    ConversationSession session,
    ChatBatch batch,
  ) => _serialize(() async {
    if (!_selected(selection, session)) return;
    if (batch.placement == ChatPlacement.set) {
      await _set(selection, session, batch);
      return;
    }
    final current = _current;
    if (current == null || current.isRetired) {
      throw const ConversationContinuityError('Chat has no active display');
    }
    final presentation = current._presentation!;
    await current._mutate(() => presentation.applyBatch(batch));
    if (!_selected(selection, session) ||
        !identical(_current, current) ||
        current.isRetired) {
      return;
    }
    current._recordBatch(batch.placement);
    if (batch.placement == ChatPlacement.prepend) {
      current._before = batch.before;
      current._hasOlder = batch.before != null;
      _publishState(isLoadingOlder: false, olderError: null);
    } else if (batch.messages.isNotEmpty) {
      _publishState(hasNewOutput: current.mode == TimelineDisplayMode.history);
    }
  });

  Future<void> _set(
    int selection,
    ConversationSession session,
    ChatBatch batch,
  ) async {
    final next = TimelineDisplayLease(
      threadId: session.threadId,
      generation: ++_generation,
      demand: _readDemand!,
      content: session.content,
      selectionId: _selectionTarget == session.threadId
          ? _visibleSelectionId
          : null,
      selectionStartedMicros: _selectionTarget == session.threadId
          ? _selectionStartedMicros
          : null,
    );
    _preparingDisplays.add(next);
    try {
      final presentation = next._presentation!;
      await next._mutate(() => presentation.applyBatch(batch));
    } catch (_) {
      _preparingDisplays.remove(next);
      _retire(next);
      rethrow;
    }
    _preparingDisplays.remove(next);
    if (!_selected(selection, session)) {
      _retire(next);
      return;
    }
    next._before = batch.before;
    next._recordBatch(batch.placement);
    next._hasOlder = batch.before != null;
    final previous = _current;
    next._mode = previous?.mode ?? TimelineDisplayMode.live;
    _current = next;
    _olderInFlight = null;
    if (previous != null) _retire(previous);
    _publishState(isLoadingOlder: false, olderError: null, hasNewOutput: false);
  }

  void _trackRetirement(TimelineDisplayLease lease) {
    if (_retiring.add(lease)) {
      lease.released.then((_) => _retiring.remove(lease));
    }
  }

  void _retire(TimelineDisplayLease lease) {
    _trackRetirement(lease);
    unawaited(lease.retire());
  }

  Future<void> retire() {
    final current = _current;
    select(null);
    return current?.released ?? Future.value();
  }

  void _publishState({
    TimelineConnectionPhase? connection,
    Object? connectionError = _unset,
    Object? olderError = _unset,
    bool? isLoadingOlder,
    bool? hasNewOutput,
  }) {
    final current = source.value;
    if (current == null) return;
    final display = _current;
    final next = current.copyWith(
      generation: display?.generation ?? current.generation,
      mode: display?.mode ?? current.mode,
      connection: connection ?? current.connection,
      connectionError: identical(connectionError, _unset)
          ? current.connectionError
          : connectionError,
      olderCursor: display?.olderCursor,
      hasOlder: display?.hasOlder ?? false,
      isLoadingOlder: isLoadingOlder ?? current.isLoadingOlder,
      olderError: identical(olderError, _unset)
          ? current.olderError
          : olderError,
      hasNewOutput: hasNewOutput ?? current.hasNewOutput,
    );
    if (next != current) source.publish(next);
  }

  Future<void> dispatch(String threadId, TimelineCommand command) {
    final current = lease(threadId);
    if (current == null) return Future.value();
    switch (command) {
      case TimelineEnterHistory():
        current._mode = TimelineDisplayMode.history;
        _publishState();
      case TimelineReturnLive():
        return returnToLive(threadId);
    }
    return Future.value();
  }

  /// Reading intent changes no Session, consumer, query scope or loaded window.
  Future<void> returnToLive(String threadId) async {
    final current = lease(threadId);
    if (current == null) return;
    current._mode = TimelineDisplayMode.live;
    _publishState(hasNewOutput: false);
  }

  Future<void> loadOlder(String threadId, {required int generation}) =>
      _requestOlder(threadId, generation: generation, retry: false);
  Future<void> retryOlder(String threadId, {required int generation}) =>
      _requestOlder(threadId, generation: generation, retry: true);

  Future<void> _requestOlder(
    String threadId, {
    required int generation,
    required bool retry,
  }) {
    final current = lease(threadId);
    if (current == null || current.generation != generation) {
      return Future.value();
    }
    final existing = _olderInFlight;
    if (existing != null) return existing;
    final task = _loadOlder(current, retry: retry);
    _olderInFlight = task;
    task.then(
      (_) {
        if (identical(_olderInFlight, task)) _olderInFlight = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_olderInFlight, task)) _olderInFlight = null;
      },
    );
    return task;
  }

  Future<void> _loadOlder(
    TimelineDisplayLease current, {
    required bool retry,
  }) async {
    if (!current.hasOlder ||
        current._before == null ||
        (!retry && source.value?.olderError != null)) {
      return;
    }
    final before = current._before!;
    _publishState(isLoadingOlder: true, olderError: null);
    try {
      final scope = current.queries;
      if (scope == null) return;
      // The SDK performs IO outside admission, then resolves only after the same
      // captured consumer applied the Prepend. Do not insert the returned batch twice.
      await scope.loadOlder(
        before: before,
        demand: _readDemand ?? current.demand,
      );
      if (!identical(_current, current) ||
          current.isRetired ||
          !scope.isActive) {
        return;
      }
      if (current._before == before) {
        throw const ConversationContinuityError('History page did not advance');
      }
      _publishState(isLoadingOlder: false, olderError: null);
    } catch (error) {
      if (identical(_current, current) && !current.isRetired) {
        _publishState(isLoadingOlder: false, olderError: error);
      }
    } finally {
      if (identical(_current, current) &&
          source.value?.isLoadingOlder == true) {
        _publishState(isLoadingOlder: false);
      }
    }
  }

  Future<CloseReport> close({DateTime? deadline}) {
    final existing = _closing;
    if (existing != null) return existing;
    final completion = Completer<CloseReport>();
    final closing = completion.future;
    // Install the shared result before cancellation, display retirement or
    // publishing null can synchronously call close again.
    _closing = closing;
    unawaited(
      Future<CloseReport>.sync(() {
        _closed = true;
        ++_selection;
        final leases = <TimelineDisplayLease>{
          ..._retiring,
          ..._preparingDisplays,
          ?_current,
        };
        _current = null;
        for (final lease in leases) {
          _trackRetirement(lease);
        }
        _detach();
        if (source.value != null) source.publish(null);
        for (final lease in leases) {
          _retire(lease);
        }
        return _join(leases, deadline);
      }).then<void>(
        (report) {
          if (!report.complete && identical(_closing, closing)) _closing = null;
          completion.complete(report);
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_closing, closing)) _closing = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return closing;
  }

  Future<CloseReport> _join(
    Set<TimelineDisplayLease> leases,
    DateTime? deadline,
  ) async {
    final pending = Future.wait<void>([
      _commits,
      ?_olderInFlight,
      for (final lease in leases) lease.released,
    ]);
    if (deadline == null) {
      await pending;
    } else {
      final remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) {
        try {
          await pending.timeout(remaining);
        } on TimeoutException {
          // All owners and native close obligations remain retained for retry.
        }
      }
    }
    return CloseReport(
      unresolved: [
        for (final lease in leases)
          if (!lease.isReleased)
            UnresolvedResource(
              owner: 'timeline-display:${lease.threadId}',
              attemptId: AttemptId(lease.generation),
              reason: StateError(
                'Display is not released: '
                '${lease.queryCleanupError ?? "waiting for operations/subtree detach"}',
              ),
            ),
      ],
    );
  }
}

final class _TimelineConsumer implements ConversationBatchConsumer {
  const _TimelineConsumer(this.owner, this.selection, this.session);
  final TimelineSessionOwner owner;
  final int selection;
  final ConversationSession session;
  @override
  Future<void> applyBatch(ChatBatch batch) =>
      owner._accept(selection, session, batch);
}
