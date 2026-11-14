import 'dart:async';

import '../../../conversation_ports.dart';
import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/close_report.dart';
import '../domain/content_lifecycle.dart';
import '../domain/conversation_repository.dart';

/// Borrows the original feed's reader. Retiring this display scope cancels its
/// watches and rejects late results, but never closes a sibling's read lease.
final class ConversationReadScope implements TimelineQueryScope {
  ConversationReadScope({
    required this.threadId,
    required this.generation,
    required ConversationReader reader,
    required bool Function() isEligible,
    Future<void> Function(ChatBatch)? applyOlder,
    TimelineReader? timeline,
  }) : _reader = reader,
       _timeline = timeline,
       _isEligible = isEligible,
       _applyOlder = applyOlder;

  @override
  final String threadId;
  @override
  final int generation;
  final ConversationReader _reader;
  final bool Function() _isEligible;
  final Future<void> Function(ChatBatch)? _applyOlder;
  final TimelineReader? _timeline;
  final Set<_ScopedDisplayMembers> _members = {};
  final Set<Future<void>> _pending = {};
  final Set<_ContentWatch> _watches = {};
  final Set<_ResourceRead> _resourceReads = {};
  bool _retired = false;
  Future<ChatBatch>? _older;
  Future<TimelinePage>? _timelineOlder;

  @override
  bool get isActive => !_retired && _isEligible();
  @override
  int get pendingQueries => _pending.length;
  bool get isSettled =>
      _retired &&
      _pending.isEmpty &&
      _watches.isEmpty &&
      _members.isEmpty &&
      _resourceReads.isEmpty;

  TimelineReader get _timelineFeed =>
      _timeline ?? (throw StateError('Not a Timeline read scope'));

  @override
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) {
    if (!isActive) return Future.error(const StaleConversationScope());
    final existing = _timelineOlder;
    if (existing != null) return existing;
    final completion = Completer<TimelinePage>();
    _timelineOlder = completion.future;
    completion.complete(
      _run(() async {
        final batch = await _timelineFeed.loadTimelineOlder(
          before: before,
          demand: demand,
        );
        if (!isActive) throw const StaleConversationScope();
        return batch;
      }),
    );
    unawaited(
      completion.future.then<void>(
        (_) => _timelineOlder = null,
        onError: (Object _, StackTrace __) => _timelineOlder = null,
      ),
    );
    return completion.future;
  }

  @override
  Future<TailSnapshot> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) => _run(() => _timelineFeed.loadLiveOlder(before: before, demand: demand));

  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) => _run(() async {
    final handle = await _timelineFeed.openDisplayMembers(
      reference: reference,
      window: window,
      demand: demand,
    );
    final owned = _ScopedDisplayMembers(this, handle, reference, window);
    _members.add(owned);
    if (!isActive) {
      owned.requestClose();
      await owned._settle();
      throw const StaleConversationScope();
    }
    return owned;
  });

  @override
  Future<ThreadBusinessRefs> readBusinessRefs() =>
      _run(_reader.readBusinessRefs);

  @override
  Future<CompletedEntry> readCompleted({
    required String recordId,
    required ReadDemand demand,
  }) => _run(() => _reader.readCompleted(recordId: recordId, demand: demand));

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
        await _applyOlder?.call(batch);
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
  }) => _run(
    () => _reader.readContent(reference: reference, range: range),
    resource: reference,
  );

  @override
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) => _run(() async {
    final page = await _reader.pageCurrent(
      reference: reference,
      continuation: continuation,
      demand: demand,
    );
    if (page.revision != reference.revision) throw _staleBusinessResource;
    return page;
  }, resource: reference);

  Future<T> _run<T>(Future<T> Function() operation, {Object? resource}) {
    if (!isActive) return Future.error(const StaleConversationScope());
    final qualification = resource == null ? null : _ResourceRead(resource);
    if (qualification != null) _resourceReads.add(qualification);
    final completion = Completer<T>();
    late final Future<void> joined;
    joined = completion.future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() {
          _pending.remove(joined);
          _resourceReads.remove(qualification);
        });
    _pending.add(joined);
    completion.complete(
      Future<T>.sync(operation).then(
        (value) {
          if (!isActive) throw const StaleConversationScope();
          if (qualification?.stale ?? false) throw _staleBusinessResource;
          return value;
        },
        onError: (Object error, StackTrace stack) {
          if (!isActive) throw const StaleConversationScope();
          if (qualification?.stale ?? false) throw _staleBusinessResource;
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
          final owned = _ContentWatch(reference, output);
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
            // Opening failed before a handle existed. Keep the
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

  void businessRefsChanged(
    ThreadBusinessRefs? previous,
    ThreadBusinessRefs next,
  ) {
    final plan = previous?.plan?.document;
    final interactions = previous?.interactions;
    bool replaced(Object resource) =>
        (plan != null && resource == plan && plan != next.plan?.document) ||
        (interactions != null &&
            resource == interactions &&
            interactions != next.interactions);
    for (final read in _resourceReads) {
      if (replaced(read.resource)) read.stale = true;
    }
    for (final watch in List.of(_watches)) {
      if (!watch.stopping && replaced(watch.reference)) {
        watch.output.addError(_staleBusinessResource);
        unawaited(_finishWatchOutput(watch, watch.output));
      }
    }
  }

  void _releaseWatch(_ContentWatch watch) {
    watch.released = true;
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
          } else {}
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
    for (final member in List.of(_members)) {
      member.requestClose();
    }
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
      for (final member in List.of(_members)) member._settle(),
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
            /* Original operations retain their cleanup responsibility. */
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
        for (final member in _members)
          UnresolvedResource(
            owner: 'display-members:$threadId:$generation',
            attemptId: AttemptId(generation),
            reason: member.error ?? StateError('members still closing'),
          ),
      ],
    );
  }
}

final class _ScopedDisplayMembers implements DisplayMembers {
  _ScopedDisplayMembers(this.scope, this.handle, this.reference, this.window);
  final ConversationReadScope scope;
  final DisplayMembers handle;
  final DisplayBlockRef reference;
  final DisplayMemberWindow window;
  bool stopping = false;
  bool pulling = false;
  bool closed = false;
  int revision = -1;
  bool sealed = false;
  bool ended = false;
  Object? error;
  Future<void>? _closing;
  DisplayMemberPage? _lastPage;

  @override
  Future<DisplayMemberPage?> next() {
    if (stopping || !scope.isActive)
      return Future.error(const StaleConversationScope());
    if (ended) return Future.value(null);
    if (pulling)
      return Future.error(StateError('Display member next already in flight'));
    pulling = true;
    return scope._run(() async {
      try {
        final page = await handle.next();
        if (stopping || !scope.isActive) throw const StaleConversationScope();
        if (page == null) {
          if (!sealed) {
            throw const ConversationContinuityError(
              'Display members ended before sealed page',
            );
          }
          ended = true;
          return null;
        }
        var order = 0;
        final keys = <String>{};
        // Member revision and block sealing are independent. An unchanged
        // bounded page may seal without another member revision.
        final previous = _lastPage;
        final sameRevisionSeal =
            previous != null &&
            page.revision == revision &&
            page.sealed &&
            _sameMemberPageContents(previous, page);
        var valid =
            !sealed &&
            page.block == reference &&
            (page.revision > revision || sameRevisionSeal);
        for (final entry in page.entries) {
          valid =
              valid &&
              entry.memberKey.isNotEmpty &&
              keys.add(entry.memberKey) &&
              entry.memberOrder > order;
          if (window case BeforeDisplayMembers(:final memberOrder)) {
            valid = valid && entry.memberOrder < memberOrder;
          }
          order = entry.memberOrder;
        }
        if (!valid)
          throw const ConversationContinuityError(
            'Invalid display member page',
          );
        revision = page.revision;
        sealed = page.sealed;
        _lastPage = page.sealed ? null : page;
        return page;
      } finally {
        pulling = false;
      }
    });
  }

  @override
  void requestClose() {
    stopping = true;
    _lastPage = null;
    if (closed) return;
    try {
      handle.requestClose();
      error = null;
    } catch (failure) {
      error = failure;
    }
  }

  Future<void> _settle() async {
    try {
      await close();
    } catch (failure) {
      error = failure;
    }
  }

  @override
  Future<void> close() {
    if (closed) return Future.value();
    requestClose();
    return _closing ??= Future<void>.sync(() async {
      try {
        await handle.close();
        if (error != null) throw error!;
        closed = true;
        scope._members.remove(this);
      } finally {
        _closing = null;
      }
    });
  }
}

// Compare only the last admitted bounded page, not a member/history mirror.
// FRB allocates fresh values, so allocation identity cannot prove continuity.
bool _sameMemberPageContents(DisplayMemberPage a, DisplayMemberPage b) =>
    a.before == b.before &&
    _sameValues(
      a.entries,
      b.entries,
      (a, b) =>
          a.memberKey == b.memberKey &&
          a.memberOrder == b.memberOrder &&
          _factFields(a.record.startFact) == _factFields(b.record.startFact) &&
          _factFields(a.record.endFact) == _factFields(b.record.endFact) &&
          _displaySourceFields(a.record.contentSource) ==
              _displaySourceFields(b.record.contentSource) &&
          _atomFields(a.record.atom) == _atomFields(b.record.atom) &&
          _sameValues(
            a.record.atom.contents,
            b.record.atom.contents,
            (a, b) => a.role == b.role && a.reference == b.reference,
          ) &&
          _samePayload(a.record.atom.payload, b.record.atom.payload),
    );

Object _displaySourceFields(DisplayContentSource source) => switch (source) {
  CurrentAtom() => (CurrentAtom,),
  FrozenObservation(:final capturedAt, :final available) => (
    FrozenObservation,
    capturedAt,
    available,
  ),
  CompletedOriginal(:final completionId) => (CompletedOriginal, completionId),
};

Object _atomFields(ChatAtom atom) => (
  atom.id,
  atom.completionItemId,
  atom.completionSeq,
  atom.source,
  switch (atom.sourceState) {
    null => null,
    final state => (
      state.source,
      switch (state.lifecycle) {
        UnknownChatSource() => (UnknownChatSource,),
        ActiveChatSource() => (ActiveChatSource,),
        EndedChatSource(:final outcome) => (EndedChatSource, outcome),
      },
      _factFields(state.started),
      _factFields(state.ended),
    ),
  },
  atom.sourceOrder,
  atom.kind,
  atom.delivery,
  switch (atom.lifecycle) {
    ActiveChatAtom(:final started, :final status) => (
      ActiveChatAtom,
      _factFields(started),
      status,
    ),
    TerminalChatAtom(:final started, :final ended, :final outcome) => (
      TerminalChatAtom,
      _factFields(started),
      _factFields(ended),
      outcome,
    ),
  },
  atom.turnId,
  atom.attemptId,
  atom.tool == null ? null : (atom.tool!.callId, atom.tool!.name),
  atom.wait,
  atom.textChannel,
  atom.contentPresent,
  atom.startedAt,
  atom.finishedAt,
);

(int, int)? _factFields(ChatFactPosition? value) =>
    value == null ? null : (value.effectSeq, value.suborder);

bool _samePayload(PayloadData? a, PayloadData? b) {
  if (a is InlinePayload && b is InlinePayload) {
    return _sameValues(a.bytes, b.bytes, (a, b) => a == b);
  }
  if (a is DeferredPayload && b is DeferredPayload) {
    return a.reference == b.reference && a.byteLength == b.byteLength;
  }
  return a == null && b == null;
}

bool _sameValues<T>(List<T> a, List<T> b, bool Function(T, T) equal) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (!equal(a[index], b[index])) return false;
  }
  return true;
}

final class _ContentWatch {
  _ContentWatch(this.reference, this.output);
  final ContentRef reference;
  final StreamController<ContentWindow> output;
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

final class _ResourceRead {
  _ResourceRead(this.resource);
  final Object resource;
  bool stale = false;
}

const _staleBusinessResource = StudioFailure(
  code: StudioFailureCode.staleRevision,
  reason: StudioFailureReason.staleContent,
  message: 'The requested business resource changed',
  retryable: false,
  correlationId: 'client-business-resource-stale',
);
