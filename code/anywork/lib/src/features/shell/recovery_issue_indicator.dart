import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';

/// Recovery 诊断的纯展示标识；影响等级只决定视觉强调，不改变生命周期状态。
class RecoveryIssueIndicator extends StatelessWidget {
  const RecoveryIssueIndicator({
    required this.issue,
    this.size = 18,
    super.key,
  });

  final StudioRecoveryIssue issue;
  final double size;

  @override
  Widget build(BuildContext context) {
    final advisory = issue.impact == RecoveryIssueImpact.advisory;
    return Tooltip(
      message: context.recoveryIssueLabel(issue),
      child: Icon(
        advisory ? Icons.info_outline : Icons.error_outline,
        size: size,
        color: advisory ? context.colors.primary : context.colors.error,
      ),
    );
  }
}
