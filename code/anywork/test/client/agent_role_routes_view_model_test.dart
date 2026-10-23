import 'dart:async';

import 'package:anywork/src/features/settings/agents/connectors/agent_profiles_connector.dart';
import 'package:anywork/src/features/settings/agents/state/agent_profiles_state.dart';
import 'package:anywork/src/features/settings/agents/views/agent_profiles_view.dart';
import 'package:anywork/src/features/settings/state/settings_navigation_state.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/agent_roles_fixture.dart';

RoleRouteRead _configured({String accountId = 'account-0', String modelId = 'text', String effort = 'low'}) =>
    RoleRouteRead.configured(route: RoleModelRoute(key: agentRole,
      accountId: accountId, modelId: modelId, effort: effort));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('configured empty, unresolved and unsupported raw routes survive the real role VM without suggestions', () async {
    final samples = [
      (account: '', model: '', effort: '', descriptor: false),
      (account: 'removed-account', model: 'removed-model', effort: 'old-raw', descriptor: false),
      (account: 'account-0', model: 'text', effort: 'UNSUPPORTED_RAW', descriptor: true),
    ];
    for (var index = 0; index < samples.length; index++) {
      final raw = samples[index];
      final harness = await AgentRolesFixture.create(ownerEpoch: 'configured-role-$index');
      final world = harness.initial;
      final call = await world.profile.configurationPort.roleCalled(0);
      expect(call.target, world.pair);
      expect(call.roleId, agentRole);
      if (index == 0) {
        final otherRead = world.profile.configuration.roleRoute(target: world.pair, roleId: 'reviewer');
        final other = await world.profile.configurationPort.roleCalled(1);
        expect(other.roleId, 'reviewer');
        final otherValue = RoleRouteRead.configured(route: const RoleModelRoute(
          key: 'reviewer', accountId: 'account-1', modelId: 'text', effort: 'other-raw'));
        other.reply.complete(otherValue);
        expect(await otherRead, otherValue);
        expect(harness.state.roleReads[agentRole]!.value, isNull,
          reason: 'Another role on the same pair cannot satisfy this pending role');
        expect(harness.state.routes.containsKey(agentRole), isFalse);
      }
      final value = _configured(accountId: raw.account, modelId: raw.model, effort: raw.effort);
      await harness.reply(call, value);
      final route = harness.state.routes[agentRole]!;
      expect((route.target, route.accountId, route.modelId, route.effort, route.configured),
        (world.pair, raw.account, raw.model, raw.effort, true));
      expect(route.descriptor != null, raw.descriptor);
      expect(harness.state.roleReads[agentRole]!.value, value);
      expect(harness.state.roleReads[agentRole]!.error, isNull);
      expect(harness.state.readIssues, isEmpty, reason: 'Recovery is explicitly ready, not a swallowed dependency error');
      expect(world.profile.modelPort.firstCalls, isEmpty);
      expect(world.profile.modelPort.effortCalls, isEmpty);
      expect(world.profile.configurationPort.roleCalls, hasLength(index == 0 ? 2 : 1));
      expect(world.profile.configurationPort.saves, isEmpty);
      await harness.close();
    }
  });

  test('native missing suggestions use the complete pair and missing null is not confused with an unknown pair', () async {
    final suggested = await AgentRolesFixture.create(ownerEpoch: 'missing-suggested',
      accountCount: 33, textEligibleAccounts: {'account-32'});
    final suggestedWorld = suggested.initial;
    final call = await suggestedWorld.profile.configurationPort.roleCalled(0);
    const value = RoleRouteRead.missing(suggestion: ModelSelection(
      model: AccountModelKey(accountId: 'account-32', modelId: 'text'), effort: 'high'));
    await suggested.reply(call, value);
    final route = suggested.state.routes[agentRole]!;
    expect((route.target, route.accountId, route.modelId, route.effort, route.configured),
      (suggestedWorld.pair, 'account-32', 'text', 'high', false));
    expect(route.descriptor, isNull, reason: 'The native suggestion is outside the loaded Models page');
    expect(suggestedWorld.profile.modelPort.pageCalls.map((call) => (call.offset, call.limit)), [(0, 32)]);
    expect(suggestedWorld.profile.modelPort.lookupCalls, isEmpty);
    expect(suggestedWorld.profile.modelPort.firstCalls, isEmpty,
      reason: 'Dart must not replace the paired native result with a partial-catalog first');
    await suggested.close();

    final empty = await AgentRolesFixture.create(ownerEpoch: 'missing-no-candidate', textEligibleAccounts: {});
    final port = empty.initial.profile.configurationPort;
    final missing = await port.roleCalled(0);
    const none = RoleRouteRead.missing(suggestion: null);
    await empty.reply(missing, none);
    final intent = empty.state.roleReads[agentRole]!.intent;
    expect((empty.state.routes[agentRole]!.accountId, empty.state.routes[agentRole]!.modelId,
      empty.state.routes[agentRole]!.effort, empty.state.routes[agentRole]!.configured), ('', '', null, false));
    await port.publishRolePair(null);
    final unknown = empty.state.roleReads[agentRole]!;
    expect(unknown.target, isNull);
    expect(unknown.value, isNull);
    expect(unknown.error, isNull, reason: 'No pair was queried, so unknown is not a fabricated query failure');
    expect(unknown.pending, isFalse);
    expect(empty.state.routes.containsKey(agentRole), isFalse,
      reason: 'Unknown is not a fabricated missing route with empty fields');
    empty.vm.retryRead();
    expect(port.roleCalls, hasLength(1));
    await port.publishRolePair(empty.initial.pair);
    final replacement = await port.roleCalled(1);
    expect(empty.state.roleReads[agentRole]!.intent, greaterThan(intent));
    expect(empty.state.roleReads[agentRole]!.value, isNull);
    await empty.reply(replacement, none);
    expect(empty.state.routes[agentRole]!.target, empty.initial.pair);
    expect(empty.state.routes[agentRole]!.configured, isFalse);
    expect(empty.state.roleReads[agentRole]!.error, isNull);
  });

  test('superseded pair and A to unknown to A results cannot publish on behalf of the replacement intent', () async {
    for (final samePairAfterUnknown in [false, true]) {
      final harness = await AgentRolesFixture.create(ownerEpoch: 'pending-role-$samePairAfterUnknown');
      final world = harness.initial;
      final port = world.profile.configurationPort;
      final original = await port.roleCalled(0);
      final intent = harness.state.roleReads[agentRole]!.intent;
      final target = samePairAfterUnknown ? world.pair : nativeRolePair(world.profile.origin, revision: 2);
      if (samePairAfterUnknown) {
        await port.publishRolePair(null);
        expect(harness.state.roleReads[agentRole]!.value, isNull);
      } else {
        port.declareRolePair(target);
}
      await port.publishRolePair(target);
      expect(harness.state.roleReads[agentRole]!.intent, greaterThan(intent));
      expect(harness.state.roleReads[agentRole]!.target, target);
      expect(harness.state.routes.containsKey(agentRole), isFalse);
      expect(original.pin.closed, isFalse, reason: 'Demand replacement is not native join');
      expect(port.roleCalls, hasLength(1), reason: 'The UI borrows one accepted role read at a time');
      original.reply.complete(_configured());
      // A bad late handoff is itself a failure signal, even if it suppresses
      // the next native read; do not wait only for that read and hide the cause.
      final admittedBeforeAValue = await Future.any([
        port.roleCalled(1).then((_) => true),
        harness.waitFor((state) => state.roleReads[agentRole]?.value != null).then((_) => false),
      ]);
      expect(admittedBeforeAValue, isTrue, reason: 'The old result may not become the replacement request value');
      final fresh = await port.roleCalled(1);
      expect(fresh.target, target);
      expect(harness.state.roleReads[agentRole]!.value, isNull);
      expect(harness.state.routes.containsKey(agentRole), isFalse);
      await harness.reply(fresh, _configured());
      expect(harness.state.routes[agentRole]!.target, target);
      expect(port.roleCalls, hasLength(2));
      await harness.close();
    }
  });

  test('role read failures stay visible across source notifications and visibility until explicit retry', () async {
    final harness = await AgentRolesFixture.create(ownerEpoch: 'failed-role');
    final world = harness.initial;
    final port = world.profile.configurationPort;
    final original = await port.roleCalled(0);
    const failure = StudioFailure(code: StudioFailureCode.unavailable,
      message: 'The original native pair read failed.', retryable: true, correlationId: 'role-read-failure');
    original.reply.completeError(failure);
    await harness.waitFor((state) => state.roleReads[agentRole]?.error == failure && state.roleReads[agentRole]?.pending == false);
    final intent = harness.state.roleReads[agentRole]!.intent;
    expect(harness.state.routes.containsKey(agentRole), isFalse);
    await world.profile.modelPort.advanceCatalog();
    await world.profile.models.loadSourceStatus();
    await port.publishRolePair(world.pair);
    harness.vm.setQuery('executor', systemNames: const {});
    final away = harness.navigation.begin(SettingsTab.security)!;
    expect(harness.navigation.complete(away), isTrue);
    final back = harness.navigation.begin(SettingsTab.agents)!;
    expect(harness.navigation.complete(back), isTrue);
    await harness.waitFor((state) => state.reading.isEmpty &&
      state.modelSource.sourceStatus is ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef>);
    expect(harness.state.roleReads[agentRole]!.error, failure);
    expect(harness.state.roleReads[agentRole]!.intent, intent);
    expect(port.roleCalls, hasLength(1), reason: 'Source/rebuild/visibility is not a retry permission');
    harness.vm.retryRead();
    final retry = await port.roleCalled(1);
    expect(retry.target, original.target);
    expect(harness.state.roleReads[agentRole]!.intent, greaterThan(intent));
    await harness.reply(retry, _configured());
    expect(harness.state.roleReads[agentRole]!.error, isNull);
    expect(harness.state.routes[agentRole]!.configured, isTrue);
    expect(port.roleCalls, hasLength(2));
    expect(world.profile.modelPort.firstCalls, isEmpty);
    expect(world.profile.modelPort.effortCalls, isEmpty);
  });

  test('same-notifier rebuild leaves the original role read owned until real cleanup and never overwrites the new VM lifetime', () async {
    final harness = await AgentRolesFixture.create(ownerEpoch: 'same-role-owner');
    final old = harness.initial;
    final originalVm = harness.vm;
    final original = await old.profile.configurationPort.roleCalled(0);
    final originalIntent = harness.state.roleReads[agentRole]!.intent;
    // Join the very same in-flight SDK query, not a copied UI Future or a new
    // native read. Its late cancellation is still an original owner result.
    final borrowed = old.profile.configuration.roleRoute(target: old.pair, roleId: agentRole);
    final joined = expectLater(borrowed, throwsA(isA<StudioFailure>().having(
      (error) => error.code, 'code', StudioFailureCode.cancelled)));
    final replacement = RoleRepositories(ownerEpoch: 'same-role-owner');
    await replacement.establish();
    await harness.replace(replacement);
    expect(harness.vm, same(originalVm));
    final fresh = await replacement.profile.configurationPort.roleCalled(0);
    expect(replacement.pair, old.pair);
    expect(harness.state.roleReads[agentRole]!.intent, originalIntent,
      reason: 'The new lifetime repeats the old target and local intent but has a distinct Repository owner');
    expect(old.profile.configurationPort.feed.requestCloseCalls, 0);
    expect(old.recoveryPort.feed.requestCloseCalls, 0,
      reason: 'Rebuilding the VM cancels observers, not shared Repository owners');
    final report = await old.profile.configuration.close(deadline: DateTime.utc(2000));
    expect(report.complete, isFalse);
    expect(report.unresolved.where((value) => value.owner == 'configuration:role-route').single.issues.single.recovery,
      CleanupRecovery.awaitCompletion);
    expect(original.pin.closed, isFalse);
    await harness.reply(fresh, _configured());
    final current = harness.state;
    original.reply.complete(_configured());
    await joined;
    expect((await old.profile.configuration.retryCleanup()).complete, isTrue);
    expect(original.pin.closed, isTrue);
    expect(harness.state, current, reason: 'Old Repository work cannot publish into the rebuilt VM lifetime');
    expect(harness.state.routes[agentRole]!.target, replacement.pair);
    expect(harness.state.routes[agentRole]!.accountId, 'account-0');
    expect(old.profile.configurationPort.roleCalls, hasLength(1));
  });

  testWidgets('Smart roles preserve paired display and source failures, then recover explicitly without replaying Unknown writes', (tester) async {
    final harness = await AgentRolesFixture.create(ownerEpoch: 'role-display-target');
    final world = harness.initial;
    final port = world.profile.configurationPort;
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(UncontrolledProviderScope(container: harness.container,
      child: MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AgentProfilesConnector()))));
    final first = await port.roleCalled(0);
    first.reply.complete(_configured(effort: 'UNSUPPORTED_RAW'));
    await tester.pumpAndSettle();
    AgentProfilesView view() => tester.widget<AgentProfilesView>(find.byType(AgentProfilesView));
    final roleCard = find.byKey(const ValueKey('agent-profile-card-executor'));
    final retryLabel = AppLocalizations.of(tester.element(find.byType(AgentProfilesView))).runtimeFatalRetry;
    final retries = find.widgetWithText(TextButton, retryLabel);
    final roleRetry = find.descendant(of: roleCard, matching: retries);
    Future<void> revealRole() async {
      await tester.scrollUntilVisible(roleCard, 200, scrollable: find.descendant(
        of: find.byKey(const ValueKey('settings-pane-scroll')), matching: find.byType(Scrollable)));
      expect(roleCard, findsOneWidget);
    }
    expect(view().roleOptions[agentRole]!.map((option) => (option.accountId, option.modelId)),
      [('account-0', 'text'), ('account-1', 'text')]);
    expect(harness.state.routes[agentRole]!.descriptor, isNotNull);
    // Same owner and revision is not enough: this pair captured another native
    // immutable catalog ref, not the one the Models feed currently publishes.
    final other = nativeRolePair(world.profile.origin, revision: 2, catalogEntry: 77);
    port.declareRolePair(other);
    await port.publishRolePair(other);
    await tester.pump();
    final second = await port.roleCalled(1);
    second.reply.complete(_configured(effort: 'UNSUPPORTED_RAW'));
    await tester.pumpAndSettle();
    final route = harness.state.routes[agentRole]!;
    expect((route.target, route.accountId, route.modelId, route.effort, route.configured),
      (other, 'account-0', 'text', 'UNSUPPORTED_RAW', true));
    expect(route.descriptor, isNull);
    expect(view().roleOptions.containsKey(agentRole), isFalse);
    final matching = nativeRolePair(world.profile.origin, revision: 3);
    port.declareRolePair(matching);
    await port.publishRolePair(matching);
    await tester.pump();
    final third = await port.roleCalled(2);
    third.reply.complete(_configured(effort: 'UNSUPPORTED_RAW'));
    await tester.pumpAndSettle();
    expect(view().roleOptions[agentRole], hasLength(2));
    expect(harness.state.routes[agentRole]!.descriptor, isNotNull);
    expect(harness.state.routes[agentRole]!.effort, 'UNSUPPORTED_RAW');
    await revealRole();
    await tester.tap(find.byKey(const ValueKey('system-agent-enabled-executor')));
    await tester.pump();
    final enabled = await port.enabledChanged(0);
    expect((enabled.request.profileId, enabled.request.enabled, enabled.request.expectedSettingsRevision), (agentRole, false, 1));
    const unknownFailure = StudioFailure(code: StudioFailureCode.unavailable,
      message: 'The original profile enabled reply was lost.', retryable: true, correlationId: 'role-enabled-unknown');
    enabled.reply.completeError(const CommandDispatchFailure.unknownOutcome(failure: unknownFailure));
    await tester.pumpAndSettle();
    final unknownAction = harness.state.actions[(agentRole, AgentProfileAction.enabled)]!;
    final unknownOperation = unknownAction.operation!;
    expect(unknownAction.error, same(unknownFailure));
    expect(unknownAction.pending, isFalse);
    expect(unknownAction.preventsResubmission, isTrue);
    expect(unknownOperation.failurePhase, OperationFailurePhase.unknownOutcome);
    expect(unknownOperation.id, enabled.request.operationId);
    harness.expectedUnknown[world] = unknownOperation;
    final operations = world.profile.operations.observations.records.value;
    await port.publishRolePair(null);
    await tester.pumpAndSettle();
    final unknown = harness.state.roleReads[agentRole]!;
    expect(harness.state.configurationSource.projection.sync.phase, ResourceSyncPhase.ready);
    expect(harness.state.configurationSource.projection.sync.error, isNull);
    expect((unknown.target, unknown.value, unknown.error, unknown.pending), (null, null, null, false));
    expect(harness.state.routes.containsKey(agentRole), isFalse);
    expect(view().roleReadErrors.containsKey(agentRole), isFalse);
    expect(view().roleOptions.containsKey(agentRole), isFalse);
    await revealRole();
    expect(roleRetry, findsNothing, reason: 'A healthy source without a pair has no role-local no-op retry control');
    expect(port.roleCalls, hasLength(3));
    final failedPair = nativeRolePair(world.profile.origin, revision: 4);
    port.declareRolePair(failedPair);
    await port.publishRolePair(failedPair);
    await tester.pump();
    final failed = await port.roleCalled(3);
    failed.reply.completeError(const StudioFailure(code: StudioFailureCode.unavailable,
      message: 'Native role read unavailable.', retryable: true, correlationId: 'role-display-failed'));
    await tester.pumpAndSettle();
    expect(view().roleReadErrors.containsKey(agentRole), isTrue);
    expect(view().roleOptions.containsKey(agentRole), isFalse);
    expect(harness.state.routes.containsKey(agentRole), isFalse);
    await revealRole();
    expect(roleRetry, findsOneWidget, reason: 'A real query failure with its original target still permits explicit retry');

    const sourceFailure = StudioFailure(code: StudioFailureCode.unavailable,
      message: 'The original Configuration feed failed.', retryable: true, correlationId: 'role-configuration-source-failed');
    var native = port.feed;
    var originalPair = failedPair;
    // Both independently owned receipts must be joined: hold cancellation on
    // the first recovery and hold native close on the second one.
    for (var recovery = 0; recovery < 2; recovery++) {
      final accounts = harness.state.configurationSource.accounts as CurrentCollectionMirror<AccountConfiguration>;
      expect((accounts.window.origin, accounts.window.complete), (world.profile.origin, true));
      final knownStatus = harness.state.configurationSource.sourceStatus;
      expect(knownStatus, isA<ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef>>());
      expect(harness.state.reading, isEmpty);
      expect(harness.state.readIssues, isEmpty);
      native.cancellationReceipt = Completer<void>();
      native.closeReceipt = Completer<FeedCloseReport>();
      // Keep the last published header/pair and every already-read field.
      // Only the original typed feed failure invalidates the current target.
      native.emit(ConfigurationFrame.failure(identity: ProductFeedIdentity(
        feedId: native.feedId, ownerEpoch: world.profile.origin.ownerEpoch,
        incarnation: world.profile.origin.incarnation,
        resource: ProductResource.configuration), error: sourceFailure));
      await tester.pumpAndSettle(); // Deliver the original failure before inspecting the UI.
      final failedProjection = harness.state.configurationSource.projection;
      final sourceRead = harness.state.roleReads[agentRole]!;
      expect(failedProjection.sync.phase, ResourceSyncPhase.failed);
      expect(failedProjection.sync.error, same(sourceFailure));
      expect(failedProjection.header!.roleRead, originalPair, reason: 'Failure is not a scripted null header or a replacement pair');
      expect(failedProjection.header!.reference, const ConfigurationReadRef(entry: 1, revision: 1));
      expect(harness.state.configurationSource.accounts, accounts);
      expect(harness.state.configurationSource.sourceStatus, knownStatus,
        reason: 'The retained fields are already materialized; source recovery cannot rely on a field miss');
      expect((sourceRead.target, sourceRead.value, sourceRead.pending), (null, null, false));
      expect(sourceRead.error, same(sourceFailure), reason: 'Unknown must not swallow or replace the original source error');
      expect(harness.state.routes.containsKey(agentRole), isFalse, reason: 'A failed source cannot fabricate a missing route');
      expect(view().roleOptions.containsKey(agentRole), isFalse, reason: 'Options cannot turn the failed source into a route');
      const sourceErrorLabel = 'The original Configuration feed failed. [unavailable: role-configuration-source-failed]';
      expect(view().roleReadErrors[agentRole], sourceErrorLabel);
      expect(view().errors, contains(sourceErrorLabel));
      await revealRole(); // Build the real role card before checking its controls.
    expect(find.descendant(of: roleCard, matching: find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == sourceErrorLabel)), findsOneWidget);
      expect(roleRetry, findsNothing, reason: 'A failed source has no role-local target to retry');
      expect(retries, findsOneWidget, reason: 'Source recovery must stay outside the role-local controls');
      expect(port.roleCalls, hasLength(4 + recovery), reason: 'Source failure cannot admit a role RPC');
      expect(native.cancellationStarted.isCompleted, isTrue);
      expect(native.closeStarted.isCompleted, isTrue);

      await tester.ensureVisible(retries);
      await tester.tap(retries);
      await tester.pump();
      expect(harness.state.reading, contains(AgentProfilesReadField.configurationSource),
        reason: 'The actual source Retry must not be a no-op just because the retained header and fields exist');
      expect(port.configurationOpens, hasLength(1 + recovery));
      final clean = FeedCloseReport(feedId: native.feedId, outcome: const FeedCloseOutcome.clean());
      if (recovery == 0) { native.closeReceipt!.complete(clean); }
      else { native.cancellationReceipt!.complete(); }
      await tester.pump();
      expect(port.configurationOpens, hasLength(1 + recovery),
        reason: 'Neither native close alone nor stream cancellation alone proves the original feed joined');
      if (recovery == 0) { native.cancellationReceipt!.complete(); }
      else { native.closeReceipt!.complete(clean); }
      await tester.pump();
      expect(port.configurationOpens, hasLength(2 + recovery), reason: 'Only the real original resync may open the replacement feed');
      final opened = await port.configurationOpened(1 + recovery);
      final next = opened.acceptNew('role-source-recovery-${recovery + 1}');
      expect(next, isNot(same(native)));
      expect(next.feedId, isNot(native.feedId));
      final recoveredPair = nativeRolePair(world.profile.origin, revision: 5 + recovery);
      port.declareRolePair(recoveredPair);
      final baseline = port.publishConfigurationBaseline(next,
        target: recoveredPair, projectionRevision: 6 + recovery);
      await tester.pump();
      await baseline;
      await tester.pump();
      final recovered = await port.roleCalled(4 + recovery);
      expect(recovered.target, recoveredPair);
      expect(recovered.roleId, agentRole);
      recovered.reply.complete(_configured(effort: 'UNSUPPORTED_RAW'));
      await tester.pumpAndSettle();
      final projection = harness.state.configurationSource.projection;
      expect(projection.sync.phase, ResourceSyncPhase.ready);
      expect(projection.sync.error, isNull);
      expect(projection.stamp, ProductProjectionStamp(ownerEpoch: world.profile.origin.ownerEpoch,
        incarnation: world.profile.origin.incarnation, revision: 6 + recovery));
      expect((projection.header!.reference, projection.header!.configurationRevision, projection.header!.roleRead),
        (const ConfigurationReadRef(entry: 1, revision: 1), 1, recoveredPair));
      expect(harness.state.roleReads[agentRole]!.error, isNull);
      expect(harness.state.routes[agentRole]!.target, recoveredPair);
      expect(harness.state.routes[agentRole]!.effort, 'UNSUPPORTED_RAW');
      expect(harness.state.routes[agentRole]!.configured, isTrue);
      expect(view().roleReadErrors.containsKey(agentRole), isFalse);
      expect(view().errors, isNot(contains(sourceErrorLabel)));
      expect(view().roleOptions[agentRole], hasLength(2));
      expect(roleRetry, findsNothing);
      expect(harness.state.actions[(agentRole, AgentProfileAction.enabled)], unknownAction);
      expect(world.profile.operations.observations.lookup(unknownOperation.id)!.state.value, unknownOperation);
      expect(world.profile.operations.observations.records.value, operations);
      expect(port.enabledChanges.single, same(enabled), reason: 'Read recovery must not replay the original Unknown business write');
      expect(port.roleCalls, hasLength(5 + recovery));
      native = next;
      originalPair = recoveredPair;
    }
    expect(world.profile.modelPort.firstCalls, isEmpty);
    expect(world.profile.configurationPort.saves, isEmpty);
  });
}
