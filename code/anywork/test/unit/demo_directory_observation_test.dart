import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Demo routes metadata by ID and publishes only changed structure', (
    tester,
  ) async {
    // The test clock keeps Demo's background prompt/title timers from racing
    // the explicit directory commands. No UI or replacement reducer is used.
    final transport = DemoStudioTransport();
    final metadata = <ThreadObservationHandle>[];
    final directories = <ThreadsObservationHandle>[];

    try {
      final bootstrap = await transport.readBootstrap();
      await tester.pump(const Duration(seconds: 1));
      final b = bootstrap.threadDirectory.rows.firstWhere(
        (row) => row.isRootRow && !row.archived,
      );
      final events = await transport
          .startNewThread(
            b.workspaceId,
            const StudioPromptInput(
              inputId: 'demo-directory-input',
              text: 'Directory observation contract',
              attachmentDraftIds: [],
            ),
            ThreadModeId.simple,
            route: bootstrap.settingsState.modeModelRoutes.firstWhere(
              (route) => route.modeId == ThreadModeId.simple,
            ),
            delegationMode: DelegationMode.automatic,
            delegationPreference: DelegationPreference.balanced,
          )
          .toList();
      expect(events.whereType<NewThreadStartFailed>(), isEmpty);
      final a = events
          .whereType<NewThreadStartSucceeded>()
          .single
          .result
          .thread;
      final list = await transport.openThreadsObservation(
        DirectoryQuery.withThreadIds(
          workspaceId: b.workspaceId,
          threadIds: [a.id, b.threadId],
        ),
        DirectoryWindow(limit: 1),
      );
      directories.add(list);
      final aMetadata = await transport.openThreadObservation(a.id);
      metadata.add(aMetadata);
      final bMetadata = await transport.openThreadObservation(b.threadId);
      metadata.add(bMetadata);
      final initial = (await list.next())!;
      expect(initial.threadIds, [a.id]);
      expect(initial.nextCursor, isNotNull);
      expect((await aMetadata.next())!.row!.threadId, a.id);
      expect((await bMetadata.next())!.row!.threadId, b.threadId);

      var listCompleted = false;
      var bCompleted = false;
      final listPending = list.next().then((frame) {
        listCompleted = true;
        return frame;
      });
      final bPending = bMetadata.next().then((frame) {
        bCompleted = true;
        return frame;
      });
      final renamedPending = aMetadata.next();
      await transport.renameThread(
        a.id,
        'Renamed A',
        operationId: const OperationId('demo-directory-rename-a'),
      );
      final renamed = (await renamedPending)!;
      expect(renamed.threadId, a.id);
      expect(renamed.row!.title, 'Renamed A');
      expect(renamed.stamp.revision, greaterThan(initial.stamp.revision));
      await tester.pump();
      expect(bCompleted, isFalse, reason: 'A must not wake B metadata');
      expect(
        listCompleted,
        isFalse,
        reason: 'a revision/title change is not changed IDs or cursor',
      );

      // Removing the off-window B changes only pagination, not the visible IDs.
      // This catches a deduplicator that compares IDs but forgets nextCursor.
      var aCompleted = false;
      final aPending = aMetadata.next().then((frame) {
        aCompleted = true;
        return frame;
      });
      await transport.archiveThread(
        b.threadId,
        operationId: const OperationId('demo-directory-archive-b'),
      );
      final cursorChanged = (await listPending)!;
      expect(cursorChanged.threadIds, initial.threadIds);
      expect(cursorChanged.nextCursor, isNull);
      expect((await bPending)!.row!.archived, isTrue);
      await tester.pump();
      expect(aCompleted, isFalse, reason: 'B removal must not wake A metadata');

      // A real membership change completes the next structural demand as well.
      var bAfterArchiveCompleted = false;
      final bAfterArchive = bMetadata.next().then((frame) {
        bAfterArchiveCompleted = true;
        return frame;
      });
      final removedPending = list.next();
      await transport.archiveThread(
        a.id,
        operationId: const OperationId('demo-directory-archive-a'),
      );
      expect((await removedPending)!.threadIds, isEmpty);
      expect((await aPending)!.row!.archived, isTrue);
      await tester.pump();
      expect(bAfterArchiveCompleted, isFalse);

      final aClosing = aMetadata.next();
      final listClosing = list.next();
      for (final handle in metadata) {
        handle.requestClose();
      }
      list.requestClose();
      expect(await aClosing, isNull);
      expect(await bAfterArchive, isNull);
      expect(await listClosing, isNull);
      await Future.wait([
        for (final handle in metadata) handle.close(),
        list.close(),
      ]);
      expect(await aMetadata.next(), isNull);
      expect(await bMetadata.next(), isNull);
      expect(await list.next(), isNull);
    } finally {
      for (final handle in metadata) {
        handle.requestClose();
      }
      for (final handle in directories) {
        handle.requestClose();
      }
      await Future.wait([
        for (final handle in metadata) handle.close(),
        for (final handle in directories) handle.close(),
      ]);
      expect(await transport.cancelDartSubscriptions(budgetMs: 5000), isEmpty);
      // The automatic title's one-shot delay is not a directory demand.
      await tester.pump(const Duration(seconds: 1));
    }
  });
}
