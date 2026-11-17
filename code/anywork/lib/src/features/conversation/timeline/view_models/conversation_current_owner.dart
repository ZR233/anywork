import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart';

import '../state/content_reference_identity.dart';
import '../state/timeline_display_diagnostics.dart';

/// Local member disclosure and its original Current body owner.
final class TimelineMemberDisclosure {
  bool expanded = false;
  bool retired = false;
  CurrentAtomBodyOwner? owner;

  void retire() {
    if (retired) return;
    retired = true;
    final original = owner;
    owner = null;
    if (original != null) {
      unawaited(original.close());
      original.dispose();
    }
  }
}

/// Display-owned Current body watches. It keeps only bounded windows and
/// resource handles, never a second atom/history collection or text mirror.
final class CurrentAtomBodyOwner extends ChangeNotifier {
  CurrentAtomBodyOwner(this.reader, {required this.isActive});

  final CurrentReader reader;
  final bool Function() isActive;
  List<CurrentWindowSource> _explicitSources = const [];
  CurrentReadScope? _scope;
  final Map<Object, CurrentWindowObservation> _windows = {};
  final Map<Object, int> _offsets = {};
  final Set<CurrentReadScope> _retiredScopes = {};
  final Set<Future<void>> _cancellations = {};
  Future<void>? _joining;
  int _generation = 1;
  bool _expanded = false;
  bool _closed = false;
  Object? cleanupError;
  String? invalidationNotice;

  bool get isCurrent => !_closed && isActive();
  Iterable<CurrentWindowObservation> get windows =>
      isCurrent ? _windows.values : const [];
  bool get expanded => _expanded;
  int get queryGeneration => _generation;

  /// A mounted, explicitly expanded Current row borrows only the producer's
  /// declared CurrentContentRef values from its bounded atom/head.
  void synchronizeSources(List<CurrentWindowSource> sources) {
    if (_closed) return;
    _explicitSources = List.unmodifiable(sources);
    _expanded = true;
    _reconcile();
  }

  CurrentReadScope get queryScope {
    if (!isCurrent || cleanupError != null) {
      throw const StaleConversationScope();
    }
    return _scope ??= CurrentReadScope(
      threadId: reader.threadId,
      generation: _generation,
      reader: reader,
      isEligible: isCurrent,
    );
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _reconcile() {
    if (!isCurrent || cleanupError != null || _joining != null) return;
    final wanted = <Object, CurrentWindowSource>{
      for (final source in _explicitSources)
        currentContentIdentity(source.reference): source,
    };
    _offsets.removeWhere((key, _) => !wanted.containsKey(key));
    if (wanted.isEmpty && !_expanded) {
      _retireScope();
      return;
    }
    final changed =
        _windows.length != wanted.length ||
        wanted.entries.any((entry) => !_windows.containsKey(entry.key));
    if (changed) {
      final old = {
        for (final entry in _windows.entries)
          entry.key: entry.value.source.reference,
      };
      for (final entry in wanted.entries) {
        final previous = old[entry.key];
        if (previous != null &&
            previous.ownerId == entry.value.reference.ownerId &&
            previous.domain == entry.value.reference.domain &&
            previous.entityId == entry.value.reference.entityId &&
            previous.contentKey == entry.value.reference.contentKey &&
            previous.generation != entry.value.reference.generation) {
          invalidationNotice = '当前内容已更新，原版本已失效';
        }
      }
      _retireScope();
    }
    for (final entry in wanted.entries) {
      final existing = _windows[entry.key];
      if (existing != null) existing.source = entry.value;
    }
    for (final entry in wanted.entries) {
      if (_windows.containsKey(entry.key)) continue;
      try {
        final scope = queryScope;
        final observation = CurrentWindowObservation(
          source: entry.value,
          offset: _offsets[entry.key] ?? 0,
        );
        _windows[entry.key] = observation;
        final handle = scope.watchBody(
          reference: observation.source.reference,
          range: ContentRange(offset: observation.offset, maxBytes: 32 * 1024),
        );
        observation.handle = handle;
        observation.subscription = handle.windows.listen(
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
    CurrentReadScope scope,
    CurrentWindowObservation observation,
    Object key,
  ) =>
      !_closed &&
      scope.isActive &&
      identical(_scope, scope) &&
      identical(_windows[key], observation) &&
      isActive();

  void nextWindow(CurrentWindowObservation observation) {
    final window = observation.window;
    if (_closed || window == null || window.bytes.isEmpty) return;
    final next = window.offset + window.bytes.length;
    if (next >= window.availableThrough) return;
    _offsets[currentContentIdentity(observation.source.reference)] = next;
    _retireScope();
  }

  void firstWindow(CurrentWindowObservation observation) {
    if (_closed) return;
    _offsets[currentContentIdentity(observation.source.reference)] = 0;
    _retireScope();
  }

  void _retireScope() {
    final scope = _scope;
    _scope = null;
    for (final window in _windows.values) {
      window.window = null;
      window.error = null;
      final subscription = window.subscription;
      window.subscription = null;
      if (subscription != null) {
        _cancellations.add(Future<void>.sync(subscription.cancel));
      }
      final handle = window.handle;
      window.handle = null;
      if (handle != null) handle.requestClose();
    }
    _windows.clear();
    if (scope == null) return;
    scope.retire();
    _generation++;
    _retiredScopes.add(scope);
    unawaited(_joinRetired());
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
  CurrentContentRef get reference => source.reference;
  @override
  final int offset;
  @override
  ContentWindow? window;
  @override
  Object? error;
  CurrentBodyWatch? handle;
  // ignore: cancel_subscriptions
  StreamSubscription<ContentWindow>? subscription;
}

/// UI-only borrowed capability from a bounded Current head.
final class CurrentWindowSource {
  const CurrentWindowSource({
    required this.id,
    required this.role,
    required this.reference,
    required this.text,
  });
  final String id;
  final ChatContentRole role;
  final CurrentContentRef reference;
  final String text;
}
