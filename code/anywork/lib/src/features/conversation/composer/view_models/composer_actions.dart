import 'package:anywork_client/studio_client.dart';

import '../../../../platform/dropped_file.dart';

/// UI dispatches intents; only the component model talks to Client/platforms.
abstract interface class ComposerActions {
  void updateText(String text);
  void submit();
  void stop(String expectedExecutionId);
  void continueConversation();
  void removeAttachment(String draftId);
  void addUrl(String url);
  void pickAttachments(
    List<ModelInputCapabilityView> capabilities,
    bool Function() isCurrent,
  );
  Future<void> dropAttachments(
    List<DroppedFileTransfer> files,
    bool Function() isCurrent,
  );
  void paste(ComposerTextPaste textPaste);
}

/// The official editor action and its UI lifetime must stay with the editor.
/// The model may invoke it after determining that the clipboard has no image.
final class ComposerTextPaste {
  const ComposerTextPaste({required this.invoke, required this.isCurrent});

  final Future<void> Function() invoke;
  final bool Function() isCurrent;
}
