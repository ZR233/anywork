import 'package:flutter/material.dart';

import 'account_sections.dart' show accountActionButtonStyle;

/// Account action anchor. The focus node lives as long as its trigger, not a
/// build, so Material can return keyboard focus from the menu to the button.
class AccountMenuButton extends StatefulWidget {
  const AccountMenuButton({
    required this.tooltip,
    required this.menuChildren,
    this.buttonKey,
    this.label,
    super.key,
  });
  final String tooltip;
  final List<Widget> menuChildren;
  final Key? buttonKey;
  final String? label;

  @override
  State<AccountMenuButton> createState() => _AccountMenuButtonState();
}

class _AccountMenuButtonState extends State<AccountMenuButton> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    childFocusNode: _focusNode,
    consumeOutsideTap: true,
    menuChildren: widget.menuChildren,
    builder: (context, controller, child) {
      final onPressed = widget.menuChildren.isEmpty
          ? null
          : () => controller.isOpen ? controller.close() : controller.open();
      return widget.label == null
          ? IconButton(
              key: widget.buttonKey,
              focusNode: _focusNode,
              tooltip: widget.tooltip,
              onPressed: onPressed,
              icon: const Icon(Icons.more_horiz),
            )
          : TextButton.icon(
              style: accountActionButtonStyle(context),
              key: widget.buttonKey,
              focusNode: _focusNode,
              onPressed: onPressed,
              icon: const Icon(Icons.expand_more, size: 18),
              iconAlignment: IconAlignment.end,
              label: Text(widget.label!),
            );
    },
  );
}
