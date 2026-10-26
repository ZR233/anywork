import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/conversation/conversation_screen.dart';
import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart';
import '../../../anywork_client/test/support/profile_native_pin.dart';
import 'support/composer_environment.dart';
import 'support/pump_client_future.dart';
import 'support/selector_conversation_port.dart';
import 'support/selector_environment.dart';
import 'support/selector_workspace_environment.dart';

const _child = 'thread-reviewer';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('子会话详情只读：运行、等待调度与待决交互都没有输入、停止、继续或答题能力', (tester) async {
    late SelectorWorkspaceEnvironment env;
    await tester.runAsync(() async {
      env = SelectorWorkspaceEnvironment();
      final index = env.core.directory.threads.indexWhere((thread) => thread.id == _child);
      env.core.directory.threads[index] = env.core.directory.threads[index].copyWith(status: ThreadStatus.idle);
      await env.establish();
      await env.core.selectThread('thread-main', bind: false);
      await env.core.workspace.loadAgents();
      expect(await env.core.workspace.selectAgentThread(_child).result, isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>());
      env.core.binding.start();
      await waitLatest(env.core.conversations.active, (session) => session?.threadId == _child);
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final opening in env.core.timeline.requests) {
        if (!opening.result.isCompleted) opening.result.complete(TestTimelineConnection());
      }
      await pumpClientFuture(tester, env.close(), 'child read-only full graph cleanup');
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: env.container,
      child: MaterialApp(theme: pureStudioTheme(), locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ConversationScreen(threadId: _child)),
      ),
    ));
    await tester.pump();
    final opening = await pumpClientFuture(tester, env.core.timeline.opened(0), 'child Timeline actual open');
    opening.result.complete(TestTimelineConnection(initial: baseline(1, items: [timelineItem(1, threadId: _child)])));
    await pumpClientFuture(tester, env.core.conversations.existingSession(_child)!.timeline.ready, 'child Timeline baseline');
    await pumpClientFuture(tester, env.container.read(conversationViewModelProvider(_child).future), 'child real VM');
    await tester.pump();
    expect(env.core.conversations.existingSession(_child)!.acceptsUserInput, isFalse);
    expect(find.byKey(StudioDriverKeys.agentReadOnlyPanel), findsOneWidget);
    expect(find.text('Child session (read-only)'), findsOneWidget);
    expect(find.text('Waiting for the main agent to schedule this member.'), findsNothing);

    await pumpClientFuture(tester, env.core.conversationPort.publishExecution(selectorExecution(execution: composerExecution)), 'child running native ACK');
    await tester.pump();
    expect(find.text('Waiting for the main agent to schedule this member.'), findsNothing, reason: '运行不冒充等待调度');
    await pumpClientFuture(tester, env.core.conversationPort.publishExecution(selectorExecution(continuation: composerContinuation)), 'child stopped awaiting parent');
    await tester.pump();
    expect(find.text('Waiting for the main agent to schedule this member.'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-readonly-waiting')), findsOneWidget);
    env.core.conversationPort.facets.interactionOpen = (thread, reference, origin) async => _ChildPendingRead(origin);
    await pumpClientFuture(tester, env.core.conversationPort.publishInteractionIndex(const [
      InteractionBrief(reference: InteractionReadRef(entry: 30, revision: 1), revision: 1,
        kind: InteractionKind.toolApproval, status: InteractionStatus.pending, createdAt: 1, updatedAt: 1),
    ]), 'child native pending index');
    await pumpClientFuture(tester, env.container.read(conversationViewModelProvider(_child).notifier).loadInteractions(), 'child pending read');
    await tester.pump();
    expect(find.byKey(const ValueKey('agent-readonly-pending')), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.childInteractionCard('interaction-approval')), findsNothing);
    expect(find.text('The child agent wants to run a command'), findsNothing);
    for (final key in [
      StudioDriverKeys.composerInput, StudioDriverKeys.composerSubmit,
      StudioDriverKeys.composerStop, StudioDriverKeys.composerContinue,
      StudioDriverKeys.userInputSubmit, StudioDriverKeys.toolApprove, StudioDriverKeys.toolDeny,
      StudioDriverKeys.planApprove,
    ]) {
      expect(find.byKey(key), findsNothing, reason: '只读child不得提供$key');
    }
    expect(env.core.commands.prompts.values, isEmpty);
    expect(env.core.commands.interrupts.values, isEmpty);
    expect(env.core.commands.continues.values, isEmpty);
  });
}

final class _ChildPendingRead extends ProfileNativePin implements InteractionReadConnection {
  _ChildPendingRead(this.origin) : super('child-pending-read');
  final ThreadFacetStamp origin;
  @override
  Future<InteractionReadHeader> header() async => InteractionReadHeader(
    scope: ReadScopeIdentity(scopeId: id, runtimeEpoch: origin.runtimeEpoch, incarnation: origin.incarnation, sourceRevision: origin.revision),
    interactionId: const ReadText.inline(text: 'interaction-approval'),
    threadId: const ReadText.inline(text: _child), turnId: const ReadText.inline(text: 'child-turn'),
    itemId: null, toolId: null, agentPath: const ReadText.inline(text: 'root/reviewer'), revision: 1,
    purpose: const InteractionPurposeRead.general(), continuation: null, createdAt: 1, updatedAt: 1,
    content: const InteractionContentRead.toolApproval(name: ReadText.inline(text: 'shell'), arguments: ReadText.inline(text: 'The child agent wants to run a command'), workingDirectory: null, parentAgentId: ReadText.inline(text: 'thread-main')),
    state: const InteractionStateRead.pending(operationId: ReadText.inline(text: 'child-native-operation')),
  );
}
