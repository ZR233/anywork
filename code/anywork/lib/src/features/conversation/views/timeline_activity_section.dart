import 'package:flutter/material.dart';

import '../widgets/activity_row.dart';

/// Controlled UI expansion. The caller owns the one expansion intent; this
/// controller only reconciles Flutter's actual expansion animation to it.
class TimelineActivitySection extends StatefulWidget {
  const TimelineActivitySection({
    required this.label,
    required this.icon,
    required this.expanded,
    required this.onExpanded,
    required this.child,
    this.active = false,
    this.isIssue = false,
    this.tooltip,
    this.labelKey,
    this.indent = true,
    super.key,
  });
  final String label;
  final IconData icon;
  final bool expanded;
  final bool active;
  final bool isIssue;
  final String? tooltip;
  final Key? labelKey;
  final bool indent;
  final ValueChanged<bool> onExpanded;
  final Widget child;
  @override
  State<TimelineActivitySection> createState() =>
      _TimelineActivitySectionState();
}

class _TimelineActivitySectionState extends State<TimelineActivitySection> {
  final ExpansibleController _controller = ExpansibleController();
  @override
  void didUpdateWidget(covariant TimelineActivitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != _controller.isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.expanded == _controller.isExpanded) return;
        if (widget.expanded) {
          _controller.expand();
        } else {
          _controller.collapse();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TimelineActivityTileTheme(
    child: ExpansionTile(
      controller: _controller,
      initiallyExpanded: widget.expanded,
      onExpansionChanged: widget.onExpanded,
      maintainState: false,
      showTrailingIcon: false,
      minTileHeight: 28,
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.only(
        left: widget.indent ? TimelineActivityRow.contentIndent : 0,
        bottom: 6,
      ),
      shape: const Border(),
      collapsedShape: const Border(),
      title: TimelineActivityRow(
        key: widget.labelKey,
        icon: widget.icon,
        label: widget.label,
        active: widget.active,
        isIssue: widget.isIssue,
        expanded: widget.expanded,
        tooltip: widget.tooltip,
      ),
      children: [widget.child],
    ),
  );
}
