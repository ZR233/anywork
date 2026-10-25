import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';

final _fixtureUnixSeconds =
    DateTime.utc(2026).millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

StudioTimelineItem timelineItem(
  int revision, {
  String id = 'item',
  String body = 'body',
  String threadId = 'thread',
  int ordinal = 0,
  bool saved = false,
  StudioTimelineLifecycle lifecycle = StudioTimelineLifecycle.streaming,
  int omittedBytes = 0,
  List<StudioTimelineDetailRef> details = const [],
}) => StudioTimelineItem(
  item: ThreadItemView(
    id: id,
    threadId: threadId,
    turnId: 'turn',
    ordinal: ordinal,
    revision: revision,
    createdAt: _fixtureUnixSeconds,
    updatedAt: _fixtureUnixSeconds,
    saved: saved,
    state: ThreadTextItemStateView(
      channel: ThreadTextChannel.finalAnswer,
      text: body,
      attachments: const <ThreadAttachmentView>[],
      lifecycle: lifecycle == StudioTimelineLifecycle.terminal
          ? CompletedThreadContentView(_fixtureUnixSeconds)
          : const StreamingThreadContentView(),
    ),
  ),
  saved: saved,
  lifecycle: lifecycle,
  omittedBytes: omittedBytes,
  details: details,
);

StudioTimelineBaseline baseline(
  int version, {
  String subscriptionId = 'sub',
  List<StudioTimelineItem>? items,
  String? before,
  bool hasOlder = false,
}) => StudioTimelineBaseline(
  subscriptionId: subscriptionId,
  version: version,
  items: items ?? [timelineItem(version)],
  before: before,
  hasOlder: hasOlder,
);

StudioTimelinePatch patch(
  int from,
  int to, {
  String subscriptionId = 'sub',
  List<StudioTimelineChange> changes = const [],
}) => StudioTimelinePatch(
  subscriptionId: subscriptionId,
  from: from,
  to: to,
  changes: changes,
  priority: StudioTimelinePriority.coalesced,
);

/// Scripts environment/transport interleavings, never a second content reducer.
final class TestTimelineTransport implements TimelineTransport {
  final List<Completer<TestTimelineConnection>> opens = [];
  final _openWaiters = <int, Completer<void>>{};

  Future<void> requested(int index) => index < opens.length
      ? Future.value()
      : _openWaiters.putIfAbsent(index, Completer<void>.new).future;

  @override
  Future<TestTimelineConnection> openTimeline(String threadId) {
    final pending = Completer<TestTimelineConnection>();
    opens.add(pending);
    _openWaiters.remove(opens.length - 1)?.complete();
    return pending.future;
  }
}

final class TestTimelineConnection implements StudioTimelineConnection {
  TestTimelineConnection({StudioTimelineBaseline? initial})
    : _initial = initial,
      _feedId = initial?.subscriptionId ?? 'test-feed';

  static const _conflict = StudioFailure(
    code: StudioFailureCode.conflict,
    message: 'The timeline stream is claimed',
    retryable: false,
    correlationId: 'test-timeline-conflict',
  );
  static const _cancelled = StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'The timeline is closing',
    retryable: false,
    correlationId: 'test-timeline-cancelled',
  );
  final subscribed = Completer<void>();
  final closeCompleted = Completer<void>();
  final closeStarted = Completer<void>();
  Completer<void>? closeGate;
  FeedCloseReport? closeReport;
  Object? closeFailure;
  Object? requestCloseFailure;
  Completer<void>? streamCancelGate;
  Object? streamCancelFailure;
  final List<({String? before, int? limit})> pageRequests = [];
  final List<({String itemId, StudioTimelineDetailQuery query})>
  detailRequests = [];
  Completer<StudioTimelinePage>? pageResult;
  Completer<StudioTimelineDetailChunk>? detailResult;
  final List<int> acks = [];
  final _ackWaiters = <int, Completer<void>>{};
  int closeCalls = 0;
  int retryCloseCalls = 0;
  int requestCloseCalls = 0;
  int streamCancelCalls = 0;
  int disposeCalls = 0;
  int nativeJoinCalls = 0;

  StudioTimelineBaseline? _initial;
  String _feedId;
  StreamController<StudioTimelineFeedFrame>? _frames;
  StudioTimelineFeedEvent? _pending;
  StudioTimelineFeedFrame? _pendingTerminal;
  (StudioFailure, StackTrace?)? _pendingError;
  final Set<Future<void>> _queries = {};
  int _sent = 0;
  int _acked = 0;
  bool _closed = false;
  bool _claimed = false;
  bool _started = false;
  bool _terminal = false;
  bool _joining = false;
  Future<FeedCloseReport>? _closing;
  FeedCloseReport? _nativeReport;
  FeedCloseReport? _currentReport;
  final Map<String, (Object, StackTrace)> _causes = {};
  Future<void>? _streamCancellation;
  FeedCloseIssue? _streamCancellationIssue;
  final List<FeedCloseIssue> _terminalNativeIssues = [];

  bool get wasSubscribed => subscribed.isCompleted;
  int get ackedThrough => _acked;

  Future<void> acknowledged(int prefix) => _acked >= prefix
      ? Future.value()
      : _ackWaiters.putIfAbsent(prefix, Completer<void>.new).future;

  void _ensureOpen() {
    if (_closed) throw _cancelled;
  }

  @override
  Stream<StudioTimelineFeedFrame> get events {
    _ensureOpen();
    return _TestTimelineStream(_listen);
  }

  StreamSubscription<StudioTimelineFeedFrame> _listen(
    void Function(StudioTimelineFeedFrame)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _ensureOpen();
    if (_claimed) throw _conflict;
    _claimed = true;
    _frames = StreamController<StudioTimelineFeedFrame>();
    _frames!.onCancel = () async {
      // Output detachment is not native Clean. close/retryClose retain the
      // same attempt's unresolved native/raw cancellation issues and causes.
      // Do not turn that report into a second terminal output cancel failure.
      await close();
    };
    final subscription = _frames!.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    subscribed.complete();
    scheduleMicrotask(() {
      if (_closed) return;
      if (_pendingError case final error?) {
        _pendingError = null;
        _frames!.addError(error.$1, error.$2);
        requestClose();
      } else if (_pendingTerminal case final terminal?) {
        _pendingTerminal = null;
        _frames!.add(terminal);
        requestClose();
      } else {
        _started = true;
        final initial = _initial;
        _initial = null;
        if (initial != null) _pushBaseline(initial);
        _drain();
      }
    });
    return subscription;
  }

  void _data(StudioTimelineFeedEvent event) {
    if (_closed || _terminal) return;
    final controller = _frames;
    if (controller == null || !_started || _sent - _acked >= 2) {
      if (_pending == null) {
        _pending = event;
      } else {
        // No fake resync computation or unbounded replay queue.
        emitFailure(
          const StudioFailure(
            code: StudioFailureCode.overloaded,
            message: 'The scripted timeline pending-frame budget is exhausted',
            retryable: false,
            correlationId: 'test-timeline-budget',
          ),
        );
      }
      return;
    }
    controller.add(
      StudioTimelineFeedFrame.data(deliverySequence: ++_sent, event: event),
    );
  }

  void _drain() {
    if (_closed || _terminal || _sent - _acked >= 2) return;
    final pending = _pending;
    _pending = null;
    if (pending != null) _data(pending);
  }

  void _pushBaseline(StudioTimelineBaseline value) {
    if (_closed || _terminal) return;
    if (_sent == 0) _feedId = value.subscriptionId;
    _data(StudioTimelineFeedEvent.baseline(baseline: value));
  }

  void emit(StudioTimelineUpdate? update) {
    if (update == null) {
      emitClosed();
    } else {
      _data(StudioTimelineFeedEvent.update(update: update));
    }
  }

  void emitBaseline(StudioTimelineBaseline value) => _pushBaseline(value);
  void emitFailure(StudioFailure error) =>
      _control(StudioTimelineFeedFrame.failure(error: error));
  void emitClosed() => _control(const StudioTimelineFeedFrame.closed());

  void _control(StudioTimelineFeedFrame frame) {
    if (_closed || _terminal) return;
    _terminal = true;
    _pending = null;
    final controller = _frames;
    if (controller == null) {
      _pendingTerminal = frame;
    } else {
      controller.add(frame);
      requestClose();
    }
  }

  void emitStreamError(Object error, [StackTrace? stackTrace]) {
    if (_closed || _terminal) return;
    _terminal = true;
    _pending = null;
    final failure = _typedFailure(error);
    final controller = _frames;
    if (controller == null) {
      _pendingError = (failure, stackTrace);
    } else {
      controller.addError(failure, stackTrace);
      requestClose();
    }
  }

  /// A Dart Stream may fail before an adapter has a typed failure. Unlike the
  /// typed-boundary helper above, this supplies the actual original object.
  void emitOriginalStreamError(Object error) {
    if (_closed || _terminal) return;
    final controller = _frames;
    if (controller == null)
      throw StateError('The original stream must be listening');
    _terminal = true;
    _pending = null;
    controller.addError(error, StackTrace.current);
    requestClose();
  }

  @override
  Future<void> ackThrough(int deliverySequence) {
    _ensureOpen();
    if (deliverySequence < 0) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'ACK must be nonnegative',
        retryable: false,
        correlationId: 'test-timeline-ack-argument',
      );
    }
    if (deliverySequence > _sent) {
      throw const StudioFailure(
        code: StudioFailureCode.protocol,
        message: 'ACK exceeds the sent prefix',
        retryable: false,
        correlationId: 'test-timeline-ack-prefix',
      );
    }
    acks.add(deliverySequence);
    if (deliverySequence > _acked) _acked = deliverySequence;
    for (final prefix in _ackWaiters.keys.toList()) {
      if (prefix <= _acked) _ackWaiters.remove(prefix)!.complete();
    }
    _drain();
    return Future<void>.value();
  }

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) {
    _ensureOpen();
    pageRequests.add((before: before, limit: limit));
    final result = Completer<StudioTimelinePage>();
    pageResult = result;
    return _query(result.future);
  }

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) {
    _ensureOpen();
    detailRequests.add((itemId: itemId, query: query));
    final result = Completer<StudioTimelineDetailChunk>();
    detailResult = result;
    return _query(result.future);
  }

  Future<T> _query<T>(Future<T> result) {
    final settled = Completer<void>();
    _queries.add(settled.future);
    return result
        .then<T>(
          (value) {
            _ensureOpen();
            return value;
          },
          onError: (Object error, StackTrace stack) {
            Error.throwWithStackTrace(
              _closed ? _cancelled : _typedFailure(error),
              stack,
            );
          },
        )
        .whenComplete(() {
          _queries.remove(settled.future);
          settled.complete();
        });
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    _closed = true;
    _terminal = true;
    _initial = null;
    _pending = null;
    _pendingTerminal = null;
    _pendingError = null;
    final failure = requestCloseFailure;
    requestCloseFailure = null;
    if (_frames case final controller?) {
      if (!controller.isClosed) unawaited(_frames!.close());
    }
    if (failure != null) throw _typedFailure(failure);
  }

  void _requestForJoin() {
    try {
      requestClose();
    } on Object catch (error, stack) {
      // The independent native join proves whether the original request settled.
      _causes['request-close'] = (error, stack);
    }
  }

  @override
  Future<FeedCloseReport> close() {
    closeCalls++;
    _requestForJoin();
    return _closing ?? _startJoin(retry: false);
  }

  @override
  Future<FeedCloseReport> retryClose() {
    retryCloseCalls++;
    _requestForJoin();
    if (_joining) return _closing!;
    if (disposeCalls != 0) return Future.value(_currentReport!);
    return _startJoin(retry: true);
  }

  Future<FeedCloseReport> _startJoin({required bool retry}) {
    nativeJoinCalls++;
    final completion = Completer<FeedCloseReport>();
    _closing = completion.future;
    _joining = true;
    unawaited(
      _join(retry: retry)
          .then<void>(completion.complete, onError: completion.completeError),
    );
    return completion.future;
  }

  Future<void> _cancelStreamOnce() => _streamCancellation ??=
      Future<void>.sync(() async {
        if (!_claimed) return;
        streamCancelCalls++;
        await streamCancelGate?.future;
        if (streamCancelFailure case final error?) throw error;
      }).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _causes['stream-cancel'] = (error, stack);
          _streamCancellationIssue = _issue(
            _typedFailure(error),
            'test-timeline-stream-cancel',
            CleanupRecovery.terminal,
          );
        },
      );

  Future<FeedCloseReport> _join({required bool retry}) async {
    _joining = true;
    if (!closeStarted.isCompleted) closeStarted.complete();
    try {
      var report = _nativeReport;
      final previous = report?.outcome;
      final recoverable =
          previous is UnresolvedFeedCloseOutcome &&
          previous.issues.any(
            (issue) => issue.recovery != CleanupRecovery.terminal,
          );
      final join = report == null || retry && recoverable
          ? Future<void>.sync(() async {
              await closeGate?.future;
              if (closeFailure case final error?) throw error;
              report =
                  closeReport ??
                  FeedCloseReport(
                    feedId: _feedId,
                    outcome: const FeedCloseOutcome.clean(),
                  );
              final value = report!;
              final outcome = value.outcome;
              if (value.feedId.isEmpty ||
                  value.feedId != _feedId ||
                  outcome is UnresolvedFeedCloseOutcome &&
                      outcome.issues.isEmpty) {
                throw _cleanupFailure;
              }
              if (outcome case UnresolvedFeedCloseOutcome(:final issues)) {
                for (final issue in issues) {
                  if (issue.recovery == CleanupRecovery.terminal &&
                      !_terminalNativeIssues.contains(issue)) {
                    _terminalNativeIssues.add(issue);
                  }
                }
              }
            }).then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                _causes['native-close'] = (error, stack);
                report = FeedCloseReport(
                  feedId: _feedId,
                  outcome: FeedCloseOutcome.unresolved(
                    issues: [
                      if (_nativeReport?.outcome
                          case UnresolvedFeedCloseOutcome(:final issues))
                        ...issues,
                      _issue(
                        _typedFailure(error),
                        'test-timeline-native-close',
                        CleanupRecovery.retryClose,
                      ),
                    ],
                  ),
                );
              },
            )
          : Future<void>.value();
      final cancellation = _cancelStreamOnce();
      final queries = Future.wait<void>(_queries.toList(growable: false));
      await Future.wait<void>([join, cancellation, queries]);
      _nativeReport = report;
      final outcome = report!.outcome;
      final issues = <FeedCloseIssue>[
        if (outcome case UnresolvedFeedCloseOutcome(:final issues)) ...issues,
        if (_streamCancellationIssue case final issue?) issue,
      ];
      for (final terminal in _terminalNativeIssues) {
        if (!issues.contains(terminal)) issues.add(terminal);
      }
      final result = FeedCloseReport(
        feedId: report!.feedId,
        outcome: issues.isEmpty
            ? const FeedCloseOutcome.clean()
            : FeedCloseOutcome.unresolved(issues: issues),
      );
      _currentReport = result;
      if (issues.isEmpty && disposeCalls == 0) {
        disposeCalls++;
        _causes.clear();
      }
      if (!closeCompleted.isCompleted) closeCompleted.complete();
      return result;
    } finally {
      _joining = false;
    }
  }
}

const _cleanupFailure = StudioFailure(
  code: StudioFailureCode.protocol,
  message: 'The scripted timeline cleanup is unresolved',
  retryable: false,
  correlationId: 'test-timeline-cleanup',
);

StudioFailure _typedFailure(Object error) => error is StudioFailure
    ? error
    : const StudioFailure(
        code: StudioFailureCode.protocol,
        message: 'A scripted timeline operation failed',
        retryable: false,
        correlationId: 'test-timeline-operation',
      );

FeedCloseIssue _issue(
  StudioFailure failure,
  String stage,
  CleanupRecovery recovery,
) => FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: stage,
    code: failure.code.name,
    message: failure.message,
    retryable: failure.retryable,
    correlationId: failure.correlationId,
  ),
  recovery: recovery,
);

final class _TestTimelineStream extends Stream<StudioTimelineFeedFrame> {
  _TestTimelineStream(this._listen);
  final StreamSubscription<StudioTimelineFeedFrame> Function(
    void Function(StudioTimelineFeedFrame)?, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  })
  _listen;
  @override
  StreamSubscription<StudioTimelineFeedFrame> listen(
    void Function(StudioTimelineFeedFrame)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
