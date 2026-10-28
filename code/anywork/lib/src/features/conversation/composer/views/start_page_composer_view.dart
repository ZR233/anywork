import 'dart:typed_data';

import 'package:anywork_client/studio_client.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import 'prompt_composer_view.dart';

class StartPageComposerView extends StatelessWidget {
  const StartPageComposerView({
    required this.composer,
    required this.controller,
    required this.pasteTargetId,
    required this.targetDiagnostic,
    required this.additionalDiagnostics,
    required this.enabled,
    required this.submissionLocked,
    required this.showSubmissionError,
    required this.inputCapabilities,
    required this.selectorBar,
    required this.settingsMenu,
    required this.onChanged,
    required this.onSubmit,
    required this.onPasteClipboard,
    required this.onPasteImage,
    required this.onReportFailure,
    required this.onPickLocalAttachments,
    required this.onDropAttachments,
    required this.onAddLocal,
    required this.onAddUrl,
    required this.onRemoveAttachment,
    super.key,
  });

  final ComposerThreadState composer;
  final TextEditingController controller;
  final String? pasteTargetId;
  final ComposerTargetDiagnostic? targetDiagnostic;
  final List<ComposerTargetDiagnostic> additionalDiagnostics;
  final bool enabled;
  final bool submissionLocked;
  final bool showSubmissionError;
  final List<ModelInputCapabilityView> inputCapabilities;
  final Widget selectorBar;
  final Widget? settingsMenu;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final Future<void> Function(
    void Function(String) pasteText,
    bool supportsImages,
    bool Function() isCurrent,
  )
  onPasteClipboard;
  final Future<void> Function(Uint8List) onPasteImage;
  final ValueChanged<Object> onReportFailure;
  final Future<void> Function(List<ModelInputCapabilityView>, bool Function())
  onPickLocalAttachments;
  final Future<void> Function(DropDetails, bool Function()) onDropAttachments;
  final Future<void> Function(List<String>) onAddLocal;
  final Future<void> Function(String) onAddUrl;
  final Future<void> Function(String) onRemoveAttachment;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 12),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: StudioLayout.conversationWidth,
          ),
          child: PromptComposerView(
            composer: composer,
            textController: controller,
            pasteTargetId: pasteTargetId,
            targetDiagnostic: targetDiagnostic,
            additionalDiagnostics: additionalDiagnostics,
            enabled: enabled,
            submissionLocked: submissionLocked,
            showSubmissionError: showSubmissionError,
            inputCapabilities: inputCapabilities,
            selectorBar: selectorBar,
            settingsMenu: settingsMenu,
            onChanged: onChanged,
            onSubmit: onSubmit,
            onPasteClipboard: onPasteClipboard,
            onPasteImage: onPasteImage,
            onReportFailure: onReportFailure,
            onPickLocalAttachments: onPickLocalAttachments,
            onDropAttachments: onDropAttachments,
            onAddLocal: onAddLocal,
            onAddUrl: onAddUrl,
            onRemoveAttachment: onRemoveAttachment,
          ),
        ),
      ),
    ),
  );
}
