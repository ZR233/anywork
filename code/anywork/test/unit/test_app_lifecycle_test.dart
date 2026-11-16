import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anywork_client/studio_client.dart';

import '../support/recording_demo_transport.dart';
import '../support/chatgpt_scene_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

void main() {
  test('ChatGPT fixture preserves its injected subscription catalog', () async {
    final transport = ChatGptSceneTransport();
    final catalog = await transport.loadAccountCatalog();
    expect(
      catalog.template('openai')!.defaultBillingKind,
      BillingKind.subscription,
    );
  });

  test(
    'root closes a scripted product owner before its frames are consumed',
    () async {
      final transport = _ScriptedTransport();
      final demand = transport.lifecycleRoot
          .child('sdk')
          .open<ProductTopicObservation>(
            'product-demand',
            (operation) => transport.openProductTopic(
              const BotsTopic(),
              resourceId: operation.resourceId,
            ),
            ownership: ClientOwnership.proxy,
          );
      await demand.ready;
      expect(transport.controller.hasListener, isFalse);
      final report = await transport.lifecycleRoot.close(
        budget: testCloseBudget(),
      );
      expect(report.complete, isTrue, reason: '${report.unresolved}');
      expect(transport.controller.isClosed, isTrue);
    },
  );

  test(
    'app and root close preserve sibling ownership and isolate applications',
    () async {
      final first = RecordingDemoTransport();
      final second = RecordingDemoTransport();
      final firstGraph = testAppGraph(
        transport: first,
        statisticsFeed: const TestStatisticsFeedPort(),
      );
      final secondGraph = testAppGraph(
        transport: second,
        statisticsFeed: const TestStatisticsFeedPort(),
      );
      final appEntry = firstGraph.scope.open<_Resource>(
        'app-work',
        (operation) async => _Resource(operation.resourceId, Future.value()),
      );
      final appResource = await appEntry.ready;
      final gate = Completer<void>();
      final firstEntry = first.contentScope.open<_Resource>(
        'transport-work',
        (operation) async => _Resource(operation.resourceId, gate.future),
      );
      final firstResource = await firstEntry.ready;
      final secondEntry = second.contentScope.open<_Resource>(
        'transport-work',
        (operation) async => _Resource(operation.resourceId, Future.value()),
      );
      final secondResource = await secondEntry.ready;
      try {
        final appReport = await firstGraph.close(budget: testCloseBudget());
        expect(appReport.complete, isTrue, reason: '${appReport.unresolved}');
        expect(appResource.closeRequested, isTrue);
        expect(appResource.closed, isTrue);
        expect(
          () => firstGraph.scope.child('closed-app'),
          throwsA(isA<ClientResourceClosed>()),
        );
        expect(firstResource.closeRequested, isFalse);
        expect(secondResource.closeRequested, isFalse);
        expect(appEntry.resourceId.scopeId, firstEntry.resourceId.scopeId);

        final report = await firstGraph.closeLifecycleRoot(
          ClientCloseBudget(Duration.zero),
        );
        expect(report.complete, isFalse);
        expect(
          report.unresolved.map((resource) => resource.resourceId),
          contains(firstEntry.resourceId),
        );
        expect(firstResource.closeRequested, isTrue);
        expect(firstResource.closed, isFalse);
        expect(secondResource.closeRequested, isFalse);
        expect(
          firstEntry.resourceId.scopeId,
          isNot(secondEntry.resourceId.scopeId),
        );
        // A second application's root must still admit a fresh child.
        second.lifecycleRoot.child('still-open');
      } finally {
        gate.complete();
        await firstEntry.close();
        expect(
          (await firstGraph.closeLifecycleRoot(testCloseBudget())).complete,
          isTrue,
        );
        expect(firstResource.closed, isTrue);
        expect(
          (await secondGraph.close(budget: testCloseBudget())).complete,
          isTrue,
        );
        expect(secondResource.closeRequested, isFalse);
        expect(
          (await secondGraph.closeLifecycleRoot(testCloseBudget())).complete,
          isTrue,
        );
        expect(secondResource.closeRequested, isTrue);
        expect(secondResource.closed, isTrue);
      }
    },
  );
}

final class _ScriptedTransport extends TestDemoStudioTransport {
  final controller = StreamController<ProductTopicFrame>();
  @override
  TestTopicFrames testProductTopicFrames(
    ProductTopic topic,
    TestTopicFrames upstream,
  ) => TestTopicFrames.controller(controller);
}

final class _Resource implements ClientResource {
  _Resource(this.resourceId, this.joined);
  @override
  final ClientResourceId resourceId;
  final Future<void> joined;
  bool closeRequested = false;
  bool closed = false;
  @override
  void requestClose() => closeRequested = true;
  @override
  Future<void> close() async {
    requestClose();
    await joined;
    closed = true;
  }

  @override
  Future<void> retryClose() => close();
}
