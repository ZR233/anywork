import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import 'timeline_activity_row.dart';

/// One producer-defined Work header with bounded, explicitly requested members.
class CompletionRunView extends StatefulWidget {
  const CompletionRunView({
    required this.id,
    required this.summary,
    required this.childBuilder,
    required this.initiallyExpanded,
    this.onExpandedChanged,
    this.executionPresent = false,
    this.closing = false,
    super.key,
  });
  final String id;
  final WorkSummary summary;
  final bool executionPresent;
  final bool closing;
  final WidgetBuilder childBuilder;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<CompletionRunView> createState() => _CompletionRunViewState();
}

class _CompletionRunViewState extends State<CompletionRunView> {
  final ExpansibleController _disclosure = ExpansibleController();
  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) _disclosure.expand();
    _disclosure.addListener(_changed);
  }

  void _changed() {
    widget.onExpandedChanged?.call(_disclosure.isExpanded);
    setState(() {});
  }

  @override
  void dispose() {
    _disclosure.removeListener(_changed);
    _disclosure.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final label = context.l10n.timelineGroupRecord;
    final count = context.l10n.timelineGroupMemberCount(summary.total);
    final status = summary.running > 0 || summary.waiting > 0
        ? '${summary.terminal}/${summary.total}'
        : widget.executionPresent
            ? (widget.closing ? '正在收束' : '等待下一步')
            : null;
    final duration = summary.durationMs;
    return Expansible(
      controller: _disclosure,
      maintainState: false,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      headerBuilder: (context, animation) => Semantics(
        button: true,
        expanded: _disclosure.isExpanded,
        child: InkWell(
          onTap: _disclosure.toggle,
          borderRadius: BorderRadius.circular(8),
          child: TimelineActivityRow(
            key: ValueKey('completion-run-header:${widget.id}'),
            label: '$label · $count',
            active: widget.executionPresent && summary.running > 0,
            summary: summary.thinkingSummary,
            meta: [
              ?status,
              if (summary.failed > 0) '失败 ${summary.failed}',
              if (summary.cancelled > 0) '取消 ${summary.cancelled}',
              if (duration != null) '${(duration / 1000).toStringAsFixed(1)}s',
            ].join(' · '),
            header: true,
            expanded: _disclosure.isExpanded,
          ),
        ),
      ),
      bodyBuilder: (context, animation) => !_disclosure.isExpanded
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 3),
              child: TimelineActivityRail(
                inset: 3,
                contentInset: 14,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 186),
                  child: SingleChildScrollView(
                    child: Builder(builder: widget.childBuilder),
                  ),
                ),
              ),
            ),
      expansibleBuilder: (context, header, body, animation) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, body],
      ),
    );
  }
}
