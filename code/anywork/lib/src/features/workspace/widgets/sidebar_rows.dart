import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/branding/host_app_logo.dart';

enum SidebarProjectAction { pin, copyPath, archive }
enum SidebarThreadAction { pin, rename, archive, restore, retryRecovery, copyPath, vsCode, zed, terminal }

/// UI-only host capabilities/artwork supplied by a Smart connector.
class WorkspaceHostApps {
  const WorkspaceHostApps({
    required this.vsCode, required this.zed, required this.terminal,
    this.vsCodeImage, this.zedImage, this.terminalImage,
  });
  final bool vsCode;
  final bool zed;
  final bool terminal;
  final ImageProvider? vsCodeImage;
  final ImageProvider? zedImage;
  final ImageProvider? terminalImage;
}

class SidebarProjectRow extends StatelessWidget {
  const SidebarProjectRow({
    required this.project, required this.expanded, required this.selected,
    required this.pinned, required this.touchMode, required this.onSelect,
    required this.onToggleExpanded, required this.onNewThread,
    required this.onAction, this.recovery, super.key,
  });
  final ProjectRecord project;
  final bool expanded;
  final bool selected;
  final bool pinned;
  final bool touchMode;
  final RecoveryIssue? recovery;
  final VoidCallback? onSelect;
  final VoidCallback onToggleExpanded;
  final VoidCallback? onNewThread;
  final ValueChanged<SidebarProjectAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final target = touchMode ? 44.0 : 32.0;
    return Tooltip(
      richMessage: TextSpan(text: recovery?.message ?? '${project.name}\n${project.path}'),
      ignorePointer: true,
      child: Row(key: StudioDriverKeys.projectRow(project.id), children: [
        IconButton(
          key: StudioDriverKeys.projectExpand(project.id),
          tooltip: l10n.sidebarProjects,
          onPressed: onToggleExpanded,
          constraints: BoxConstraints(minWidth: target, minHeight: target),
          icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 18),
        ),
        Expanded(child: InkWell(
          onTap: recovery?.blocksAccess == true ? null : onSelect,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: touchMode ? 12 : 7),
            child: Row(children: [
              Icon(recovery == null ? Icons.folder_outlined : Icons.error_outline, size: 17),
              const SizedBox(width: 6),
              Flexible(child: Text(project.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              )),
              const SizedBox(width: 6),
              Text(project.sshAlias == null ? l10n.sidebarLocal : 'SSH',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ]),
          ),
        )),
        IconButton(
          key: selected ? StudioDriverKeys.newSession : ValueKey('project-new-session-${project.id}'),
          onPressed: recovery?.blocksAccess == true ? null : onNewThread,
          tooltip: '${l10n.sidebarNewSession} · ${project.name}',
          icon: const Icon(Icons.add, size: 18),
          constraints: BoxConstraints(minWidth: target, minHeight: target),
        ),
        _SidebarMenu(
          menuKey: StudioDriverKeys.projectMenu(project.id),
          tooltip: l10n.sidebarProjects,
          children: [
            MenuItemButton(onPressed: () => onAction(SidebarProjectAction.pin),
              child: Text(pinned ? l10n.sidebarUnpin : l10n.sidebarPin)),
            MenuItemButton(onPressed: () => onAction(SidebarProjectAction.copyPath),
              child: Text(l10n.sidebarCopyPath)),
            MenuItemButton(key: const ValueKey('project-close'),
              onPressed: () => onAction(SidebarProjectAction.archive),
              child: Text(l10n.sidebarCloseProject)),
          ],
        ),
      ]),
    );
  }
}

class SidebarThreadRow extends StatelessWidget {
  const SidebarThreadRow({
    required this.thread, required this.project, required this.selected,
    required this.pinned, required this.hostApps, required this.onSelect,
    required this.onAction, this.recovery, super.key,
  });
  final WorkspaceThreadRecord thread;
  final ProjectRecord project;
  final bool selected;
  final bool pinned;
  final WorkspaceHostApps hostApps;
  final RecoveryIssue? recovery;
  final VoidCallback? onSelect;
  final ValueChanged<SidebarThreadAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final blocked = recovery?.blocksAccess == true;
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      richMessage: TextSpan(text: recovery?.message ??
          '${thread.title}\n${project.name}\n${thread.workspacePath}'),
      ignorePointer: true,
      child: Material(
        key: StudioDriverKeys.threadRow(thread.id),
        color: selected ? colors.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Row(children: [
          Expanded(child: InkWell(
            onTap: blocked ? null : onSelect,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(thread.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          )),
          if (thread.workspaceMode == ThreadWorkspaceMode.worktree)
            Tooltip(message: l10n.sidebarSessionWorktree,
              child: Icon(Icons.account_tree_outlined,
                key: StudioDriverKeys.threadWorkspaceMode(thread.id), size: 16)),
          if (thread.status != ThreadStatus.idle || recovery != null)
            Tooltip(message: context.threadStatusLabel(thread.status),
              child: Icon(recovery != null || thread.status == ThreadStatus.faulted
                  ? Icons.error_outline
                  : thread.status == ThreadStatus.waitingInteraction
                      ? Icons.help_outline : Icons.circle,
                size: 14,
                color: recovery != null || thread.status == ThreadStatus.faulted
                    ? colors.error : colors.onSurfaceVariant,
              )),
          IconButton(
            key: StudioDriverKeys.pinThread(thread.id),
            onPressed: () => onAction(SidebarThreadAction.pin),
            tooltip: pinned ? l10n.sidebarUnpin : l10n.sidebarPin,
            icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 16),
            visualDensity: VisualDensity.compact,
          ),
          _SidebarMenu(
            menuKey: StudioDriverKeys.threadMenu(thread.id),
            tooltip: l10n.sessionMoreActionsTooltip,
            children: [
              if (thread.archived) MenuItemButton(
                onPressed: blocked ? null : () => onAction(SidebarThreadAction.restore),
                child: Text(l10n.sidebarRestore),
              ),
              MenuItemButton(
                onPressed: () => onAction(SidebarThreadAction.rename),
                child: Text(l10n.sidebarRenameSession),
              ),
              if (!thread.archived) MenuItemButton(
                onPressed: () => onAction(SidebarThreadAction.archive),
                child: Text(l10n.sidebarArchiveSession),
              ),
              if (recovery?.canRetry == true) MenuItemButton(
                onPressed: () => onAction(SidebarThreadAction.retryRecovery),
                child: Text(l10n.sidebarRetry),
              ),
              MenuItemButton(
                onPressed: () => onAction(SidebarThreadAction.copyPath),
                child: Text(l10n.sidebarCopyPath),
              ),
              SubmenuButton(
                menuChildren: [
                  _hostItem(context, SidebarThreadAction.vsCode, hostApps.vsCode,
                    hostApps.vsCodeImage, Icons.code, l10n.sessionOpenInVsCode),
                  _hostItem(context, SidebarThreadAction.zed, hostApps.zed,
                    hostApps.zedImage, Icons.code, l10n.sessionOpenInZed),
                  _hostItem(context, SidebarThreadAction.terminal, hostApps.terminal,
                    hostApps.terminalImage, Icons.terminal, l10n.sessionOpenInTerminal),
                ],
                child: Text(l10n.sessionOpenWith),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _hostItem(BuildContext context, SidebarThreadAction action, bool available,
      ImageProvider? image, IconData fallback, String label) => MenuItemButton(
    onPressed: available ? () => onAction(action) : null,
    leadingIcon: HostAppLogo(image: image, fallback: fallback),
    child: Text(label, maxLines: 1),
  );
}

class _SidebarMenu extends StatefulWidget {
  const _SidebarMenu({required this.menuKey, required this.tooltip, required this.children});
  final Key menuKey;
  final String tooltip;
  final List<Widget> children;
  @override
  State<_SidebarMenu> createState() => _SidebarMenuState();
}

class _SidebarMenuState extends State<_SidebarMenu> {
  final _controller = MenuController();
  final _focus = FocusNode(debugLabel: 'workspace-row-menu');
  @override
  void dispose() { _focus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => MenuAnchor(
    key: widget.menuKey, controller: _controller,
    childFocusNode: _focus, menuChildren: widget.children,
    child: IconButton(
      focusNode: _focus, tooltip: widget.tooltip,
      onPressed: () => _controller.isOpen ? _controller.close() : _controller.open(),
      icon: const Icon(Icons.more_horiz, size: 18),
      visualDensity: VisualDensity.compact,
    ),
  );
}
