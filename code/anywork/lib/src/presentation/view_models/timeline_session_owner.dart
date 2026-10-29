import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart'
    show Key, Listenable, ValueKey, ValueNotifier;
import 'package:flutter/widgets.dart' show ScrollController;
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../domain/models/timeline_commands.dart';
import '../../features/conversation/timeline/state/timeline_entry.dart';
import '../../features/conversation/timeline/state/timeline_image_resources.dart';
import '../../features/conversation/timeline/state/timeline_view_state.dart';
import '../../features/conversation/timeline/state/timeline_ui_controllers.dart';
import '../../features/conversation/timeline/view_models/timeline_message_controller.dart';

export '../../features/conversation/timeline/state/timeline_view_state.dart';

const Object _unset = Object();

/// One presentation generation. It borrows the SDK content resource, owns its
/// loaded atomic references and UI resources, and never owns a second feed.
final class TimelineDisplayLease implements TimelineUiControllers {
  TimelineDisplayLease({
    required this.threadId,
    required this.generation,
    required this.timelineEpoch,
    required this.content,
  }) : _controller = InMemoryChatController(),
       imageResources = TimelineImageResources(threadId: threadId) {
    _presentation = TimelineMessageController(
      _controller,
      generation: generation,
      imageResources: imageResources,
    );
  }

  final String threadId;
  final int generation;
  final String timelineEpoch;
  final ConversationContent content;
  final TimelineImageResources imageResources;
  final InMemoryChatController _controller;
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );
  late final TimelineMessageController _presentation;
  final Completer<void> _released = Completer<void>();
  final ValueNotifier<bool> retirement = ValueNotifier(false);
  final Set<ConversationQueryScope> _ownedQueries = {};
  final Map<ConversationQueryScope, Future<void>> _closingQueries = {};
  ConversationQueryScope? _queries;
  ConversationQueryCursor? _before;
  ConversationCompletionCursor? _completedCursor;
  TimelineDisplayMode _mode = TimelineDisplayMode.live;
  bool _hasOlder = false;
  bool _mounted = false;
  bool _retired = false;
  bool _disposed = false;
  int _mutations = 0;
  Object? queryCleanupError;

  @override
  Key get chatKey => ValueKey('timeline-chat:$threadId:$generation');
  @override
  ChatController get controller => _controller;
  @override
  ScrollController get scrollController => _scrollController;
  @override
  bool get isRetired => _retired;
  bool get isMounted => _mounted;
  bool get isReleased => _released.isCompleted;
  TimelineDisplayMode get mode => _mode;
  ConversationCompletionCursor? get completedCursor => _completedCursor;
  String? get olderCursor => _before?.token;
  bool get hasOlder => _hasOlder;
  int get loadedCount => _presentation.length;
  Iterable<ConversationItem> get items => _presentation.items;
  Future<void> get released => _released.future;

  TimelineEntry? presentationFor(String itemId) =>
      _presentation.ownerOf(itemId);
  Listenable? memberObservation(String itemId) =>
      _presentation.memberObservation(itemId);
  ConversationItem? itemOf(String itemId) => _presentation.item(itemId);
  ConversationDetailRef? detailRef(
    String itemId,
    ThreadContentFieldView field,
  ) => itemOf(itemId)?.detailFor(field);

  ConversationQueryScope? get queries {
    if (_retired) return null;
    final existing = _queries;
    if (existing != null && existing.isActive) return existing;
    if (existing != null) unawaited(_settleQueries(existing));
    final scope = content.openScope(
      timelineEpoch: timelineEpoch,
      generation: generation,
    );
    _ownedQueries.add(scope);
    return _queries = scope;
  }

  ConversationQueryScope? openDetailQueries() {
    if (_retired) return null;
    final scope = content.openScope(
      timelineEpoch: timelineEpoch,
      generation: generation,
    );
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
    _controller.operationsStream.listen(
      (_) {},
      onDone: () {
        if (!_released.isCompleted) _released.complete();
      },
    );
    _presentation.dispose();
    imageResources.release();
    retirement.dispose();
    _controller.dispose();
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
    if (_bindingConsumer || !_selected(selection, session)) return;
    _bindingConsumer = true;
    try {
      final observation = session.content.attachConsumer(
        _TimelineConsumer(this, selection, session),
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
    ConversationContentFrame frame,
  ) => _serialize(() async {
    if (!_selected(selection, session)) return;
    switch (frame) {
      case ConversationBaselineFrame(:final baseline):
        if (_current != null) {
          throw const ConversationContinuityError(
            'Unexpected repeated baseline',
          );
        }
        await _baseline(selection, session, baseline);
      case ConversationResetFrame(:final baseline):
        await _baseline(selection, session, baseline);
      case ConversationCompletedBatchFrame(:final batch):
        final current = _current;
        final cursor = current?._completedCursor;
        if (current == null ||
            cursor == null ||
            batch.timelineEpoch != current.timelineEpoch ||
            batch.fromSeq != cursor.appendSeq) {
          throw const ConversationContinuityError(
            'Completion position mismatch',
          );
        }
        await current._mutate(() => current._presentation.append(batch.items));
        if (!_selected(selection, session) ||
            !identical(_current, current) ||
            current.isRetired) {
          return;
        }
        current._completedCursor = ConversationCompletionCursor(
          timelineEpoch: batch.timelineEpoch,
          appendSeq: batch.throughSeq,
        );
        _publishState(
          hasNewOutput: current.mode == TimelineDisplayMode.history,
        );
    }
  });

  Future<void> _baseline(
    int selection,
    ConversationSession session,
    ConversationBaseline baseline,
  ) async {
    final next = TimelineDisplayLease(
      threadId: session.threadId,
      generation: ++_generation,
      timelineEpoch: baseline.timelineEpoch,
      content: session.content,
    );
    _preparingDisplays.add(next);
    try {
      await next._mutate(() => next._presentation.initialize(baseline.items));
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
    next._before = baseline.before;
    next._hasOlder = baseline.hasOlder;
    next._completedCursor = baseline.completedCursor;
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
      final page = await scope.page(before: before);
      await _serialize(() async {
        if (!identical(_current, current) ||
            current.isRetired ||
            !scope.isActive) {
          return;
        }
        if (page.threadId != current.threadId ||
            page.timelineEpoch != current.timelineEpoch ||
            page.hasOlder && (page.before == null || page.before == before)) {
          throw const ConversationContinuityError(
            'History page did not advance',
          );
        }
        await current._mutate(() async {
          await current._presentation.prepend(page.items);
        });
        if (!identical(_current, current) || current.isRetired) return;
        // Advance by atoms, even when the complete page joined one existing group.
        current._before = page.before;
        current._hasOlder = page.hasOlder;
        _publishState(isLoadingOlder: false, olderError: null);
      });
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

final class _TimelineConsumer implements ConversationCompletionConsumer {
  const _TimelineConsumer(this.owner, this.selection, this.session);
  final TimelineSessionOwner owner;
  final int selection;
  final ConversationSession session;
  @override
  Future<void> accept(ConversationContentFrame frame) =>
      owner._accept(selection, session, frame);
}
