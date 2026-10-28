import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

/// Holds the demo Turn in its running phase so the stop target is stable while
/// the command runs. Everything else is the real demo transport.
class _HeldTurnTransport extends RecordingDemoTransport {
  @override
  Duration get promptStartDelay => const Duration(seconds: 2);

  @override
  Duration get promptActivityDelay => const Duration(seconds: 2);
}

void main() {
  test('stop targets the demo execution identity and continue opens exactly one new Turn', () async {
    final transport = _HeldTurnTransport();
    final client = AnyworkClient(
      transport: transport,
      clientId: 'stop-continue',
    );
    addTearDown(
      () => client.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    await client.bootstrap();
    // Demo's root session; bootstrap only loads the directory and settings.
    const threadId = 'thread-main';
    client.selection.selectThread(
      projectId: client.selection.state.selectedProjectId!,
      threadId: threadId,
    );
    final session = client.session(threadId);
    // The saved model route is the CAS baseline of an explicit continue.
    await session.source.waitFor((state) => state.runtime?.modelRoute != null);
    await client.threadCommands.submitComposer(
      threadId,
      const StudioPromptInput(
        inputId: 'input-1',
        text: 'run the demo task',
        attachmentDraftIds: [],
      ),
      expectedModelRouteRevision: session.state.runtime!.modelRoute!.revision,
    );
    await session.source.waitFor((state) => state.runtime?.execution != null);
    final execution = session.state.runtime!.execution!;
    expect(execution.phase, AgentExecutionPhase.running);
    expect(execution.turnId, isNotNull);

    await client.threadCommands.stop(threadId);
    expect(
      client.mutations.latest('stop:$threadId')!.state.value.receipt,
      isNotNull,
      reason: 'The stop is accepted with the frozen execution identity',
    );
    await session.source.waitFor((state) => state.runtime?.execution == null);
    expect(
      client.mutations.latest('stop:$threadId')!.state.value.observed,
      isTrue,
    );
    expect(
      client.threadCommands.state.commands.containsKey('stop:$threadId'),
      isFalse,
    );

    // The interrupted work left a continuation point in the canonical runtime
    // projection: an explicit continue is the only user path to a new Turn.
    await session.source.waitFor(
      (state) => state.runtime?.continuation != null,
    );
    final point = client.threadCommands.continuation(threadId)!;
    expect(point.claimed, isFalse);
    expect(point.reason, ContinuationReason.userStop);
    expect(point.sourceTurnId, isNotNull);
    final continued = await client.threadCommands.continueThread(
      threadId,
      point,
      expectedModelRouteRevision: session.state.runtime!.modelRoute!.revision,
    );
    expect(continued.threadId, threadId);
    expect(
      continued.inputId,
      continued.receipt.operationId.value,
      reason: 'The control input identity is the operation identity',
    );
    await session.source.waitFor((state) => state.runtime?.execution != null);
    expect(
      client.mutations
          .lookup(continued.receipt.operationId)!
          .state
          .value
          .observed,
      isTrue,
      reason: 'The canonical new Turn proves the continuation took effect',
    );
    final view = await client.threadCommands.readContinuationOperation(
      threadId,
      continued.receipt.operationId.value,
    );
    expect(view.continuationId, point.id);
    expect(
      client.composer(threadId).state.draft,
      isEmpty,
      reason: 'A content-free continuation never writes a user draft',
    );
  });

  test('准入后的继续被报告为已消费并绑定接续轮次', () async {
    final transport = RecordingDemoTransport();
    final client = AnyworkClient(
      transport: transport,
      clientId: 'continue-consumed',
    );
    addTearDown(
      () => client.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    await client.bootstrap();
    const threadId = 'thread-main';
    client.selection.selectThread(
      projectId: client.selection.state.selectedProjectId!,
      threadId: threadId,
    );
    final session = client.session(threadId);
    await session.source.waitFor((state) => state.runtime?.modelRoute != null);
    await client.threadCommands.submitComposer(
      threadId,
      const StudioPromptInput(
        inputId: 'input-consumed',
        text: 'run the demo task',
        attachmentDraftIds: [],
      ),
      expectedModelRouteRevision: session.state.runtime!.modelRoute!.revision,
    );
    await session.source.waitFor((state) => state.runtime?.execution != null);
    await client.threadCommands.stop(threadId);
    await session.source.waitFor(
      (state) => state.runtime?.continuation != null,
    );
    final point = client.threadCommands.continuation(threadId)!;

    final continued = await client.threadCommands.continueThread(
      threadId,
      point,
      expectedModelRouteRevision: session.state.runtime!.modelRoute!.revision,
    );
    await session.source.waitFor((state) => state.runtime?.execution != null);
    // 演示的准入发生在准备延迟之后：在有限预算内观察同一事实，不用固定等待。
    var view = await client.threadCommands.readContinuationOperation(
      threadId,
      continued.receipt.operationId.value,
    );
    for (
      var attempt = 0;
      attempt < 200 && view.state is PendingContinuation;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      view = await client.threadCommands.readContinuationOperation(
        threadId,
        continued.receipt.operationId.value,
      );
    }
    expect(view.state, isA<ConsumedContinuation>(), reason: '准入即消费，不等整轮完成');
    expect(
      (view.state as ConsumedContinuation).turnId,
      session.state.runtime!.execution!.turnId,
      reason: '消费事实绑定实际接续的轮次',
    );
  });

  test('同一操作身份用于不同请求时明确冲突，不继承别人的回执', () async {
    final transport = _HeldTurnTransport();
    final client = AnyworkClient(
      transport: transport,
      clientId: 'continue-identity',
    );
    addTearDown(
      () => client.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    await client.bootstrap();
    const threadId = 'thread-main';
    client.selection.selectThread(
      projectId: client.selection.state.selectedProjectId!,
      threadId: threadId,
    );
    final session = client.session(threadId);
    await session.source.waitFor((state) => state.runtime?.modelRoute != null);
    await client.threadCommands.submitComposer(
      threadId,
      const StudioPromptInput(
        inputId: 'input-identity',
        text: 'run the demo task',
        attachmentDraftIds: [],
      ),
      expectedModelRouteRevision: session.state.runtime!.modelRoute!.revision,
    );
    await session.source.waitFor((state) => state.runtime?.execution != null);
    await client.threadCommands.stop(threadId);
    await session.source.waitFor(
      (state) => state.runtime?.continuation != null,
    );
    final point = client.threadCommands.continuation(threadId)!;
    final revision = session.state.runtime!.modelRoute!.revision;

    const operation = OperationId('op-identity');
    await transport.continueThread(
      threadId,
      point.id,
      expectedModelRouteRevision: revision,
      operationId: operation,
    );
    await expectLater(
      transport.continueThread(
        threadId,
        'another-point',
        expectedModelRouteRevision: revision,
        operationId: operation,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.conflict,
        ),
      ),
    );
  });

  test('准入前停止的继续不被报告为已消费', () async {
    final transport = _HeldTurnTransport();
    final client = AnyworkClient(
      transport: transport,
      clientId: 'continue-before-admission',
    );
    addTearDown(
      () => client.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    await client.bootstrap();
    const threadId = 'thread-main';
    client.selection.selectThread(
      projectId: client.selection.state.selectedProjectId!,
      threadId: threadId,
    );
    final session = client.session(threadId);
    await session.source.waitFor((state) => state.runtime?.modelRoute != null);
    await client.threadCommands.submitComposer(
      threadId,
      const StudioPromptInput(
        inputId: 'input-early-stop',
        text: 'run the demo task',
        attachmentDraftIds: [],
      ),
      expectedModelRouteRevision: session.state.runtime!.modelRoute!.revision,
    );
    await session.source.waitFor((state) => state.runtime?.execution != null);
    await client.threadCommands.stop(threadId);
    await session.source.waitFor(
      (state) => state.runtime?.continuation != null,
    );
    final point = client.threadCommands.continuation(threadId)!;

    final continued = await transport.continueThread(
      threadId,
      point.id,
      expectedModelRouteRevision: session.state.runtime!.modelRoute!.revision,
      operationId: const OperationId('op-early-stop'),
    );
    await session.source.waitFor((state) => state.runtime?.execution != null);
    final running = session.state.runtime!.execution!;
    await transport.stopThread(
      threadId,
      running.id,
      operationId: const OperationId('stop-before-admission'),
    );
    final view = await client.threadCommands.readContinuationOperation(
      threadId,
      continued.receipt.operationId.value,
    );
    expect(view.state, isA<PendingContinuation>(), reason: '准入前取消不得冒充已消费');
  });
}
