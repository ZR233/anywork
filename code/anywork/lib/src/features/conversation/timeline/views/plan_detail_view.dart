import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import 'markdown_document_body.dart';

/// Dock 计划详情的展示状态。运行态来自 [PlanRuntimePhase]；历史决定
/// `cancelled`/`resolved` 只出现在时间线回执，不进入当前 dock。
enum PlanDetailStatus {
  drafting,
  awaitingConfirmation,
  revisionRequested,
  approved,
}

PlanDetailStatus planDetailStatusFromRuntime(PlanRuntimePhase phase) =>
    switch (phase) {
      PlanRuntimePhase.drafting => PlanDetailStatus.drafting,
      PlanRuntimePhase.awaitingConfirmation =>
        PlanDetailStatus.awaitingConfirmation,
      PlanRuntimePhase.revisionRequested => PlanDetailStatus.revisionRequested,
      PlanRuntimePhase.approved => PlanDetailStatus.approved,
    };

String planDetailStatusLabel(BuildContext context, PlanDetailStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    PlanDetailStatus.drafting => l10n.planDetailDrafting,
    PlanDetailStatus.awaitingConfirmation =>
      l10n.interactionPlanAwaitingConfirmation,
    PlanDetailStatus.revisionRequested => l10n.planDetailRevisionRequested,
    PlanDetailStatus.approved => l10n.interactionPlanApproved,
  };
}

class PlanDetailView extends StatefulWidget {
  const PlanDetailView({super.key, required this.identity, required this.body});

  final String identity;
  final Widget? body;

  @override
  State<PlanDetailView> createState() => _PlanDetailViewState();
}

class _PlanDetailViewState extends State<PlanDetailView> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = MarkdownDocumentBody(
      child: widget.body ?? const SizedBox.shrink(),
    );
    // Split/full layout can reparent the same panel state. A PageStorage key
    // preserves the user's reading position across that ScrollPosition swap.
    return Material(
      key: StudioDriverKeys.planDetails,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SelectionArea(
        child: KeyedSubtree(
          key: PageStorageKey<String>(
            'plan-details-scroll-storage:${widget.identity}',
          ),
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              key: StudioDriverKeys.planDetailsScroll,
              controller: _scroll,
              primary: false,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

class PlanDetailStatusBadge extends StatelessWidget {
  const PlanDetailStatusBadge({required this.status, super.key});

  final PlanDetailStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = switch (status) {
      PlanDetailStatus.drafting => (Icons.edit_outlined, StudioTone.neutral),
      PlanDetailStatus.awaitingConfirmation => (
        Icons.schedule,
        StudioTone.warning,
      ),
      PlanDetailStatus.revisionRequested => (
        Icons.edit_outlined,
        StudioTone.brand,
      ),
      PlanDetailStatus.approved => (Icons.check, StudioTone.success),
    };
    final foreground = tone.foreground(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.background(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                planDetailStatusLabel(context, status),
                key: StudioDriverKeys.planDetailsStatus,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
