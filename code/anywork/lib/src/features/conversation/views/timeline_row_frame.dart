import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';

class TimelineRowFrame extends StatelessWidget {
  const TimelineRowFrame({required this.id, required this.child, this.prompt = false,
    this.parentAgent = false, this.accepted = false, this.rolledBack = false,
    this.compact = false, this.inGroup = false, super.key});
  final String id;
  final Widget child;
  final bool prompt;
  final bool parentAgent;
  final bool accepted;
  final bool rolledBack;
  final bool compact;
  final bool inGroup;
  @override
  Widget build(BuildContext context) => Padding(key: StudioDriverKeys.timelineRow(id),
    padding: EdgeInsets.only(bottom: prompt ? 14 : inGroup ? 2 : compact ? 6 : 12),
    child: Align(alignment: prompt ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: prompt ? StudioLayout.conversationPromptWidth : double.infinity),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (accepted) Text(context.l10n.promptAccepted),
          if (parentAgent) Text(context.l10n.timelineParentAgent,
            key: StudioDriverKeys.parentAgentLabel(id)),
          Opacity(opacity: rolledBack ? .52 : 1, child: child),
          if (rolledBack) Text(context.l10n.timelineRolledBack,
            key: StudioDriverKeys.timelineRolledBack(id), style: Theme.of(context).textTheme.labelSmall),
        ]))));
}
