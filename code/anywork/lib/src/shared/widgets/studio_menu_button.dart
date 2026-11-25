import 'package:material_ui/material_ui.dart';

/// A Studio menu trigger whose anchor and button share one focus lifetime.
///
/// Material owns opening, dismissal, traversal and focus restoration. Callers
/// supply current menu contents and business actions without keeping a second
/// menu controller or reaching into the trigger's focus node.
class StudioMenuButton extends StatefulWidget {
  const StudioMenuButton({
    required this.tooltip,
    required this.menuChildren,
    required this.child,
    this.enabled = true,
    this.onBlockedTap,
    this.onOpen,
    this.menuStyle,
    this.buttonStyle,
    this.buttonKey,
    this.alignmentOffset = Offset.zero,
    this.consumeOutsideTap = false,
    this.crossAxisUnconstrained = true,
    super.key,
  }) : _icon = false;

  const StudioMenuButton.icon({
    required this.tooltip,
    required this.menuChildren,
    required Widget icon,
    this.enabled = true,
    this.onBlockedTap,
    this.onOpen,
    this.menuStyle,
    this.buttonStyle,
    this.buttonKey,
    this.alignmentOffset = Offset.zero,
    this.consumeOutsideTap = false,
    this.crossAxisUnconstrained = true,
    super.key,
  }) : child = icon,
       _icon = true;

  final String tooltip;
  final List<Widget> menuChildren;
  final Widget child;
  final bool enabled;
  final VoidCallback? onBlockedTap;
  final VoidCallback? onOpen;
  final MenuStyle? menuStyle;
  final ButtonStyle? buttonStyle;
  final Key? buttonKey;
  final Offset alignmentOffset;
  final bool consumeOutsideTap;
  final bool crossAxisUnconstrained;
  final bool _icon;

  @override
  State<StudioMenuButton> createState() => _StudioMenuButtonState();
}

class _StudioMenuButtonState extends State<StudioMenuButton> {
  final _focusNode = FocusNode(debugLabel: 'studio-menu-trigger');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    childFocusNode: _focusNode,
    style: widget.menuStyle,
    alignmentOffset: widget.alignmentOffset,
    consumeOutsideTap: widget.consumeOutsideTap,
    crossAxisUnconstrained: widget.crossAxisUnconstrained,
    onOpen: widget.onOpen,
    menuChildren: widget.menuChildren,
    builder: (context, controller, child) {
      final canOpen = widget.enabled && widget.menuChildren.isNotEmpty;
      final onPressed = canOpen
          ? () => controller.isOpen ? controller.close() : controller.open()
          : widget.onBlockedTap;
      if (widget._icon) {
        return IconButton(
          key: widget.buttonKey,
          focusNode: _focusNode,
          tooltip: widget.tooltip,
          onPressed: onPressed,
          style: widget.buttonStyle,
          icon: widget.child,
        );
      }
      return Tooltip(
        message: widget.tooltip,
        child: TextButton(
          key: widget.buttonKey,
          focusNode: _focusNode,
          onPressed: onPressed,
          style: widget.buttonStyle,
          child: widget.child,
        ),
      );
    },
  );
}

/// Borderless configuration triggers share sizing and disabled feedback.
ButtonStyle studioConfigurationButtonStyle({required bool enabled}) =>
    TextButton.styleFrom(
      overlayColor: enabled ? null : Colors.transparent,
      enabledMouseCursor: enabled ? null : SystemMouseCursors.basic,
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide.none,
    );
