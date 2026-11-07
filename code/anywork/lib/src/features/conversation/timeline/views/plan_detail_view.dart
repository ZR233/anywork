import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import 'plan_document_theme.dart';

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
  final Widget? body;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      key: StudioDriverKeys.planDetailsTitle,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
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
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: context.l10n.modelDetailClose,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _PlanStatus(status: widget.status),
            ),
          ],
        ),
      );
      final body = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.all(constraints.maxWidth < 520 ? 20 : 24),
              child: widget.body == null
                  ? const _PlanEmptyBody()
                  : PlanDocumentTheme(child: widget.body!),
            ),
          ),
        ),
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

class _PlanStatus extends StatelessWidget {
  const _PlanStatus({required this.status});
  final PlanDetailStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, tone, copy) = switch (status) {
      PlanDetailStatus.drafting => (
        Icons.edit_outlined,
        StudioTone.neutral,
        l10n.planDetailDraftingHelp,
      ),
      PlanDetailStatus.awaitingConfirmation => (
        Icons.schedule,
        StudioTone.warning,
        l10n.planDetailAwaitingHelp,
      ),
      PlanDetailStatus.revisionRequested => (
        Icons.edit_outlined,
        StudioTone.brand,
        l10n.planDetailRevisionHelp,
      ),
      PlanDetailStatus.approved => (
        Icons.check,
        StudioTone.success,
        l10n.planDetailApprovedHelp,
      ),
    };
    final foreground = tone.foreground(context);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DecoratedBox(
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
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          copy,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PlanEmptyBody extends StatelessWidget {
  const _PlanEmptyBody();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.description_outlined,
          size: 32,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.planDetailEmptyTitle,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.planDetailEmptyHelp,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
