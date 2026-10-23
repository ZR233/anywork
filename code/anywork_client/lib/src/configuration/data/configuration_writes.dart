import 'dart:async';

import '../../../models_ports.dart' show ModelCatalogTargetReceiver;
import '../../../operations.dart';
import '../../../operations_ports.dart' show OperationRecorder, RejectedCommandDispatchFailure, UnknownOutcomeCommandDispatchFailure, CommittedButUnobservedCommandDispatchFailure, ConfirmedWithoutUsableReceiptCommandDispatchFailure;
import '../../../resources.dart';
import '../../../resources_ports.dart' show ResourceBudget;
import '../domain/account_edits.dart';
import '../domain/configuration_repository.dart';
import '../domain/configuration_values.dart';
import '../domain/profile_values.dart';
import '../domain/settings_updates.dart';
import 'account_intent.dart';
import 'configuration_commands.dart';
import 'configuration_port.dart';
import 'configuration_read_fields.dart';
import 'configuration_write_context.dart';
import 'configuration_write_job.dart';

/// One Settings CAS lane. Lane slots are reserved before begin() can notify
/// observers and reenter, so a newer intent cannot jump ahead of its predecessor.
final class ConfigurationWrites {
  ConfigurationWrites({required this.port, required this.host, required this.operations, required this.modelTargets, required this.budget});
  final ConfigurationPort port;
  final ConfigurationWriteHost host;
  final OperationRecorder operations;
  final ModelCatalogTargetReceiver modelTargets;
  final ResourceBudget budget;
  final Map<OperationId, ConfigurationWriteJobBase> _jobs = {};
  Future<void> _tail = Future.value();
  bool _sealed = false;
  int _attempt = 0;

  void _admit() { host.admit(); if (_sealed) throw configurationCancelled; }
  void seal() => _sealed = true;
  Future<void> join() => _tail;
  List<UnresolvedResource> get unresolved => List.unmodifiable([
    for (final job in _jobs.values)
      UnresolvedResource(owner: 'configuration:operation:${job.writer.ticket.id.value}', attemptId: job.attempt, issues: [FeedCloseIssue(diagnostic: StudioShutdownIssue(stage: 'configuration', code: job.writer.ticket.state.value.failurePhase?.name ?? 'commandEvidencePending', message: 'The original configuration operation has unresolved outcome or receipt observation.', retryable: job.writer.ticket.state.value.error?.retryable ?? false, correlationId: job.writer.ticket.state.value.error?.correlationId ?? 'configuration'), recovery: job.finished ? CleanupRecovery.terminal : CleanupRecovery.awaitCompletion)]),
  ]);

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
      try { if (action != null) await action(); } finally { slot.done.complete(); }
      });
    } catch (error, stack) {
      host.retainFailure(error, stack);
      slot.refused?.call(configurationFailure(error));
      if (!slot.done.isCompleted) slot.done.complete();
      return;
    }
    work.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      host.retainFailure(error, stack);
      if (!slot.done.isCompleted) slot.done.complete();
    });
  }

  ConfigurationWriteJob<T, P> _begin<T, P>(String target, T intent, Future<ConfigurationWriteReply> Function(T, OperationId, void Function(P, ProductReadOrigin)) send) {
    final writer = operations.begin<Unit>(target: target);
    try {
      final job = ConfigurationWriteJob<T, P>(writer: writer, attempt: AttemptId(++_attempt), intent: intent, send: (intent, id, capture) => send(intent, id, (request, origin) {
        // Reading a fresh CAS base is not dispatch. A synchronous seal while
        // awaiting it must still reject this not-yet-sent step.
        if (_sealed || host.sealed) throw configurationCancelled;
        capture(request, origin);
      }));
      job.evidencePermit = budget.acquire(ResourceKind.observer, owner: 'configuration:operation:${writer.ticket.id.value}');
      _jobs[writer.ticket.id] = job;
      void observe(OperationState _) {
        if (!job.proven) return;
        if (identical(_jobs[writer.ticket.id], job)) _jobs.remove(writer.ticket.id);
        job.releaseObservation();
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

  OperationTicket<Unit> _single<T, P>(String target, T intent, Future<ConfigurationWriteReply> Function(T, OperationId, void Function(P, ProductReadOrigin)) send) {
    final slot = _reserve();
    try {
      final job = _begin<T, P>(target, intent, send);
      slot.refused = job.writer.rejected;
      slot.ready.complete(() async { await _execute(job); });
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
    return _single<AccountEdit, UpdateAccountRequest>('configuration:account:${intent.accountId.length}:${intent.accountId}', intent, (intent, id, capture) async {
      final base = await host.accountWriteBase(intent.accountId);
      final request = UpdateAccountRequest(operationId: id, expectedRevision: base.revision, account: buildAccountUpdate(intent, base.account));
      capture(request, base.origin);
      return ConfigurationWriteReply.settings(await port.saveAccount(request));
    });
  }

  OperationTicket<Unit> setDefaultAccount(String accountId) => _single<String, SetDefaultAccountRequest>('configuration:default-account', accountId, (accountId, id, capture) async {
    final base = await host.currentWriteBase();
    final request = SetDefaultAccountRequest(operationId: id, expectedRevision: base.revision, accountId: accountId);
    capture(request, base.origin);
    return ConfigurationWriteReply.settings(await port.setDefaultAccount(request));
  });

  OperationTicket<Unit> removeAccount(String accountId, {String? replacementAccountId}) => _single<({String accountId, String? replacement}), RemoveAccountRequest>('configuration:account:${accountId.length}:$accountId', (accountId: accountId, replacement: replacementAccountId), (intent, id, capture) async {
    final base = await host.currentWriteBase();
    final request = RemoveAccountRequest(operationId: id, expectedRevision: base.revision, accountId: intent.accountId, replacementAccountId: intent.replacement);
    capture(request, base.origin);
    return ConfigurationWriteReply.settings(await port.removeAccount(request));
  });

  OperationTicket<Unit> removeAccountModel(String accountId, String modelId) => _single<({String accountId, String modelId}), RemoveAccountModelRequest>('configuration:account-model:${accountId.length}:$accountId:$modelId', (accountId: accountId, modelId: modelId), (intent, id, capture) async {
    final base = await host.currentWriteBase();
    final request = RemoveAccountModelRequest(operationId: id, expectedRevision: base.revision, accountId: intent.accountId, modelId: intent.modelId);
    capture(request, base.origin);
    return ConfigurationWriteReply.settings(await port.removeAccountModel(request));
  });

  OperationTicket<Unit> applyField(SettingsFieldUpdate value) {
    _admit();
    final intent = freezeSettingsUpdate(value);
    return _single<SettingsFieldUpdate, UpdateSettingsFieldRequest>(configurationFieldTarget(intent), intent, _sendField);
  }

  Future<ConfigurationWriteReply> _sendField(SettingsFieldUpdate intent, OperationId id, void Function(UpdateSettingsFieldRequest, ProductReadOrigin) capture) async {
    final base = await host.currentWriteBase();
    final request = UpdateSettingsFieldRequest(operationId: id, expectedRevision: base.revision, update: intent);
    capture(request, base.origin);
    return ConfigurationWriteReply.settings(await port.applyField(request));
  }

  SettingsWriteBatch applyFields(List<SettingsFieldUpdate> values) {
    _admit();
    final intents = List<SettingsFieldUpdate>.unmodifiable(values.map(freezeSettingsUpdate));
    if (intents.isEmpty) return _SettingsBatch(const [], Future.value(SettingsBatchResult(steps: const [])));
    final slot = _reserve();
    final jobs = <ConfigurationWriteJob<SettingsFieldUpdate, UpdateSettingsFieldRequest>>[];
    try {
      for (final intent in intents) { jobs.add(_begin<SettingsFieldUpdate, UpdateSettingsFieldRequest>(configurationFieldTarget(intent), intent, _sendField)); }
    } catch (error) {
      for (final job in jobs) { job.writer.rejected(configurationFailure(error)); }
      slot.ready.complete(null);
      _activate(slot);
      rethrow;
    }
    final completed = Completer<SettingsBatchResult>();
    slot.refused = (error) {
      final steps = <SettingsFieldResult>[];
      for (var index = 0; index < jobs.length; index++) {
        final job = jobs[index];
        job.writer.rejected(error);
        steps.add(SettingsFieldResult.notStarted(index: index, operationId: job.writer.ticket.id, error: error));
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
          job.writer.rejected(error);
          steps.add(SettingsFieldResult.notStarted(index: index, operationId: job.writer.ticket.id, error: error));
          stopped ??= error;
          continue;
        }
        final result = await _execute(job);
        steps.add(SettingsFieldResult.finished(index: index, operationId: job.writer.ticket.id, result: result));
        if (result is! CommittedCommandResult<Unit> && result is! AcknowledgedCommandResult<Unit>) stopped = _batchStopped;
      }
      completed.complete(SettingsBatchResult(steps: List.unmodifiable(steps)));
    });
    _activate(slot);
    return _SettingsBatch(List.unmodifiable([for (final job in jobs) job.writer.ticket]), completed.future);
  }

  OperationTicket<Unit> setPermissionMode(PermissionMode mode) => _single<PermissionMode, UpdatePermissionSettingsRequest>('configuration:permission', mode, (mode, id, capture) async {
    final base = await host.currentWriteBase();
    final label = switch (mode) { PermissionMode.requestApproval => 'request-approval', PermissionMode.autoReview => 'auto-review', PermissionMode.fullAccess => 'full-access' };
    final request = UpdatePermissionSettingsRequest(operationId: id, expectedRevision: base.revision, mode: label);
    capture(request, base.origin);
    return ConfigurationWriteReply.settings(await port.setPermission(request));
  });

  OperationTicket<Unit> saveProfile(AgentProfileEdit intent) => _single<AgentProfileEdit, SaveProfileRequest>('configuration:profile:${intent.profileId.length}:${intent.profileId}', intent, (intent, id, capture) async {
    final base = await host.currentWriteBase();
    final request = SaveProfileRequest(operationId: id, expectedSettingsRevision: base.revision, profile: intent);
    capture(request, base.origin);
    return ConfigurationWriteReply.profile(await port.saveProfile(request));
  });

  OperationTicket<Unit> setSystemProfileEnabled(String profileId, bool enabled) => _single<({String profileId, bool enabled}), SetSystemProfileEnabledRequest>('configuration:profile:${profileId.length}:$profileId', (profileId: profileId, enabled: enabled), (intent, id, capture) async {
    final base = await host.currentWriteBase();
    final request = SetSystemProfileEnabledRequest(operationId: id, expectedSettingsRevision: base.revision, profileId: intent.profileId, enabled: intent.enabled);
    capture(request, base.origin);
    return ConfigurationWriteReply.profile(await port.setSystemProfileEnabled(request));
  });

  OperationTicket<Unit> reload() => _single<Unit, int>('configuration:reload', const Unit(), (_, id, capture) async {
    final base = await host.currentWriteBase();
    capture(base.revision, base.origin);
    return ConfigurationWriteReply.reload(await port.reload(expectedRevision: base.revision));
  });

  Future<CommandResult<Unit>> _execute(ConfigurationWriteJobBase job) async {
    final writer = job.writer;
    CommitReceipt? committed;
    var confirmedWithoutReceipt = false;
    for (var recovery = 0; ; recovery++) {
      job.nextAttempt();
      try {
        if (_sealed || host.sealed) { writer.rejected(configurationCancelled); break; }
        final reply = await job.dispatch();
        final receipt = reply.receipt;
        if (receipt != null && receipt.operationId != writer.ticket.id) throw ConfirmedWithoutUsableReceiptCommandDispatchFailure(failure: configurationProtocol('The native Settings receipt belongs to another operation.'));
        committed = receipt;
        confirmedWithoutReceipt = receipt == null;
        await Future.wait([
          host.synchronizeConfiguration(reply.configuration, receipt: receipt),
          modelTargets.synchronize(reply.models),
          if (reply.profiles case final profiles?) host.synchronizeProfiles(profiles, receipt: receipt),
        ]);
        if (receipt == null) {
          // Actual reply targets were synchronized; this is observation evidence,
          // not a fabricated receipt/effect/durable guarantee for disk import.
          writer.identityObserved();
          writer.acknowledged(const Unit());
        } else {
          writer.accepted(const Unit(), receipt);
          if (!writer.ticket.state.value.observed) writer.synchronizationFailed(configurationProtocol('The Settings source clocks did not cover the real receipt.'), value: const Unit(), receipt: receipt);
        }
        break;
      } catch (error, stack) {
        host.retainFailure(error, stack);
        final failure = _dispatchFailure(error);
        if (committed != null) {
          writer.synchronizationFailed(failure, value: const Unit(), receipt: committed);
        } else if (confirmedWithoutReceipt) {
          writer.acknowledgedSynchronizationFailed(failure, value: const Unit());
        } else if (error is RejectedCommandDispatchFailure) {
          if (error.failure.code == StudioFailureCode.staleRevision && recovery < 2 && !_sealed && !host.sealed) {
            try { await host.recoverCanonicalRead(); continue; } catch (readError, readStack) {
              host.retainFailure(readError, readStack);
              writer.evidenceFailed(configurationFailure(readError));
            }
          }
          writer.rejected(error.failure);
        } else if (error is CommittedButUnobservedCommandDispatchFailure) {
          if (error.receipt.operationId == writer.ticket.id) { writer.synchronizationFailed(error.failure, receipt: error.receipt); } else { writer.acknowledgedSynchronizationFailed(configurationProtocol('The committed receipt cannot be mapped to its original operation.')); }
        } else if (error is ConfirmedWithoutUsableReceiptCommandDispatchFailure) {
          writer.acknowledgedSynchronizationFailed(error.failure);
        } else if (error is UnknownOutcomeCommandDispatchFailure || job.dispatched) {
          writer.unknownOutcome(failure);
        } else {
          writer.rejected(failure);
        }
        job.retainUnresolved();
        break;
      }
    }
    job.finished = true;
    return writer.ticket.result;
  }

  StudioFailure _dispatchFailure(Object error) => switch (error) {
    RejectedCommandDispatchFailure(:final failure) || UnknownOutcomeCommandDispatchFailure(:final failure) || CommittedButUnobservedCommandDispatchFailure(:final failure) || ConfirmedWithoutUsableReceiptCommandDispatchFailure(:final failure) => failure,
    _ => configurationFailure(error),
  };

  static const _batchStopped = StudioFailure(code: StudioFailureCode.cancelled, message: 'This field was not dispatched because a preceding batch step did not finish successfully.', retryable: false, correlationId: 'configuration-batch');
}

final class _LaneSlot {
  _LaneSlot(this.previous);
  final Future<void> previous;
  void Function(StudioFailure)? refused;
  final Completer<Future<void> Function()?> ready = Completer();
  final Completer<void> done = Completer();
}

final class _SettingsBatch implements SettingsWriteBatch {
  _SettingsBatch(List<OperationObservation> operations, this.result) : operations = List.unmodifiable(operations);
  @override
  final List<OperationObservation> operations;
  @override
  final Future<SettingsBatchResult> result;
}

String configurationFieldTarget(SettingsFieldUpdate update) => switch (update) {
  InstructionBaseOverride() => 'configuration:instructions:base', InstructionDeveloper() => 'configuration:instructions:developer', InstructionUser() => 'configuration:instructions:user', ProjectDocMaxBytes() => 'configuration:instructions:bytes', ProjectDocFallbackFilenames() => 'configuration:instructions:filenames',
  SkillsEnabled() => 'configuration:skills:enabled', SkillsAutoLearn() => 'configuration:skills:auto-learn', SkillsSystemEnabled() => 'configuration:skills:system', SkillsProjectDir() => 'configuration:skills:project-dir', SkillsUserDir() => 'configuration:skills:user-dir', SkillsExternalDirs() => 'configuration:skills:external', SkillsDisabled() => 'configuration:skills:disabled', SkillsAutoLearnMinToolCalls() => 'configuration:skills:min-calls',
  McpServerEnabled(:final id) => 'configuration:mcp-enabled:${id.length}:$id', McpServerTransport(:final id) => 'configuration:mcp-transport:${id.length}:$id', McpServerEndpoint(:final id) => 'configuration:mcp-endpoint:${id.length}:$id',
  GeneralFollowActiveTurn() => 'configuration:general:follow', GeneralCompactTimeline() => 'configuration:general:compact', GeneralSidebarWidth() => 'configuration:general:width', GeneralPinnedThreadIds() => 'configuration:general:threads', GeneralPinnedProjectIds() => 'configuration:general:projects',
  WebSearchMode() => 'configuration:search:mode', WebSearchContextSize() => 'configuration:search:context', WebSearchAllowedDomains() => 'configuration:search:domains', WebSearchCountry() => 'configuration:search:country', WebSearchRegion() => 'configuration:search:region', WebSearchCity() => 'configuration:search:city', WebSearchTimezone() => 'configuration:search:timezone', DeepSeekWebSearchEnabled() => 'configuration:deepseek:search', DeepSeekWebFetchEnabled() => 'configuration:deepseek:fetch',
  ModeModel(:final modeId) => 'configuration:mode-model:${modeId.length}:$modeId', ModeReasoningEffort(:final modeId) => 'configuration:mode-effort:${modeId.length}:$modeId', RoleModel(:final role) => 'configuration:role-model:${role.length}:$role', RoleReasoningEffort(:final role) => 'configuration:role-effort:${role.length}:$role',
};
