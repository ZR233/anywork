import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../presentation/plan_labels.dart';
import 'plan_panel_props.dart';

/// Unified minimum visual box of the Plan header action group.
///
/// The action group keeps the standard density and standard tap target so a
/// desktop `ThemeData` plus a compact app theme cannot shrink it to 32: visual
/// 40, layout box 48 (design/13-plan.md §13.5).
const double _planHeaderActionSize = 40;
const VisualDensity _planHeaderVisualDensity = VisualDensity.standard;
const MaterialTapTargetSize _planHeaderTapTargetSize =
    MaterialTapTargetSize.padded;

/// Header right inset: the action group ends exactly on this content edge.
const double _planHeaderContentInset = 8;

/// Fixed header + independently scrolling body need at least this height.
/// Below it the whole panel degrades to one scroll container instead of
/// overflowing (design/19 §19.10 short viewports).
const double _minimumPinnedHeight = 260;

/// The one Plan reading panel: a quiet, independently scrolling document view.
///
/// No feedback/approve/revise callbacks: those belong to Interaction
/// exclusively. Reading mode switches side-by-side/full-width geometry and close
/// hides the panel; neither closes the Session, clears a draft, or cancels an
/// accepted command. Both are GUI-only placement of the same published document.
class PlanView extends StatefulWidget {
  const PlanView({required this.props, super.key});
  final PlanPanelProps props;

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.props.state;
    final plan = state.plan;
    if (plan == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final document = state.document;
    final identity =
        '${state.threadId}:${plan.document?.version}:${plan.document?.contentHash}';
    final title = document == null
        ? context.l10n.interactionPlanDetailsTitle
        : planDocumentTitle(
            document.markdown,
            fallback: context.l10n.interactionPlanDetailsTitle,
          );
    final status = planPhaseStatusLabel(context, plan.state);
    final header = _header(context, title: title, status: status);
    final divider = Divider(height: 1, color: colors.outlineVariant);
    final body = KeyedSubtree(
      key: StudioDriverKeys.planDetailsScroll,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context)
            .copyWith(scrollbars: false, overscroll: false),
        child: RawScrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SelectionArea(
            child: ListView(
              key: PageStorageKey<String>('plan-details:$identity'),
              controller: _scrollController,
              primary: false,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
              children: [
                if (state.loading) const LinearProgressIndicator(),
                if (state.error != null)
                  Row(
                    children: [
                      Expanded(child: Text(state.error!.message)),
                      TextButton(
                        onPressed: widget.props.onRetry,
                        child: Text(context.l10n.sidebarRetry),
                      ),
                    ],
                  ),
                if (document != null)
                  KeyedSubtree(
                    key: StudioDriverKeys.planDetailsMarkdown,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: StudioLayout.conversationWidth,
                        ),
                        child: widget.props.documentBuilder(
                          context,
                          document.markdown,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Material(
      key: StudioDriverKeys.planDetails,
      color: colors.surfaceContainerLowest,
      elevation: 0,
      shape: Border(left: BorderSide(color: colors.outline)),
      child: SafeArea(
        left: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.hasBoundedHeight &&
                constraints.maxHeight < _minimumPinnedHeight) {
              return SingleChildScrollView(
                key: PageStorageKey<String>('plan-details:$identity'),
                controller: _scrollController,
                primary: false,
                padding: const EdgeInsets.only(bottom: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, divider, _inlineBody(context)],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                divider,
                Expanded(child: body),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Short-viewport fallback keeps the same reading content in one scroll view.
  Widget _inlineBody(BuildContext context) {
    final state = widget.props.state;
    final document = state.document;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.loading) const LinearProgressIndicator(),
          if (state.error != null)
            Row(
              children: [
                Expanded(child: Text(state.error!.message)),
                TextButton(
                  onPressed: widget.props.onRetry,
                  child: Text(context.l10n.sidebarRetry),
                ),
              ],
            ),
          if (document != null)
            KeyedSubtree(
              key: StudioDriverKeys.planDetailsMarkdown,
              child: widget.props.documentBuilder(context, document.markdown),
            ),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required String title,
    required String? status,
  }) {
    final colors = Theme.of(context).colorScheme;
    final fullWidth = widget.props.state.fullWidth;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, _planHeaderContentInset, 12),
      child: Row(
        // The action group stays vertically centred on the title column.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.article_outlined, size: 19, color: colors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  key: StudioDriverKeys.planDetailsTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      status,
                      key: StudioDriverKeys.planDetailsStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // The action slot fills its own share and aligns the group to the end,
          // so the last action lands on the content edge instead of stopping
          // next to the title. The bounded slot lets the variable reading label
          // ellipsize while the close action stays reachable.
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.props.sideBySideFeasible)
                  Flexible(
                    child: TextButton.icon(
                      key: StudioDriverKeys.planDetailsReadingMode,
                      icon: Icon(
                        fullWidth
                            ? Icons.vertical_split_outlined
                            : Icons.open_in_full_rounded,
                        size: 16,
                      ),
                      label: Text(
                        fullWidth
                            ? context.l10n.planRestoreSplit
                            : context.l10n.planExpandReading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, _planHeaderActionSize),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: Theme.of(context).textTheme.labelMedium,
                        visualDensity: _planHeaderVisualDensity,
                        tapTargetSize: _planHeaderTapTargetSize,
                      ),
                      onPressed: widget.props.onToggleReading,
                    ),
                  ),
                if (widget.props.sideBySideFeasible) const SizedBox(width: 4),
                IconButton(
                  key: StudioDriverKeys.planDetailsClose,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(_planHeaderActionSize),
                    padding: EdgeInsets.zero,
                    visualDensity: _planHeaderVisualDensity,
                    tapTargetSize: _planHeaderTapTargetSize,
                  ),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: widget.props.onClose,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
