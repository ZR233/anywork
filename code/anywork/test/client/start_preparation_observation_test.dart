import 'dart:async';

import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/view_models/composer_view_model.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/drafts_native_fixture.dart';
import 'support/timeline_drafts_environment.dart';

void main() {
  test(
    'start-page observers rebind to the same preparation after disposal',
    () async {
      final fixture = TimelineDraftsEnvironment(clientId: 'preparation-adapter');
      addTearDown(fixture.close);
      await _boundary(fixture.establish(), 'initial native material');
      await _boundary(
        fixture.recovery.loadSourceStatus(),
        'current Recovery source',
      );
      final selected = await _boundary(
        fixture.workspace.beginNewThread('project').result,
        'Start selection',
      );
      expect(
        selected,
        isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
        reason: selected is RejectedCommandResult<WorkspaceSelectionResult>
            ? '${selected.error.code.name}: ${selected.error.message}'
            : null,
      );
      ProviderContainer createContainer() => ProviderContainer(
        overrides: [
        draftsRepositoryProvider.overrideWithValue(fixture.repository),
        ],
      );
      var container = createContainer();
      final provider = composerViewModelProvider(
        const ComposerKey.start(projectId: 'project'),
      );
      addTearDown(() => container.dispose());
      final owner = fixture.repository.start('project');
      owner.setText('prepare a workspace');
      owner.setWorkspaceMode(ThreadWorkspaceMode.worktree);
      final preparing = owner.prepareRoute();
      final routePin = (await _boundary(
        fixture.configuration.opened(0),
        'Start route open',
      )).accept();
      final resolve = await _boundary(routePin.called(0), 'Start route query');
      resolve.reply.complete(
        StartRouteRead.ready(
          sources: routePin.originalHeader,
          query: resolve.query,
        intent: resolve.query.intent,
          route: const ModelSelection(
            model: AccountModelKey(
              accountId: 'start-account',
              modelId: 'native-model',
            ),
            effort: null,
          ),
          defaults: const DelegationSettings(
            mode: DelegationMode.automatic,
            preference: DelegationPreference.economy,
          ),
        ),
      );
      await _boundary(preparing, 'Start route preparation');
      final observer = container.listen(provider, (_, _) {});
      await _boundary(container.read(provider.future), 'first Composer VM');
      final submitted = owner.submit();
      final opening = await Future.any([
        fixture.creations.begins.at(0),
        submitted.result.then(
          (result) => throw StateError(switch (result) {
            RejectedCommandResult(:final error) =>
              'Creation rejected: ${error.code.name}: ${error.message}',
          _ => 'Creation was not admitted: $result',
          }),
        ),
      ]);
      final creation = DraftCreationJob(
        submitted.id,
        'project',
        opening.request.input.inputId,
      );
      opening.reply.complete(creation);
      final result = await _boundary(
        creation.reads.at(0),
        'native creation result read',
      );
      // Wait for the real Drafts owner to observe native progress before
      // disposing its presentation observer. Native work is not UI-owned.
      expect(creation.progress.observerCount, 1);
      observer.close();
      container.dispose();
      expect(
        creation.requests != 0,
        isFalse,
        reason: 'route observation owns no creation operation',
      );
      expect(creation.progress.observerCount, 1);

      creation.progressSource.publish(
        ThreadPreparationProgress(
          projectId: 'project',
          inputId: opening.request.input.inputId,
            stage: ThreadPreparationStage.creatingWorktree,
          workspacePath: '/isolated/session-worktree',
          branch: 'pure/session',
        ),
      );
      owner.setWorkspaceMode(ThreadWorkspaceMode.local);
      container = createContainer();
      final rebuilt = container.listen(provider, (_, _) {});
      addTearDown(rebuilt.close);
      final projection = await _boundary(
        container.read(provider.future),
        'rebuilt Composer VM',
      );
      expect(
        projection.startDraft?.preparation?.progress?.workspacePath,
        '/isolated/session-worktree',
      );
      expect(
        projection.startDraft?.preparation?.workspaceMode,
        ThreadWorkspaceMode.worktree,
      );
      expect(projection.startDraft?.workspaceMode, ThreadWorkspaceMode.local);
      expect(projection.submission is SubmittingDraft, isTrue);

      result.completeError(
        const CommandDispatchFailure.rejected(
        failure: StudioFailure(
            code: StudioFailureCode.invalidArgument,
            message: 'the repository has no HEAD',
            retryable: false,
            correlationId: 'preparation-adapter-failure',
          ),
        ),
      );
      final close = await _boundary(
        creation.closes.at(0),
        'native creation close',
      );
      close.reply.complete(
        FeedCloseReport(
          feedId: submitted.id.value,
          outcome: const FeedCloseOutcome.clean(),
        ),
      );
      expect(
        await _boundary(submitted.result, 'original submission result'),
        isA<RejectedCommandResult<StartNewThreadResult>>(),
      );
      final terminal = container.read(provider).requireValue;
      expect(
        terminal.startDraft?.preparation?.phase,
        NewThreadPreparationPhase.failed,
      );
      expect(
        terminal.startDraft?.preparation?.progress?.stage,
        ThreadPreparationStage.creatingWorktree,
      );
      expect(terminal.text, 'prepare a workspace');
      expect(terminal.submission is SubmittingDraft, isFalse);
      expect(creation.requests != 0, isTrue);
      expect(creation.progress.observerCount == 0, isTrue);
    },
  );
}

Future<T> _boundary<T>(Future<T> future, String name) => future.timeout(
  const Duration(seconds: 5),
  onTimeout: () =>
      throw TimeoutException('No actual $name boundary was reached.'),
);
