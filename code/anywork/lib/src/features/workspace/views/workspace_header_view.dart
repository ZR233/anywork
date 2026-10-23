import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';

class WorkspaceHeaderView extends StatelessWidget {
  const WorkspaceHeaderView({
    required this.project, required this.root, required this.hasThread,
    this.actions, this.notice, super.key,
  });
  final ProjectRecord? project;
  final WorkspaceThreadRecord? root;
  final bool hasThread;
  final Widget? actions;
  final Widget? notice;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    child: LayoutBuilder(builder: (context, constraints) {
      final label = project?.name.trim() ?? '';
      final title = Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(root?.title ?? (hasThread ? context.l10n.workspaceLoading : context.l10n.shellNoSession),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Tooltip(richMessage: TextSpan(text: root?.workspacePath ?? project!.path,
              style: const TextStyle(fontFamily: studioCodeFontFamily)),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant))),
          ],
        ]);
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (constraints.maxWidth < 520)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            title, if (actions != null) actions!,
          ])
        else Row(children: [
          Expanded(child: title),
          if (actions != null) ...[
            const SizedBox(width: 16),
            ConstrainedBox(constraints: BoxConstraints(maxWidth: constraints.maxWidth * .7),
              child: actions!),
          ],
        ]),
        if (notice != null) notice!,
      ]);
    }),
  );
}
