import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'canvas_binding.dart';
import 'display_binding.dart';
import 'display_content.dart';
import 'presentation_work.dart';

/// Owns one concrete display, all of its scope incarnations and actual mounts.
/// Only [canvas] is borrowed by Dumb widgets.
final class TimelineDisplayLease {
  TimelineDisplayLease({required this.session, required this.generation}) {
    content = DisplayContent(_chat, generation);
    canvas = _CanvasBorrow(this);
    binding = _DisplayBorrow(this);
  }

  final ConversationSession session;
  final int generation;
  final InMemoryChatController _chat = InMemoryChatController();
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);
  late final DisplayContent content;
  late final TimelineCanvasBinding canvas;
  late final TimelineDisplayBinding binding;
  final Set<_MountToken> _mounts = {};
  final Set<Future<void>> _writes = {};
  final List<_ScopeClose> _scopes = [];
  final List<FeedCloseIssue> _issues = [];
  final List<FeedCloseIssue> _retireIssues = [];
  final Set<VoidCallback> _retireListeners = {};
  final List<(Object, StackTrace)> _retireFailures = [];
  final Completer<void> _released = Completer<void>();
  StudioTimelineQueryScope? _query;
  Future<CloseReport>? _closing;
  bool retired = false;
  bool _disposing = false;
  int _queryOpenings = 0;

  /// The generation is released once its controllers are disposed and no
  /// mount, write or query still borrows them.
  ///
  /// Observation of the stock operations stream ending stays a separate fact:
  /// [_released] and [report] still wait for that real done (design/26 §26.3).
  bool get isReleased => _released.isCompleted || _disposing;
  int get _pendingQueries =>
      _scopes.fold(0, (count, item) => count + item.scope.pendingQueries);
  String get threadId => session.threadId;
  ChatController get controller => _chat;
  ScrollController get scrollController => _scroll;
  void addRetireListener(VoidCallback listener) {
    if (retired) {
      _notifyRetire(listener);
    } else {
      _retireListeners.add(listener);
    }
  }

  void removeRetireListener(VoidCallback listener) =>
      _retireListeners.remove(listener);

  /// Captures this display's original Session, never a same-ID replacement.
  StudioTimelineQueryScope? queries() {
    if (retired) return null;
    final existing = _query;
    if (existing != null && existing.isActive) return existing;
    if (existing != null) _retireScope(existing);
    // A synchronous open may reenter retirement before handing back its scope.
    // Keep release blocked until that returned capability is registered too.
    _queryOpenings++;
    try {
      final opened = session.timeline.openScope(generation: generation);
      if (opened != null) {
        _scopes.add(_ScopeClose(opened, _releaseIfReady));
        if (retired) {
          _retireScope(opened);
        } else {
          _query = opened;
        }
      }
      return retired ? null : opened;
    } finally {
      _queryOpenings--;
      _releaseIfReady();
    }
  }

  Future<StudioTimelineDetailChunk> _readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) {
    if (retired) return Future<StudioTimelineDetailChunk>.error(_retired);
    final reference = content.payloadOf(itemId)?.detailFor(query.field);
    if (reference == null || reference.revision != query.revision) {
      return Future<StudioTimelineDetailChunk>.error(
        const StudioFailure(
          code: StudioFailureCode.staleRevision,
          message: 'The timeline detail reference changed',
          retryable: false,
          correlationId: 'timeline-detail-reference-changed',
        ),
      );
    }
    final scope = queries();
    if (scope == null || retired || !scope.isActive) {
      return Future<StudioTimelineDetailChunk>.error(_retired);
    }
    // No await or same-ID lookup between freezing the original scope and D1's
    // read admission. Its close obligation was registered by queries() above.
    return scope.readDetail(itemId: itemId, query: query);
  }

  static const _retired = StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'The timeline display is retired',
    retryable: false,
    correlationId: 'timeline-display-retired',
  );

  /// Registration precedes action and its first await. Synchronous projection
  /// failure still drains every stock write started by that action.
  Future<void> write(void Function() action) {
    if (retired) return Future<void>.value();
    final complete = Completer<void>();
    final future = complete.future;
    _writes.add(future);
    // A registered projection is applied in this delivery turn, not one event
    // loop turn later: the consumer's completion below is its first await.
    Future<void>.microtask(() async {
      Object? failure;
      StackTrace? trace;
      try {
        action();
      } catch (error, stack) {
        failure = error;
        trace = stack;
      }
      try {
        await content.flushWrites();
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
        _issues.add(
          presentationIssue(
            'controllerWriteFailed',
            CleanupRecovery.terminal,
            error is StudioFailure ? error : null,
          ),
        );
      }
      _writes.remove(future);
      if (failure == null) {
        complete.complete();
      } else {
        complete.completeError(failure, trace);
      }
      _releaseIfReady();
    });
    // A consumer/page awaits the original error. Retirement independently owns
    // completion even if that caller is no longer displaying this generation.
    future.ignore();
    return future;
  }

  _MountToken _mount() {
    // Retirement stops publication and queries, not an already existing
    // subtree: a late real mount of a controller that still exists must join
    // the release barrier. Only a released generation rejects its binding.
    if (_disposing || isReleased) throw _retired;
    final token = _MountToken(this);
    _mounts.add(token);
    return token;
  }

  void _unmount(_MountToken token) {
    _mounts.remove(token);
    _releaseIfReady();
  }

  void requestRetire() {
    if (retired) return;
    retired = true;
    final listeners = List<VoidCallback>.of(_retireListeners);
    _retireListeners.clear();
    for (final listener in listeners) {
      _notifyRetire(listener);
    }
    _query = null;
    for (final item in _scopes) {
      item.scope.retire();
      item.start();
    }
    _releaseIfReady();
  }

  void _notifyRetire(VoidCallback listener) {
    try {
      listener();
    } catch (error, stack) {
      _retireFailures.add((error, stack));
      _retireIssues.add(
        presentationIssue(
          'retireListenerFailed',
          CleanupRecovery.terminal,
          error is StudioFailure ? error : null,
        ),
      );
    }
  }

  void _retireScope(StudioTimelineQueryScope scope) {
    scope.retire();
    for (final item in _scopes) {
      if (identical(item.scope, scope)) item.start();
    }
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) {
    requestRetire();
    final running = _closing;
    if (running != null) return running;
    final task = _join(deadline, retry);
    _closing = task;
    task.whenComplete(() {
      if (identical(_closing, task)) _closing = null;
    }).ignore();
    return task;
  }

  Future<CloseReport> _join(DateTime? deadline, bool retry) async {
    for (final item in _scopes) {
      item.start(retry: retry);
    }
    await observePresentationCompletion([
      for (final write in _writes)
        write.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      for (final item in _scopes) item.completion,
    ], deadline);
    _releaseIfReady();
    if (_issues.isEmpty && _scopes.every((item) => item.clean)) {
      await observePresentationCompletion([_released.future], deadline);
    }
    return report;
  }

  Future<CloseReport> _observeRelease({required DateTime deadline}) async {
    // Freeze only completions already supervised by this exact lease before
    // the first await. The release ACK also covers work registered later by an
    // already-entered opening/retirement callback, without observing a new owner.
    final release = _released.future;
    final existing = <Future<void>>[
      for (final write in _writes)
        write.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      for (final item in _scopes) ?item._work,
    ];
    await observePresentationCompletion([...existing, release], deadline);
    // No requestRetire/close/retry/queries/read is invoked here. The timeout
    // only ends observation; every original Future and issue remains with us.
    return report;
  }

  CloseReport get report {
    final unresolved = <UnresolvedResource>[];
    for (final item in _scopes) {
      final report = item.report;
      if (report != null) unresolved.addAll(report.unresolved);
      if (item.pending) {
        unresolved.add(
          UnresolvedResource(
            owner: 'timeline-query:$threadId',
            attemptId: item.scope.attemptId,
            issues: [
              presentationIssue(
                'queryPending',
                CleanupRecovery.awaitCompletion,
              ),
            ],
          ),
        );
      }
      final error = item.error;
      if (error != null) {
        unresolved.add(
          UnresolvedResource(
            owner: 'timeline-query-close:$threadId',
            attemptId: item.scope.attemptId,
            issues: [
              presentationIssue(
                'queryCloseFailed',
                CleanupRecovery.retryClose,
                error,
              ),
            ],
          ),
        );
      }
    }
    final releasePending =
        !retired ||
        !_released.isCompleted ||
        _mounts.isNotEmpty ||
        _writes.isNotEmpty ||
        _queryOpenings > 0 ||
        _pendingQueries > 0;
    if (_issues.isNotEmpty || _retireIssues.isNotEmpty || releasePending) {
      unresolved.add(
        UnresolvedResource(
          owner: 'timeline-display:$threadId',
          attemptId: AttemptId(generation),
          issues: [
            ..._issues,
            ..._retireIssues,
            if (releasePending)
              presentationIssue(
                'displayPending',
                CleanupRecovery.awaitCompletion,
              ),
          ],
        ),
      );
    }
    return CloseReport(unresolved: unresolved);
  }

  void _releaseIfReady() {
    if (!retired ||
        _disposing ||
        isReleased ||
        _mounts.isNotEmpty ||
        _writes.isNotEmpty ||
        _queryOpenings > 0 ||
        _issues.isNotEmpty ||
        !_scopes.every((s) => s.clean)) {
      return;
    }
    _disposing = true;
    // Observe the real operations-stream done before disposing its owner.
    _chat.operationsStream.listen(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _issues.add(
          presentationIssue(
            'controllerStreamFailed',
            CleanupRecovery.terminal,
            error is StudioFailure ? error : null,
          ),
        );
      },
      onDone: () {
        if (!_released.isCompleted) _released.complete();
      },
    );
    content.dispose();
    _chat.dispose();
    _scroll.dispose();
  }
}

/// A distinct runtime object, not an interface cast of TimelineDisplayLease.
final class _DisplayBorrow implements TimelineDisplayBinding {
  _DisplayBorrow(this._owner);
  final TimelineDisplayLease _owner;
  @override
  String get threadId => _owner.threadId;
  @override
  int get generation => _owner.generation;
  @override
  bool get retired => _owner.retired;
  @override
  int get pendingQueries => _owner._pendingQueries;
  @override
  bool get isReleased => _owner.isReleased;
  @override
  Future<CloseReport> observeRelease({required DateTime deadline}) =>
      _owner._observeRelease(deadline: deadline);
  @override
  int? get appliedVersion => _owner.content.appliedVersion;
  @override
  TimelineCanvasBinding get canvas => _owner.canvas;
  @override
  StudioTimelineDetailRef? detailFor(
    String itemId,
    ThreadContentFieldView field,
  ) => retired ? null : _owner.content.payloadOf(itemId)?.detailFor(field);
  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) => _owner._readDetail(itemId: itemId, query: query);
  @override
  void addRetireListener(VoidCallback listener) =>
      _owner.addRetireListener(listener);
  @override
  void removeRetireListener(VoidCallback listener) =>
      _owner.removeRetireListener(listener);
}

final class _ScopeClose {
  _ScopeClose(this.scope, this.onSettled);
  final StudioTimelineQueryScope scope;
  final VoidCallback onSettled;
  CloseReport? report;
  StudioFailure? error;
  Object? cause;
  StackTrace? trace;
  Future<void>? _work;
  bool get pending => _work != null;
  bool get clean => !pending && error == null && report?.complete == true;
  Future<void> get completion => _work ?? Future<void>.value();

  void start({bool retry = false}) {
    if (pending || clean) return;
    final previous = report;
    if (!retry && (previous != null || error != null)) return;
    if (previous != null &&
        previous.unresolved.every(
          (resource) => resource.issues.every(
            (issue) => issue.recovery == CleanupRecovery.terminal,
          ),
        )) {
      return;
    }
    final done = Completer<void>();
    _work = done.future;
    Future<void>(() async {
      try {
        report = await scope.close();
        error = null;
      } on StudioFailure catch (failure) {
        error = failure;
      } catch (failure, stack) {
        cause = failure;
        trace = stack;
        error = const StudioFailure(
          code: StudioFailureCode.internal,
          message: 'The timeline query close failed unexpectedly',
          retryable: false,
          correlationId: 'timeline-query-close-internal',
        );
      } finally {
        _work = null;
        done.complete();
        onSettled();
      }
    });
  }
}

final class _CanvasBorrow implements TimelineCanvasBinding {
  _CanvasBorrow(this._owner);
  final TimelineDisplayLease _owner;
  @override
  String get threadId => _owner.threadId;
  @override
  int get displayGeneration => _owner.generation;
  @override
  Key get chatKey => ValueKey('timeline-chat:$threadId:$displayGeneration');
  @override
  ChatController get chatController => _owner.controller;
  @override
  ScrollController get scrollController => _owner.scrollController;
  @override
  TimelineCanvasMount mount() => _owner._mount();
}

final class _MountToken implements TimelineCanvasMount {
  _MountToken(this._owner);
  TimelineDisplayLease? _owner;
  @override
  void unmount() {
    final owner = _owner;
    _owner = null;
    owner?._unmount(this);
  }
}
