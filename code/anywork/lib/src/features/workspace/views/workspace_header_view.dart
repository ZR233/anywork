import 'package:anywork_client/configuration.dart' show DelegationSettings;
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/labels/delegation_labels.dart';

class WorkspaceHeaderView extends StatelessWidget {
  const WorkspaceHeaderView({
    required this.project,
    required this.root,
    this.actions,
    this.notice,
    super.key,
  });
  final ProjectRecord? project;
  final WorkspaceThreadRecord? root;
  final Widget? actions;
  final Widget? notice;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final label = project?.name.trim() ?? '';
        final title = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              root?.title ?? context.l10n.shellNoSession,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            // 冻结的委托设置只在存在 root Thread 时展示，帮助理解会话为什么这样分工。
            if (root case final thread?)
              Tooltip(
                message: context.l10n.delegationFrozen,
                child: Text(
                  context.delegationSummary(
                    DelegationSettings(
                      mode: thread.delegationMode,
                      preference: thread.delegationPreference,
                    ),
                  ),
                  key: const ValueKey('shell-delegation-summary'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall,
                ),
              ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Tooltip(
                richMessage: TextSpan(
                  text: root?.workspacePath ?? project!.path,
                  style: const TextStyle(fontFamily: studioCodeFontFamily),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (constraints.maxWidth < 520)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, ?actions],
              )
            else
              Row(
                children: [
                  Expanded(child: title),
                  if (actions != null) ...[
                    const SizedBox(width: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * .7,
                      ),
                      child: actions!,
                    ),
                  ],
                ],
              ),
            ?notice,
          ],
        );
      },
    ),
  );
}
