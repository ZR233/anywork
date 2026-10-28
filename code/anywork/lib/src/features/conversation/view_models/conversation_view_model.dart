import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/composer_primary_action.dart';
import '../state/conversation_view_state.dart';
import '../state/editor_keys.dart';
import 'session_facet_observer.dart';

part 'conversation_view_model.g.dart';

/// Future.any keeps an error handler on the loser; it does not cancel or join
/// SDK work. This adapter captures no VM, Session or source binding.
Future<CommandResult<T>?> _observeControlResult<T>(
  Future<CommandResult<T>> result,
  Future<void> retired,
) => Future.any<CommandResult<T>?>([
  result,
  retired.then<CommandResult<T>?>((_) => null),
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
  final String target;
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
    executionId: target,
    operation: operation,
    result: result,
    localError: localError,
    observationError: observationError,
  );
}

final class _ContinuationContext {
  _ContinuationContext({
    required this.binding,
    required this.value,
    required this.keepAlive,
  });
  final SessionFacetCapture<ThreadExecutionState> binding;
  final KeepAliveLink keepAlive;
  ConversationContinuationState value;
  OperationTicket<ContinueThreadReply>? ticket;
  Observation? observation;
  Future<void>? work;
  Future<void>? reading;
  bool sourceRetired = false;
  Object? cause;
  StackTrace? causeStack;
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
  late SessionFacetObserver<ThreadConfigurationState> _configuration;
  Observation? _recoveryObservation;
  RecoveryState? _recovery;
  _ContinuationContext? _continuation;
  int _continuationIntent = 0;
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
        state = AsyncData(
          _mergeIndex(
            state.requireValue.copyWith(metadata: value),
            _index.value,
          ),
        );
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
    _configuration = SessionFacetObserver<ThreadConfigurationState>(
      repository: repository,
      threadId: threadId,
      source: (session) => session.configuration,
      onValue: (value) {
        if (ref.mounted && state.hasValue) {
          state = AsyncData(state.requireValue.copyWith(configuration: value));
        }
      },
    );
    final recovery = ref.read(recoveryRepositoryProvider).state.watchLatest((
      value,
    ) {
      _recovery = value;
      if (ref.mounted && state.hasValue) {
        state = AsyncData(
          state.requireValue.copyWith(
            workspaceBlocker: _workspaceBlocker(state.requireValue.thread),
          ),
        );
      }
    });
    _recoveryObservation = recovery.observation;
    _recovery = recovery.value;
    _indexBinding = _index.generation;
    final metadataOwner = _metadata;
    final metadataWatch = _metadataObservation;
    final indexOwner = _index;
    final executionOwner = _execution;
    final configurationOwner = _configuration;
    final recoveryWatch = _recoveryObservation;
    ref.onDispose(() {
      if (!disposed.isCompleted) disposed.complete();
      _StopContext? stop;
      _ContinuationContext? continuation;
      if (identical(_stopLifetime, lifetime)) {
        _stopLifetime = Object();
        _stopPage?.retire();
        _stopPage = null;
        stop = _stop;
        continuation = _continuation;
        _continuation = null;
      }
      _disposePresentation(
        stop,
        metadataOwner,
        metadataWatch,
        indexOwner,
        executionOwner,
        configurationOwner,
        recoveryWatch,
        continuation,
      );
      // Only this presentation observation ends; the Session joins the command.
    });
    scheduleMicrotask(_ensureInitialIndexRead);
    return _mergeIndex(
      ConversationViewState(
        threadId: threadId,
        metadata: metadata.value,
        execution: _execution.value,
        configuration: _configuration.value,
        acceptsUserInput: _execution.session?.acceptsUserInput == true,
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
        _index.session?.acceptsUserInput == true &&
        !before.runtimeDriven &&
        value?.error == null &&
        identical(_execution.session, _index.session) &&
        execution?.sync.phase == FacetSyncPhase.ready &&
        execution?.stamp?.runtimeEpoch == snapshot.origin.runtimeEpoch &&
        execution?.stamp?.incarnation == snapshot.origin.incarnation &&
        execution?.value?.interactions.reference == snapshot.index.reference) {
      for (final item in snapshot.items) {
        if (item.status != InteractionStatus.pending) continue;
        final hosted = item.targetThreadId != before.threadId;
        final existing = before.visibleEditors
            .where(
              (key) =>
                  key.threadId == before.threadId &&
                  key.target == item.targetThreadId &&
                  key.runtimeEpoch == snapshot.origin.runtimeEpoch &&
                  key.incarnation == snapshot.origin.incarnation &&
                  key.sourceGeneration == _index.generation &&
                  key.interactionId == item.interactionId &&
                  key.revision == item.revision &&
                  (!hosted ||
                      key.hostedReference == item.reference &&
                          key.hostedOrigin?.runtimeEpoch ==
                              snapshot.origin.runtimeEpoch),
            )
            .firstOrNull;
        current.add(
          existing ??
              InteractionEditorKey(
                threadId: before.threadId,
                runtimeEpoch: snapshot.origin.runtimeEpoch,
                incarnation: snapshot.origin.incarnation,
                sourceGeneration: _index.generation,
                interactionId: item.interactionId,
                revision: item.revision,
                targetThreadId: hosted ? item.targetThreadId : null,
                hostedReference: hosted ? item.reference : null,
                hostedOrigin: hosted ? snapshot.origin : null,
              ),
        );
      }
    }
    // These are UI editor identities, never copied interaction bodies or a
    // second index reducer. Removal/unknown/revision change keeps the old raw
    // editor visible but disabled until the user explicitly closes that editor.
    return before.copyWith(
      acceptsUserInput: _execution.session?.acceptsUserInput == true,
      workspaceBlocker: _workspaceBlocker(before.thread),
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

  ComposerBlocker? _workspaceBlocker(WorkspaceThreadRecord? thread) {
    final issues = _recovery?.issues;
    if (issues is! CurrentCollectionMirror<RecoveryIssue>) return null;
    for (final row in issues.window.rows.values) {
      if (row is! ReadyReadValue<RecoveryIssue, ProductEntityRef>) continue;
      final issue = row.current.value;
      if (issue.blocksAccess &&
          (issue.scope == RecoveryScope.application ||
              issue.threadId == thread?.id && issue.threadId != null ||
              issue.scope == RecoveryScope.project &&
                  issue.projectId != null &&
                  issue.projectId == thread?.projectId)) {
        return const ComposerWorkspaceBlocker();
      }
    }
    return null;
  }

  /// The same pure decision is used by the connector and synchronous command
  /// admission. Local pending disables duplicates without inventing acceptance.
  ComposerPrimaryAction primaryAction({
    required bool hasContent,
    required bool submissionPending,
  }) {
    final view = state.asData?.value;
    if (view == null) {
      return const ComposerPrimaryAction(
        kind: ComposerPrimaryActionKind.send,
        enabled: false,
      );
    }
    final baseline = view.execution?.value;
    final binding = _execution.capture();
    final ready =
        binding != null &&
        _execution.matches(binding, requireActive: true) &&
        binding.source.value.sync.phase == FacetSyncPhase.ready &&
        binding.session.acceptsUserInput;
    final stop = _stop;
    final stopCurrent =
        stop != null &&
        !stop.sourceRetired &&
        _execution.matches(stop.binding) &&
        _sameStopOrigin(view.execution?.stamp ?? stop.origin, stop.origin);
    final continuation = _continuation;
    final continueCurrent =
        continuation != null && _continuationCurrent(continuation);
    final stopValue = stopCurrent ? stop.value : null;
    final continuationValue = continueCurrent ? continuation.value : null;
    final storage = baseline?.storage;
    final route = view.configuration?.value?.modelRoute;
    final configurationReady =
        _configuration.session == _execution.session &&
        view.configuration?.sync.phase == FacetSyncPhase.ready &&
        view.configuration?.stamp?.runtimeEpoch ==
            view.execution?.stamp?.runtimeEpoch &&
        view.configuration?.stamp?.incarnation ==
            view.execution?.stamp?.incarnation &&
        route != null;
    final ComposerBlocker? blocker =
        storage != null &&
            (storage.fault != null ||
                storage.resumeRequired ||
                storage.pressurePaused)
        ? const ComposerStorageBlocker()
        : view.workspaceBlocker ??
              (route?.available == false ? const ComposerModelBlocker() : null);
    final action = ComposerPrimaryAction.resolve(
      isChild: view.runtimeDriven,
      execution: baseline?.execution,
      continuation: baseline?.continuation,
      hasContent: hasContent,
      submissionPending: submissionPending,
      stopAccepted:
          stopValue?.accepted == true &&
          (baseline?.execution == null
              ? stopValue?.operation?.observed != true
              : baseline?.execution?.id == stopValue?.executionId),
      stopPending:
          stopCurrent &&
          baseline?.execution?.id == stopValue?.executionId &&
          (stopValue?.pending == true || stopValue?.unknown == true),
      continuationAccepted: continuationValue?.inProgress == true,
      continuationPending:
          continueCurrent &&
          (baseline?.continuation == null ||
              baseline?.continuation?.id ==
                  continuationValue?.continuationId) &&
          (continuationValue?.pending == true ||
              continuationValue?.unknown == true),
      blocker: blocker,
    );
    return action.copyWith(
      enabled:
          action.enabled &&
          ready &&
          (action.kind == ComposerPrimaryActionKind.stop ||
              view.canCompose && configurationReady),
    );
  }

  Future<void> Function()? captureContinuation() {
    if (!ref.mounted || !state.hasValue) return null;
    final page = _stopPage;
    final binding = _execution.capture();
    final configuration = _configuration.capture();
    if (page?.isCurrent != true ||
        binding == null ||
        configuration == null ||
        !_execution.matches(binding, requireActive: true) ||
        !identical(binding.session, configuration.session)) {
      return null;
    }
    final current = binding.source.value;
    final origin = current.stamp;
    final point = current.value?.continuation;
    final routeRevision =
        configuration.source.value.value?.modelRoute?.revision;
    if (origin == null ||
        point == null ||
        point.claimed ||
        routeRevision == null) {
      return null;
    }
    final lifetime = _stopLifetime;
    return () {
      final previous = _continuation;
      if (previous != null &&
          _continuationCurrent(previous) &&
          previous.value.continuationId == point.id &&
          (previous.value.pending ||
              previous.value.unknown ||
              previous.value.inProgress)) {
        return previous.work ?? Future<void>.value();
      }
      if (!ref.mounted ||
          !identical(_stopLifetime, lifetime) ||
          page?.isCurrent != true ||
          _stopBoundary ||
          !_execution.matches(binding, requireActive: true) ||
          !_configuration.matches(configuration) ||
          binding.source.value.value?.continuation?.id != point.id ||
          configuration.source.value.value?.modelRoute?.revision !=
              routeRevision ||
          !primaryAction(hasContent: false, submissionPending: false).enabled) {
        return Future<void>.value();
      }
      _stopBoundary = true;
      try {
        previous?.observation?.cancel();
        previous?.keepAlive.close();
        // Cancellation can synchronously reenter navigation/source publication.
        final admitted = binding.source.value;
        if (!ref.mounted ||
            !identical(_stopLifetime, lifetime) ||
            page?.isCurrent != true ||
            !_execution.matches(binding, requireActive: true) ||
            !_configuration.matches(configuration) ||
            admitted.stamp == null ||
            !_sameStopOrigin(admitted.stamp!, origin) ||
            admitted.value?.execution != null ||
            admitted.value?.continuation?.id != point.id ||
            admitted.value?.continuation?.claimed != false ||
            configuration.source.value.value?.modelRoute?.revision !=
                routeRevision) {
          return Future<void>.value();
        }
        final context = _ContinuationContext(
          binding: binding,
          keepAlive: ref.keepAlive(),
          value: ConversationContinuationState(
            intent: ++_continuationIntent,
            origin: admitted.stamp!,
            continuationId: point.id,
            modelRouteRevision: routeRevision,
          ),
        );
        _continuation = context;
        _publishContinuation(context);
        try {
          if (!_continuationCurrent(context) ||
              page?.isCurrent != true ||
              !_execution.matches(binding, requireActive: true) ||
              !_configuration.matches(configuration) ||
              configuration.source.value.value?.modelRoute?.revision !=
                  routeRevision) {
            throw const StudioFailure(
              code: StudioFailureCode.superseded,
              message: 'The continuation source changed before dispatch',
              retryable: false,
              correlationId: 'conversation-continue-source',
            );
          }
          final ticket = binding.session.continueThread(
            origin: context.value.origin,
            continuationId: point.id,
            expectedModelRouteRevision: routeRevision,
          );
          context.ticket = ticket;
          var delivered = false;
          final watch = ticket.state.watchLatest((operation) {
            delivered = true;
            context.value = context.value.copyWith(operation: operation);
            _publishContinuation(context);
          });
          context.observation = watch.observation;
          if (!delivered) {
            context.value = context.value.copyWith(operation: watch.value);
          }
          if (!_continuationCurrent(context)) {
            watch.observation.cancel();
            context.observation = null;
          }
          _publishContinuation(context);
          return context.work = _settleContinuation(
            context,
            _stopDisposed.future,
          );
        } catch (error) {
          context.value = context.value.copyWith(
            error: _stopFailure(error, 'conversation-continue-call'),
          );
          _publishContinuation(context);
          if (context.ticket != null) {
            return context.work = _settleContinuation(
              context,
              _stopDisposed.future,
            );
          }
          context.keepAlive.close();
          return Future<void>.value();
        }
      } finally {
        _stopBoundary = false;
      }
    };
  }

  bool _continuationCurrent(_ContinuationContext context) =>
      ref.mounted &&
      !context.sourceRetired &&
      identical(_continuation, context) &&
      _execution.matches(context.binding) &&
      context.binding.source.value.stamp != null &&
      _sameStopOrigin(
        context.binding.source.value.stamp!,
        context.value.origin,
      );

  void _publishContinuation(_ContinuationContext context) {
    if (context.ticket?.state.value.isPending == false) {
      context.keepAlive.close();
    }
    if (!_continuationCurrent(context) || !state.hasValue) return;
    state = AsyncData(state.requireValue.copyWith(continuation: context.value));
  }

  Future<void> _settleContinuation(
    _ContinuationContext context,
    Future<void> retired,
  ) async {
    try {
      final result = await _observeControlResult(
        context.ticket!.result,
        retired,
      );
      if (result == null) return;
      final error = switch (result) {
        RejectedCommandResult<ContinueThreadReply>(:final error) ||
        UnknownOutcomeCommandResult<ContinueThreadReply>(:final error) ||
        SyncFailedCommandResult<ContinueThreadReply>(:final error) ||
        AcknowledgedSyncFailedCommandResult<ContinueThreadReply>(
          :final error,
        ) => error,
        _ => null,
      };
      context.value = context.value.copyWith(result: result, error: error);
    } catch (error) {
      context.value = context.value.copyWith(
        error: _stopFailure(error, 'conversation-continue-result'),
      );
    }
    _publishContinuation(context);
  }

  /// Explicit read of the original operation, never a second continue dispatch.
  Future<void> Function()? captureContinuationRead() {
    final context = _continuation;
    if (context == null ||
        !_continuationCurrent(context) ||
        context.ticket == null) {
      return null;
    }
    return () => _continuationCurrent(context)
        ? _joinContinuationRead(context)
        : Future<void>.value();
  }

  Future<void> _joinContinuationRead(_ContinuationContext context) {
    if (context.reading case final existing?) return existing;
    final done = Completer<void>();
    context.reading = done.future;
    _readContinuationOperation(context).then<void>(
      (_) {
        context.reading = null;
        done.complete();
      },
      onError: (Object error, StackTrace stack) {
        context.reading = null;
        done.completeError(error, stack);
      },
    );
    return done.future;
  }

  Future<void> _readContinuationOperation(_ContinuationContext context) async {
    context.value = context.value.copyWith(reading: true);
    _publishContinuation(context);
    try {
      final recovered = await context.binding.session.readContinuationOperation(
        context.ticket!.id,
      );
      context.value = context.value.copyWith(
        recovered: recovered,
        error: recovered == null ? context.value.error : null,
      );
    } catch (error) {
      context.value = context.value.copyWith(
        error: _stopFailure(error, 'conversation-continue-read'),
      );
    } finally {
      context.value = context.value.copyWith(reading: false);
      _publishContinuation(context);
    }
  }

  void _disposePresentation(
    _StopContext? stop,
    ThreadMetadata metadata,
    Observation? metadataWatch,
    SessionFacetObserver<InteractionIndexReadState> index,
    SessionFacetObserver<ThreadExecutionState> execution,
    SessionFacetObserver<ThreadConfigurationState> configuration,
    Observation? recovery,
    _ContinuationContext? continuation,
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
    if (continuation != null) {
      attempt(
        'continuation-observation',
        continuation,
        () => continuation.observation?.cancel(),
      );
      attempt(
        'continuation-presentation',
        continuation,
        continuation.keepAlive.close,
      );
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
    attempt('configuration-observations', configuration, configuration.cancel);
    if (recovery != null) {
      attempt('recovery-observation', recovery, recovery.cancel);
    }
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
    final execution = current.value?.execution;
    if (!_stopReady(current) ||
        origin == null ||
        execution == null ||
        !binding.session.acceptsUserInput ||
        _blocksStop(binding, origin, execution.id)) {
      return null;
    }
    final lifetime = _stopLifetime;
    // The control binds an execution. Its click freezes the current revision
    // from this source only; it cannot borrow another Session with the same ID.
    return () => _admitStop(page, lifetime, binding, origin, execution.id);
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
      value.value?.execution != null &&
      value.value?.execution?.phase != AgentExecutionPhase.stopping;

  bool _sameStopOrigin(ThreadFacetStamp left, ThreadFacetStamp right) =>
      left.runtimeEpoch == right.runtimeEpoch &&
      left.incarnation == right.incarnation &&
      left.facet == right.facet;

  bool _blocksStop(
    SessionFacetCapture<ThreadExecutionState> binding,
    ThreadFacetStamp origin,
    String executionId,
  ) {
    final stop = _stop;
    return stop != null &&
        !stop.sourceRetired &&
        identical(stop.binding.session, binding.session) &&
        identical(stop.binding.source, binding.source) &&
        stop.binding.generation == binding.generation &&
        _sameStopOrigin(stop.origin, origin) &&
        stop.target == executionId &&
        (stop.value.pending || stop.value.unknown || stop.value.accepted);
  }

  void _checkStopSource() {
    final continuation = _continuation;
    if (continuation != null &&
        !continuation.sourceRetired &&
        !_continuationCurrent(continuation)) {
      // A replacement source cannot recover or render the old intent. Retire
      // only its UI demand; the original Session retains and joins all work.
      continuation.sourceRetired = true;
      try {
        continuation.observation?.cancel();
        continuation.observation = null;
      } catch (error, stack) {
        // Keep the actual handle for disposal's independent cleanup reporting;
        // an observer fault must not escape into the execution publisher.
        continuation.cause = error;
        continuation.causeStack = stack;
        continuation.value = continuation.value.copyWith(
          error: _stopFailure(error, 'conversation-continue-observation-close'),
        );
      } finally {
        continuation.keepAlive.close();
      }
    }
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
    String executionId,
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
    final target = current.value?.execution?.id;
    if (!_stopReady(current) ||
        origin == null ||
        target == null ||
        target != executionId ||
        !binding.session.acceptsUserInput ||
        !_sameStopOrigin(origin, shownOrigin) ||
        _blocksStop(binding, origin, executionId)) {
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
      final admittedTarget = admitted.value?.execution?.id;
      if (!_stopReady(admitted) ||
          admittedOrigin == null ||
          admittedTarget == null ||
          admittedTarget != executionId ||
          !binding.session.acceptsUserInput ||
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
        final admission = binding.session.stopExecution(
          origin: admittedOrigin,
          executionId: admittedTarget,
        );
        switch (admission) {
          case StopNoExecution():
            // A valid empty source admits no command at all. Do not turn the
            // absence of a target into failure, acceptance or a stopped state.
            if (identical(_stop, stop)) _stop = null;
            return Future<void>.value();
          case StopExecutionOperation(:final ticket):
            stop.ticket = ticket;
        }
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
      final result = await _observeControlResult(stop.ticket!.result, retired);
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
    // The deferred read-back keeps this frame's widget lifecycle and Provider
    // publication apart. A microtask is enough to leave the current stack, and
    // unlike a timer it leaves nothing pending when the tree is torn down from
    // inside that stack (design/25).
    scheduleMicrotask(() {
      if (!ref.mounted || !identical(_stopLifetime, lifetime)) return;
      _stopSyncScheduled = false;
      _syncStopPage(lifetime);
    });
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
      continuation:
          _continuation != null && _continuationCurrent(_continuation!)
          ? _continuation!.value
          : null,
    );
    if (next != before) state = AsyncData(next);
  }
}
