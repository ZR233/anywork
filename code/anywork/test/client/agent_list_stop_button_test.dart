import 'dart:async';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/workspace/connectors/workspace_header_connector.dart';
import 'package:anywork/src/features/workspace/view_models/workspace_view_model.dart';
import 'package:anywork/src/features/workspace/state/workspace_view_state.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/composer_environment.dart';
import 'support/pump_client_future.dart';
import 'support/selector_workspace_environment.dart';

const _root = 'thread-main';
const _child = 'thread-reviewer';
const _waiting = 'cold-sibling';
const _execution = AgentExecution(id: 'child-execution', phase: AgentExecutionPhase.running, turnId: 'child-turn');
const _stale = StudioFailure(code: StudioFailureCode.superseded, message: 'raw stop failure', retryable: false, correlationId: 'list-stop-stale', details: StudioFailureDetails.reason(reason: 'staleExecution'));

AgentDirectoryEntry _member(String id, {AgentState state = const AgentState.running(turnId: 'child-turn'), AgentExecution? execution, bool canStop = false, bool awaitingScheduling = false, String role = 'executor'}) => AgentDirectoryEntry(
  id: id, threadId: id, rootThreadId: _root, path: 'root/$id', parentPath: 'root', depth: 1,
  role: role, task: id == _child ? 'Running member' : 'Waiting member', summary: null,
  delegationMode: DelegationMode.profile, delegationPreference: DelegationPreference.balanced,
  frozenModel: null, state: state, execution: execution, canStop: canStop,
  awaitingScheduling: awaitingScheduling, updatedAt: 1767225600,
);

final class _Fixture {
  _Fixture(this.env);
  final SelectorWorkspaceEnvironment env;
  WorkspaceViewModel get vm => env.container.read(workspaceViewModelProvider.notifier);
  WorkspaceViewState get state => env.container.read(workspaceViewModelProvider).requireValue;
  late final ProviderSubscription<AsyncValue<WorkspaceViewState>> subscription;
  List<AgentDirectoryEntry> get members => AgentDirectoryQueries.forRoot(rootThreadId: _root, directory: env.core.workspace.agents.value);

  static Future<_Fixture> open(WidgetTester tester, {List<AgentDirectoryEntry>? rows}) async {
    late _Fixture fixture;
    await tester.runAsync(() async {
      final env = SelectorWorkspaceEnvironment();
      env.core.directory.agents = rows ?? [
        _member(_child, execution: _execution, canStop: true),
        _member(_waiting, state: const AgentState.idle(budgetPause: null), awaitingScheduling: true),
        _member('closed-member', state: const AgentState.closed()),
      ];
      fixture = _Fixture(env);
      await env.establish();
      await env.core.selectThread(_root, bind: false);
      await env.core.workspace.loadAgents();
      fixture.subscription = env.container.listen(workspaceViewModelProvider, (_, _) {});
      await env.container.read(workspaceViewModelProvider.future);
      await fixture.waitFor((state) => state.selectedMetadata?.value is ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>);
    });
    addTearDown(() async {
      fixture.subscription.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpClientFuture(tester, fixture.env.close(), 'directory full graph cleanup');
    });
    await fixture.pump(tester);
    return fixture;
  }

  Future<WorkspaceViewState> waitFor(bool Function(WorkspaceViewState) matches) {
    final done = Completer<WorkspaceViewState>();
    final observation = env.container.listen(workspaceViewModelProvider, (_, next) {
      final value = next.asData?.value;
      if (!done.isCompleted && value != null && matches(value)) done.complete(value);
    }, fireImmediately: true);
    return done.future.whenComplete(observation.close);
  }

  Future<void> publish(WidgetTester tester, List<AgentDirectoryEntry> values) async {
    await pumpClientFuture(tester, env.core.directory.publishAgents(values), 'directory native frame ACK');
    await pumpClientFuture(tester, env.core.workspace.loadAgents(), 'directory exact read');
    await tester.pump();
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container: env.container,
      child: MaterialApp(theme: pureStudioTheme(), locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _Header()),
      ),
    ));
    await tester.pump();
    await pumpClientUntil(tester, () => find.byKey(StudioDriverKeys.agentSwitcher).evaluate().isNotEmpty, 'header rendered canonical membership');
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(StudioDriverKeys.agentSwitcher));
    await tester.pump();
  }
}

class _Header extends ConsumerWidget {
  const _Header();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceViewModelProvider).requireValue;
    return WorkspaceHeaderConnector(workspace: state);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('行内停止只停该行执行，不切页、不开会话、不建草稿', (tester) async {
    final fixture = await _Fixture.open(tester);
    final env = fixture.env.core;
    final selection = env.workspace.state.value.selection;
    final usage = List.of(env.budget.usage);
    await fixture.openMenu(tester);
    expect(find.text('2 agents'), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.agentStop(_waiting)), findsNothing);
    expect(find.byKey(StudioDriverKeys.agentStop('closed-member')), findsNothing);
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_child)));
    final call = await pumpClientFuture(tester, env.commands.interrupts.at(0), 'row native stop');
    expect((call.threadId, call.executionId), (_child, _execution.id));
    expect(env.workspace.state.value.selection, selection);
    expect(env.conversations.existingSession(_child), isNull);
    expect(env.conversationPort.facets.execution, isEmpty);
    expect(env.timeline.requests, isEmpty);
    expect(env.budget.usage.where((value) => value.kind == ResourceKind.draft), usage.where((value) => value.kind == ResourceKind.draft));
    call.reply.complete(StopExecutionReply(threadId: call.threadId, executionId: call.executionId, stopped: true, receipt: composerReceipt(call.operationId)));
    final operation = env.operations.observations.lookup(call.operationId)!;
    await pumpClientFuture(tester, operation.state.waitFor((state) => state.receipt != null), 'row accepted');
    await tester.pump();
    expect(find.text('Stopping'), findsOneWidget);
    expect(operation.state.value.observed, isFalse);
    await fixture.publish(tester, [
      for (final row in fixture.members)
        row.threadId == _child ? row.copyWith(execution: null, canStop: false, awaitingScheduling: true, state: const AgentState.idle(budgetPause: null)) : row,
    ]);
    await pumpClientFuture(tester, operation.state.waitFor((state) => state.observed && state.effective), 'directory terminal effect');
    await tester.pump();
    expect(find.text('Stopped, waiting for the main agent to schedule'), findsNWidgets(2));
    expect(find.text('Continue'), findsNothing);
    expect(env.workspace.state.value.selection, selection);
  });

  testWidgets('停止未受理显示 typed 原因，保留可点停止；目录新目标不继承旧失败', (tester) async {
    final fixture = await _Fixture.open(tester);
    await fixture.openMenu(tester);
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_child)));
    final call = await pumpClientFuture(tester, fixture.env.core.commands.interrupts.at(0), 'row rejection entered');
    call.reply.completeError(const CommandDispatchFailure.rejected(failure: _stale));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.actions['directory-stop:$_child']?.operation?.failurePhase == OperationFailurePhase.rejected), 'row rejection shown');
    await tester.pump();
    expect(find.byKey(const ValueKey('agent-stop-failure-thread-reviewer')), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(StudioDriverKeys.agentStop(_child))).onPressed, isNotNull);
    expect(find.text('Stopping'), findsNothing);
    await fixture.publish(tester, [for (final row in fixture.members) row.threadId == _child ? row.copyWith(execution: _execution.copyWith(id: 'new-execution')) : row]);
    expect(find.byKey(const ValueKey('agent-stop-failure-thread-reviewer')), findsNothing);
    expect(fixture.env.core.commands.interrupts.values, hasLength(1));
  });

  testWidgets('终态、关闭、退役、关闭中与故障成员遗留 execution 均不产生停止；Idle preparing 可停', (tester) async {
    final rows = [
      _member('closed-member', state: const AgentState.closed(), execution: _execution, canStop: true, awaitingScheduling: true),
      _member('retired-member', role: 'planner', execution: _execution, canStop: true),
      _member('closing-member', state: const AgentState.closing(workspaceDisposition: AgentWorkspaceDisposition.preserve, turnId: 'turn', error: null), execution: _execution, canStop: true),
      _member('faulted-member', state: const AgentState.faulted(error: SourceStateError(code: 'failed', message: 'failed', retryable: false), turnId: 'turn', classification: AgentFaultClassification.recoverableRuntime), execution: _execution, canStop: true),
      _member('terminal-member', state: const AgentState.idle(budgetPause: null)),
      _member('preparing-member', state: const AgentState.idle(budgetPause: null), execution: const AgentExecution(id: 'preparing', phase: AgentExecutionPhase.preparing, turnId: null), canStop: true),
    ];
    final fixture = await _Fixture.open(tester, rows: rows);
    await fixture.openMenu(tester);
    for (final id in ['closed-member', 'retired-member', 'closing-member', 'faulted-member', 'terminal-member']) {
      expect(find.byKey(StudioDriverKeys.agentStop(id)), findsNothing, reason: id);
    }
    expect(find.byKey(StudioDriverKeys.agentStop('preparing-member')), findsOneWidget);
    expect(find.text('5 agents'), findsOneWidget, reason: '关闭成员仍可查看，但不计数');
    expect(find.byKey(StudioDriverKeys.agentRow('closed-member')), findsOneWidget);
  });

  testWidgets('视图落后于目录资格时0请求0本地action；NoExecution不伪成功，来源或执行变更真拒绝', (tester) async {
    final fixture = await _Fixture.open(tester);
    final oldDirectory = fixture.env.core.workspace.agents.value;
    final row = fixture.members.firstWhere((value) => value.threadId == _child);
    await fixture.publish(tester, [for (final item in fixture.members) item.threadId == _child ? item.copyWith(execution: null, canStop: false) : item]);
    await pumpClientFuture(tester, fixture.vm.stopDirectoryExecution(oldDirectory, row), 'stale menu callback');
    expect(fixture.env.core.commands.interrupts.values, isEmpty);
    expect(fixture.state.actions['directory-stop:$_child'], isNull, reason: '同源完整Ready的新read确认NoExecution，不登记本地action');
    final current = fixture.env.core.workspace.agents.value;
    final mirror = current.agents as CurrentCollectionMirror<AgentDirectoryEntry>;
    final reference = mirror.window.entries.firstWhere((entry) => (mirror.window.rows[entry.entry] as ReadyReadValue<AgentDirectoryEntry, ProductEntityRef>).current.value.threadId == _child);
    final before = List.of(fixture.env.core.budget.usage);
    final result = fixture.env.core.conversations.stopDirectoryExecution(origin: current.projection.stamp!, member: reference, executionId: _execution.id);
    expect(result, isA<StopNoExecution>());
    expect(fixture.env.core.budget.usage, before);
    expect(fixture.env.core.commands.interrupts.values, isEmpty);
    expect(() => fixture.env.core.conversations.stopDirectoryExecution(origin: oldDirectory.projection.stamp!.copyWith(ownerEpoch: 'retired-owner'), member: reference, executionId: _execution.id), throwsA(isA<StudioFailure>()));
    await fixture.publish(tester, [for (final item in fixture.members) item.threadId == _child ? item.copyWith(execution: _execution.copyWith(id: 'successor-execution'), canStop: true) : item]);
    expect(() => fixture.env.core.conversations.stopDirectoryExecution(origin: oldDirectory.projection.stamp!, member: reference, executionId: _execution.id), throwsA(isA<StudioFailure>().having((failure) => failure.code, 'different execution rejects', StudioFailureCode.superseded)));
    expect(fixture.env.core.commands.interrupts.values, isEmpty);
  });

  testWidgets('行内请求在途不伪受理，菜单重建仍禁用原操作；迟到回执不锁新执行', (tester) async {
    final fixture = await _Fixture.open(tester);
    await fixture.openMenu(tester);
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_child)));
    final call = await pumpClientFuture(tester, fixture.env.core.commands.interrupts.at(0), 'row pending entered');
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(StudioDriverKeys.agentStop(_child))).onPressed, isNull);
    expect(find.text('Stopping'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.pump(tester);
    await fixture.openMenu(tester);
    expect(tester.widget<IconButton>(find.byKey(StudioDriverKeys.agentStop(_child))).onPressed, isNull);
    await fixture.publish(tester, [for (final row in fixture.members) row.threadId == _child ? row.copyWith(execution: _execution.copyWith(id: 'replacement')) : row]);
    call.reply.complete(StopExecutionReply(threadId: call.threadId, executionId: call.executionId, stopped: true, receipt: composerReceipt(call.operationId)));
    await pumpClientFuture(tester, fixture.env.core.operations.observations.lookup(call.operationId)!.state.waitFor((state) => state.observed), 'old execution replaced');
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(StudioDriverKeys.agentStop(_child))).onPressed, isNotNull);
    expect(fixture.env.core.commands.interrupts.values, hasLength(1));
  });

  testWidgets('行内Unknown有独立未确认说明，不重发，重建不以计时器假受理', (tester) async {
    final fixture = await _Fixture.open(tester);
    await fixture.openMenu(tester);
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_child)));
    final call = await pumpClientFuture(tester, fixture.env.core.commands.interrupts.at(0), 'row unknown entered');
    call.reply.completeError(StateError('lost native stop response'));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.actions['directory-stop:$_child']?.operation?.failurePhase == OperationFailurePhase.unknownOutcome), 'row Unknown');
    await tester.pump();
    expect(find.byKey(const ValueKey('agent-stop-unconfirmed-thread-reviewer')), findsOneWidget);
    expect(find.text('Stopping'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.pump(tester);
    await fixture.openMenu(tester);
    expect(fixture.env.core.commands.interrupts.values, hasLength(1));
    expect(fixture.state.actions['directory-stop:$_child']!.operation!.receipt, isNull);
  });

  testWidgets('行内停止有独立可访问名称和命中区，不触发行选择', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final fixture = await _Fixture.open(tester);
    final selection = fixture.env.core.workspace.state.value.selection;
    await fixture.openMenu(tester);
    final stop = find.byKey(StudioDriverKeys.agentStop(_child));
    expect(tester.getSemantics(stop).label, contains('Running member'));
    expect(tester.getSize(stop).width, greaterThanOrEqualTo(40));
    expect(tester.getSize(stop).height, greaterThanOrEqualTo(40));
    await tester.tap(stop);
    final call = await pumpClientFuture(tester, fixture.env.core.commands.interrupts.at(0), 'accessible stop');
    expect(fixture.env.core.workspace.state.value.selection, selection);
    call.reply.completeError(const CommandDispatchFailure.rejected(failure: _stale));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.actions['directory-stop:$_child']?.operation?.error != null), 'accessible stop rejected');
  });
}
