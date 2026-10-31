import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart';

import '../../../../presentation/view_models/timeline_session_owner.dart';
import '../state/timeline_detail_state.dart';

/// One user-opened viewer owns one query scope, accepted Future and exact body.
/// Closing it cancels/joins that scope only, never the shared conversation.
final class TimelineDetailOwner extends ChangeNotifier {
  TimelineDetailOwner({
    required this.lease,
    required this.itemId,
    required this.field,
  }) {
    _item = lease.itemOf(itemId);
    _reference = lease.detailRef(itemId, field);
    lease.retirement.addListener(_checkIdentity);
    _rebindIdentity();
    _checkIdentity();
  }
  final TimelineDisplayLease lease;
  final String itemId;
  final ThreadContentFieldView field;
  late final ConversationDetailRef? _reference;
  late final ConversationItem? _item;
  Listenable? _entry;
  Listenable? _member;
  ConversationQueryScope? _scope;
  Future<void>? _accepted;
  Future<void>? _closing;
  ConversationQueryCursor? _continuation;
  bool _closed = false;
  bool _invalidated = false;
  TimelineDetailState _state = const TimelineDetailState();
  TimelineDetailState get state => _state;
  bool get canCopy =>
      !_closed &&
      _valid &&
      _state.complete &&
      !_state.terminal &&
      _state.error == null;

  void _publish(TimelineDetailState next) {
    _state = next;
    notifyListeners();
  }

  bool get _valid =>
      !lease.isRetired &&
      _reference != null &&
      identical(lease.itemOf(itemId), _item);

  void _rebindIdentity() {
    final entry = lease.presentationFor(itemId);
    final member = lease.memberObservation(itemId);
    if (!identical(_entry, entry)) {
      _entry?.removeListener(_structureChanged);
      _entry = entry;
      _entry?.addListener(_structureChanged);
    }
    if (!identical(_member, member)) {
      _member?.removeListener(_checkIdentity);
      _member = member;
      _member?.addListener(_checkIdentity);
    }
  }

  void _structureChanged() {
    if (_closed || _invalidated) return;
    _rebindIdentity();
    _checkIdentity();
  }

  void _invalidate() {
    if (_closed || _invalidated) return;
    _invalidated = true;
    _continuation = null;
    _scope?.retire();
    _publish(const TimelineDetailState(terminal: true));
  }

  void _checkIdentity() {
    if (_closed || _valid) return;
    _invalidate();
  }

  bool _isIdentityFailure(Object error) =>
      error is StaleConversationScope ||
      error is StudioFailure &&
          (error.code == StudioFailureCode.conflict ||
              error.code == StudioFailureCode.notFound);

  Future<void> load() {
    if (_closed || _state.loading || _state.complete || _state.terminal) {
      return Future.value();
    }
    if (!_valid) {
      _checkIdentity();
      return Future.value();
    }
    final oldScope = _scope;
    if (oldScope != null && !oldScope.isActive) {
      // The lease retains any failed cleanup and its real scope. A stale
      // cleanup failure must not publish into the replacement attempt.
      unawaited(lease.closeDetailQueries(oldScope).catchError((Object _) {}));
      _scope = null;
    }
    final scope = _scope ??= lease.openDetailQueries();
    if (scope == null) {
      _publish(
        TimelineDetailState(text: _state.text, error: StateError('内容连接尚未就绪')),
      );
      return Future.value();
    }
    // Capture and register the real operation before the first await.
    _publish(TimelineDetailState(text: _state.text, loading: true));
    return _accepted = _read(scope);
  }

  Future<void> _read(ConversationQueryScope scope) async {
    try {
      while (!_closed && _valid && scope.isActive) {
        final before = _continuation;
        final chunk = await scope.readDetail(
          itemId: itemId,
          query: ConversationDetailQuery(
            timelineEpoch: lease.timelineEpoch,
            field: field,
            continuation: before,
            maxBytes: 64 * 1024,
          ),
        );
        if (_closed ||
            !_valid ||
            !scope.isActive ||
            !identical(scope, _scope)) {
          return;
        }
        if (chunk.continuation != null && chunk.continuation == before) {
          throw const ChatProtocolError('Detail continuation did not advance');
        }
        _continuation = chunk.continuation;
        _publish(
          TimelineDetailState(
            text: _state.text + chunk.text,
            loading: !chunk.isLast,
            complete: chunk.isLast,
          ),
        );
        if (chunk.isLast) return;
      }
    } catch (error) {
      if (!_closed && identical(scope, _scope) && _isIdentityFailure(error)) {
        _invalidate();
      } else if (!_closed && _valid && identical(scope, _scope)) {
        _publish(TimelineDetailState(text: _state.text, error: error));
      }
    } finally {
      if (!_closed && !_invalidated && _state.loading) {
        if (!_valid) {
          _invalidate();
        } else {
          _publish(TimelineDetailState(text: _state.text));
        }
      }
    }
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _scope?.retire();
    _publish(const TimelineDetailState(terminal: true));
    return _closing = _join().catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _join() async {
    final accepted = _accepted;
    if (accepted != null) await accepted;
    final scope = _scope;
    if (scope != null) {
      await lease.closeDetailQueries(scope);
    }
    _scope = null;
    _publish(const TimelineDetailState(terminal: true));
  }

  @override
  void dispose() {
    assert(_closed, 'The connector must close/join its owner before disposing');
    lease.retirement.removeListener(_checkIdentity);
    _entry?.removeListener(_structureChanged);
    _member?.removeListener(_checkIdentity);
    _state = const TimelineDetailState(terminal: true);
    super.dispose();
  }
}
