import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 1, maxBytes: 1024);

ThreadWorkspace _workspace(int revision) =>
    emptyCurrentWorkspace('thread').copyWith(revision: revision);

CurrentView _view(int revision) =>
    currentViewForWorkspace(_workspace(revision));

Future<TestCurrentReader> _open(ConversationFixture fixture) async {
  await fixture.open(demand: _demand);
  await fixture.transport.currentOpened(0);
  return fixture.currentReader();
}

Future<TestCurrentReader> _reopen(
  ConversationFixture fixture,
  int index,
) async {
  await fixture.transport
      .currentOpened(index)
      .timeout(const Duration(seconds: 4));
  return fixture.currentReader();
}

void main() {
  test('Current watch failures rebuild a fresh Reset baseline with bounded retries', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    var reader = await _open(fixture);
    for (var attempt = 0; attempt < 3; attempt++) {
      await reader.deliver(ResetCurrentFrame(_view(1)));
      reader.sendError(ConversationContinuityError('stream $attempt'));
      await reader.requestCloseStarted.future.timeout(
        const Duration(seconds: 2),
      );
      reader = await _reopen(fixture, attempt + 1);
    }
    await reader.deliver(ResetCurrentFrame(_view(9)));
    expect(fixture.session().state.workspace!.revision, 9);
    expect(fixture.transport.currentOpens, hasLength(4));
  });

  test(
    'late old Current reader cannot mutate the replacement generation',
    () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      final old = await _open(fixture);
      await old.deliver(ResetCurrentFrame(_view(1)));
      old.sendError(ConversationContinuityError('old current broke'));
      await old.requestCloseStarted.future.timeout(const Duration(seconds: 2));
      final replacement = await _reopen(fixture, 1);
      await replacement.deliver(ResetCurrentFrame(_view(2)));
      old.send(testCurrentEvent(frame: _progress(99)));
      expect(fixture.session().state.workspace!.revision, 2);
    },
  );

  test('unsupported State schema fails without retry', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    fixture.transport.currentReaderFactory = (threadId, index) =>
        TestCurrentReader(
          threadId: threadId,
          initialView: currentViewForWorkspace(_workspace(1))
              .copyWithStateSchema(threadSchemaVersion + 1),
        );
    await fixture.open(demand: _demand);
    await fixture.transport.currentOpened(0);
    final failed = fixture.session().source.waitFor(
      (value) =>
          value.sync.phase == DomainSyncPhase.failed &&
          value.sync.retryExhausted,
    );
    await failed;
    expect(fixture.transport.currentOpens, hasLength(1));
    expect(fixture.session().state.hasSnapshot, isFalse);
  });

  test('New Current watch starts with Reset and preserves envelope order after Reset', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    final reader = await _open(fixture);
    await reader.deliver(ResetCurrentFrame(_view(1)));
    await reader.deliver(testCurrentEvent(frame: _progress(2)));
    await reader.deliver(testCurrentEvent(frame: _progress(3)));
    expect(fixture.session().state.revision, 3);
  });
}

ThreadNotificationFrame _progress(int revision) => ThreadNotificationFrame(
  threadId: 'thread',
  revision: revision,
  baseRevision: revision - 1,
  epoch: 7,
  update: const ThreadActivityUpdate(activity: null),
);

extension on CurrentView {
  CurrentView copyWithStateSchema(int schemaVersion) => CurrentView(
    revision: revision,
    state: ThreadSnapshotFrame(
      workspace: state.workspace,
      schemaVersion: schemaVersion,
    ),
    projection: projection,
  );
}
