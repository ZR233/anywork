import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/studio_l10n.dart';
import '../../../ui/overlays/confirmation_view.dart';
import '../state/editor_keys.dart';
import '../view_models/interaction_view_model.dart';
import 'interaction_connector.dart';

/// Conversation-internal editor chrome. Only explicit discard ends raw editing;
/// navigation/dispose merely removes these UI observers.
class InteractionEditorCloseConnector extends ConsumerStatefulWidget {
  const InteractionEditorCloseConnector({required this.target, required this.enabled,
    required this.onDirty, required this.onClosed, super.key});
  final InteractionEditorKey target;
  final bool enabled;
  final ValueChanged<bool> onDirty;
  final VoidCallback onClosed;
  @override
  ConsumerState<InteractionEditorCloseConnector> createState() => _InteractionEditorCloseState();
}

class _InteractionEditorCloseState extends ConsumerState<InteractionEditorCloseConnector> {
  bool _confirming = false;
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) widget.onDirty(ref.read(interactionViewModelProvider(widget.target)).value?.hasDraftEdits == true);
    });
  }

  Future<void> _close() async {
    if (_confirming) return;
    final provider = interactionViewModelProvider(widget.target);
    final value = ref.read(provider).value;
    if (value == null || !value.canCloseEditor) return;
    final vm = ref.read(provider.notifier);
    final revision = vm.editRevision;
    var discard = false;
    if (value.hasDraftEdits) {
      setState(() { _confirming = true; });
      try {
        discard = await showDialog<bool>(context: context, builder: (context) => ConfirmationView(
          title: context.l10n.modeEditorUnsavedTitle,
          body: context.l10n.interactionDiscardAnswersBody,
          confirmLabel: context.l10n.modeEditorDiscard,
          cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
          destructive: true, onConfirm: () => Navigator.of(context).pop(true),
          onCancel: () => Navigator.of(context).pop(false))) == true;
      } finally {
        if (mounted) setState(() { _confirming = false; });
      }
      if (!mounted || !discard) return;
    }
    // Freeze the original editor/raw revision before the confirmation await.
    // Late confirmation cannot discard newer input or cancel an accepted command.
    if (vm.endEditing(expectedEditRevision: revision, discardDraft: discard)) widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    final provider = interactionViewModelProvider(widget.target);
    final value = ref.watch(provider).value;
    ref.listen(provider.select((value) => value.value?.hasDraftEdits == true),
      (previous, next) => widget.onDirty(next));
    return InteractionConnector(target: widget.target, enabled: widget.enabled,
      trailing: TextButton(onPressed: _confirming || value?.canCloseEditor != true ? null : () => _close().ignore(),
        child: Text(MaterialLocalizations.of(context).closeButtonLabel)));
  }
}
