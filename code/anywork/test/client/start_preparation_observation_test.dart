import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/interaction/composer_view.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _PreparingTransport extends DemoStudioTransport {
  _PreparingTransport() : super(lspActivityLoop: false) {
    events.onCancel = () => cancelled = true;
  }

  final events = StreamController<NewThreadStartEvent>();
  final entered = Completer<StudioPromptInput>();
  bool cancelled = false;

  @override
  Stream<NewThreadStartEvent> startNewThread(
    String projectId,
    StudioPromptInput input,
    ThreadModeId mode, {
    required ModeModelRouteView route,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    String? workspaceMode,
  }) {
    entered.complete(input);
    return events.stream;
  }
}

void main() {
  test(
    'start-page observers rebind to the same preparation after disposal',
    () async {
      final transport = _PreparingTransport();
      final graph = AppGraph(
        transport: transport,
        clientId: 'preparation-adapter',
      );
      await graph.client.bootstrap();
      await graph.client.directoryCommands.beginNewThread();
      var container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      addTearDown(() async {
        container.dispose();
        await graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        );
        await transport.events.close();
      });
      final project = container.read(startPageComposerViewProvider).project!;
      final owner = graph.client.startDraft;
      owner.updateDraft(project.id, 'prepare a workspace');
      owner.setWorkspaceMode(project.id, ThreadWorkspaceMode.worktree);
      final observer = container.listen(
        startPageComposerViewProvider,
        (_, _) {},
      );
      final submitted = owner.submit(project.id);
      final input = await transport.entered.future;
      observer.close();
      container.dispose();
      expect(
        transport.cancelled,
        isFalse,
        reason: 'route observation owns no creation operation',
      );

      final updated = owner.source.waitFor(
        (state) =>
            state.preparations[project.id]?.progress?.stage ==
            ThreadPreparationStage.creatingWorktree,
      );
      transport.events.add(
        NewThreadStartProgress(
          ThreadPreparationProgress(
            projectId: project.id,
            inputId: input.inputId,
            stage: ThreadPreparationStage.creatingWorktree,
            workspacePath: '/isolated/session-worktree',
            branch: 'pure/session',
          ),
        ),
      );
      await updated;
      owner.setWorkspaceMode(project.id, ThreadWorkspaceMode.local);
      container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      final projection = container.read(startPageComposerViewProvider);
      expect(
        projection.preparation?.progress?.workspacePath,
        '/isolated/session-worktree',
      );
      expect(
        projection.preparation?.workspaceMode,
        ThreadWorkspaceMode.worktree,
      );
      expect(projection.workspaceMode, ThreadWorkspaceMode.local);
      expect(projection.submitting, isTrue);

      transport.events.add(
        const NewThreadStartFailed(
          StudioFailure(
            code: StudioFailureCode.invalidArgument,
            message: 'the repository has no HEAD',
            retryable: false,
            correlationId: 'preparation-adapter-failure',
          ),
        ),
      );
      expect(await submitted, isFalse);
      final terminal = container.read(startPageComposerViewProvider);
      expect(terminal.preparation?.phase, NewThreadPreparationPhase.failed);
      expect(
        terminal.preparation?.progress?.stage,
        ThreadPreparationStage.creatingWorktree,
      );
      expect(terminal.draftText, 'prepare a workspace');
      expect(terminal.submitting, isFalse);
      expect(transport.cancelled, isTrue);
    },
  );
}
