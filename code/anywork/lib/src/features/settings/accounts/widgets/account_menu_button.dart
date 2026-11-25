import 'package:material_ui/material_ui.dart';

import '../../../../shared/widgets/studio_menu_button.dart';
import 'account_sections.dart' show accountActionButtonStyle;

/// Account action trigger with account-specific labels, icons and styling.
/// The shared menu owns its focus lifetime and Material interaction.
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
