import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/conversation_fixture.dart';

/// Uses the actual domain owners; only their external native ports are scripted.
/// No legacy Client, Session reducer or second Timeline implementation lives here.
final class TimelineTestEnvironment {
  TimelineTestEnvironment({
    required TimelineTransport timeline,
    ConversationCommandPort commands = const UnscriptedConversationCommands(),
    ResourceBudget? budget,
  }) : budget = budget ?? ResourceBudget() {
    operations = OperationRegistry(
      clientId: 'timeline-test',
      budget: this.budget,
    );
    final assembly = createConversationRepository(
      port: facets,
      context: context,
      commands: commands,
      timeline: timeline,
      budget: this.budget,
      operations: operations,
    );
    conversations = assembly.repository;
    demand = assembly.demand;
  }

  final ResourceBudget budget;
  final facets = FixtureConversationPort();
  final context = FixtureConversationContext();
  late final OperationRegistry operations;
  late final ConversationRepository conversations;
  late final ConversationDemand demand;
  int _selectionGeneration = 0;

  ConversationSession? select(String threadId) {
    demand.select(
      threadId: threadId,
      needsOpen: false,
      selectionGeneration: ++_selectionGeneration,
    );
    return conversations.active.value;
  }

  Future<void> close() async {
    final report = await conversations.close(
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    );
    expect(
      report.complete,
      isTrue,
      reason: 'all original Timeline owners join',
    );
    operations.seal();
    expect(budget.usage, isEmpty);
  }
}

/// No content demand is opened for pure display projection tests. Unexpected
/// queries fail at the real port boundary instead of manufacturing empty facts.
final class UnscriptedTimelineTransport implements TimelineTransport {
  const UnscriptedTimelineTransport();

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) =>
      throw UnsupportedError('Unscripted Timeline open for $threadId');
}
