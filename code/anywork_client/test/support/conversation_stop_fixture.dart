import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'conversation_stop_native.dart';

Future<StopFixture> stopFixture() async {
  final fixture = StopFixture();
  addTearDown(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final report = await fixture.close(deadline: deadline);
    expect(report.complete, isTrue);
    expect(
      (await fixture.owner.repository.retryCleanup(deadline: deadline))
          .complete,
      isTrue,
    );
    // Unknown/unobserved native receipts retain their real Registry permits.
    // No test clears them by manually returning budget or changing a ticket.
    for (final retained in fixture.retainedOperations) {
      expect(retained.ticket.state.value.failurePhase, retained.phase);
      expect(retained.ticket.state.value.isPending, isTrue);
    }
    expect(
      fixture.budget.usage,
      unorderedEquals([
        for (final retained in fixture.retainedOperations)
          ResourceUsage(
            kind: ResourceKind.pendingOperation,
            owner: retained.ticket.id.value,
            phase: ResourcePhase.unresolved,
          ),
      ]),
    );
  });
  return fixture;
}
