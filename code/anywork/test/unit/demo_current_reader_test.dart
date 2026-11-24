import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _demand = ReadDemand(maxItems: 8, maxBytes: 64 * 1024);

void main() {
  test(
    'Current keeps business facts by reference without inline bodies',
    () async {
      final root = ClientScope(owner: 'demo-current-references');
      final transport = DriverDemoStudioTransport(
        contentScope: root.child('transport'),
      );
      addTearDown(() => _closeRoot(root, transport));

      transport.prepareThemeScenario(plan: true);
      await transport.readBootstrap();
      final reader = await transport.openCurrentReader(
        'thread-main',
        currentProtocolVersion: currentProtocolVersion,
        demand: _demand,
      );

      final view = reader.initialView;
      final interactions = view.projection.interactions;
      final plan = view.projection.plan?.document;
      expect(interactions, isNotNull);
      expect(view.projection.collections, contains(interactions));
      expect(view.state.workspace.businessRefs.interactions, interactions);
      expect(view.state.workspace.interactions, isEmpty);
      expect(view.state.workspace.runtime.plan?.document, isNull);
      expect(plan, isNotNull);

      final page = await reader.pageCollection(
        reference: interactions!,
        demand: _demand,
      );
      expect(page.entries, isNotEmpty);

      final body = await reader.readBody(
        reference: plan!,
        range: const ContentRange(offset: 0, maxBytes: 256),
      );
      expect(body.bytes, isNotEmpty);
      await reader.close();
    },
  );

  test(
    'Current watch delivers typed State updates with Current qualification',
    () async {
      final root = ClientScope(owner: 'demo-current-notifications');
      final transport = DriverDemoStudioTransport(
        contentScope: root.child('transport'),
      );
      addTearDown(() => _closeRoot(root, transport));

      transport.prepareThemeScenario(plan: true);
      await transport.readBootstrap();
      final reader = await transport.openCurrentReader(
        'thread-main',
        currentProtocolVersion: currentProtocolVersion,
        demand: _demand,
      );
      final initial = reader.initialView;
      final watch = await reader.watch(
        after: initial.revision,
        demand: _demand,
      );
      final pending = watch.frames
          .where((frame) => frame is NotificationCurrentFrame)
          .cast<NotificationCurrentFrame>()
          .firstWhere(
            (frame) => frame.notification.update is ThreadRuntimeUpdate,
          );

      final command = transport.setThreadMode(
        threadId: 'thread-main',
        mode: ThreadModeId.auto,
        operationId: const OperationId('demo-current-notification'),
      );
      final frame = await pending.timeout(const Duration(seconds: 2));
      await command;
      final update = frame.notification.update as ThreadRuntimeUpdate;

      expect(frame.revision.ownerId, reader.metadata.currentOwnerId);
      expect(frame.notification.threadId, 'thread-main');
      expect(frame.notification.baseRevision, initial.state.workspace.revision);
      expect(
        frame.notification.revision,
        greaterThan(initial.state.workspace.revision),
      );
      expect(update.runtime.plan?.document, isNull);
      await watch.close();
      await reader.close();
    },
  );

  test('Current close joins unlistened metadata and body watches', () async {
    final root = ClientScope(owner: 'demo-current-close');
    final transport = DriverDemoStudioTransport(
      contentScope: root.child('transport'),
    );
    addTearDown(() => _closeRoot(root, transport));

    transport.prepareThemeScenario(plan: true);
    await transport.readBootstrap();
    final reader = await transport.openCurrentReader(
      'thread-main',
      currentProtocolVersion: currentProtocolVersion,
      demand: _demand,
    );
    final view = reader.initialView;
    final peer = await transport.openCurrentReader(
      'thread-main',
      currentProtocolVersion: currentProtocolVersion,
      demand: _demand,
    );
    expect(peer.metadata.readerId, isNot(reader.metadata.readerId));
    expect(peer.metadata.currentOwnerId, reader.metadata.currentOwnerId);
    final unlistened = await reader.watch(
      after: view.revision,
      demand: _demand,
    );
    await unlistened.close().timeout(const Duration(seconds: 1));

    final watch = await reader.watch(after: view.revision, demand: _demand);
    final body = await reader.watchBody(
      reference: view.projection.plan!.document!,
      range: const ContentRange(offset: 0, maxBytes: 256),
    );
    reader.requestClose();
    await reader.close().timeout(const Duration(seconds: 1));
    await watch.close().timeout(const Duration(seconds: 1));
    await body.close().timeout(const Duration(seconds: 1));
    expect(
      (await peer.snapshot(_demand)).state.workspace.thread.id,
      'thread-main',
    );
    await peer.close();
  });
}

Future<void> _closeRoot(ClientScope root, DemoStudioTransport transport) async {
  final budget = ClientCloseBudget(const Duration(seconds: 5));
  await transport.cancelDartSubscriptions(budget: budget);
  final report = await root.close(budget: budget);
  expect(
    report.complete,
    isTrue,
    reason: report.unresolved
        .map((resource) => '${resource.owner}: ${resource.reason}')
        .join('; '),
  );
}
