import 'dart:async';

import 'package:anywork/src/app/bootstrap/application_bootstrap.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart';
import 'support/application_environment.dart';
import 'support/selector_directory_port.dart';
import 'support/selector_environment.dart';
import 'support/selector_models_port.dart';

const _catalogFailure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'catalog unavailable',
  retryable: false,
  correlationId: 'bootstrap-catalog',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('closing a project discards only its logical drafts and releases their permits', () async {
    final environment = SelectorEnvironment();
    addTearDown(environment.close);
    await environment.establish();
    await environment.selectStart();
    const projectId = 'project';
    final start = environment.drafts.start(projectId)
      ..setText('closed project draft');
    await environment.selectThread('thread-main');
    final opening = await environment.timeline.opened(0);
    opening.result.complete(
      TestTimelineConnection(
        initial: baseline(1, items: [timelineItem(1, threadId: 'thread-main')]),
      ),
    );
    final composer = environment.drafts.composer('thread-main')
      ..setText('closed Thread draft');
    final startStamp = start.state.value.stamp;
    final composerStamp = composer.state.value.stamp;
    final closing = environment.workspace.archiveProject(projectId);
    await environment.directory.archiveEntered.future;
    await environment.directory.publishProjects([selectorForeignProject]);
    environment.directory.archiveReply.complete(selectorProject);
    final result = await closing.result;
    expect(
      result,
      isA<AcknowledgedCommandResult<Unit>>(),
      reason: switch (result) {
        AcknowledgedSyncFailedCommandResult(:final error) =>
          '${error.code}: ${error.message} (${error.correlationId})',
        _ => null,
      },
    );
    // The old facade's owner maps are private now. The original handles are
    // cleared/retired and their permits have actually been released.
    expect(start.state.value.text, isEmpty);
    expect(start.state.value.stamp, isNot(startStamp));
    expect(composer.state.value.text, isEmpty);
    expect(composer.state.value.stamp, isNot(composerStamp));
    expect(environment.budget.used(ResourceKind.draft), 0);
    await environment.close();
    expect(environment.budget.usage, isEmpty);
  });

  test(
    'catalog failure can explicitly retry the entire typed bootstrap',
    () async {
      final budget = ResourceBudget();
      final operations = OperationRegistry(
        clientId: 'bootstrap-retry',
        budget: budget,
      );
      final startupPort = ApplicationStartupPort();
      final startup = createStartupRepository(
        port: startupPort,
        budget: budget,
        operations: operations,
      );
      final catalogPort = _CatalogFailurePort();
      final catalog = createModelsRepository(
        port: catalogPort,
        budget: budget,
      ).repository;
      var attachments = 0;
      final bootstrap = ApplicationBootstrap(
        startup: startup,
        attachDomains: (_) async {
          attachments++;
          await catalog.loadAccountsPage();
        },
      );
      addTearDown(() async {
        await bootstrap.close();
        expect((await startup.close()).complete, isTrue);
        expect((await catalog.close()).complete, isTrue);
        operations.seal();
        expect(budget.usage, isEmpty);
      });
      await expectLater(bootstrap.start(), throwsA(same(_catalogFailure)));
      final retry = bootstrap.start();
      await catalogPort.base.base.feed.listened.future;
      catalogPort.base.base.baseline();
      await retry;
      expect(attachments, 2);
      expect(catalogPort.catalogCalls, 2);
      // RuntimeReady is retained across attachment failure (design/25 §25.9).
      // Retrying the catalog must not initialize a second native runtime.
      expect(startupPort.initializeCalls, 1);
      expect(
        catalog.state.value.projection.sync.phase,
        ResourceSyncPhase.ready,
      );
      expect(catalogPort.base.base.feed.acknowledgements, isNotEmpty);
      expect((await bootstrap.close()).complete, isTrue);
    },
  );

  test('late bootstrap stays owned at deadline and cannot reopen a closed application', () async {
    final environment = ApplicationTestEnvironment()..installHost();
    final port = environment.startupPort..initializeGate = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      environment.hostChannel,
      (call) async => call.method == 'beginExit' ? 0 : null,
    );
    addTearDown(() async {
      if (!port.initializeGate!.isCompleted) port.initializeGate!.complete();
      await environment.close();
    });
    final graph = environment.graph;
    final boot = graph.bootstrap.start();
    await port.initializeEntered.future;
    final closing = graph.exitCoordinator.exit(ExitIntent.exit);
    expect(
      identical(closing, graph.exitCoordinator.exit(ExitIntent.updateRestart)),
      isTrue,
    );
    final report = await closing;
    expect(
      report.shutdown.issues.any(
        (item) => item.stage == 'application-bootstrap',
      ),
      isTrue,
    );
    expect(
      () => graph.drafts.composer('late'),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    port.initializeGate!.complete();
    await boot;
    expect(environment.domains.directory.projectFeeds, isEmpty);
    expect(
      graph.configuration.state.value.projection.sync.phase,
      ResourceSyncPhase.closed,
    );
    expect((await graph.bootstrap.retryCleanup()).complete, isTrue);
    expect((await graph.startup.retryCleanup()).complete, isTrue);
    await environment.close();
    expect(graph.budget.usage, isEmpty);
  });
}

final class _CatalogFailurePort implements ModelsPort {
  final base = SelectorModelsPort();
  int catalogCalls = 0;
  @override
  Future<FeedConnection<ModelCatalogFrame>> openModelCatalog() {
    if (++catalogCalls == 1) {
      return Future.error(_catalogFailure);
    }
    return base.openModelCatalog();
  }

  @override
  Future<ModelCatalogReadConnection> openModelCatalogRead(
    ModelCatalogReadRef reference, {
    required ProductReadOrigin origin,
  }) => base.openModelCatalogRead(reference, origin: origin);
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted catalog capability: ${invocation.memberName}',
  );
}
