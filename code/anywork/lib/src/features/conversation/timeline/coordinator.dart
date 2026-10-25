import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import '../state/timeline_view_state.dart';
import '../view_models/timeline_actions.dart';
import 'display_binding.dart';
import 'display_lease.dart';
import 'presentation_work.dart';
import 'selection_binding.dart';

/// Application-instance owner. Widget/Provider disposal never closes it.
final class TimelineCoordinator implements TimelineActions {
  TimelineCoordinator({required ConversationRepository conversations}) {
    final watched = conversations.active.watchLatest(_select);
    _selectionObservation = watched.observation;
    _select(watched.value);
  }

  final StreamController<TimelineViewState?> _changes =
      StreamController<TimelineViewState?>.broadcast(sync: true);
  Observation? _selectionObservation;
  TimelineSelectionBinding? _binding;
  TimelineDisplayLease? _current;
  final Set<TimelineDisplayLease> _candidates = {};
  final Set<TimelineDisplayLease> _retiring = {};
  final Set<PresentationWork> _work = {};
  final Map<TimelineDisplayLease, Future<void>> _pages = {};
  PendingLiveSwitch? _pending;
  TimelineViewState? _value;
  String? _subscription;
  int _serial = 0;
  int _displayGeneration = 0;
  int _candidateEpoch = 0;
  bool _closed = false;
  Future<CloseReport>? _closing;
  Future<void>? _changesCompletion;
  Future<void>? _controllerClose;

  @override
  TimelineViewState? get value => _value;
  @override
  Stream<TimelineViewState?> get changes => _changes.stream;

  TimelineDisplayBinding? display(String threadId) =>
      _display(threadId)?.binding;

  TimelineDisplayLease? _display(String threadId) {
    final display = _current;
    return !_closed && display?.threadId == threadId ? display : null;
  }

  void _publish(TimelineViewState? value) {
    if (_closed || _value == value) return;
    _value = value;
    _changes.add(value);
  }

  bool _isCurrent(TimelineSelectionBinding binding) =>
      !_closed && !binding.retired && identical(_binding, binding);

  void _select(ConversationSession? session) {
    if (_closed || identical(_binding?.session, session)) return;
    final old = _binding;
    _binding = null;
    if (old != null) _detach(old);
    final previous = _current;
    _current = null;
    _subscription = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.result.isCompleted) {
      pending.result.completeError(const TimelineSelectionChanged());
    }
    if (previous != null) _retire(previous);
    if (session == null) {
      _publish(null);
      return;
    }
    final binding = TimelineSelectionBinding(session, ++_serial);
    _binding = binding;
    _publish(TimelineViewState(threadId: session.threadId));
    final watched = session.timeline.state.watchLatest(
      (next) => _connection(binding, next),
    );
    binding.observation = watched.observation;
    _connection(binding, watched.value);
    try {
      // Contract: attach returns before the first callback can reenter.
      binding.consumer = session.timeline.attachConsumer(
        (frame) => _accept(binding, frame),
      );
    } on StudioFailure catch (error) {
      _fail(binding, error);
    }
  }

  void _detach(TimelineSelectionBinding binding) {
    binding.retired = true;
    binding.observation?.cancel();
    binding.observation = null;
    final consumer = binding.consumer;
    binding.consumer = null;
    if (consumer == null) return;
    consumer.requestClose();
    // Every detach performs the real close and registers its own completion.
    // No shared ??= can skip a later consumer.
    _track(
      'timeline-consumer:${binding.serial}',
      binding.serial,
      Future<void>.sync(consumer.close),
    );
  }

  void _connection(
    TimelineSelectionBinding binding,
    TimelineConnectionState next,
  ) {
    if (!_isCurrent(binding)) return;
    final state = _value!;
    final failure = _connectionFailure(binding, next);
    _publish(
      state.copyWith(connectionPhase: next.phase, connectionError: failure),
    );
    if (next.phase == TimelineConnectionPhase.failed ||
        next.phase == TimelineConnectionPhase.closed) {
      _fail(binding, next.error ?? _connectionClosed, connectionError: failure);
    }
  }

  static const _connectionClosed = StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'The timeline connection closed',
    retryable: false,
    correlationId: 'timeline-connection-closed',
  );

  /// Typed failures keep their canonical [StudioFailure]; an unknown error keeps
  /// the original object borrowed from the same failed attempt, so diagnostics
  /// read its runtime type instead of a synthesized `internal` failure
  /// (design/26 §26.9). No `toString`, message or stack is read here.
  Object? _connectionFailure(
    TimelineSelectionBinding binding,
    TimelineConnectionState next,
  ) {
    final failure = next.error;
    if (failure == null) return null;
    final identity = binding.session.timeline.failure;
    if (identity == null || !identical(identity.failure, failure)) {
      return failure;
    }
    return identity.diagnosticError;
  }

  Future<void> _accept(
    TimelineSelectionBinding binding,
    StudioTimelineFrame frame,
  ) {
    if (!_isCurrent(binding)) return Future<void>.value();
    final done = Completer<void>();
    // Callback ownership exists before projection/candidate creation/first await.
    _track(
      'timeline-callback:${binding.serial}:${++_serial}',
      _serial,
      done.future,
    );
    Future<void>.sync(() => _consume(binding, frame)).then<void>(
      (_) => done.complete(),
      onError: (Object error, StackTrace stack) {
        if (_isCurrent(binding) && error is StudioFailure) {
          _fail(binding, error);
        }
        done.completeError(error, stack);
      },
    );
    done.future.ignore();
    return done.future;
  }

  Future<void> _consume(
    TimelineSelectionBinding binding,
    StudioTimelineFrame frame,
  ) async {
    switch (frame) {
      case StudioTimelineBaselineFrame(:final baseline):
        await _baseline(binding, baseline);
      case StudioTimelinePatchFrame(:final patch):
        final display = _current;
        if (display == null || !identical(display.session, binding.session)) {
          if (_isCurrent(binding)) binding.session.timeline.refresh();
          return;
        }
        if (display.content.mode == TimelineDisplayMode.history) {
          if (_isCurrent(binding) && _historyHasOutput(display, patch)) {
            _publish(_value!.copyWith(hasNewOutput: true));
          }
          return;
        }
        var continuous = true;
        await display.write(() {
          continuous = display.content.applyPatch(patch);
        });
        // A frame this generation cannot prove continuous is never half
        // applied: the same Session publishes a new authoritative baseline.
        if (!continuous && identical(_current, display)) {
          _resync(binding, _patchGap);
        }
    }
  }

  /// A frame or page this generation cannot prove continuous asks the original
  /// Session for an authoritative new baseline instead of guessing an
  /// incremental state (design/26 §26.5, §26.7).
  ///
  /// The current display stays until that baseline commits, so the retired
  /// generation keeps its last applied facts. The typed reason is carried by
  /// the published state rather than reported as a successful projection, and
  /// it is cleared by the new baseline that actually resolves it.
  void _resync(TimelineSelectionBinding binding, StudioFailure reason) {
    if (!_isCurrent(binding)) return;
    try {
      binding.session.timeline.refresh();
    } on StudioFailure catch (error) {
      _fail(binding, error);
      return;
    }
    if (!_isCurrent(binding)) return;
    _publish(_value!.copyWith(connectionError: reason));
  }

  static const _patchGap = StudioFailure(
    code: StudioFailureCode.protocol,
    message: 'The timeline patch is not continuous',
    retryable: true,
    correlationId: 'timeline-patch-gap',
  );

  static const _pageNotContinuous = StudioFailure(
    code: StudioFailureCode.protocol,
    message: 'The history page is not continuous',
    retryable: true,
    correlationId: 'timeline-page-not-continuous',
  );

  Future<void> _baseline(
    TimelineSelectionBinding binding,
    StudioTimelineBaseline baseline,
  ) async {
    if (!_isCurrent(binding)) return;
    final pending = _pending;
    if (pending != null &&
        identical(pending.binding, binding) &&
        baseline.subscriptionId == pending.previousSubscription) {
      return;
    }
    if (pending == null &&
        _current?.content.mode == TimelineDisplayMode.history) {
      _subscription = baseline.subscriptionId;
      _publish(_value!.copyWith(hasNewOutput: true));
      return;
    }
    final epoch = ++_candidateEpoch;
    binding.candidateEpoch = epoch;
    final consumer = binding.consumer;
    final candidate = TimelineDisplayLease(
      session: binding.session,
      generation: ++_displayGeneration,
    );
    _candidates.add(candidate);
    try {
      await candidate.write(() => candidate.content.adoptBaseline(baseline));
      if (!_isCurrent(binding) ||
          !identical(binding.consumer, consumer) ||
          binding.candidateEpoch != epoch ||
          _candidateEpoch != epoch ||
          !identical(_pending, pending)) {
        _retire(candidate);
        return;
      }
      final previous = _current;
      _current = candidate;
      _subscription = baseline.subscriptionId;
      _publish(
        _value!.copyWith(
          generation: candidate.generation,
          displayMode: TimelineDisplayMode.live,
          olderCursor: candidate.content.olderCursor,
          hasOlder: candidate.content.hasOlder,
          olderLoading: false,
          olderError: null,
          ready: true,
          hasNewOutput: false,
          preparingLive: false,
          connectionError: null,
        ),
      );
      if (previous != null) _retire(previous);
      if (pending != null && identical(_pending, pending)) {
        _pending = null;
        if (!pending.result.isCompleted) pending.result.complete();
      }
    } catch (_) {
      _retire(candidate);
      rethrow;
    } finally {
      _candidates.remove(candidate);
    }
  }

  /// [connectionError] is the object published as the state's current
  /// connection error when the typed [error] is only its projection.
  void _fail(
    TimelineSelectionBinding binding,
    StudioFailure error, {
    Object? connectionError,
  }) {
    if (!_isCurrent(binding)) return;
    _publish(
      _value!.copyWith(
        connectionError: connectionError ?? error,
        preparingLive: false,
      ),
    );
    final pending = _pending;
    if (pending != null && identical(pending.binding, binding)) {
      _pending = null;
      if (!pending.result.isCompleted) pending.result.completeError(error);
    }
  }

  @override
  void enterHistory(String threadId) {
    final current = _display(threadId);
    if (current == null || _value == null || _pending != null) return;
    current.content.enterHistory();
    _publish(
      _value!.copyWith(
        displayMode: TimelineDisplayMode.history,
        hasNewOutput: false,
      ),
    );
  }

  @override
  Future<void> returnLive(String threadId) {
    if (_closed) {
      return Future<void>.error(
        const StudioFailure(
          code: StudioFailureCode.cancelled,
          message: 'Timeline presentation is closing',
          retryable: false,
          correlationId: 'timeline-owner-closing',
        ),
      );
    }
    final binding = _binding;
    if (binding == null ||
        binding.session.threadId != threadId ||
        _display(threadId) == null) {
      return Future<void>.value();
    }
    final existing = _pending;
    if (existing != null) return existing.result.future;
    final pending = PendingLiveSwitch(binding, ++_serial, _subscription);
    pending.result.future.ignore();
    _pending = pending;
    // Revoke every older unpublished candidate as soon as this intent starts.
    binding.candidateEpoch = ++_candidateEpoch;
    _publish(_value!.copyWith(preparingLive: true));
    try {
      binding.session.timeline.refresh();
    } on StudioFailure catch (error) {
      _fail(binding, error);
    }
    return pending.result.future;
  }

  Future<void> prepareSend(ConversationSession session) async {
    if (_closed) {
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'Timeline presentation is closing',
        retryable: false,
        correlationId: 'timeline-send-closing',
      );
    }
    if (!identical(_binding?.session, session) ||
        _display(session.threadId) == null) {
      return;
    }
    try {
      await returnLive(session.threadId);
    } on TimelineSelectionChanged {
      // Only the display precondition ceased to apply; D1 keeps frozen target.
    }
  }

  @override
  Future<void> retryConnection(String threadId) async {
    final binding = _binding;
    if (binding == null ||
        !_isCurrent(binding) ||
        binding.session.threadId != threadId) {
      return;
    }
    binding.session.timeline.refresh();
  }

  @override
  Future<void> loadOlder(
    String threadId,
    int generation, {
    bool retry = false,
  }) {
    final current = _display(threadId);
    if (current == null || current.generation != generation) {
      return Future<void>.value();
    }
    final running = _pages[current];
    if (running != null) return running;
    final done = Completer<void>();
    _pages[current] = done.future;
    _track('timeline-page:$threadId:$generation', generation, done.future);
    Future<void>.sync(() => _loadPage(current, retry)).then<void>(
      (_) {
        _pages.remove(current);
        done.complete();
      },
      onError: (Object error, StackTrace stack) {
        _pages.remove(current);
        done.completeError(error, stack);
      },
    );
    done.future.ignore();
    return done.future;
  }

  Future<void> _loadPage(TimelineDisplayLease display, bool retry) async {
    bool current() =>
        !_closed && identical(_current, display) && !display.retired;
    final state = _value;
    if (!current() ||
        state == null ||
        !display.content.hasOlder ||
        state.preparingLive ||
        state.connectionPhase != TimelineConnectionPhase.ready ||
        (state.olderError != null && !retry)) {
      return;
    }
    final before = display.content.olderCursor;
    _publish(state.copyWith(olderLoading: true, olderError: null));
    try {
      final StudioTimelinePage page;
      try {
        if (!current()) return;
        // Scope admission can fail synchronously before acquiring a permit.
        // Those typed read failures are operation feedback, not cleanup debt.
        final scope = display.queries();
        if (scope == null) {
          if (!current()) return;
          throw display.session.timeline.state.value.error ??
              const StudioFailure(
                code: StudioFailureCode.unavailable,
                message: 'The history query scope is not available',
                retryable: true,
                correlationId: 'timeline-page-scope-unavailable',
              );
        }
        page = await scope.page(before: before);
        if (!current()) return;
        if (!scope.isActive) {
          throw display.session.timeline.state.value.error ??
              const StudioFailure(
                code: StudioFailureCode.cancelled,
                message: 'The original history query is no longer active',
                retryable: true,
                correlationId: 'timeline-page-scope-changed',
              );
        }
        if (page.hasOlder && (page.before == null || page.before == before)) {
          throw const StudioFailure(
            code: StudioFailureCode.protocol,
            message: 'The history cursor did not advance',
            retryable: true,
            correlationId: 'timeline-page-no-progress',
          );
        }
      } catch (error) {
        // Publish the diagnostic object as-is: a typed failure stays typed and an
        // unknown exception keeps its original identity/type for diagnostics.
        if (current()) {
          _publish(_value!.copyWith(olderLoading: false, olderError: error));
        }
        return;
      }

      // This boundary is deliberately outside the read-error catch. Real
      // controller write failures still reach the original supervised work;
      // scope close/join remains independently owned by this lease and D1.
      var continuous = false;
      await display.write(() {
        continuous = display.content.prependOlder(page) != null;
      });
      if (!current()) return;
      if (!continuous) {
        // A page that would let the cursor jump over an identity this
        // generation already knows cannot be merged; retry state alone would
        // keep claiming the older range is still reachable.
        _publish(
          _value!.copyWith(olderLoading: false, olderError: _pageNotContinuous),
        );
        final binding = _binding;
        if (binding != null) _resync(binding, _pageNotContinuous);
        return;
      }
      _publish(
        _value!.copyWith(
          olderCursor: display.content.olderCursor,
          hasOlder: display.content.hasOlder,
          olderLoading: false,
        ),
      );
    } finally {
      if (current() && _value?.olderLoading == true) {
        _publish(_value!.copyWith(olderLoading: false));
      }
    }
  }

  void _track(String owner, int attempt, Future<void> completion) {
    final work = PresentationWork(
      owner: owner,
      attempt: attempt,
      completion: completion,
    );
    _work.add(work);
    work.done.then((_) {
      if (work.unresolved == null) _work.remove(work);
    });
  }

  void _retire(TimelineDisplayLease lease) {
    if (!_retiring.add(lease)) return;
    lease.requestRetire();
    final completion = lease.close().then<void>((report) {
      if (report.complete) _retiring.remove(lease);
    });
    _track(
      'timeline-retire:${lease.threadId}:${lease.generation}',
      lease.generation,
      completion,
    );
  }

  Future<CloseReport> close({DateTime? deadline}) {
    if (!_closed) {
      _closed = true;
      _value = null;
      _closeChanges();
      _selectionObservation?.cancel();
      _selectionObservation = null;
      final binding = _binding;
      _binding = null;
      if (binding != null) _detach(binding);
      final pending = _pending;
      _pending = null;
      if (pending != null && !pending.result.isCompleted) {
        pending.result.completeError(
          const StudioFailure(
            code: StudioFailureCode.cancelled,
            message: 'Timeline presentation is closing',
            retryable: false,
            correlationId: 'timeline-close-preparation',
          ),
        );
      }
      final leases = {..._candidates, ..._retiring, ?_current};
      _current = null;
      // Router replacement and actual mount tokens, not Provider disposal, ACK.
      for (final lease in leases) {
        _retiring.add(lease);
        lease.requestRetire();
      }
    }
    return _observeClose(deadline, false);
  }

  void _closeChanges() {
    if (_changesCompletion != null) return;
    final done = Completer<void>();
    // Register before invoking any observation/retirement callback. A close
    // requested from inside a synchronous changes listener cannot reenter add/
    // close while that event is firing: final null and close run after unwind.
    _changesCompletion = done.future;
    _track('timeline-changes', ++_serial, done.future);
    scheduleMicrotask(() {
      try {
        _changes.add(null);
      } catch (error, stack) {
        // A failed final notification must not skip the independent real close.
        _track(
          'timeline-final-change',
          ++_serial,
          Future<void>.error(error, stack),
        );
      }
      try {
        final original = _controllerClose ??= _changes.close();
        original.then<void>(
          (_) => done.complete(),
          onError: (Object error, StackTrace stack) {
            done.completeError(error, stack);
          },
        );
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    });
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) {
    if (!_closed) return close(deadline: deadline);
    return _observeClose(deadline, true);
  }

  Future<CloseReport> _observeClose(DateTime? deadline, bool retry) {
    final running = _closing;
    if (running != null) return running;
    final task = _join(deadline, retry);
    _closing = task;
    task.whenComplete(() {
      if (identical(_closing, task)) _closing = null;
    }).ignore();
    return task;
  }

  Future<CloseReport> _join(DateTime? deadline, bool retry) async {
    final leases = {..._retiring, ..._candidates};
    final closes = [
      for (final lease in leases) lease.close(deadline: deadline, retry: retry),
    ];
    await observePresentationCompletion([
      for (final item in _work) item.done,
      for (final close in closes) close.then<void>((_) {}),
    ], deadline);
    final unresolved = [
      for (final work in _work) ?work.unresolved,
      for (final lease in leases) ...lease.report.unresolved,
    ];
    _retiring.removeWhere((lease) => lease.report.complete);
    return CloseReport(unresolved: unresolved);
  }
}

bool _historyHasOutput(
  TimelineDisplayLease display,
  StudioTimelinePatch patch,
) {
  for (final change in patch.changes) {
    switch (change) {
      case StudioTimelineAdd() || StudioTimelineRemove():
        return true;
      case StudioTimelineUpdateItem():
        final previous = display.content.payloadOf(change.itemId);
        if (previous == null ||
            change.revision != change.expectedRevision ||
            (change.lifecycle == StudioTimelineLifecycle.terminal &&
                !previous.terminal)) {
          return true;
        }
        for (final field in change.fields) {
          if (field.change is! UnchangedThreadFieldChangeView ||
              previous.detailFor(field.field)?.totalBytes != field.totalBytes) {
            return true;
          }
        }
    }
  }
  return false;
}
