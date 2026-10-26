import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../app/theme/material3_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/studio_l10n.dart';
import '../workspace/views/workspace_header_view.dart';
import 'sidebar_entries.dart';
import 'studio_shell.dart';
import 'views/thread_status_indicator.dart';

@Preview(name: 'Root shell', group: 'Application shell', size: Size(1280, 800))
Widget previewRootShell() => _sampleShell();

@Preview(name: 'Child shell', group: 'Application shell', size: Size(1280, 800))
Widget previewChildShell() => _sampleShell(child: true);

@Preview(
  name: 'Unknown directory',
  group: 'Application shell',
  size: Size(1280, 800),
)
Widget previewLoadingShell() => _sampleShell(child: true, loading: true);

@Preview(
  name: 'Compact shell',
  group: 'Application shell',
  size: Size(640, 600),
)
Widget previewCompactShell() => _sampleShell(child: true);

/// Static development props only. No ProviderScope, Repository, transport or
/// Session is instantiated; these fixtures cannot be mistaken for runtime facts.
Widget _sampleShell({bool child = false, bool loading = false}) {
  const project = ProjectRecord(
    id: 'sample-project',
    name: 'Application shell',
    path: '/workspace/example',
    sshAlias: null,
    updatedAt: 1,
  );
  final root = WorkspaceThreadRecord(
    id: 'sample-root',
    projectId: project.id,
    title: 'Implement the workspace boundary',
    mode: ThreadModeId.task,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    frozenModel: null,
    workspaceMode: ThreadWorkspaceMode.local,
    workspacePath: project.path,
    rootThreadId: 'sample-root',
    parentThreadId: null,
    role: 'planner',
    agentPath: 'root',
    status: ThreadStatus.idle,
    createdAt: 1,
    updatedAt: 1,
    lastUserMessageAt: null,
    archived: false,
  );
  final agents = [
    AgentDirectoryEntry(
      id: 'sample-main',
      threadId: root.id,
      rootThreadId: root.id,
      path: 'root',
      parentPath: null,
      role: 'planner',
      delegationMode: root.delegationMode,
      delegationPreference: root.delegationPreference,
      frozenModel: null,
      task: root.title,
      summary: null,
      depth: 0,
      state: const AgentState.idle(budgetPause: null),
      updatedAt: 1,
    ),
    AgentDirectoryEntry(
      id: 'sample-review',
      threadId: 'sample-child',
      rootThreadId: root.id,
      path: 'root/review',
      parentPath: 'root',
      role: 'reviewer',
      delegationMode: root.delegationMode,
      delegationPreference: root.delegationPreference,
      frozenModel: const ModelSelection(
        model: AccountModelKey(
          accountId: 'sample-account',
          modelId: 'review-model',
        ),
        effort: 'high',
      ),
      task: 'Review ownership and cancellation',
      summary: null,
      depth: 1,
      state: const AgentState.running(turnId: 'sample-turn'),
      updatedAt: 1,
    ),
  ];
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: pureStudioTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, content) => Theme(
      data: pureStudioTheme(locale: Localizations.localeOf(context)),
      child: content ?? const SizedBox.shrink(),
    ),
    home: Builder(
      builder: (context) => AppShell(
        navigation: ShellNavigationView(
          projectDirectory: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(project.name),
                subtitle: Text(project.path),
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(root.title),
                selected: !child,
                trailing: const ShellThreadStatusIndicator(
                  status: ThreadStatus.idle,
                ),
              ),
            ],
          ),
        ),
        // The single header implementation, shared with the live shell.
        chrome: WorkspaceHeaderView(
          project: project,
          root: loading ? null : root,
        ),
        notices: const SizedBox.shrink(),
        workspace: loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child ? agents.last.task : root.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      child
                          ? context.l10n.timelineAgentSubagent
                          : context.l10n.delegationFrozen,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        ShellThreadStatusIndicator(
                          status: child
                              ? ThreadStatus.running
                              : ThreadStatus.idle,
                        ),
                        const SizedBox(width: 8),
                        const Text('Preview · no live Session'),
                      ],
                    ),
                  ],
                ),
              ),
        canonicalSidebarWidth: 336,
        widthDraft: null,
        onResizeWidth: (_, _, _) {},
        onResetWidth: () {},
        onCommitWidth: () async {},
        onCancelWidth: () {},
      ),
    ),
  );
}
