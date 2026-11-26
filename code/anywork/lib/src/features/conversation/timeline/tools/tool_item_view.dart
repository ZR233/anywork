import 'package:anywork_client/models.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/timeline_display_unit.dart';
import '../state/tool_presentation.dart';
import '../widgets/timeline_activity_row.dart';
import '../widgets/timeline_content_range_view.dart'
    show TimelineBodyReadQualification;
import 'support/tool_detail_panel.dart';
import 'support/tool_detail_values.dart';
import 'support/tool_status_labels.dart';
import 'tool_item_adapter.dart';
import 'tool_item_registry.dart';

/// Resolves the canonical localized title for [item].
String timelineToolTitle(
  BuildContext context,
  TimelineToolPresentation item, {
  TimelineToolItemRegistry? registry,
  ToolAcceptanceProjection? acceptance,
}) {
  final activeRegistry = registry ?? timelineToolItemRegistry;
  final adapter = activeRegistry.resolveForPresentation(item);
  return adapter.title(context.l10n, item, acceptance: acceptance);
}

/// Builds inline semantic body widget for [item] when no declared content
/// windows are present.
Widget? timelineToolInlineBody(
  BuildContext context,
  TimelineToolPresentation item, {
  TimelineToolMarkdownBuilder? markdownBuilder,
  ToolAcceptanceProjection? acceptance,
  TimelineToolItemRegistry? registry,
}) {
  final activeRegistry = registry ?? timelineToolItemRegistry;
  final adapter = activeRegistry.resolveForPresentation(item);
  final controller = adapter.createController(item);
  try {
    final toolContext = TimelineToolItemContext(
      buildContext: context,
      l10n: context.l10n,
      item: item,
      controller: controller,
      markdownBuilder: markdownBuilder,
      staticObservation: item.frozenObservation,
    );
    return adapter.buildInlineBody(toolContext, acceptance: acceptance);
  } finally {
    controller.dispose();
  }
}

/// Builds body widget for an on-demand declared content window ([windowText]).
Widget timelineToolWindowBody(
  BuildContext context,
  TimelineToolPresentation item,
  String windowText, {
  required bool input,
  TimelineToolMarkdownBuilder? markdownBuilder,
  ToolAcceptanceProjection? acceptance,
  TimelineToolItemRegistry? registry,
}) {
  final activeRegistry = registry ?? timelineToolItemRegistry;
  final adapter = activeRegistry.resolveForPresentation(item);
  final controller = adapter.createController(item);
  try {
    final toolContext = TimelineToolItemContext(
      buildContext: context,
      l10n: context.l10n,
      item: item,
      controller: controller,
      markdownBuilder: markdownBuilder,
      staticObservation: item.frozenObservation,
    );
    return adapter.buildWindowBody(
      toolContext,
      windowText,
      isInput: input,
      acceptance: acceptance,
    );
  } finally {
    controller.dispose();
  }
}

/// Unified interactive timeline row and disclosure view for all tool calls,
/// including waits, patches, LSP queries, and stateful dynamic-icon tools.
class TimelineToolItemView extends StatefulWidget {
  const TimelineToolItemView({
    required this.item,
    this.registry,
    this.initiallyExpanded = false,
    this.staticObservation,
    this.workGroupMember = false,
    this.onExpansionChanged,
    this.markdownBuilder,
    this.additionalContentBuilder,
    this.declaredContentIdentity,
    this.declaredContentBuilder,
    super.key,
  }) : assert(
         declaredContentBuilder == null || declaredContentIdentity != null,
       );

  final TimelineToolPresentation item;
  final TimelineToolItemRegistry? registry;
  final bool initiallyExpanded;
  final bool? staticObservation;
  final bool workGroupMember;
  final ValueChanged<bool>? onExpansionChanged;
  final TimelineToolMarkdownBuilder? markdownBuilder;
  final WidgetBuilder? additionalContentBuilder;
  final Object? declaredContentIdentity;
  final List<Widget> Function(
    ValueChanged<BodyWindow> onOutputRead,
    ToolAcceptanceProjection? acceptance,
  )?
  declaredContentBuilder;

  @override
  State<TimelineToolItemView> createState() => _TimelineToolItemViewState();
}

class _TimelineToolItemViewState extends State<TimelineToolItemView> {
  late TimelineToolItemAdapter _adapter;
  late TimelineToolItemController _controller;
  TimelineExpansionIntent? _group;
  Object? _groupGeneration;

  TimelineToolItemRegistry get _registry =>
      widget.registry ?? timelineToolItemRegistry;

  bool get _isStaticObservation =>
      widget.staticObservation ?? widget.item.frozenObservation;

  @override
  void initState() {
    super.initState();
    _adapter = _registry.resolveForPresentation(widget.item);
    _controller = _adapter.createController(widget.item);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group = TimelineGroupBodyIntent.of(context);
    if (!identical(group, _group)) {
      _group?.removeListener(_groupChanged);
      _group = group;
      _groupGeneration = group?.bodyGeneration;
      group?.addListener(_groupChanged);
      _controller.retireTransientState(notify: false);
    }
  }

  @override
  void didUpdateWidget(TimelineToolItemView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextAdapter = _registry.resolveForPresentation(widget.item);
    if (nextAdapter.id != _adapter.id) {
      _controller.dispose();
      _adapter = nextAdapter;
      _controller = _adapter.createController(widget.item);
      return;
    }
    _controller.updateItem(widget.item);
    if (widget.item.id != oldWidget.item.id ||
        widget.item.toolCallId != oldWidget.item.toolCallId ||
        widget.item.presentationContract !=
            oldWidget.item.presentationContract ||
        widget.item.statusString != oldWidget.item.statusString ||
        widget.item.output != oldWidget.item.output ||
        widget.declaredContentIdentity != oldWidget.declaredContentIdentity ||
        (widget.declaredContentBuilder == null) !=
            (oldWidget.declaredContentBuilder == null)) {
      _controller.retireTransientState(notify: false);
    }
  }

  void _groupChanged() {
    if (identical(_groupGeneration, _group?.bodyGeneration) &&
        _group?.bodyActive == true) {
      return;
    }
    _groupGeneration = _group?.bodyGeneration;
    _controller.retireTransientState(notify: false);
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _group?.removeListener(_groupChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TimelineToolItemScope(
      controller: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final l10n = context.l10n;
          final item = widget.item;
          final epoch = _controller.callbackEpoch;
          final acceptance = _controller.acceptance;
          final toolContext = TimelineToolItemContext(
            buildContext: context,
            l10n: l10n,
            item: item,
            controller: _controller,
            markdownBuilder: widget.markdownBuilder,
            additionalContentBuilder: widget.additionalContentBuilder,
            staticObservation: _isStaticObservation,
          );
          final summary = _adapter.buildRowSummary(toolContext);
          final effectiveIcon = _controller.iconOverride ?? summary.icon;

          final declaredContents = widget.declaredContentBuilder?.call((
            window,
          ) {
            if (!mounted) return;
            _controller.notifyOutputWindowRead(epoch, window, group: _group);
          }, acceptance);

          final diagnostics = toolDiagnostics(context, item);
          final outputUnavailable =
              item.error?.trim().isNotEmpty == true &&
              item.error!.trim() == item.output.trim() &&
              _adapter.bodyPolicy.readsStructuredOutput &&
              _adapter
                  .decodeOutput(l10n, item.output)
                  .any((value) => value is ToolDetailUnavailable);
          final inputValues = _adapter.decodeInput(l10n, item.arguments);
          final artifactValues = [
            for (final artifact in item.outputArtifacts)
              ..._adapter.decodeArtifacts(l10n, artifact),
          ];
          final inlineBody = declaredContents == null
              ? _adapter.buildInlineBody(toolContext, acceptance: acceptance)
              : null;

          final panelChildren = <Widget>[
            if (declaredContents == null)
              ?inlineBody
            else ...[
              if (_adapter.showsDeclaredPrefixInput && inputValues.isNotEmpty)
                TimelineToolSemanticBody(values: inputValues),
              if (_adapter.bodyPolicy.readsArgumentsWindow ||
                  _adapter.readsOutput(item.statusString, output: item.output))
                ...declaredContents,
            ],
            if (artifactValues.isNotEmpty)
              TimelineToolSemanticBody(values: artifactValues),
            if (diagnostics.isNotEmpty)
              Text(
                diagnostics.join('\n'),
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            if (item.error case final error?
                when error.trim().isNotEmpty &&
                    (error.trim() != item.output.trim() ||
                        outputUnavailable ||
                        !_adapter.readsOutput(
                          item.statusString,
                          output: item.output,
                        )))
              Text(
                error,
                style: context.text.bodySmall?.copyWith(
                  color: toolDiagnosticColor(context, item),
                ),
              ),
            if (widget.additionalContentBuilder != null)
              Builder(builder: widget.additionalContentBuilder!),
          ];

          final standardPanel = panelChildren.isEmpty
              ? null
              : TimelineBodyReadQualification(
                  value: epoch,
                  child: TimelineToolDetailPanel(children: panelChildren),
                );

          final expandedChildren = _adapter.buildExpandedChildren(
            toolContext,
            TimelineToolExpandedSlots(
              declaredContents: declaredContents,
              standardPanel: standardPanel,
            ),
          );
          final expandable = expandedChildren.isNotEmpty;

          Widget body = TimelineActivityTileTheme(
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: TimelineActivityDisclosure(
                key: summary.disclosureKey,
                initiallyExpanded: widget.initiallyExpanded,
                onExpansionChanged: widget.onExpansionChanged,
                enabled: expandable,
                titleBuilder: (context, expanded) => _buildRow(
                  context,
                  summary,
                  effectiveIcon,
                  expanded,
                  expandable: expandable,
                ),
                children: expandedChildren,
              ),
            ),
          );

          if (summary.cardKey case final key?) {
            body = KeyedSubtree(key: key, child: body);
          }

          if (summary.semanticsLabel case final semantics?) {
            body = Semantics(container: true, label: semantics, child: body);
          }

          return body;
        },
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    TimelineToolRowSummary summary,
    TimelineToolIcon effectiveIcon,
    bool expanded, {
    required bool expandable,
  }) {
    final active = summary.active && !_isStaticObservation;
    switch (effectiveIcon) {
      case TimelineToolIconWidget(:final builder, :final fallbackIcon):
        final iconState = TimelineToolRowIconState(
          active: active,
          expanded: expanded,
          isIssue: summary.isIssue,
          isStopped: summary.isStopped,
          staticObservation: _isStaticObservation,
          statusString: widget.item.statusString,
        );
        return TimelineActivityRow(
          icon: fallbackIcon,
          leading: Builder(builder: (ctx) => builder(ctx, iconState)),
          label: summary.label,
          active: active,
          isIssue: summary.isIssue,
          expanded: expanded,
          expandable: expandable,
          tooltip: summary.tooltip,
          meta: summary.meta,
        );
      case TimelineToolIconData(
        :final icon,
        :final color,
        :final activeIndicatorStyle,
        :final idleIndicatorStyle,
        :final preserveWhenStopped,
        :final preserveWhenIssue,
      ):
        final resolvedIcon = summary.isStopped && !preserveWhenStopped
            ? Icons.stop_circle_outlined
            : icon;
        final rowIsIssue = summary.isIssue && !preserveWhenIssue;
        final inWorkGroup =
            widget.workGroupMember || _group?.current?.body is WorkDisplayBlock;
        final runningStyle =
            inWorkGroup &&
                activeIndicatorStyle ==
                    TimelineActivityIndicatorStyle.restingCat
            ? TimelineActivityIndicatorStyle.circularProgress
            : activeIndicatorStyle;
        return TimelineActivityRow(
          icon: resolvedIcon,
          iconColor: color,
          label: summary.label,
          active: active,
          indicatorStyle: active ? runningStyle : idleIndicatorStyle,
          isIssue: rowIsIssue,
          expanded: expanded,
          expandable: expandable,
          tooltip: summary.tooltip,
          meta: summary.meta,
        );
    }
  }
}
