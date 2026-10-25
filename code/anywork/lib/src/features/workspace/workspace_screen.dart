import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/feedback/studio_loading.dart';
import '../../l10n/studio_l10n.dart';
import '../conversation/conversation.dart';
import '../interaction/interaction.dart';
import '../shell/shell_view.dart';
import 'connectors/application_recovery_banner_connector.dart';
import 'connectors/persistence_panel_connector.dart';
import 'connectors/recovery_check_status_connector.dart';
import 'connectors/sidebar_connector.dart';
import 'connectors/startup_recovery_banner_connector.dart';
import 'connectors/workspace_header_connector.dart';
import 'state/collection_presentation.dart';
import 'state/workspace_view_state.dart';
import 'view_models/sidebar_view_model.dart';
import 'view_models/workspace_view_model.dart';
import 'views/unopened_thread_view.dart';
import 'views/workspace_activation_failure_view.dart';
import 'views/workspace_open_result_view.dart';
import 'views/workspace_start_view.dart';
import 'widgets/workspace_failure_notice.dart';

/// Smart application workspace. Routing remains with the one app router; this
/// screen forwards typed navigation intents and reads D3's unique selection.
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({
    required this.onAddProject,
    required this.onNavigate,
    super.key,
  });
  final VoidCallback onAddProject;
  final ValueChanged<WorkspaceNavigationIntent> onNavigate;

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  @override
  Widget build(BuildContext context) {
    final watched = ref.watch(workspaceViewModelProvider);
    final sidebar = ref.watch(sidebarViewModelProvider).asData?.value;
    final vm = ref.read(workspaceViewModelProvider.notifier);
    final sidebarVM = ref.read(sidebarViewModelProvider.notifier);
    ref.listen(workspaceViewModelProvider, (previous, next) {
      final intent = next.asData?.value.navigation;
      if (intent == null ||
          previous?.asData?.value.navigation?.serial == intent.serial) {
        return;
      }
      widget.onNavigate(intent);
    });
    return watched.when(
      loading: () => const StudioWorkspaceLoading(),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return Center(
          child: WorkspaceFailureNotice(
            failure: error,
            onRetry: () => ref.invalidate(workspaceViewModelProvider),
          ),
        );
      },
      data: (value) {
        final selection = value.workspace.selection;
        final threadId = selection.threadId;
        final projectId = selection.projectId;
        final activationFailure = value.activationFailure;
        final general = sidebar == null
            ? null
            : presentReadValue(sidebar.configuration.general);
        // Lookup can fail before an entity ref/value exists even while the
        // canonical source is ready. Keep its error alongside source/read
        // failures, never replacing either with a healthy empty selection.
        final metadataErrors = <StudioFailure>{
          ?value.selectedMetadata?.projection.sync.error,
          if (value.selectedMetadata?.value case FailedReadValue(:final error))
            error,
          ?value.selectedMetadata?.readError,
          ?value.metadataDemandError,
        };
        void retryMetadata() {
          if (!mounted ||
              !identical(ref.read(workspaceViewModelProvider.notifier), vm)) {
            return;
          }
          final current = ref.read(workspaceViewModelProvider).asData?.value;
          if (current == null ||
              current.workspace.sealed ||
              current.workspace.selectionGeneration !=
                  value.workspace.selectionGeneration ||
              current.workspace.selection != selection ||
              !identical(current.selectedMetadata, value.selectedMetadata) ||
              value.selectedMetadata == null && !identical(current, value)) {
            return;
          }
          // The VM captures its original metadata borrow before retry's await;
          // an obsolete notice cannot redirect that retry to a new selection.
          unawaited(vm.retrySelectedMetadata());
        }

        return AppShell(
          navigation: ShellNavigationView(
            projectDirectory: SidebarConnector(
              onAddProject: widget.onAddProject,
            ),
          ),
          chrome: WorkspaceHeaderConnector(workspace: value),
          canonicalSidebarWidth: general?.sidebarWidth,
          widthDraft: sidebar?.widthDraft,
          onResizeWidth: sidebarVM.resizeWidth,
          onResetWidth: () => sidebarVM.changeWidth(336),
          onCommitWidth: sidebarVM.commitWidth,
          onCancelWidth: sidebarVM.cancelWidth,
          // Notices never starve the workspace: they are bounded to a share of
          // the window and scroll inside that box, so any number of stacked
          // failure banners keeps the conversation footer usable.
          notices: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.3,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Canonical Project directory failure with its own retry entry, as
                  // before the split; later notice kinds stack below it.
                  if (value.projects.projection.sync.error case final error?)
                    MaterialBanner(
                      key: const ValueKey('project-directory-failure'),
                      leading: const Icon(Icons.sync_problem),
                      content: Text(error.message),
                      actions: [
                        TextButton(
                          key: const ValueKey('project-directory-retry'),
                          onPressed: value.workspace.sealed
                              ? null
                              : () => unawaited(vm.retryProjectsSource()),
                          child: Text(context.l10n.runtimeFatalRetry),
                        ),
                      ],
                    ),
                  if (value.projectReadError case final error?)
                    WorkspaceFailureNotice(
                      failure: error,
                      onRetry: () => unawaited(vm.loadSelectedProject()),
                    ),
                  for (final error in metadataErrors)
                    WorkspaceFailureNotice(
                      failure: error,
                      onRetry: value.workspace.sealed || threadId == null
                          ? null
                          : retryMetadata,
                    ),
                  if (value.opening)
                    const LinearProgressIndicator(minHeight: 2),
                  if (value.openAdmissionError case final error?)
                    WorkspaceFailureNotice(failure: error),
                  if (value.openResult case final result?)
                    WorkspaceOpenResultView(
                      result: result,
                      onDismiss: vm.dismissOpenResult,
                    ),
                  const PersistencePanelConnector(),
                  const StartupRecoveryBannerConnector(),
                  const ApplicationRecoveryBannerConnector(),
                  const RecoveryCheckStatusConnector(),
                ],
              ),
            ),
          ),
          workspace: threadId != null && selection.needsOpen
              ? Center(
                  child: UnopenedThreadView(
                    threadId: threadId,
                    onOpen:
                        value.workspace.sealed ||
                            value.actions['open-thread:$threadId']?.waiting ==
                                true
                        ? null
                        : () => unawaited(vm.openSelectedThread(threadId)),
                  ),
                )
              : activationFailure != null
              ? WorkspaceActivationFailureView(
                  failure: activationFailure.error,
                  onRetry:
                      value.workspace.sealed ||
                          !activationFailure.error.retryable
                      ? null
                      : () {
                          try {
                            vm.retryActivation(activationFailure);
                          } on StudioFailure catch (error) {
                            // A stale retry is a rejected action, not a replacement for
                            // D1's activation-failure evidence or the current selection.
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: WorkspaceFailureNotice(failure: error),
                              ),
                            );
                          }
                        },
                )
              : threadId != null
              ? ConversationScreen(
                  key: ValueKey(('conversation', threadId)),
                  threadId: threadId,
                )
              : WorkspaceStartView(
                  hasProject: projectId != null,
                  projectName: value.selectedProject?.name,
                  onAddProject: widget.onAddProject,
                  composer: projectId == null
                      ? null
                      : StartInputConnector(
                          key: ValueKey(('start-composer', projectId)),
                          projectId: projectId,
                        ),
                ),
        );
      },
    );
  }
}
