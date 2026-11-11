import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/studio_l10n.dart';
import '../acp/connectors/acp_start_composer_connector.dart';
import 'state/composer_view_state.dart';
import 'view_models/composer_view_model.dart';
import 'view_models/start_backend_view_model.dart';
import 'views/composer_content_view.dart';
import 'views/start_environment_bar.dart';
import 'views/start_page_composer_view.dart';
import 'widgets/start_backend_selector.dart';

export 'state/composer_view_state.dart' show ComposerTarget;

/// The only page-level input boundary. Business operations remain in Client;
/// observation and user intents belong to its target-bound presentation model.
class Composer extends ConsumerWidget {
  const Composer({
    required this.target,
    this.compact = false,
    this.onAddProject,
    super.key,
  });

  final ComposerTarget target;
  final bool compact;
  final VoidCallback? onAddProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = composerViewModelProvider(target);
    final state = ref.watch(provider);
    final workspaceId = switch (target) {
      StartComposerTarget(:final workspaceId) => workspaceId,
      _ => null,
    };
    final backend = target is StartComposerTarget
        ? ref.watch(startBackendViewModelProvider(workspaceId)).accountId
        : null;
    final backendSelector = target is StartComposerTarget
        ? StartBackendSelector(workspaceId: workspaceId)
        : null;
    return state.when(
      loading: () => const SafeArea(child: LinearProgressIndicator()),
      error: (error, _) => Text('$error'),
      data: (view) => backend != null && workspaceId != null
          ? StartPageComposerView(
              environmentBar: StartEnvironmentBar(
                state: view,
                actions: ref.read(provider.notifier),
                projectOnly: true,
                backendSelector: backendSelector,
                onAddProject: onAddProject,
              ),
              composer: AcpStartComposerConnector(workspaceId: workspaceId),
            )
          : ComposerContentView(
              key: ValueKey(target),
              target: target,
              state: view,
              actions: ref.read(provider.notifier),
              compact: compact,
              onAddProject: onAddProject,
              startBackendSelector: backendSelector,
            ),
    );
  }
}

/// Actions for one immutable submission use the same target-bound model as the
/// input. Client revalidates current eligibility, including older snapshots.
class ComposerSubmissionControls extends ConsumerWidget {
  const ComposerSubmissionControls({
    required this.target,
    required this.submission,
    super.key,
  });

  final ComposerTarget target;
  final ComposerSubmission submission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (submission.phase != ComposerSubmissionPhase.failed) {
      return const SizedBox.shrink();
    }
    final provider = composerViewModelProvider(target);
    final state = ref.watch(provider).value;
    final actions = ref.read(provider.notifier);
    final pending =
        state == null ||
        state.submissionOperations.contains(submission.inputId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state?.submissionFailures[submission.inputId] case final failure?)
          Text('$failure'),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: pending
                  ? null
                  : () => actions.retrySubmission(submission.inputId),
              child: Text(context.l10n.composerRetrySubmission),
            ),
            TextButton(
              onPressed: pending
                  ? null
                  : () => actions.removeSubmission(submission.inputId),
              child: Text(context.l10n.composerRemoveSubmission),
            ),
            if (pending)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ],
    );
  }
}
