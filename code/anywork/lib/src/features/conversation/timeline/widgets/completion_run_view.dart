import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../state/completion_run_presentation.dart';
import 'timeline_activity_row.dart';

/// The folded header reads only the representative's explicit class and
/// ordinal. No body or aggregate facts are read to render a one-member Run.
class CompletionRunView extends StatefulWidget {
  const CompletionRunView({
    required this.id,
    required this.presentation,
    required this.childBuilder,
    required this.initiallyExpanded,
    this.onExpandedChanged,
    super.key,
  });
  final String id;
  final CompletionRunPresentation presentation;
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
    final entry = widget.presentation.representative;
    final label = entry.mainPresentation == MainPresentation.backgroundResults
        ? context.l10n.timelineBackgroundResults
        : context.l10n.timelineGroupRecord;
    final count = context.l10n.timelineGroupMemberCount(entry.run!.ordinal);
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
                child: Builder(builder: widget.childBuilder),
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
