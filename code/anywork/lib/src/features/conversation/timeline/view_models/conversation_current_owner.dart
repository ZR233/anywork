import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart';

import '../state/content_reference_identity.dart';
import '../state/timeline_display_diagnostics.dart';

/// Display-owned range subscriptions on one captured SDK content qualification.
/// Only bounded windows and resource handles live here, never chat messages or
/// a text-delta accumulator.
final class ConversationCurrentOwner extends ChangeNotifier {
  ConversationCurrentOwner(this.content) {
    _attempt = content.currentAttemptId;
    _connection = content.state.watch((state) {
      if (_closed) return;
      final attemptChanged = _attempt != content.currentAttemptId;
      if (attemptChanged || state is! ChatReady<bool>) {
        _attempt = content.currentAttemptId;
        if (attemptChanged) {
          _current = null;
          _explicitSources = const [];
          _offsets.clear();
        }
        _retireScope();
      }
      if (state is ChatReady<bool>) _reconcile();
      _notify();
    });
  }

  final ConversationContent content;
  Observation? _connection;
  Object? _attempt;
  CurrentProjection? _current;
  List<CurrentWindowSource> _explicitSources = const [];
  ConversationQueryScope? _scope;
  final Map<Object, CurrentWindowObservation> _windows = {};
  final Map<Object, int> _offsets = {};
  final Set<ConversationQueryScope> _retiredScopes = {};
  final Set<Future<void>> _cancellations = {};
  Future<void>? _joining;
  int _generation = 1;
  bool _expanded = false;
  bool _responding = false;
  bool _closed = false;
  Object? cleanupError;
  String? invalidationNotice;

  bool get isCurrent =>
      !_closed &&
      !content.isClosed &&
      _attempt == content.currentAttemptId &&
      content.state.value is ChatReady<bool>;
  Iterable<CurrentWindowObservation> get windows =>
      isCurrent ? _windows.values : const [];
  bool get expanded => _expanded;
  int get queryGeneration => _generation;

  void synchronize(
    CurrentProjection current, {
    required bool responding,
    required bool expanded,
  }) {
    if (_closed) return;
    _current = current;
    _responding = responding;
    _expanded = expanded;
    _reconcile();
  }

  /// A mounted, explicitly expanded collection entry borrows its own scope.
  /// Only producer-declared body capabilities from the bounded page are accepted.
  void synchronizeSources(List<CurrentWindowSource> sources) {
    if (_closed) return;
    _explicitSources = List.unmodifiable(sources);
    _expanded = true;
    _reconcile();
  }

  ConversationQueryScope get queryScope {
    if (!isCurrent || cleanupError != null) {
      throw const StaleConversationScope();
    }
    return _scope ??= content.openScope(generation: _generation);
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _reconcile() {
    if (!isCurrent || cleanupError != null || _joining != null) return;
    final current = _current;
    final wanted = <Object, CurrentWindowSource>{
      for (final source in _explicitSources)
        contentReferenceIdentity(source.reference): source,
      for (final preview
          in current?.previews ?? const <CurrentContentPreview>[])
        if (_responding
            ? preview.role == CurrentContentRole.response
            : _expanded)
          contentReferenceIdentity(preview.reference): CurrentWindowSource(
            id: '${preview.id}:${preview.role.name}',
            reference: preview.reference,
            text: preview.text,
          ),
      if (_expanded && current?.plan?.document != null)
        contentReferenceIdentity(current!.plan!.document!): CurrentWindowSource(
          id: 'plan:${current.plan!.revision}',
          reference: current.plan!.document!,
          text: '',
        ),
    };
    _offsets.removeWhere((key, _) => !wanted.containsKey(key));
    if (wanted.isEmpty && !_expanded) {
      _retireScope();
      return;
    }
    final removed = [
      for (final entry in _windows.entries)
        if (!wanted.containsKey(entry.key)) entry.value,
    ];
    if (removed.isNotEmpty) {
      for (final observation in removed) {
        if (observation.source.reference.target case BodyContentTarget(
          owner: CurrentContentOwner(:final domain, :final id, :final revision),
          :final key,
        )) {
          for (final replacement in wanted.values) {
            if (replacement.reference.databaseId !=
                observation.source.reference.databaseId) {
              continue;
            }
            if (replacement.reference.target case BodyContentTarget(
              owner: CurrentContentOwner(
                domain: final nextDomain,
                id: final nextId,
                revision: final nextRevision,
              ),
              key: final nextKey,
            )) {
              if (domain == nextDomain &&
                  id == nextId &&
                  key == nextKey &&
                  revision != nextRevision) {
                invalidationNotice = '当前文档已更新，原版本已失效';
              }
            }
          }
        }
      }
      // Close the original scope before replacing capabilities; in particular a
      // failed cancel cannot be hidden by opening a fresh display scope.
      _retireScope();
      return;
    }
    for (final entry in wanted.entries) {
      final existing = _windows[entry.key];
      if (existing != null) {
        existing.source = entry.value;
        continue;
      }
      try {
        final scope = queryScope;
        final observation = CurrentWindowObservation(
          source: entry.value,
          offset: _offsets[entry.key] ?? 0,
        );
        _windows[entry.key] = observation;
        observation.subscription = scope
            .watchContent(
              reference: observation.source.reference,
              range: ContentRange(
                offset: observation.offset,
                maxBytes: 32 * 1024,
              ),
            )
            .listen(
              (window) {
                if (!_eligible(scope, observation, entry.key)) return;
                observation.window = window;
                observation.error = null;
                _notify();
              },
              onError: (Object error, StackTrace stack) {
                if (!_eligible(scope, observation, entry.key)) return;
                observation.error = error;
                _notify();
              },
            );
      } catch (error) {
        cleanupError = error;
      }
    }
  }

  bool _eligible(
    ConversationQueryScope scope,
    CurrentWindowObservation observation,
    Object key,
  ) =>
      !_closed &&
      scope.isActive &&
      identical(_scope, scope) &&
      identical(_windows[key], observation) &&
      _attempt == content.currentAttemptId;

  void nextWindow(CurrentWindowObservation observation) {
    final window = observation.window;
    if (_closed || window == null || window.bytes.isEmpty) return;
    final next = window.offset + window.bytes.length;
    if (next >= window.availableThrough) return;
    final key = contentReferenceIdentity(observation.source.reference);
    _offsets[key] = next;
    _retireScope();
  }

  void firstWindow(CurrentWindowObservation observation) {
    if (_closed) return;
    _offsets[contentReferenceIdentity(observation.source.reference)] = 0;
    _retireScope();
  }

  void _retireScope() {
    final scope = _scope;
    _scope = null;
    for (final window in _windows.values) {
      // Release no-longer-displayed windows before any native join.
      window.window = null;
      window.error = null;
      final subscription = window.subscription;
      window.subscription = null;
      if (subscription != null) {
        final cancelled = Future<void>.sync(subscription.cancel);
        _cancellations.add(cancelled);
      }
    }
    _windows.clear();
    if (scope == null) return;
    scope.retire(); // Synchronously cancels watch admission/wakes native next.
    _generation++;
    _retiredScopes.add(scope);
    unawaited(_joinRetired());
    // All users of this scope lose eligibility now, even if content/attempt and
    // collection references are unchanged. Joining must not be the first notice.
    _notify();
  }

  Future<void> _joinRetired() {
    final existing = _joining;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _joining = completion.future;
    completion.complete(
      Future<void>.sync(() async {
        try {
          // A scope/cancellation may be retired while an earlier scope.close is
          // awaiting IO. Keep the shared join pending until those new original
          // obligations also finish; do not retry an unresolved failure here.
          while (_retiredScopes.isNotEmpty || _cancellations.isNotEmpty) {
            var failed = false;
            final cancellations = List.of(_cancellations);
            await Future.wait(
              cancellations.map(
                (future) => future.then<void>(
                  (_) {},
                  onError: (Object error, StackTrace _) {
                    failed = true;
                    cleanupError = error;
                  },
                ),
              ),
            );
            for (final scope in List.of(_retiredScopes)) {
              final report = await scope.close();
              if (report.complete) {
                _retiredScopes.remove(scope);
              } else {
                failed = true;
                cleanupError = report;
              }
            }
            if (_retiredScopes.isEmpty) {
              _cancellations.removeAll(cancellations);
            }
            if (failed) break;
          }
        } catch (error) {
          cleanupError = error;
        } finally {
          _joining = null;
          if (!_closed && _retiredScopes.isEmpty && _cancellations.isEmpty) {
            cleanupError = null;
            _reconcile();
          }
          _notify();
        }
      }),
    );
    return completion.future;
  }

  Future<void> retryCleanup() async {
    if (_closed) return;
    await _joinRetired();
    if (_retiredScopes.isEmpty && _cancellations.isEmpty) {
      cleanupError = null;
      _reconcile();
      _notify();
    }
  }

  Future<void> close() {
    if (!_closed) {
      _closed = true;
      _connection?.cancel();
      _connection = null;
      _current = null;
      _explicitSources = const [];
      _offsets.clear();
      _retireScope();
    }
    return _joinRetired();
  }

  @override
  void dispose() {
    assert(_closed);
    super.dispose();
  }
}

final class CurrentWindowObservation implements TimelineCurrentWindowDisplay {
  CurrentWindowObservation({required this.source, required this.offset});
  CurrentWindowSource source;
  @override
  String get id => source.id;
  @override
  ContentRef get reference => source.reference;
  @override
  final int offset;
  @override
  ContentWindow? window;
  @override
  Object? error;
  // The original SDK scope owns actual cancel/join; this is a borrowed handle.
  // ignore: cancel_subscriptions
  StreamSubscription<ContentWindow>? subscription;
}

/// UI-only capability and bounded fallback, shared by previews and plan document.
final class CurrentWindowSource {
  const CurrentWindowSource({
    required this.id,
    required this.reference,
    required this.text,
  });
  final String id;
  final ContentRef reference;
  final String text;
}
