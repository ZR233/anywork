import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/collection_presentation.dart';
import '../view_models/workspace_diagnostics_view_model.dart';
import '../views/recovery_check_status_view.dart';
import '../widgets/workspace_failure_notice.dart';

/// Migration of shared/recovery_check_status without the old store projection.
class RecoveryCheckStatusConnector extends ConsumerWidget {
  const RecoveryCheckStatusConnector({this.showChecking = false, super.key});
  final bool showChecking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watched = ref.watch(workspaceDiagnosticsViewModelProvider);
    if (watched.asError case final failure?) {
      if (failure.error is! StudioFailure) {
        Error.throwWithStackTrace(failure.error, failure.stackTrace);
      }
      return WorkspaceFailureNotice(
        failure: failure.error as StudioFailure,
        onRetry: () => ref.invalidate(workspaceDiagnosticsViewModelProvider),
      );
    }
    final value = watched.asData?.value;
    if (value == null) return const SizedBox.shrink();
    final source = presentReadValue(value.recovery.sourceStatus);
    final action = value.actions['recovery'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RecoveryCheckStatusView(
          status: value.recovery.projection.header?.source.brief,
          sourceError: switch (source) {
            FailedProductSourceStatus(:final error) ||
            DegradedProductSourceStatus(:final error) => error,
            _ => null,
          },
          readError:
              value.readErrors['recovery-source'] ??
              value.readErrors['recovery-issues'] ??
              switch (value.recovery.sourceStatus) {
                FailedReadValue(:final error) => error,
                _ => value.recovery.projection.sync.error,
              },
          retryPending: value.actions['recovery']?.waiting == true,
          showChecking: showChecking,
          onRetry: () => unawaited(
            ref
                .read(workspaceDiagnosticsViewModelProvider.notifier)
                .retryRecovery(),
          ),
        ),
        if (action?.admissionError ?? action?.operation?.error
            case final error?)
          WorkspaceFailureNotice(failure: error),
        if (action?.operation?.evidenceError case final error?)
          WorkspaceFailureNotice(failure: error),
        if (action?.observationError case final error?)
          WorkspaceFailureNotice(failure: error),
      ],
    );
  }
}
