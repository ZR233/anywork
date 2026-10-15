import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/interaction/composer_view.dart';
import 'package:anywork/src/features/shell/shell_view.dart';
import 'package:anywork/src/features/status/status_view.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

final class _UnusedTransport implements StudioTransport {
  var calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw UnsupportedError(
      'Driver query attempted transport: ${invocation.memberName}',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('workspace and Driver join current directory identity after a Turn', () async {
    final graph = AppGraph(
      transport: RecordingDemoTransport(),
      clientId: 'directory-identity',
    );
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    );
    final client = graph.client;
    await client.bootstrap();
    await client.directoryCommands.selectThread('thread-main');
    final session = client.existingSession('thread-main')!;
    await session.source.waitFor((state) => state.hasChatWindow);
    final initial = session.state.workspace!;
    // A runtime baseline may predate the directory's terminal/title/mode frame.
    session.applySnapshot(
      initial.copyWith(
        thread: initial.thread.copyWith(status: ThreadStatusView.running),
      ),
    );
    final container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    addTearDown(container.dispose);
    final workspace = container.listen(
      shellComposerWorkspaceProvider,
      (_, _) {},
    );
    final status = container.listen(statusBarViewProvider, (_, _) {});
    final composer = container.listen(
      composerDockViewProvider('thread-main'),
      (_, _) {},
    );
    addTearDown(workspace.close);
    addTearDown(status.close);
    addTearDown(composer.close);
    final canonical = initial.thread.copyWith(
      title: 'Completed canonical title',
      mode: ThreadModeId.task,
      status: ThreadStatusView.idle,
      updatedAt: initial.thread.updatedAt,
    );
    client.threadDirectory.applyDelta(
      revision: client.threadDirectory.state.revision + 1,
      upserted: [canonical],
      removed: const [],
    );
    // The directory frame can arrive before an already captured runtime
    // baseline. Unix-second timestamps cannot order these resource domains.
    session.applySnapshot(
      initial.copyWith(
        thread: initial.thread.copyWith(status: ThreadStatusView.running),
      ),
    );
    expect(client.findThread('thread-main'), same(canonical));
    final facts = queryStudioDriverFacts(client);
    final json =
        jsonDecode(StudioDriverState.snapshotJson(observed: facts)) as Map;
    expect((json['workspace'] as Map)['threadStatus'], 'idle');
    expect(facts.workspace!.thread, same(canonical));
    expect(workspace.read()!.thread, same(canonical));
    expect(status.read()!.thread, same(canonical));
    expect(composer.read().thread, same(canonical));
  });

  test(
    'Driver reads current Client facts without creating any owner or lease',
    () async {
      final transport = _UnusedTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'driver-query',
      );
      final thread = StudioThread(
        id: 'thread',
        projectId: 'project',
        title: 'Original title',
        mode: ThreadModeId.simple,
        updatedAt: DateTime.utc(2026),
        workspacePath: '/tmp/thread',
      );
      client.threadDirectory.applyWindow(
        ThreadDirectoryWindow(threads: [thread], revision: 1),
      );
      bindStudioDriver(client);
      final usageBefore = client.budget.usage.length;
      final original = StudioDriverState.readFacts();
      expect(original.rootThreads.single.title, 'Original title');
      expect(client.sessionStates, isEmpty);
      expect(client.composerState('thread'), isNull);
      expect(client.ownedSkills, isEmpty);
      expect(client.ownedSessionCosts, isEmpty);
      expect(transport.calls, 0);

      client.threadDirectory.applyDelta(
        revision: 2,
        upserted: [thread.copyWith(title: 'Updated canonical title')],
        removed: const [],
      );
      final current = StudioDriverState.readFacts();
      expect(current.rootThreads.single.title, 'Updated canonical title');
      expect(original.rootThreads.single.title, 'Original title');
      expect(() => current.rootThreads.add(thread), throwsUnsupportedError);
      final json =
          jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
      final directory = json['sidebarDirectory'] as Map<String, dynamic>;
      expect(directory['titles'], {'thread': 'Updated canonical title'});
      studioDriverTopicDiagnostics(client);
      expect(client.sessionStates, isEmpty);
      expect(client.composerState('thread'), isNull);
      expect(client.budget.usage.length, usageBefore);
      expect(
        transport.calls,
        0,
        reason: 'snapshot queries never create transport demand',
      );
      expect((await client.close()).complete, isTrue);
    },
  );
}
