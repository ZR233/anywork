import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_menu_label.dart';
import '../view_models/start_environment_view_model.dart';
import '../views/start_environment_view.dart';

class StartEnvironmentConnector extends ConsumerWidget {
  const StartEnvironmentConnector({
    required this.workspaceId,
    required this.enabled,
    this.projectOnly = false,
    this.onAddProject,
    super.key,
  });

  final String? workspaceId;
  final bool enabled;
  final bool projectOnly;
  final VoidCallback? onAddProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(startEnvironmentViewModelProvider(workspaceId));
    final actions = ref.read(
      startEnvironmentActionsProvider(workspaceId).notifier,
    );
    ref.listen(startEnvironmentActionsProvider(workspaceId), (_, error) {
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    });
    final defaults = model.defaults;
    final editable = enabled && model.editable;
    final selector = _ProjectTargetSelector(
      projects: model.projects,
      selected: model.workspace,
      enabled: editable,
      onAddProject: onAddProject,
      onSelected: actions.selectProject,
    );
    if (projectOnly || defaults == null || workspaceId == null) {
      return Align(alignment: Alignment.centerLeft, child: selector);
    }
    return StartEnvironmentView(
      projectSelector: selector,
      defaultMode: defaults.mode,
      defaultPreference: defaults.preference,
      modeOverride: model.modeOverride,
      preferenceOverride: model.preferenceOverride,
      workspaceMode: model.workspaceMode,
      isStandalone: model.workspace?.isStandalone ?? false,
      enabled: editable,
      onModeChanged: actions.setMode,
      onPreferenceChanged: actions.setPreference,
      onWorkspaceModeChanged: actions.setWorkspaceMode,
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
  final Future<void> Function(StudioProject?) onSelected;
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
