import 'dart:async';

import '../domain/budgets.dart';
import '../domain/closing.dart';
import '../domain/failures.dart';
import '../domain/product_identity.dart';
import 'feed_connection.dart';
import 'resource_budget.dart';
import 'resource_errors.dart';
import 'resource_lifetime.dart';

enum _FeedFailureStage {
  opening,
  stream,
  frame,
  apply,
  ack,
  notification,
  consumer,
}

/// One concrete typed product-feed attempt, with no payload queue or reducer.
final class ProductFeedOwner<F> implements ResourceOwner {
  ProductFeedOwner({
    required this.lifetime,
    required this.owner,
    required Future<FeedConnection<F>> Function() open,
    required this.sequence,
    required this.apply,
    required this.failed,
  }) : attempt = lifetime.nextAttempt() {
    lifetime.admit();
    permit = lifetime.budget.acquire(
      ResourceKind.readModel,
      owner: owner,
      phase: ResourcePhase.opening,
    );
    final opening = Completer<FeedConnection<F>>();
    _opened = opening.future;
    _openSettled = _opened.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    final consumer = Completer<void>();
    _consumer = consumer.future;
    _consumerSettled = _consumer.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _recordConsumerFailure(
          error,
          stack,
          _FeedFailureStage.consumer,
          unresolved: true,
        );
      },
    );
    try {
      lifetime.register(this);
    } catch (_) {
      permit.release();
      rethrow;
    }
    final start = Completer<void>();
    unawaited(
      lifetime
          .accepted<FeedConnection<F>>(this, () async {
            // Both accepted work records and their error paths exist before open can
            // synchronously seal the lifetime. Late handoff stays in this same Future.
            await start.future;
            final FeedConnection<F> connection;
            try {
              connection = await open();
            } catch (error, stack) {
              _rememberCause(error, stack, 'opening');
              _openFailed = true;
              rethrow;
            }
            _connection = connection;
            if (_closing) _requestNative(connection);
            return connection;
          })
          .then<void>(opening.complete, onError: opening.completeError),
    );
    unawaited(
      lifetime
          .accepted<void>(this, _consume)
          .then<void>(
            (_) => consumer.complete(),
            onError: consumer.completeError,
          ),
    );
    start.complete();
  }

  final ResourceLifetime lifetime;
  @override
  final String owner;
  @override
  final int attempt;
  late final ResourcePermit permit;
  final int? Function(F) sequence;
  final Future<int?> Function(F) apply;
  final void Function(StudioFailure) failed;
  late final Future<FeedConnection<F>> _opened;
  late final Future<void> _openSettled;
  late final Future<void> _consumer;
  late final Future<void> _consumerSettled;
  FeedConnection<F>? _connection;
  StreamIterator<F>? _iterator;
  Future<void>? _streamCancel;
  bool _closing = false;
  bool _requestingNative = false;
  bool _openFailed = false;
  bool _consumerDone = false;
  bool _released = false;
  Future<void>? _cleaning;
  bool _cleaningDone = false;
  FeedCloseReport? _report;
  FeedCloseIssue? _nativeIssue;
  FeedCloseIssue? _cancelIssue;
  final List<FeedCloseIssue> _consumerIssues = [];
  final List<({String stage, Object cause, StackTrace stack})> _causes = [];
  final List<FeedCloseIssue> _terminalIssues = [];
  ProductFeedIdentity? _identity;
  int _delivery = 0;

  @override
  bool get released => _released;
  bool get closing => _closing;

  void _rememberCause(Object error, StackTrace stack, String stage) {
    _causes.add((stage: stage, cause: error, stack: stack));
    lifetime.lastCause = error;
    lifetime.lastStack = stack;
  }

  void _retainConsumerIssue(FeedCloseIssue issue) {
    if (!_consumerIssues.contains(issue)) _consumerIssues.add(issue);
  }

  FeedCloseIssue _recordConsumerFailure(
    Object error,
    StackTrace stack,
    _FeedFailureStage stage, {
    required bool unresolved,
  }) {
    _rememberCause(error, stack, stage.name);
    final original = resourceCleanupIssue(error, CleanupRecovery.terminal);
    final issue = original.copyWith(
      diagnostic: original.diagnostic.copyWith(
        stage: 'resources:feed:${stage.name}',
      ),
    );
    if (unresolved) _retainConsumerIssue(issue);
    return issue;
  }

  void bindIdentity(ProductFeedIdentity identity) {
    if (identity.feedId.isEmpty ||
        identity.feedId.length >= 64 ||
        identity.feedId.codeUnits.any((unit) => unit > 127) ||
        identity.ownerEpoch.isEmpty ||
        identity.ownerEpoch.length >= 64 ||
        identity.ownerEpoch.codeUnits.any((unit) => unit > 127) ||
        identity.incarnation < 0) {
      throw resourceProtocol(
        'The product feed has an invalid native identity.',
      );
    }
    if (_identity != null && _identity != identity) {
      throw resourceProtocol(
        'The product feed identity changed within one connection.',
      );
    }
    _identity = identity;
  }

  Future<void> _consume() async {
    StudioFailure? failure;
    FeedCloseIssue? notificationIssue;
    var stage = _FeedFailureStage.opening;
    try {
      final connection = await _opened;
      if (_closing) return;
      permit.mark(ResourcePhase.active);
      stage = _FeedFailureStage.stream;
      final iterator = StreamIterator(connection.events);
      _iterator = iterator;
      while (!_closing) {
        stage = _FeedFailureStage.stream;
        if (!await iterator.moveNext()) break;
        if (_closing) break;
        stage = _FeedFailureStage.frame;
        final incoming = sequence(iterator.current);
        if (incoming != null && (incoming <= 0 || incoming != _delivery + 1)) {
          throw resourceProtocol(
            'The product feed delivery prefix is not continuous.',
          );
        }
        stage = _FeedFailureStage.apply;
        final delivery = await apply(iterator.current);
        stage = _FeedFailureStage.frame;
        if (incoming != delivery) {
          throw resourceProtocol(
            'The product feed reducer returned another delivery identity.',
          );
        }
        if (delivery != null) {
          if (delivery != _delivery + 1) {
            throw resourceProtocol(
              'The product feed delivery prefix is not continuous.',
            );
          }
          if (!_closing) {
            stage = _FeedFailureStage.ack;
            await connection.ackThrough(delivery);
            _delivery = delivery;
          }
        }
      }
      if (!_closing) {
        failure = const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'The product feed ended without a terminal frame.',
          retryable: true,
          correlationId: 'resources',
        );
        notificationIssue = _recordConsumerFailure(
          failure,
          StackTrace.current,
          _FeedFailureStage.stream,
          unresolved: false,
        );
      }
    } catch (error, stack) {
      final processing =
          stage == _FeedFailureStage.frame ||
          stage == _FeedFailureStage.apply ||
          stage == _FeedFailureStage.ack;
      if (processing || !_closing) {
        notificationIssue = _recordConsumerFailure(
          error,
          stack,
          stage,
          unresolved: processing,
        );
        failure = resourceFailure(error);
      } else {
        // Closing a stream/open is distinct from an admitted apply/ACK failure.
        _rememberCause(error, stack, stage.name);
      }
    } finally {
      try {
        if (!_closing && failure != null) {
          try {
            failed(failure);
          } catch (error, stack) {
            if (notificationIssue != null)
              _retainConsumerIssue(notificationIssue);
            _recordConsumerFailure(
              error,
              stack,
              _FeedFailureStage.notification,
              unresolved: true,
            );
          }
        }
      } finally {
        _consumerDone = true;
        requestClose();
        // Do not await this from the consumer that the cleanup must join.
        unawaited(cleanup(retry: false));
      }
    }
  }

  @override
  void requestClose() {
    _closing = true;
    if (_released) return;
    permit.mark(
      _report?.outcome is UnresolvedFeedCloseOutcome ||
              _nativeIssue != null ||
              _cancelIssue != null ||
              _consumerIssues.isNotEmpty ||
              _terminalIssues.isNotEmpty
          ? ResourcePhase.unresolved
          : ResourcePhase.retiring,
    );
    final connection = _connection;
    if (connection != null) _requestNative(connection);
    final iterator = _iterator;
    if (iterator != null && _streamCancel == null) {
      final done = Completer<void>();
      _streamCancel = done.future;
      unawaited(
        Future<void>.sync(iterator.cancel).then(
          (_) => done.complete(),
          onError: (Object error, StackTrace stack) {
            _rememberCause(error, stack, 'cancellation');
            _cancelIssue = resourceCleanupIssue(
              error,
              CleanupRecovery.terminal,
            );
            done.complete();
          },
        ),
      );
    }
  }

  void _requestNative(FeedConnection<F> connection) {
    if (_requestingNative || _report?.outcome is CleanFeedCloseOutcome) return;
    _requestingNative = true;
    try {
      connection.requestClose();
    } catch (error, stack) {
      _rememberCause(error, stack, 'requestClose');
      _nativeIssue = resourceCleanupIssue(error, CleanupRecovery.retryClose);
    } finally {
      _requestingNative = false;
    }
  }

  @override
  Future<void> cleanup({required bool retry}) {
    requestClose();
    if (_released) return Future.value();
    if (_cleaning != null && (!_cleaningDone || !retry)) return _cleaning!;
    _cleaningDone = false;
    final done = Completer<void>();
    _cleaning = done.future;
    unawaited(
      _clean(retry: retry).then(
        (_) {
          _cleaningDone = true;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          _rememberCause(error, stack, 'cleanup');
          _nativeIssue = resourceCleanupIssue(
            error,
            CleanupRecovery.retryClose,
          );
          if (!_released) permit.mark(ResourcePhase.unresolved);
          _cleaningDone = true;
          done.complete();
        },
      ),
    );
    return done.future;
  }

  void _rememberReport(FeedCloseReport report) {
    final expected = _identity?.feedId ?? _report?.feedId;
    if (expected != null && report.feedId != expected) {
      throw resourceProtocol(
        'The product close report belongs to another connection.',
      );
    }
    _report = report;
    if (report.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
      for (final issue in issues) {
        if (issue.recovery == CleanupRecovery.terminal &&
            !_terminalIssues.contains(issue)) {
          _terminalIssues.add(issue);
        }
      }
    }
  }

  Future<void> _clean({required bool retry}) async {
    await _openSettled;
    if (_openFailed) {
      await _consumerSettled;
      if (_consumerIssues.isEmpty &&
          _cancelIssue == null &&
          _terminalIssues.isEmpty) {
        _released = true;
        permit.release();
      } else {
        permit.mark(ResourcePhase.unresolved);
      }
      return;
    }
    requestClose();
    final connection = _connection!;
    final native = Future<void>.sync(() async {
      final outcome = _report?.outcome;
      final recoverable =
          outcome is UnresolvedFeedCloseOutcome &&
          outcome.issues.any(
            (issue) => issue.recovery != CleanupRecovery.terminal,
          );
      if (outcome is CleanFeedCloseOutcome) return;
      if (outcome is UnresolvedFeedCloseOutcome &&
          !(retry && recoverable) &&
          _nativeIssue == null)
        return;
      try {
        _rememberReport(
          await (retry ? connection.retryClose() : connection.close()),
        );
        _nativeIssue = null;
      } catch (error, stack) {
        _rememberCause(error, stack, 'nativeClose');
        _nativeIssue = resourceCleanupIssue(error, CleanupRecovery.retryClose);
      }
    });
    // Every completion/error path is registered before awaiting any of them.
    // A failed native call does not abandon stream cancellation or the consumer.
    await Future.wait([
      native,
      _streamCancel ?? Future<void>.value(),
      _consumerSettled,
    ]);
    if (_report?.outcome is CleanFeedCloseOutcome &&
        _nativeIssue == null &&
        _cancelIssue == null &&
        _consumerIssues.isEmpty &&
        _terminalIssues.isEmpty) {
      _released = true;
      permit.release();
    } else {
      permit.mark(ResourcePhase.unresolved);
    }
  }

  @override
  List<FeedCloseIssue> get issues {
    final issues = <FeedCloseIssue>[
      if (_report?.outcome case UnresolvedFeedCloseOutcome(:final issues))
        ...issues,
      if (_nativeIssue case final issue?) issue,
      if (_cancelIssue case final issue?) issue,
      ..._consumerIssues,
      if (!_consumerDone || _cleaning != null && !_cleaningDone)
        resourcePendingIssue('feedPending'),
    ];
    for (final issue in _terminalIssues) {
      if (!issues.contains(issue)) issues.add(issue);
    }
    return List.unmodifiable(issues);
  }
}
