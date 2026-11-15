import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../shared/studio_child_readonly_panel.dart';
import '../view_models/acp_session_view_model.dart';
import '../views/acp_workspace_view.dart';
import 'acp_composer_connector.dart';
import 'acp_permission_connector.dart';
import 'acp_status_bar_connector.dart';
import 'acp_timeline_connector.dart';

/// Top-level ACP conversation workspace connector mounted by `AgentWorkspacePane`.
class AcpWorkspaceConnector extends ConsumerWidget {
  const AcpWorkspaceConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(acpChildReadOnlyViewModelProvider(threadId));
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight && constraints.maxHeight < 600;
        return AcpWorkspaceView(
          readingArea: AcpTimelineConnector(threadId: threadId),
          permissionDock: AcpPermissionConnector(threadId: threadId),
          composer: switch (child) {
            true => const StudioChildReadOnlyPanel(),
            false => AcpComposerConnector(threadId: threadId, compact: compact),
            null => const SizedBox.shrink(),
          },
          statusBar: AcpStatusBarConnector(threadId: threadId),
        );
      },
    );
  }
}
