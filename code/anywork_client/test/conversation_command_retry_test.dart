import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/conversation_fixture.dart';
import 'support/drafts_native_fixture.dart' show DraftCalls;
import 'support/timeline_transport.dart';

const _conflict = StudioFailure(
  code: StudioFailureCode.conflict,
  message: 'The original route CAS was rejected.',
  retryable: true,
  correlationId: 'route-retry-cas',
);
const _unknown = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The original dispatch reply is lost.',
  retryable: true,
  correlationId: 'route-retry-unknown',
);

final class _RouteCall {
  _RouteCall(
    this.id,
    this.account,
    this.model,
    this.effort,
    this.routeRevision,
    this.settingsRevision,
  );
  final OperationId id;
  final String account;
  final String model;
  final String? effort;
  final int routeRevision;
  final int settingsRevision;
  final reply = Completer<ThreadModelRouteCommandReply>();
}

final class _Commands extends UnscriptedConversationCommands {
  final calls = DraftCalls<_RouteCall>();
  @override
  Future<ThreadModelRouteCommandReply> setThreadModelRoute(
    String threadId, {
    required OperationId operationId,
    required String accountId,
    required String modelId,
    required String? effort,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
  }) {
    expect(threadId, 'thread');
    final call = _RouteCall(
      operationId,
      accountId,
      modelId,
      effort,
      expectedModelRouteRevision,
      expectedSettingsRevision,
    );
    calls.add(call);
    return call.reply.future;
  }
}

ThreadFacetStamp _origin(int revision) => ThreadFacetStamp(
  runtimeEpoch: 'route-retry-native',
  incarnation: 1,
  facet: ThreadFacet.configuration,
  revision: revision,
);
ThreadConfigurationValue _configuration(int revision) =>
    ThreadConfigurationValue(
      details: ThreadConfigurationReadRef(entry: 1, revision: revision),
      sources: ConfigProjectionStamp(
        settingsRevision: revision,
        modelCatalogRevision: 1,
        closing: false,
      ),
      modeRevision: 1,
      modeBindingRevision: 1,
      modelRoute: ModelRouteBrief(
        revision: revision,
        available: true,
        hasUnavailableReason: false,
      ),
      activeSkillCount: 0,
      activeMcp: ThreadCapabilitySupport.unsupported,
      activeLsp: ThreadCapabilitySupport.unsupported,
      mcpHealth: ThreadCapabilitySupport.unsupported,
    );

Future<
  ({
    ConversationFixture fixture,
    ConversationSession session,
    FacetOpen<ThreadConfigurationFrame> source,
  })
>
_fixture(_Commands commands, {bool retainUnknown = false}) async {
  final fixture = ConversationFixture(commands: commands);
  addTearDown(() async {
    if (fixture.repository.active.value != null) fixture.deselect();
    for (final request in fixture.timeline.requests) {
      if (!request.result.isCompleted) {
        request.result.complete(TestTimelineConnection(initial: baseline(1)));
      }
    }
    for (final call in commands.calls.values) {
      if (!call.reply.isCompleted)
        call.reply.completeError(
          const CommandDispatchFailure.rejected(failure: _conflict),
        );
    }
    final report = await fixture.repository.close();
    expect(report.complete, !retainUnknown);
    expect(
      fixture.budget.usage,
      retainUnknown
          ? unorderedEquals([
              const ResourceUsage(
                kind: ResourceKind.readModel,
                owner: 'conversation-repository',
                phase: ResourcePhase.active,
              ),
              const ResourceUsage(
                kind: ResourceKind.readModel,
                owner: 'session:thread',
                phase: ResourcePhase.active,
              ),
              ResourceUsage(
                kind: ResourceKind.pendingOperation,
                owner: commands.calls.values.single.id.value,
                phase: ResourcePhase.unresolved,
              ),
            ])
          : isEmpty,
    );
  });
  final session = fixture.select('thread');
  final source = await fixture.facets.configurationOpened(0);
  await source.feed.listened.future;
  source.feed.emit(
    ThreadConfigurationFrame.data(
      deliverySequence: 1,
      event: ThreadConfigurationEvent.baseline(
        identity: ThreadFeedIdentity(
          feedId: source.feed.feedId,
          runtimeEpoch: 'route-retry-native',
          incarnation: 1,
          facet: ThreadFacet.configuration,
          mode: source.mode,
        ),
        stamp: _origin(1),
        value: _configuration(1),
      ),
    ),
  );
  await source.feed.acknowledged(1);
  return (fixture: fixture, session: session, source: source);
}

void main() {
  test('explicit route CAS retry preserves the original operation and intent with new canonical revisions', () async {
    final commands = _Commands();
    final setup = await _fixture(commands);
    final first = setup.session.setThreadModelRoute(
      origin: _origin(1),
      accountId: 'account',
      modelId: 'model',
      effort: 'high',
      expectedModelRouteRevision: 1,
      expectedSettingsRevision: 1,
    );
    final initial = await commands.calls.at(0);
    initial.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _conflict),
    );
    final rejected = await first.result;
    expect(
      rejected,
      const CommandResult<ThreadModelRouteCommandReply>.rejected(
        error: _conflict,
      ),
    );
    final previousStates = <OperationState>[];
    final previousWatch = first.state.watch(previousStates.add);
    addTearDown(previousWatch.cancel);
    await pumpEventQueue();
    expect(
      commands.calls.values,
      hasLength(1),
      reason: 'A known CAS rejection is never automatically resent',
    );
    setup.source.feed.emit(
      ThreadConfigurationFrame.data(
        deliverySequence: 2,
        event: ThreadConfigurationEvent.replace(
          stamp: _origin(2),
          value: _configuration(2),
        ),
      ),
    );
    await setup.source.feed.acknowledged(2);
    final retry = setup.session.setThreadModelRoute(
      origin: _origin(2),
      operationId: first.id,
      accountId: 'account',
      modelId: 'model',
      effort: 'high',
      expectedModelRouteRevision: 2,
      expectedSettingsRevision: 2,
    );
    final next = await commands.calls.at(1);
    expect(previousWatch.isCancelled, isFalse);
    expect((initial.id, next.id, retry.id), (first.id, first.id, first.id));
    expect(
      commands.calls.values.map(
        (call) => (call.routeRevision, call.settingsRevision),
      ),
      [(1, 1), (2, 2)],
    );
    expect(
      commands.calls.values.map(
        (call) => (call.account, call.model, call.effort),
      ),
      [('account', 'model', 'high'), ('account', 'model', 'high')],
    );
    expect(
      (
        retry.state.value.acknowledged,
        retry.state.value.observed,
        retry.state.value.effective,
        retry.state.value.durable,
      ),
      (false, false, false, false),
    );
    next.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _conflict),
    );
    expect(await retry.result, rejected);
    expect(
      await first.result,
      same(rejected),
      reason: 'The new attempt cannot resettle its predecessor',
    );
    expect(previousStates, isEmpty);
    expect(first.state.value.failurePhase, OperationFailurePhase.rejected);
    previousWatch.cancel();
    expect(
      () => setup.session.setThreadModelRoute(
        origin: _origin(2),
        operationId: retry.id,
        accountId: 'account',
        modelId: 'another-model',
        effort: 'high',
        expectedModelRouteRevision: 2,
        expectedSettingsRevision: 2,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.invalidArgument,
        ),
      ),
    );
    expect(commands.calls.values, hasLength(2));
  });

  test('an unknown route outcome cannot be explicitly replayed under its operation identity', () async {
    final commands = _Commands();
    final setup = await _fixture(commands, retainUnknown: true);
    final first = setup.session.setThreadModelRoute(
      origin: _origin(1),
      accountId: 'account',
      modelId: 'model',
      effort: null,
      expectedModelRouteRevision: 1,
      expectedSettingsRevision: 1,
    );
    final call = await commands.calls.at(0);
    call.reply.completeError(_unknown);
    expect(
      await first.result,
      const CommandResult<ThreadModelRouteCommandReply>.unknownOutcome(
        error: _unknown,
      ),
    );
    expect(
      () => setup.session.setThreadModelRoute(
        origin: _origin(1),
        operationId: first.id,
        accountId: 'account',
        modelId: 'model',
        effort: null,
        expectedModelRouteRevision: 2,
        expectedSettingsRevision: 2,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.conflict,
        ),
      ),
    );
    expect(commands.calls.values, hasLength(1));
    // Unknown has a real retained owner; teardown must not invent Clean.
    setup.fixture.deselect();
    for (final opening in setup.fixture.timeline.requests) {
      if (!opening.result.isCompleted)
        opening.result.complete(TestTimelineConnection(initial: baseline(1)));
    }
    final report = await setup.fixture.repository.close();
    expect(
      report.unresolved.where(
        (item) => item.owner.startsWith('conversation-command:'),
      ),
      hasLength(1),
    );
  });
}
