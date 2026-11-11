import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';

import '../../timeline/widgets/timeline_markdown.dart';

/// Selection belongs only to the frozen body, not submission status or controls.
/// Markdown rendering stays shared with Timeline; no content permit or image
/// download is created for this temporary submission.
class ComposerSubmissionBody extends StatelessWidget {
  const ComposerSubmissionBody({
    required this.submission,
    required this.isSafeLink,
    required this.onLink,
    super.key,
  });

  final ComposerSubmission submission;
  final bool Function(String) isSafeLink;
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: TimelineMarkdown(
      id: 'composer-submission-${submission.inputId}',
      text: submission.text,
      isSafeLink: isSafeLink,
      onLink: onLink,
      imageBuilder: (_, url) => SelectionContainer.disabled(
        child: TextButton.icon(
          onPressed: isSafeLink(url) ? () => onLink(url) : null,
          icon: const Icon(Icons.open_in_new),
          label: Text(url),
        ),
      ),
    ),
  );
}
