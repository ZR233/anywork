import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';

/// Starting a draft is supplied by the Conversation feature's public connector.
/// This widget owns only geometry; no draft, selection or preparation is copied.
class WorkspaceStartView extends StatelessWidget {
  const WorkspaceStartView({
    required this.hasProject,
    required this.projectName,
    required this.onAddProject,
    this.composer,
    this.projectNotice,
    super.key,
  });
  final bool hasProject;
  final String? projectName;
  final Widget? composer;
  final Widget? projectNotice;
  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) => Material(
    key: StudioDriverKeys.startPage,
    color: Theme.of(context).colorScheme.surface,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: StudioLayout.conversationWidth,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasProject
                          ? context.l10n.startPageWelcome
                          : context.l10n.startPageOpenProjectTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      !hasProject
                          ? context.l10n.startPageOpenProjectBody
                          : projectName == null
                          ? context.l10n.workspaceLoading
                          : context.l10n.startPageProject(projectName!),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (projectNotice != null) ...[
                      const SizedBox(height: 16),
                      projectNotice!,
                    ],
                    const SizedBox(height: 28),
                    ?composer,
                    if (!hasProject)
                      FilledButton.icon(
                        onPressed: onAddProject,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: Text(context.l10n.sidebarAddProject),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
