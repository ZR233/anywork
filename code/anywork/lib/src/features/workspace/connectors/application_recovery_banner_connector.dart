import 'dart:async';

import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/collection_presentation.dart';
import '../view_models/workspace_diagnostics_view_model.dart';
import '../views/application_recovery_banner_view.dart';
import '../widgets/workspace_failure_notice.dart';

class ApplicationRecoveryBannerConnector extends ConsumerWidget {
  const ApplicationRecoveryBannerConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watched = ref.watch(workspaceDiagnosticsViewModelProvider);
    if (watched.asError case final failure?) {
      if (failure.error is! StudioFailure) Error.throwWithStackTrace(failure.error, failure.stackTrace);
      return WorkspaceFailureNotice(failure: failure.error as StudioFailure,
        onRetry: () => ref.invalidate(workspaceDiagnosticsViewModelProvider));
    }
    final current = watched.asData?.value;
    if (current == null) return const SizedBox.shrink();
    final vm = ref.read(workspaceDiagnosticsViewModelProvider.notifier);
    final issues = current.recovery.issues;
    return ApplicationRecoveryBannerView(
      issues: presentRows(issues).where((issue) => issue.scope == RecoveryScope.application).toList(),
      dismissedIds: current.dismissedRecoveryIssues,
      hasMore: presentWindow(issues)?.continuation is OffsetCollectionContinuation,
      onMore: () => unawaited(vm.loadRecoveryIssues()),
      onDismiss: vm.dismissRecoveryIssue,
    );
  }
}
