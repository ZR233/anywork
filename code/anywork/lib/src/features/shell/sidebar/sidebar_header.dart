part of 'studio_sidebar.dart';

class SidebarHeader extends StatelessWidget {
  const SidebarHeader({
    super.key,
    required this.searchController,
    required this.filter,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onFilterChanged,
    this.onNewSession,
    this.preparing = false,
    this.touchMode = false,
  });

  final TextEditingController searchController;
  final DirectoryFilter filter;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<DirectoryFilter> onFilterChanged;
  final VoidCallback? onNewSession;
  final bool preparing;
  final bool touchMode;

  @override
  Widget build(BuildContext context) {
    final height = touchMode ? 44.0 : 36.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            key: StudioDriverKeys.newSession,
            onPressed: preparing ? null : onNewSession,
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              backgroundColor: context.colors.surface,
              foregroundColor: context.colors.onSurface,
              side: BorderSide(color: context.colors.outlineVariant),
              minimumSize: Size(0, height),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              textStyle: context.text.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Row(
              children: [
                if (preparing)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.edit_outlined, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.sidebarNewSession,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('sidebar-search'),
            controller: searchController,
            onChanged: onSearchChanged,
            style: context.text.bodySmall,
            decoration: InputDecoration(
              hintText: context.l10n.sidebarSearch,
              isDense: true,
              filled: true,
              fillColor: context.colors.surface.withValues(alpha: .6),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              prefixIcon: const Icon(Icons.search, size: 16),
              prefixIconConstraints: BoxConstraints(
                minWidth: 32,
                minHeight: height,
              ),
              suffixIconConstraints: BoxConstraints(
                minWidth: 32,
                minHeight: height,
              ),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : _tileIconButton(
                      key: const ValueKey('sidebar-search-clear'),
                      tooltip: context.l10n.settingsCancel,
                      icon: Icons.close,
                      minTarget: touchMode ? 44 : 32,
                      onPressed: onClearSearch,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.colors.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SidebarFilters(
            selected: filter,
            touchMode: touchMode,
            onChanged: onFilterChanged,
          ),
        ],
      ),
    );
  }
}

class SidebarFilters extends StatelessWidget {
  const SidebarFilters({
    super.key,
    required this.selected,
    required this.onChanged,
    this.touchMode = false,
  });

  final DirectoryFilter selected;
  final ValueChanged<DirectoryFilter> onChanged;
  final bool touchMode;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: Row(
      children: [
        for (final filter in DirectoryFilter.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                selected: selected == filter,
                child: TextButton(
                  key: ValueKey('sidebar-filter-${filter.name}'),
                  onPressed: () => onChanged(filter),
                  style: TextButton.styleFrom(
                    foregroundColor: selected == filter
                        ? context.colors.onSurface
                        : context.colors.onSurfaceVariant,
                    backgroundColor: selected == filter
                        ? context.colors.surface
                        : Colors.transparent,
                    minimumSize: Size(0, touchMode ? 44 : 26),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: context.text.labelMedium?.copyWith(fontSize: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  child: Text(
                    switch (filter) {
                      DirectoryFilter.all => context.l10n.sidebarAll,
                      DirectoryFilter.running => context.l10n.sidebarRunning,
                      DirectoryFilter.attention =>
                        context.l10n.sidebarAttention,
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class SidebarSectionHeading extends StatelessWidget {
  const SidebarSectionHeading({
    super.key,
    required this.title,
    this.action,
    this.trailing,
  });

  final String title;
  final Widget? action;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6, top: 2, bottom: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: context.text.labelMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        ?action,
        ?trailing,
      ],
    ),
  );
}

class SidebarPageStatus extends StatelessWidget {
  const SidebarPageStatus({
    super.key,
    required this.workspaceId,
    required this.window,
    required this.onRetry,
    this.onMore,
    this.onFirst,
    this.filtered = false,
    this.standalone = false,
    this.showEmpty = true,
    this.keyPrefix = 'sidebar',
  });

  final String workspaceId;
  final SidebarWindow window;
  final VoidCallback? onRetry;
  final VoidCallback? onMore;
  final VoidCallback? onFirst;
  final bool filtered;
  final bool standalone;
  final bool showEmpty;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 2, 4, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (window.loading)
          LinearProgressIndicator(
            key: ValueKey('$keyPrefix-loading-$workspaceId'),
            minHeight: 2,
          ),
        if (window.error case final error?) ...[
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(error, style: TextStyle(color: context.colors.error)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: TextButton(
              key: ValueKey('$keyPrefix-retry-$workspaceId'),
              onPressed: window.loading ? null : onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(context.l10n.sidebarRetry),
            ),
          ),
        ] else if (showEmpty && !window.loading && window.threadIds.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 6, bottom: 6),
            child: Text(
              filtered
                  ? context.l10n.sidebarNoResults
                  : standalone
                  ? context.l10n.sidebarStandaloneEmpty
                  : context.l10n.sidebarEmptyProject,
              style: context.text.bodySmall,
            ),
          ),
        if (window.hasPrevious && onFirst != null)
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: TextButton(
              key: ValueKey('$keyPrefix-first-$workspaceId'),
              onPressed: window.loading ? null : onFirst,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(context.l10n.sidebarBack),
            ),
          ),
        if (window.hasMore && onMore != null)
          TextButton(
            key: ValueKey('$keyPrefix-more-$workspaceId'),
            onPressed: window.loading ? null : onMore,
            style: TextButton.styleFrom(
              foregroundColor: context.colors.onSurfaceVariant,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.only(right: 8),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: context.text.labelMedium,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: Center(child: Icon(Icons.history, size: 15)),
                ),
                const SizedBox(width: 6),
                Text(context.l10n.sidebarEarlier),
              ],
            ),
          ),
      ],
    ),
  );
}
