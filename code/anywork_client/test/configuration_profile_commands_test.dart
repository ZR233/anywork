import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/profile_command_fixture.dart';
import 'support/profile_configuration_port.dart';
import 'support/profile_editor_fixture.dart';
import 'support/profile_reload_fixture.dart';

const _refused = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'Native explicitly refused this original Profile intent.',
  retryable: false,
  correlationId: 'profile-business-refusal',
);
const _stale = StudioFailure(
  code: StudioFailureCode.staleRevision,
  message: 'Native rejected the original CAS base before adoption.',
  retryable: true,
  correlationId: 'profile-reload-stale',
);
const _captureFailed = StudioFailure(
  code: StudioFailureCode.storage,
  message: 'The original save/adoption succeeded but its captured result was not exposed.',
  retryable: true,
  correlationId: 'profile-original-capture',
);
const _joinFailed = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'profile-native',
    code: 'originalCallJoinFailed',
    message: 'Original native cleanup still needs a retry.',
    retryable: true,
    correlationId: 'profile-call-close',
  ),
  recovery: CleanupRecovery.retryClose,
);

final class _Scenario {
  _Scenario({AgentProfileSnapshot? profile})
    : owner = ProfileEditorFixture(profile: profile ?? profileSnapshot());
  final ProfileEditorFixture owner;
  ConfigurationRepository get repository => owner.configuration;
  ProfileConfigurationPort get port => owner.configurationPort;
  CloseReport? retainedReport;

  Future<void> finish() async {
    // Every scripted API response has settled. A deliberately retained owner
    // below is unresolved evidence, not an abandoned in-flight environment
    // Future hidden by a deadline or by teardown returning early.
    for (final call in port.saves) {
      expect(call.beginReply.isCompleted, isTrue);
      _settled(call.native);
    }
    for (final call in port.enabledChanges) {
      expect(call.beginReply.isCompleted, isTrue);
      _settled(call.native);
    }
    for (final call in port.reloads) {
      expect(call.beginReply.isCompleted, isTrue);
      _settled(call.native);
    }
    for (final lookup in port.profileLookups) {
      expect(lookup.reply.isCompleted, isTrue);
    }
    for (final lookup in port.reloadLookups) {
      expect(lookup.reply.isCompleted, isTrue);
    }
    for (final header in owner.modelPort.catalogHeaders) {
      expect(header.reply.isCompleted, isTrue);
    }
    final report =
        retainedReport ??
        await repository.close(
          deadline: DateTime.now().add(const Duration(seconds: 3)),
        );
    final models = await owner.models.close(
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    );
    expect(models.complete, isTrue);
    if (retainedReport == null) {
      expect(report.unresolved, isEmpty);
      expect(
        owner.budget.usage,
        isEmpty,
        reason: 'Every admitted original command, target, native pin and feed must actually join',
      );
    } else {
      expect(
        report.unresolved.any(
          (item) => item.owner.startsWith('configuration:call:'),
        ),
        isTrue,
      );
      expect(
        owner.budget.usage,
        isNotEmpty,
        reason: 'Unprovable evidence is explicitly retained, never erased by a fake Clean',
      );
    }
  }
}

void _settled<R>(ScriptedProfileNativeCall<R> native) {
  for (var index = 0; index < native.resultCalls; index++) {
    expect(native.resultAt(index).reply.isCompleted, isTrue);
  }
  for (final closing in native.closes) {
    expect(closing.reply.isCompleted, isTrue);
  }
}

Future<_Scenario> _scenario({AgentProfileSnapshot? profile}) async {
  final fixture = _Scenario(profile: profile);
  fixture.port.scriptProfileCommands = true;
  fixture.port.scriptReload = true;
  addTearDown(fixture.finish);
  await fixture.owner.establish();
  return fixture;
}

AgentProfileEdit _edit() => const AgentProfileEdit(
  profileId: 'custom_profile',
  displayName: 'Profile',
  description: 'A custom profile',
  whenToUse: 'For this task',
  systemInstructions: 'Keep the original instructions.',
  accountId: 'account-0',
  modelId: 'text',
  effort: 'low',
  enabled: true,
  workspaceMode: AgentWorkspaceMode.directory,
);

/// Explicit native materials, never derived from the request or SDK latest.
ConfigurationReloadResult _targets(
  _Scenario fixture, {
  int settings = 2,
  int catalog = 2,
  int profiles = 8,
}) => ConfigurationReloadResult(
  configuration: ConfigurationReadTarget(
    origin: fixture.owner.origin,
    reference: ConfigurationReadRef(entry: 1, revision: settings),
  ),
  models: ModelCatalogReadTarget(
    origin: fixture.owner.origin,
    reference: ModelCatalogReadRef(entry: 1, revision: catalog),
  ),
  profiles: AgentProfilesReadTarget(
    origin: fixture.owner.origin,
    reference: AgentProfilesReadRef(entry: 1, revision: profiles),
  ),
);

ProfileCommandReply _profileReply(
  OperationId operationId,
  ConfigurationReloadResult targets, {
  CommitDisposition disposition = CommitDisposition.applied,
}) => ProfileCommandReply(
  receipt: CommitReceipt(
    operationId: operationId,
    disposition: disposition,
    targets: [
      ResourceStamp(
        resourceKey: 'settings',
        ownerEpoch: targets.configuration.origin.ownerEpoch,
        revision: targets.configuration.reference.revision,
      ),
      ResourceStamp(
        resourceKey: 'agent-profiles',
        ownerEpoch: targets.profiles.origin.ownerEpoch,
        revision: targets.profiles.reference.revision,
      ),
    ],
    effect: EffectPoint.futureSession,
    effective: false,
    durable: true,
  ),
  configuration: targets.configuration,
  models: targets.models,
  profiles: targets.profiles,
);

void _stillOwned<R>(
  _Scenario fixture,
  OperationTicket<Unit> ticket,
  ScriptedProfileNativeCall<R> call,
) {
  expect(
    (ticket.state.value.observed, ticket.state.value.acknowledged),
    (false, false),
  );
  expect(call.requestCloseCalls, 0);
  expect(call.closes, isEmpty);
  expect(
    fixture.owner.budget.usage.any(
      (usage) =>
          usage.kind == ResourceKind.pendingOperation &&
          usage.owner == ticket.id.value,
    ),
    isTrue,
  );
  expect(
    fixture.owner.budget.usage.any(
      (usage) => usage.owner == 'configuration:operation:${ticket.id.value}',
    ),
    isTrue,
    reason: 'Request/evidence responsibility was registered before the native begin await',
  );
}

Future<void> _clean<R>(
  ScriptedProfileNativeCall<R> call, [
  int index = 0,
]) async {
  final closing = await call.closed(index);
  closing.reply.complete(
    FeedCloseReport(
      feedId: call.callId,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
}

void main() {
  for (final systemEnabled in [false, true]) {
    test(
      '${systemEnabled ? 'system enabled' : 'Profile save'} freezes the typed intent and waits for every original target before close',
      () async {
        final original = systemEnabled
            ? profileSnapshot().copyWith(profileId: 'executor', system: true)
            : profileSnapshot();
        final fixture = await _scenario(profile: original);
        final ticket = systemEnabled
            ? fixture.repository.setSystemProfileEnabled('executor', false)
            : fixture.repository.saveProfile(
                _edit().copyWith(description: 'Saved raw intent', effort: null),
              );
        final ScriptedProfileCommandCall native;
        if (systemEnabled) {
          final call = await fixture.port.enabledChanged(0);
          expect(
            call.request,
            SetSystemProfileEnabledRequest(
              operationId: ticket.id,
              expectedSettingsRevision: 1,
              profileId: 'executor',
              enabled: false,
            ),
          );
          native = call.native;
          _stillOwned(fixture, ticket, native);
          call.accept();
        } else {
          final call = await fixture.port.saved(0);
          expect(
            call.request,
            SaveProfileRequest(
              operationId: ticket.id,
              expectedSettingsRevision: 1,
              profile: _edit().copyWith(
                description: 'Saved raw intent',
                effort: null,
              ),
            ),
          );
          native = call.native;
          _stillOwned(fixture, ticket, native);
          call.accept();
        }
        expect(native.callId, isNot(ticket.id.value));
        expect(
          await fixture.repository.loadProfile(original.profileId),
          original,
          reason: 'Admission is not an optimistic canonical update',
        );
        final resultRead = await native.resultRead(0);
        final targets = _targets(fixture);
        final reply = _profileReply(ticket.id, targets);
        fixture.port.profileSnapshots[8] = systemEnabled
            ? original.copyWith(
                enabled: false,
                revision: 'native-profile-8',
                contentHash: 'disabled-native-hash',
              )
            : original.copyWith(
                description: 'Saved raw intent',
                effort: null,
                revision: 'native-profile-8',
                contentHash: 'saved-native-hash',
              );
        fixture.owner.modelPort.declaredCatalogs.add(2);
        fixture.owner.modelPort.holdCatalogHeaders = true;
        final headerIndex = fixture.owner.modelPort.catalogHeaders.length;
        resultRead.reply.complete(reply);
        final header = await fixture.owner.modelPort.catalogHeaderCalled(
          headerIndex,
        );
        expect(header.catalog, targets.models);
        _stillOwned(fixture, ticket, native);
        header.accept();

        // Save publishes both receipt clocks before Models; enabled publishes
        // Models/Settings before Profiles. Neither two-target subset is enough.
        if (systemEnabled) await fixture.owner.modelPort.advanceCatalog();
        await fixture.port.publishSettings(2);
        if (!systemEnabled) await fixture.port.publishProfiles(8);
        _stillOwned(fixture, ticket, native);
        final waiting = await fixture.repository.close(
          deadline: DateTime.utc(2000),
        );
        expect(waiting.complete, isFalse);
        expect(
          waiting.unresolved.any(
            (item) => item.owner == 'configuration:write-lane',
          ),
          isTrue,
        );
        _stillOwned(fixture, ticket, native);
        expect(
          fixture.port.feed.requestCloseCalls,
          0,
          reason: 'SDK-only close keeps the real accepted target sources open',
        );
        if (systemEnabled)
          await fixture.port.publishProfiles(8);
        else
          await fixture.owner.modelPort.advanceCatalog();
        final result = await ticket.result;
        expect(result, isA<CommittedCommandResult<Unit>>());
        expect((result as CommittedCommandResult<Unit>).receipt, reply.receipt);
        expect(
          (
            ticket.state.value.receipt,
            ticket.state.value.observed,
            ticket.state.value.durable,
          ),
          (reply.receipt, true, true),
        );
        expect(ticket.state.value.effective, isFalse);
        final nativeClose = await native.closed(0);
        expect(native.requestCloseCalls, 1);
        expect(
          (await fixture.repository.close(deadline: DateTime.utc(2000)))
              .complete,
          isFalse,
          reason: 'Observed business success does not join a still-pending native close',
        );
        nativeClose.reply.complete(
          FeedCloseReport(
            feedId: native.callId,
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
        expect((await fixture.repository.retryCleanup()).complete, isTrue);
        expect(native.resultCalls, 1);
        expect(native.closeCalls + native.retryCloseCalls, 1);
        expect(fixture.port.profileLookups, isEmpty);
        expect(
          fixture.port.saves.length + fixture.port.enabledChanges.length,
          1,
        );
      },
    );
  }

  test('reload has no receipt and concurrent deadlines retain late begin, result, all three targets and native close', () async {
    final fixture = await _scenario();
    final ticket = fixture.repository.reload();
    final call = await fixture.port.reloaded(
      0,
    ); // Native begin has really entered.
    expect(
      call.request,
      ConfigurationReloadRequest(operationId: ticket.id, expectedRevision: 1),
    );
    _stillOwned(fixture, ticket, call.native);
    final deadlines = await Future.wait([
      fixture.repository.close(deadline: DateTime.utc(2000)),
      fixture.repository.close(deadline: DateTime.utc(2000)),
    ]);
    expect(deadlines.every((report) => !report.complete), isTrue);
    expect(call.native.resultCalls, 0);
    expect(fixture.port.feed.requestCloseCalls, 0);
    call.accept();
    final resultRead = await call.native.resultRead(0);
    expect(
      (await fixture.repository.close(deadline: DateTime.utc(2000))).complete,
      isFalse,
    );
    final targets = _targets(fixture);
    fixture.port.profileSnapshots[8] = profileSnapshot().copyWith(
      description: 'Imported from disk',
      revision: 'native-profile-8',
      contentHash: 'imported-native-hash',
    );
    fixture.owner.modelPort.declaredCatalogs.add(2);
    fixture.owner.modelPort.holdCatalogHeaders = true;
    final headerIndex = fixture.owner.modelPort.catalogHeaders.length;
    resultRead.reply.complete(targets);
    final header = await fixture.owner.modelPort.catalogHeaderCalled(
      headerIndex,
    );
    expect(header.catalog, targets.models);
    header.accept();
    await fixture.port.publishProfiles(8);
    await fixture.owner.modelPort.advanceCatalog();
    _stillOwned(fixture, ticket, call.native);
    expect(
      (await fixture.repository.close(deadline: DateTime.utc(2000))).unresolved
          .any((item) => item.owner == 'configuration:command-target'),
      isTrue,
      reason: 'The last actual Settings receiver is still admitted and waiting',
    );
    await fixture.port.publishSettings(2);
    final result = await ticket.result;
    expect(result, isA<AcknowledgedCommandResult<Unit>>());
    expect(
      (
        ticket.state.value.receipt,
        ticket.state.value.acknowledged,
        ticket.state.value.observed,
        ticket.state.value.durable,
        ticket.state.value.effective,
      ),
      (null, true, true, false, false),
    );
    expect(
      fixture.repository.profiles.value.projection.header!.reference,
      targets.profiles.reference,
    );
    expect(
      fixture.owner.models.state.value.projection.header!.reference,
      targets.models.reference,
    );
    final closing = await call.native.closed(0);
    expect(
      (await fixture.repository.close(deadline: DateTime.utc(2000))).complete,
      isFalse,
    );
    closing.reply.complete(
      FeedCloseReport(
        feedId: call.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(await ticket.result, same(result));
    expect(call.native.resultCalls, 1);
    expect(call.native.closeCalls + call.native.retryCloseCalls, 1);
    expect(fixture.port.reloads, hasLength(1));
    expect(fixture.port.reloadLookups, isEmpty);
  });

  test('reload stale CAS has at most three attempts and must Clean the old call before fresh typed revision capture', () async {
    final fixture = await _scenario();
    final ticket = fixture.repository.reload();
    final ids = <String>{};
    for (var attempt = 0; attempt < 3; attempt++) {
      final call = await fixture.port.reloaded(attempt);
      expect(
        call.request,
        ConfigurationReloadRequest(
          operationId: ticket.id,
          expectedRevision: attempt + 1,
        ),
      );
      expect(ids.add(call.native.callId), isTrue);
      expect(call.native.callId, isNot(ticket.id.value));
      call.accept();
      final resultRead = await call.native.resultRead(0);
      resultRead.reply.completeError(
        const CommandDispatchFailure.rejected(failure: _stale),
      );
      final closing = await call.native.closed(0);
      expect(closing.retry, isFalse);
      expect(fixture.port.reloads, hasLength(attempt + 1));
      expect(
        fixture.port.configurationOpens,
        hasLength(attempt + 1),
        reason: 'No fresh CAS source or replacement native call before old Clean, even though reload has no receipt',
      );
      closing.reply.complete(
        FeedCloseReport(
          feedId: call.native.callId,
          outcome: const FeedCloseOutcome.clean(),
        ),
      );
      if (attempt < 2) {
        final opening = await fixture.port.configurationOpened(attempt + 1);
        final next = opening.acceptNew('reload-cas-source-${attempt + 2}');
        await fixture.port.publishCasBaseline(next, attempt + 2);
      }
    }
    final result = await ticket.result;
    expect(result, isA<RejectedCommandResult<Unit>>());
    expect((result as RejectedCommandResult<Unit>).error, _stale);
    expect(fixture.port.reloads, hasLength(3));
    expect(fixture.port.configurationOpens, hasLength(3));
    expect(fixture.port.reloadLookups, isEmpty);
    expect(
      (
        ticket.state.value.receipt,
        ticket.state.value.acknowledged,
        ticket.state.value.observed,
      ),
      (null, false, false),
    );
  });

  test('a replacement source origin cannot dispatch a reload retry on behalf of the frozen original request', () async {
    final fixture = await _scenario();
    final ticket = fixture.repository.reload();
    final call = await fixture.port.reloaded(0);
    final frozen = call.request;
    call.accept();
    final resultRead = await call.native.resultRead(0);
    resultRead.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _stale),
    );
    await _clean(call.native);
    final opening = await fixture.port.configurationOpened(1);
    final next = opening.acceptNew('reload-replaced-origin');
    await fixture.port.publishCasBaseline(
      next,
      2,
      sourceOrigin: const ProductReadOrigin(
        ownerEpoch: 'another-native-owner',
        incarnation: 2,
      ),
    );
    final result = await ticket.result;
    expect(result, isA<RejectedCommandResult<Unit>>());
    expect(
      (result as RejectedCommandResult<Unit>).error.code,
      StudioFailureCode.superseded,
    );
    expect(call.request, frozen);
    expect(fixture.port.reloads, hasLength(1));
    expect(fixture.port.reloadLookups, isEmpty);
  });

  test('typed begin refusal creates no call while an admitted Profile rejection owns a real native close', () async {
    final fixture = await _scenario();
    final admission = fixture.repository.saveProfile(_edit());
    final refusedBegin = await fixture.port.saved(0);
    refusedBegin.beginReply.completeError(
      const CommandDispatchFailure.rejected(failure: _refused),
    );
    final admissionResult = await admission.result;
    expect(admissionResult, isA<RejectedCommandResult<Unit>>());
    expect((admissionResult as RejectedCommandResult<Unit>).error, _refused);
    expect(refusedBegin.native.resultCalls, 0);
    expect(refusedBegin.native.requestCloseCalls, 0);
    expect(refusedBegin.native.closes, isEmpty);
    expect(fixture.port.profileLookups, isEmpty);

    final business = fixture.repository.setSystemProfileEnabled(
      'executor',
      false,
    );
    final call = await fixture.port.enabledChanged(0);
    call.accept();
    final resultRead = await call.native.resultRead(0);
    resultRead.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _refused),
    );
    final rejected = await business.result;
    expect(rejected, isA<RejectedCommandResult<Unit>>());
    expect((rejected as RejectedCommandResult<Unit>).error, _refused);
    final closing = await call.native.closed(0);
    expect(call.native.requestCloseCalls, 1);
    expect(
      (await fixture.repository.close(deadline: DateTime.utc(2000))).complete,
      isFalse,
    );
    closing.reply.complete(
      FeedCloseReport(
        feedId: call.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(
      (
        business.state.value.receipt,
        business.state.value.acknowledged,
        business.state.value.observed,
      ),
      (null, false, false),
    );
  });

  test('unscripted Profile, reload and existing Configuration begins fail typed admission instead of entering hanging lookup', () async {
    final fixture = await _scenario();
    fixture.port.scriptProfileCommands = false;
    fixture.port.scriptReload = false;
    final tickets = [
      fixture.repository.saveProfile(_edit()),
      fixture.repository.reload(),
      fixture.repository.setPermissionMode(PermissionMode.requestApproval),
    ];
    for (final ticket in tickets) {
      final result = await ticket.result;
      expect(result, isA<RejectedCommandResult<Unit>>());
      expect(
        (result as RejectedCommandResult<Unit>).error.correlationId,
        'configuration-fixture:unscripted-begin',
      );
    }
    expect(fixture.port.saves, isEmpty);
    expect(fixture.port.reloads, isEmpty);
    expect(fixture.port.profileLookups, isEmpty);
    expect(fixture.port.reloadLookups, isEmpty);
  });

  for (final reload in [false, true]) {
    test(
      'lost ${reload ? 'reload' : 'Profile'} begin with ${reload ? 'lookup error' : 'find null'} stays Unknown and only joins the original typed call',
      () async {
        final fixture = await _scenario();
        // Deliberately uses a stale-looking ordinary transport code. It is not
        // a typed CAS rejection and may not dispatch another native attempt.
        const lost = StudioFailure(
          code: StudioFailureCode.staleRevision,
          message: 'Transport lost the begin reply after native admission.',
          retryable: true,
          correlationId: 'profile-lost-begin',
        );
        final ticket = reload
            ? fixture.repository.reload()
            : fixture.repository.saveProfile(_edit());
        if (reload) {
          final call = await fixture.port.reloaded(0);
          call.beginReply.completeError(lost);
          final lookup = await fixture.port.reloadLookedUp(0);
          expect(lookup.operationId, ticket.id);
          lookup.reply.completeError(
            const CommandDispatchFailure.rejected(failure: _refused),
          );
        } else {
          final call = await fixture.port.saved(0);
          call.beginReply.completeError(lost);
          final lookup = await fixture.port.profileLookedUp(0);
          expect(lookup.operationId, ticket.id);
          lookup.reply.complete(null);
        }
        final unknown = await ticket.result;
        expect(unknown, isA<UnknownOutcomeCommandResult<Unit>>());
        expect(
          (unknown as UnknownOutcomeCommandResult<Unit>).error,
          same(lost),
        );
        expect(
          ticket.state.value.failurePhase,
          OperationFailurePhase.unknownOutcome,
        );
        expect(ticket.state.value.receipt, isNull);
        expect(fixture.port.configurationOpens, hasLength(1));

        final joining = fixture.repository.retryCleanup();
        final currentTargets = _targets(
          fixture,
          settings: 1,
          catalog: 1,
          profiles: 7,
        );
        if (reload) {
          final call = fixture.port.reloads.single;
          expect(call.native.requestCloseCalls, 0);
          final lookup = await fixture.port.reloadLookedUp(1);
          expect(lookup.operationId, ticket.id);
          lookup.reply.complete(call.native);
          final resultRead = await call.native.resultRead(0);
          resultRead.reply.complete(currentTargets);
          await _clean(call.native);
          expect(call.native.resultCalls, 1);
          expect(fixture.port.profileLookups, isEmpty);
        } else {
          final call = fixture.port.saves.single;
          expect(call.native.requestCloseCalls, 0);
          final lookup = await fixture.port.profileLookedUp(1);
          expect(lookup.operationId, ticket.id);
          lookup.reply.complete(call.native);
          final resultRead = await call.native.resultRead(0);
          resultRead.reply.complete(
            _profileReply(
              ticket.id,
              currentTargets,
              disposition: CommitDisposition.noChange,
            ),
          );
          await _clean(call.native);
          expect(call.native.resultCalls, 1);
          expect(fixture.port.reloadLookups, isEmpty);
        }
        expect((await joining).complete, isTrue);
        expect(
          await ticket.result,
          same(unknown),
          reason: 'Cleanup does not rewrite the original Unknown result Future',
        );
        expect(ticket.state.value.observed, isTrue);
        expect(ticket.state.value.failurePhase, isNull);
        expect(ticket.state.value.acknowledged, reload);
        expect(ticket.state.value.receipt == null, reload);
        expect(fixture.port.saves.length + fixture.port.reloads.length, 1);
      },
    );
  }

  test('Profile committed-but-unobserved keeps its real receipt through contradictory rejection and only the original reply can finish observation', () async {
    final fixture = await _scenario();
    final ticket = fixture.repository.saveProfile(_edit());
    final call = await fixture.port.saved(0);
    call.accept();
    final reply = _profileReply(ticket.id, _targets(fixture));
    final resultRead = await call.native.resultRead(0);
    resultRead.reply.completeError(
      CommandDispatchFailure.committedButUnobserved(
        failure: _captureFailed,
        receipt: reply.receipt,
      ),
    );
    final originalResult = await ticket.result;
    expect(originalResult, isA<SyncFailedCommandResult<Unit>>());
    final failed = originalResult as SyncFailedCommandResult<Unit>;
    expect(failed.receipt, reply.receipt);
    expect(failed.error, _captureFailed);
    expect(ticket.state.value.receipt, reply.receipt);
    expect(ticket.state.value.durable, isTrue);
    expect(ticket.state.value.observed, isFalse);
    expect(call.native.closes, isEmpty);

    final contradicting = fixture.repository.retryCleanup();
    final contradiction = await call.native.resultRead(1);
    contradiction.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _refused),
    );
    final unresolved = await contradicting;
    expect(unresolved.complete, isFalse);
    expect(ticket.state.value.receipt, reply.receipt);
    expect(ticket.state.value.error, _captureFailed);
    expect(ticket.state.value.failurePhase, OperationFailurePhase.syncFailed);
    expect(ticket.state.value.observed, isFalse);
    expect(call.native.closes, isEmpty);
    expect(
      unresolved.unresolved.any(
        (item) => item.issues.any(
          (issue) => issue.diagnostic.code == StudioFailureCode.protocol.name,
        ),
      ),
      isTrue,
    );

    fixture.port.profileSnapshots[8] = profileSnapshot().copyWith(
      revision: 'native-profile-8',
    );
    fixture.owner.modelPort.declaredCatalogs.add(2);
    fixture.owner.modelPort.holdCatalogHeaders = true;
    final headerIndex = fixture.owner.modelPort.catalogHeaders.length;
    final recovering = fixture.repository.retryCleanup();
    final restored = await call.native.resultRead(2);
    restored.reply.complete(reply);
    final modelRead = await fixture.owner.modelPort.catalogHeaderCalled(
      headerIndex,
    );
    expect(modelRead.catalog, reply.models);
    await fixture.port.publishSettings(2);
    await fixture.port.publishProfiles(8);
    expect(
      fixture.repository.state.value.projection.header!.configurationRevision,
      2,
    );
    expect(
      fixture.repository.profiles.value.projection.header!.profilesRevision,
      8,
    );
    expect(
      fixture.owner.models.state.value.projection.header!.reference,
      const ModelCatalogReadRef(entry: 1, revision: 1),
    );
    expect(
      (
        ticket.state.value.receipt,
        ticket.state.value.observed,
        ticket.state.value.isPending,
      ),
      (reply.receipt, false, true),
      reason: 'Both receipt stamps are covered, but the original Models target is really waiting at its native header',
    );
    expect(
      (
        ticket.state.value.failurePhase,
        ticket.state.value.error,
        ticket.state.value.effective,
        ticket.state.value.durable,
      ),
      (OperationFailurePhase.syncFailed, _captureFailed, false, true),
    );
    expect(await ticket.result, same(originalResult));
    expect(
      fixture.owner.operations.observations.lookup(ticket.id)!.state.value,
      ticket.state.value,
    );
    expect(
      fixture.owner.budget.usage.any(
        (usage) =>
            usage.kind == ResourceKind.pendingOperation &&
            usage.owner == ticket.id.value &&
            usage.phase == ResourcePhase.unresolved,
      ),
      isTrue,
    );
    expect(call.native.requestCloseCalls, 0);
    expect(
      call.native.closes,
      isEmpty,
      reason: 'Receipt stamp coverage cannot release the original call before all three receivers synchronize',
    );
    modelRead.accept();
    await fixture.owner.modelPort.advanceCatalog();
    await _clean(call.native);
    expect((await recovering).complete, isTrue);
    expect(ticket.state.value.receipt, reply.receipt);
    expect(ticket.state.value.observed, isTrue);
    expect(ticket.state.value.error, _captureFailed);
    expect(ticket.state.value.failurePhase, OperationFailurePhase.syncFailed);
    expect(await ticket.result, same(originalResult));
    expect(
      call.native.resultCalls,
      3,
      reason: 'Recovery joins the original result, not another begin or native call',
    );
    expect(call.native.closeCalls + call.native.retryCloseCalls, 1);
    expect(fixture.owner.budget.used(ResourceKind.pendingOperation), 0);
    expect(fixture.port.saves, hasLength(1));
    expect(fixture.port.profileLookups, isEmpty);
  });

  test('Profile confirmed-without-usable-receipt preserves the save fact and diagnostic rather than becoming a later rejection', () async {
    final fixture = await _scenario();
    final ticket = fixture.repository.saveProfile(_edit());
    final call = await fixture.port.saved(0);
    call.accept();
    final resultRead = await call.native.resultRead(0);
    resultRead.reply.completeError(
      const CommandDispatchFailure.confirmedWithoutUsableReceipt(
        failure: _captureFailed,
      ),
    );
    final originalResult = await ticket.result;
    expect(originalResult, isA<AcknowledgedSyncFailedCommandResult<Unit>>());
    expect(
      (originalResult as AcknowledgedSyncFailedCommandResult<Unit>).error,
      _captureFailed,
    );
    expect(
      (
        ticket.state.value.receipt,
        ticket.state.value.acknowledged,
        ticket.state.value.observed,
      ),
      (null, true, false),
    );
    expect(
      (ticket.state.value.durable, ticket.state.value.effective),
      (false, false),
    );
    final cleaning = fixture.repository.retryCleanup();
    final contradicted = await call.native.resultRead(1);
    contradicted.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _refused),
    );
    final report = await cleaning;
    fixture.retainedReport = report;
    expect(report.complete, isFalse);
    expect(ticket.state.value.failurePhase, OperationFailurePhase.syncFailed);
    expect(ticket.state.value.error, _captureFailed);
    expect(
      (
        ticket.state.value.receipt,
        ticket.state.value.acknowledged,
        ticket.state.value.observed,
      ),
      (null, true, false),
    );
    expect(await ticket.result, same(originalResult));
    expect(call.native.requestCloseCalls, 0);
    expect(call.native.closes, isEmpty);
    expect(fixture.port.saves, hasLength(1));
  });

  test('reload adopted-but-unobserved keeps acknowledged failure and cannot be rejected or fake-observed by cleanup', () async {
    final fixture = await _scenario();
    final ticket = fixture.repository.reload();
    final call = await fixture.port.reloaded(0);
    call.accept();
    final resultRead = await call.native.resultRead(0);
    // Adapter's typed AdoptedButUnobserved maps to this SDK failure; this test
    // proves only the public Dart boundary, not native/FRB outcome decoding.
    resultRead.reply.completeError(
      const CommandDispatchFailure.confirmedWithoutUsableReceipt(
        failure: _captureFailed,
      ),
    );
    final originalResult = await ticket.result;
    expect(originalResult, isA<AcknowledgedSyncFailedCommandResult<Unit>>());
    expect(
      (originalResult as AcknowledgedSyncFailedCommandResult<Unit>).error,
      _captureFailed,
    );
    expect(
      (
        ticket.state.value.receipt,
        ticket.state.value.acknowledged,
        ticket.state.value.observed,
      ),
      (null, true, false),
    );
    final contradicting = fixture.repository.retryCleanup();
    final contradiction = await call.native.resultRead(1);
    contradiction.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _refused),
    );
    expect((await contradicting).complete, isFalse);
    expect(ticket.state.value.error, _captureFailed);
    expect(ticket.state.value.failurePhase, OperationFailurePhase.syncFailed);
    expect(call.native.closes, isEmpty);

    fixture.port.profileSnapshots[8] = profileSnapshot().copyWith(
      revision: 'native-import-8',
    );
    fixture.owner.modelPort.declaredCatalogs.add(2);
    final recovering = fixture.repository.retryCleanup();
    final restored = await call.native.resultRead(2);
    restored.reply.complete(_targets(fixture));
    await fixture.port.publishSettings(2);
    await fixture.owner.modelPort.advanceCatalog();
    expect(ticket.state.value.observed, isFalse);
    expect(
      call.native.closes,
      isEmpty,
      reason: 'The original Profiles target is still missing',
    );
    await fixture.port.publishProfiles(8);
    await _clean(call.native);
    expect((await recovering).complete, isTrue);
    expect(
      (
        ticket.state.value.receipt,
        ticket.state.value.acknowledged,
        ticket.state.value.observed,
        ticket.state.value.durable,
        ticket.state.value.effective,
      ),
      (null, true, true, false, false),
    );
    expect(ticket.state.value.error, _captureFailed);
    expect(ticket.state.value.failurePhase, OperationFailurePhase.syncFailed);
    expect(await ticket.result, same(originalResult));
    expect(fixture.port.reloads, hasLength(1));
    expect(fixture.port.reloadLookups, isEmpty);
  });

  test('synchronous Models refusal still joins both admitted Profile targets without releasing unobserved receipt materials', () async {
    final fixture = await _scenario();
    fixture.owner.models
        .seal(); // Real receiver, not a fake synchronize failure.
    final ticket = fixture.repository.saveProfile(_edit());
    final call = await fixture.port.saved(0);
    call.accept();
    final resultRead = await call.native.resultRead(0);
    final reply = _profileReply(ticket.id, _targets(fixture));
    fixture.port.profileSnapshots[8] = profileSnapshot().copyWith(
      revision: 'native-profile-8',
    );
    resultRead.reply.complete(reply);
    final waiting = await fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(
      waiting.unresolved.map((item) => item.owner),
      containsAll([
        'configuration:write-lane',
        'configuration:command-target',
        'profiles:command-target',
      ]),
    );
    expect(ticket.state.value.failurePhase, isNull);
    expect(call.native.requestCloseCalls, 0);
    await fixture.port.publishSettings(2);
    final onlyProfiles = await fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(
      onlyProfiles.unresolved.map((item) => item.owner),
      contains('profiles:command-target'),
    );
    expect(
      onlyProfiles.unresolved.any(
        (item) => item.owner == 'configuration:command-target',
      ),
      isFalse,
    );
    expect(
      ticket.state.value.failurePhase,
      isNull,
      reason: 'A synchronous second receiver throw must not orphan the third admitted Future',
    );
    await fixture.port.publishProfiles(8);
    final result = await ticket.result;
    expect(result, isA<SyncFailedCommandResult<Unit>>());
    final failed = result as SyncFailedCommandResult<Unit>;
    expect(failed.receipt, reply.receipt);
    expect(failed.error.code, StudioFailureCode.cancelled);
    final unresolved = await fixture.repository.close();
    fixture.retainedReport = unresolved;
    expect(
      unresolved.unresolved.any(
        (item) => item.issues.any(
          (issue) =>
              issue.diagnostic.code == 'originalConfigurationTargetsUnobserved',
        ),
      ),
      isTrue,
    );
    expect(
      (ticket.state.value.receipt, ticket.state.value.observed),
      (reply.receipt, false),
    );
    expect(call.native.closes, isEmpty);
    expect(
      (await fixture.owner.models.close()).complete,
      isTrue,
      reason: 'Independent Models owners still join despite unobserved Profile evidence',
    );
    expect(
      fixture.owner.modelPort.feed.closeCalls +
          fixture.owner.modelPort.feed.retryCloseCalls,
      1,
    );
  });

  test('a foreign reload handle cannot be queried or closed for the original operation', () async {
    final fixture = await _scenario();
    final ticket = fixture.repository.reload();
    final begin = await fixture.port.reloaded(0);
    // The type is correct but the native metadata belongs to another owner.
    final foreign = ScriptedProfileReloadCall(
      callId: 'foreign-reload-call',
      operationId: const OperationId('foreign'),
    );
    begin.beginReply.complete(foreign);
    final unknown = await ticket.result;
    expect(unknown, isA<UnknownOutcomeCommandResult<Unit>>());
    expect(
      (unknown as UnknownOutcomeCommandResult<Unit>).error.code,
      StudioFailureCode.protocol,
    );
    final report = await fixture.repository.close();
    fixture.retainedReport = report;
    expect(report.complete, isFalse);
    expect(foreign.resultCalls, 0);
    expect(foreign.requestCloseCalls, 0);
    expect(foreign.closes, isEmpty);
    expect(ticket.state.value.receipt, isNull);
    expect(fixture.port.reloads, hasLength(1));
    expect(fixture.port.profileLookups, isEmpty);
    expect(fixture.port.reloadLookups, isEmpty);
  });

  test('observed receiptless reload validates close callId and one failed public retry stays Unresolved until the next explicit retry', () async {
    final fixture = await _scenario();
    final ticket = fixture.repository.reload();
    final call = await fixture.port.reloaded(0);
    call.accept();
    final resultRead = await call.native.resultRead(0);
    resultRead.reply.complete(
      _targets(fixture, settings: 1, catalog: 1, profiles: 7),
    );
    final result = await ticket.result;
    expect(result, isA<AcknowledgedCommandResult<Unit>>());
    final closing = await call.native.closed(0);
    closing.reply.complete(
      FeedCloseReport(
        feedId: ticket.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    final report = await fixture.repository.close();
    expect(report.complete, isFalse);
    expect(
      report.unresolved.any(
        (item) => item.issues.any(
          (issue) => issue.diagnostic.code == StudioFailureCode.protocol.name,
        ),
      ),
      isTrue,
    );
    expect(fixture.port.feed.closeCalls + fixture.port.feed.retryCloseCalls, 1);
    expect(
      fixture.port.profilesFeed.closeCalls +
          fixture.port.profilesFeed.retryCloseCalls,
      1,
      reason: 'Wrong call close identity cannot prevent independent Configuration/Profiles owners from joining',
    );
    final retrying = fixture.repository.retryCleanup();
    final retry = await call.native.closed(1);
    expect(retry.retry, isTrue);
    retry.reply.complete(
      FeedCloseReport(
        feedId: call.native.callId,
        outcome: FeedCloseOutcome.unresolved(issues: const [_joinFailed]),
      ),
    );
    await Future.any<void>([
      retrying.then<void>((_) {}),
      call.native.closed(2).then<void>((_) {}),
    ]);
    expect(
      call.native.retryCloseCalls,
      1,
      reason: 'Shared cleanup layers may not silently issue a second retry in this public request',
    );
    final failed = await retrying;
    expect(failed.complete, isFalse);
    expect(
      failed.unresolved.any((item) => item.issues.contains(_joinFailed)),
      isTrue,
    );
    expect(
      (
        ticket.state.value.receipt,
        ticket.state.value.observed,
        ticket.state.value.acknowledged,
      ),
      (null, true, true),
    );
    expect(await ticket.result, same(result));
    final next = fixture.repository.retryCleanup();
    final last = await call.native.closed(2);
    expect(last.retry, isTrue);
    last.reply.complete(
      FeedCloseReport(
        feedId: call.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await next).complete, isTrue);
    expect(call.native.closeCalls, 1);
    expect(call.native.retryCloseCalls, 2);
    expect(call.native.resultCalls, 1);
    expect(fixture.port.reloads, hasLength(1));
    expect(fixture.port.reloadLookups, isEmpty);
    expect(await ticket.result, same(result));
    expect(
      (
        ticket.state.value.receipt,
        ticket.state.value.durable,
        ticket.state.value.effective,
      ),
      (null, false, false),
    );
  });
}
