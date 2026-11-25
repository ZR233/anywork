import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_menu_label.dart';
import '../../../../shared/studio_menu_button.dart';
import '../state/composer_view_state.dart';
import '../view_models/composer_view_model.dart';
import '../view_models/start_backend_view_model.dart';
import 'start_environment_view.dart';

class StartEnvironmentBar extends ConsumerWidget {
  const StartEnvironmentBar({
    required this.workspaceId,
    this.onAddProject,
    super.key,
  });

  final String workspaceId;
  final VoidCallback? onAddProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ComposerTarget.start(workspaceId: workspaceId);
    final provider = composerViewModelProvider(target);
    final state = ref.watch(provider).value;
    if (state?.start == null) return const SizedBox.shrink();
    final backend = ref.watch(startBackendViewModelProvider(workspaceId));
    return StartEnvironmentBarView(
      state: state!,
      actions: ref.read(provider.notifier),
      enabled: backend.enabled,
      onAddProject: onAddProject,
    );
  }
}

class StartEnvironmentBarView extends StatelessWidget {
  const StartEnvironmentBarView({
    required this.state,
    required this.actions,
    this.onAddProject,
    this.enabled = true,
    super.key,
  });

  final ComposerViewState state;
  final ComposerViewModel actions;
  final VoidCallback? onAddProject;
  final bool enabled;

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
    if (defaults == null || workspace == null) {
      return Align(alignment: Alignment.centerLeft, child: selector);
    }
    final draft = start.sessionDraft.forProject(workspace.id);
    return StartEnvironmentView(
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
    return StudioMenuButton(
      buttonKey: const ValueKey('start-project-selector'),
      enabled: widget.enabled,
      tooltip: widget.enabled
          ? (current?.path ?? title)
          : context.l10n.composerEnvironmentLocked,
      buttonStyle: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onOpen: () {
        _search.clear();
        setState(() {});
      },
      crossAxisUnconstrained: false,
      menuStyle: MenuStyle(
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
      child: StudioMenuLabel(
        label: title,
        enabled: widget.enabled,
        maxWidth: 180,
      ),
    );
  }
}
