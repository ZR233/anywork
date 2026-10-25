import 'dart:async';

import '../../../models_ports.dart' show ModelCatalogTargetReceiver;
import '../../../models.dart' show BillingKind;
import '../../../operations.dart';
import '../../../operations_ports.dart'
    show
        OperationRecorder,
        RejectedCommandDispatchFailure,
        UnknownOutcomeCommandDispatchFailure,
        CommittedButUnobservedCommandDispatchFailure,
        ConfirmedWithoutUsableReceiptCommandDispatchFailure;
import '../../../resources.dart';
import '../../../resources_ports.dart' show ResourceBudget;
import '../domain/account_edits.dart';
import '../domain/configuration_repository.dart';
import '../domain/configuration_values.dart';
import '../domain/profile_values.dart';
import '../domain/settings_updates.dart';
import 'account_intent.dart';
import 'configuration_commands.dart';
import 'configuration_command_owner.dart';
import 'configuration_port.dart';
import 'configuration_read_fields.dart';
import 'configuration_write_context.dart';
import 'configuration_write_job.dart';

/// One Settings CAS lane. Lane slots are reserved before begin() can notify
/// observers and reenter, so a newer intent cannot jump ahead of its predecessor.
final class ConfigurationWrites {
  ConfigurationWrites({
    required this.port,
    required this.host,
    required this.operations,
    required this.modelTargets,
    required this.budget,
  });
  final ConfigurationPort port;
  final ConfigurationWriteHost host;
  final OperationRecorder operations;
  final ModelCatalogTargetReceiver modelTargets;
  final ResourceBudget budget;
  final Map<OperationId, ConfigurationWriteJobBase> _jobs = {};
  Future<void> _tail = Future.value();
  bool _sealed = false;
  int _attempt = 0;

  void _admit() {
    host.admit();
    if (_sealed) throw configurationCancelled;
  }

  void seal() => _sealed = true;
  Future<void> join() => _tail;
  bool get needsReadDependencies => _jobs.values.any(
    (job) => job.calls.any((call) => call.needsReadDependencies),
  );
  Future<void> joinCalls({required bool retry}) async {
    // Snapshot original owners only. No new mutation or lane admission occurs.
    final calls = [for (final job in _jobs.values) ...job.calls];
    for (final call in calls) {
      call.requestClose();
    }
    await Future.wait([for (final call in calls) call.cleanup(retry: retry)]);
  }

  List<UnresolvedResource> get unresolved => List.unmodifiable([
    for (final job in _jobs.values)
      if (!job.proven)
        UnresolvedResource(
          owner: 'configuration:operation:${job.writer.ticket.id.value}',
          attemptId: job.attempt,
          issues: [
            FeedCloseIssue(
              diagnostic: StudioShutdownIssue(
                stage: 'configuration',
                code:
                    job.writer.ticket.state.value.failurePhase?.name ??
                    'commandEvidencePending',
                message: 'The original configuration operation has unresolved outcome or receipt observation.',
                retryable:
                    job.writer.ticket.state.value.error?.retryable ?? false,
                correlationId:
                    job.writer.ticket.state.value.error?.correlationId ??
                    'configuration',
              ),
              recovery: !job.finished
                  ? CleanupRecovery.awaitCompletion
                  : job.currentCall != null
                  ? CleanupRecovery.retryClose
                  : CleanupRecovery.terminal,
            ),
          ],
        ),
  ]);

  void _release(ConfigurationWriteJobBase job) {
    if (!job.releasable) return;
    final id = job.writer.ticket.id;
    if (identical(_jobs[id], job)) _jobs.remove(id);
    job.releaseObservation();
  }

  void _notStarted(ConfigurationWriteJobBase job, StudioFailure error) {
    job.finished = true;
    job.writer.rejected(error);
    _release(job);
  }

  _LaneSlot _reserve() {
    _admit();
    final previous = _tail;
    final slot = _LaneSlot(previous);
    _tail = slot.done.future;
    return slot;
  }

  void _activate(_LaneSlot slot) {
    final Future<void> work;
    try {
      work = host.supervise('configuration:write-lane', () async {
        await slot.previous;
        final action = await slot.ready.future;
        try {
          if (action != null) await action();
        } finally {
          slot.done.complete();
        }
      });
    } catch (error, stack) {
      host.retainFailure(error, stack);
      slot.refused?.call(configurationFailure(error));
      if (!slot.done.isCompleted) slot.done.complete();
      return;
    }
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          host.retainFailure(error, stack);
          if (!slot.done.isCompleted) slot.done.complete();
        },
      ),
    );
  }

  ConfigurationWriteJob<T, P> _begin<T, P>(
    String target,
    T intent,
    Future<ConfigurationWriteReply> Function(
      T,
      OperationId,
      void Function(P, ProductReadOrigin),
    )
    send,
  ) {
    final writer = operations.begin<Unit>(
      target: target,
      requireIdentityObservation: true,
    );
    try {
      final job = ConfigurationWriteJob<T, P>(
        writer: writer,
        attempt: AttemptId(++_attempt),
        intent: intent,
        send: (intent, id, capture) => send(intent, id, (request, origin) {
          // Reading a fresh CAS base is not dispatch. A synchronous seal while
          // awaiting it must still reject this not-yet-sent step.
          if (_sealed || host.sealed) throw configurationCancelled;
          capture(request, origin);
        }),
      );
      job.evidencePermit = budget.acquire(
        ResourceKind.observer,
        owner: 'configuration:operation:${writer.ticket.id.value}',
      );
      _jobs[writer.ticket.id] = job;
      void observe(OperationState state) {
        job.observe(state);
        _release(job);
      }

      final watched = writer.ticket.state.watchLatest(observe);
      job.observation = watched.observation;
      observe(watched.value);
      return job;
    } catch (error, stack) {
      _jobs.remove(writer.ticket.id)?.releaseObservation();
      writer.rejected(configurationFailure(error));
      host.retainFailure(error, stack);
      Error.throwWithStackTrace(configurationFailure(error), stack);
    }
  }

  OperationTicket<Unit> _single<T, P>(
    String target,
    T intent,
    Future<ConfigurationWriteReply> Function(
      T,
      OperationId,
      void Function(P, ProductReadOrigin),
    )
    send,
  ) {
    final slot = _reserve();
    try {
      final job = _begin<T, P>(target, intent, send);
      slot.refused = (error) => _notStarted(job, error);
      slot.ready.complete(() async {
        await _execute(job);
      });
      _activate(slot);
      return job.writer.ticket;
    } catch (_) {
      slot.ready.complete(null);
      _activate(slot);
      rethrow;
    }
  }

  OperationTicket<Unit> saveAccount(AccountEdit value) {
    _admit();
    final intent = freezeAccountEdit(value);
    return _single<AccountEdit, UpdateAccountRequest>(
      'configuration:account:${intent.accountId.length}:${intent.accountId}',
      intent,
      (intent, id, capture) async {
        final base = await host.accountWriteBase(intent.accountId);
        final request = UpdateAccountRequest(
          operationId: id,
          expectedRevision: base.revision,
          account: buildAccountUpdate(intent, base.account),
        );
        capture(request, base.origin);
        return ConfigurationWriteReply.settings(
          await _command(id, () => port.saveAccount(request)),
        );
      },
    );
  }

  OperationTicket<Unit> setDefaultAccount(String accountId) =>
      _single<String, SetDefaultAccountRequest>(
        'configuration:default-account',
        accountId,
        (accountId, id, capture) async {
          final base = await host.currentWriteBase();
          final request = SetDefaultAccountRequest(
            operationId: id,
            expectedRevision: base.revision,
            accountId: accountId,
          );
          capture(request, base.origin);
          return ConfigurationWriteReply.settings(
            await _command(id, () => port.setDefaultAccount(request)),
          );
        },
      );

  OperationTicket<Unit> removeAccount(
    String accountId, {
    String? replacementAccountId,
  }) =>
      _single<({String accountId, String? replacement}), RemoveAccountRequest>(
        'configuration:account:${accountId.length}:$accountId',
        (accountId: accountId, replacement: replacementAccountId),
        (intent, id, capture) async {
          final base = await host.currentWriteBase();
          final request = RemoveAccountRequest(
            operationId: id,
            expectedRevision: base.revision,
            accountId: intent.accountId,
            replacementAccountId: intent.replacement,
          );
          capture(request, base.origin);
          return ConfigurationWriteReply.settings(
            await _command(id, () => port.removeAccount(request)),
          );
        },
      );

  OperationTicket<Unit> removeAccountModel(String accountId, String modelId) =>
      _single<({String accountId, String modelId}), RemoveAccountModelRequest>(
        'configuration:account-model:${accountId.length}:$accountId:$modelId',
        (accountId: accountId, modelId: modelId),
        (intent, id, capture) async {
          final base = await host.currentWriteBase();
          final request = RemoveAccountModelRequest(
            operationId: id,
            expectedRevision: base.revision,
            accountId: intent.accountId,
            modelId: intent.modelId,
          );
          capture(request, base.origin);
          return ConfigurationWriteReply.settings(
            await _command(id, () => port.removeAccountModel(request)),
          );
        },
      );

  OperationTicket<Unit> setAccountModelEnabled(
    String accountId,
    String modelId,
    bool enabled,
  ) =>
      _single<
        ({String accountId, String modelId, bool enabled}),
        SetAccountModelEnabledRequest
      >(
        'configuration:account-model-enabled:${accountId.length}:$accountId:$modelId',
        (accountId: accountId, modelId: modelId, enabled: enabled),
        (intent, id, capture) async {
          final base = await host.currentWriteBase();
          final request = SetAccountModelEnabledRequest(
            operationId: id,
            expectedRevision: base.revision,
            accountId: intent.accountId,
            modelId: intent.modelId,
            enabled: intent.enabled,
          );
          capture(request, base.origin);
          return ConfigurationWriteReply.settings(
            await _command(id, () => port.setAccountModelEnabled(request)),
          );
        },
      );

  OperationTicket<Unit> setAccountBillingKind(
    String accountId,
    BillingKind? billingKind,
  ) =>
      _single<
        ({String accountId, BillingKind? billingKind}),
        SetAccountBillingKindRequest
      >(
        'configuration:account-billing-kind:${accountId.length}:$accountId',
        (accountId: accountId, billingKind: billingKind),
        (intent, id, capture) async {
          final base = await host.currentWriteBase();
          final request = SetAccountBillingKindRequest(
            operationId: id,
            expectedRevision: base.revision,
            accountId: intent.accountId,
            billingKind: intent.billingKind,
          );
          capture(request, base.origin);
          return ConfigurationWriteReply.settings(
            await _command(id, () => port.setAccountBillingKind(request)),
          );
        },
      );

  OperationTicket<Unit> applyField(SettingsFieldUpdate value) {
    _admit();
    final intent = freezeSettingsUpdate(value);
    return _single<SettingsFieldUpdate, UpdateSettingsFieldRequest>(
      configurationFieldTarget(intent),
      intent,
      _sendField,
    );
  }

  Future<ConfigurationWriteReply> _sendField(
    SettingsFieldUpdate intent,
    OperationId id,
    void Function(UpdateSettingsFieldRequest, ProductReadOrigin) capture,
  ) async {
    final base = await host.currentWriteBase();
    final request = UpdateSettingsFieldRequest(
      operationId: id,
      expectedRevision: base.revision,
      update: intent,
    );
    capture(request, base.origin);
    return ConfigurationWriteReply.settings(
      await _command(id, () => port.applyField(request)),
    );
  }

  SettingsWriteBatch applyFields(List<SettingsFieldUpdate> values) {
    _admit();
    final intents = List<SettingsFieldUpdate>.unmodifiable(
      values.map(freezeSettingsUpdate),
    );
    if (intents.isEmpty)
      return _SettingsBatch(
        const [],
        Future.value(SettingsBatchResult(steps: const [])),
      );
    final slot = _reserve();
    final jobs =
        <
          ConfigurationWriteJob<SettingsFieldUpdate, UpdateSettingsFieldRequest>
        >[];
    try {
      for (final intent in intents) {
        jobs.add(
          _begin<SettingsFieldUpdate, UpdateSettingsFieldRequest>(
            configurationFieldTarget(intent),
            intent,
            _sendField,
          ),
        );
      }
    } catch (error) {
      for (final job in jobs) {
        _notStarted(job, configurationFailure(error));
      }
      slot.ready.complete(null);
      _activate(slot);
      rethrow;
    }
    final completed = Completer<SettingsBatchResult>();
    slot.refused = (error) {
      final steps = <SettingsFieldResult>[];
      for (var index = 0; index < jobs.length; index++) {
        final job = jobs[index];
        _notStarted(job, error);
        steps.add(
          SettingsFieldResult.notStarted(
            index: index,
            operationId: job.writer.ticket.id,
            error: error,
          ),
        );
      }
      completed.complete(SettingsBatchResult(steps: List.unmodifiable(steps)));
    };
    slot.ready.complete(() async {
      final steps = <SettingsFieldResult>[];
      StudioFailure? stopped;
      for (var index = 0; index < jobs.length; index++) {
        final job = jobs[index];
        if (stopped != null || _sealed || host.sealed) {
          final error = stopped ?? configurationCancelled;
          _notStarted(job, error);
          steps.add(
            SettingsFieldResult.notStarted(
              index: index,
              operationId: job.writer.ticket.id,
              error: error,
            ),
          );
          stopped ??= error;
          continue;
        }
        final result = await _execute(job);
        steps.add(
          SettingsFieldResult.finished(
            index: index,
            operationId: job.writer.ticket.id,
            result: result,
          ),
        );
        if (result is! CommittedCommandResult<Unit> &&
            result is! AcknowledgedCommandResult<Unit>)
          stopped = _batchStopped;
      }
      completed.complete(SettingsBatchResult(steps: List.unmodifiable(steps)));
    });
    _activate(slot);
    return _SettingsBatch(
      List.unmodifiable([for (final job in jobs) job.writer.ticket]),
      completed.future,
    );
  }

  OperationTicket<Unit> setPermissionMode(PermissionMode mode) =>
      _single<PermissionMode, UpdatePermissionSettingsRequest>(
        'configuration:permission',
        mode,
        (mode, id, capture) async {
          final base = await host.currentWriteBase();
          final label = switch (mode) {
            PermissionMode.requestApproval => 'request-approval',
            PermissionMode.autoReview => 'auto-review',
            PermissionMode.fullAccess => 'full-access',
          };
          final request = UpdatePermissionSettingsRequest(
            operationId: id,
            expectedRevision: base.revision,
            mode: label,
          );
          capture(request, base.origin);
          return ConfigurationWriteReply.settings(
            await _command(id, () => port.setPermission(request)),
          );
        },
      );

  OperationTicket<Unit> saveProfile(AgentProfileEdit intent) =>
      _single<AgentProfileEdit, SaveProfileRequest>(
        'configuration:profile:${intent.profileId.length}:${intent.profileId}',
        intent,
        (intent, id, capture) async {
          final base = await host.currentWriteBase();
          final request = SaveProfileRequest(
            operationId: id,
            expectedSettingsRevision: base.revision,
            profile: intent,
          );
          capture(request, base.origin);
          return ConfigurationWriteReply.profile(
            await _profileCommand(id, () => port.saveProfile(request)),
          );
        },
      );

  OperationTicket<Unit> setSystemProfileEnabled(
    String profileId,
    bool enabled,
  ) =>
      _single<
        ({String profileId, bool enabled}),
        SetSystemProfileEnabledRequest
      >(
        'configuration:profile:${profileId.length}:$profileId',
        (profileId: profileId, enabled: enabled),
        (intent, id, capture) async {
          final base = await host.currentWriteBase();
          final request = SetSystemProfileEnabledRequest(
            operationId: id,
            expectedSettingsRevision: base.revision,
            profileId: intent.profileId,
            enabled: intent.enabled,
          );
          capture(request, base.origin);
          return ConfigurationWriteReply.profile(
            await _profileCommand(
              id,
              () => port.setSystemProfileEnabled(request),
            ),
          );
        },
      );

  OperationTicket<Unit> reload() => _single<Unit, ConfigurationReloadRequest>(
    'configuration:reload',
    const Unit(),
    (_, id, capture) async {
      final base = await host.currentWriteBase();
      final request = ConfigurationReloadRequest(
        operationId: id,
        expectedRevision: base.revision,
      );
      capture(request, base.origin);
      return ConfigurationWriteReply.reload(
        await _reloadCommand(id, () => port.reload(request)),
      );
    },
  );

  Future<ConfigurationCommandReply> _command(
    OperationId id,
    Future<ConfigurationCommandCall> Function() begin,
  ) => _ownedCommand<ConfigurationCommandReply>(
    id,
    () async => _settingsCall(await begin()),
    () async {
      final call = await port.findConfigurationCommand(id);
      return call == null ? null : _settingsCall(call);
    },
    ConfigurationWriteReply.settings,
  );

  Future<ProfileCommandReply> _profileCommand(
    OperationId id,
    Future<ProfileCommandCall> Function() begin,
  ) => _ownedCommand<ProfileCommandReply>(
    id,
    () async => _profileCall(await begin()),
    () async {
      final call = await port.findProfileCommand(id);
      return call == null ? null : _profileCall(call);
    },
    ConfigurationWriteReply.profile,
  );

  Future<ConfigurationReloadResult> _reloadCommand(
    OperationId id,
    Future<ConfigurationReloadCall> Function() begin,
  ) => _ownedCommand<ConfigurationReloadResult>(
    id,
    () async => _reloadCall(await begin()),
    () async {
      final call = await port.findConfigurationReload(id);
      return call == null ? null : _reloadCall(call);
    },
    ConfigurationWriteReply.reload,
  );

  // Only bind methods of the original typed handle; these wrappers do not own
  // another resource, manufacture metadata or run a second result state machine.
  ConfigurationCallBinding<ConfigurationCommandReply> _settingsCall(
    ConfigurationCommandCall call,
  ) => (
    callId: () => call.callId,
    operationId: () => call.operationId,
    result: call.result,
    requestClose: call.requestClose,
    close: call.close,
    retryClose: call.retryClose,
  );

  ConfigurationCallBinding<ProfileCommandReply> _profileCall(
    ProfileCommandCall call,
  ) => (
    callId: () => call.callId,
    operationId: () => call.operationId,
    result: call.result,
    requestClose: call.requestClose,
    close: call.close,
    retryClose: call.retryClose,
  );

  ConfigurationCallBinding<ConfigurationReloadResult> _reloadCall(
    ConfigurationReloadCall call,
  ) => (
    callId: () => call.callId,
    operationId: () => call.operationId,
    result: call.result,
    requestClose: call.requestClose,
    close: call.close,
    retryClose: call.retryClose,
  );

  Future<R> _ownedCommand<R extends Object>(
    OperationId id,
    Future<ConfigurationCallBinding<R>> Function() begin,
    Future<ConfigurationCallBinding<R>?> Function() find,
    ConfigurationWriteReply Function(R) project,
  ) {
    final job = _jobs[id];
    if (job == null || !job.dispatched || job.currentCall != null)
      throw configurationProtocol(
        'The original Configuration request was not registered before begin.',
      );
    final ConfigurationCommandOwner<R> owner;
    try {
      owner = ConfigurationCommandOwner<R>(
        lifetime: host.lifetime,
        operationId: id,
        priorCallIds: job.calls
            .map((call) => call.callId)
            .whereType<String>()
            .toSet(),
        cleanupAttempt: () => host.cleanupAttempt,
        project: project,
        find: find,
        reconcile: (call) => _reconcile(job, call),
        changed: () => _release(job),
      );
    } catch (error) {
      // This is local registration, before the native begin callback can run.
      throw RejectedCommandDispatchFailure(
        failure: configurationFailure(error),
      );
    }
    // Both the frozen typed request and its owner are retained before start can
    // execute the port callback, including synchronous reentry and late open.
    job.calls.add(owner);
    job.currentCall = owner;
    return owner.start(begin);
  }

  Future<void> _synchronize(
    ConfigurationWriteJobBase job,
    ConfigurationWriteReply reply,
  ) async {
    // One receiver can reject synchronously (for example after seal). Observe
    // every admitted peer even then; never orphan an earlier target Future.
    await Future.wait<void>([
      Future<void>.sync(
        () => host.synchronizeConfiguration(
          reply.configuration,
          receipt: reply.receipt,
        ),
      ),
      Future<void>.sync(() => modelTargets.synchronize(reply.models)),
      if (reply.profiles case final profiles?)
        Future<void>.sync(
          () => host.synchronizeProfiles(profiles, receipt: reply.receipt),
        ),
    ]);
    job.currentCall?.synchronized(reply.receipt);
  }

  Future<void> _reconcile(
    ConfigurationWriteJobBase job,
    ConfigurationCallOwner call,
  ) async {
    if (!identical(job.currentCall, call))
      throw configurationProtocol(
        'A retired Configuration call cannot settle another attempt.',
      );
    final writer = job.writer;
    ConfigurationWriteReply reply;
    try {
      reply = await call.readReply();
    } on RejectedCommandDispatchFailure catch (error) {
      writer.rejected(error.failure);
      return;
    } on CommittedButUnobservedCommandDispatchFailure catch (error) {
      final state = writer.ticket.state.value;
      if (state.receipt == null && !state.acknowledged) {
        if (error.receipt.operationId == writer.ticket.id) {
          writer.synchronizationFailed(error.failure, receipt: error.receipt);
        } else {
          writer.acknowledgedSynchronizationFailed(
            configurationProtocol(
              'The joined Configuration receipt belongs to another operation.',
            ),
          );
        }
      } else {
        writer.evidenceFailed(error.failure);
      }
      rethrow;
    } on ConfirmedWithoutUsableReceiptCommandDispatchFailure catch (error) {
      final state = writer.ticket.state.value;
      if (state.receipt == null && !state.acknowledged) {
        writer.acknowledgedSynchronizationFailed(error.failure);
      } else {
        writer.evidenceFailed(error.failure);
      }
      rethrow;
    }
    final receipt = reply.receipt;
    if (receipt != null && receipt.operationId != writer.ticket.id)
      throw configurationProtocol(
        'The original Configuration result belongs to another operation.',
      );
    final state = writer.ticket.state.value;
    if (state.acknowledged && receipt != null ||
        state.receipt != null && state.receipt != receipt) {
      throw configurationProtocol(
        'The joined Configuration result contradicts the original commit evidence.',
      );
    }
    // Only the original reply is reused. No current target, new request, CAS
    // attempt or mutation is synthesized while joining unresolved evidence.
    try {
      await _synchronize(job, reply);
    } catch (error) {
      if (state.failurePhase == OperationFailurePhase.syncFailed) {
        // Keep the first synchronization result/diagnostic, but retain the real
        // receipt and any newly joined evidence without pretending cleanup won.
        if (receipt == null) {
          writer.acknowledged(const Unit());
        } else {
          writer.accepted(const Unit(), receipt);
        }
        writer.evidenceFailed(_dispatchFailure(error));
      } else {
        if (receipt == null) {
          writer.acknowledgedSynchronizationFailed(
            _dispatchFailure(error),
            value: const Unit(),
          );
        } else {
          writer.synchronizationFailed(
            _dispatchFailure(error),
            value: const Unit(),
            receipt: receipt,
          );
        }
      }
      rethrow;
    }
    writer.identityObserved();
    if (receipt == null) {
      writer.acknowledged(const Unit());
    } else {
      writer.accepted(const Unit(), receipt);
    }
    call.observe(writer.ticket.state.value);
  }

  Future<CommandResult<Unit>> _execute(ConfigurationWriteJobBase job) async {
    final writer = job.writer;
    CommitReceipt? committed;
    var confirmedWithoutReceipt = false;
    for (var recovery = 0; ; recovery++) {
      job.nextAttempt();
      try {
        if (_sealed || host.sealed) {
          writer.rejected(configurationCancelled);
          break;
        }
        final reply = await job.dispatch();
        final receipt = reply.receipt;
        if (receipt != null && receipt.operationId != writer.ticket.id)
          throw ConfirmedWithoutUsableReceiptCommandDispatchFailure(
            failure: configurationProtocol(
              'The native Settings receipt belongs to another operation.',
            ),
          );
        committed = receipt;
        confirmedWithoutReceipt = receipt == null;
        await _synchronize(job, reply);
        writer.identityObserved();
        if (receipt == null) {
          // Actual reply targets were synchronized; this is observation evidence,
          // not a fabricated receipt/effect/durable guarantee for disk import.
          writer.acknowledged(const Unit());
        } else {
          writer.accepted(const Unit(), receipt);
          if (!writer.ticket.state.value.observed)
            writer.synchronizationFailed(
              configurationProtocol(
                'The Settings source clocks did not cover the real receipt.',
              ),
              value: const Unit(),
              receipt: receipt,
            );
        }
        break;
      } catch (error, stack) {
        host.retainFailure(error, stack);
        final failure = _dispatchFailure(error);
        if (committed != null) {
          writer.synchronizationFailed(
            failure,
            value: const Unit(),
            receipt: committed,
          );
        } else if (confirmedWithoutReceipt) {
          writer.acknowledgedSynchronizationFailed(
            failure,
            value: const Unit(),
          );
        } else if (error is RejectedCommandDispatchFailure) {
          final call = job.currentCall;
          final retryRequested =
              error.failure.code == StudioFailureCode.staleRevision &&
              recovery < 2 &&
              !_sealed &&
              !host.sealed;
          if (retryRequested) {
            // Never capture another CAS request until the old call is really
            // Clean. Cleanup failure stops this retry without rewriting it.
            if (call != null) await call.cleanup(retry: false);
            final closed = call == null || call.released && call.issues.isEmpty;
            if (closed && !_sealed && !host.sealed) {
              try {
                await host.recoverCanonicalRead();
                continue;
              } catch (readError, readStack) {
                host.retainFailure(readError, readStack);
                writer.evidenceFailed(configurationFailure(readError));
              }
            }
          }
          writer.rejected(error.failure);
          call?.cleanup(retry: false).ignore();
        } else if (error is CommittedButUnobservedCommandDispatchFailure) {
          if (error.receipt.operationId == writer.ticket.id) {
            writer.synchronizationFailed(error.failure, receipt: error.receipt);
          } else {
            writer.acknowledgedSynchronizationFailed(
              configurationProtocol(
                'The committed receipt cannot be mapped to its original operation.',
              ),
            );
          }
        } else if (error
            is ConfirmedWithoutUsableReceiptCommandDispatchFailure) {
          writer.acknowledgedSynchronizationFailed(error.failure);
        } else if (error is UnknownOutcomeCommandDispatchFailure ||
            job.dispatched) {
          writer.unknownOutcome(failure);
        } else {
          writer.rejected(failure);
        }
        job.retainUnresolved();
        break;
      }
    }
    job.finished = true;
    _release(job);
    return writer.ticket.result;
  }

  StudioFailure _dispatchFailure(Object error) => switch (error) {
    RejectedCommandDispatchFailure(:final failure) ||
    UnknownOutcomeCommandDispatchFailure(:final failure) ||
    CommittedButUnobservedCommandDispatchFailure(:final failure) ||
    ConfirmedWithoutUsableReceiptCommandDispatchFailure(
      :final failure,
    ) => failure,
    _ => configurationFailure(error),
  };

  static const _batchStopped = StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'This field was not dispatched because a preceding batch step did not finish successfully.',
    retryable: false,
    correlationId: 'configuration-batch',
  );
}

final class _LaneSlot {
  _LaneSlot(this.previous);
  final Future<void> previous;
  void Function(StudioFailure)? refused;
  final Completer<Future<void> Function()?> ready = Completer();
  final Completer<void> done = Completer();
}

final class _SettingsBatch implements SettingsWriteBatch {
  _SettingsBatch(List<OperationObservation> operations, this.result)
    : operations = List.unmodifiable(operations);
  @override
  final List<OperationObservation> operations;
  @override
  final Future<SettingsBatchResult> result;
}

String configurationFieldTarget(SettingsFieldUpdate update) => switch (update) {
  DelegationModeUpdate() => 'configuration:delegation:mode',
  DelegationPreferenceUpdate() => 'configuration:delegation:preference',
  InstructionBaseOverride() => 'configuration:instructions:base',
  InstructionDeveloper() => 'configuration:instructions:developer',
  InstructionUser() => 'configuration:instructions:user',
  ProjectDocMaxBytes() => 'configuration:instructions:bytes',
  ProjectDocFallbackFilenames() => 'configuration:instructions:filenames',
  SkillsEnabled() => 'configuration:skills:enabled',
  SkillsAutoLearn() => 'configuration:skills:auto-learn',
  SkillsSystemEnabled() => 'configuration:skills:system',
  SkillsProjectDir() => 'configuration:skills:project-dir',
  SkillsUserDir() => 'configuration:skills:user-dir',
  SkillsExternalDirs() => 'configuration:skills:external',
  SkillsDisabled() => 'configuration:skills:disabled',
  SkillsAutoLearnMinToolCalls() => 'configuration:skills:min-calls',
  McpServerEnabled(:final id) => 'configuration:mcp-enabled:${id.length}:$id',
  McpServerTransport(:final id) =>
    'configuration:mcp-transport:${id.length}:$id',
  McpServerEndpoint(:final id) => 'configuration:mcp-endpoint:${id.length}:$id',
  GeneralFollowActiveTurn() => 'configuration:general:follow',
  GeneralCompactTimeline() => 'configuration:general:compact',
  GeneralSidebarWidth() => 'configuration:general:width',
  GeneralPinnedThreadIds() => 'configuration:general:threads',
  GeneralPinnedProjectIds() => 'configuration:general:projects',
  WebSearchMode() => 'configuration:search:mode',
  WebSearchContextSize() => 'configuration:search:context',
  WebSearchAllowedDomains() => 'configuration:search:domains',
  WebSearchCountry() => 'configuration:search:country',
  WebSearchRegion() => 'configuration:search:region',
  WebSearchCity() => 'configuration:search:city',
  WebSearchTimezone() => 'configuration:search:timezone',
  DeepSeekWebSearchEnabled() => 'configuration:deepseek:search',
  DeepSeekWebFetchEnabled() => 'configuration:deepseek:fetch',
  ModeModel(:final modeId) =>
    'configuration:mode-model:${modeId.length}:$modeId',
  ModeReasoningEffort(:final modeId) =>
    'configuration:mode-effort:${modeId.length}:$modeId',
  RoleModel(:final role) => 'configuration:role-model:${role.length}:$role',
  RoleReasoningEffort(:final role) =>
    'configuration:role-effort:${role.length}:$role',
};
