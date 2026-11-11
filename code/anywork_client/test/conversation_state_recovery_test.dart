import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 1, maxBytes: 1024);

ThreadWorkspace _workspace(int revision, {StudioTurnView? latestTurn}) {
  return ThreadWorkspace(
    thread: StudioThread(
      id: 'thread',
      workspaceId: 'project',
      title: 'Thread',
      mode: ThreadModeId.simple,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      updatedAt: DateTime.utc(2026),
      workspacePath: '/tmp/thread',
    ),
    revision: revision,
    interactions: const [],
    runtime: const ThreadRuntimeView(
      modelId: 'model',
      contextTokens: 0,
      contextWindow: 1,
      totalTokens: 0,
      costLabel: '',
      activeSkills: [],
      activeMcpServers: [],
      activeLspServers: [],
    ),
    businessRefs: const ThreadBusinessRefs(plan: null, interactions: null),
    latestTurn: latestTurn,
  );
}

ThreadNotificationFrame _progress(int revision) => ThreadNotificationFrame(
  threadId: 'thread',
  revision: revision,
  baseRevision: revision - 1,
  epoch: 7,
  update: const ThreadActivityUpdate(activity: null),
);

ThreadSnapshotFrame _snapshot(int revision, {StudioTurnView? latestTurn}) =>
    ThreadSnapshotFrame(
      schemaVersion: threadSchemaVersion,
      completedHistoryVersion: 1,
      workspace: _workspace(revision, latestTurn: latestTurn),
    );

Future<TestConversationStateFeed> _open(ConversationFixture fixture) async {
  await fixture.open(demand: _demand);
  await fixture.transport.stateOpened(0);
  return fixture.stateFeed();
}

Future<TestConversationStateFeed> _reopen(
  ConversationFixture fixture,
  int index,
  Stopwatch delay,
) async {
  await fixture.transport
      .stateOpened(index)
      .timeout(const Duration(seconds: 4));
  expect(delay.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 80)));
  return fixture.stateFeed();
}

void _lag(TestConversationStateFeed feed) {
  feed.send(
    ConversationStateEvent(
      frame: ThreadResyncRequiredFrame(threadId: 'thread', dropped: 1),
    ),
  );
}

Future<void> _acceptedSnapshot(
  TestConversationStateFeed feed,
  int revision, {
  StudioTurnView? latestTurn,
}) => feed.deliver(
  ConversationStateEvent(frame: _snapshot(revision, latestTurn: latestTurn)),
);

void main() {
  test(
    'each ACKed forward State recovery starts a fresh lag retry episode',
    () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      var feed = await _open(fixture);

      for (var episode = 0; episode < 5; episode++) {
        await _acceptedSnapshot(feed, 1);
        await feed.deliver(ConversationStateEvent(frame: _progress(2)));
        final delay = Stopwatch()..start();
        _lag(feed);
        await feed.requestCloseStarted.future;
        feed = await _reopen(fixture, episode + 1, delay);
      }

      final completedTurn = StudioTurnView(
        inputId: 'input',
        turnId: 'turn',
        threadId: 'thread',
        revision: 1,
        state: const CompletedStudioTurnState(
          startedAt: 1,
          completedAt: 2,
          completion: StudioTurnCompletion.normal,
        ),
        updatedAt: DateTime.utc(2026),
      );
      await _acceptedSnapshot(feed, 1, latestTurn: completedTurn);
      expect(
        fixture.session().state.workspace!.latestTurn!.state.isTerminal,
        isTrue,
      );
      expect(fixture.session().state.sync.retryExhausted, isFalse);
    },
  );

  for (final duplicateNotification in [false, true]) {
    test(
      '${duplicateNotification ? 'ACKed duplicate notification' : 'baseline only'} does not reset consecutive lag retries',
      () async {
        final fixture = ConversationFixture();
        addTearDown(fixture.close);
        var feed = await _open(fixture);
        const delays = [
          Duration(milliseconds: 100),
          Duration(milliseconds: 400),
          Duration(seconds: 1),
        ];

        for (var attempt = 0; attempt < delays.length + 1; attempt++) {
          await _acceptedSnapshot(feed, 1);
          if (duplicateNotification) {
            await feed.deliver(
              ConversationStateEvent(
                frame: ThreadNotificationFrame(
                  threadId: 'thread',
                  revision: 1,
                  baseRevision: 1,
                  epoch: 7,
                  update: const ThreadActivityUpdate(activity: null),
                ),
              ),
            );
          }
          final delay = Stopwatch()..start();
          _lag(feed);
          await feed.requestCloseStarted.future;
          if (attempt == delays.length) {
            expect(fixture.session().state.sync.retryExhausted, isTrue);
            expect(fixture.transport.stateOpens, hasLength(delays.length + 1));
          } else {
            final next = await _reopen(fixture, attempt + 1, delay);
            expect(
              delay.elapsed,
              greaterThanOrEqualTo(
                delays[attempt] - const Duration(milliseconds: 20),
              ),
            );
            feed = next;
          }
        }
      },
    );
  }

  test('retired attempt late progress ACK cannot reset the next attempt retry budget', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    var feed = await _open(fixture);

    _lag(feed);
    await feed.requestCloseStarted.future;
    feed = await _reopen(fixture, 1, Stopwatch()..start());

    await _acceptedSnapshot(feed, 1);
    final gate = Completer<void>();
    feed.ackGate = gate;
    feed.send(ConversationStateEvent(frame: _progress(2)));
    await feed.ackStarted(2).timeout(const Duration(seconds: 2));
    _lag(feed);
    await feed.requestCloseStarted.future;
    final oldFeed = feed;
    gate.complete();
    await oldFeed.acknowledged(2).timeout(const Duration(seconds: 2));
    feed = await _reopen(fixture, 2, Stopwatch()..start());

    await _acceptedSnapshot(feed, 1);
    _lag(feed);
    await feed.requestCloseStarted.future;
    feed = await _reopen(fixture, 3, Stopwatch()..start());
    await _acceptedSnapshot(feed, 1);
    _lag(feed);
    await feed.requestCloseStarted.future;
    expect(fixture.session().state.sync.retryExhausted, isTrue);
    expect(fixture.transport.stateOpens, hasLength(4));
  });

  test(
    'failed forward notification ACK does not count as State recovery',
    () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      var feed = await _open(fixture);

      _lag(feed);
      await feed.requestCloseStarted.future;
      feed = await _reopen(fixture, 1, Stopwatch()..start());
      await _acceptedSnapshot(feed, 1);
      feed.ackFailure = StateError('ACK failed');
      feed.send(ConversationStateEvent(frame: _progress(2)));
      await feed.requestCloseStarted.future;

      feed = await _reopen(fixture, 2, Stopwatch()..start());
      await _acceptedSnapshot(feed, 1);
      _lag(feed);
      await feed.requestCloseStarted.future;
      feed = await _reopen(fixture, 3, Stopwatch()..start());
      await _acceptedSnapshot(feed, 1);
      _lag(feed);
      await feed.requestCloseStarted.future;
      expect(fixture.session().state.sync.retryExhausted, isTrue);
      expect(fixture.transport.stateOpens, hasLength(4));
    },
  );

  test('unsupported State protocol fails immediately without retry', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    final feed = await _open(fixture);

    feed.send(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: threadSchemaVersion + 1,
          completedHistoryVersion: 1,
          workspace: _workspace(1),
        ),
      ),
    );
    await feed.requestCloseStarted.future;
    expect(fixture.session().state.sync.retryExhausted, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(fixture.transport.stateOpens, hasLength(1));
  });
}
