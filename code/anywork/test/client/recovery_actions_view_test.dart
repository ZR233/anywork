import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/agents/state/agent_profiles_state.dart';
import 'package:anywork/src/features/settings/agents/views/agent_profiles_view.dart';
import 'package:anywork/src/features/settings/agents/widgets/worktree_recovery_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/selector_environment.dart';

const _preview = WorktreeRecoveryPreview(
  inspection: WorktreeInspection.unavailable, ownerKind: WorktreeOwner.session,
  ownerThreadId: 'thread-main', leaseRevision: 9, state: 'preserved', repositoryRoot: '/projects/demo',
  path: '/projects/demo/.anywork/worktrees/thread-main/session', branch: 'pure-session-thread-main',
  baseCommit: 'base', headCommit: null, dirty: null, changedFiles: null,
);
RecoveryIssue _issue(List<RecoveryAction> actions) => RecoveryIssue(
  id: 'original-issue', scope: RecoveryScope.thread, category: RecoveryCategory.repository,
  availableActions: actions, projectId: 'project', threadId: 'thread-main',
  message: 'Inspection failed without proving a clean working tree', worktree: _preview,
);
const _readIssue = RecoveryIssueRead(
  id: ReadText.inline(text: 'worktree-blocker'), scope: RecoveryScope.thread, category: RecoveryCategory.repository,
  availableActions: [RecoveryAction.retry, RecoveryAction.cleanupWorktree],
  projectId: ReadText.inline(text: 'project'), threadId: ReadText.inline(text: 'thread-main'),
  message: ReadText.inline(text: 'worktree unavailable'),
  worktree: WorktreeRecoveryPreviewRead(inspection: WorktreeInspection.unavailable, ownerKind: WorktreeOwner.session,
    ownerThreadId: ReadText.inline(text: 'thread-main'), leaseRevision: 9, state: ReadText.inline(text: 'preserved'),
    repositoryRoot: ReadText.inline(text: '/projects/demo'), path: ReadText.inline(text: '/projects/demo/.anywork/worktrees/thread-main/session'),
    branch: ReadText.inline(text: 'pure-session-thread-main'), baseCommit: ReadText.inline(text: 'base'), headCommit: null, dirty: null, changedFiles: null),
);

Widget _app(Widget child) => MaterialApp(theme: pureStudioTheme(), locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unknown worktree facts are not clean; [] gives no action and Retry/Cleanup can coexist', (tester) async {
    var retries = 0, cleanups = 0;
    Future<void> pump(List<RecoveryAction> actions) async {
      await tester.pumpWidget(_app(WorktreeRecoveryView(worktree: _preview, availableActions: actions,
        message: 'Original inspection failure', enabled: true, action: null, retryAction: null, errors: const [],
        onCleanup: () => cleanups++, onRetry: () => retries++)));
      await tester.pump();
    }
    await pump(const []);
    expect(find.byKey(const ValueKey('worktree-cleanup-session-thread-main')), findsNothing);
    expect(find.byKey(const ValueKey('worktree-retry-session-thread-main')), findsNothing);
    expect(find.textContaining('No uncommitted changes'), findsNothing, reason: 'Unknown must not claim Clean');
    expect(find.textContaining('Change status unknown'), findsOneWidget);
    expect(find.text('Changed files are not yet known. Retry the inspection.'), findsOneWidget);
    expect(find.textContaining(_preview.path), findsOneWidget);
    await pump(const [RecoveryAction.retry, RecoveryAction.cleanupWorktree]);
    await tester.tap(find.byKey(const ValueKey('worktree-retry-session-thread-main')));
    await tester.tap(find.byKey(const ValueKey('worktree-cleanup-session-thread-main')));
    expect((retries, cleanups), (1, 1));
    expect(find.textContaining('delete the branch'), findsNothing, reason: 'Cleanup preserves the branch');
  });

  testWidgets('AgentProfilesView receives full issues and returns the original issue for both actions', (tester) async {
    late SelectorEnvironment env;
    await tester.runAsync(() async { env = SelectorEnvironment(); await env.establish(); });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpClientFuture(tester, env.close(), 'profiles view source cleanup');
    });
    final issue = _issue(const [RecoveryAction.retry, RecoveryAction.cleanupWorktree]);
    RecoveryIssue? cleanup, retry;
    await tester.pumpWidget(_app(AgentProfilesView(
      state: AgentProfilesViewState(source: env.configuration.profiles.value, configurationSource: env.configuration.state.value,
        modelSource: env.models.state.value, recoverySource: env.recovery.state.value),
      profiles: const [], roleOptions: const {}, routeLabels: const {}, roleReadErrors: const {}, errors: const [], profileErrors: const {},
      worktreeIssues: [issue], actionableWorktreeIssueIds: {issue.id}, worktreeErrors: const {}, checkingRecovery: false,
      recoveryError: null, hasMore: false,
      onQuery: (_) {}, onAdd: () {}, onEdit: (_) {}, onEnabled: (_, _) {}, onModel: (_, _) {}, onEffort: (_, _) {}, onMore: () {}, onRetry: () {},
      onCleanup: (original) => cleanup = original, onRetryWorktree: (original) => retry = original, onRetryRecovery: () {},
    )));
    await tester.pump();
    final retryButton = find.byKey(const ValueKey('worktree-retry-session-thread-main'));
    final cleanupButton = find.byKey(const ValueKey('worktree-cleanup-session-thread-main'));
    await tester.ensureVisible(retryButton);
    await tester.tap(retryButton);
    await tester.ensureVisible(cleanupButton);
    await tester.tap(cleanupButton);
    expect(retry, same(issue));
    expect(cleanup, same(issue));
  });

  test('worktree blocker still rejects rename/select but does not block archive; unarchive never selects or opens', () async {
    final env = SelectorEnvironment();
    env.recoveryPort.preparedIssues = const [_readIssue];
    addTearDown(env.close);
    await env.establish(catalog: false);
    final selection = env.workspace.state.value;
    expect(await env.workspace.selectThread('thread-main').result, isA<RejectedCommandResult<WorkspaceSelectionResult>>());
    expect(await env.workspace.renameThread('thread-main', 'still blocked').result, isA<RejectedCommandResult<WorkspaceThreadRecord>>());
    expect(env.directory.renamedThreads, isEmpty);
    expect(env.workspace.state.value.selection, selection.selection);
    env.directory.onArchiveThread = (thread, operation) async {
      final original = env.directory.threads.firstWhere((value) => value.id == thread);
      await env.directory.publishThread(original.copyWith(archived: true));
      return ArchiveThreadCommandReply(
        result: ArchiveThreadResult(archivedRootId: thread,
          removedThreadIds: [for (final value in env.directory.threads) if (value.rootThreadId == thread) value.id], nextRoot: null),
        receipt: CommitReceipt(operationId: operation, disposition: CommitDisposition.applied,
          targets: const [ResourceStamp(resourceKey: 'thread-directory', ownerEpoch: 'selector-native', revision: 8)],
          effect: EffectPoint.immediate, effective: true, durable: false, requiresIdentityObservation: false),
    );
    };
    expect(await env.workspace.archiveThread('thread-main').result, isA<CommittedCommandResult<ArchiveThreadResult>>());
    expect(env.directory.archivedThreads, ['thread-main']);
    final beforeRestore = env.workspace.state.value;
    final saved = env.directory.threads.firstWhere((thread) => thread.id == 'thread-alt');
    env.directory.onRestore = (thread) async => saved.copyWith(archived: false);
    expect(await env.workspace.restoreThread(saved.id).result, isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>());
    expect(env.workspace.state.value, beforeRestore, reason: 'Visibility-only restore does not select/open');
    expect(env.directory.restores, ['thread-alt']);
    expect(env.directory.activations, isEmpty);
    expect(env.conversations.active.value, isNull);
    expect(env.conversations.existingSession('thread-alt'), isNull);
    expect(env.conversationPort.facets.execution, isEmpty);
    expect(env.timeline.requests, isEmpty);
  });
}
