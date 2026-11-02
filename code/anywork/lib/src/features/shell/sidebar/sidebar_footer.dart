part of 'studio_sidebar.dart';

class SidebarFooter extends StatelessWidget {
  const SidebarFooter({
    super.key,
    required this.archived,
    required this.onToggleArchived,
    this.onSettings,
    this.hasUpdate = false,
    this.touchMode = false,
  });

  final bool archived;
  final VoidCallback onToggleArchived;
  final VoidCallback? onSettings;
  final bool hasUpdate;
  final bool touchMode;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    child: Column(
      children: [
        const Divider(height: 16),
        Row(
          children: [
            Expanded(
              child: SidebarFooterButton(
                key: const ValueKey('sidebar-archived'),
                tooltip: context.l10n.sidebarArchived,
                icon: Icons.archive_outlined,
                selected: archived,
                onPressed: onToggleArchived,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SidebarFooterButton(
                key: StudioDriverKeys.settingsOpen,
                tooltip: context.l10n.sidebarSettings,
                icon: Icons.settings_outlined,
                showIndicator: hasUpdate,
                onPressed: onSettings,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class SidebarFooterButton extends StatelessWidget {
  const SidebarFooterButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showIndicator = false,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool showIndicator;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 18),
        if (showIndicator)
          Positioned(
            key: const ValueKey('studio-update-indicator'),
            right: -3,
            top: -3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.statusColors.activeIndicator,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.surface, width: 1.5),
              ),
              child: const SizedBox.square(dimension: 8),
            ),
          ),
      ],
    );
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: selected
              ? colors.onSurface
              : colors.onSurfaceVariant,
          backgroundColor: selected ? colors.surfaceContainerHigh : null,
          minimumSize: const Size(0, 44),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          textStyle: context.text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(StudioRadii.sm),
          ),
        ),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 10),
            Expanded(child: Text(tooltip)),
          ],
        ),
      ),
    );
  }
}
