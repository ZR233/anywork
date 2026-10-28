import 'dart:async';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/conversation/connectors/interaction_connector.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/state/interaction_view_state.dart';
import 'package:anywork/src/features/conversation/view_models/interaction_view_model.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/hosted_interaction_environment.dart';
import 'support/pump_client_future.dart';

const _readFailure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'hosted detail unavailable',
  retryable: true,
  correlationId: 'hosted-read',
);
const _rejected = StudioFailure(
  code: StudioFailureCode.staleRevision,
  message: 'interaction revision advanced',
  retryable: false,
  correlationId: 'hosted-rejected',
  details: StudioFailureDetails.reason(reason: 'staleInteraction'),
);

Future<HostedInteractionEnvironment> _open(
  WidgetTester tester, {
  String host = hostedHost,
}) async {
  late HostedInteractionEnvironment env;
  await tester.runAsync(() async {
    env = HostedInteractionEnvironment(host: host);
    await env.establish();
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(tester, env.close(), 'hosted owner cleanup');
  });
  return env;
}

InteractionViewState _state(
  HostedInteractionEnvironment env,
  InteractionEditorKey key,
) => env.container.read(interactionViewModelProvider(key)).requireValue;
InteractionViewModel _vm(
  HostedInteractionEnvironment env,
  InteractionEditorKey key,
) => env.container.read(interactionViewModelProvider(key).notifier);
Future<InteractionViewState> _wait(
  HostedInteractionEnvironment env,
  InteractionEditorKey key,
  bool Function(InteractionViewState) matches,
) {
  final done = Completer<InteractionViewState>();
  final observation = env.container.listen(interactionViewModelProvider(key), (
    _,
    next,
  ) {
    final value = next.asData?.value;
    if (value != null && !done.isCompleted && matches(value)) {
      done.complete(value);
    }
  }, fireImmediately: true);
  return done.future.whenComplete(observation.close);
}

Future<void> _mount(
  WidgetTester tester,
  HostedInteractionEnvironment env,
  InteractionEditorKey key,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: env.container,
      child: MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: InteractionConnector(target: key, enabled: true),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  HostedInteractionEnvironment env,
  InteractionEditorKey key,
) async {
  await _mount(tester, env, key);
  await pumpClientFuture(
    tester,
    env.container.read(interactionViewModelProvider(key).future),
    'hosted initial detail',
  );
  await pumpClientFuture(
    tester,
    _vm(env, key).completeRead(),
    'hosted complete bounded detail',
  );
  await tester.pump();
}

Future<HostedResponse> _answer(
  WidgetTester tester,
  HostedInteractionEnvironment env,
  InteractionEditorKey key,
) async {
  await tester.enterText(
    find.byKey(StudioDriverKeys.userInputFirstText),
    'Use the safe path',
  );
  await tester.tap(find.byKey(StudioDriverKeys.userInputSubmit));
  return pumpClientFuture(
    tester,
    env.commands.calls.at(0),
    'hosted response native entry',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('root展示来源明确的child问答/审批，冻结host/ref/origin与真target；普通root走普通能力', (
    tester,
  ) async {
    final env = await _open(tester);
    final key = env.key('qa');
    expect(
      (key.threadId, key.target, key.hostedReference, key.hostedOrigin),
      (
        hostedHost,
        hostedChild,
        const InteractionReadRef(entry: 1, revision: 1),
        env.origin,
      ),
    );
    await _pump(tester, env, key);
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('qa')),
      findsOneWidget,
    );
    expect(find.textContaining('root/reviewer'), findsOneWidget);
    final call = await _answer(tester, env, key);
    expect(
      (call.host, call.interactionId, call.revision),
      (hostedHost, 'qa', 1),
    );
    expect(
      (call.resolution as UserInputResolutionCommand).answers.single.answers,
      ['Use the safe path'],
    );
    expect(env.reads.values.every((read) => read.host == hostedHost), isTrue);
    call.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _rejected),
    );
    await pumpClientFuture(
      tester,
      _wait(env, key, (state) => state.submissionError != null),
      'rejected question remains editable',
    );

    final approval = env.key('approval');
    await _pump(tester, env, approval);
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('approval')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(StudioDriverKeys.toolApprove));
    final approving = await pumpClientFuture(
      tester,
      env.commands.calls.at(1),
      'typed hosted approval',
    );
    expect(
      approving.resolution,
      const InteractionResolutionCommand.toolApproval(
        decision: ToolApprovalDecision.approved,
        reason: null,
      ),
    );
    expect((approving.host, approving.revision), (hostedHost, 1));
    approving.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _rejected),
    );
    await pumpClientFuture(
      tester,
      _wait(env, approval, (state) => state.submissionError != null),
      'approval rejection',
    );

    final root = env.key('root-qa');
    expect(root.isHosted, isFalse);
    expect(root.target, hostedHost);
    await _pump(tester, env, root);
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('root-qa')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(StudioDriverKeys.userInputFirstText),
      'Root answer',
    );
    await tester.tap(find.byKey(StudioDriverKeys.userInputSubmit));
    final rootCall = await pumpClientFuture(
      tester,
      env.commands.calls.at(2),
      'ordinary root response',
    );
    expect(rootCall.host, hostedHost);
    expect(rootCall.interactionId, 'root-qa');
    rootCall.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _rejected),
    );
    await pumpClientFuture(
      tester,
      _wait(env, root, (state) => state.submissionError != null),
      'ordinary response rejection',
    );
  });

  testWidgets('决定被拒绝保留原卡片、typed原因和Dirty输入，重建不丢编辑', (tester) async {
    final env = await _open(tester);
    final key = env.key('qa');
    await _pump(tester, env, key);
    final call = await _answer(tester, env, key);
    call.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _rejected),
    );
    await pumpClientFuture(
      tester,
      _wait(env, key, (state) => state.submissionError != null),
      'hosted rejection',
    );
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('qa')),
      findsOneWidget,
    );
    expect(
      _state(env, key).submission!.failurePhase,
      OperationFailurePhase.rejected,
    );
    expect(_state(env, key).answers[0]!.text, 'Use the safe path');
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, env, key);
    expect(
      tester
          .widget<TextField>(find.byKey(StudioDriverKeys.userInputFirstText))
          .controller!
          .text,
      'Use the safe path',
    );
    expect(env.commands.calls.values, hasLength(1));
  });

  testWidgets('reply先于newindex：受理未观察绝不显示saved，可靠facts与真read两道屏障独立', (
    tester,
  ) async {
    final env = await _open(tester);
    final key = env.key('qa');
    await _pump(tester, env, key);
    final call = await _answer(tester, env, key);
    env.resolutions[(env.host, 'qa')] = call.resolution;
    final terminalReadGate = env.gates[(env.host, 1, 2)] = Completer<void>();
    call.reply.complete(env.reply(call));
    await pumpClientFuture(
      tester,
      _wait(env, key, (state) => state.submission?.receipt != null),
      'accepted before new index',
    );
    await tester.pump();
    expect(_state(env, key).submission!.observed, isFalse);
    expect(
      env.headerReads.values.where((read) => read.reference.revision == 2),
      isEmpty,
      reason: '不能用回复自行制造new index的read ref',
    );
    expect(
      find.text(
        'The answer is saved. The main agent decides whether this member continues.',
      ),
      findsNothing,
    );
    expect(
      find.text(
        'The original permission wait is decided. The original call may continue when it was approved, and is not executed when it was denied.',
      ),
      findsNothing,
    );
    final nextRead = env.headerReads.values.length;
    await pumpClientFuture(
      tester,
      env.publishResolved('qa'),
      'reliable terminal index facts',
    );
    final read = await pumpClientFuture(
      tester,
      env.headerReads.at(nextRead),
      'terminal detail actually entered',
    );
    expect(
      (read.host, read.reference.entry, read.reference.revision),
      (hostedHost, 1, 2),
    );
    expect(_state(env, key).submission!.observed, isFalse);
    terminalReadGate.complete();
    await pumpClientFuture(
      tester,
      _wait(env, key, (state) => state.submission?.observed == true),
      'real terminal detail observation',
    );
    await tester.pump();
    expect(
      find.text(
        'The answer is saved. The main agent decides whether this member continues.',
      ),
      findsOneWidget,
    );
    expect(env.commands.calls.values, hasLength(1));
  });

  testWidgets('决议后canonical读取失败不假保存，显式重读只查原操作，不重发决定', (tester) async {
    final env = await _open(tester);
    final key = env.key('qa');
    await _pump(tester, env, key);
    final call = await _answer(tester, env, key);
    env.resolutions[(env.host, 'qa')] = call.resolution;
    env.failures[(env.host, 1, 2)] = _readFailure;
    call.reply.complete(env.reply(call));
    await pumpClientFuture(
      tester,
      _wait(env, key, (state) => state.submission?.receipt != null),
      'accepted decision',
    );
    await pumpClientFuture(
      tester,
      env.publishResolved('qa'),
      'terminal index before failed read',
    );
    await pumpClientFuture(
      tester,
      _wait(
        env,
        key,
        (state) =>
            state.submission?.failurePhase == OperationFailurePhase.syncFailed,
      ),
      'real terminal read failure',
    );
    await tester.pump();
    expect(
      find.text(
        'The answer is saved. The main agent decides whether this member continues.',
      ),
      findsNothing,
    );
    expect(_state(env, key).submission!.observed, isFalse);
    env.failures.remove((env.host, 1, 2));
    await pumpClientFuture(
      tester,
      _vm(env, key).retrySubmissionRead(),
      'explicit original-operation read retry',
    );
    await tester.pump();
    expect(_state(env, key).submission!.observed, isTrue);
    expect(env.commands.calls.values, hasLength(1));
  });

  testWidgets('初次读取失败页面内可重试，读取成功仍绑定原hosted来源', (tester) async {
    final env = await _open(tester);
    final key = env.key('qa');
    env.failures[(env.host, 1, 1)] = _readFailure;
    await _pump(tester, env, key);
    expect(_state(env, key).readIssues.single.error, _readFailure);
    env.failures.remove((env.host, 1, 1));
    await pumpClientFuture(
      tester,
      _vm(env, key).retryRead(),
      'retry exact hosted detail',
    );
    await pumpClientFuture(
      tester,
      _vm(env, key).completeRead(),
      'complete retried hosted material',
    );
    await tester.pump();
    expect(_state(env, key).readIssues, isEmpty);
    expect(_state(env, key).key, key);
    expect(find.byKey(StudioDriverKeys.userInputFirstText), findsOneWidget);
    expect(env.commands.calls.values, isEmpty);
  });

  testWidgets('切换宿主时旧读取与lateACK仅结算原能力，不污染新宿主', (tester) async {
    final old = await _open(tester);
    final oldKey = old.key('qa');
    await _pump(tester, old, oldKey);
    final oldCall = await _answer(tester, old, oldKey);
    await pumpClientFuture(
      tester,
      old.selectHost('thread-alt'),
      'same Repository switches host',
    );
    final next = old;
    final nextKey = next.key('qa');
    await _pump(tester, next, nextKey);
    oldCall.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _rejected),
    );
    await pumpClientFuture(
      tester,
      old.operations.observations
          .lookup(oldCall.operationId)!
          .state
          .waitFor(
            (state) => state.failurePhase == OperationFailurePhase.rejected,
          ),
      'old exact operation ACK',
    );
    await tester.pump();
    expect(_state(next, nextKey).key.threadId, 'thread-alt');
    expect(_state(next, nextKey).submission, isNull);
    expect(_state(next, nextKey).answers, isEmpty);
    expect(next.commands.calls.values, hasLength(1));
    expect(old.commands.calls.values.single.host, hostedHost);
  });

  testWidgets('同一Repository切换宿主时旧read先进入屏障，迟到结束不覆盖新宿主卡片', (tester) async {
    final env = await _open(tester);
    final oldKey = env.key('qa');
    final gate = env.gates[(hostedHost, 1, 1)] = Completer<void>();
    final nextRead = env.headerReads.values.length;
    final hold = env.container.listen(
      interactionViewModelProvider(oldKey),
      (_, _) {},
    );
    addTearDown(hold.close);
    final originalRead = env.container.read(
      interactionViewModelProvider(oldKey).future,
    );
    await _mount(tester, env, oldKey);
    final entered = await pumpClientFuture(
      tester,
      env.headerReads.at(nextRead),
      'original host header actually entered',
    );
    expect(
      (entered.host, entered.reference),
      (hostedHost, const InteractionReadRef(entry: 1, revision: 1)),
    );
    await pumpClientFuture(
      tester,
      env.selectHost('thread-alt'),
      'new host actual source and bounded index',
    );
    final nextKey = env.key('qa');
    await _pump(tester, env, nextKey);
    expect(_state(env, nextKey).key.threadId, 'thread-alt');
    gate.complete();
    await pumpClientFuture(tester, originalRead, 'late original read joined');
    await tester.pump();
    expect(_state(env, nextKey).key, nextKey);
    expect(
      _state(env, nextKey).header!.threadId,
      const ReadText.inline(text: 'thread-alt-child'),
    );
    expect(_state(env, nextKey).answers, isEmpty);
    expect(env.commands.calls.values, isEmpty);
  });

  testWidgets('child计划即使有header/ref也不是主会话可决议卡片', (tester) async {
    final env = await _open(tester);
    final key = InteractionEditorKey(
      threadId: env.host,
      runtimeEpoch: hostedEpoch,
      incarnation: 1,
      sourceGeneration: env.key('qa').sourceGeneration,
      interactionId: 'child-plan',
      revision: 1,
      targetThreadId: hostedChild,
      hostedReference: const InteractionReadRef(entry: 4, revision: 1),
      hostedOrigin: env.origin,
    );
    await _pump(tester, env, key);
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('child-plan')),
      findsNothing,
    );
    expect(find.byKey(StudioDriverKeys.planApprove), findsNothing);
    expect(find.byKey(StudioDriverKeys.userInputSubmit), findsNothing);
    await pumpClientFuture(
      tester,
      _vm(env, key).approvePlan(),
      'child plan cannot decide',
    );
    expect(env.commands.calls.values, isEmpty);
  });

  testWidgets('420x360受限窗口中child问答与审批动作可滚动访问且不溢出', (tester) async {
    tester.view.physicalSize = const Size(420, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final env = await _open(tester);
    await _pump(tester, env, env.key('qa'));
    await tester.enterText(
      find.byKey(StudioDriverKeys.userInputFirstText),
      'Long answer remains accessible in a constrained window',
    );
    final submit = find.byKey(StudioDriverKeys.userInputSubmit);
    await tester.ensureVisible(submit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await _pump(tester, env, env.key('approval'));
    await tester.ensureVisible(find.byKey(StudioDriverKeys.toolApprove));
    expect(
      tester
          .widget<FilledButton>(find.byKey(StudioDriverKeys.toolApprove))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    expect(env.commands.calls.values, isEmpty);
  });
}
