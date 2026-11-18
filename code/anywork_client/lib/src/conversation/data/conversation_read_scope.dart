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
      onCancel: _join,
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
  (Object, StackTrace)? requestError;
  (Object, StackTrace)? subscriptionError;
  (Object, StackTrace)? handleError;
  bool _requested = false;
  bool subscriptionSettled = false;
  bool handleSettled = false;
  bool released = false;

  Object? get error =>
      requestError?.$1 ?? subscriptionError?.$1 ?? handleError?.$1;

  @override
  Stream<ContentWindow> get windows => _output.stream;

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
            if (!_requested && !_output.isClosed) {
              _output.addError(failure, stack);
            }
            unawaited(_settle());
          },
          onDone: () {
            subscriptionSettled = true;
            if (!_output.isClosed) unawaited(_output.close());
            unawaited(_settle());
          },
        );
      } catch (failure, stack) {
        subscriptionSettled = true;
        handleSettled = true;
        if (!_output.isClosed) {
          _output.addError(failure, stack);
          unawaited(_output.close());
        }
        unawaited(_settle());
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
  Future<void> close() => _join();

  Future<void> _join() {
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
                requestError = null;
                handleError = null;
                handleSettled = true;
              },
              onError: (Object failure, StackTrace stack) {
                handleError = (failure, stack);
                handleSettled = true;
              },
            );
        await Future.wait([cancelled, joined]);
        // Stream completion may await this method through onCancel. Native
        // cleanup must not wait for a listener to consume done or resume.
        if (!_output.isClosed) unawaited(_output.close());
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
