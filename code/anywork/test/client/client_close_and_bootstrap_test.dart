import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anywork/src/app/app_graph.dart';

import 'support/test_statistics_feed.dart';

import 'support/recording_demo_transport.dart';

class _CatalogFailureTransport extends RecordingDemoTransport {
  int catalogCalls = 0;
  @override
  Future<AccountCatalogView> loadAccountCatalog() {
    if (++catalogCalls == 1) {
      return Future.error(StateError('catalog unavailable'));
    }
    return super.loadAccountCatalog();
  }
}

class _LateBootstrapTransport extends RecordingDemoTransport {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<StudioBootstrap> readBootstrap() async {
    entered.complete();
    await release.future;
    return super.readBootstrap();
  }
}

void main() {
  test('closing a project discards only its logical drafts and releases their permits', () async {
    final transport = RecordingDemoTransport();
    final client = AnyworkClient(
      transport: transport,
      clientId: 'project-close',
    );
    await client.bootstrap();
    final projectId = client.selection.state.selectedProjectId!;
    client.startDraft.updateDraft(projectId, 'closed project draft');
    final composer = client.composer('thread-main')
      ..updateDraft('closed Thread draft');
    await client.directoryCommands.archiveProject(projectId);
    expect(client.startDraft.state.projects.containsKey(projectId), isFalse);
    expect(client.composerState('thread-main'), isNull);
    expect(composer.state.draft, isEmpty);
    expect(client.budget.used(ResourceKind.draft), 0);
    expect((await client.close()).complete, isTrue);
  });

  test(
    'template failure retries its own resource without re-running bootstrap',
    () async {
      final transport = _CatalogFailureTransport();
      final graph = AppGraph(
        transport: transport,
        statisticsFeed: const TestStatisticsFeedPort(),
        clientId: 'bootstrap-retry',
      );
      final client = graph.client;
      addTearDown(
        () => graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 3)),
        ),
      );
      await client.bootstrap();
      await expectLater(graph.accounts.loadTemplates(), throwsStateError);
      expect(graph.accounts.state.value.templates.revision, isEmpty);
      await graph.accounts.loadTemplates();
      expect(graph.accounts.state.value.templates.revision, isNotEmpty);
      expect(transport.bootstrapCalls, 1);
      expect(transport.catalogCalls, 2);
      expect(client.applicationTopics, isNotEmpty);
      expect((await client.close()).complete, isTrue);
    },
  );

  test(
    'late bootstrap stays owned at deadline and cannot reopen a closed client',
    () async {
      final transport = _LateBootstrapTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'late-bootstrap',
      );
      final boot = client.bootstrap();
      await transport.entered.future;
      final deadline = DateTime.utc(2000);
      final closing = client.close(deadline: deadline);
      expect(
        identical(closing, client.close(deadline: DateTime.utc(2100))),
        isTrue,
      );
      final report = await closing;
      expect(
        report.unresolved.any((item) => item.owner == 'bootstrap'),
        isTrue,
      );
      expect(() => client.composer('late'), throwsStateError);
      transport.release.complete();
      await boot;
      expect(client.applicationTopics, isEmpty);
      expect(client.settings.state.configLoaded, isFalse);
      expect((await client.retryCleanup()).complete, isTrue);
      expect(client.budget.usage, isEmpty);
    },
  );
}
