import 'dart:async';

import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/studio_client.dart';

import 'mapped_conversation_feed.dart';

/// Controls only delivery at the transport boundary; production owners apply all state.
class ControlledTimelineTransport extends DemoStudioTransport {
  final readers = <ControlledTimelineReader>[];
  final opened = StreamController<ControlledTimelineReader>.broadcast();
  ViewUpdate? initial;
  Future<void>? nextOpenGate;
  bool controlOlder = false;
  @override
  Duration get shutdownPhaseDelay => Duration.zero;

  @override
  Future<TimelineReader> openTimelineReader(
    String threadId, {
    required int presentationVersion,
    required int readerProtocolVersion,
    required ReadDemand demand,
  }) async {
    final gate = nextOpenGate;
    nextOpenGate = null;
    final native = await super.openTimelineReader(
      threadId,
      presentationVersion: presentationVersion,
      readerProtocolVersion: readerProtocolVersion,
      demand: demand,
    );
    final baseline = await native.next(after: native.metadata.initialCursor);
    final declared = initial ?? baseline;
    final reader = ControlledTimelineReader(
      queries: native,
      initial: () => declared,
      controlOlder: controlOlder,
    );
    readers.add(reader);
    opened.add(reader);
    await gate;
    return reader;
  }

  Future<void> settleFixtures() async {
    for (final reader in readers) {
      for (final request in reader.olderRequests) {
        if (!request.reply.isCompleted) {
          request.reply.completeError(const StaleConversationScope());
        }
      }
    }
    await opened.close();
  }
}

class ControlledTimelineReader extends ScriptedTimelineReader {
  ControlledTimelineReader({
    required super.queries,
    required super.initial,
    required this.controlOlder,
  });
  final bool controlOlder;
  final olderRequests =
      <({String before, ReadDemand demand, Completer<TimelinePage> reply})>[];
  final olderEntered = StreamController<void>.broadcast();
  final cursors = <ViewCursor>[];

  Future<void> send(ViewUpdate update) {
    final response = deliveredFrames + 1;
    emitTimeline(update);
    return accepted(response);
  }

  @override
  Future<ViewUpdate> next({required ViewCursor after}) {
    cursors.add(after);
    return super.next(after: after);
  }

  @override
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) {
    if (!controlOlder) {
      return super.loadTimelineOlder(before: before, demand: demand);
    }
    final reply = Completer<TimelinePage>();
    olderRequests.add((before: before, demand: demand, reply: reply));
    olderEntered.add(null);
    return reply.future;
  }
}
