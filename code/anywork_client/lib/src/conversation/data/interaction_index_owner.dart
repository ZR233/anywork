import 'dart:async';
import 'dart:convert';

import '../../../resources_ports.dart';
import '../domain/execution_values.dart';
import '../domain/interaction_index_state.dart';
import '../domain/thread_identity.dart';
import 'connection_owner.dart';
import 'conversation_mirror.dart';
import 'read_scope_owners.dart';
import 'read_connections.dart';

/// Materializes only visible index identities. Question/answer bodies remain lazy.
final class ConversationInteractionIndex {
  ConversationInteractionIndex({
    required this.threadId,
    required ResourceBudget budget,
    required this.nextAttempt,
    required this.openIndex,
    required this.openInteraction,
  }) : _state = ConversationMirror(
         const InteractionIndexReadState(),
         budget: budget,
         owner: 'interaction-index:$threadId',
       );
  final String threadId;
  final AttemptId Function() nextAttempt;
  final Future<InteractionIndexScopeOwner> Function(
    ThreadFacetStamp,
    InteractionIndexRef,
  )
  openIndex;
  final Future<InteractionScopeOwner> Function(
    ThreadFacetStamp,
    InteractionReadRef,
  )
  openInteraction;
  final ConversationMirror<InteractionIndexReadState> _state;
  ThreadFacetStamp? _origin;
  InteractionIndexHeader? _index;
  InteractionIndexScopeOwner? _scope;
  ThreadFacetStamp? _scopeOrigin;
  InteractionIndexHeader? _pinnedIndex;
  bool _scopeHeaderReady = false;
  final Map<int, InteractionListItem> _items = {};
  final Map<int, InteractionBrief?> _overrides = {};
  Future<void>? _loading;
  AttemptId? _loadAttempt;
  int? _offset = 0;
  int _generation = 0;
  int _deltaCount = 0;
  int _deltaBytesUpperBound = 0;
  bool _sealed = false;
  bool _sourceReady = false;
  Object? lastCause;
  StackTrace? lastStack;
  ReadonlyLatestValue<InteractionIndexReadState> get state => _state.readonly;

  void connecting() {
    if (_sealed) return;
    _sourceReady = false;
    _state.publish(
      InteractionIndexReadState(
        lastKnown: _state.value.current ?? _state.value.lastKnown,
        loading: _loading != null,
        error: _state.value.error,
      ),
    );
  }

  void adopt(
    ThreadFacetStamp origin,
    InteractionIndexHeader index,
    InteractionDelta? delta,
  ) {
    if (_sealed) return;
    _sourceReady = true;
    final previous = _origin;
    final sameOwner =
        previous != null &&
        previous.runtimeEpoch == origin.runtimeEpoch &&
        previous.incarnation == origin.incarnation;
    final continuous =
        sameOwner &&
        _index?.reference.entry == index.reference.entry &&
        (delta != null || _index?.reference == index.reference);
    if (!continuous) _reset();
    _origin = origin;
    _index = index;
    if (delta != null && continuous) {
      if (_scope != null || _loading != null) {
        _deltaCount++;
        // A brief has at most six 20-digit integer scalars, two fixed enums and
        // fixed keys; 512 source-JSON bytes is a conservative per-entry bound.
        // The 2048 envelope bound includes the fixed generated identity/stamp.
        _deltaBytesUpperBound +=
            2048 +
            512 *
                (delta.upserted.length +
                    delta.removedEntries.length +
                    delta.terminalFacts.length);
        if (_deltaCount > 64 || _deltaBytesUpperBound > 8 * 1024 * 1024) {
          _reset();
          _origin = origin;
          _index = index;
          _state.publish(
            _state.value.copyWith(
              error: const StudioFailure(
                code: StudioFailureCode.superseded,
                message: 'The interaction index read was superseded by bounded reliable changes.',
                retryable: true,
                correlationId: 'interaction-index-resync',
              ),
            ),
          );
          return;
        }
        for (final entry in delta.removedEntries) {
          _overrides[entry] = null;
          _items.remove(entry);
        }
        for (final brief in delta.upserted) {
          _overrides[brief.reference.entry] = brief;
          final known = _items[brief.reference.entry];
          if (known != null)
            _items[brief.reference.entry] = _item(brief, known.interactionId, known.targetThreadId);
        }
      }
    }
    _publish();
  }

  void _reset() {
    _generation++;
    _origin = null;
    _index = null;
    final previous = _state.value.current;
    final scope = _scope;
    _scope = null;
    _scopeOrigin = null;
    _pinnedIndex = null;
    _scopeHeaderReady = false;
    if (scope != null) {
      scope.requestClose();
      scope.close().ignore();
    }
    _items.clear();
    _overrides.clear();
    _offset = 0;
    _deltaCount = 0;
    _deltaBytesUpperBound = 0;
    _state.publish(
      InteractionIndexReadState(lastKnown: previous ?? _state.value.lastKnown),
    );
  }

  Future<void> load({int limit = 32}) {
    if (_sealed) return Future.error(conversationCancelled);
    if (limit < 1 || limit > 100)
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message: 'Interaction page limit must be within 1..100.',
          retryable: false,
          correlationId: 'interaction-index-limit',
        ),
      );
    final pending = _loading;
    if (pending != null) return pending;
    final origin = _origin;
    final index = _index;
    if (!_sourceReady || origin == null || index == null)
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'The execution index has no current source.',
          retryable: true,
          correlationId: 'interaction-index-unavailable',
        ),
      );
    if (_state.value.current?.complete == true) return Future.value();
    final completion = Completer<void>();
    _loading = completion.future;
    _loadAttempt = nextAttempt();
    final generation = _generation;
    _state.publish(_state.value.copyWith(loading: true, error: null));
    unawaited(
      _load(origin, index, generation, limit).then(
        (_) {
          _loading = null;
          completion.complete();
          if (!_sealed) _publish();
        },
        onError: (Object error, StackTrace stack) {
          lastCause = error;
          lastStack = stack;
          _loading = null;
          final failure = conversationFailure(error);
          completion.completeError(failure, stack);
          if (!_sealed && generation == _generation) {
            if (failure.code == StudioFailureCode.superseded) {
              final currentOrigin = _origin;
              final currentIndex = _index;
              _reset();
              _origin = currentOrigin;
              _index = currentIndex;
            }
            _state.publish(
              _state.value.copyWith(loading: false, error: failure),
            );
          }
        },
      ),
    );
    return completion.future;
  }

  bool _current(int generation) => !_sealed && generation == _generation;
  Future<void> _load(
    ThreadFacetStamp origin,
    InteractionIndexHeader index,
    int generation,
    int limit,
  ) async {
    if (!_current(generation)) throw conversationCancelled;
    if (_scope == null) {
      final scope = await openIndex(origin, index.reference);
      if (!_current(generation)) {
        scope.requestClose();
        scope.close().ignore();
        throw conversationCancelled;
      }
      _scope = scope;
      _scopeOrigin = origin;
      _pinnedIndex = index;
    }
    if (!_scopeHeaderReady) {
      final header = await _scope!.header();
      if (header.total != _pinnedIndex!.total ||
          header.pending != _pinnedIndex!.pending) {
        throw readProtocol(
          'The pinned interaction index header contradicts its reference.',
        );
      }
      _scopeHeaderReady = true;
    }
    if (!_current(generation)) throw conversationCancelled;
    final scope = _scope!;
    final offset = _offset;
    final source = offset == null ? _origin! : _scopeOrigin!;
    int? nextOffset = offset;
    final List<InteractionBrief> requested;
    if (offset != null) {
      final page = await scope.entries(offset: offset, limit: limit);
      if (!_current(generation)) throw conversationCancelled;
      if (page.total != _pinnedIndex!.total)
        throw readProtocol(
          'The index page total changed within a pinned scope.',
        );
      requested = page.items;
      nextOffset = page.nextOffset;
    } else {
      requested = [
        for (final entry in _overrides.entries)
          if (entry.value != null && !_items.containsKey(entry.key))
            entry.value!,
      ]..sort((a, b) => a.reference.entry.compareTo(b.reference.entry));
      if (requested.length > limit)
        requested.removeRange(limit, requested.length);
    }
    final seen = <int>{};
    var last = -1;
    for (final brief in requested) {
      if (!_current(generation)) throw conversationCancelled;
      final entry = brief.reference.entry;
      if (!seen.add(entry) ||
          entry <= last ||
          brief.reference.revision != brief.revision) {
        throw readProtocol(
          'Interaction entries are not unique ascending exact references.',
        );
      }
      last = entry;
      if (_overrides.containsKey(entry) && _overrides[entry] == null) continue;
      final known = _items[entry];
      if (known == null) {
        final detail = await openInteraction(source, brief.reference);
        try {
          final header = await detail.header();
          final id = await readConversationText(detail, header.interactionId);
          final target = await readConversationText(detail, header.threadId);
          if (!_current(generation)) throw conversationCancelled;
          if (header.revision != brief.revision)
            throw readProtocol('The interaction identity revision changed.');
          if (_overrides.containsKey(entry) && _overrides[entry] == null)
            continue;
          _items[entry] = _item(_overrides[entry] ?? brief, id, target);
        } finally {
          detail.requestClose();
          await detail.close();
        }
      }
    }
    _offset = nextOffset;
    if (_offset == null &&
        _items.length != _index!.total &&
        !_overrides.entries.any(
          (entry) => entry.value != null && !_items.containsKey(entry.key),
        )) {
      throw readProtocol(
        'The complete interaction index did not match its declared total.',
      );
    }
  }

  InteractionListItem _item(InteractionBrief brief, String id, String targetThreadId) =>
      InteractionListItem(
        reference: brief.reference,
        interactionId: id,
        targetThreadId: targetThreadId,
        revision: brief.revision,
        kind: brief.kind,
        status: brief.status,
        createdAt: brief.createdAt,
        updatedAt: brief.updatedAt,
      );

  void _publish() {
    final origin = _origin;
    final index = _index;
    if (_sealed || !_sourceReady || origin == null || index == null) return;
    final items = _items.values.toList()
      ..sort((a, b) => a.reference.entry.compareTo(b.reference.entry));
    final complete =
        (index.total == 0 || _offset == null) && items.length == index.total;
    _state.publish(
      InteractionIndexReadState(
        current: InteractionIndexReadSnapshot(
          origin: origin,
          index: index,
          items: items,
          nextOffset: complete ? null : _offset,
          complete: complete,
        ),
        lastKnown: _state.value.lastKnown,
        loading: _loading != null,
      ),
    );
  }

  void seal() {
    if (_sealed) return;
    _sealed = true;
    _generation++;
    _scope?.requestClose();
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    seal();
    final pending = _loading;
    if (pending != null)
      await observeConversationCompletion(
        pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        deadline,
      );
    final scope = _scope;
    final report = scope == null
        ? CloseReport(unresolved: [])
        : await (retry
              ? scope.retryCleanup(deadline: deadline)
              : scope.close(deadline: deadline));
    final unresolved = [...report.unresolved];
    if (_loading != null)
      unresolved.add(
        UnresolvedResource(
          owner: 'interaction-index:$threadId',
          attemptId: _loadAttempt!,
          issues: [
            const FeedCloseIssue(
              diagnostic: StudioShutdownIssue(
                stage: 'interactionIndex',
                code: 'pagePending',
                message: 'The original interaction identity page is still in flight.',
                retryable: true,
                correlationId: 'interaction-index',
              ),
              recovery: CleanupRecovery.awaitCompletion,
            ),
          ],
        ),
      );
    if (unresolved.isEmpty) _state.close();
    return CloseReport(unresolved: unresolved);
  }
}

Future<String> readConversationText(
  TextConversationScope<ConversationTextReadConnection> scope,
  ReadText value,
) async {
  if (value is InlineReadText) return value.text;
  final field = value as DeferredReadText;
  final buffer = StringBuffer();
  var offset = 0;
  while (offset < field.utf8Bytes) {
    final chunk = await scope.text(field.fieldId, offset: offset);
    final bytes = utf8.encode(chunk.text).length;
    if (bytes == 0 ||
        offset + bytes > field.utf8Bytes ||
        (chunk.nextOffset == null && offset + bytes != field.utf8Bytes)) {
      throw readProtocol(
        'The deferred identity did not make exact UTF-8 progress.',
      );
    }
    buffer.write(chunk.text);
    offset += bytes;
    if (chunk.nextOffset == null) break;
  }
  return buffer.toString();
}
