import 'dart:async';

import '../../../operations.dart';
import '../../../operations_ports.dart' show OperationRecorder;
import '../../../resources_ports.dart';
import '../domain/bot_values.dart';
import '../domain/bots_state.dart';
import 'bots_frames.dart';
import 'bots_port.dart';

/// One canonical publisher. Command return values never enter this mirror.
final class BotsMirror {
  BotsMirror(this.port, this.lifetime, this.operations)
    : source = ResourceSource(
        const BotsState(
          projection: ProductProjection(
            stamp: null,
            header: null,
            sync: ResourceSyncState(
              phase: ResourceSyncPhase.idle,
              error: null,
              retryExhausted: false,
            ),
          ),
          sourceStatus: null,
          snapshot: null,
        ),
        lifetime.budget,
        'bots:observer',
      ) {
    lifetime.onSeal(source.seal);
  }

  final BotsPort port;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final ResourceSource<BotsState> source;
  ProductFeedOwner<BotsFrame>? _feed;
  ProductProjectionStamp? _feedStamp;
  Future<void>? _restarting;
  int _recoveries = 0;
  final Map<
    ({ProductReadOrigin origin, ProductSourceStatusRef reference}),
    PinnedReadOwner<ProductSourceStatusReadConnection>
  >
  _statusScopes = {};
  final Map<
    ({ProductReadOrigin origin, ProductSourceStatusRef reference}),
    Future<void>
  >
  _statusReads = {};

  Future<void> synchronize() {
    lifetime.admit();
    if (_feed == null) {
      try {
        _start();
      } on ResourceBudgetExceeded catch (error) {
        throw error.failure;
      }
    }
    return lifetime.run('bots:synchronize', () async {
      await ready();
    });
  }

  Future<void> retrySync() {
    lifetime.admit();
    _recoveries = 0;
    final feed = _feed;
    if (feed == null) return synchronize();
    return lifetime.run('bots:explicit-sync', () async {
      await _restart(feed, retry: true);
      await ready();
    });
  }

  Future<BotsState> ready() async {
    lifetime.admit();
    if (_feed == null) _start();
    return source.waitFor((value) {
      final sync = value.projection.sync;
      if (sync.phase == ResourceSyncPhase.failed) throw sync.error!;
      if (sync.phase == ResourceSyncPhase.closed) throw resourceCancelled;
      return sync.phase == ResourceSyncPhase.ready;
    });
  }

  void _sync(
    ResourceSyncPhase phase, {
    StudioFailure? error,
    bool exhausted = false,
  }) {
    final old = source.value;
    source.publish(
      old.copyWith(
        projection: old.projection.copyWith(
          sync: ResourceSyncState(
            phase: phase,
            error: error,
            retryExhausted: exhausted,
          ),
        ),
      ),
    );
  }

  void _start() {
    lifetime.admit();
    _feedStamp = null;
    late final ProductFeedOwner<BotsFrame> feed;
    feed = ProductFeedOwner<BotsFrame>(
      lifetime: lifetime,
      owner: 'bots:feed',
      open: port.openBots,
      sequence: (frame) => frame is BotsData ? frame.deliverySequence : null,
      apply: (frame) async {
        if (lifetime.sealed || !identical(_feed, feed)) {
          return frame is BotsData ? frame.deliverySequence : null;
        }
        switch (frame) {
          case BotsData(:final deliverySequence, :final event):
            switch (event) {
              case BotsBaseline(
                :final identity,
                :final stamp,
                :final header,
                :final state,
              ):
                if (_feedStamp != null ||
                    identity.resource != ProductResource.bots ||
                    identity.ownerEpoch != stamp.ownerEpoch ||
                    identity.incarnation != stamp.incarnation) {
                  throw resourceProtocol(
                    'The Bots baseline has another feed identity.',
                  );
                }
                feed.bindIdentity(identity);
                _adopt(stamp, header, state);
                _feedStamp = stamp;
              case BotsStateChangedPayload(
                :final stamp,
                :final baseRevision,
                :final header,
                :final state,
              ):
                final prior = _feedStamp;
                if (prior == null ||
                    stamp.origin != prior.origin ||
                    baseRevision != prior.revision ||
                    stamp.revision <= baseRevision) {
                  throw resourceProtocol(
                    'The Bots product projection has a revision gap.',
                  );
                }
                _adopt(stamp, header, state);
                _feedStamp = stamp;
            }
            return deliverySequence;
          case BotsResyncRequired(:final identity):
            _control(feed, identity);
            _recover(feed);
          case BotsFeedFailure(:final identity, :final error):
            _control(feed, identity);
            _failed(feed, error);
          case BotsClosed(:final identity, :final reason):
            _control(feed, identity);
            if (reason == ProductFeedCloseReason.ownerReplaced) {
              _recover(feed);
            } else {
              _failed(
                feed,
                const StudioFailure(
                  code: StudioFailureCode.runtimeStopped,
                  message: 'The Bots source has closed.',
                  retryable: false,
                  correlationId: 'bots',
                ),
              );
            }
        }
        return null;
      },
      failed: (error) => _failed(feed, error),
    );
    _feed = feed;
    _sync(ResourceSyncPhase.connecting);
  }

  void _control(
    ProductFeedOwner<BotsFrame> feed,
    ProductFeedIdentity identity,
  ) {
    final stamp = _feedStamp;
    if (identity.resource != ProductResource.bots ||
        stamp != null &&
            (identity.ownerEpoch != stamp.ownerEpoch ||
                identity.incarnation != stamp.incarnation)) {
      throw resourceProtocol('A Bots control frame belongs to another source.');
    }
    feed.bindIdentity(identity);
  }

  void _failed(ProductFeedOwner<BotsFrame> feed, StudioFailure error) {
    if (lifetime.sealed || !identical(_feed, feed)) return;
    if (error.retryable && _recoveries < 2) {
      _recover(feed, failure: error);
      return;
    }
    _sync(ResourceSyncPhase.failed, error: error, exhausted: _recoveries >= 2);
    feed.requestClose();
    unawaited(feed.cleanup(retry: false));
  }

  void _recover(ProductFeedOwner<BotsFrame> feed, {StudioFailure? failure}) {
    if (lifetime.sealed || !identical(_feed, feed) || _restarting != null)
      return;
    if (_recoveries >= 2) {
      _failed(
        feed,
        failure ??
            const StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'The Bots feed recovery budget is exhausted.',
              retryable: false,
              correlationId: 'bots',
            ),
      );
      return;
    }
    ++_recoveries;
    unawaited(
      _restart(feed).then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  Future<void> _restart(
    ProductFeedOwner<BotsFrame> feed, {
    bool retry = false,
  }) {
    lifetime.admit();
    final pending = _restarting;
    if (pending != null) return pending;
    final done = Completer<void>();
    _restarting = done.future;
    _sync(ResourceSyncPhase.reconnecting);
    feed.requestClose();
    unawaited(
      Future<void>.sync(
        () => lifetime.run('bots:resync', () async {
          await feed.cleanup(retry: retry);
          lifetime.admit();
          if (!feed.released) {
            throw const StudioFailure(
              code: StudioFailureCode.busy,
              message: 'The original Bots feed retains unresolved cleanup.',
              retryable: true,
              correlationId: 'bots',
            );
          }
        }),
      ).then<void>(
        (_) {
          _restarting = null;
          if (!lifetime.sealed && identical(_feed, feed)) {
            try {
              _start();
            } catch (error, stack) {
              lifetime.lastCause = error;
              lifetime.lastStack = stack;
              _sync(ResourceSyncPhase.failed, error: resourceFailure(error));
              done.completeError(resourceFailure(error), stack);
              return;
            }
          }
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          _restarting = null;
          if (!lifetime.sealed) {
            _sync(
              ResourceSyncPhase.failed,
              error: resourceFailure(error),
              exhausted: _recoveries >= 2,
            );
          }
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    return done.future;
  }

  void _adopt(
    ProductProjectionStamp stamp,
    BotsHeader header,
    BotsStateSnapshot? snapshot,
  ) {
    final brief = header.source.brief;
    final hasValue =
        brief is ReadyObservedBrief ||
        brief is RefreshingObservedBrief ||
        brief is StaleObservedBrief ||
        brief is DegradedObservedBrief;
    if (stamp.revision < 0 ||
        stamp.incarnation < 0 ||
        header.source.status.entry < 0 ||
        header.source.status.revision != brief.revision ||
        brief.revision < 0 ||
        hasValue != (snapshot != null) ||
        hasValue != (header.botsRevision != null) ||
        hasValue != (header.updatedAt != null) ||
        snapshot != null &&
            (snapshot.revision != header.botsRevision ||
                snapshot.updatedAt != header.updatedAt)) {
      throw resourceProtocol(
        'The Bots source header has inconsistent value availability.',
      );
    }
    if (snapshot != null) validateBotsSnapshot(snapshot);
    final old = source.value;
    final previous = old.projection;
    if (previous.stamp?.ownerEpoch == stamp.ownerEpoch) {
      if (previous.stamp!.origin == stamp.origin &&
              previous.stamp!.revision > stamp.revision ||
          previous.header != null &&
              previous.header!.source.brief.revision > brief.revision ||
          old.snapshot?.reference.ownerEpoch == stamp.ownerEpoch &&
              snapshot != null &&
              old.snapshot!.value.revision > snapshot.revision) {
        throw resourceProtocol(
          'The Bots source moved backwards within one owner.',
        );
      }
      if (previous.header?.source.status == header.source.status &&
          previous.header!.source.brief != brief) {
        throw resourceProtocol(
          'A Bots source-status reference changed its immutable value.',
        );
      }
      if (old.snapshot?.reference.ownerEpoch == stamp.ownerEpoch &&
          old.snapshot?.value.revision == snapshot?.revision &&
          snapshot != null &&
          old.snapshot!.value != snapshot) {
        throw resourceProtocol(
          'A Bots domain revision changed its immutable value.',
        );
      }
    }
    final target = (origin: stamp.origin, reference: header.source.status);
    for (final entry in List.of(_statusScopes.entries)) {
      if (entry.key != target) {
        entry.value.retire();
        _statusScopes.remove(entry.key);
      }
    }
    source.publish(
      old.copyWith(
        projection: ProductProjection(
          stamp: stamp,
          header: header,
          sync: const ResourceSyncState(
            phase: ResourceSyncPhase.ready,
            error: null,
            retryExhausted: false,
          ),
        ),
        sourceStatus: _rebindStatus(
          old.sourceStatus,
          target.origin,
          target.reference,
        ),
        // Absence of a current value preserves only last-known material. It does
        // not clear credential responsibility, registration or diagnostics.
        snapshot: snapshot == null
            ? old.snapshot
            : Materialized(
                origin: stamp.origin,
                reference: ResourceStamp(
                  resourceKey: 'bots',
                  ownerEpoch: stamp.ownerEpoch,
                  revision: snapshot.revision,
                ),
                value: snapshot,
              ),
      ),
    );
    if (snapshot != null) {
      operations.observe(
        ResourceStamp(
          resourceKey: 'bots',
          ownerEpoch: stamp.ownerEpoch,
          revision: snapshot.revision,
        ),
      );
    }
  }

  Future<void> observe(CommitReceipt receipt) async {
    await source.waitFor((value) {
      final projection = value.projection;
      if (projection.sync.phase == ResourceSyncPhase.failed)
        throw projection.sync.error!;
      if (projection.stamp != null &&
          projection.stamp!.ownerEpoch !=
              (receipt.targets.single as ResourceStamp).ownerEpoch) {
        throw const StudioFailure(
          code: StudioFailureCode.superseded,
          message: 'The original Bots command source was replaced.',
          retryable: false,
          correlationId: 'bots',
        );
      }
      if (projection.sync.phase != ResourceSyncPhase.ready ||
          projection.header?.botsRevision == null)
        return false;
      final target = receipt.targets.single as ResourceStamp;
      return projection.header!.botsRevision! >= target.revision;
    });
  }

  Future<void> loadSourceStatus() =>
      lifetime.run('bots:source-status', () async {
        final original = await ready();
        final origin = original.projection.stamp!.origin;
        final header = original.projection.header!.source;
        final key = (origin: origin, reference: header.status);
        final pending = _statusReads[key];
        if (pending != null) return await pending;
        final done = Completer<void>();
        _statusReads[key] = done.future;
        unawaited(
          done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        );
        final previous = _statusMaterial(original.sourceStatus);
        try {
          source.publish(
            source.value.copyWith(
              sourceStatus: ReadValue.loading(
                origin: origin,
                reference: key.reference,
                previous: previous,
              ),
            ),
          );
          var pin = _statusScopes[key];
          if (pin == null || !pin.accepting) {
            final registered = Completer<void>();
            pin = PinnedReadOwner(
              lifetime: lifetime,
              owner: 'bots:source-status-read',
              open: () async {
                await registered.future;
                return port.openSourceStatus(key.reference, origin: key.origin);
              },
              request: (scope) => scope.requestClose(),
              closeNative: (scope) => scope.close(),
              retryNative: (scope) => scope.retryClose(),
            );
            _statusScopes[key] = pin;
            registered.complete();
          }
          final value = await pin.use(
            (scope) =>
                materializeProductSourceStatus(scope, expected: header.brief),
          );
          lifetime.admit();
          if (source.value.projection.stamp?.origin != origin ||
              source.value.projection.header?.source.status != key.reference) {
            throw const StudioFailure(
              code: StudioFailureCode.superseded,
              message: 'The Bots source status advanced during its read.',
              retryable: true,
              correlationId: 'bots',
            );
          }
          source.publish(
            source.value.copyWith(
              sourceStatus: ReadValue.ready(
                current: Materialized(
                  origin: origin,
                  reference: key.reference,
                  value: value,
                ),
              ),
            ),
          );
          done.complete();
        } catch (error, stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          if (!lifetime.sealed &&
              source.value.projection.stamp?.origin == origin &&
              source.value.projection.header?.source.status == key.reference) {
            source.publish(
              source.value.copyWith(
                sourceStatus: ReadValue.failed(
                  origin: origin,
                  reference: key.reference,
                  error: resourceFailure(error),
                  previous: previous,
                ),
              ),
            );
          }
          done.completeError(resourceFailure(error), stack);
          Error.throwWithStackTrace(resourceFailure(error), stack);
        } finally {
          unawaited(_statusReads.remove(key));
        }
      });
}

Materialized<ProductSourceStatus, ProductSourceStatusRef>? _statusMaterial(
  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? value,
) => switch (value) {
  ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef>(:final current) =>
    current,
  LoadingReadValue<ProductSourceStatus, ProductSourceStatusRef>(
    :final previous,
  ) ||
  FailedReadValue<ProductSourceStatus, ProductSourceStatusRef>(
    :final previous,
  ) => previous,
  _ => null,
};

ReadValue<ProductSourceStatus, ProductSourceStatusRef> _rebindStatus(
  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? previous,
  ProductReadOrigin origin,
  ProductSourceStatusRef reference,
) {
  final current = switch (previous) {
    ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef>(
      :final current,
    ) =>
      (origin: current.origin, reference: current.reference),
    UnloadedReadValue<ProductSourceStatus, ProductSourceStatusRef>(
      :final origin,
      :final reference,
    ) ||
    LoadingReadValue<ProductSourceStatus, ProductSourceStatusRef>(
      :final origin,
      :final reference,
    ) ||
    FailedReadValue<ProductSourceStatus, ProductSourceStatusRef>(
      :final origin,
      :final reference,
    ) => (origin: origin, reference: reference),
    null => null,
  };
  if (current?.origin == origin && current?.reference == reference)
    return previous!;
  final known = _statusMaterial(previous);
  return known == null
      ? ReadValue.unloaded(origin: origin, reference: reference)
      : ReadValue.failed(
          origin: origin,
          reference: reference,
          previous: known,
          error: const StudioFailure(
            code: StudioFailureCode.superseded,
            message: 'The previous Bots status is last-known only.',
            retryable: true,
            correlationId: 'bots',
          ),
        );
}

void validateBotsSnapshot(BotsStateSnapshot value) {
  if (value.revision < 0 ||
      value.bots.map((bot) => bot.id).toSet().length != value.bots.length ||
      value.pendingCredentialOperations
              .map((item) => item.botId)
              .toSet()
              .length !=
          value.pendingCredentialOperations.length) {
    throw resourceProtocol(
      'The Bots snapshot has inconsistent identities or revision.',
    );
  }
  for (final bot in value.bots) {
    if (bot.configRevision < 0 ||
        bot.pairing.any((item) => item.botId != bot.id)) {
      throw resourceProtocol('A Bots snapshot row has inconsistent ownership.');
    }
  }
  if (value.registration case final attempt?) validateBotRegistration(attempt);
}

void validateBotRegistration(BotRegistrationAttempt value) {
  final attemptId = switch (value.status) {
    BotRegistrationIdle() => null,
    BotRegistrationPreparing(:final attemptId) ||
    BotRegistrationWaiting(:final attemptId) ||
    BotRegistrationSlowDown(:final attemptId) ||
    BotRegistrationCompleted(:final attemptId) ||
    BotRegistrationCommitting(:final attemptId) ||
    BotRegistrationDenied(:final attemptId) ||
    BotRegistrationExpired(:final attemptId) ||
    BotRegistrationCancelled(:final attemptId) ||
    BotRegistrationFailed(:final attemptId) => attemptId,
  };
  if (attemptId != null && attemptId != value.attemptId) {
    throw resourceProtocol('A registration status belongs to another attempt.');
  }
}
