import 'package:flutter/material.dart';

/// UI-only menu row; it contains no writer, route policy or resource owner.
@immutable
final class QuietSelectorMenuItem<T> {
  const QuietSelectorMenuItem({
    required this.value,
    required this.child,
    this.enabled = true,
    this.selected = false,
    this.itemKey,
  });

  final T value;
  final Widget child;
  final bool enabled;
  final bool selected;
  final Key? itemKey;
}

/// Borderless Material menu chrome. Flutter owns anchoring, keyboard traversal,
/// closing and focus restoration; the caller owns the selected value.
class QuietSelectorMenu<T> extends StatefulWidget {
  QuietSelectorMenu({
    required this.tooltip,
    required List<QuietSelectorMenuItem<T>> items,
    required this.child,
    required this.onSelected,
    this.enabled = true,
    this.onBlockedTap,
    super.key,
  }) : items = List.unmodifiable(items);

  final String tooltip;
  final List<QuietSelectorMenuItem<T>> items;
  final Widget child;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final VoidCallback? onBlockedTap;

  @override
  State<QuietSelectorMenu<T>> createState() => _QuietSelectorMenuState<T>();
}

class _QuietSelectorMenuState<T> extends State<QuietSelectorMenu<T>> {
  final MenuController _controller = MenuController();
  final FocusNode _triggerFocus = FocusNode(debugLabel: 'selector-trigger');

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canOpen = widget.enabled && widget.items.isNotEmpty;
    return MenuAnchor(
      controller: _controller,
      childFocusNode: _triggerFocus,
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        for (final item in widget.items)
          MenuItemButton(
            key: item.itemKey,
            overflowAxis: Axis.vertical,
            onPressed: widget.enabled && item.enabled
                ? () => widget.onSelected(item.value)
                : null,
            style: item.selected
                ? ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.surfaceContainerHigh,
                    ),
                  )
                : null,
            child: Semantics(selected: item.selected, child: item.child),
          ),
      ],
      child: Tooltip(
        message: widget.tooltip,
        child: Semantics(
          button: true,
          enabled: canOpen || widget.onBlockedTap != null,
          label: widget.tooltip,
          child: TextButton(
            focusNode: _triggerFocus,
            onPressed: canOpen
                ? () {
                    if (_controller.isOpen) {
                      _controller.close();
                    } else {
                      _controller.open();
                    }
                  }
                : widget.onBlockedTap,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              side: BorderSide.none,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
