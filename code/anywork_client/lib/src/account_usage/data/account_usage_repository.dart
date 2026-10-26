import 'dart:async';

import '../../../configuration.dart';
import '../../../operations.dart';
import '../../../operations_ports.dart'
    show
        OperationRecorder,
        OperationWriter,
        RejectedCommandDispatchFailure,
        UnknownOutcomeCommandDispatchFailure,
        CommittedButUnobservedCommandDispatchFailure,
        ConfirmedWithoutUsableReceiptCommandDispatchFailure;
import '../../../resources_ports.dart';
import '../domain/account_usage_repository.dart';
import '../domain/usage_state.dart';
import '../domain/usage_values.dart';
import 'account_read_fields.dart';
import 'account_usage_port.dart';
import 'usage_check_job.dart';
import 'usage_identity.dart';
import 'usage_mirror.dart';

AccountUsageRepository createAccountUsageRepository({
  required AccountUsagePort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
  required AccountConfigurationReadSource configuration,
}) => _AccountUsageRepository(port, budget, operations, configuration);

final class _AccountUsageRepository implements AccountUsageRepository {
  _AccountUsageRepository(
    this.port,
    ResourceBudget budget,
    this.operations,
    this.configuration,
  ) : lifetime = ResourceLifetime(budget),
      checkSource = ResourceSource(
        Map<String, AccountUsageCheck>.unmodifiable({}),
        budget,
        'account-usage:checks-observer',
      ) {
    mirror = UsageMirror(port, lifetime);
    final watched = configuration.state.watchLatest(_configurationChanged);
    _configurationObservation = watched.observation;
    lifetime.onSeal(() => _configurationObservation.cancel());
    lifetime.onSeal(checkSource.seal);
    _configurationChanged(watched.value);
  }
  final AccountUsagePort port;
  final OperationRecorder operations;
  final AccountConfigurationReadSource configuration;
  final ResourceLifetime lifetime;
  final ResourceSource<Map<String, AccountUsageCheck>> checkSource;
  late final UsageMirror mirror;
  late final Observation _configurationObservation;
  final Map<OperationId, UsageCheckJob> _jobs = {};
  final Map<String, UsageCheckJob> _preparing = {};
  final Map<String, UsageCheckJob> _presented = {};
  final Map<AccountUsageQueryIdentity, UsageNetworkAttempt> _networks = {};
  final Map<OperationId, Future<void>> _work = {};
  final Set<String> _starting = {};
  final Map<String, ({AccountUsageQueryIdentity identity, UsageCheckJob? job})>
  _attempted = {};
  final Map<String, UsagePreparation> _unknownAttempts = {};
  Set<String> _visible = const {};
  bool _sealed = false;
  bool _sourcesClosed = false;
  bool _draining = false;
  bool _drainAgain = false;

  @override
  ReadonlyLatestValue<AccountUsageState> get state => mirror.source.readonly;
  @override
  ReadonlyLatestValue<Map<String, AccountUsageCheck>> get checks =>
      checkSource.readonly;
  void _admit() {
    if (_sealed) throw resourceCancelled;
    lifetime.admit();
  }

  void _retain(Object error, StackTrace stack) {
    lifetime.lastCause = error;
    lifetime.lastStack = stack;
  }

  AccountUsageQueryIdentity? _currentIdentity(String id) {
    final account = usageAccount(configuration.state.value, id);
    return account == null ? null : usageIdentity(account);
  }

  bool _current(AccountUsageQueryIdentity identity) =>
      _currentIdentity(identity.accountId) == identity;

  @override
  Future<void> loadSourceStatus() {
    _admit();
    return mirror.loadStatus();
  }

  @override
  Future<void> loadRecordsPage({int limit = 32}) {
    _admit();
    return mirror.page(limit: limit);
  }

  @override
  Future<AccountUsageRecord> load(String accountId) {
    _admit();
    return mirror.record(accountId);
  }

  void _publishChecks() => checkSource.publish(
    Map<String, AccountUsageCheck>.unmodifiable({
      for (final entry in _presented.entries) entry.key: entry.value.borrow,
    }),
  );
  void _present(UsageCheckJob job) {
    if (_sourcesClosed) return;
    final identity = job.identity;
    if (identity != null
        ? !_current(identity)
        : !job.preparation.compatible(configuration.state.value))
      return;
    _presented[job.accountId] = job;
    _publishChecks();
  }

  void _configurationChanged(ConfigurationState value) {
    for (final job in List.of(_jobs.values)) {
      if (job.preparing) job.preparation.observe(value);
    }
    for (final entry in List.of(_unknownAttempts.entries)) {
      if (!entry.value.compatible(value) &&
          identical(_unknownAttempts[entry.key], entry.value))
        _unknownAttempts.remove(entry.key);
    }
    final accounts = value.accounts;
    if (value.projection.sync.phase == ResourceSyncPhase.ready &&
        value.projection.header?.reference != null &&
        accounts is CurrentCollectionMirror<AccountConfiguration> &&
        accounts.window.origin == value.projection.stamp?.origin &&
        accounts.window.complete &&
        accounts.window.entries.length == accounts.window.reference.total &&
        accounts.window.entries.every((reference) {
          final row = accounts.window.rows[reference.entry];
          return row
                  is ReadyReadValue<AccountConfiguration, ProductEntityRef> &&
              row.current.origin == accounts.window.origin &&
              row.current.reference == reference;
        })) {
      // Only a fully materialized authoritative membership can prove deletion.
      // Partial/superseded rows and visibility changes retain consumed attempts.
      final members = {
        for (final reference in accounts.window.entries)
          if (accounts.window.rows[reference.entry]
              case ReadyReadValue<AccountConfiguration, ProductEntityRef>(
                :final current,
              ))
            current.value.accountId,
      };
      _attempted.removeWhere((id, _) => !members.contains(id));
    }
    var changed = false;
    for (final entry in List.of(_presented.entries)) {
      final job = entry.value;
      final identity = job.identity;
      final valid = identity == null
          ? job.preparation.compatible(value)
          : _current(identity);
      if (!valid && identical(_presented[entry.key], job)) {
        _presented.remove(entry.key);
        changed = true;
      }
    }
    if (changed) _publishChecks();
    if (!_sealed) _drainVisible();
  }

  @override
  void setVisibleAccounts(Set<String> accountIds) {
    _admit();
    _visible = Set.unmodifiable(accountIds);
    _drainVisible();
  }

  void _drainVisible() {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        for (final id in List.of(_visible)) {
          if (_sealed) break;
          final identity = _currentIdentity(id);
          final attempted = _attempted[id];
          if (identity != null && attempted?.identity == identity) {
            // A temporary unmaterialized row does not consume another native
            // attempt or discard the original failure/unknown presentation.
            final previous = attempted?.job;
            if (_presented[id] == null && previous != null) _present(previous);
            continue;
          }
          final unknown = _unknownAttempts[id];
          final snapshot = configuration.state.value;
          final origin = snapshot.projection.stamp?.origin;
          final sameUnknownSource =
              unknown != null &&
              unknown.compatible(snapshot) &&
              unknown.origin == origin;
          if (identity == null && sameUnknownSource ||
              identity != null && sameUnknownSource && unknown.expected == null)
            continue;
          // Admission/preparation failure also consumes this visible demand;
          // unrelated configuration publications do not form a retry loop.
          if (identity != null) {
            _attempted[id] = (identity: identity, job: null);
          } else {
            _unknownAttempts[id] = UsagePreparation(
              configuration,
              id,
              configuration.state.value,
            );
          }
          try {
            _check(id, manual: false);
          } catch (error, stack) {
            _retain(error, stack);
          }
        }
      } while (_drainAgain && !_sealed);
    } finally {
      _draining = false;
    }
  }

  @override
  OperationTicket<AccountUsageRecord> check(String accountId) =>
      _check(accountId, manual: true);

  OperationTicket<AccountUsageRecord> _check(
    String accountId, {
    required bool manual,
  }) {
    _admit();
    final known = _currentIdentity(accountId);
    if (known != null) {
      final network = _networks[known];
      if (network != null && network.jobs.isNotEmpty) {
        final job = network.jobs.reduce(
          (left, right) =>
              left.attempt.value >= right.attempt.value ? left : right,
        );
        _attempted[accountId] = (identity: known, job: job);
        _present(job);
        if (job.finished && network.reply != null && !job.proven) _recover(job);
        return job.writer.ticket;
      }
    }
    final pending = _preparing[accountId];
    if (pending != null &&
        pending.preparation.compatible(configuration.state.value)) {
      if (manual) pending.manual = true;
      _present(pending);
      return pending.writer.ticket;
    }
    if (!_starting.add(accountId))
      throw const StudioFailure(
        code: StudioFailureCode.busy,
        message: 'The account check is being synchronously registered.',
        retryable: true,
        correlationId: 'account-usage',
      );
    OperationWriter<AccountUsageRecord>? writer;
    ResourcePermit? permit;
    UsageCheckJob? admitted;
    final start = Completer<void>();
    try {
      final preparation = UsagePreparation(
        configuration,
        accountId,
        configuration.state.value,
      );
      permit = lifetime.budget.acquire(
        ResourceKind.observer,
        owner: 'account-usage:check-evidence',
      );
      writer = operations.begin<AccountUsageRecord>(
        target: 'account-usage:${accountId.length}:$accountId',
      );
      final job = UsageCheckJob(
        accountId,
        preparation,
        writer,
        AttemptId(lifetime.nextAttempt()),
        permit,
        manual: manual,
      );
      admitted = job;
      _jobs[writer.ticket.id] = job;
      _preparing[accountId] = job;
      if (known != null) {
        _attempted[accountId] = (identity: known, job: job);
      } else {
        _unknownAttempts[accountId] = preparation;
      }
      final watched = writer.ticket.state.watchLatest((_) {
        if (job.proven) _releaseJob(job);
      });
      job.observation = watched.observation;
      final work = lifetime.run('account-usage:check', () async {
        await start.future;
        await _execute(job);
      });
      final settled = work.then<void>(
        (_) {
          unawaited(_work.remove(job.writer.ticket.id));
        },
        onError: (Object error, StackTrace stack) {
          _retain(error, stack);
          _fail(job, error);
          job.finished = true;
          unawaited(_work.remove(job.writer.ticket.id));
        },
      );
      job.completion = settled;
      _work[writer.ticket.id] = settled;
      _present(job);
      start.complete();
      return writer.ticket;
    } catch (error, stack) {
      _retain(error, stack);
      if (!start.isCompleted) start.complete();
      if (admitted != null) {
        admitted.finished = true;
        admitted.writer.rejected(accountDataFailure(error));
        _releaseJob(admitted);
      } else {
        writer?.rejected(accountDataFailure(error));
        permit?.release();
      }
      throw accountDataFailure(error);
    } finally {
      _starting.remove(accountId);
    }
  }

  Future<void> _execute(UsageCheckJob job) async {
    try {
      if (job.proven) return;
      if (_sealed) throw resourceCancelled;
      final identity = await job.preparation.resolve();
      if (_sealed ||
          !job.preparation.compatible(configuration.state.value) ||
          !_current(identity))
        throw accountDataSuperseded;
      job.identity = identity;
      job.preparing = false;
      if (identical(_preparing[job.accountId], job))
        _preparing.remove(job.accountId);
      if (identical(_unknownAttempts[job.accountId], job.preparation))
        _unknownAttempts.remove(job.accountId);
      final attempted = _attempted[job.accountId];
      if (!job.manual &&
          attempted?.identity == identity &&
          !identical(attempted?.job, job)) {
        // This ticket admitted only a pure identity read. Re-materializing the
        // same business identity is not authorization for a second native call.
        job.writer.rejected(
          const StudioFailure(
            code: StudioFailureCode.cancelled,
            message: 'This automatic usage identity was already attempted; this preparation did not dispatch a network check.',
            retryable: false,
            correlationId: 'account-usage',
          ),
        );
        // Rejection can synchronously reenter. Never replace a newer manual
        // check, but retain the original real failure/unknown ticket if current.
        if (identical(_presented[job.accountId], job)) {
          final previous = attempted?.job;
          _present(previous ?? job);
        }
        return;
      }
      _attempted[job.accountId] = (identity: identity, job: job);
      final existing = _networks[identity];
      final network = existing ?? UsageNetworkAttempt(identity);
      job.network = network;
      network.jobs.add(job);
      _networks[identity] = network;
      // Both the job and shared response are installed before observers can
      // reenter seal/change identity. A borrow's identity is now non-null.
      unawaited(
        network.response.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        ),
      );
      _present(job);
      if (existing == null) _dispatch(job, network);
      final reply = await network.response.future;
      final value = await _observe(job, reply);
      job.writer.identityObserved();
      job.writer.acknowledged(value);
    } catch (error, stack) {
      _retain(error, stack);
      _fail(job, error);
    } finally {
      job.preparing = false;
      job.finished = true;
      if (identical(_preparing[job.accountId], job))
        _preparing.remove(job.accountId);
      if (job.preparation.invalidated &&
          identical(_unknownAttempts[job.accountId], job.preparation))
        _unknownAttempts.remove(job.accountId);
    }
  }

  void _dispatch(UsageCheckJob job, UsageNetworkAttempt network) {
    unawaited(
      Future<AccountUsageCheckResult>.sync(() {
        if (_sealed ||
            !job.preparation.compatible(configuration.state.value) ||
            !_current(network.identity))
          throw RejectedCommandDispatchFailure(failure: accountDataSuperseded);
        network.permit = lifetime.budget.acquire(
          ResourceKind.readModel,
          owner: 'account-usage:network',
        );
        final call = port.check(
          job.accountId,
          expectedUsageQueryRevision: network.identity.usageQueryRevision,
        );
        // Only a call the native owner actually accepted is a dispatched
        // attempt. A synchronous throw above means nothing was handed over, so
        // the failure is a rejected dispatch rather than an unknown outcome.
        network.dispatched = true;
        return call;
      }).then(
        (reply) {
          network.reply = reply;
          network.settled = true;
          network.permit?.release();
          network.response.complete(reply);
        },
        onError: (Object error, StackTrace stack) {
          _retain(error, stack);
          network.settled = true;
          network.permit?.release();
          network.response.completeError(error, stack);
        },
      ),
    );
  }

  Future<AccountUsageRecord> _observe(
    UsageCheckJob job,
    AccountUsageCheckResult reply,
  ) async {
    lifetime.admit();
    final identity = job.identity!;
    if (reply.accountId != identity.accountId ||
        reply.usageQueryRevision != identity.usageQueryRevision ||
        reply.target.origin.ownerEpoch != identity.ownerEpoch)
      throw accountDataProtocol(
        'The usage check reply belongs to another query identity.',
      );
    if (!_current(identity)) {
      if (configuration.state.value.projection.stamp?.ownerEpoch !=
          identity.ownerEpoch)
        throw accountDataSuperseded;
      await configuration.loadAccount(identity.accountId);
      if (!_current(identity)) throw accountDataSuperseded;
    }
    return mirror.synchronize(
      reply.target,
      identity.accountId,
      validate: () => _current(identity),
    );
  }

  void _fail(UsageCheckJob job, Object error) {
    if (job.proven) return;
    final failure = switch (error) {
      RejectedCommandDispatchFailure(:final failure) ||
      UnknownOutcomeCommandDispatchFailure(:final failure) ||
      CommittedButUnobservedCommandDispatchFailure(:final failure) ||
      ConfirmedWithoutUsableReceiptCommandDispatchFailure(
        :final failure,
      ) => failure,
      _ => accountDataFailure(error),
    };
    final network = job.network;
    if (network != null && !network.dispatched && !network.settled) {
      network.settled = true;
      network.response.completeError(
        RejectedCommandDispatchFailure(failure: failure),
        StackTrace.current,
      );
    }
    if (job.network?.reply != null ||
        error is ConfirmedWithoutUsableReceiptCommandDispatchFailure ||
        error is CommittedButUnobservedCommandDispatchFailure) {
      job.writer.acknowledgedSynchronizationFailed(failure);
    } else if (error is RejectedCommandDispatchFailure ||
        job.network?.dispatched != true) {
      job.writer.rejected(failure);
    } else {
      job.writer.unknownOutcome(failure);
    }
    if (!job.permit.isReleased) job.permit.mark(ResourcePhase.unresolved);
  }

  void _recover(UsageCheckJob job) {
    if (job.recovery != null || _sealed) return;
    final reply = job.network?.reply;
    if (reply == null) return;
    final done = Completer<void>();
    job.recovery = done.future;
    unawaited(
      Future<void>.sync(
        () => lifetime.run('account-usage:evidence-read', () async {
          await _observe(job, reply);
          // The original result Future stays settled. This is later evidence only,
          // not a second network query, new ticket or rewritten command result.
          job.writer.identityObserved();
        }),
      ).then(
        (_) {
          job.recovery = null;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          _retain(error, stack);
          job.writer.evidenceFailed(accountDataFailure(error));
          job.recovery = null;
          done.complete();
        },
      ),
    );
  }

  void _releaseJob(UsageCheckJob job) {
    _jobs.remove(job.writer.ticket.id);
    if (identical(_preparing[job.accountId], job))
      _preparing.remove(job.accountId);
    job.observation?.cancel();
    job.observation = null;
    job.permit.release();
    final network = job.network;
    if (network != null) {
      network.jobs.remove(job);
      if (network.settled &&
          network.jobs.isEmpty &&
          identical(_networks[network.identity], network))
        _networks.remove(network.identity);
    }
  }

  @override
  void seal() {
    _sealed = true;
    _visible = const {};
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, true);
  Future<void> _join() async {
    while (_work.isNotEmpty) {
      await Future.wait(List.of(_work.values));
    }
  }

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    seal();
    final joining = _join();
    if (deadline == null) {
      await joining;
    } else {
      final expired = Completer<void>();
      final remaining = deadline.difference(DateTime.now());
      final timer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () => expired.complete(),
      );
      try {
        await Future.any([joining, expired.future]);
      } finally {
        timer.cancel();
      }
    }
    final report = await lifetime.close(deadline: deadline, retry: retry);
    final unresolved = [
      ...report.unresolved,
      for (final job in _jobs.values)
        UnresolvedResource(
          owner: 'account-usage:operation:${job.writer.ticket.id.value}',
          attemptId: job.attempt,
          issues: [
            FeedCloseIssue(
              diagnostic: StudioShutdownIssue(
                stage: 'account-usage',
                code:
                    job.writer.ticket.state.value.failurePhase?.name ??
                    'checkPending',
                message: 'The original account usage query has unresolved outcome or observation.',
                retryable:
                    job.writer.ticket.state.value.error?.retryable ?? false,
                correlationId:
                    job.writer.ticket.state.value.error?.correlationId ??
                    'account-usage',
              ),
              recovery: job.finished && job.recovery == null
                  ? CleanupRecovery.terminal
                  : CleanupRecovery.awaitCompletion,
            ),
          ],
        ),
    ];
    if (unresolved.isEmpty && !_sourcesClosed) {
      _sourcesClosed = true;
      mirror.source.publish(
        mirror.source.value.copyWith(
          projection: mirror.source.value.projection.copyWith(
            sync: const ResourceSyncState(
              phase: ResourceSyncPhase.closed,
              error: null,
              retryExhausted: false,
            ),
          ),
        ),
      );
      mirror.source.close();
      checkSource.close();
    }
    return CloseReport(unresolved: unresolved);
  }
}
