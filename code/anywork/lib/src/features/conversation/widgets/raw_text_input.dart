import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Controller owns selection/composing only. All raw business text is supplied
/// by its VM; programmatic updates preserve the controller when text is equal.
class RawTextInput extends StatefulWidget {
  const RawTextInput({
    required this.raw,
    required this.onChanged,
    this.enabled = true,
    this.secret = false,
    this.minLines = 1,
    this.maxLines = 4,
    this.decoration = const InputDecoration(),
    this.onSubmit,
    this.canSubmit = false,
    this.onStop,
    this.onPaste,
    this.inputKey,
    super.key,
  });

  final String raw;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool secret;
  final int minLines;
  final int maxLines;
  final InputDecoration decoration;
  final VoidCallback? onSubmit;
  final bool canSubmit;
  final VoidCallback? onStop;

  /// Platform adapter returns text only when it did not admit an image.
  final Future<String?> Function()? onPaste;
  final Key? inputKey;

  @override
  State<RawTextInput> createState() => _RawTextInputState();
}

class _RawTextInputState extends State<RawTextInput> {
  late final TextEditingController _controller;
  bool _pasting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.raw);
  }

  @override
  void didUpdateWidget(covariant RawTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text == widget.raw) return;
    final old = _controller.value;
    final length = widget.raw.length;
    _controller.value = TextEditingValue(
      text: widget.raw,
      selection: old.selection.isValid
          ? TextSelection(
              baseOffset: old.selection.baseOffset.clamp(0, length),
              extentOffset: old.selection.extentOffset.clamp(0, length),
            )
          : TextSelection.collapsed(offset: length),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      widget.enabled &&
      widget.canSubmit &&
      !_controller.value.composing.isValid;

  void _submit() {
    if (_canSubmit) widget.onSubmit?.call();
  }

  Future<void> _paste() async {
    if (_pasting || !widget.enabled) return;
    _pasting = true;
    try {
      final text = await widget.onPaste!();
      if (!mounted || text == null) return;
      final value = _controller.value;
      final selection = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      final replaced = value.replaced(selection, text);
      _controller.value = replaced.copyWith(
        selection: TextSelection.collapsed(
          offset: selection.start + text.length,
        ),
        composing: TextRange.empty,
      );
      widget.onChanged?.call(_controller.text);
    } finally {
      _pasting = false;
    }
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: {
      if (widget.onSubmit != null) ...{
        const SingleActivator(LogicalKeyboardKey.enter): const _SubmitIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const _SubmitIntent(),
      },
      if (widget.onStop != null)
        const SingleActivator(LogicalKeyboardKey.escape): const _StopIntent(),
      if (widget.onPaste != null) ...{
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            const _PasteIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            const _PasteIntent(),
        const SingleActivator(LogicalKeyboardKey.insert, shift: true):
            const _PasteIntent(),
        const SingleActivator(LogicalKeyboardKey.paste): const _PasteIntent(),
      },
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        _SubmitIntent: _SubmitAction(
          enabled: () => _canSubmit,
          submit: _submit,
        ),
        _StopIntent: CallbackAction<_StopIntent>(
          onInvoke: (_) {
            widget.onStop?.call();
            return null;
          },
        ),
        _PasteIntent: CallbackAction<_PasteIntent>(
          onInvoke: (_) {
            if (widget.enabled) _paste().ignore();
            return null;
          },
        ),
      },
      child: TextField(
        key: widget.inputKey,
        controller: _controller,
        enabled: widget.enabled,
        // isSecret is known before this control exists; no plaintext first frame.
        obscureText: widget.secret,
        enableSuggestions: !widget.secret,
        autocorrect: !widget.secret,
        minLines: widget.secret ? 1 : widget.minLines,
        maxLines: widget.secret ? 1 : widget.maxLines,
        textInputAction: TextInputAction.newline,
        onEditingComplete: () {},
        onSubmitted: widget.onSubmit == null ? null : (_) => _submit(),
        decoration: widget.decoration,
        onChanged: widget.onChanged,
      ),
    ),
  );
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

class _StopIntent extends Intent {
  const _StopIntent();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

class _SubmitAction extends Action<_SubmitIntent> {
  _SubmitAction({required this.enabled, required this.submit});
  final bool Function() enabled;
  final VoidCallback submit;
  @override
  bool isEnabled(_SubmitIntent intent) => enabled();
  @override
  Object? invoke(_SubmitIntent intent) {
    submit();
    return null;
  }
}
