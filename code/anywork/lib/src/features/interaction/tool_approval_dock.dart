import 'package:anywork/src/presentation/providers/client_provider.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/thread_session_store.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'hosted_child_interaction.dart';
import 'interaction_payload.dart';
import 'interaction_widgets.dart';

class ToolApprovalDock extends ConsumerStatefulWidget {
  const ToolApprovalDock({
    required this.threadId,
    required this.interactionId,
    required this.payload,
    required this.enabled,
    this.hostedChild,
    this.trailing,
    super.key,
  });

  /// 宿主会话：root 自身交互就是 root；转交的 child 交互也是 root。
  final String threadId;
  final String interactionId;
  final InteractionPayloadSnapshot payload;
  final bool enabled;

  /// 非空表示这是主会话代表的直接 child 交互，决定经主会话提交。
  final HostedChildInteraction? hostedChild;

  final Widget? trailing;

  @override
  ConsumerState<ToolApprovalDock> createState() => _ToolApprovalDockState();
}

class _ToolApprovalDockState extends ConsumerState<ToolApprovalDock> {
  late final TextEditingController _reasonController;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    final arguments = payload.formattedArguments;
    final enabled =
        widget.enabled &&
        (widget.hostedChild != null ||
            pendingInteractionIsActive(
              ref
                  .watch(threadSessionStoreProvider(widget.threadId))
                  .interactions,
              widget.interactionId,
            ));
    return InteractionDockShell(
      kind: InteractionDockKind.permission,
      trailing: widget.trailing,
      title: context.l10n.interactionPermissionTitle,
      subtitle: context.l10n.interactionPermissionSubtitle,
      footerHint: context.l10n.interactionPermissionFooterHint,
      footer: DockActions(
        children: [
          TextButton.icon(
            key: StudioDriverKeys.toolDeny,
            icon: const Icon(Icons.close),
            label: Text(context.l10n.interactionReject),
            onPressed: enabled
                ? () => _resolve(ToolApprovalDecision.denied)
                : null,
          ),
          FilledButton.icon(
            key: StudioDriverKeys.toolApprove,
            icon: const Icon(Icons.check),
            label: Text(context.l10n.interactionApprove),
            onPressed: enabled
                ? () => _resolve(ToolApprovalDecision.approved)
                : null,
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
          if (arguments.isNotEmpty) ...[
            const SizedBox(height: 10),
            InteractionCodeBlock(text: arguments),
          ],
          const SizedBox(height: 10),
          TextField(
            enabled: enabled,
            controller: _reasonController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.l10n.interactionReasonLabel,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  void _resolve(ToolApprovalDecision decision) {
    final reason = _reasonController.text.trim();
    final resolution = ToolApprovalResolutionCommand(
      decision: decision,
      reason: reason.isEmpty ? null : reason,
    );
    final hosted = widget.hostedChild;
    if (hosted != null) {
      submitHostedChildDecision(ref, widget.threadId, hosted, resolution);
      return;
    }
    unawaited(
      ref
          .read(anyworkClientProvider)
          .threadCommands
          .resolveActiveInteraction(
            widget.threadId,
            widget.interactionId,
            resolution,
          ),
    );
  }
}
