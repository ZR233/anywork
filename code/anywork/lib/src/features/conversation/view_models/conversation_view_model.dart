import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/conversation_view_state.dart';
import '../state/editor_keys.dart';
import 'session_facet_observer.dart';

part 'conversation_view_model.g.dart';

/// Future.any keeps an error handler on the loser; it does not cancel or join
/// SDK work. This adapter captures no VM, Session or source binding.
Future<CommandResult<Unit>?> _observeStopResult(
  Future<CommandResult<Unit>> result,
  Future<void> retired,
) => Future.any<CommandResult<Unit>?>([
  result,
  retired.then<CommandResult<Unit>?>((_) => null),
]);

/// A Smart page's presentation permission, not a Session or operation owner.
final class ConversationStopPage {
  ConversationStopPage({required this._isCurrent});
  final bool Function() _isCurrent;
  bool _retired = false;
  bool get isCurrent => !_retired && _isCurrent();
  void retire() {
    _retired = true;
  }
}

final class _StopContext {
  _StopContext({
    required this.intent,
    required this.binding,
    required this.origin,
    required this.target,
  });
  final int intent;
  final SessionFacetCapture<ThreadExecutionState> binding;
  final ThreadFacetStamp origin;
  final TurnReadRef target;
  OperationTicket<Unit>? ticket;
  OperationState? operation;
  CommandResult<Unit>? result;
  StudioFailure? localError;
  StudioFailure? observationError;
  Object? cause;
  StackTrace? causeStack;
  Observation? observation;
  ConversationStopPage? observedPage;
  int watchGeneration = 0;
  bool sourceRetired = false;

  ConversationStopState get value => ConversationStopState(
    intent: intent,
    origin: origin,
    target: target,
    operation: operation,
    result: result,
    localError: localError,
    observationError: observationError,
  );
}

typedef _PresentationCleanupIssue = ({
  String stage,
  Object owner,
  Object cause,
  StackTrace? stack,
});

/// Unexpected local cleanup faults and the original metadata close report.
/// This is diagnostic evidence, not another resource owner or an exit receipt.
final class _PresentationCleanupFailure implements Exception {
  _PresentationCleanupFailure(List<_PresentationCleanupIssue> issues)
    : issues = List.unmodifiable(issues);
  final List<_PresentationCleanupIssue> issues;
  @override
  String toString() =>
      'Conversation presentation cleanup: ${issues.map((issue) => '${issue.stage} (${issue.cause.runtimeType})').join(', ')}';
}

// Observe native cleanup diagnostics without retaining the disposed VM's
// closure context. The Workspace still owns the actual metadata close.
Future<void> _observePresentationClose(
  Future<CloseReport>? closing,
  ThreadMetadata metadata,
  List<_PresentationCleanupIssue> issues,
  Zone zone,
) async {
  if (closing != null) {
    try {
      final report = await closing;
      if (!report.complete) {
        issues.add((
          stage: 'metadata-close-report',
          owner: metadata,
          cause: report,
          stack: null,
        ));
      }
    } catch (error, stack) {
      issues.add((
        stage: 'metadata-close',
        owner: metadata,
        cause: error,
        stack: stack,
      ));
    }
  }
  if (issues.isNotEmpty) {
    zone.handleUncaughtError(
      _PresentationCleanupFailure(issues),
      issues.map((issue) => issue.stack).whereType<StackTrace>().firstOrNull ??
          StackTrace.current,
    );
  }
}

@riverpod
class ConversationViewModel extends _$ConversationViewModel {
  late ThreadMetadata _metadata;
  Observation? _metadataObservation;
  late SessionFacetObserver<InteractionIndexReadState> _index;
  late SessionFacetObserver<ThreadExecutionState> _execution;
  final Set<ConversationSession> _initialIndexReads =
      Set<ConversationSession>.identity();
  final Set<InteractionEditorKey> _dismissed = {};
  final Map<ConversationSession, Future<void>> _loadingIndex =
      Map<ConversationSession, Future<void>>.identity();
  final Set<InteractionEditorKey> _dirtyEditors = {};
  KeepAliveLink? _editing;
  int _indexBinding = 0;
  late ComposerKey composerTarget;
  Object _stopLifetime = Object();
  late Completer<void> _stopDisposed;
  ConversationStopPage? _stopPage;
  _StopContext? _stop;
  int _stopIntent = 0;
  bool _stopBoundary = false;
  bool _stopSyncScheduled = false;

  @override
  FutureOr<ConversationViewState> build(String threadId) {
    final lifetime = _stopLifetime = Object();
    final disposed = _stopDisposed = Completer<void>();
    _stopSyncScheduled = false;
    _stopPage = null;
    if (_stop case final previous?) previous.sourceRetired = true;
    composerTarget = ComposerKey.thread(threadId: threadId);
    final repository = ref.read(conversationRepositoryProvider);
    _metadata = ref.read(workspaceRepositoryProvider).thread(threadId);
    final metadata = _metadata.state.watchLatest((value) {
      if (ref.mounted && state.hasValue) {
        state = AsyncData(state.requireValue.copyWith(metadata: value));
      }
    });
    _metadataObservation = metadata.observation;
    _index = SessionFacetObserver<InteractionIndexReadState>(
      repository: repository,
      threadId: threadId,
      source: (session) => session.interactions,
      onValue: _indexChanged,
    );
    _execution = SessionFacetObserver<ThreadExecutionState>(
      repository: repository,
      threadId: threadId,
      source: (session) => session.execution,
      onBindingInvalidated: _scheduleStopSync,
      onValue: (value) {
        _checkStopSource();
        if (ref.mounted && state.hasValue) {
          state = AsyncData(
            _mergeIndex(
              state.requireValue.copyWith(execution: value),
              _index.value,
            ),
          );
        }
        _scheduleStopSync();
      },
    );
    _indexBinding = _index.generation;
    final metadataOwner = _metadata;
    final metadataWatch = _metadataObservation;
    final indexOwner = _index;
    final executionOwner = _execution;
    ref.onDispose(() {
      if (!disposed.isCompleted) disposed.complete();
      _StopContext? stop;
      if (identical(_stopLifetime, lifetime)) {
        _stopLifetime = Object();
        _stopPage?.retire();
        _stopPage = null;
        stop = _stop;
      }
      _disposePresentation(
        stop,
        metadataOwner,
        metadataWatch,
        indexOwner,
        executionOwner,
      );
    });
    scheduleMicrotask(_ensureInitialIndexRead);
    return _mergeIndex(
      ConversationViewState(
        threadId: threadId,
        metadata: metadata.value,
        execution: _execution.value,
        interactions: _index.value,
      ),
      _index.value,
    );
  }

  void _indexChanged(InteractionIndexReadState value) {
    if (!ref.mounted || !state.hasValue) return;
    final changed = _indexBinding != _index.generation;
    _indexBinding = _index.generation;
    final session = _index.session;
    state = AsyncData(
      _mergeIndex(
        state.requireValue.copyWith(
          indexLoading: session != null && _loadingIndex.containsKey(session),
          indexError: changed ? null : state.requireValue.indexError,
        ),
        value,
      ),
    );
    _ensureInitialIndexRead();
  }

  ConversationViewState _mergeIndex(
    ConversationViewState before,
    InteractionIndexReadState? value,
  ) {
    final current = <InteractionEditorKey>{};
    final snapshot = value?.current;
    final execution = before.execution;
    if (snapshot != null &&
        value?.error == null &&
        identical(_execution.session, _index.session) &&
        execution?.sync.phase == FacetSyncPhase.ready &&
        execution?.stamp?.runtimeEpoch == snapshot.origin.runtimeEpoch &&
        execution?.stamp?.incarnation == snapshot.origin.incarnation &&
        execution?.value?.interactions.reference == snapshot.index.reference) {
      for (final item in snapshot.items) {
        if (item.status != InteractionStatus.pending) continue;
        current.add(
          InteractionEditorKey(
            threadId: before.threadId,
            incarnation: snapshot.origin.incarnation,
            interactionId: item.interactionId,
            revision: item.revision,
          ),
        );
      }
    }
    // These are UI editor identities, never copied interaction bodies or a
    // second index reducer. Removal/unknown/revision change keeps the old raw
    // editor visible but disabled until the user explicitly closes that editor.
    return before.copyWith(
      interactions: value,
      currentEditors: current,
      visibleEditors: [
        ...before.visibleEditors,
        for (final key in current)
          if (!before.visibleEditors.contains(key) && !_dismissed.contains(key))
            key,
      ],
    );
  }

  void _ensureInitialIndexRead() {
    if (!ref.mounted) return;
    final session = _index.session;
    if (session != null && _initialIndexReads.add(session)) {
      loadInteractions().ignore();
    }
  }

  Future<void> loadInteractions() {
    final session = _index.session;
    if (session == null || !ref.mounted || !state.hasValue) {
      return Future<void>.value();
    }
    final running = _loadingIndex[session];
    if (running != null) return running;
    final done = Completer<void>();
    _loadingIndex[session] = done.future;
    state = AsyncData(
      state.requireValue.copyWith(indexLoading: true, indexError: null),
    );
    Future<void>(() async {
      try {
        await session.loadInteractionsPage();
      } on StudioFailure catch (error) {
        if (ref.mounted && identical(_index.session, session)) {
          state = AsyncData(state.requireValue.copyWith(indexError: error));
        }
      } catch (_) {
        if (ref.mounted && identical(_index.session, session)) {
          state = AsyncData(
            state.requireValue.copyWith(
              indexError: const StudioFailure(
                code: StudioFailureCode.internal,
                message: 'The interaction index could not be read',
                retryable: false,
                correlationId: 'conversation-interaction-index-internal',
              ),
            ),
          );
        }
      } finally {
        if (ref.mounted && identical(_index.session, session)) {
          state = AsyncData(state.requireValue.copyWith(indexLoading: false));
        }
        if (identical(_loadingIndex[session], done.future)) {
          _loadingIndex.remove(session);
        }
        done.complete();
      }
    });
    return done.future;
  }

  void closeEditor(InteractionEditorKey key) {
    setEditorDirty(key, false);
    _dismissed.add(key);
    final before = state.requireValue;
    state = AsyncData(
      before.copyWith(
        visibleEditors: [
          for (final existing in before.visibleEditors)
            if (existing != key) existing,
        ],
      ),
    );
  }

  /// Keep only editor identities across Settings/navigation while their unique
  /// Interaction VM retains raw. No answer, secret, scope or operation is copied.
  void setEditorDirty(InteractionEditorKey key, bool dirty) {
    if (dirty) {
      _dirtyEditors.add(key);
      _editing ??= ref.keepAlive();
    } else {
      _dirtyEditors.remove(key);
      if (_dirtyEditors.isEmpty) {
        _editing?.close();
        _editing = null;
      }
    }
  }

  void reopenCurrentEditors() {
    _dismissed.removeAll(state.requireValue.currentEditors);
    state = AsyncData(_mergeIndex(state.requireValue, _index.value));
  }

  Future<void> retryMetadata() => _metadata.retry();

  void _disposePresentation(
    _StopContext? stop,
    ThreadMetadata metadata,
    Observation? metadataWatch,
    SessionFacetObserver<InteractionIndexReadState> index,
    SessionFacetObserver<ThreadExecutionState> execution,
  ) {
    final issues = <_PresentationCleanupIssue>[];
    void attempt(String stage, Object owner, void Function() release) {
      try {
        release();
      } catch (error, stack) {
        issues.add((stage: stage, owner: owner, cause: error, stack: stack));
      }
    }

    if (stop != null) {
      attempt('stop-observation', stop, () {
        if (!_releaseStopObservation(stop)) {
          Error.throwWithStackTrace(stop.cause!, stop.causeStack!);
        }
      });
    }
    if (metadataWatch != null) {
      attempt('metadata-observation', metadataWatch, () {
        metadataWatch.cancel();
        if (identical(_metadataObservation, metadataWatch)) {
          _metadataObservation = null;
        }
      });
    }
    attempt('interaction-observations', index, index.cancel);
    attempt('execution-observations', execution, execution.cancel);
    attempt('metadata-request-close', metadata, metadata.requestClose);
    Future<CloseReport>? closing;
    attempt('metadata-close', metadata, () {
      closing = metadata.close();
    });
    final zone = Zone.current;
    // D3, not this disposed VM, retains native metadata handles/permits and
    // exposes unresolved cleanup through Workspace.close/retryCleanup. Observe
    // this original result without suppressing errors or claiming it was Clean.
    // All independent cleanup was attempted before the diagnostic callback,
    // which itself may reenter. No Session is closed and no command retried.
    unawaited(_observePresentationClose(closing, metadata, issues, zone));
  }

  /// Safe from widget lifecycle/build: retirement is synchronous, observation
  /// callbacks and Provider publication run only after this stack has returned.
  void deferStopPage(ConversationStopPage page) {
    if (page.isCurrent) {
      _stopPage = page;
    } else if (identical(_stopPage, page)) {
      _stopPage = null;
    }
    _scheduleStopSync();
  }

  Future<void> Function()? captureStop(ConversationStopPage page) {
    if (!ref.mounted || !page.isCurrent || _stopBoundary) return null;
    final binding = _execution.capture();
    if (binding == null || !_execution.matches(binding, requireActive: true)) {
      return null;
    }
    final current = binding.source.value;
    final origin = current.stamp;
    final turn = current.value?.activeTurn;
    if (!_stopReady(current) ||
        origin == null ||
        turn == null ||
        _blocksStop(binding, origin, turn.reference.entry)) {
      return null;
    }
    final lifetime = _stopLifetime;
    // The control binds an entry. Its click freezes the then-current revision
    // from this source only; it cannot borrow another Session with the same ID.
    return () =>
        _admitStop(page, lifetime, binding, origin, turn.reference.entry);
  }

  /// Guards the pure projection too: deferred publication must not flash an old
  /// source's result while a replacement source is already being rendered.
  ConversationStopState? stopStateFor(ConversationStopPage page) {
    final stop = _stop;
    if (!ref.mounted ||
        !page.isCurrent ||
        stop == null ||
        stop.sourceRetired ||
        !_execution.matches(stop.binding, requireActive: true)) {
      return null;
    }
    final stamp = stop.binding.source.value.stamp;
    if (stamp != null && !_sameStopOrigin(stamp, stop.origin)) return null;
    final value = state.asData?.value.stop;
    return value?.intent == stop.intent ? value : null;
  }

  bool _stopReady(ThreadExecutionState value) =>
      value.sync.phase == FacetSyncPhase.ready &&
      value.stamp?.facet == ThreadFacet.execution &&
      (value.value?.activeTurn?.state is QueuedTurnBrief ||
          value.value?.activeTurn?.state is RunningTurnBrief);

  bool _sameStopOrigin(ThreadFacetStamp left, ThreadFacetStamp right) =>
      left.runtimeEpoch == right.runtimeEpoch &&
      left.incarnation == right.incarnation &&
      left.facet == right.facet;

  bool _blocksStop(
    SessionFacetCapture<ThreadExecutionState> binding,
    ThreadFacetStamp origin,
    int entry,
  ) {
    final stop = _stop;
    return stop != null &&
        !stop.sourceRetired &&
        identical(stop.binding.session, binding.session) &&
        identical(stop.binding.source, binding.source) &&
        stop.binding.generation == binding.generation &&
        _sameStopOrigin(stop.origin, origin) &&
        stop.target.entry == entry &&
        stop.value.pending;
  }

  void _checkStopSource() {
    final stop = _stop;
    if (stop == null || stop.sourceRetired) return;
    final stamp = stop.binding.source.value.stamp;
    if (!_execution.matches(stop.binding, requireActive: true) ||
        stamp != null && !_sameStopOrigin(stamp, stop.origin)) {
      stop.sourceRetired = true;
    }
  }

  Future<void> _admitStop(
    ConversationStopPage page,
    Object lifetime,
    SessionFacetCapture<ThreadExecutionState> binding,
    ThreadFacetStamp shownOrigin,
    int entry,
  ) {
    if (!ref.mounted ||
        !identical(_stopLifetime, lifetime) ||
        !page.isCurrent ||
        _stopBoundary ||
        !_execution.matches(binding, requireActive: true)) {
      return Future<void>.value();
    }
    final current = binding.source.value;
    final origin = current.stamp;
    final target = current.value?.activeTurn?.reference;
    if (!_stopReady(current) ||
        origin == null ||
        target == null ||
        target.entry != entry ||
        !_sameStopOrigin(origin, shownOrigin) ||
        _blocksStop(binding, origin, entry)) {
      return Future<void>.value();
    }
    final retired = _stopDisposed.future;
    _stopBoundary = true;
    try {
      final previous = _stop;
      if (previous != null && !_releaseStopObservation(previous)) {
        return Future<void>.value();
      }
      // Recheck after cancellation: an observer may synchronously change the page/source.
      if (!page.isCurrent ||
          !_execution.matches(binding, requireActive: true) ||
          !identical(_stopLifetime, lifetime)) {
        return Future<void>.value();
      }
      final admitted = binding.source.value;
      final admittedOrigin = admitted.stamp;
      final admittedTarget = admitted.value?.activeTurn?.reference;
      if (!_stopReady(admitted) ||
          admittedOrigin == null ||
          admittedTarget == null ||
          admittedTarget.entry != entry ||
          !_sameStopOrigin(admittedOrigin, shownOrigin)) {
        return Future<void>.value();
      }
      final stop = _StopContext(
        intent: ++_stopIntent,
        binding: binding,
        origin: admittedOrigin,
        target: admittedTarget,
      );
      _stop = stop;
      _stopPage = page;
      try {
        stop.ticket = binding.session.stopTurn(
          origin: admittedOrigin,
          target: admittedTarget,
        );
      } catch (error, stack) {
        stop.cause = error;
        stop.causeStack = stack;
        // A UI call failure does not prove that native rejected the command.
        stop.localError = _stopFailure(error, 'conversation-stop-call');
        return Future<void>.value();
      }
      return _settleStop(stop, lifetime, retired);
    } finally {
      _stopBoundary = false;
      _scheduleStopSync();
    }
  }

  Future<void> _settleStop(
    _StopContext stop,
    Object lifetime,
    Future<void> retired,
  ) async {
    try {
      final result = await _observeStopResult(stop.ticket!.result, retired);
      if (result == null) return;
      stop.result = result;
    } catch (error, stack) {
      stop.cause = error;
      stop.causeStack = stack;
      stop.observationError = _stopFailure(error, 'conversation-stop-result');
    }
    if (ref.mounted &&
        identical(_stopLifetime, lifetime) &&
        identical(_stop, stop)) {
      _scheduleStopSync();
    }
    // Result settlement is not Effective. Keep the original ticket observation.
  }

  StudioFailure _stopFailure(Object error, String correlationId) =>
      error is StudioFailure
      ? error
      : StudioFailure(
          code: StudioFailureCode.internal,
          message: 'The stop operation could not be presented',
          retryable: false,
          correlationId: correlationId,
        );

  bool _releaseStopObservation(_StopContext stop) {
    stop.watchGeneration++;
    final observation = stop.observation;
    if (observation == null) return true;
    try {
      observation.cancel();
      stop.observation = null;
      stop.observedPage = null;
      return true;
    } catch (error, stack) {
      stop.cause = error;
      stop.causeStack = stack;
      stop.observationError = _stopFailure(
        error,
        'conversation-stop-observation-close',
      );
      return false; // Keep the actual handle; never register a replacement over it.
    }
  }

  void _scheduleStopSync() {
    if (!ref.mounted || _stopSyncScheduled) return;
    _stopSyncScheduled = true;
    final lifetime = _stopLifetime;
    unawaited(
      Future<void>(() {
        if (!ref.mounted || !identical(_stopLifetime, lifetime)) return;
        _stopSyncScheduled = false;
        _syncStopPage(lifetime);
      }),
    );
  }

  void _syncStopPage(Object lifetime) {
    if (!state.hasValue) return;
    _checkStopSource();
    final page = _stopPage;
    final visible = page != null && page.isCurrent;
    final stop = _stop;
    _stopBoundary = true;
    try {
      if (stop != null) {
        final observe = visible && !stop.sourceRetired && stop.ticket != null;
        if (!observe || !identical(stop.observedPage, page)) {
          if (!_releaseStopObservation(stop)) {
            _publishStop(page);
            return;
          }
        }
        if (observe && stop.observation == null) {
          final generation = ++stop.watchGeneration;
          var delivered = false;
          try {
            final watch = stop.ticket!.state.watchLatest((value) {
              if (!identical(_stopLifetime, lifetime) ||
                  stop.watchGeneration != generation) {
                return;
              }
              delivered = true;
              stop.operation = value;
              _scheduleStopSync();
            });
            stop.observation = watch.observation;
            stop.observedPage = page;
            if (!delivered) stop.operation = watch.value;
            if (!ref.mounted ||
                !identical(_stopLifetime, lifetime) ||
                !identical(_stop, stop) ||
                page.isCurrent != true ||
                !identical(_stopPage, page) ||
                stop.sourceRetired) {
              _releaseStopObservation(stop);
            }
          } catch (error, stack) {
            stop.cause = error;
            stop.causeStack = stack;
            stop.observationError = _stopFailure(
              error,
              'conversation-stop-observation',
            );
            // No resubscription loop or command retry is scheduled on this failure.
          }
        }
      }
      _publishStop(page);
    } finally {
      _stopBoundary = false;
    }
  }

  void _publishStop(ConversationStopPage? page) {
    if (!ref.mounted ||
        !state.hasValue ||
        page?.isCurrent != true ||
        !identical(_stopPage, page)) {
      return;
    }
    final capture = _execution.capture();
    final current =
        capture != null &&
        _execution.matches(capture, requireActive: true) &&
        capture.source.value.sync.phase == FacetSyncPhase.ready &&
        capture.source.value.stamp != null;
    final before = state.requireValue;
    final next = before.copyWith(
      stopSourceCurrent: current,
      stop: _stop?.sourceRetired == false ? _stop!.value : null,
    );
    if (next != before) state = AsyncData(next);
  }
}
