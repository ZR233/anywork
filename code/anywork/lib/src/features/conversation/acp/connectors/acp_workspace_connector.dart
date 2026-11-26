import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_child_readonly_panel.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../status/connectors/workflow_graph_connectors.dart';
import '../../timeline/connectors/file_reading_panel.dart';
import '../../timeline/connectors/plan_detail_connector.dart';
import '../../workspace/conversation_workspace.dart';
import '../view_models/acp_plan_card_view_model.dart';
import '../view_models/acp_session_view_model.dart';
import '../views/acp_workspace_view.dart';
import 'acp_composer_connector.dart';
import 'acp_host_interaction_connector.dart';
import 'acp_permission_connector.dart';
import 'acp_plan_card_connector.dart';
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
  final Map<String, ConversationSidebarState<FileReadingRequest>>
  _sidebarByThread = {};
  double? _sidebarCustomWidth;

  @override
  void didUpdateWidget(covariant AcpWorkspaceConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.threadId != oldWidget.threadId) {
      _sidebarByThread[oldWidget.threadId]?.closeFile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final threadId = widget.threadId;
    final child = ref.watch(acpChildReadOnlyViewModelProvider(threadId));
    final workflowState = ref.watch(
      acpConversationStateProvider(threadId)
          .select((value) => value.value?.workflowState),
    );
    final acpPlan = ref.watch(acpPlanCardViewModelProvider(threadId));

    final hostPlan = workflowState?.plan;
    final hasHostPlan =
        hostPlan != null &&
        (hostPlan.revision > 0 || hostPlan.document != null);
    final planIdentity = hasHostPlan
        ? 'acp-plan:${hostPlan.revision}:${hostPlan.document?.contentHash ?? ''}'
        : null;

    final sidebar = _sidebarByThread.putIfAbsent(
      threadId,
      ConversationSidebarState<FileReadingRequest>.new,
    );
    sidebar.observePlan(identity: planIdentity, pending: false);

    final hasSteps = acpPlan != null && acpPlan.entries.isNotEmpty;
    final l10n = context.l10n;
    final entries = <ConversationSidebarPanelEntry>[
      if (workflowState != null)
        ConversationSidebarPanelEntry(
          kind: ConversationSidebarPanelKind.workflow,
          icon: Icons.account_tree_outlined,
          label: l10n.rightSidebarTabWorkflow,
          tooltip: l10n.workflowGraphPanelTitle,
          defaultWidthBuilder: (w) => (w * 0.36).clamp(360.0, 440.0),
          builder: (_) => AcpWorkflowGraphPanelConnector(threadId: threadId),
        ),
      if (hasHostPlan)
        ConversationSidebarPanelEntry(
          kind: ConversationSidebarPanelKind.plan,
          icon: Icons.description_outlined,
          label: l10n.rightSidebarTabPlan,
          tooltip: l10n.interactionPlanDetailsTitle,
          badge: PlanDetailStatusBadge(
            status: planDetailStatusFromRuntime(hostPlan.state),
          ),
          defaultLayoutMode: ConversationSidebarLayoutMode.split,
          expandedDockBehavior: ConversationExpandedDockBehavior.coverAll,
          defaultWidthBuilder: (w) => (w * 0.48).clamp(360.0, 620.0),
          builder: (_) => AcpPlanDetailConnector(
            threadId: threadId,
            identity: planIdentity!,
          ),
        ),
      if (sidebar.file case final file?)
        ConversationSidebarPanelEntry(
          kind: ConversationSidebarPanelKind.file,
          icon: Icons.article_outlined,
          label: file.filename,
          tooltip: file.filename,
          onDismiss: () {
            final remaining = [
              if (workflowState != null) ConversationSidebarPanelKind.workflow,
              if (hasHostPlan) ConversationSidebarPanelKind.plan,
              if (hasSteps) ConversationSidebarPanelKind.todo,
            ];
            setState(() => sidebar.closeFile(remainingAvailable: remaining));
          },
          defaultWidthBuilder: (w) => (w * 0.48).clamp(360.0, 620.0),
          builder: (_) => FileReadingPanel(request: file),
        ),
      if (hasSteps)
        ConversationSidebarPanelEntry(
          kind: ConversationSidebarPanelKind.todo,
          icon: Icons.checklist_outlined,
          label: l10n.rightSidebarTabSteps,
          tooltip: l10n.acpPlanTitle,
          badge: StudioPill(
            label: '${acpPlan.completedCount}/${acpPlan.entries.length}',
            tone: acpPlan.completedCount == acpPlan.entries.length
                ? StudioTone.success
                : StudioTone.brand,
          ),
          defaultWidthBuilder: (w) => (w * 0.34).clamp(340.0, 420.0),
          builder: (_) => AcpPlanCardConnector(threadId: threadId),
        ),
    ];
    sidebar.reconcileAvailable({for (final entry in entries) entry.kind});

    final activeEntry = sidebar.isOpen && entries.isNotEmpty
        ? entries.firstWhere(
            (entry) => entry.kind == sidebar.activeKind,
            orElse: () => entries.first,
          )
        : null;
    final activeLayoutMode = activeEntry == null
        ? ConversationSidebarLayoutMode.split
        : sidebar.layoutModeFor(
            activeEntry.kind,
            defaultMode: activeEntry.defaultLayoutMode,
          );
    final availableOrder = [for (final entry in entries) entry.kind];

    return ColoredBox(
      color: context.colors.surface,
      child: AcpWorkspaceView(
        readingArea: FileReadingScope(
          onOpen: (request) {
            if (!request.isActive()) return;
            setState(() {
              sidebar.openFile(
                FileReadingRequest(
                  identity: request.identity,
                  filename: request.filename,
                  readBytes: request.readBytes,
                  isActive: () =>
                      mounted &&
                      widget.threadId == threadId &&
                      request.isActive(),
                ),
              );
            });
          },
          child: AcpTimelineConnector(threadId: threadId),
        ),
        permissionDock: AcpPermissionConnector(threadId: threadId),
        hostInteractionDock: AcpHostInteractionConnector(
          threadId: threadId,
          onReadPlan: () => setState(
            () => sidebar.openPanel(ConversationSidebarPanelKind.plan),
          ),
        ),
        composerBuilder: (context, compact) => switch (child) {
          true => const StudioChildReadOnlyPanel(),
          false => AcpComposerConnector(threadId: threadId, compact: compact),
          null => const SizedBox.shrink(),
        },
        sidebarBuilder: activeEntry == null
            ? null
            : (context, presentation) => ConversationRightSidebar(
                entries: entries,
                activeKind: activeEntry.kind,
                presentation: presentation,
                onSelectKind: (kind) {
                  final target = entries.firstWhere(
                    (entry) => entry.kind == kind,
                  );
                  setState(
                    () => sidebar.openPanel(
                      kind,
                      defaultMode: target.defaultLayoutMode,
                    ),
                  );
                },
                onToggleLayoutMode: () => setState(
                  () => sidebar.toggleLayoutMode(
                    activeEntry.kind,
                    defaultMode: activeEntry.defaultLayoutMode,
                  ),
                ),
                onCollapse: () => setState(sidebar.collapse),
              ),
        sidebarExpanded:
            activeEntry != null &&
            activeLayoutMode == ConversationSidebarLayoutMode.expanded,
        expandedDockBehavior:
            activeEntry?.expandedDockBehavior ??
            ConversationExpandedDockBehavior.coverAll,
        sidebarCustomWidth: _sidebarCustomWidth,
        sidebarDefaultWidthBuilder: activeEntry?.defaultWidthBuilder,
        onSidebarWidthChanged: (width) => _sidebarCustomWidth = width,
        onCollapseSidebar: () => setState(sidebar.collapse),
        statusBar: AcpStatusBarConnector(
          threadId: threadId,
          workflowExpanded: sidebar.isPanelOpen(
            ConversationSidebarPanelKind.workflow,
          ),
          onToggleWorkflow: workflowState == null
              ? null
              : () => setState(
                  () => sidebar.togglePanel(
                    ConversationSidebarPanelKind.workflow,
                  ),
                ),
          showPlanEntry: hasHostPlan,
          planExpanded: sidebar.isPanelOpen(ConversationSidebarPanelKind.plan),
          onTogglePlan: !hasHostPlan
              ? null
              : () => setState(
                  () => sidebar.togglePanel(
                    ConversationSidebarPanelKind.plan,
                    defaultMode: ConversationSidebarLayoutMode.split,
                  ),
                ),
          stepsExpanded: sidebar.isPanelOpen(ConversationSidebarPanelKind.todo),
          onToggleSteps: !hasSteps
              ? null
              : () => setState(
                  () => sidebar.togglePanel(ConversationSidebarPanelKind.todo),
                ),
          hasSidebarPanels: entries.isNotEmpty,
          sidebarOpen: sidebar.isOpen,
          onToggleSidebar: entries.isEmpty
              ? null
              : () => setState(
                  () => sidebar.toggleSidebar(availableOrder: availableOrder),
                ),
        ),
      ),
    );
  }
}
