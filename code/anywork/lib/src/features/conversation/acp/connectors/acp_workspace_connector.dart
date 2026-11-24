import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../shared/studio_child_readonly_panel.dart';
import '../../../status/workflow_graph_panel.dart';
import '../view_models/acp_session_view_model.dart';
import '../views/acp_workspace_view.dart';
import 'acp_composer_connector.dart';
import 'acp_permission_connector.dart';
import 'acp_status_bar_connector.dart';
import 'acp_timeline_connector.dart';

/// Top-level ACP conversation workspace connector mounted by `AgentWorkspacePane`.
class AcpWorkspaceConnector extends ConsumerStatefulWidget {
  const AcpWorkspaceConnector({super.key, required this.threadId});

  final String threadId;

  @override
  ConsumerState<AcpWorkspaceConnector> createState() =>
      _AcpWorkspaceConnectorState();
}

class _AcpWorkspaceConnectorState extends ConsumerState<AcpWorkspaceConnector> {
  static const double _minimumTimelineWidth = 560.0;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<String, bool> _workflowExpandedByThread = {};

  @override
  Widget build(BuildContext context) {
    final threadId = widget.threadId;
    final child = ref.watch(acpChildReadOnlyViewModelProvider(threadId));
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight && constraints.maxHeight < 600;
        final inDrawer =
            constraints.maxWidth <
            AcpWorkspaceView.sidePanelWidth + _minimumTimelineWidth;
        final expanded = _workflowExpandedByThread[threadId] ?? false;

        void toggleWorkflow() {
          if (inDrawer) {
            _scaffoldKey.currentState?.openEndDrawer();
          } else {
            setState(() => _workflowExpandedByThread[threadId] = !expanded);
          }
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: context.colors.surface,
          endDrawerEnableOpenDragGesture: false,
          endDrawer: inDrawer
              ? Drawer(
                  width: AcpWorkspaceView.sidePanelWidth,
                  backgroundColor: context.colors.surfaceContainer,
                  child: AcpWorkflowGraphPanelConnector(
                    threadId: threadId,
                    inDrawer: true,
                    onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
                  ),
                )
              : null,
          body: AcpWorkspaceView(
            readingArea: AcpTimelineConnector(threadId: threadId),
            permissionDock: AcpPermissionConnector(threadId: threadId),
            composer: switch (child) {
              true => const StudioChildReadOnlyPanel(),
              false => AcpComposerConnector(
                threadId: threadId,
                compact: compact,
              ),
              null => const SizedBox.shrink(),
            },
            statusBar: AcpStatusBarConnector(
              threadId: threadId,
              workflowExpanded: !inDrawer && expanded,
              onToggleWorkflow: toggleWorkflow,
            ),
            sidePanel: !inDrawer && expanded
                ? AcpWorkflowGraphPanelConnector(
                    threadId: threadId,
                    onClose: () => setState(
                      () => _workflowExpandedByThread[threadId] = false,
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}
