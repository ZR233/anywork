import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../state/interaction_payload.dart';
import '../widgets/interaction_widgets.dart';

class ToolApprovalView extends StatelessWidget {
  const ToolApprovalView({
    required this.payload,
    required this.enabled,
    this.error,
    required this.reasonController,
    required this.onReasonChanged,
    required this.onApprove,
    required this.onDeny,
    this.trailing,
    super.key,
  });

  final InteractionPayloadSnapshot payload;
  final bool enabled;
  final Object? error;
  final TextEditingController reasonController;
  final ValueChanged<String> onReasonChanged;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InteractionDockShell(
    kind: InteractionDockKind.permission,
    trailing: trailing,
    title: context.l10n.interactionPermissionTitle,
    subtitle: context.l10n.interactionPermissionSubtitle,
    footerHint: context.l10n.interactionPermissionFooterHint,
    footer: DockActions(
      children: [
        TextButton.icon(
          key: StudioDriverKeys.toolDeny,
          icon: const Icon(Icons.close),
          label: Text(context.l10n.interactionReject),
          onPressed: enabled ? onDeny : null,
        ),
        FilledButton.icon(
          key: StudioDriverKeys.toolApprove,
          icon: const Icon(Icons.check),
          label: Text(context.l10n.interactionApprove),
          onPressed: enabled ? onApprove : null,
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            InfoChip(icon: Icons.build_outlined, label: payload.toolName),
            if (payload.workingDirectory.isNotEmpty)
              InfoChip(
                icon: Icons.folder_outlined,
                label: payload.workingDirectory,
              ),
          ],
        ),
        if (payload.formattedArguments.isNotEmpty) ...[
          const SizedBox(height: 10),
          InteractionCodeBlock(text: payload.formattedArguments),
        ],
        const SizedBox(height: 10),
        TextField(
          enabled: enabled,
          controller: reasonController,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: context.l10n.interactionReasonLabel,
          ),
          onChanged: onReasonChanged,
        ),
        if (error case final cause?) ...[
          const SizedBox(height: 6),
          Text(
            '$cause',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
  );
}
