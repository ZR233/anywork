import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/studio_typography.dart';

/// UI-only controller for Settings forms. The value is the VM's raw input;
/// selection, focus and IME composing are the only locally owned state.
class SettingsFormField extends StatefulWidget {
  const SettingsFormField({
    required this.value,
    required this.label,
    required this.onChanged,
    this.enabled = true,
    this.obscureText = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.hint,
    this.error,
    this.onComposing,
    this.onCommit,
    this.code = false,
    this.inputFormatters,
    this.keyboardType,
    this.suffix,
    this.helper,
    this.autofocus = false,
    this.onSubmitted,
    this.maxLength,
    super.key,
  });

  final String value;
  final String label;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool obscureText;
  final int minLines;
  final int? maxLines;
  final String? hint;
  final String? error;
  final ValueChanged<bool>? onComposing;
  final VoidCallback? onCommit;
  final bool code;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final String? helper;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;

  @override
  State<SettingsFormField> createState() => _SettingsFormFieldState();
}

class _SettingsFormFieldState extends State<SettingsFormField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();
  bool _composing = false;
  bool _applyingValue = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_compositionChanged);
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant SettingsFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value || _controller.text == widget.value) return;
    final selection = _controller.selection;
    _applyingValue = true;
    try {
    _controller.value = TextEditingValue(
      text: widget.value,
      selection: TextSelection(
        baseOffset: selection.baseOffset.clamp(0, widget.value.length),
        extentOffset: selection.extentOffset.clamp(0, widget.value.length),
      ),
    );
    } finally { _applyingValue = false; }
  }

  void _compositionChanged() {
    final range = _controller.value.composing;
    final composing = range.isValid && !range.isCollapsed;
    if (composing == _composing) return;
    _composing = composing;
    if (_applyingValue) return;
    widget.onComposing?.call(composing);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) widget.onCommit?.call();
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _controller.removeListener(_compositionChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: _focus,
    enabled: widget.enabled,
    obscureText: widget.obscureText,
    minLines: widget.minLines,
    maxLines: widget.maxLines,
    maxLength: widget.maxLength,
    inputFormatters: widget.inputFormatters,
    keyboardType: widget.keyboardType,
    autofocus: widget.autofocus,
    style: widget.code ? const TextStyle(fontFamily: studioCodeFontFamily) : null,
    decoration: InputDecoration(labelText: widget.label, hintText: widget.hint,
      suffixIcon: widget.suffix, helperText: widget.helper, helperMaxLines: 3,
      errorText: widget.error, alignLabelWithHint: widget.maxLines != 1),
    onChanged: widget.onChanged,
    onEditingComplete: widget.onCommit,
    onSubmitted: widget.onSubmitted,
  );
}
