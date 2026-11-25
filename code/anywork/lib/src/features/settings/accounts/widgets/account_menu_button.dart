import 'package:material_ui/material_ui.dart';

import '../../../../shared/studio_menu_button.dart';
import 'account_sections.dart' show accountActionButtonStyle;

/// Account action anchor. The focus node lives as long as its trigger, not a
/// build, so Material can return keyboard focus from the menu to the button.
class AccountMenuButton extends StatelessWidget {
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
  Widget build(BuildContext context) => label == null
      ? StudioMenuButton.icon(
          buttonKey: buttonKey,
          tooltip: tooltip,
          consumeOutsideTap: true,
          menuChildren: menuChildren,
          icon: const Icon(Icons.more_horiz),
        )
      : StudioMenuButton(
          buttonKey: buttonKey,
          tooltip: tooltip,
          consumeOutsideTap: true,
          menuChildren: menuChildren,
          buttonStyle: accountActionButtonStyle(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label!)),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        );
}
