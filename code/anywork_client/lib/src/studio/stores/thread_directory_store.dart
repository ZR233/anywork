import 'dart:async';

import '../../../anywork_client.dart'
    show
        CloseReport,
        AttemptId,
        LatestValue,
        UnresolvedResource,
        ValueObservation;
import '../../../directory_ports.dart';
import '../../../lifecycle.dart';
import '../../../models.dart';

typedef _Open<T> = Future<_NativeObservation<T>> Function(
  ClientOperation operation,
);
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
    required ClientScope scope,
    void Function(ResourceStamp stamp)? onStamp,
    void Function(UnresolvedResource failure)? onCleanupFailure,
  }) : _feed = feed,
       _scope = scope,
       _onStamp = onStamp,
       _onCleanupFailure = onCleanupFailure;

  final DirectoryFeedPort _feed;
  final ClientScope _scope;
  final void Function(ResourceStamp stamp)? _onStamp;
  final void Function(UnresolvedResource failure)? _onCleanupFailure;
  final Map<_ThreadsDemand, _DirectorySlot<ThreadDirectoryFrame>> _threads = {};
  final Map<String, _DirectorySlot<ThreadMetadataFrame>> _metadata = {};
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
    var slot = _threads[demand];
    if (slot == null || slot._retiring) {
      final previous = slot?.currentSource;
      slot = _DirectorySlot<ThreadDirectoryFrame>(
        owner: this,
        label: 'threads:$query:$window',
        predecessor: previous,
        open: (operation) async {
          final handle = await _feed.openThreadsObservation(
            query,
            window,
            resourceId: operation.resourceId,
          );
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
      );
      _threads[demand] = slot;
      slot.start();
    }
    return slot.borrow();
  }

  DirectoryObservation<ThreadMetadataFrame> observeThread(String threadId) {
    if (_sealed) throw StateError('Thread directory observations are closed');
    if (threadId.isEmpty) throw ArgumentError.value(threadId, 'threadId');
    var slot = _metadata[threadId];
    if (slot == null || slot._retiring) {
      final previous = slot?.currentSource;
      slot = _DirectorySlot<ThreadMetadataFrame>(
        owner: this,
        label: 'thread:$threadId',
        predecessor: previous,
        open: (operation) async {
          final handle = await _feed.openThreadObservation(
            threadId,
            resourceId: operation.resourceId,
          );
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
      );
      _metadata[threadId] = slot;
      slot.start();
    }
    return slot.borrow();
  }

  Future<CloseReport> close({required ClientCloseBudget budget}) {
    _sealed = true;
    final slots = <_DirectorySlot<Object?>>{
      ..._threads.values,
      ..._metadata.values,
    };
    for (final slot in slots) {
      slot.requestRetire();
    }
    return _scope.close(budget: budget);
  }

  /// Retries only native owners already retiring after an earlier close failure.
  ///
  /// Runtime cleanup must not seal admission for unrelated or replacement
  /// observations.
  Future<CloseReport> retryCleanup({required ClientCloseBudget budget}) async {
    final report = await _scope.retryCleanup(budget: budget);
    for (final slot in <_DirectorySlot<Object?>>{
      ..._threads.values,
      ..._metadata.values,
    }) {
      if (!slot._retiring && slot._predecessor != null) slot.start();
    }
    return report;
  }

  void _settled(_DirectorySlot<Object?> slot) {
    _threads.removeWhere((_, candidate) => identical(candidate, slot));
    _metadata.removeWhere((_, candidate) => identical(candidate, slot));
  }

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
    _DirectorySource<T>? predecessor,
  }) : _predecessor = predecessor;

  final ThreadDirectoryStore owner;
  final String label;
  final _Open<T> open;
  final _Validate<T> validate;
  final _Accept<T> onAccept;
  final LatestValue<DirectoryObservationState<T>> source = LatestValue(
    const DirectoryObservationState(),
  );
  _DirectorySource<T>? _current;
  _DirectorySource<T>? _predecessor;
  Future<void>? _transition;
  int _generation = 0;
  int _borrowers = 0;
  bool _retiring = false;

  _DirectorySource<T>? get currentSource => _current ?? _predecessor;

  T? get frame => _retiring ? null : source.value.frame;

  void start() {
    if (_predecessor != null) {
      unawaited(
        refresh().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    } else {
      _open();
    }
  }

  void _open() {
    if (_retiring || owner._sealed) return;
    final generation = ++_generation;
    final current = _current = _DirectorySource<T>();
    current.acquisition = owner._scope.open<_NativeObservation<T>>(
      'thread-directory:$label',
      (operation) {
        current.resourceId = operation.resourceId;
        return open(operation);
      },
      ownership: ClientOwnership.proxy,
      consume: (handle, operation) async {
        while (!operation.closeRequested) {
          final frame = await handle.next();
          if (frame == null) {
            if (!operation.closeRequested) {
              throw StateError('Directory observation ended without close');
            }
            return;
          }
          // Do not drop a next that already completed before requestClose.
          accept(generation, frame);
        }
      },
      onFailure: (error, stack) => failed(generation, error),
    );
    if (_retiring || owner._sealed) current.requestClose();
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
    final previous = currentSource;
    final completion = Completer<void>();
    final transition = _transition = completion.future;
    unawaited(
      transition.then<void>(
        (_) {
          if (identical(_transition, transition)) _transition = null;
        },
        onError: (Object error, StackTrace _) {
          if (identical(_transition, transition)) _transition = null;
          failed(_generation, error);
        },
      ),
    );
    completion.complete(
      Future<void>.sync(() async {
        source.publish(
          DirectoryObservationState(frame: source.value.frame, isLoading: true),
        );
        previous?.requestClose();
        if (previous != null) await previous.close();
        if (_retiring || owner._sealed) return;
        _predecessor = null;
        _open();
      }),
    );
    return transition;
  }

  _DirectorySource<T>? release() {
    if (_borrowers == 0) return null;
    _borrowers -= 1;
    if (_borrowers != 0) return null;
    // This is the synchronous domain decision. The lease captures identity
    // before requestClose can synchronously admit a replacement demand.
    _retiring = true;
    return currentSource;
  }

  void requestRetire() {
    _retiring = true;
    currentSource?.requestClose();
  }

  Future<void> retire(_DirectorySource<T>? retirement, {bool retry = false}) {
    requestRetire();
    final closing = retirement == null
        ? Future<void>.value()
        : retirement.close(retry: retry);
    return closing.then<void>(
      (_) {
        owner._settled(this as _DirectorySlot<Object?>);
        source.publish(
          DirectoryObservationState(
            isLoading: false,
            error: source.value.error,
            closed: true,
          ),
        );
      },
      onError: (Object error, StackTrace stack) {
        final resourceId = retirement?.resourceId;
        try {
          if (resourceId != null) {
            owner._cleanupFailed(
              UnresolvedResource(
                resourceId: resourceId,
                owner: 'thread-directory:$label',
                attemptId: const AttemptId(0),
                reason: error,
              ),
            );
          }
        } finally {
          // No source identity means there is no source report to publish.
          // The lease entry still observes this original release failure, even
          // if a diagnostic callback itself throws during synchronous delivery.
          Error.throwWithStackTrace(error, stack);
        }
      },
    );
  }
}

final class _DirectoryBorrow<T> implements DirectoryObservation<T> {
  _DirectoryBorrow(this._slot);
  final _DirectorySlot<T> _slot;
  bool _released = false;
  bool _lastBorrower = false;
  _DirectorySource<T>? _retirement;
  List<ClientResourceId> _retirementResourceIds = const [];
  Future<void>? _releasing;

  @override
  List<ClientResourceId> get retirementResourceIds => _retirementResourceIds;

  @override
  ValueObservation<DirectoryObservationState<T>> get state => _slot.source;

  @override
  Future<void> release() {
    final existing = _releasing;
    if (existing != null) return existing;
    final retry = _released;
    if (!_released) {
      _released = true;
      _retirement = _slot.release();
      _lastBorrower = _slot._borrowers == 0;
      _retirementResourceIds = List.unmodifiable([
        if (_retirement?.resourceId case final resourceId?)
          if (_retirement?.acquisition?.isClosed != true) resourceId,
      ]);
    }
    final completion = Completer<void>();
    _releasing = completion.future;
    completion.complete(
      _lastBorrower
          ? _slot.retire(_retirement, retry: retry)
          : Future<void>.value(),
    );
    unawaited(
      completion.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) => _releasing = null,
      ),
    );
    return completion.future;
  }

  @override
  Future<void> refresh() {
    if (_released) {
      return Future.error(
        StateError('Directory observation demand is released'),
      );
    }
    return _slot.refresh();
  }
}

// A domain identity reference, not a second lifecycle owner. It is installed
// before factory callbacks can reenter refresh/release; all work is delegated to
// the one scope acquisition once open returns it in the same synchronous turn.
final class _DirectorySource<T> {
  ClientResourceId? resourceId;
  ClientAcquisition<_NativeObservation<T>>? acquisition;

  void requestClose() => acquisition?.requestClose();

  Future<void> close({bool retry = false}) {
    Future<void> closeSource() {
      final entry = acquisition;
      if (entry == null) {
        if (resourceId != null) {
          throw StateError(
            'Directory acquisition registration did not complete',
          );
        }
        return Future<void>.value();
      }
      entry.requestClose();
      return retry ? entry.retryClose() : entry.close();
    }

    return acquisition == null
        ? Future<void>.microtask(closeSource)
        : closeSource();
  }
}

abstract interface class _NativeObservation<T> implements ClientResource {
  Future<T?> next();
}

final class _ThreadsNative implements _NativeObservation<ThreadDirectoryFrame> {
  const _ThreadsNative(this.handle);
  final ThreadsObservationHandle handle;

  @override
  ClientResourceId get resourceId => handle.resourceId;
  @override
  Future<ThreadDirectoryFrame?> next() => handle.next();
  @override
  void requestClose() => handle.requestClose();
  @override
  Future<void> close() => handle.close();
  @override
  Future<void> retryClose() => handle.retryClose();
}

final class _ThreadNative implements _NativeObservation<ThreadMetadataFrame> {
  const _ThreadNative(this.handle);
  final ThreadObservationHandle handle;

  @override
  ClientResourceId get resourceId => handle.resourceId;
  @override
  Future<ThreadMetadataFrame?> next() => handle.next();
  @override
  void requestClose() => handle.requestClose();
  @override
  Future<void> close() => handle.close();
  @override
  Future<void> retryClose() => handle.retryClose();
}
