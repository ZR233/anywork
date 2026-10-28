import 'dart:async';

import '../../anywork_client.dart'
    show Observation, ReadModel, ResourceKind, ResourcePermit, ResourcePhase;
import '../../models.dart';
import 'anywork_client.dart';
import 'commands/command_lane.dart';

/// Client-owned, display-scoped reads. No history polling, resource paths or
/// second timeline; each scope retains only its current visible demand.
final class ThreadAudienceQueries {
  ThreadAudienceQueries(this._client);
  final AnyworkClient _client;
  final Set<ThreadAudienceScope> _scopes = {};
  final CommandLane _history = CommandLane();
  bool _closed = false;

  ThreadAudienceScope openScope(String threadId, int generation) {
    if (_closed || _client.isClosed)
      throw StateError('Audience queries closed');
    if (threadId.isEmpty || generation < 1)
      throw ArgumentError('Invalid display identity');
    final permit = _client.budget.acquire(
      ResourceKind.readModel,
      owner: 'audience:$threadId:$generation',
    );
    try {
      final scope = ThreadAudienceScope._(this, threadId, generation, permit);
      _scopes.add(scope);
      return scope;
    } catch (_) {
      permit.release();
      rethrow;
    }
  }

  /// Explicit history action only. The opaque cursor is scoped by this handle,
  /// not reusable on another Thread or after the target changes.
  ThreadClosedAuthorizationsHistory openHistory(String threadId) {
    if (_closed || _client.isClosed)
      throw StateError('Audience queries closed');
    return ThreadClosedAuthorizationsHistory._(
      this,
      threadId,
      _client.session(threadId).state.audience.known?.target,
    );
  }

  Future<void> close() {
    _closed = true;
    _history.seal();
    return Future.wait<void>([
      _history.join(),
      for (final scope in List.of(_scopes)) scope.close(),
    ]);
  }
}

final class ThreadAudienceItemsState {
  const ThreadAudienceItemsState({
    this.authorization,
    this.phase,
    this.summaryVersion,
    this.deliveryVersion,
    this.items = const {},
    this.loading = false,
    this.unavailable,
    this.error,
  });
  final BotAuthorizationRef? authorization;
  final BotAuthorizationPhase? phase;
  final int? summaryVersion;
  final int? deliveryVersion;
  final Map<String, BotAudienceItemStatus> items;
  final bool loading;
  final BotAudienceItemsUnavailableReason? unavailable;
  final Object? error;
}

final class ThreadAudienceScope extends ReadModel<ThreadAudienceItemsState> {
  ThreadAudienceScope._(
    this._owner,
    this.threadId,
    this.generation,
    this._permit,
  ) : super(const ThreadAudienceItemsState()) {
    _observerPermit = _client.budget.acquire(
      ResourceKind.observer,
      owner: 'audience-state:$threadId:$generation',
    );
    try {
      final watched = _client
          .session(threadId)
          .source
          .watchLatest((_) => _audienceChanged());
      _observation = watched.observation;
    } catch (_) {
      _observerPermit.release();
      rethrow;
    }
  }
  final ThreadAudienceQueries _owner;
  AnyworkClient get _client => _owner._client;
  final String threadId;
  final int generation;
  final ResourcePermit _permit;
  late final Observation _observation;
  late final ResourcePermit _observerPermit;
  final CommandLane _work = CommandLane();
  Map<String, int> _visible = const {};
  BotAuthorizationRef? _explicitAuthorization;
  BotAuthorizationRef? _authorization;
  ThreadAudience? _audience;
  (BotAuthorizationId, int, int)? _versions;
  int _incarnation = 0;
  bool _retired = false;
  bool _scheduled = false;
  bool _running = false;
  bool _dirty = false;
  Future<void>? _closing;

  bool get isActive => !_retired && !_owner._closed && !_client.isClosed;
  bool get isHistoricalSelection => _explicitAuthorization != null;

  /// Canonical IDs and their displayed revisions; Map insertion order is wire
  /// order. A group ID is never an item ID. Repeated observers share this demand.
  void setVisible(Map<String, int> revisions) {
    if (!isActive) throw StateError('Audience display retired');
    if (revisions.entries.any((e) => e.key.isEmpty || e.value < 0)) {
      throw ArgumentError('Invalid canonical item identity');
    }
    if (_sameRevisions(_visible, revisions)) return;
    _visible = Map.unmodifiable(revisions);
    _invalidate();
  }

  /// Only an explicit history selection may change the default current-or-
  /// latest-closed authorization context. Never enumerate generations per item.
  void selectAuthorization(BotAuthorizationRef? authorization) {
    if (!isActive) throw StateError('Audience display retired');
    final target = _client.session(threadId).state.audience.known?.target;
    if (authorization != null &&
        (target == null ||
            target.botId != authorization.id.botId ||
            target.chatId != authorization.id.chatId)) {
      throw ArgumentError('Authorization belongs to another target');
    }
    _explicitAuthorization = authorization;
    _invalidate();
  }

  void retry() {
    if (!isActive) throw StateError('Audience display retired');
    _invalidate();
  }

  void _audienceChanged() {
    if (!isActive) return;
    final next = _client.session(threadId).state.audience;
    if (_audience == next) return;
    _invalidate();
  }

  void _invalidate() {
    _incarnation++;
    final audience = _client.session(threadId).state.audience;
    final target = audience.known?.target;
    final selected = _explicitAuthorization;
    if (selected != null &&
        (target == null ||
            target.botId != selected.id.botId ||
            target.chatId != selected.id.chatId)) {
      // A closed authorization stays explainable only while this Thread still
      // proves the same bot/chat target. Losing that proof (unavailable,
      // unbound or a different scope) must not keep an old authorization's
      // receipts as displayable current context or re-query them.
      _explicitAuthorization = null;
    }
    final authorization = _explicitAuthorization ?? audience.queryAuthorization;
    _audience = audience;
    _authorization = authorization;
    if (_versions?.$1 != authorization?.id) _versions = null;
    // Matching item/auth revisions do not prove a ledger is still fresh after
    // its summary/control context invalidates it. Clear it before waiting for
    // an already running read, not merely when the replacement chain starts.
    state = ThreadAudienceItemsState(
      authorization: authorization,
      loading: authorization != null && _visible.isNotEmpty,
    );
    _dirty = true;
    if (_scheduled || _running) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!isActive || !_dirty) return;
      unawaited(_work.run(_refresh));
    });
  }

  Future<void> _refresh() async {
    _running = true;
    _dirty = false;
    final incarnation = _incarnation;
    final authorization = _authorization;
    final visible = _visible;
    final audience = _audience;
    try {
      if (authorization == null || visible.isEmpty || !isActive) return;
      state = ThreadAudienceItemsState(
        authorization: authorization,
        items: state.items,
        loading: true,
      );
      final ids = visible.keys.toList(growable: false);
      final statuses = <String, BotAudienceItemStatus>{};
      BotAudienceItemsReadItems? combined;
      for (var offset = 0; offset < ids.length; offset += 100) {
        if (!_accepts(incarnation)) return;
        final batch = ids.skip(offset).take(100).toList(growable: false);
        final permit = _client.budget.acquire(
          ResourceKind.pendingOperation,
          owner: 'audience:$threadId:$generation:$incarnation:$offset',
        );
        late final ReadThreadAudienceItemsReply reply;
        try {
          reply = await _client.transport.readThreadAudienceItems(
            ReadThreadAudienceItemsRequest(
              threadId: threadId,
              authorization: authorization.id,
              itemIds: batch,
            ),
          );
        } finally {
          permit.release();
        }
        if (!_accepts(incarnation)) return;
        if (reply.threadId != threadId ||
            reply.authorization != authorization.id) {
          throw _audienceProtocol('Audience response belongs to another scope');
        }
        switch (reply.result) {
          case BotAudienceItemsReadUnavailable(:final reason):
            state = ThreadAudienceItemsState(
              authorization: authorization,
              unavailable: reason,
            );
            return;
          case BotAudienceItemsReadItems result:
            if (result.authorization != authorization ||
                result.summaryVersion <
                    (audience?.known?.delivery.version ?? 0) ||
                (_versions != null &&
                    (result.summaryVersion < _versions!.$2 ||
                        result.deliveryVersion < _versions!.$3)) ||
                result.items.length != batch.length ||
                (combined != null &&
                    (combined.summaryVersion != result.summaryVersion ||
                        combined.deliveryVersion != result.deliveryVersion ||
                        combined.phase != result.phase))) {
              throw _audienceProtocol('Audience versions cannot be reconciled');
            }
            for (var i = 0; i < batch.length; i++) {
              final item = result.items[i];
              if (item.itemId != batch[i])
                throw _audienceProtocol('Audience item order mismatch');
              if (item.canonical case BotAudienceCanonicalItemPresent(
                :final revision,
              )) {
                if (revision != visible[item.itemId]) {
                  // Canonical and display snapshots differ. Preserve no stale
                  // receipt as a current revision; a demand/version change retries.
                  state = ThreadAudienceItemsState(
                    authorization: authorization,
                    unavailable: BotAudienceItemsUnavailableReason
                        .canonicalReadInvalidated,
                  );
                  return;
                }
              }
              statuses[item.itemId] = item;
            }
            combined = result;
        }
      }
      if (!_accepts(incarnation) || combined == null) return;
      _versions = (
        authorization.id,
        combined.summaryVersion,
        combined.deliveryVersion,
      );
      state = ThreadAudienceItemsState(
        authorization: authorization,
        phase: combined.phase,
        summaryVersion: combined.summaryVersion,
        deliveryVersion: combined.deliveryVersion,
        items: Map.unmodifiable(statuses),
      );
    } catch (error) {
      if (_accepts(incarnation)) {
        state = ThreadAudienceItemsState(
          authorization: authorization,
          error: error,
        );
      }
    } finally {
      _running = false;
      if (_dirty && isActive) {
        // At most one real request chain plus one latest demand, no token FIFO.
        _invalidate();
      }
    }
  }

  bool _accepts(int incarnation) => isActive && _incarnation == incarnation;

  void retire() {
    if (_retired) return;
    _retired = true;
    _incarnation++;
    _observation.cancel();
    _observerPermit.release();
    _work.seal();
    _permit.mark(ResourcePhase.retiring);
    _visible = const {};
    _versions = null;
    state = const ThreadAudienceItemsState();
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    retire();
    await _work.join();
    _owner._scopes.remove(this);
    source.close();
    _permit.release();
  }
}

final class ThreadClosedAuthorizationsHistory {
  ThreadClosedAuthorizationsHistory._(this._owner, this.threadId, this._target);
  final ThreadAudienceQueries _owner;
  final String threadId;
  final BotAudienceTarget? _target;
  String? _cursor;
  bool _started = false;
  bool _done = false;
  Future<ThreadClosedAuthorizationsRead>? _pending;
  bool _retired = false;

  Future<ThreadClosedAuthorizationsRead> next({int limit = 16}) {
    if (_retired || _owner._closed || _owner._client.isClosed) {
      return Future.error(StateError('Authorization history retired'));
    }
    if (limit < 1 || limit > 32 || _done)
      return Future.error(ArgumentError('Invalid history page'));
    final current = _pending;
    if (current != null) return current;
    final permit = _owner._client.budget.acquire(
      ResourceKind.pendingOperation,
      owner: 'audience-history:$threadId',
    );
    late final Future<ThreadClosedAuthorizationsRead> work;
    work = _owner._history
        .run(() async {
          try {
            final reply = await _owner._client.transport
                .readThreadClosedAuthorizations(
                  ReadThreadClosedAuthorizationsRequest(
                    threadId: threadId,
                    cursor: _started ? _cursor : null,
                    limit: limit,
                  ),
                );
            if (_retired ||
                _owner._closed ||
                _owner._client.isClosed ||
                _owner._client.session(threadId).state.audience.known?.target !=
                    _target) {
              throw StateError('Authorization history scope changed');
            }
            if (reply.threadId != threadId)
              throw _audienceProtocol('History Thread mismatch');
            if (reply.result case ThreadClosedAuthorizationsReadPage(
              :final page,
            )) {
              if (page.target != _target ||
                  page.authorizations.length > limit ||
                  page.authorizations.any(
                    (a) =>
                        a.authorization.id.botId != _target?.botId ||
                        a.authorization.id.chatId != _target?.chatId,
                  ))
                throw _audienceProtocol('History target mismatch');
              _cursor = page.nextCursor;
              _done = _cursor == null;
            } else {
              _done = true;
            }
            _started = true;
            return reply.result;
          } finally {
            permit.release();
          }
        })
        .whenComplete(() {
          if (identical(_pending, work)) _pending = null;
        });
    _pending = work;
    return work;
  }

  void retire() => _retired = true;
}

bool _sameRevisions(Map<String, int> a, Map<String, int> b) =>
    a.length == b.length && a.keys.every((key) => a[key] == b[key]);
StudioFailure _audienceProtocol(String message) => StudioFailure(
  code: StudioFailureCode.protocol,
  message: message,
  retryable: false,
  correlationId: 'client-audience',
);
