import 'dart:async';

import '../../../lifecycle.dart';
import '../../../models.dart';
import '../../../conversation_ports.dart';
import '../../../directory_ports.dart';
import '../../observation/latest_value.dart';
import '../../studio/stores/thread_directory_store.dart';
import '../../studio/stores/domain_sync.dart';
import '../domain/conversation_repository.dart';
import '../domain/conversation_state.dart';
import '../domain/conversation_errors.dart';
import 'input_turn_facts.dart';

/// Shares one Native feed with the visible page and mirrors only its metadata.
final class ConversationSessionImpl implements ConversationSession {
  ConversationSessionImpl(
    this.threadId, {
    required this.transport,
    required this.directory,
    required InputFactRegistry inputFacts,
    required ClientScope scope,
  }) : _scope = scope,
       _inputFacts = inputFacts,
       _source = LatestValue(ThreadSessionState(threadId: threadId)) {
    final lease = _scope.acquireLease(
      'conversation-directory',
      () => _SessionDirectoryLease(directory.observeThread(threadId)),
    );
    _directory = lease.observation;
    _directoryObservation = _directory.state.watch((_) {
      if (!_closed)
        _source.publish(
          state.copyWith(directoryRow: _directory.state.value.frame?.row),
        );
    }, fireImmediately: true);
  }
  @override
  final String threadId;
  final ConversationFeedPort transport;
  final ThreadDirectoryStore directory;
  final ClientScope _scope;
  final InputFactRegistry _inputFacts;
  final LatestValue<ThreadSessionState> _source;
  late final DirectoryObservation<ThreadMetadataFrame> _directory;
  late final Observation _directoryObservation;
  ClientAcquisition<_FeedResource>? _feed;
  ClientScope? _feedScope;
  final List<ClientScope> _retiredScopes = [];
  bool _visible = false;
  bool _closed = false;
  int _generation = 0;
  Completer<ThreadWorkspace>? _resync;
  Future<CloseReport>? _closing;

  @override
  ThreadSessionState get state => _source.value;
  @override
  ValueObservation<ThreadSessionState> get source => _source;
  @override
  bool get isActive => _visible && !_closed;
  @override
  bool get isClosed => _closed;

  void setVisible(bool visible) {
    if (_closed && visible) throw StateError('Conversation is closed');
    if (_visible == visible) return;
    _visible = visible;
    if (!visible) {
      _retire();
      _source.publish(state.copyWith(sync: const DomainSyncStatus()));
      return;
    }
    _source.publish(
      state.copyWith(
        sync: const DomainSyncStatus(phase: DomainSyncPhase.connecting),
      ),
    );
  }

  Future<ConversationFeedHandle> openFeed({int initialLimit = 50}) {
    if (_closed) return Future.error(StateError('Conversation is closed'));
    final existing = _feed;
    if (existing != null) return existing.ready.then((r) => r.handle);
    final generation = ++_generation;
    // Register before publishing connecting: synchronous navigation can retire it.
    final feedScope = _scope.child('feed-$generation');
    _feedScope = feedScope;
    final acquisition = feedScope.open<_FeedResource>(
      'conversation-feed',
      (operation) async {
        final handle = await transport.openConversationFeed(
          threadId,
          initialLimit: initialLimit,
        );
        return _FeedResource(
          operation.resourceId,
          handle,
          onRetire: () {
            if (generation == _generation && identical(_feedScope, feedScope)) {
              _retire();
            }
          },
          onMeta: (meta) {
            if (_closed || generation != _generation) return;
            _acceptMeta(meta);
          },
          onPresented: (event) {
            if (_closed || generation != _generation) return;
            _inputFacts.publish(
              InputTurnFact(
                threadId: threadId,
                inputId: event.inputId,
                itemId: event.itemId,
                turnId: null,
                status: StudioTurnStatus.queued,
                saved: null,
              ),
            );
          },
          onFailure: (error) {
            if (_closed || generation != _generation) return;
            _source.publish(
              state.copyWith(
                sync: DomainSyncStatus(
                  phase: DomainSyncPhase.failed,
                  errorMessage: error.toString(),
                ),
              ),
            );
          },
        );
      },
      onFailure: (error, stack) {
        if (!_closed && generation == _generation) {
          _source.publish(
            state.copyWith(
              sync: DomainSyncStatus(
                phase: DomainSyncPhase.failed,
                errorMessage: error.toString(),
              ),
            ),
          );
        }
      },
    );
    if (!_closed && generation == _generation) {
      _feed = acquisition;
      _source.publish(
        state.copyWith(
          sync: const DomainSyncStatus(phase: DomainSyncPhase.connecting),
        ),
      );
    } else {
      acquisition.requestClose();
    }
    return acquisition.ready.then((resource) {
      if (_closed || generation != _generation)
        throw ThreadStateResyncCancelled(threadId);
      if (resource.handle.threadId != threadId) {
        _retire();
        throw StateError('ConversationFeed thread identity mismatch');
      }
      _acceptMeta(resource.handle.sessionMetaSnapshot);
      if (_closed || generation != _generation)
        throw ThreadStateResyncCancelled(threadId);
      return resource.handle;
    });
  }

  @override
  Future<SessionDetailWindow> readSessionDetail({
    required SessionDetailKind kind,
    required int offset,
    required int maxBytes,
  }) async {
    final feed = _feed;
    if (_closed || feed == null) throw ThreadStateResyncCancelled(threadId);
    final generation = _generation;
    final resource = await feed.ready;
    if (_closed || generation != _generation || !identical(feed, _feed)) {
      throw ThreadStateResyncCancelled(threadId);
    }
    final window = await resource.handle.readSessionDetail(
      kind: kind,
      offset: offset,
      maxBytes: maxBytes,
    );
    if (_closed || generation != _generation || !identical(feed, _feed)) {
      throw ThreadStateResyncCancelled(threadId);
    }
    return window;
  }

  void _acceptMeta(SessionMetaSnapshot meta) {
    if (meta.threadId != threadId)
      throw StateError('SessionMeta thread identity mismatch');
    _source.publish(state.copyWith(meta: meta, sync: DomainSyncStatus.ready));
    if (_closed) return;
    for (final turn in [meta.activeTurn, meta.lastTurn]) {
      if (turn?.inputId != null && _inputFacts.isWatching(turn!.inputId!)) {
        _inputFacts.publish(_turnFact(turn));
      }
    }
  }

  void seedInputFacts(String inputId, void Function(InputTurnFact) onFact) {
    for (final turn in [state.activeTurn, state.lastTurn]) {
      if (turn?.inputId == inputId) onFact(_turnFact(turn!));
    }
  }

  InputTurnFact _turnFact(StudioTurnView turn) => InputTurnFact(
    threadId: turn.threadId,
    inputId: turn.inputId!,
    itemId: null,
    turnId: turn.turnId,
    status: turn.state.status,
    saved: null,
  );

  void _retire() {
    ++_generation;
    final resync = _resync;
    _resync = null;
    if (resync != null && !resync.isCompleted)
      resync.completeError(ThreadStateResyncCancelled(threadId));
    final feed = _feed;
    final resources = _feedScope;
    _feed = null;
    _feedScope = null;
    if (resources != null) {
      _retiredScopes.add(resources);
      resources.requestClose();
    }
    if (feed != null) {
      feed.requestClose();
      unawaited(
        feed.close().then<void>((_) {
          _retiredScopes.remove(resources);
        }, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  @override
  void refresh() {
    if (!isActive) return;
    _retire();
    unawaited(
      openFeed().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  @override
  Future<ThreadWorkspace> resyncRuntime() {
    if (!isActive) return Future.error(ThreadStateResyncCancelled(threadId));
    final existing = _resync;
    if (existing != null) return existing.future;
    _retire();
    final pending = Completer<ThreadWorkspace>();
    _resync = pending;
    unawaited(
      openFeed().then<void>(
        (_) {
          if (!identical(_resync, pending)) return;
          _resync = null;
          final workspace = state.workspace;
          if (workspace == null)
            pending.completeError(ThreadStateResyncCancelled(threadId));
          else
            pending.complete(workspace);
        },
        onError: (Object error, StackTrace stack) {
          if (!identical(_resync, pending)) return;
          _resync = null;
          pending.completeError(error, stack);
        },
      ),
    );
    return pending.future;
  }

  Future<CloseReport> retire({ClientCloseBudget? budget}) async {
    setVisible(false);
    final scopes = List.of(_retiredScopes);
    final reports = await Future.wait(
      scopes.map(
        (scope) => scope.close(
          budget: budget ?? ClientCloseBudget(const Duration(seconds: 30)),
        ),
      ),
    );
    for (var i = 0; i < scopes.length; i++) {
      if (reports[i].complete) _retiredScopes.remove(scopes[i]);
    }
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }

  Future<CloseReport> close({ClientCloseBudget? budget}) {
    final existing = _closing;
    if (existing != null) return existing;
    final completion = Completer<CloseReport>();
    _closing = completion.future;
    completion.complete(Future.sync(() => _close(budget)));
    return completion.future;
  }

  Future<CloseReport> _close(ClientCloseBudget? budget) async {
    _closed = true;
    _directoryObservation.cancel();
    _visible = false;
    _retire();
    final result = await _scope.close(
      budget: budget ?? ClientCloseBudget(const Duration(seconds: 30)),
    );
    _source.close();
    return result;
  }

  Future<CloseReport> retryCleanup({required ClientCloseBudget budget}) =>
      _scope.retryCleanup(budget: budget);
}

final class _SessionDirectoryLease implements ClientLease {
  _SessionDirectoryLease(this.observation);
  final DirectoryObservation<ThreadMetadataFrame> observation;
  @override
  List<ClientResourceId> get retirementResourceIds =>
      observation.retirementResourceIds;
  @override
  Future<void> release() => observation.release();
}

/// Adapts resource ownership and taps typed metadata while the page consumes it.
/// No timeline list, payload decoding or second event buffer lives in the SDK.
final class _FeedResource implements ClientResource {
  _FeedResource(
    this.resourceId,
    ConversationFeedHandle native, {
    required void Function() onRetire,
    required void Function(SessionMetaSnapshot) onMeta,
    required void Function(ConversationInputPresented) onPresented,
    required void Function(Object) onFailure,
  }) : _native = native,
       _onRetire = onRetire {
    handle = _ObservedFeed(this, onMeta, onPresented, onFailure);
  }
  @override
  final ClientResourceId resourceId;
  final ConversationFeedHandle _native;
  final void Function() _onRetire;
  late final ConversationFeedHandle handle;
  Future<void>? _closing;
  bool _closeRequested = false;
  bool _retired = false;
  void _seal() {
    if (_closeRequested) return;
    _closeRequested = true;
    _retired = true;
    // Withdraw this generation before native callbacks can reopen the thread.
    // The scope keeps ownership and joins this resource's shared close future.
    _onRetire();
  }

  @override
  void requestClose() {
    if (_closeRequested) return;
    _seal();
    try {
      _native.requestClose();
    } catch (_) {
      _closeRequested = false;
      rethrow;
    }
  }

  @override
  Future<void> close() {
    final existing = _closing;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _closing = completion.future;
    completion.complete(
      Future<void>.sync(() {
        _seal();
        return _native.close();
      }),
    );
    return completion.future;
  }

  @override
  Future<void> retryClose() {
    _closing = null;
    return close();
  }
}

final class _ObservedFeed implements ConversationFeedHandle {
  _ObservedFeed(this.owner, this.onMeta, this.onPresented, this.onFailure);
  final _FeedResource owner;
  final void Function(SessionMetaSnapshot) onMeta;
  final void Function(ConversationInputPresented) onPresented;
  final void Function(Object) onFailure;
  ConversationFeedHandle get native => owner._native;
  @override
  String get threadId => native.threadId;
  @override
  LiveStatusSnapshot get liveStatusSnapshot => native.liveStatusSnapshot;
  @override
  SessionMetaSnapshot get sessionMetaSnapshot => native.sessionMetaSnapshot;
  @override
  late final Stream<ConversationFeedEvent> events = native.events.transform(
    StreamTransformer<
      ConversationFeedEvent,
      ConversationFeedEvent
    >.fromHandlers(
      handleData: (event, sink) {
        try {
          switch (event) {
            case ConversationSessionMeta(:final snapshot):
              onMeta(snapshot);
            case ConversationInputPresented():
              onPresented(event);
            case ConversationResyncRequired(:final reason):
              onFailure(StateError(reason));
            default:
              break;
          }
          sink.add(event);
        } catch (error, stack) {
          onFailure(error);
          sink.addError(error, stack);
        }
      },
      handleError: (error, stack, sink) {
        if (!owner._closeRequested) onFailure(error);
        sink.addError(error, stack);
      },
      handleDone: (sink) {
        if (!owner._closeRequested)
          onFailure(StateError('ConversationFeed stream ended'));
        sink.close();
      },
    ),
  );
  @override
  Future<TimelinePatch> loadOlder({required String cursor, int limit = 50}) =>
      native.loadOlder(cursor: cursor, limit: limit);
  @override
  Future<List<WorkGroupMember>> loadWorkGroupMembers({
    int? afterSeq,
    int? beforeSeq,
  }) => native.loadWorkGroupMembers(afterSeq: afterSeq, beforeSeq: beforeSeq);
  @override
  Future<BodyWindow> readBodyWindow({
    required BodyRef reference,
    required int offset,
    required int maxBytes,
  }) => native.readBodyWindow(
    reference: reference,
    offset: offset,
    maxBytes: maxBytes,
  );
  @override
  Future<SessionDetailWindow> readSessionDetail({
    required SessionDetailKind kind,
    required int offset,
    required int maxBytes,
  }) async {
    if (owner._retired) throw const ClientResourceClosed();
    final window = await native.readSessionDetail(
      kind: kind,
      offset: offset,
      maxBytes: maxBytes,
    );
    if (owner._retired) throw const ClientResourceClosed();
    return window;
  }

  @override
  Future<TimelinePatch> resetToLatest({int limit = 50}) =>
      native.resetToLatest(limit: limit);
  @override
  void requestClose() => owner.requestClose();
  @override
  Future<void> close() => owner.close();
}
