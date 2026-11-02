import 'dart:async';

import '../../../conversation_ports.dart';
import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';
import '../domain/content_lifecycle.dart';
import '../domain/conversation_repository.dart';

/// Borrows the original feed's reader. Retiring this display scope cancels its
/// watches and rejects late results, but never closes a sibling's read lease.
final class ConversationReadScope implements ConversationQueryScope {
  ConversationReadScope({
    required this.threadId,
    required this.generation,
    required ConversationReader reader,
    required ResourceBudget budget,
    required bool Function() isEligible,
    required Future<void> Function(ChatBatch) applyOlder,
  }) : _reader = reader,
       _budget = budget,
       _isEligible = isEligible,
       _applyOlder = applyOlder;

  @override
  final String threadId;
  @override
  final int generation;
  final ConversationReader _reader;
  final ResourceBudget _budget;
  final bool Function() _isEligible;
  final Future<void> Function(ChatBatch) _applyOlder;
  final Set<Future<void>> _pending = {};
  final Set<_ContentWatch> _watches = {};
  bool _retired = false;
  int _sequence = 0;
  Future<ChatBatch>? _older;

  @override
  bool get isActive => !_retired && _isEligible();
  @override
  int get pendingQueries => _pending.length;
  bool get isSettled => _retired && _pending.isEmpty && _watches.isEmpty;

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
        // Start native IO outside the serial component admission queue.
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
  Future<ChatBatch> readBefore({
    required int completionSeq,
    String? before,
    required ReadDemand demand,
  }) => _run(
    () => _reader.readBefore(
      completionSeq: completionSeq,
      before: before,
      demand: demand,
    ),
  );

  @override
  Future<ChatBatch> readAt({
    required int completionSeq,
    String? before,
    required ReadDemand demand,
  }) => _run(
    () => _reader.readAt(
      completionSeq: completionSeq,
      before: before,
      demand: demand,
    ),
  );

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
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) => _run(
    () => _reader.pageCurrent(
      reference: reference,
      continuation: continuation,
      demand: demand,
    ),
  );

  Future<T> _run<T>(Future<T> Function() operation) {
    if (!isActive) return Future.error(const StaleConversationScope());
    final permit = _budget.acquire(
      ResourceKind.pendingOperation,
      owner: 'chat-query:$threadId:$generation:${++_sequence}',
    );
    final completion = Completer<T>();
    late final Future<void> joined;
    joined = completion.future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() {
          _pending.remove(joined);
          permit.release();
        });
    _pending.add(joined);
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
          final owned = _ContentWatch(
            _budget.acquire(
              ResourceKind.pendingOperation,
              owner: 'chat-watch:$threadId:$generation:${++_sequence}',
            ),
          );
          watch = owned;
          _watches.add(owned);
          owned.handle = _reader.watchContent(
            reference: reference,
            range: range,
          );
          owned.subscription = owned.handle!.windows.listen(
            (value) {
              if (isActive && !owned.stopping) output.add(value);
            },
            onError: (Object error, StackTrace stack) {
              if (owned.stopping) return;
              if (isActive) output.addError(error, stack);
              // A terminal read error need not be followed by EOF. Retire the
              // exact transport watch immediately and retain failed join IO.
              unawaited(_finishWatchOutput(owned, output));
            },
            onDone: () {
              // EOF ends delivery, not ownership of the original native
              // watch. A failed join must remain retryable after onDone.
              unawaited(_finishWatchOutput(owned, output));
            },
          );
        } catch (error, stack) {
          output.addError(error, stack);
          final owned = watch;
          if (owned == null) {
            // Admission failed before a permit/handle existed. Keep the
            // original error on this Stream, not its listener's uncaught Zone.
            unawaited(output.close());
          } else {
            unawaited(_finishWatchOutput(owned, output));
          }
        } finally {
          final owned = watch;
          if (owned != null) {
            owned.listening.complete();
            if (!isActive || owned.stopping) _requestWatchClose(owned);
          }
        }
      },
      onCancel: () async {
        final owned = watch;
        if (owned == null) return;
        _requestWatchClose(owned);
        await (owned.cancelling ??
            owned.lastCancellation ??
            _cancelWatch(owned));
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

  void _releaseWatch(_ContentWatch watch) {
    watch.released = true;
    watch.permit.release();
    _watches.remove(watch);
  }

  Future<void> _finishWatchOutput(
    _ContentWatch watch,
    StreamController<ContentWindow> output,
  ) async {
    if (watch.sourceEnded) return;
    watch.sourceEnded = true;
    await _cancelWatch(watch);
    // Native EOF is not evidence of successful teardown. Deliver its actual
    // failure before done, while the original scope retains retry ownership.
    if (isActive && !output.isClosed) {
      for (final error in watch.errors) {
        output.addError(error.$1, error.$2);
      }
    }
    unawaited(output.close());
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
      watch.permit.mark(ResourcePhase.unresolved);
    }
  }

  Future<void> _cancelWatch(_ContentWatch watch) {
    if (watch.released) return Future.value();
    // Synchronous wake precedes every await, including a late-open/listen join.
    _requestWatchClose(watch);
    final existing = watch.cancelling;
    if (existing != null) return existing;
    final completion = Completer<void>();
    watch.cancelling = completion.future;
    watch.lastCancellation = completion.future;
    completion.complete(
      Future<void>.sync(() async {
        try {
          await watch.listening.future;
          _requestWatchClose(watch);
          final subscription = watch.subscription;
          // Dart cancel may cache its Future. Call it exactly once and retain an
          // independent cancellation failure; native close cannot erase it.
          final cancelled = watch.subscriptionCancellation ??=
              Future<void>.sync(() async => subscription?.cancel()).then<void>(
                (_) {},
                onError: (Object error, StackTrace stack) {
                  watch.subscriptionError = (error, stack);
                },
              );
          final handle = watch.handle;
          // Unlike StreamSubscription.cancel, this is the explicit retryable
          // transport join on the very same watch capability.
          final joined = Future<void>.sync(() async => handle?.close())
              .then<void>(
                (_) => watch.handleError = null,
                onError: (Object error, StackTrace stack) {
                  watch.handleError = (error, stack);
                },
              );
          await Future.wait([cancelled, joined]);
          if (watch.errors.isEmpty) {
            _releaseWatch(watch);
          } else {
            watch.permit.mark(ResourcePhase.unresolved);
          }
        } finally {
          watch.cancelling = null;
        }
      }),
    );
    return completion.future;
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
  Future<CloseReport> close({DateTime? deadline}) async {
    retire();
    final pending = [
      ..._pending,
      for (final watch in List.of(_watches)) _cancelWatch(watch),
    ];
    if (pending.isNotEmpty) {
      if (deadline == null) {
        await Future.wait(pending);
      } else {
        final remaining = deadline.difference(DateTime.now());
        if (remaining > Duration.zero) {
          try {
            await Future.wait(pending).timeout(remaining);
          } on TimeoutException {
            /* Original operations retain their permits. */
          }
        }
      }
    }
    return CloseReport(
      unresolved: [
        for (var i = 0; i < _pending.length; i++)
          UnresolvedResource(
            owner: 'chat-query:$threadId:$generation',
            attemptId: AttemptId(generation),
            reason: StateError('query still in flight'),
          ),
        for (final watch in _watches)
          for (final reason
              in watch.errors.isEmpty
                  ? [StateError('watch still closing')]
                  : watch.errors.map((error) => error.$1))
            UnresolvedResource(
              owner: 'chat-watch:$threadId:$generation',
              attemptId: AttemptId(generation),
              reason: reason,
            ),
      ],
    );
  }
}

final class _ContentWatch {
  _ContentWatch(this.permit);
  final ResourcePermit permit;
  final listening = Completer<void>();
  ConversationContentWatch? handle;
  // Owned until both subscription cancellation and original watch join settle.
  // ignore: cancel_subscriptions
  StreamSubscription<ContentWindow>? subscription;
  Future<void>? subscriptionCancellation;
  Future<void>? cancelling;
  Future<void>? lastCancellation;
  (Object, StackTrace)? requestError;
  (Object, StackTrace)? subscriptionError;
  (Object, StackTrace)? handleError;
  bool stopping = false;
  bool sourceEnded = false;
  bool released = false;
  Iterable<(Object, StackTrace)> get errors => [
    ?requestError,
    ?subscriptionError,
    ?handleError,
  ];
}
