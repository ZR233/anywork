import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../widgets/workspace_failure_notice.dart';

/// Failure evidence and a frozen retry callback, never a Session capability or
/// another activation-state owner.
class WorkspaceActivationFailureView extends StatelessWidget {
  const WorkspaceActivationFailureView({
    required this.failure,
    required this.onRetry,
    super.key,
  });
  final StudioFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: WorkspaceFailureNotice(
        key: const ValueKey('workspace-activation-failure'),
        failure: failure,
        onRetry: onRetry,
      ),
    ),
  );
}
