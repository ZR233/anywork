import 'package:material_ui/material_ui.dart';

import '../views/acp_workspace_view.dart';
import 'acp_composer_connector.dart';
import 'acp_permission_connector.dart';
import 'acp_status_bar_connector.dart';
import 'acp_timeline_connector.dart';

/// Top-level ACP conversation workspace connector mounted by `AgentWorkspacePane`.
class AcpWorkspaceConnector extends StatelessWidget {
  const AcpWorkspaceConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight && constraints.maxHeight < 600;
        return AcpWorkspaceView(
          readingArea: AcpTimelineConnector(threadId: threadId),
          permissionDock: AcpPermissionConnector(threadId: threadId),
          composer: AcpComposerConnector(threadId: threadId, compact: compact),
          statusBar: AcpStatusBarConnector(threadId: threadId),
        );
      },
    );
  }
}
