import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/feedback/studio_loading.dart';
import '../conversation/conversation.dart';
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
import 'views/workspace_layout_view.dart';
import 'views/workspace_open_result_view.dart';
import 'views/workspace_start_view.dart';
import 'widgets/workspace_failure_notice.dart';

/// Smart application workspace. Routing remains with the one app router; this
/// screen forwards typed navigation intents and reads D3's unique selection.
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({required this.onAddProject, required this.onNavigate, super.key});
  final VoidCallback onAddProject;
  final ValueChanged<WorkspaceNavigationIntent> onNavigate;

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  bool _reportedFirstFrame = false;

  void _afterFirstFrame(WorkspaceState frozen) {
    if (_reportedFirstFrame) return;
    _reportedFirstFrame = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(workspaceViewModelProvider).asData?.value.workspace;
      if (current == null || current.sealed ||
          current.selectionGeneration != frozen.selectionGeneration ||
          current.selection != frozen.selection) return;
      final id = frozen.selection.threadId;
      if (id != null && frozen.selection.needsOpen) {
        unawaited(ref.read(workspaceViewModelProvider.notifier).openSelectedThread(id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final watched = ref.watch(workspaceViewModelProvider);
    final sidebar = ref.watch(sidebarViewModelProvider).asData?.value;
    final vm = ref.read(workspaceViewModelProvider.notifier);
    final sidebarVM = ref.read(sidebarViewModelProvider.notifier);
    ref.listen(workspaceViewModelProvider, (previous, next) {
      final intent = next.asData?.value.navigation;
      if (intent == null || previous?.asData?.value.navigation?.serial == intent.serial) return;
      widget.onNavigate(intent);
    });
    return watched.when(
      loading: () => const StudioWorkspaceLoading(),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return Center(child: WorkspaceFailureNotice(failure: error,
          onRetry: () => ref.invalidate(workspaceViewModelProvider)));
      },
      data: (value) {
        _afterFirstFrame(value.workspace);
        final selection = value.workspace.selection;
        final threadId = selection.threadId;
        final projectId = selection.projectId;
        final activationFailure = value.activationFailure;
        final general = sidebar == null ? null : presentReadValue(sidebar.configuration.general);
        // Lookup can fail before an entity ref/value exists even while the
        // canonical source is ready. Keep its error alongside source/read
        // failures, never replacing either with a healthy empty selection.
        final metadataErrors = <StudioFailure>{
          if (value.selectedMetadata?.projection.sync.error case final error?) error,
          if (value.selectedMetadata?.value case FailedReadValue(:final error)) error,
          if (value.selectedMetadata?.readError case final error?) error,
          if (value.metadataDemandError case final error?) error,
        };
        void retryMetadata() {
          if (!mounted || !identical(ref.read(workspaceViewModelProvider.notifier), vm)) return;
          final current = ref.read(workspaceViewModelProvider).asData?.value;
          if (current == null || current.workspace.sealed ||
              current.workspace.selectionGeneration != value.workspace.selectionGeneration ||
              current.workspace.selection != selection ||
              !identical(current.selectedMetadata, value.selectedMetadata) ||
              value.selectedMetadata == null && !identical(current, value)) return;
          // The VM captures its original metadata borrow before retry's await;
          // an obsolete notice cannot redirect that retry to a new selection.
          unawaited(vm.retrySelectedMetadata());
        }
        return WorkspaceLayoutView(
          sidebar: SidebarConnector(onAddProject: widget.onAddProject),
          header: WorkspaceHeaderConnector(workspace: value),
          canonicalSidebarWidth: general?.sidebarWidth,
          widthDraft: sidebar?.widthDraft,
          onResizeWidth: sidebarVM.resizeWidth,
          onResetWidth: () => sidebarVM.changeWidth(336),
          onCommitWidth: sidebarVM.commitWidth,
          onCancelWidth: sidebarVM.cancelWidth,
          banners: Column(mainAxisSize: MainAxisSize.min, children: [
            if (value.projectReadError case final error?)
              WorkspaceFailureNotice(failure: error, onRetry: () => unawaited(vm.loadSelectedProject())),
            for (final error in metadataErrors)
              WorkspaceFailureNotice(failure: error,
                onRetry: value.workspace.sealed || threadId == null
                    ? null : retryMetadata),
            if (value.opening) const LinearProgressIndicator(minHeight: 2),
            if (value.openAdmissionError case final error?) WorkspaceFailureNotice(failure: error),
            if (value.openResult case final result?)
              WorkspaceOpenResultView(result: result, onDismiss: vm.dismissOpenResult),
            const PersistencePanelConnector(),
            const StartupRecoveryBannerConnector(),
            const ApplicationRecoveryBannerConnector(),
            const RecoveryCheckStatusConnector(),
            if (threadId != null && selection.needsOpen) UnopenedThreadView(
              threadId: threadId,
              onOpen: value.workspace.sealed || value.actions['open-thread:$threadId']?.waiting == true
                  ? null : () => unawaited(vm.openSelectedThread(threadId))),
          ]),
          content: activationFailure != null ? WorkspaceActivationFailureView(
            failure: activationFailure.error,
            onRetry: value.workspace.sealed || !activationFailure.error.retryable ? null : () {
              try {
                vm.retryActivation(activationFailure);
              } on StudioFailure catch (error) {
                // A stale retry is a rejected action, not a replacement for
                // D1's activation-failure evidence or the current selection.
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: WorkspaceFailureNotice(failure: error)));
              }
            }) : threadId != null
              ? ConversationScreen(key: ValueKey(('conversation', threadId)), threadId: threadId)
              : WorkspaceStartView(hasProject: projectId != null,
                  projectName: value.selectedProject?.name,
                  onAddProject: widget.onAddProject,
                  composer: projectId == null ? null : ComposerConnector(
                    key: ValueKey(('start-composer', projectId)), target: ComposerKey.start(projectId: projectId))),
        );
      },
    );
  }
}
