import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';

/// Controlled text field that keeps IME composition while canonical values
/// echo back from the Client-owned draft.
class ModeEditorTextField extends StatefulWidget {
  const ModeEditorTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 1,
    this.hintText,
    this.helperText,
    this.monospace = false,
    this.keyboardType,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final String? hintText;
  final String? helperText;
  final bool monospace;
  final TextInputType? keyboardType;

  @override
  State<ModeEditorTextField> createState() => _ModeEditorTextFieldState();
}

class _ModeEditorTextFieldState extends State<ModeEditorTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant ModeEditorTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      style: widget.monospace
          ? const TextStyle(
              fontFamily: studioCodeFontFamily,
              fontSize: 12,
              height: 1.55,
            )
          : null,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        helperText: widget.helperText,
        alignLabelWithHint: widget.maxLines > 1,
      ),
    );
  }
}
