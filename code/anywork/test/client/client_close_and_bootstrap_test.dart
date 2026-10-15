import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

class _CatalogFailureTransport extends RecordingDemoTransport {
  int catalogCalls = 0;
  @override
  Future<ProviderCatalogView> loadProviderCatalog() {
    if (++catalogCalls == 1) {
      return Future.error(StateError('catalog unavailable'));
    }
    return super.loadProviderCatalog();
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
    'catalog failure can explicitly retry the entire typed bootstrap',
    () async {
      final transport = _CatalogFailureTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'bootstrap-retry',
      );
      await expectLater(client.bootstrap(), throwsStateError);
      await client.bootstrap();
      expect(transport.bootstrapCalls, 2);
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
