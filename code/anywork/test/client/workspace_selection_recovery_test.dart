import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/app/composition/workspace_conversation_binding.dart';
import 'package:anywork/src/app/lifecycle/exit_participant.dart';
import 'package:anywork/src/features/workspace/view_models/sidebar_view_model.dart';
import 'package:anywork/src/features/workspace/view_models/workspace_view_model.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/configuration_fixture.dart';
import '../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../anywork_client/test/support/updates_port_fixture.dart';
import '../../../anywork_client/test/support/workspace_selection_fixture.dart';

const _cold = WorkspaceSelection(
  projectId: 'project',
  threadId: 'cold-child',
  needsOpen: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final restoreBeforeBuild in [false, true]) {
    test(
      'application cold restoration stays unread and inactive until explicit open (before build: $restoreBeforeBuild)',
      () async {
        final fixture = WorkspaceSelectionFixture();
        final workspace = fixture.workspace;
        final conversations = fixture.conversations;
        final binding = WorkspaceConversationBinding(
          workspace: workspace,
          demand: conversations.demand,
        );
        final container = ProviderContainer(
          overrides: [
            workspaceRepositoryProvider.overrideWithValue(workspace),
            conversationRepositoryProvider.overrideWithValue(
              conversations.repository,
            ),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await binding.close();
          expect((await fixture.close()).unresolved, isEmpty);
          expect(fixture.budget.usage, isEmpty);
        });
        if (restoreBeforeBuild) workspace.restoreSelection(_cold);
        binding.start();
        await container.read(workspaceViewModelProvider.future);
        final vm = container.read(workspaceViewModelProvider.notifier);
        if (!restoreBeforeBuild) {
          final WorkspaceSelectionResult result = vm.restoreSelection(_cold);
          expect(result.selection, _cold);
        }
        await container.pump();
        final restored = container
            .read(workspaceViewModelProvider)
            .requireValue;
        expect(
          restored.workspace,
          workspace.state.value,
          reason: 'The VM only presents the SDK-owned selection',
        );
        expect(restored.workspace.selection, _cold);
        expect(restored.selectedMetadata, isNull);
        expect(
          restored.actions,
          isEmpty,
          reason: 'Restoration is not wrapped in an application command',
        );
        expect(fixture.directory.native.threads, isEmpty);
        expect(fixture.directory.native.projects, isEmpty);
        expect(fixture.directory.native.restores, isEmpty);
        expect(fixture.directory.activations, isEmpty);
        expect(conversations.context.metadataRequests, isEmpty);
        expect(conversations.context.recoveryRequests, isEmpty);
        expect(conversations.repository.active.value, isNull);
        expect(
          conversations.repository.existingSession(_cold.threadId!),
          isNull,
        );
        expect(conversations.timeline.requests, isEmpty);
        expect(conversations.facets.execution, isEmpty);
        expect(conversations.operations.observations.records.value, isEmpty);
        await vm.retrySelectedMetadata();
        await vm.loadSelectedProject();
        expect(
          fixture.directory.native.threads,
          isEmpty,
          reason: 'A read retry cannot bypass explicit open',
        );
        expect(fixture.directory.native.projects, isEmpty);

        await fixture.establishAccess();
        final opening = vm.openSelectedThread(_cold.threadId!);
        final material = await fixture.directory.threadBaseline(
          0,
          fixtureThread('cold-child', parentThreadId: 'root'),
        );
        await material.entityEntered.future;
        final result = await opening;
        expect(
          result,
          isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
          reason: result is RejectedCommandResult<WorkspaceSelectionResult>
              ? '${result.error.code}: ${result.error.message}'
              : null,
        );
        final opened = container.read(workspaceViewModelProvider).requireValue;
        expect(opened.workspace, workspace.state.value);
        expect(opened.workspace.selection, _cold.copyWith(needsOpen: false));
        expect(conversations.repository.active.value?.threadId, _cold.threadId);
        expect(conversations.context.metadataRequests, [_cold.threadId]);
        expect(
          conversations.context.recoveryRequests.single.id,
          _cold.threadId,
        );
        expect(
          fixture.directory.native.restores,
          isEmpty,
          reason: 'Cold open never restores execution',
        );
        expect(fixture.directory.activations, isEmpty);

        final metadataScopes = fixture.directory.native.threads.length;
        final operations = conversations.operations.observations.records.value;
        vm.restoreSelection(_cold);
        await container.pump();
        final coldAgain = container
            .read(workspaceViewModelProvider)
            .requireValue;
        expect(coldAgain.workspace, workspace.state.value);
        expect(coldAgain.workspace.selection, _cold);
        expect(
          coldAgain.selectedMetadata,
          isNull,
          reason: 'The previous opened metadata borrow is released',
        );
        expect(conversations.repository.active.value, isNull);
        expect(
          fixture.directory.native.threads,
          hasLength(metadataScopes),
          reason: 'Restoring the same previously opened Thread must not reborrow its metadata',
        );
        expect(conversations.context.metadataRequests, [_cold.threadId]);
        expect(conversations.operations.observations.records.value, operations);
      },
    );

    test(
      'cold restoration does not auto-expand a Sidebar metadata query (before build: $restoreBeforeBuild)',
      () async {
        final fixture = WorkspaceSelectionFixture();
        final configuration = ConfigurationFixture(budget: fixture.budget);
        final updates = UpdatesPortFixture(resourceBudget: fixture.budget);
        final workspace = fixture.workspace;
        final container = ProviderContainer(
          overrides: [
            workspaceRepositoryProvider.overrideWithValue(workspace),
            configurationRepositoryProvider.overrideWithValue(
              configuration.repository,
            ),
            updatesRepositoryProvider.overrideWithValue(updates.repository),
            applicationEditProducerRegistryProvider.overrideWithValue(
              ApplicationEditProducerRegistry(),
            ),
          ],
        );
        addTearDown(() async {
          container.dispose();
          final reports = await Future.wait([
            fixture.close(),
            configuration.repository.close(),
            configuration.models.close(),
            updates.close(),
          ]);
          expect(reports.expand((report) => report.unresolved), isEmpty);
          expect(fixture.budget.usage, isEmpty);
        });
        if (restoreBeforeBuild) workspace.restoreSelection(_cold);
        await container.read(sidebarViewModelProvider.future);
        // A visible project list is an independent read demand. It must not turn
        // the restored Thread into an implicit expanded metadata query.
        await fixture.directory.projectsBaseline();
        await container
            .read(sidebarViewModelProvider.notifier)
            .loadProjectsPage();
        if (!restoreBeforeBuild) workspace.restoreSelection(_cold);
        await container.pump();
        final sidebar = container.read(sidebarViewModelProvider).requireValue;
        expect(sidebar.workspace, workspace.state.value);
        expect(sidebar.workspace.selection, _cold);
        expect(sidebar.expandedProjectIds, isEmpty);
        expect(sidebar.pages, isEmpty);
        expect(fixture.directory.native.threads, isEmpty);

        // Explicit directory browsing remains available independently of opening
        // a Conversation; it must not change the restored selection.
        container
            .read(sidebarViewModelProvider.notifier)
            .toggleExpanded(_cold.projectId!);
        final query = await fixture.directory.threadOpens.at(0);
        expect(query.scope, isA<QueryThreadDirectoryScope>());
        expect(workspace.state.value.selection, _cold);
      },
    );
  }
}
