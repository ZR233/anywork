import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';

/// Normal delivery stages stay compact; uncertain or failed outcomes stay visible.
/// This describes only submission, never execution or durable storage.
class ComposerSubmissionStatus extends StatelessWidget {
  const ComposerSubmissionStatus({required this.phase, super.key});

  final ComposerSubmissionPhase phase;

  @override
  Widget build(BuildContext context) {
    final label = switch (phase) {
      ComposerSubmissionPhase.sending => context.l10n.composerSubmissionSending,
      ComposerSubmissionPhase.accepted =>
        context.l10n.composerSubmissionAccepted,
      ComposerSubmissionPhase.failed => context.l10n.composerSubmissionFailed,
      ComposerSubmissionPhase.unknownOutcome =>
        context.l10n.composerSubmissionUnknown,
    };
    return SelectionContainer.disabled(
      child: switch (phase) {
        ComposerSubmissionPhase.sending ||
        ComposerSubmissionPhase.accepted => Tooltip(
          message: label,
          child: Icon(
            phase == ComposerSubmissionPhase.sending
                ? Icons.schedule_rounded
                : Icons.done_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        ComposerSubmissionPhase.failed ||
        ComposerSubmissionPhase.unknownOutcome => Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      },
    );
  }
}
