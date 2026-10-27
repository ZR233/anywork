import 'support/test_statistics_feed.dart';

import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/interaction/composer_view.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _waitLimit = Duration(seconds: 5);

final class _PreparingTransport extends DemoStudioTransport {
  _PreparingTransport() : super(lspActivityLoop: false);

  StreamController<NewThreadStartEvent>? _events;
  StreamController<NewThreadStartEvent> get events => _events!;
  final entered = Completer<StudioPromptInput>();
  bool _listened = false;
  bool cancelled = false;
  int starts = 0;
  String? receivedProjectId;
  String? receivedWorkspaceMode;

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
    starts++;
    if (_events != null) {
      throw StateError('Only one creation is scripted by this fixture');
    }
    receivedProjectId = projectId;
    receivedWorkspaceMode = workspaceMode;
    _events = StreamController<NewThreadStartEvent>(
      onListen: () => _listened = true,
      onCancel: () => cancelled = true,
    );
    entered.complete(input);
    return events.stream;
  }

  Future<void> closeEvents() async {
    final controller = _events;
    if (controller == null) return;
    // A rejected submit never creates this controller. If admission failed
    // before listening, consume done rather than awaiting an unlistened close.
    final drain = _listened ? null : controller.stream.listen((_) {});
    if (!cancelled && !controller.isClosed) {
      // An assertion may fail while the controlled creation is still active.
      // Supply a typed terminal outcome before closing, not an unknown EOF.
      controller.add(
        const NewThreadStartFailed(
          StudioFailure(
            code: StudioFailureCode.runtimeStopped,
            message: 'The controlled preparation fixture is closing',
            retryable: false,
            correlationId: 'preparation-fixture-close',
          ),
        ),
      );
    }
    try {
      await controller.close().timeout(_waitLimit);
    } finally {
      await drain?.cancel();
    }
  }
}

void main() {
  test(
    'start-page observers rebind to the same preparation after disposal',
    () async {
      final transport = _PreparingTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'preparation-adapter',
      );
      var container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      var containerDisposed = false;
      Future<bool>? submission;
      void disposeContainer() {
        if (containerDisposed) return;
        container.dispose();
        containerDisposed = true;
      }

      addTearDown(() async {
        disposeContainer();
        try {
          await transport.closeEvents();
          if (submission case final pending?) {
            await pending.timeout(_waitLimit);
          }
        } finally {
          final report = await graph
              .close(deadline: DateTime.now().add(_waitLimit))
              .timeout(_waitLimit + const Duration(seconds: 1));
          expect(
            report.complete,
            isTrue,
            reason: report.unresolved
                .map((value) => '${value.owner}: ${value.reason}')
                .join('; '),
          );
        }
      });
      await graph.client.bootstrap();
      await graph.client.directoryCommands.beginNewThread();
      final projectId = graph.client.selection.state.selectedProjectId!;
      final owner = graph.client.startDraft;
      owner.updateDraft(projectId, 'prepare a workspace');
      owner.setWorkspaceMode(projectId, ThreadWorkspaceMode.worktree);

      // Bootstrap no longer materializes the model directory. An unavailable
      // route must reject without starting creation or losing the raw intent.
      expect(graph.models.state.value.accounts, isEmpty);
      submission = owner.submit(projectId);
      expect(await submission.timeout(_waitLimit), isFalse);
      expect(transport.entered.isCompleted, isFalse);
      expect(transport.starts, 0);
      expect(owner.state.preparations[projectId], isNull);
      expect(owner.state.forProject(projectId).text, 'prepare a workspace');
      expect(
        owner.state.forProject(projectId).workspaceMode,
        ThreadWorkspaceMode.worktree,
      );

      final observer = container.listen(
        startPageComposerViewProvider,
        (_, _) {},
      );
      await graph.accounts.state
          .waitFor((state) => state.loaded)
          .timeout(_waitLimit);
      await graph.models.state
          .waitFor(
            (state) => state.accounts.values.any(
              (resource) =>
                  resource.loaded && resource.value?.models.isNotEmpty == true,
            ),
          )
          .timeout(_waitLimit);
      final project = container.read(startPageComposerViewProvider).project!;
      expect(project.id, projectId);
      final submitted = submission = owner.submit(project.id);
      final input = await Future.any<StudioPromptInput>([
        transport.entered.future,
        submitted.then<StudioPromptInput>((accepted) {
          throw StateError(
            'Submission completed before transport entry: accepted=$accepted',
          );
        }),
      ]).timeout(_waitLimit);
      expect(transport.starts, 1);
      expect(transport.receivedProjectId, project.id);
      expect(transport.receivedWorkspaceMode, ThreadWorkspaceMode.worktree.id);
      observer.close();
      disposeContainer();
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
      await updated.timeout(_waitLimit);
      owner.setWorkspaceMode(project.id, ThreadWorkspaceMode.local);
      container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      containerDisposed = false;
      final projection = container.read(startPageComposerViewProvider);
      expect(projection.preparation?.inputId, input.inputId);
      expect(projection.preparation?.projectId, project.id);
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
      expect(
        transport.starts,
        1,
        reason: 'rebinding must not restart creation',
      );
      expect(transport.receivedWorkspaceMode, ThreadWorkspaceMode.worktree.id);

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
      expect(await submitted.timeout(_waitLimit), isFalse);
      final terminal = container.read(startPageComposerViewProvider);
      expect(terminal.preparation?.phase, NewThreadPreparationPhase.failed);
      expect(terminal.preparation?.inputId, input.inputId);
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
