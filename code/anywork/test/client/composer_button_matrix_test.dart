import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/conversation/state/composer_primary_action.dart';
import 'package:anywork/src/features/conversation/views/composer_view.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/composer_environment.dart';
import 'support/pump_client_future.dart';
import 'support/selector_conversation_port.dart';
import 'support/selector_environment.dart' show waitLatest;

const _failure = StudioFailure(
  code: StudioFailureCode.conflict,
  message: 'raw stop failure', retryable: false, correlationId: 'matrix-stale',
  details: StudioFailureDetails.reason(reason: 'staleExecution'),
);

const _storage = StorageBrief(
  reference: StorageReadRef(entry: 11, revision: 1),
  fault: null, faultGeneration: 0, acceptedSequence: 7, durableSequence: 6,
  execution: ThreadStorageExecution.running,
  pressurePaused: true, resumeRequired: true, canResume: false, hasLastError: false,
);

Future<void> _acceptStop(WidgetTester tester, ComposerEnvironment fixture) async {
  final call = await pumpClientFuture(tester, fixture.env.commands.interrupts.at(0), 'native stop dispatch');
  call.reply.complete(StopExecutionReply(
    threadId: call.threadId, executionId: call.executionId,
    stopped: true, receipt: composerReceipt(call.operationId),
  ));
  await pumpClientFuture(tester, fixture.waitFor((state) => state.stop?.accepted == true), 'stop acceptance');
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('运行中、清理中、可继续、正在继续与完成态的按钮矩阵', (tester) async {
    final fixture = await ComposerEnvironment.open(tester);
    await fixture.pump(tester);
    expect(tester.widget<ComposerView>(find.byType(ComposerView)).primaryAction.kind, ComposerPrimaryActionKind.send);
    await fixture.publish(tester, selectorExecution(execution: composerExecution));
    expect(find.byKey(StudioDriverKeys.composerStop), findsOneWidget);
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), 'raw draft');
    await tester.pump();
    expect(tester.widget<ComposerView>(find.byType(ComposerView)).primaryAction.kind, ComposerPrimaryActionKind.sendAndContinue);
    await fixture.publish(tester, selectorExecution(execution: composerExecution.copyWith(phase: AgentExecutionPhase.stopping)));
    expect(find.byKey(const ValueKey('composer-stopping-disabled')), findsOneWidget);
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), '');
    await fixture.publish(tester, selectorExecution(continuation: composerContinuation));
    expect(find.byKey(StudioDriverKeys.composerContinue), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(fixture.env.commands.continues.values, isEmpty, reason: '空继续必须显式点击，Enter 不提交');
    await fixture.publish(tester, selectorExecution(continuation: composerContinuation.copyWith(claimed: true)));
    expect(find.byKey(const ValueKey('composer-continuing-disabled')), findsOneWidget);
    await fixture.publish(tester, selectorExecution());
    expect(find.byKey(StudioDriverKeys.composerContinue), findsNothing);
    expect(tester.widget<ComposerView>(find.byType(ComposerView)).primaryAction.kind, ComposerPrimaryActionKind.send);
  });

  testWidgets('保存与模型阻塞禁用继续而不清草稿，阻塞不挡仍存在的停止目标', (tester) async {
    final fixture = await ComposerEnvironment.open(tester);
    await fixture.pump(tester);
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), 'keep this draft');
    await fixture.publish(tester, selectorExecution(continuation: composerContinuation).copyWith(storage: _storage));
    final blocked = tester.widget<ComposerView>(find.byType(ComposerView));
    expect(blocked.primaryAction.enabled, isFalse);
    expect(blocked.primaryAction.blocker, isA<ComposerStorageBlocker>());
    expect(fixture.env.drafts.composer(composerThreadId).state.value.text, 'keep this draft');
    await fixture.publish(tester, selectorExecution(continuation: composerContinuation));
    await pumpClientFuture(tester, fixture.env.conversationPort.publishRoute(
      fixture.env.conversationPort.routes[1]!.copyWith(available: false, unavailableReason: 'native model unavailable'),
    ), 'native unavailable model route ACK');
    await tester.pump();
    expect(tester.widget<ComposerView>(find.byType(ComposerView)).primaryAction.blocker, isA<ComposerModelBlocker>());
    expect(tester.widget<ComposerView>(find.byType(ComposerView)).primaryAction.enabled, isFalse);
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), '');
    await fixture.publish(tester, selectorExecution(execution: composerExecution).copyWith(storage: _storage));
    expect(tester.widget<ComposerView>(find.byType(ComposerView)).primaryAction.enabled, isTrue);
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await _acceptStop(tester, fixture);
    await fixture.publish(tester, selectorExecution());
  });

  testWidgets('停止与继续被拒绝显示 typed 原因且不丢草稿', (tester) async {
    final fixture = await ComposerEnvironment.open(tester, initial: selectorExecution(execution: composerExecution));
    await fixture.pump(tester);
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    final stop = await pumpClientFuture(tester, fixture.env.commands.interrupts.at(0), 'rejected stop entered');
    stop.reply.completeError(const CommandDispatchFailure.rejected(failure: _failure));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.stop?.failure != null), 'stop rejection');
    await tester.pump();
    expect(find.byKey(const ValueKey('composer-stop-failure')), findsOneWidget);
    expect(fixture.state.stop!.accepted, isFalse);
    await fixture.publish(tester, selectorExecution(continuation: composerContinuation));
    await tester.tap(find.byKey(StudioDriverKeys.composerContinue));
    final continuation = await pumpClientFuture(tester, fixture.env.commands.continues.at(0), 'rejected continuation entered');
    continuation.reply.completeError(const CommandDispatchFailure.rejected(failure: _failure));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.continuation?.result is RejectedCommandResult<ContinueThreadReply>), 'continue rejection');
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), 'draft after failure');
    await tester.pump();
    expect(fixture.env.drafts.composer(composerThreadId).state.value.text, 'draft after failure');
    expect(fixture.state.continuation!.accepted, isFalse);
    expect(fixture.vm.primaryAction(hasContent: true, submissionPending: false).enabled, isTrue);
  });

  testWidgets('输入法组词中的 send 动作不提交，草稿保留', (tester) async {
    final fixture = await ComposerEnvironment.open(tester);
    await fixture.pump(tester);
    await tester.tap(find.byKey(StudioDriverKeys.composerInput));
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '正在组词', selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    ));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(fixture.env.commands.prompts.values, isEmpty);
    expect(fixture.env.drafts.composer(composerThreadId).state.value.text, '正在组词');
  });

  testWidgets('有内容时Enter走真实submitPrompt而不是空continue，冻结原草稿和route', (tester) async {
    for (final initial in [
      selectorExecution(execution: composerExecution),
      selectorExecution(continuation: composerContinuation),
    ]) {
      final fixture = await ComposerEnvironment.open(tester, initial: initial);
      await fixture.pump(tester);
      await tester.enterText(find.byKey(StudioDriverKeys.composerInput), '  exact raw draft  ');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      final call = await pumpClientFuture(tester, fixture.env.commands.prompts.at(0), 'Enter actual prompt dispatch');
      expect((call.threadId, call.input.text, call.routeRevision), (composerThreadId, '  exact raw draft  ', 8));
      expect(fixture.env.commands.continues.values, isEmpty);
      call.reply.completeError(const CommandDispatchFailure.rejected(failure: _failure));
      final draft = fixture.env.drafts.composer(composerThreadId);
      await pumpClientFuture(tester, waitLatest(draft.state, (state) => state.submission is FailedDraftSubmission), 'prompt rejected without draft loss');
      expect(draft.state.value.text, '  exact raw draft  ');
    }
  });

  testWidgets('点击冻结 executionId，旧渲染目标不会在排队期间被重选', (tester) async {
    final fixture = await ComposerEnvironment.open(tester, initial: selectorExecution(execution: composerExecution));
    await fixture.pump(tester);
    final old = fixture.vm.captureStop(fixture.page)!;
    await fixture.publish(tester, selectorExecution(execution: composerExecution.copyWith(id: 'replacement-execution')));
    await pumpClientFuture(tester, old(), 'stale captured stop');
    expect(fixture.env.commands.interrupts.values, isEmpty);
    expect(fixture.env.drafts.composer(composerThreadId).state.value.text, '');
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    final call = await pumpClientFuture(tester, fixture.env.commands.interrupts.at(0), 'replacement stop entered');
    expect((call.threadId, call.executionId), (composerThreadId, 'replacement-execution'));
    call.reply.completeError(const CommandDispatchFailure.rejected(failure: _failure));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.stop?.failure != null), 'exact target rejection');
  });

  testWidgets('请求在途只禁用停止，不伪受理；Escape 在有草稿时仍停原执行', (tester) async {
    final fixture = await ComposerEnvironment.open(tester, initial: selectorExecution(execution: composerExecution));
    await fixture.pump(tester);
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), 'retained draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    final call = await pumpClientFuture(tester, fixture.env.commands.interrupts.at(0), 'Escape native stop');
    expect(call.executionId, composerExecution.id);
    await tester.pump();
    final view = tester.widget<ComposerView>(find.byType(ComposerView));
    expect(view.primaryAction.enabled, isFalse, reason: '在途停止也阻止发送');
    expect(fixture.state.stop!.accepted, isFalse);
    expect(find.byKey(StudioDriverKeys.composerStopping), findsNothing);
    expect(find.byKey(StudioDriverKeys.composerPending), findsOneWidget, reason: '在途请求仍保留main的进度反馈，但不冒充已受理');
    expect(fixture.env.drafts.composer(composerThreadId).state.value.text, 'retained draft');
    await _acceptStop(tester, fixture);
    expect(find.byKey(const ValueKey('composer-stopping-disabled')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.pump(tester);
    expect(find.byKey(const ValueKey('composer-stopping-disabled')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-stop-unconfirmed')), findsNothing);
    expect(fixture.state.stop!.operation!.id, call.operationId);
    await fixture.publish(tester, selectorExecution());
  });

  testWidgets('Unknown 不假受理、不按旧计时器重发；重建仍观察原操作', (tester) async {
    final fixture = await ComposerEnvironment.open(tester, initial: selectorExecution(execution: composerExecution));
    await fixture.pump(tester);
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    final call = await pumpClientFuture(tester, fixture.env.commands.interrupts.at(0), 'unknown stop entered');
    call.reply.completeError(StateError('native reply lost after dispatch'));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.stop?.unknown == true), 'original Unknown');
    await tester.pump();
    expect(fixture.state.stop!.accepted, isFalse);
    expect(find.byKey(const ValueKey('composer-stop-unconfirmed')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.pump(tester);
    expect(fixture.state.stop!.operation!.id, call.operationId);
    expect(fixture.vm.captureStop(fixture.page), isNull);
    expect(fixture.env.commands.interrupts.values, hasLength(1));
    // Terminal canonical evidence, not a clock, releases the original SDK owner.
    await fixture.publish(tester, selectorExecution());
  });

  testWidgets('受理状态跨重建保持，迟到旧回执不污染新 execution', (tester) async {
    final fixture = await ComposerEnvironment.open(tester, initial: selectorExecution(execution: composerExecution));
    await fixture.pump(tester);
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    final call = await pumpClientFuture(tester, fixture.env.commands.interrupts.at(0), 'original stop entered');
    await fixture.publish(tester, selectorExecution(execution: composerExecution.copyWith(id: 'new-execution')));
    call.reply.complete(StopExecutionReply(threadId: call.threadId, executionId: call.executionId, stopped: true, receipt: composerReceipt(call.operationId)));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.stop?.operation?.receipt != null), 'late original receipt');
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.pump(tester);
    final action = fixture.vm.primaryAction(hasContent: false, submissionPending: false);
    expect(action.kind, ComposerPrimaryActionKind.stop);
    expect(action.enabled, isTrue, reason: '旧 accepted 不锁住新 target');
    expect(fixture.env.commands.interrupts.values, hasLength(1));
    await fixture.publish(tester, selectorExecution());
  });

  testWidgets('Unknown继续不假accepted；显式原操作读取才可恢复Pending并且绝不重发', (tester) async {
    final fixture = await ComposerEnvironment.open(tester, initial: selectorExecution(continuation: composerContinuation));
    await fixture.pump(tester);
    await tester.tap(find.byKey(StudioDriverKeys.composerContinue));
    final call = await pumpClientFuture(tester, fixture.env.commands.continues.at(0), 'unknown continuation dispatch');
    call.reply.completeError(StateError('lost continuation reply'));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.continuation?.unknown == true), 'unknown continuation projection');
    await tester.pump();
    expect(fixture.state.continuation!.accepted, isFalse);
    expect(fixture.vm.primaryAction(hasContent: false, submissionPending: false).kind, ComposerPrimaryActionKind.continueConversation);
    expect(fixture.vm.primaryAction(hasContent: false, submissionPending: false).enabled, isFalse);
    expect(find.byKey(const ValueKey('composer-continuing-disabled')), findsNothing);
    var recovered = composerContinuationView(call);
    fixture.env.commands.continuationQuery = (thread, operation) async {
      expect((thread, operation), (call.threadId, call.operationId));
      return recovered;
    };
    await pumpClientFuture(tester, fixture.vm.captureContinuationRead()!(), 'recover same operation Pending');
    expect(fixture.state.continuation!.accepted, isTrue);
    expect(fixture.vm.primaryAction(hasContent: false, submissionPending: false).kind, ComposerPrimaryActionKind.continuing);
    recovered = composerContinuationView(call, state: const ContinuationOperationState.discarded());
    await pumpClientFuture(tester, fixture.vm.captureContinuationRead()!(), 'settle recovered original operation');
    expect(fixture.env.commands.continues.values, hasLength(1));
    expect(fixture.env.commands.acceptances.values, isEmpty);
  });

  for (final terminal in const <ContinuationOperationState>[
    ContinuationOperationState.consumed(turnId: 'continued-turn'),
    ContinuationOperationState.discarded(),
  ]) {
  testWidgets('recovered Pending durable+observed 在无 execution/point 时仍 disabled continuing；${terminal.runtimeType} 解锁', (tester) async {
    final fixture = await ComposerEnvironment.open(tester, initial: selectorExecution(continuation: composerContinuation));
    await fixture.pump(tester);
    await tester.tap(find.byKey(StudioDriverKeys.composerContinue));
    final call = await pumpClientFuture(tester, fixture.env.commands.continues.at(0), 'continuation dispatch');
    var nativeView = composerContinuationView(call);
    fixture.env.commands.continuationQuery = (thread, operation) async {
      expect((thread, operation), (call.threadId, call.operationId));
      return nativeView;
    };
    call.reply.complete(ContinueThreadReply(threadId: call.threadId, inputId: call.operationId.value, continuationId: call.continuationId, cursor: 7, receipt: composerReceipt(call.operationId)));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.continuation?.accepted == true), 'accepted continuation');
    await pumpClientFuture(tester, fixture.vm.captureContinuationRead()!(), 'read durable Pending');
    await fixture.publish(tester, selectorExecution());
    await tester.pump();
    expect(fixture.state.continuation!.recovered!.durable, isTrue);
    expect(fixture.state.continuation!.operation!.observed, isTrue);
    expect(fixture.state.continuation!.inProgress, isTrue);
    expect(fixture.vm.primaryAction(hasContent: true, submissionPending: false).kind, ComposerPrimaryActionKind.continuing);
    expect(find.byKey(const ValueKey('composer-continuing-disabled')), findsOneWidget);
      nativeView = composerContinuationView(call, state: terminal);
      await pumpClientFuture(tester, fixture.vm.captureContinuationRead()!(), 'read typed terminal continuation');
      await tester.pump();
      expect(fixture.state.continuation!.accepted, isTrue, reason: '历史受理事实仍保留');
      expect(fixture.state.continuation!.inProgress, isFalse);
      expect(fixture.vm.primaryAction(hasContent: true, submissionPending: false).kind, ComposerPrimaryActionKind.send);
    expect(fixture.env.commands.continues.values, hasLength(1));
    expect(fixture.env.commands.acceptances.values, isEmpty);
  });

  }

  testWidgets('受限尺寸下三类原因同时存在，84px 原因区可访问，主按钮保持40px', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await ComposerEnvironment.open(tester, initial: selectorExecution(execution: composerExecution));
    await fixture.pump(tester);
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    final call = await pumpClientFuture(tester, fixture.env.commands.interrupts.at(0), 'failure before reason layout');
    call.reply.completeError(const CommandDispatchFailure.rejected(failure: _failure));
    await pumpClientFuture(tester, fixture.waitFor((state) => state.stop?.failure != null), 'failure displayed');
    await fixture.publish(tester, selectorExecution(continuation: composerContinuation).copyWith(storage: _storage));
    await tester.pump();
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), 'geometry draft');
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('composer-reasons'))).height, lessThanOrEqualTo(84));
    for (final key in const ['composer-blocker', 'composer-stop-failure', 'composer-continuation-reason']) {
      final reason = find.byKey(ValueKey(key));
      expect(reason, findsOneWidget, reason: key);
      await tester.ensureVisible(reason);
      expect(tester.getSize(reason).height, greaterThan(0));
    }
    final button = find.byKey(const ValueKey('composer-submit-disabled'));
    expect(tester.getSize(button), const Size(40, 40));
    expect(tester.takeException(), isNull);
  });
}
