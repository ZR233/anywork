import 'dart:async';
import 'dart:math';

import '../../../conversation_ports.dart';
import '../../../lifecycle.dart'
    show ClientCloseBudget, ClientOwnership, ClientResourceId;
import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/close_report.dart';
import '../domain/content_lifecycle.dart';
import '../domain/conversation_repository.dart';

/// Borrows the original completion reader until the display scope retires.
///
/// Queries start outside the component admission queue. Only an eligible older
/// page is handed to [applyOlder]; late results never mutate a replacement scope.
final class ConversationReadScope implements ConversationQueryScope {
  ConversationReadScope({
    required this.threadId,
    required this.generation,
    required ConversationReader reader,
    required bool Function() isEligible,
    required Future<void> Function(ChatBatch batch) applyOlder,
  }) : _reader = reader,
       _isEligible = isEligible,
       _applyOlder = applyOlder;

  @override
  final String threadId;
  @override
  final int generation;
  final ConversationReader _reader;
  final bool Function() _isEligible;
  final Future<void> Function(ChatBatch batch) _applyOlder;
  final Set<_ContentWatch> _watches = {};
  final Map<Future<void>, ClientResourceId> _pending = {};
  final String _resourceScopeId = _newResourceScopeId();
  int _resourceSequence = 0;
  bool _retired = false;
  Future<ChatBatch>? _older;

  @override
  bool get isActive => !_retired && _isEligible();
  @override
  int get pendingQueries => _pending.length;
  bool get isSettled => _retired && _pending.isEmpty && _watches.isEmpty;

  /// Preserves identities and original failures without mutating the scope.
  CloseReport get cleanupReport => CloseReport(
    unresolved: [
      for (final resourceId in _pending.values)
        UnresolvedResource(
          resourceId: resourceId,
          owner: 'conversation-query:$threadId:$generation',
          attemptId: AttemptId(generation),
          reason: StateError('query still in flight'),
          ownership: ClientOwnership.owned,
          stages: [
            ClientResourceStage(
              owner: 'conversation-query:$threadId:$generation',
              phase: ClientClosePhase.consumer,
              ownership: ClientOwnership.owned,
              pending: true,
            ),
          ],
        ),
      for (final watch in _watches)
        UnresolvedResource(
          resourceId: watch.resourceId,
          owner: 'conversation-watch:$threadId:$generation',
          attemptId: AttemptId(generation),
          reason:
              watch.errors.firstOrNull?.$1 ?? StateError('watch still closing'),
          ownership: ClientOwnership.owned,
          stages: [
            if (watch.requestError case final failure?)
              ClientResourceStage(
                owner: 'conversation-watch:$threadId:$generation',
                phase: ClientClosePhase.closeRequest,
                ownership: ClientOwnership.owned,
                error: failure.$1,
                stackTrace: failure.$2,
              ),
            ClientResourceStage(
              owner: 'conversation-watch:$threadId:$generation',
              phase: ClientClosePhase.consumer,
              ownership: ClientOwnership.owned,
              pending: !watch.subscriptionSettled,
              error: watch.subscriptionError?.$1,
              stackTrace: watch.subscriptionError?.$2,
            ),
            ClientResourceStage(
              owner: 'conversation-watch:$threadId:$generation',
              phase: ClientClosePhase.close,
              ownership: ClientOwnership.owned,
              pending: !watch.handleSettled,
              error: watch.handleError?.$1,
              stackTrace: watch.handleError?.$2,
            ),
          ],
        ),
    ],
  );

  ClientResourceId _allocateResourceId() =>
      ClientResourceId(_resourceScopeId, ++_resourceSequence);

  Future<T> _run<T>(Future<T> Function() operation) {
    if (!isActive) return Future.error(const StaleConversationScope());
    final completion = Completer<T>();
    late final Future<void> joined;
    joined = completion.future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _pending.remove(joined));
    _pending[joined] = _allocateResourceId();
    completion.complete(
      Future<T>.sync(operation).then(
        (value) {
          if (!isActive) throw const StaleConversationScope();
          return value;
        },
        onError: (Object error, StackTrace stack) {
          if (!isActive) throw const StaleConversationScope();
          Error.throwWithStackTrace(error, stack);
        },
      ),
    );
    return completion.future;
  }

  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) {
    if (!isActive) return Future.error(const StaleConversationScope());
    final existing = _older;
    if (existing != null) return existing;
    final completion = Completer<ChatBatch>();
    _older = completion.future;
    completion.complete(
      _run(() async {
        final batch = await _reader.loadOlder(before: before, demand: demand);
        if (!isActive) throw const StaleConversationScope();
        await _applyOlder(batch);
        if (!isActive) throw const StaleConversationScope();
        return batch;
      }),
    );
    unawaited(
      completion.future.then<void>(
        (_) => _older = null,
        onError: (Object _, StackTrace __) => _older = null,
      ),
    );
    return completion.future;
  }

  @override
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  }) => _run(
    () => _reader.listContents(
      itemId: itemId,
      continuation: continuation,
      demand: demand,
    ),
  );

  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) => _run(() => _reader.readContent(reference: reference, range: range));

  @override
  Stream<ContentWindow> watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    late final StreamController<ContentWindow> output;
    _ContentWatch? watch;
    output = StreamController<ContentWindow>(
      onListen: () {
        if (!isActive) {
          output.addError(const StaleConversationScope());
          unawaited(output.close());
          return;
        }
        try {
          final owned = _ContentWatch(reference, output, _allocateResourceId());
          watch = owned;
          _watches.add(owned);
          owned.handle = _reader.watchContent(
            reference: reference,
            range: range,
          );
          owned.subscription = owned.handle!.windows.listen(
            (value) {
              if (isActive && !owned.stopping && !output.isClosed) {
                output.add(value);
              }
            },
            onError: (Object error, StackTrace stack) {
              if (owned.stopping) return;
              if (isActive && !output.isClosed) output.addError(error, stack);
              unawaited(_finishWatchOutput(owned, output));
            },
            onDone: () {
              unawaited(_finishWatchOutput(owned, output));
            },
          );
        } catch (error, stack) {
          if (!output.isClosed) output.addError(error, stack);
          final owned = watch;
          if (owned == null) {
            unawaited(output.close());
          } else {
            unawaited(_finishWatchOutput(owned, output));
          }
        } finally {
          final owned = watch;
          if (owned != null) {
            if (!owned.listening.isCompleted) owned.listening.complete();
            if (!isActive || owned.stopping) _requestWatchClose(owned);
          }
        }
      },
      onCancel: () async {
        final owned = watch;
        if (owned == null) return;
        _requestWatchClose(owned);
        await _cancelWatch(owned);
        if (!owned.sourceEnded) {
          if (owned.errors.firstOrNull case final error?) {
            Error.throwWithStackTrace(error.$1, error.$2);
          }
        }
      },
      onPause: () => watch?.subscription?.pause(),
      onResume: () => watch?.subscription?.resume(),
    );
    return output.stream;
  }

  Future<void> _finishWatchOutput(
    _ContentWatch watch,
    StreamController<ContentWindow> output,
  ) async {
    if (watch.sourceEnded) return;
    watch.sourceEnded = true;
    await _cancelWatch(watch);
    if (isActive && !output.isClosed) {
      for (final error in watch.errors) {
        output.addError(error.$1, error.$2);
      }
    }
    if (!output.isClosed) unawaited(output.close());
  }

  void _requestWatchClose(_ContentWatch watch) {
    watch.stopping = true;
    final handle = watch.handle;
    if (handle == null || watch.released) return;
    try {
      handle.requestClose();
      watch.requestError = null;
    } catch (error, stack) {
      watch.requestError = (error, stack);
    }
  }

  Future<void> _cancelWatch(_ContentWatch watch) {
    if (watch.released) return Future<void>.value();
    _requestWatchClose(watch);
    final existing = watch.cancelling;
    if (existing != null) return existing;
    watch.handleSettled = false;
    final completion = Completer<void>();
    watch.cancelling = completion.future;
    completion.complete(
      Future<void>.sync(() async {
        try {
          await watch.listening.future;
          _requestWatchClose(watch);
          final subscription = watch.subscription;
          final cancelled = watch.subscriptionCancellation ??=
              Future<void>.sync(() async => subscription?.cancel()).then<void>(
                (_) => watch.subscriptionSettled = true,
                onError: (Object error, StackTrace stack) {
                  watch.subscriptionError = (error, stack);
                  watch.subscriptionSettled = true;
                },
              );
          final joined = Future<void>.sync(() async => watch.handle?.close())
              .then<void>(
                (_) {
                  watch.handleError = null;
                  watch.handleSettled = true;
                },
                onError: (Object error, StackTrace stack) {
                  watch.handleError = (error, stack);
                  watch.handleSettled = true;
                },
              );
          await Future.wait([cancelled, joined]);
          if (watch.errors.isEmpty) _releaseWatch(watch);
        } finally {
          watch.cancelling = null;
        }
      }),
    );
    return completion.future;
  }

  void _releaseWatch(_ContentWatch watch) {
    watch.released = true;
    _watches.remove(watch);
  }

  @override
  void retire() {
    if (_retired) return;
    _retired = true;
    for (final watch in List.of(_watches)) {
      unawaited(_cancelWatch(watch));
    }
  }

  @override
  Future<CloseReport> close({ClientCloseBudget? budget}) async {
    retire();
    final pending = <Future<void>>[
      ..._pending.keys,
      for (final watch in List.of(_watches)) _cancelWatch(watch),
    ];
    if (pending.isNotEmpty) {
      if (budget == null) {
        await Future.wait(pending);
      } else if (budget.remaining > Duration.zero) {
        try {
          await Future.wait(pending).timeout(budget.remaining);
        } on TimeoutException {
          // Original operations retain their cleanup responsibility.
        }
      }
    }
    return cleanupReport;
  }
}

/// A pure History query borrow. It never applies pages to a presenter.
final class HistoryReadScope implements HistoryQueryScope {
  HistoryReadScope({
    required this.threadId,
    required this.generation,
    required HistoryReader reader,
    required bool Function() isEligible,
  }) : _reader = reader,
       _isEligible = isEligible;

  final String threadId;
  final int generation;
  final HistoryReader _reader;
  final bool Function() _isEligible;
  final Map<Future<void>, ClientResourceId> _pending = {};
  final String _resourceScopeId = _newResourceScopeId();
  int _resourceSequence = 0;
  bool _retired = false;

  bool get isActive => !_retired && _isEligible();

  CloseReport get cleanupReport => CloseReport(
    unresolved: [
      for (final resourceId in _pending.values)
        UnresolvedResource(
          resourceId: resourceId,
          owner: 'history-query:$threadId:$generation',
          attemptId: AttemptId(generation),
          reason: StateError('history query still in flight'),
          ownership: ClientOwnership.owned,
          stages: [
            ClientResourceStage(
              owner: 'history-query:$threadId:$generation',
              phase: ClientClosePhase.consumer,
              ownership: ClientOwnership.owned,
              pending: true,
            ),
          ],
        ),
    ],
  );

  ClientResourceId _allocateResourceId() =>
      ClientResourceId(_resourceScopeId, ++_resourceSequence);

  Future<T> _run<T>(Future<T> Function() operation) {
    if (!isActive) return Future.error(const StaleConversationScope());
    final completion = Completer<T>();
    late final Future<void> joined;
    joined = completion.future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _pending.remove(joined));
    _pending[joined] = _allocateResourceId();
    completion.complete(
      Future<T>.sync(operation).then(
        (value) {
          if (!isActive) throw const StaleConversationScope();
          return value;
        },
        onError: (Object error, StackTrace stack) {
          if (!isActive) throw const StaleConversationScope();
          Error.throwWithStackTrace(error, stack);
        },
      ),
    );
    return completion.future;
  }

  @override
  Future<HistoryCut> capture() => _run(_reader.capture);

  @override
  Future<HistoryTimelinePage> timelinePage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _run(
    () => _reader.timelinePage(cut: cut, cursor: cursor, demand: demand),
  );

  @override
  Future<HistoryGroupPage> groupPage({
    required String groupId,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _run(
    () => _reader.groupPage(
      groupId: groupId,
      cut: cut,
      cursor: cursor,
      demand: demand,
    ),
  );

  @override
  Future<HistoryTimelinePage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _run(() => _reader.turnsPage(cut: cut, cursor: cursor, demand: demand));

  @override
  Future<HistoryEventDetail> readEvent({
    required String eventId,
    required HistoryDemand demand,
  }) => _run(() => _reader.readEvent(eventId: eventId, demand: demand));

  @override
  Future<HistoryBodyPage> listBodies({
    required String eventId,
    String? cursor,
    required HistoryDemand demand,
  }) => _run(
    () => _reader.listBodies(eventId: eventId, cursor: cursor, demand: demand),
  );

  @override
  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  }) => _run(
    () => _reader.readBody(
      reference: reference,
      offset: offset,
      maxBytes: maxBytes,
    ),
  );

  @override
  void retire() {
    _retired = true;
  }

  @override
  Future<CloseReport> close({ClientCloseBudget? budget}) async {
    retire();
    final pending = List<Future<void>>.of(_pending.keys);
    if (pending.isNotEmpty) {
      if (budget == null) {
        await Future.wait(pending);
      } else if (budget.remaining > Duration.zero) {
        try {
          await Future.wait(pending).timeout(budget.remaining);
        } on TimeoutException {
          // Original reads retain their cleanup responsibility.
        }
      }
    }
    return cleanupReport;
  }
}

/// One Current-owner borrow. Body watches and collection reads are independent.
final class CurrentReadScope implements CurrentQueryScope {
  CurrentReadScope({
    required this.threadId,
    required this.generation,
    required CurrentReader reader,
    required bool Function() isEligible,
  }) : _reader = reader,
       _isEligible = isEligible;

  @override
  final String threadId;
  @override
  final int generation;
  final CurrentReader _reader;
  final bool Function() _isEligible;
  final Set<_ScopedCurrentBodyWatch> _watches = {};
  final Map<Future<void>, ClientResourceId> _pending = {};
  final String _resourceScopeId = _newResourceScopeId();
  int _resourceSequence = 0;
  bool _retired = false;

  @override
  CurrentReader get reader => _reader;

  bool get isActive => !_retired && _isEligible();

  CloseReport get cleanupReport => CloseReport(
    unresolved: [
      for (final resourceId in _pending.values)
        UnresolvedResource(
          resourceId: resourceId,
          owner: 'current-query:$threadId:$generation',
          attemptId: AttemptId(generation),
          reason: StateError('current query still in flight'),
          ownership: ClientOwnership.owned,
          stages: [
            ClientResourceStage(
              owner: 'current-query:$threadId:$generation',
              phase: ClientClosePhase.consumer,
              ownership: ClientOwnership.owned,
              pending: true,
            ),
          ],
        ),
      for (final watch in _watches)
        UnresolvedResource(
          resourceId: watch.resourceId,
          owner: 'current-watch:$threadId:$generation',
          attemptId: AttemptId(generation),
          reason: watch.error ?? StateError('current watch still closing'),
          ownership: ClientOwnership.owned,
          stages: [
            if (watch.openError case final error?)
              ClientResourceStage(
                owner: 'current-watch:$threadId:$generation',
                phase: ClientClosePhase.opening,
                ownership: ClientOwnership.owned,
                error: error.$1,
                stackTrace: error.$2,
              ),
            if (watch.requestError case final error?)
              ClientResourceStage(
                owner: 'current-watch:$threadId:$generation',
                phase: ClientClosePhase.closeRequest,
                ownership: ClientOwnership.owned,
                error: error.$1,
                stackTrace: error.$2,
              ),
            ClientResourceStage(
              owner: 'current-watch:$threadId:$generation',
              phase: ClientClosePhase.consumer,
              ownership: ClientOwnership.owned,
              pending: !watch.subscriptionSettled,
              error: watch.subscriptionError?.$1,
              stackTrace: watch.subscriptionError?.$2,
            ),
            ClientResourceStage(
              owner: 'current-watch:$threadId:$generation',
              phase: ClientClosePhase.close,
              ownership: ClientOwnership.owned,
              pending: !watch.handleSettled,
              error: watch.handleError?.$1,
              stackTrace: watch.handleError?.$2,
            ),
          ],
        ),
    ],
  );

  ClientResourceId _allocateResourceId() =>
      ClientResourceId(_resourceScopeId, ++_resourceSequence);

  Future<T> _run<T>(Future<T> Function() operation) {
    if (!isActive) return Future.error(const StaleConversationScope());
    final completion = Completer<T>();
    late final Future<void> joined;
    joined = completion.future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _pending.remove(joined));
    _pending[joined] = _allocateResourceId();
    completion.complete(
      Future<T>.sync(operation).then(
        (value) {
          if (!isActive) throw const StaleConversationScope();
          return value;
        },
        onError: (Object error, StackTrace stack) {
          if (!isActive) throw const StaleConversationScope();
          Error.throwWithStackTrace(error, stack);
        },
      ),
    );
    return completion.future;
  }

  @override
  Future<CurrentCollectionPage> pageCollection({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) => _run(() async {
    _validateCollection(reference);
    final page = await _reader.pageCollection(
      reference: reference,
      continuation: continuation,
      demand: demand,
    );
    if (page.revision != reference.revision) throw _staleCurrentReference;
    return page;
  });

  @override
  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) => _run(() async {
    _validateBody(reference);
    final window = await _reader.readBody(reference: reference, range: range);
    if (window.generation != reference.generation) {
      throw _staleCurrentReference;
    }
    return window;
  });

  @override
  CurrentBodyWatch watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) {
    if (!isActive) throw const StaleConversationScope();
    _validateBody(reference);
    final owned = _ScopedCurrentBodyWatch(
      this,
      reference,
      _reader.watchBody(reference: reference, range: range),
      _allocateResourceId(),
    );
    _watches.add(owned);
    owned._start();
    return owned;
  }

  void _validateCollection(CurrentCollectionRef reference) {
    if (reference.ownerId.isEmpty ||
        reference.collection.isEmpty ||
        reference.revision < 0) {
      throw _staleCurrentReference;
    }
  }

  void _validateBody(CurrentContentRef reference) {
    if (reference.ownerId.isEmpty ||
        reference.domain.isEmpty ||
        reference.entityId.isEmpty ||
        reference.contentKey.isEmpty ||
        reference.generation.isEmpty) {
      throw _staleCurrentReference;
    }
  }

  void _releaseWatch(_ScopedCurrentBodyWatch watch) {
    watch.released = true;
    _watches.remove(watch);
  }

  @override
  void retire() {
    if (_retired) return;
    _retired = true;
    for (final watch in List.of(_watches)) {
      watch.requestClose();
    }
  }

  @override
  Future<CloseReport> close({ClientCloseBudget? budget}) async {
    retire();
    final pending = <Future<void>>[
      ..._pending.keys,
      for (final watch in List.of(_watches)) watch._settle(),
    ];
    if (pending.isNotEmpty) {
      if (budget == null) {
        await Future.wait(pending);
      } else if (budget.remaining > Duration.zero) {
        try {
          await Future.wait(pending).timeout(budget.remaining);
        } on TimeoutException {
          // Original operations retain their cleanup responsibility.
        }
      }
    }
    return cleanupReport;
  }
}

final class _ContentWatch {
  _ContentWatch(this.reference, this.output, this.resourceId);

  final ClientResourceId resourceId;
  final ContentRef reference;
  final StreamController<ContentWindow> output;
  final Completer<void> listening = Completer<void>();
  ConversationContentWatch? handle;
  // ignore: cancel_subscriptions
  StreamSubscription<ContentWindow>? subscription;
  Future<void>? subscriptionCancellation;
  Future<void>? cancelling;
  (Object, StackTrace)? requestError;
  (Object, StackTrace)? subscriptionError;
  (Object, StackTrace)? handleError;
  bool subscriptionSettled = false;
  bool handleSettled = false;
  bool stopping = false;
  bool sourceEnded = false;
  bool released = false;

  Iterable<(Object, StackTrace)> get errors => [
    ?requestError,
    ?subscriptionError,
    ?handleError,
  ];
}

final class _ScopedCurrentBodyWatch implements CurrentBodyWatch {
  _ScopedCurrentBodyWatch(
    this.scope,
    this.reference,
    this.opening,
    this.resourceId,
  ) {
    _output = StreamController<ContentWindow>(
      onPause: () => _subscription?.pause(),
      onResume: () => _subscription?.resume(),
      onCancel: () => _join(closeOutput: false),
    );
  }

  final CurrentReadScope scope;
  final CurrentContentRef reference;
  final Future<CurrentBodyWatch> opening;
  final ClientResourceId resourceId;
  late final StreamController<ContentWindow> _output;
  CurrentBodyWatch? _handle;
  // ignore: cancel_subscriptions
  StreamSubscription<ContentWindow>? _subscription;
  Future<void>? _openingTask;
  Future<void>? _cancelling;
  Future<void>? _subscriptionCancellation;
  (Object, StackTrace)? openError;
  (Object, StackTrace)? requestError;
  (Object, StackTrace)? subscriptionError;
  (Object, StackTrace)? handleError;
  bool _requested = false;
  bool subscriptionSettled = false;
  bool handleSettled = false;
  bool released = false;

  Object? get error =>
      openError?.$1 ??
      requestError?.$1 ??
      subscriptionError?.$1 ??
      handleError?.$1;

  @override
  Stream<ContentWindow> get windows {
    if (_output.isClosed) return const Stream.empty();
    return _output.stream;
  }

  void _start() {
    _openingTask ??= Future<void>.sync(() async {
      try {
        final handle = await opening;
        _handle = handle;
        if (_requested) {
          try {
            handle.requestClose();
            requestError = null;
          } catch (failure, stack) {
            requestError = (failure, stack);
          }
        }
        if (_output.isClosed) return;
        _subscription = handle.windows.listen(
          (window) {
            if (window.generation != reference.generation) {
              if (!_requested && !_output.isClosed) {
                _output.addError(_staleCurrentReference, StackTrace.current);
              }
              unawaited(_settle());
              return;
            }
            if (!_requested && !_output.isClosed) _output.add(window);
          },
          onError: (Object failure, StackTrace stack) {
            subscriptionError = (failure, stack);
            if (!_requested && !_output.isClosed) {
              _output.addError(failure, stack);
            }
            unawaited(_settle());
          },
          onDone: () {
            subscriptionSettled = true;
            if (!_output.isClosed) unawaited(_output.close());
          },
        );
      } catch (failure, stack) {
        openError = (failure, stack);
        handleSettled = true;
        if (!_output.isClosed) {
          _output.addError(failure, stack);
          await _output.close();
        }
      }
    });
    unawaited(_openingTask);
  }

  @override
  void requestClose() {
    if (_requested) return;
    _requested = true;
    _start();
    final handle = _handle;
    if (handle == null || released) return;
    try {
      handle.requestClose();
      requestError = null;
    } catch (failure, stack) {
      requestError = (failure, stack);
    }
  }

  Future<void> _settle() async {
    try {
      await close();
    } catch (_) {
      // The original failure remains in this watch's cleanup report.
    }
  }

  @override
  Future<void> close() => _join(closeOutput: true);

  Future<void> _join({required bool closeOutput}) {
    if (released) return Future<void>.value();
    requestClose();
    return _cancelling ??= Future<void>.sync(() async {
      try {
        await _openingTask;
        final subscription = _subscription;
        final cancelled = _subscriptionCancellation ??=
            Future<void>.sync(() async => subscription?.cancel()).then<void>(
              (_) {
                subscriptionSettled = true;
              },
              onError: (Object failure, StackTrace stack) {
                subscriptionError = (failure, stack);
                subscriptionSettled = true;
              },
            );
        final handle = _handle;
        final joined = Future<void>.sync(() async => handle?.close())
            .then<void>(
              (_) {
                handleError = null;
                handleSettled = true;
              },
              onError: (Object failure, StackTrace stack) {
                handleError = (failure, stack);
                handleSettled = true;
              },
            );
        await Future.wait([cancelled, joined]);
        if (closeOutput && !_output.isClosed) await _output.close();
        if (error == null) scope._releaseWatch(this);
      } finally {
        _cancelling = null;
      }
    });
  }
}

String _newResourceScopeId() {
  final random = Random.secure();
  final nonce = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'conversation-query-$nonce';
}

const _staleCurrentReference = StudioFailure(
  code: StudioFailureCode.staleRevision,
  reason: StudioFailureReason.staleCurrentReference,
  message: 'The Current owner, collection revision, or body generation expired',
  retryable: false,
  correlationId: 'client-stale-current-reference',
);
