import 'dart:async';

import '../../../anywork_client.dart'
    show
        CloseReport,
        AttemptId,
        LatestValue,
        UnresolvedResource,
        ValueObservation;
import '../../../directory_ports.dart';
import '../../../models.dart';

typedef _Open<T> = Future<_NativeObservation<T>> Function();
typedef _Validate<T> = void Function(T frame);
typedef _Accept<T> = void Function(T frame);

StudioFailure _protocolFailure(String message) => StudioFailure(
  code: StudioFailureCode.protocol,
  message: message,
  retryable: false,
  correlationId: 'client-thread-directory-protocol',
);

final class ThreadDirectoryStore {
  ThreadDirectoryStore({
    required DirectoryFeedPort feed,
    void Function(ResourceStamp stamp)? onStamp,
    void Function(UnresolvedResource failure)? onCleanupFailure,
  }) : _feed = feed,
       _onStamp = onStamp,
       _onCleanupFailure = onCleanupFailure;

  final DirectoryFeedPort _feed;
  final void Function(ResourceStamp stamp)? _onStamp;
  final void Function(UnresolvedResource failure)? _onCleanupFailure;
  final Map<_ThreadsDemand, _DirectorySlot<ThreadDirectoryFrame>> _threads = {};
  final Map<String, _DirectorySlot<ThreadMetadataFrame>> _metadata = {};
  final Set<_DirectorySlot<Object?>> _retiring = {};
  bool _sealed = false;

  /// One-shot diagnostics over the actual bounded list demands currently held.
  Iterable<ThreadDirectoryFrame> get observedWindows sync* {
    for (final slot in _threads.values) {
      final frame = slot.frame;
      if (frame != null) yield frame;
    }
  }

  /// Borrows metadata only from an active exact-ID observation already held by
  /// a consumer. This neither opens a demand nor searches list windows.
  SessionDirectoryRow? observedThread(String threadId) =>
      _metadata[threadId]?.frame?.row;

  DirectoryObservation<ThreadDirectoryFrame> observeThreads(
    DirectoryQuery query,
    DirectoryWindow window,
  ) {
    if (_sealed) throw StateError('Thread directory observations are closed');
    final demand = _ThreadsDemand(query, window);
    final slot = _threads.putIfAbsent(demand, () {
      return _DirectorySlot<ThreadDirectoryFrame>(
        owner: this,
        label: 'threads:$query:$window',
        open: () async {
          final handle = await _feed.openThreadsObservation(query, window);
          return _ThreadsNative(handle);
        },
        validate: (frame) {
          if (frame.query != query || frame.window != window) {
            throw _protocolFailure(
              'Thread directory observation demand mismatch',
            );
          }
          if (frame.stamp.resourceKey != 'thread-directory') {
            throw _protocolFailure(
              'Thread directory observation resource mismatch',
            );
          }
          if (frame.threadIds.length > window.limit) {
            throw _protocolFailure('Thread directory frame exceeds its window');
          }
        },
        onAccept: (frame) => _onStamp?.call(frame.stamp),
      )..start();
    });
    return slot.borrow();
  }

  DirectoryObservation<ThreadMetadataFrame> observeThread(String threadId) {
    if (_sealed) throw StateError('Thread directory observations are closed');
    if (threadId.isEmpty) throw ArgumentError.value(threadId, 'threadId');
    final slot = _metadata.putIfAbsent(threadId, () {
      return _DirectorySlot<ThreadMetadataFrame>(
        owner: this,
        label: 'thread:$threadId',
        open: () async {
          final handle = await _feed.openThreadObservation(threadId);
          return _ThreadNative(handle);
        },
        validate: (frame) {
          if (frame.threadId != threadId ||
              frame.stamp.resourceKey != 'thread-directory') {
            throw _protocolFailure(
              'Thread metadata observation identity mismatch',
            );
          }
          if (frame.row != null && frame.row!.threadId != threadId) {
            throw _protocolFailure('Thread metadata frame row mismatch');
          }
        },
        onAccept: (frame) => _onStamp?.call(frame.stamp),
      )..start();
    });
    return slot.borrow();
  }

  Future<CloseReport> close() {
    _sealed = true;
    final slots = <_DirectorySlot<Object?>>{
      ..._retiring,
      ..._threads.values,
      ..._metadata.values,
    };
    for (final slot in slots) {
      slot.requestRetire();
    }
    return retryCleanup();
  }

  /// Retries only native owners already retiring after an earlier close failure.
  ///
  /// Runtime cleanup must not seal admission for unrelated or replacement
  /// observations.
  Future<CloseReport> retryCleanup() async {
    final slots = Set<_DirectorySlot<Object?>>.of(_retiring);
    final unresolved = <UnresolvedResource>[];
    for (final slot in slots) {
      try {
        await slot.retire();
      } catch (error) {
        unresolved.add(slot.unresolved(error));
      }
    }
    return CloseReport(unresolved: unresolved);
  }

  void _beginRetire(_DirectorySlot<Object?> slot) {
    _threads.removeWhere((_, candidate) => identical(candidate, slot));
    _metadata.removeWhere((_, candidate) => identical(candidate, slot));
    _retiring.add(slot);
  }

  void _settled(_DirectorySlot<Object?> slot) => _retiring.remove(slot);

  void _cleanupFailed(UnresolvedResource failure) {
    _onCleanupFailure?.call(failure);
  }
}

final class _ThreadsDemand {
  const _ThreadsDemand(this.query, this.window);
  final DirectoryQuery query;
  final DirectoryWindow window;

  @override
  bool operator ==(Object other) =>
      other is _ThreadsDemand && query == other.query && window == other.window;

  @override
  int get hashCode => Object.hash(query, window);
}

final class _DirectorySlot<T> {
  _DirectorySlot({
    required this.owner,
    required this.label,
    required this.open,
    required this.validate,
    required this.onAccept,
  });

  final ThreadDirectoryStore owner;
  final String label;
  final _Open<T> open;
  final _Validate<T> validate;
  final _Accept<T> onAccept;
  final LatestValue<DirectoryObservationState<T>> source = LatestValue(
    const DirectoryObservationState(),
  );
  _DirectoryAttempt<T>? _attempt;
  Future<void>? _transition;
  Future<void>? _closing;
  int _generation = 0;
  int _borrowers = 0;
  bool _retiring = false;
  bool _settled = false;

  T? get frame => _retiring ? null : source.value.frame;

  void start() {
    _attempt = _DirectoryAttempt(this, ++_generation)..start();
  }

  DirectoryObservation<T> borrow() {
    if (_retiring) throw StateError('Directory observation is retiring');
    _borrowers += 1;
    return _DirectoryBorrow<T>(this);
  }

  void accept(int generation, T frame) {
    if (_retiring || generation != _generation) return;
    validate(frame);
    onAccept(frame);
    source.publish(DirectoryObservationState(frame: frame, isLoading: false));
  }

  void failed(int generation, Object error) {
    if (_retiring || generation != _generation) return;
    source.publish(
      DirectoryObservationState(
        frame: source.value.frame,
        isLoading: false,
        error: error is StudioFailure
            ? error
            : const StudioFailure(
                code: StudioFailureCode.internal,
                message: 'Thread directory observation failed',
                retryable: true,
                correlationId: 'thread-directory-observation',
              ),
      ),
    );
  }

  Future<void> refresh() {
    if (_retiring) {
      return Future.error(StateError('Directory observation is closed'));
    }
    final existing = _transition;
    if (existing != null) return existing;
    source.publish(
      DirectoryObservationState(frame: source.value.frame, isLoading: true),
    );
    final previous = _attempt;
    previous?.requestClose();
    final transition = () async {
      if (previous != null) await previous.close();
      if (_retiring) return;
      _attempt = _DirectoryAttempt(this, ++_generation)..start();
    }();
    _transition = transition;
    unawaited(
      transition.then<void>(
        (_) => _transition = null,
        onError: (Object error, StackTrace _) {
          _transition = null;
          failed(_generation, error);
        },
      ),
    );
    return transition;
  }

  void release() {
    if (_borrowers == 0) return;
    _borrowers -= 1;
    if (_borrowers == 0) requestRetire();
  }

  void requestRetire() {
    if (_retiring) return;
    _retiring = true;
    owner._beginRetire(this as _DirectorySlot<Object?>);
    _attempt?.requestClose();
  }

  Future<void> retire() {
    if (_settled) return Future.value();
    final existing = _closing;
    if (existing != null) return existing;
    requestRetire();
    final operation = () async {
      final transition = _transition;
      if (transition != null) await transition;
      final attempt = _attempt;
      if (attempt != null) await attempt.close();
      _settled = true;
      source.publish(
        DirectoryObservationState(
          isLoading: false,
          error: source.value.error,
          closed: true,
        ),
      );
      owner._settled(this as _DirectorySlot<Object?>);
    }();
    final tracked = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _closing = null;
        owner._cleanupFailed(unresolved(error));
        Error.throwWithStackTrace(error, stack);
      },
    );
    _closing = tracked;
    return tracked;
  }

  UnresolvedResource unresolved(Object error) => UnresolvedResource(
    owner: 'thread-directory:$label',
    attemptId: const AttemptId(0),
    reason: error,
  );
}

final class _DirectoryBorrow<T> implements DirectoryObservation<T> {
  _DirectoryBorrow(this._slot);
  final _DirectorySlot<T> _slot;
  Future<void>? _releasing;

  @override
  ValueObservation<DirectoryObservationState<T>> get state => _slot.source;

  @override
  Future<void> release() {
    final existing = _releasing;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _releasing = completion.future;
    completion.complete(
      Future<void>.sync(() {
        _slot.release();
        if (_slot._retiring) return _slot.retire();
      }),
    );
    return completion.future;
  }

  @override
  Future<void> refresh() {
    if (_releasing != null) {
      return Future.error(
        StateError('Directory observation demand is released'),
      );
    }
    return _slot.refresh();
  }
}

final class _DirectoryAttempt<T> {
  _DirectoryAttempt(this.slot, this.generation);
  final _DirectorySlot<T> slot;
  final int generation;
  _NativeObservation<T>? _handle;
  final Completer<void> _consumer = Completer<void>();
  Future<void>? _closing;
  bool _stop = false;
  bool _settled = false;

  void start() {
    unawaited(
      _run().then<void>(
        (_) => _consumer.complete(),
        onError: (Object error, StackTrace _) {
          slot.failed(generation, error);
          _consumer.complete();
          requestClose();
        },
      ),
    );
  }

  Future<void> _run() async {
    final handle = await slot.open();
    _handle = handle;
    if (_stop) {
      handle.requestClose();
      return;
    }
    while (!_stop) {
      final frame = await handle.next();
      if (frame == null) {
        if (!_stop) {
          throw StateError('Directory observation ended without close');
        }
        return;
      }
      // A completed next racing close is still accepted for this exact demand.
      slot.accept(generation, frame);
    }
  }

  void requestClose() {
    _stop = true;
    _handle?.requestClose();
  }

  Future<void> close() {
    if (_settled) return Future.value();
    final existing = _closing;
    if (existing != null) return existing;
    requestClose();
    final operation = () async {
      await _consumer.future;
      final handle = _handle;
      if (handle != null) await handle.close();
      _settled = true;
    }();
    final tracked = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _closing = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
    _closing = tracked;
    return tracked;
  }
}

abstract interface class _NativeObservation<T> {
  Future<T?> next();
  void requestClose();
  Future<void> close();
}

final class _ThreadsNative implements _NativeObservation<ThreadDirectoryFrame> {
  const _ThreadsNative(this.handle);
  final ThreadsObservationHandle handle;

  @override
  Future<ThreadDirectoryFrame?> next() => handle.next();
  @override
  void requestClose() => handle.requestClose();
  @override
  Future<void> close() => handle.close();
}

final class _ThreadNative implements _NativeObservation<ThreadMetadataFrame> {
  const _ThreadNative(this.handle);
  final ThreadObservationHandle handle;

  @override
  Future<ThreadMetadataFrame?> next() => handle.next();
  @override
  void requestClose() => handle.requestClose();
  @override
  Future<void> close() => handle.close();
}
