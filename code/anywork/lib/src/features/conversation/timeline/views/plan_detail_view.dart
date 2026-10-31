import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';

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
  const PlanDetailView({
    super.key,
    required this.identity,
    required this.title,
    required this.body,
    required this.status,
    required this.onClose,
    this.onToggleReadingMode,
    this.fullWidth = false,
  });
  final String identity;
  final String title;
  final Widget body;
  final PlanDetailStatus status;
  final VoidCallback onClose;
  final VoidCallback? onToggleReadingMode;
  final bool fullWidth;
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
  Widget build(BuildContext context) => LayoutBuilder(
    key: StudioDriverKeys.planDetails,
    builder: (context, constraints) {
      final header = SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      key: StudioDriverKeys.planDetailsTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      planDetailStatusLabel(context, widget.status),
                      key: StudioDriverKeys.planDetailsStatus,
                    ),
                  ],
                ),
              ),
              if (widget.onToggleReadingMode != null) ...[
                IconButton(
                  key: StudioDriverKeys.planDetailsReadingMode,
                  visualDensity: VisualDensity.standard,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  tooltip: widget.fullWidth
                      ? context.l10n.planRestoreSplit
                      : context.l10n.planExpandReading,
                  onPressed: widget.onToggleReadingMode,
                  icon: Icon(
                    widget.fullWidth
                        ? Icons.vertical_split_outlined
                        : Icons.open_in_full,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                key: StudioDriverKeys.planDetailsClose,
                visualDensity: VisualDensity.standard,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: context.l10n.modelDetailClose,
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      );
      final body = Padding(
        padding: const EdgeInsets.all(18),
        child: widget.body,
      );
      Widget scroll(Widget child) => Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          key: StudioDriverKeys.planDetailsScroll,
          controller: _scroll,
          primary: false,
          child: child,
        ),
      );
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: SelectionArea(
          child: constraints.maxHeight < 260
              ? scroll(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [header, const Divider(height: 1), body],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const Divider(height: 1),
                    Expanded(child: scroll(body)),
                  ],
                ),
        ),
      );
    },
  );
}
