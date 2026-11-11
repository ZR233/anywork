import 'package:material_ui/material_ui.dart';

/// ACP has no Native execution/continuation identity. Keep only its text editor
/// local instead of forging an AgentExecutionView for the Native action button.
class AcpPromptInput extends StatefulWidget {
  const AcpPromptInput({
    super.key,
    required this.text,
    required this.onChanged,
    required this.enabled,
    this.compact = false,
    this.hint = '发送消息给 ACP 智能体',
  });

  final String text;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool compact;
  final String hint;

  @override
  State<AcpPromptInput> createState() => _AcpPromptInputState();
}

class _AcpPromptInputState extends State<AcpPromptInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(covariant AcpPromptInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A streamed token/configuration update must not disturb selection or IME.
    if (widget.text == _controller.text) return;
    final selection = _controller.selection;
    _controller.value = TextEditingValue(
      text: widget.text,
      selection: TextSelection(
        baseOffset: selection.baseOffset.clamp(0, widget.text.length),
        extentOffset: selection.extentOffset.clamp(0, widget.text.length),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    enabled: widget.enabled,
    minLines: widget.compact ? 1 : 3,
    maxLines: widget.compact ? 4 : 8,
    textInputAction: TextInputAction.newline,
    decoration: InputDecoration(
      hintText: widget.hint,
      border: const OutlineInputBorder(),
    ),
    onChanged: widget.onChanged,
  );
}
