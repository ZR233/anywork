import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_menu_label.dart';
import '../state/composer_view_state.dart';
import '../view_models/composer_view_model.dart';
import 'start_environment_view.dart';

class StartEnvironmentBar extends StatelessWidget {
  const StartEnvironmentBar({
    required this.state,
    required this.actions,
    this.onAddProject,
    this.enabled = true,
    this.projectOnly = false,
    this.backendSelector,
    super.key,
  });

  final ComposerViewState state;
  final ComposerViewModel actions;
  final VoidCallback? onAddProject;
  final bool enabled;
  final bool projectOnly;
  final Widget? backendSelector;

  @override
  Widget build(BuildContext context) {
    final start = state.start!;
    final workspace = start.project;
    final editable = enabled && !start.submitting && !state.standalonePreparing;
    final selector = _ProjectTargetSelector(
      projects: state.projects,
      selected: workspace,
      enabled: editable,
      onAddProject: onAddProject,
      onSelected: actions.selectProject,
    );
    final defaults = state.delegation;
    if (projectOnly || defaults == null || workspace == null) {
      return _withBackend(
        Align(alignment: Alignment.centerLeft, child: selector),
      );
    }
    final draft = start.sessionDraft.forProject(workspace.id);
    return _withBackend(
      StartEnvironmentView(
        projectSelector: selector,
        defaultMode: defaults.mode,
        defaultPreference: defaults.preference,
        modeOverride: draft.delegationModeOverride,
        preferenceOverride: draft.delegationPreferenceOverride,
        workspaceMode: draft.workspaceMode,
        isStandalone: workspace.isStandalone,
        enabled: editable,
        onModeChanged: actions.setDelegationMode,
        onPreferenceChanged: actions.setDelegationPreference,
        onWorkspaceModeChanged: actions.setWorkspaceMode,
      ),
    );
  }

  Widget _withBackend(Widget leading) {
    final backend = backendSelector;
    if (backend == null) return leading;
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 520
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                Align(alignment: Alignment.centerRight, child: backend),
              ],
            )
          : Row(
              children: [
                Expanded(child: leading),
                const SizedBox(width: 8),
                backend,
              ],
            ),
    );
  }
}

class _ProjectTargetSelector extends StatefulWidget {
  const _ProjectTargetSelector({
    required this.projects,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    this.onAddProject,
  });
  final List<StudioProject> projects;
  final StudioProject? selected;
  final bool enabled;
  final ValueChanged<StudioProject?> onSelected;
  final VoidCallback? onAddProject;

  @override
  State<_ProjectTargetSelector> createState() => _ProjectTargetSelectorState();
}

class _ProjectTargetSelectorState extends State<_ProjectTargetSelector> {
  final _search = TextEditingController();
  final _controller = MenuController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.selected;
    final title = current == null || current.isStandalone
        ? context.l10n.composerNoProject
        : '${current.name}${current.sshAlias == null ? '' : ' · SSH ${current.sshAlias}'}';
    final width = (MediaQuery.sizeOf(context).width - 40).clamp(160.0, 380.0);
    final query = _search.text.trim().toLowerCase();
    return MenuAnchor(
      controller: _controller,
      onOpen: () {
        _search.clear();
        setState(() {});
      },
      crossAxisUnconstrained: false,
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(
          Size(
            width,
            (MediaQuery.sizeOf(context).height - 48).clamp(160.0, 520.0),
          ),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              key: const ValueKey('start-project-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.l10n.composerProjectSearch,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        ),
        MenuItemButton(
          key: const ValueKey('start-project-standalone'),
          leadingIcon: Icon(
            current?.isStandalone == true
                ? Icons.check
                : Icons.chat_bubble_outline,
          ),
          onPressed: widget.enabled ? () => widget.onSelected(null) : null,
          child: Text(context.l10n.composerNoProject),
        ),
        for (final project in widget.projects.where(
          (item) =>
              !item.isStandalone &&
              '${item.name} ${item.path} ${item.sshAlias ?? ''}'
                  .toLowerCase()
                  .contains(query),
        ))
          MenuItemButton(
            key: ValueKey('start-project-${project.id}'),
            leadingIcon: Icon(
              current?.id == project.id ? Icons.check : Icons.folder_outlined,
            ),
            onPressed: widget.enabled ? () => widget.onSelected(project) : null,
            child: SizedBox(
              width: width - 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${project.name}${project.sshAlias == null ? '' : ' · SSH ${project.sshAlias}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    project.path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        const Divider(),
        MenuItemButton(
          key: const ValueKey('start-project-add'),
          leadingIcon: const Icon(Icons.add),
          onPressed: widget.enabled ? widget.onAddProject : null,
          child: Text(context.l10n.composerNewProject),
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: widget.enabled
            ? (current?.path ?? title)
            : context.l10n.composerEnvironmentLocked,
        child: TextButton(
          key: const ValueKey('start-project-selector'),
          onPressed: widget.enabled
              ? (controller.isOpen ? controller.close : controller.open)
              : null,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: StudioMenuLabel(
            label: title,
            enabled: widget.enabled,
            maxWidth: 180,
          ),
        ),
      ),
    );
  }
}
