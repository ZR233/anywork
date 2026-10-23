import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/attachments/attachment_metadata_view.dart';
import '../../../ui/layout/studio_panel.dart';
import '../state/composer_view_state.dart';
import '../widgets/raw_text_input.dart';

class ComposerView extends StatelessWidget {
  const ComposerView({
    required this.state,
    required this.enabled,
    required this.canSend,
    required this.running,
    required this.onText,
    required this.onSend,
    required this.onAddLocal,
    required this.onAddUrl,
    required this.onRemove,
    required this.onOpenAttachment,
    required this.onPaste,
    this.onStop,
    this.selectors,
    this.preparation,
    this.compact = false,
    super.key,
  });
  final ComposerViewState state;
  final bool enabled;
  final bool canSend;
  final bool running;
  final bool compact;
  final ValueChanged<String> onText;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final VoidCallback onAddLocal;
  final VoidCallback onAddUrl;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onOpenAttachment;
  final Future<String?> Function() onPaste;
  final Widget? selectors;
  final Widget? preparation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stop = running && !state.hasInput && !state.pending;
    return SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (preparation != null) preparation!,
      StudioPanel(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (state.attachments.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final attachment in state.attachments)
              SizedBox(width: 240, child: AttachmentMetadataView(
                attachment: attachment, enabled: enabled,
                onOpen: onOpenAttachment, onRemove: onRemove,
              )),
          ]),
        RawTextInput(
          raw: state.text, onChanged: onText, enabled: enabled,
          minLines: compact ? 2 : 3, maxLines: 8,
          canSubmit: canSend, onSubmit: onSend, onStop: onStop, onPaste: onPaste,
          inputKey: StudioDriverKeys.composerInput,
          decoration: InputDecoration(hintText: context.l10n.composerHint,
            filled: false, border: InputBorder.none),
        ),
        if (state.error != null || state.platformError != null || state.inputIssue != null)
          Align(alignment: Alignment.centerLeft, child: Text(
            state.error?.message ?? state.platformError?.message ?? state.inputIssue!.message,
            key: StudioDriverKeys.composerError,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.error))),
        if (state.submissionFailure != null && state.submissionFailure != state.error)
          Text(state.submissionFailure!.message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.error)),
        Row(children: [
          MenuAnchor(menuChildren: [
            MenuItemButton(onPressed: enabled ? onAddLocal : null,
              leadingIcon: const Icon(Icons.attach_file),
              child: Text(context.l10n.composerAttachmentPickLocal)),
            MenuItemButton(onPressed: enabled ? onAddUrl : null,
              leadingIcon: const Icon(Icons.link),
              child: Text(context.l10n.composerAddUrlTitle)),
          ], builder: (context, controller, child) => IconButton(
            onPressed: enabled ? () => controller.isOpen ? controller.close() : controller.open() : null,
            icon: const Icon(Icons.add))),
          Expanded(child: Align(alignment: Alignment.centerRight, child: selectors)),
          IconButton.filled(
            key: stop ? StudioDriverKeys.composerStop : canSend
                ? StudioDriverKeys.composerSubmit : const ValueKey('composer-submit-disabled'),
            tooltip: stop ? context.l10n.composerStop : running
                ? context.l10n.composerSendAndContinue : context.l10n.composerSend,
            onPressed: stop ? onStop : canSend ? onSend : null,
            style: IconButton.styleFrom(backgroundColor: stop
                ? colors.surfaceContainerHighest : colors.primary,
              foregroundColor: stop ? colors.onSurface : colors.onPrimary),
            icon: state.pending
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(stop ? Icons.stop : Icons.arrow_upward),
          ),
        ]),
      ])),
    ]));
  }
}
