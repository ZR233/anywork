import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/thread_session_store.dart';
import '../../../../domain/models/studio_models.dart';
import 'hosted_child_interaction_connector.dart';
import '../state/interaction_payload.dart';
import '../view_models/interaction_command_view_model.dart';
import '../views/tool_approval_view.dart';

class ToolApprovalConnector extends ConsumerStatefulWidget {
  const ToolApprovalConnector({
    required this.threadId,
    required this.interactionId,
    required this.expectedRevision,
    required this.payload,
    required this.enabled,
    this.hostedChild,
    this.trailing,
    super.key,
  });

  /// 宿主会话：root 自身交互就是 root；转交的 child 交互也是 root。
  final String threadId;
  final String interactionId;
  final int expectedRevision;
  final InteractionPayloadSnapshot payload;
  final bool enabled;

  /// 非空表示这是主会话代表的直接 child 交互，决定经主会话提交。
  final HostedChildInteraction? hostedChild;

  final Widget? trailing;

  @override
  ConsumerState<ToolApprovalConnector> createState() =>
      _ToolApprovalConnectorState();
}

class _ToolApprovalConnectorState extends ConsumerState<ToolApprovalConnector> {
  late final TextEditingController _reasonController;
  int _approvalGeneration = 0;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant ToolApprovalConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_approvalIdentity(oldWidget) != _approvalIdentity(widget)) {
      _approvalGeneration++;
      _reasonController.clear();
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = _approvalIdentity(widget);
    final generation = _approvalGeneration;
    final expectedRevision = widget.expectedRevision;
    final hosted = widget.hostedChild;
    final reason = _reasonController.text.trim();
    final command = ref
        .watch(interactionCommandViewModelProvider(identity.hostThreadId))
        .value
        ?.status(identity.interactionId);
    final enabled =
        widget.enabled &&
        !(command?.pending ?? false) &&
        !(command?.blocked ?? false) &&
        !(command?.accepted ?? false) &&
        (hosted != null ||
            pendingInteractionIsActive(
              ref
                  .watch(threadSessionStoreProvider(identity.hostThreadId))
                  .interactions,
              identity.interactionId,
            ));
    void resolve(ToolApprovalDecision decision) => _resolve(
      decision,
      identity: identity,
      generation: generation,
      expectedRevision: expectedRevision,
      hosted: hosted,
      reason: reason,
    );
    return ToolApprovalView(
      payload: widget.payload,
      enabled: enabled,
      error: hosted == null ? command?.error : null,
      reasonController: _reasonController,
      trailing: widget.trailing,
      onReasonChanged: (_) => setState(() {}),
      onApprove: () => resolve(ToolApprovalDecision.approved),
      onDeny: () => resolve(ToolApprovalDecision.denied),
    );
  }

  void _resolve(
    ToolApprovalDecision decision, {
    required _ApprovalIdentity identity,
    required int generation,
    required int expectedRevision,
    required HostedChildInteraction? hosted,
    required String reason,
  }) {
    // An old rendered action cannot combine its reason with a replacement request.
    if (!mounted ||
        !widget.enabled ||
        generation != _approvalGeneration ||
        identity != _approvalIdentity(widget) ||
        reason != _reasonController.text.trim()) {
      return;
    }
    final resolution = ToolApprovalResolutionCommand(
      decision: decision,
      reason: reason.isEmpty ? null : reason,
    );
    if (hosted != null) {
      submitHostedChildDecision(ref, identity.hostThreadId, hosted, resolution);
      return;
    }
    unawaited(
      ref
          .read(
            interactionCommandViewModelProvider(identity.hostThreadId).notifier,
          )
          .resolveActive(
            identity.hostThreadId,
            identity.interactionId,
            expectedRevision,
            resolution,
          )
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }
}

typedef _ApprovalIdentity = ({
  String hostThreadId,
  String interactionId,
  String? childThreadId,
  String rawBody,
  String summary,
  String toolName,
  String formattedArguments,
  String workingDirectory,
});

_ApprovalIdentity _approvalIdentity(ToolApprovalConnector widget) => (
  hostThreadId: widget.threadId,
  interactionId: widget.interactionId,
  childThreadId: widget.hostedChild?.summary.childThreadId,
  rawBody: widget.payload.rawBody,
  summary: widget.payload.summary,
  toolName: widget.payload.toolName,
  formattedArguments: widget.payload.formattedArguments,
  workingDirectory: widget.payload.workingDirectory,
);
