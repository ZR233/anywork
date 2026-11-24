import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../features/conversation/composer/widgets/composer_attachments.dart';
import '../features/conversation/composer/widgets/composer_paste_action.dart';
import '../features/conversation/composer/widgets/multiline_enter_shortcuts.dart';
import '../l10n/studio_l10n.dart';
import '../platform/desktop_drop_adapter.dart';
import '../platform/dropped_file.dart';
import 'composer_action_button.dart';
import 'composer_input_frame.dart';
import 'studio_driver_keys.dart';

/// An owner-qualified action; editor composition is checked before send actions.
final class ComposerActionPresentation {
  const ComposerActionPresentation({
    required this.state,
    required this.tooltip,
    this.onPressed,
    this.buttonKey,
    this.progressKey,
  });

  final ComposerActionButtonState state;
  final String tooltip;
  final VoidCallback? onPressed;
  final Key? buttonKey;
  final Key? progressKey;
}

/// The shared editor, attachments and toolbar for every conversation backend.
///
/// Only local editing state lives here. Drafts and protocol commands remain with
/// the owner supplying [text], [onTextChanged] and qualified actions.
class ConversationComposer extends StatelessWidget {
  const ConversationComposer({
    required this.identity,
    required this.text,
    required this.inputKey,
    required this.onTextChanged,
    required this.primaryAction,
    this.onSubmit,
    this.enabled = true,
    this.autofocus = false,
    this.creationCard = false,
    this.compact = false,
    this.dragging = false,
    this.configuration,
    this.diagnostics = const [],
    this.attachments = const [],
    this.onRemoveAttachment,
    this.canAttach = false,
    this.localCapabilities = const [],
    this.remoteCapabilities = const [],
    this.onPickLocal,
    this.onAddUrl,
    this.onDropFiles,
    this.onPaste,
    this.onKeyEvent,
    super.key,
  });

  final Object identity;
  final String text;
  final Key inputKey;
  final ValueChanged<String> onTextChanged;
  final ComposerActionPresentation primaryAction;
  final VoidCallback? onSubmit;
  final bool enabled;
  final bool autofocus;
  final bool creationCard;
  final bool compact;
  final bool dragging;
  final Widget? configuration;
  final List<Widget> diagnostics;
  final List<AttachmentDraftView> attachments;
  final ValueChanged<String>? onRemoveAttachment;
  final bool canAttach;
  final List<ModelInputCapabilityView> localCapabilities;
  final List<ModelInputCapabilityView> remoteCapabilities;
  final Future<void> Function(
    List<ModelInputCapabilityView> capabilities,
    bool Function() isCurrent,
  )?
  onPickLocal;
  final Future<void> Function(String url, bool Function() isCurrent)? onAddUrl;
  final Future<void> Function(
    List<DroppedFileTransfer> files,
    bool Function() isCurrent,
  )?
  onDropFiles;
  final void Function(
    Future<void> Function() pasteText,
    bool Function() isCurrent,
  )?
  onPaste;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  @override
  Widget build(BuildContext context) =>
      _ConversationComposerScope(key: ValueKey(identity), composer: this);
}

class _ConversationComposerScope extends StatefulWidget {
  const _ConversationComposerScope({required this.composer, super.key});

  final ConversationComposer composer;

  @override
  State<_ConversationComposerScope> createState() =>
      _ConversationComposerState();
}

class _ConversationComposerState extends State<_ConversationComposerScope> {
  ConversationComposer get _composer => widget.composer;

  late final _controller = TextEditingController.fromValue(
    TextEditingValue(
      text: _composer.text,
      selection: TextSelection.collapsed(offset: _composer.text.length),
    ),
  );
  late final FocusNode _focusNode = FocusNode(
    onKeyEvent: _handleEditorKeyEvent,
  );
  var _dragging = false;

  KeyEventResult _handleEditorKeyEvent(FocusNode node, KeyEvent event) {
    final handler = _composer.onKeyEvent;
    if (handler == null || _controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    return handler(node, event);
  }

  @override
  void didUpdateWidget(covariant _ConversationComposerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_composer.text == _controller.text) return;
    final previousLength = _controller.text.length;
    final selection = _controller.selection;
    final wasAtEnd =
        selection.isCollapsed && selection.baseOffset == previousLength;
    final nextSelection = wasAtEnd
        ? TextSelection.collapsed(offset: _composer.text.length)
        : selection.isValid
        ? selection.copyWith(
            baseOffset: selection.baseOffset.clamp(0, _composer.text.length),
            extentOffset: selection.extentOffset.clamp(
              0,
              _composer.text.length,
            ),
          )
        : TextSelection.collapsed(offset: _composer.text.length);
    _controller.value = TextEditingValue(
      text: _composer.text,
      selection: nextSelection,
    );
  }

  @override
  void dispose() {
    // Descendant editors are unmounted before their controller owner. Invalidate
    // the retired selection so a framework paste already awaiting the clipboard
    // cannot resume against this draft, even when it does not check mounted.
    _controller.value = const TextEditingValue();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool Function() _captureEligibility() {
    return () => mounted && _composer.enabled;
  }

  void _submit() {
    final state = _composer.primaryAction.state;
    if (!_composer.enabled ||
        (state != ComposerActionButtonState.send &&
            state != ComposerActionButtonState.sendAndContinue) ||
        _controller.value.composing.isValid) {
      return;
    }
    _composer.onSubmit?.call();
  }

  void _primaryAction() {
    final action = _composer.primaryAction;
    if ((action.state == ComposerActionButtonState.send ||
            action.state == ComposerActionButtonState.sendAndContinue) &&
        (!_composer.enabled || _controller.value.composing.isValid)) {
      return;
    }
    action.onPressed?.call();
  }

  Future<void> _addUrl() async {
    final isCurrent = _captureEligibility();
    var draft = '';
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        key: StudioDriverKeys.attachmentUrlDialog,
        title: Text(context.l10n.composerAddUrlTitle),
        content: TextField(
          key: StudioDriverKeys.attachmentUrlInput,
          autofocus: true,
          onChanged: (value) => draft = value,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
          decoration: const InputDecoration(hintText: 'https://…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            key: StudioDriverKeys.attachmentUrlSubmit,
            onPressed: () => Navigator.pop(context, draft.trim()),
            child: Text(context.l10n.composerAddUrlConfirm),
          ),
        ],
      ),
    );
    if (isCurrent() && url != null && url.isNotEmpty) {
      await _composer.onAddUrl?.call(url, isCurrent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = _composer.primaryAction;
    Widget editor = MultilineEnterShortcuts(
      controller: _controller,
      child: TextField(
        key: _composer.inputKey,
        controller: _controller,
        focusNode: _focusNode,
        autofocus: _composer.autofocus,
        enabled: _composer.enabled,
        minLines: _composer.compact ? 2 : 3,
        maxLines: 8,
        textInputAction: TextInputAction.send,
        onChanged: _composer.onTextChanged,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: context.l10n.composerHint,
          isDense: true,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
      ),
    );
    if (_composer.onPaste case final onPaste?) {
      editor = Actions(
        actions: {
          PasteTextIntent: ComposerPasteAction(
            canPaste: () => _composer.enabled,
            paste: (pasteText) => onPaste(pasteText, _captureEligibility()),
          ),
        },
        child: editor,
      );
    }
    final frame = ComposerInputFrame(
      creationCard: _composer.creationCard,
      compact: _composer.compact,
      dragging: _dragging || _composer.dragging,
      configuration: _composer.configuration,
      attachmentAction: AttachmentMenu(
        enabled: _composer.canAttach,
        localCapabilities: _composer.localCapabilities,
        remoteCapabilities: _composer.remoteCapabilities,
        onPickLocal: (capabilities) async {
          await _composer.onPickLocal?.call(
            capabilities,
            _captureEligibility(),
          );
        },
        onAddUrl: _addUrl,
      ),
      primaryAction: ComposerActionButton(
        state: action.state,
        tooltip: action.tooltip,
        buttonKey: action.buttonKey,
        progressKey: action.progressKey,
        onPressed: action.onPressed == null ? null : _primaryAction,
      ),
      body: [
        if (_composer.attachments.isNotEmpty)
          AttachmentDraftRail(
            attachments: _composer.attachments,
            enabled: _composer.onRemoveAttachment != null,
            onRemove: (id) => _composer.onRemoveAttachment?.call(id),
          ),
        editor,
        ..._composer.diagnostics,
      ],
    );
    final onDrop = _composer.onDropFiles;
    if (onDrop == null) return frame;
    return DesktopFileDropTarget(
      enabled: _composer.canAttach && _composer.localCapabilities.isNotEmpty,
      onEnter: () => setState(() => _dragging = true),
      onLeave: () {
        if (_dragging) setState(() => _dragging = false);
      },
      onDrop: (files) => onDrop(files, _captureEligibility()),
      child: frame,
    );
  }
}
