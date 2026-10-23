import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/branding/host_app_logo.dart';
import 'sidebar_rows.dart';

enum WorkspaceHostAction { vsCode, zed, terminal }

class WorkspaceHostMenu extends StatefulWidget {
  const WorkspaceHostMenu({
    required this.apps, required this.targetDescription, required this.terminalUnavailable,
    required this.onOpen, super.key,
  });
  final WorkspaceHostApps apps;
  final String targetDescription;
  final String terminalUnavailable;
  final ValueChanged<WorkspaceHostAction> onOpen;

  @override
  State<WorkspaceHostMenu> createState() => _WorkspaceHostMenuState();
}

class _WorkspaceHostMenuState extends State<WorkspaceHostMenu> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _controller, alignmentOffset: const Offset(6, 6),
    menuChildren: [
      _item(WorkspaceHostAction.vsCode, StudioDriverKeys.sessionOpenWorkspaceVsCode,
        widget.apps.vsCode, widget.apps.vsCodeImage, Icons.code,
        context.l10n.sessionOpenInVsCode, context.l10n.sessionVsCodeUnavailable),
      _item(WorkspaceHostAction.zed, StudioDriverKeys.sessionOpenWorkspaceZed,
        widget.apps.zed, widget.apps.zedImage, Icons.code,
        context.l10n.sessionOpenInZed, context.l10n.sessionZedUnavailable),
      _item(WorkspaceHostAction.terminal, StudioDriverKeys.sessionOpenWorkspaceTerminal,
        widget.apps.terminal, widget.apps.terminalImage, Icons.terminal,
        context.l10n.sessionOpenInTerminal, widget.terminalUnavailable),
    ],
    child: Tooltip(message: '${context.l10n.sessionOpenWorkspace}\n${widget.targetDescription}',
      child: TextButton(key: StudioDriverKeys.sessionOpenWorkspaceMenu,
        onPressed: () => _controller.isOpen ? _controller.close() : _controller.open(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.folder_open_outlined, size: 18), const SizedBox(width: 8),
          Text(context.l10n.sessionOpenWorkspace), const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 16),
        ]))),
  );

  Widget _item(WorkspaceHostAction action, Key key, bool available, ImageProvider? image,
      IconData fallback, String label, String unavailable) {
    final description = '$label\n${widget.targetDescription}${available ? '' : '\n$unavailable'}';
    return MenuItemButton(key: key, semanticsLabel: description,
      leadingIcon: HostAppLogo(image: image, fallback: fallback),
      onPressed: available ? () => widget.onOpen(action) : null,
      child: Tooltip(message: description,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)));
  }
}
