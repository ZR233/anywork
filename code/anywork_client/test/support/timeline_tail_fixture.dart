import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'conversation_fixture.dart';
import 'timeline_transport.dart';

/// A test composition root, not a channel implementation. Frames are recorded
/// only by the real Timeline's one consumer; no fake reducer, tail or state is
/// constructed here. Control/observation goes directly through public owners.
final class TimelineTailFixture {
  TimelineTailFixture(this.transport) {
    final budget = ResourceBudget();
    final assembly = createConversationRepository(
      port: FixtureConversationPort(),
      context: FixtureConversationContext(),
      commands: const UnscriptedConversationCommands(),
      timeline: transport,
      budget: budget,
      operations: OperationRegistry(clientId: 'timeline-tail', budget: budget),
    );
    repository = assembly.repository;
    demand = assembly.demand;
    timeline = repository.session('thread').timeline;
    addTearDown(() async {
      final closing = repository.close();
      for (final open in transport.opens) {
        if (!open.isCompleted)
          open.complete(TestTimelineConnection(initial: baseline(1)));
      }
      await closing;
    });
  }
  final TestTimelineTransport transport;
  late final ConversationRepository repository;
  late final ConversationDemand demand;
  late final ConversationTimeline timeline;
  final frames = <StudioTimelineFrame>[];
  final _waiters =
      <
        ({
          bool Function(StudioTimelineFrame) matches,
          Completer<StudioTimelineFrame> reply,
        })
      >[];
  int _selection = 0;

  Future<void> start() async {
    demand.select(
      threadId: 'thread',
      needsOpen: false,
      selectionGeneration: ++_selection,
    );
    await transport.requested(0);
  }

  void deselect() => demand.select(
    threadId: null,
    needsOpen: false,
    selectionGeneration: ++_selection,
  );

  void record(StudioTimelineFrame frame) {
    frames.add(frame);
    for (final waiter in List.of(_waiters)) {
      if (waiter.matches(frame)) {
        _waiters.remove(waiter);
        waiter.reply.complete(frame);
      }
    }
  }

  Future<StudioTimelineFrame> nextFrame(
    bool Function(StudioTimelineFrame) matches,
  ) {
    final reply = Completer<StudioTimelineFrame>();
    _waiters.add((matches: matches, reply: reply));
    return reply.future;
  }
}
