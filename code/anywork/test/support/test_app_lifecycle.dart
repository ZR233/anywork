import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_startup_host.dart';
import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork/src/platform/clipboard_image_reader.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/statistics_ports.dart';
import 'package:anywork_client/studio_client.dart';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart'
    show TestConversationTransport;
import 'test_resource_owners.dart';

export 'package:anywork_client/lifecycle.dart';

abstract interface class TestLifecycleOwner {
  ClientScope get lifecycleRoot;
}

class TestDemoStudioTransport extends DemoStudioTransport
    implements TestLifecycleOwner {
  TestDemoStudioTransport({
    bool lspActivityLoop = false,
    ClientScope? lifecycleRoot,
    AccountCatalogView accountCatalog = demoAccountCatalogFixture,
  }) : this._(
         lifecycleRoot ?? ClientScope(owner: 'test-application'),
         lspActivityLoop,
         accountCatalog,
       );

  TestDemoStudioTransport._(
    this.lifecycleRoot,
    bool lspActivityLoop,
    AccountCatalogView accountCatalog,
  ) : super(
        contentScope: lifecycleRoot.child('transport'),
        lspActivityLoop: lspActivityLoop,
        accountCatalog: accountCatalog,
      ) {
    addTearDown(() async {
      final report = await lifecycleRoot.close(budget: testCloseBudget());
      expect(report.complete, isTrue, reason: '${report.unresolved}');
    });
  }

  @override
  final ClientScope lifecycleRoot;

  TestTopicFrames testProductTopicFrames(
    ProductTopic topic,
    TestTopicFrames upstream,
  ) => upstream;

  @override
  Future<ProductTopicObservation> openProductTopic(
    ProductTopic topic, {
    required ClientResourceId resourceId,
  }) async {
    final source = contentScope.open<ProductTopicObservation>(
      'demo-source',
      (operation) =>
          super.openProductTopic(topic, resourceId: operation.resourceId),
      ownership: ClientOwnership.proxy,
    );
    final upstream = await source.ready;
    final mapped = testProductTopicFrames(
      topic,
      TestTopicFrames.stream(upstream.frames),
    );
    return ownTestProductTopic(
      contentScope,
      resourceId,
      mapped.frames,
      requestSource: () {
        mapped.requestClose();
        source.requestClose();
      },
      closeSource: () async {
        await Future.wait([mapped.close(), source.close()]);
      },
      retrySource: () async {
        await Future.wait([mapped.close(), source.retryClose()]);
      },
    );
  }
}

final class TestTopicFrames {
  TestTopicFrames.stream(this.frames) : _controller = null;
  TestTopicFrames.controller(StreamController<ProductTopicFrame> controller)
    : frames = controller.stream,
      _controller = controller;

  final Stream<ProductTopicFrame> frames;
  final StreamController<ProductTopicFrame>? _controller;
  Future<void>? _closing;

  void requestClose() {
    if (_closing != null) return;
    final controller = _controller;
    if (controller == null) return;
    final hadListener = controller.hasListener;
    final closed = controller.close();
    // Mark an unconsumed scripted source closed without waiting for a listener
    // that was never transferred to the SDK. A real listener must acknowledge.
    _closing = hadListener ? closed : Future.value();
  }

  Future<void> close() {
    requestClose();
    return _closing ?? Future.value();
  }
}

ClientScope _transportRoot(StudioTransport transport) => switch (transport) {
  TestLifecycleOwner(:final lifecycleRoot) => lifecycleRoot,
  TestConversationTransport(:final lifecycleScope) => lifecycleScope,
  _ => throw StateError('Test transport must expose its lifecycle root'),
};

AppGraph testAppGraph({
  required StudioTransport transport,
  required StatisticsFeedPort statisticsFeed,
  String? clientId,
  StudioUpdateApi? updateApi,
  bool updatesEnabled = false,
  AccountFeedPort? accountFeed,
  AccountConfigurationPort? accountConfiguration,
  AccountModelsPort? accountModels,
  AccountUsagePort? accountUsage,
  AcpPort? acpPort,
  AcpBusinessPort? acpBusinessPort,
  StudioStartupHost? startupHost,
  ClipboardImageStager? clipboardImageStager,
}) {
  final root = _transportRoot(transport);
  return AppGraph(
    scope: root.child('app'),
    closeLifecycleRoot: (budget) => root.close(budget: budget),
    transport: transport,
    statisticsFeed: statisticsFeed,
    clientId: clientId,
    updateApi: updateApi,
    updatesEnabled: updatesEnabled,
    accountFeed: accountFeed,
    accountConfiguration: accountConfiguration,
    accountModels: accountModels,
    accountUsage: accountUsage,
    acpPort: acpPort,
    acpBusinessPort: acpBusinessPort,
    startupHost: startupHost,
    clipboardImageStager: clipboardImageStager,
  );
}

AnyworkClient testAnyworkClient({
  required StudioTransport transport,
  required String clientId,
  SettingsWriteCoordinator? settingsWrites,
  MutationBoard? mutationBoard,
  AccountDomainResources? accountDomains,
  AcpBusinessPort? acpBusinessPort,
  Future<String?> Function(Uint8List)? clipboardImageStager,
  Future<void> Function(String)? clipboardImageCleanup,
  StudioUpdateApi? updateApi,
  bool updatesEnabled = false,
  int Function()? threadCommandsClock,
}) {
  final root = _transportRoot(transport);
  addTearDown(() async {
    final report = await root.close(budget: testCloseBudget());
    expect(report.complete, isTrue, reason: describeTestCloseReport(report));
  });
  return AnyworkClient(
    scope: root.child('client'),
    transport: transport,
    clientId: clientId,
    settingsWrites: settingsWrites,
    mutationBoard: mutationBoard,
    accountDomains: accountDomains,
    acpBusinessPort: acpBusinessPort,
    clipboardImageStager: clipboardImageStager,
    clipboardImageCleanup: clipboardImageCleanup,
    updateApi: updateApi,
    updatesEnabled: updatesEnabled,
    threadCommandsClock: threadCommandsClock,
  );
}

ClientCloseBudget testCloseBudget() =>
    ClientCloseBudget(const Duration(seconds: 5));

String describeTestCloseReport(CloseReport report) => report.unresolved
    .map(
      (resource) => [
        'id=${resource.resourceId} owner=${resource.owner} '
            'ownership=${resource.ownership} attempt=${resource.attemptId.value} '
            'reason=${resource.reason}',
        for (final stage in resource.stages)
          '  phase=${stage.phase} owner=${stage.owner} '
              'ownership=${stage.ownership} path=${stage.scopePath.join('/')} '
              'pending=${stage.pending} error=${stage.error}\n'
              '${stage.stackTrace ?? ''}',
      ].join('\n'),
    )
    .join('\n');

Matcher get isDartResourceCloseClean => isA<DartResourceCloseResult>()
    .having((result) => result.resources.complete, 'resources complete', isTrue)
    .having((result) => result.issues, 'transport issues', isEmpty);

ClientCloseBudget testBudgetUntil(DateTime deadline) {
  final remaining = deadline.difference(DateTime.now());
  return ClientCloseBudget(remaining.isNegative ? Duration.zero : remaining);
}
