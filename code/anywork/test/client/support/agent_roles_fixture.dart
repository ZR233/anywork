import 'dart:async';

import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/settings/agents/state/agent_profiles_state.dart';
import 'package:anywork/src/features/settings/agents/view_models/agent_profiles_view_model.dart';
import 'package:anywork/src/features/settings/state/settings_navigation_state.dart';
import 'package:anywork/src/features/settings/view_models/settings_navigation_view_model.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/profile_configuration_port.dart';
import '../../../../anywork_client/test/support/profile_editor_fixture.dart';
import '../../../../anywork_client/test/support/profile_recovery_port.dart';
import 'pump_client_future.dart';

const agentRole = 'executor';

/// Explicit synthetic native material, not a pair built from two latest states.
ConfigurationRoleReadTarget nativeRolePair(
  ProductReadOrigin origin, {
  int revision = 1,
  int catalogEntry = 1,
  int catalogRevision = 1,
}) => ConfigurationRoleReadTarget(
  reference: ConfigurationRoleReadRef(entry: 70, revision: revision),
  configuration: ConfigurationReadTarget(
    origin: origin,
    reference: const ConfigurationReadRef(entry: 1, revision: 1),
  ),
  catalog: ModelCatalogReadTarget(
    origin: origin,
    reference: ModelCatalogReadRef(
      entry: catalogEntry,
      revision: catalogRevision,
    ),
  ),
  stamp: ConfigProjectionStamp(
    settingsRevision: 1,
    modelCatalogRevision: catalogRevision,
    closing: false,
  ),
);

final class RoleRepositories {
  RoleRepositories({
    String ownerEpoch = 'role-native',
    int accountCount = 2,
    Set<String>? textEligibleAccounts,
  }) {
    profile = ProfileEditorFixture(
      ownerEpoch: ownerEpoch,
      accountCount: accountCount,
      textEligibleAccounts: textEligibleAccounts,
      profile: profileSnapshot().copyWith(profileId: agentRole, system: true),
    );
    profile.configurationPort.scriptProfileCommands = true;
    pair = nativeRolePair(profile.origin);
    profile.configurationPort.declareRolePair(pair, initial: true);
    recovery = createRecoveryRepository(
      port: recoveryPort,
      budget: profile.budget,
      operations: profile.operations,
    );
  }
  late final ProfileEditorFixture profile;
  late final ConfigurationRoleReadTarget pair;
  final recoveryPort = ProfileRecoveryPort();
  late final RecoveryRepository recovery;

  Future<void> establish() async {
    await Future.wait<void>([
      profile.establish(),
      recoveryPort.establish(recovery),
    ]);
  }
}

final class _StateWait {
  _StateWait(this.matches);
  final bool Function(AgentProfilesViewState) matches;
  final done = Completer<AgentProfilesViewState>();
}

/// Production generated VM + three real Repository owners. Only native ports
/// are scripted, and every accepted read is joined during teardown.
final class AgentRolesFixture {
  AgentRolesFixture(this.initial, this.tester)
    : container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          configurationRepositoryProvider.overrideWithValue(
            initial.profile.configuration,
          ),
          modelsRepositoryProvider.overrideWithValue(initial.profile.models),
          recoveryRepositoryProvider.overrideWithValue(initial.recovery),
        ],
      ) {
    worlds.add(initial);
    subscription = container.listen(agentProfilesViewModelProvider, (_, next) {
      if (next.asData?.value case final value?) {
        publications.add(value);
        for (final waiting in List.of(_waiting)) {
          if (waiting.matches(value)) {
            _waiting.remove(waiting);
            waiting.done.complete(value);
          }
        }
      }
    }, fireImmediately: true);
  }
  final RoleRepositories initial;
  final WidgetTester? tester;
  final ProviderContainer container;
  final worlds = <RoleRepositories>[];
  final publications = <AgentProfilesViewState>[];
  final expectedUnknown = <RoleRepositories, OperationState>{};
  final _waiting = <_StateWait>[];
  late final ProviderSubscription<AsyncValue<AgentProfilesViewState>>
  subscription;
  bool _disposed = false;

  AgentProfilesViewState get state =>
      container.read(agentProfilesViewModelProvider).requireValue;
  AgentProfilesViewModel get vm =>
      container.read(agentProfilesViewModelProvider.notifier);
  SettingsNavigationViewModel get navigation =>
      container.read(settingsNavigationViewModelProvider.notifier);

  static Future<AgentRolesFixture> create({
    String ownerEpoch = 'role-native',
    int accountCount = 2,
    Set<String>? textEligibleAccounts,
    WidgetTester? tester,
  }) async {
    final world = RoleRepositories(
      ownerEpoch: ownerEpoch,
      accountCount: accountCount,
      textEligibleAccounts: textEligibleAccounts,
    );
    final harness = AgentRolesFixture(world, tester);
    addTearDown(harness.close);
    await world.establish();
    await harness.container.read(settingsNavigationViewModelProvider.future);
    await harness.container.read(agentProfilesViewModelProvider.future);
    harness.navigation.enter(SettingsTab.agents);
    return harness;
  }

  Future<AgentProfilesViewState> waitFor(
    bool Function(AgentProfilesViewState) matches,
  ) {
    final current = state;
    if (matches(current)) return Future.value(current);
    final waiting = _StateWait(matches);
    _waiting.add(waiting);
    return waiting.done.future;
  }

  Future<AgentProfilesViewState> reply(
    ProfileRoleCall call,
    RoleRouteRead value,
  ) {
    call.reply.complete(value);
    return waitFor(
      (state) =>
          state.roleReads[agentRole]?.target == call.target &&
          state.roleReads[agentRole]?.pending == false &&
          state.roleReads[agentRole]?.value == value,
    );
  }

  Future<void> replace(RoleRepositories replacement) async {
    worlds.add(replacement);
    container.updateOverrides([
      configurationRepositoryProvider.overrideWithValue(
        replacement.profile.configuration,
      ),
      modelsRepositoryProvider.overrideWithValue(replacement.profile.models),
      recoveryRepositoryProvider.overrideWithValue(replacement.recovery),
    ]);
    await container.read(agentProfilesViewModelProvider.future);
  }

  Future<void> close() => tester == null
      ? _close()
      : pumpClientFuture(tester!, _close(), 'Agent role Repository cleanup');

  Future<void> _close() async {
    if (_disposed) return;
    _disposed = true;
    subscription.close();
    container.dispose();
    const cancelled = StudioFailure(
      code: StudioFailureCode.cancelled,
      message: 'The scripted role scenario is closing.',
      retryable: false,
      correlationId: 'role-test-close',
    );
    for (final world in worlds) {
      for (final open in world.profile.configurationPort.configurationOpens) {
        final native =
            open.native ??
            (!open.reply.isCompleted
                ? open.acceptNew('role-close-settings-${open.index}')
                : null);
        final cancellation = native?.cancellationReceipt;
        if (cancellation != null && !cancellation.isCompleted) {
          cancellation.complete();
        }
        final closing = native?.closeReceipt;
        if (closing != null && !closing.isCompleted) {
          closing.complete(
            FeedCloseReport(
              feedId: native!.feedId,
              outcome: const FeedCloseOutcome.clean(),
            ),
          );
        }
      }
      final unknown = expectedUnknown[world];
      if (unknown != null) {
        expectSync(
          world.profile.operations.observations.lookup(unknown.id)!.state.value,
          unknown,
        );
      }
      for (final call in world.profile.configurationPort.enabledChanges) {
        if (!call.beginReply.isCompleted) {
          call.beginReply.completeError(
            const CommandDispatchFailure.rejected(failure: cancelled),
          );
        } else if (call.accepted) {
          await call.native.resultRead(0);
          for (var index = 0; index < call.native.resultCalls; index++) {
            final read = call.native.resultAt(index);
            if (!read.reply.isCompleted) {
              read.reply.completeError(
                const CommandDispatchFailure.rejected(failure: cancelled),
              );
            }
          }
        }
      }
      for (final call in world.profile.configurationPort.roleCalls) {
        if (!call.reply.isCompleted) call.reply.completeError(cancelled);
      }
      for (final call in world.profile.modelPort.firstCalls) {
        if (!call.reply.isCompleted) call.reply.completeError(cancelled);
      }
      for (final call in world.profile.modelPort.effortCalls) {
        if (!call.reply.isCompleted) call.reply.completeError(cancelled);
      }
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      final closing = Future.wait([
        world.profile.close(deadline: deadline),
        world.recovery.close(deadline: deadline),
      ]);
      for (final call in world.profile.configurationPort.enabledChanges.where(
        (call) => call.accepted,
      )) {
        if (unknown?.id == call.request.operationId) {
          // UI assertions above retain Unknown unchanged. Teardown now obtains
          // a definitive *original* business rejection, not a fabricated Clean
          // for an invocation whose result is still unknown.
          final originalResult = await call.native.resultRead(1);
          originalResult.reply.completeError(
            const CommandDispatchFailure.rejected(failure: cancelled),
          );
        }
        final nativeClose = await call.native.closed(0);
        if (!nativeClose.reply.isCompleted) {
          nativeClose.reply.complete(
            FeedCloseReport(
              feedId: call.native.callId,
              outcome: const FeedCloseOutcome.clean(),
            ),
          );
        }
      }
      final reports = await closing;
      expectSync(
        [for (final report in reports) ...report.unresolved],
        isEmpty,
        reason: 'Every original role/field read and observer belongs to real Repository cleanup',
      );
      expectSync(world.profile.budget.usage, isEmpty);
      if (unknown != null) {
        final settled = world.profile.operations.observations
            .lookup(unknown.id)!
            .state
            .value;
        expectSync(settled.failurePhase, OperationFailurePhase.rejected);
        expectSync(settled.error, cancelled);
        expectSync(
          (settled.receipt, settled.acknowledged, settled.observed),
          (null, false, false),
          reason: 'Cleanup joins the native rejection; it never fabricates save/observation evidence',
        );
        final call = world.profile.configurationPort.enabledChanges.single;
        expectSync(call.native.resultCalls, 2);
        expectSync(call.native.closeCalls + call.native.retryCloseCalls, 1);
        expectSync(world.profile.configurationPort.profileLookups, isEmpty);
      }
    }
  }
}
