import 'dart:async';

import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/conversation/state/conversation_view_state.dart';
import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/conversation_stop_native.dart';
import '../../../../anywork_client/test/support/profile_recovery_port.dart';
import '../../../../anywork_client/test/support/workspace_port_fixture.dart';

final class _StateWait {
  _StateWait(this.matches);
  final bool Function(ConversationViewState) matches;
  final done = Completer<ConversationViewState>();
}

/// A generated production VM with real Conversation, Workspace and operation
/// owners. Only the native ports are scripted; no Session/ticket is replaced.
final class ConversationStopViewModelFixture {
  ConversationStopViewModelFixture(this.stop, this.initial) {
    recovery = createRecoveryRepository(
      port: recoveryPort,
      budget: stop.budget,
      operations: stop.owner.operations,
    );
    workspace = createWorkspaceRepository(
      port: workspacePort,
      budget: stop.budget,
      operations: stop.owner.operations,
      recovery: recovery.state,
      archiveCapture: stop.owner.archive,
    ).repository;
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        conversationRepositoryProvider.overrideWithValue(stop.owner.repository),
        workspaceRepositoryProvider.overrideWithValue(workspace),
      ],
    );
    subscription = container.listen(
      conversationViewModelProvider(initial.session.threadId),
      (_, next) {
        if (next.asData?.value case final value?) {
          for (final waiting in List.of(_waiting)) {
            if (waiting.matches(value)) {
              _waiting.remove(waiting);
              waiting.done.complete(value);
            }
          }
        }
      },
      fireImmediately: true,
    );
  }

  final StopFixture stop;
  final StopSource initial;
  final workspacePort = ScriptedWorkspacePort();
  final recoveryPort = ProfileRecoveryPort();
  late final RecoveryRepository recovery;
  late final WorkspaceRepository workspace;
  late final ProviderContainer container;
  late final ProviderSubscription<AsyncValue<ConversationViewState>>
  subscription;
  final _waiting = <_StateWait>[];
  bool _disposed = false;

  ConversationViewModel get vm => container.read(
    conversationViewModelProvider(initial.session.threadId).notifier,
  );
  ConversationViewState get state => container
      .read(conversationViewModelProvider(initial.session.threadId))
      .requireValue;

  static Future<ConversationStopViewModelFixture> create() async {
    final stop = StopFixture();
    final initial = await stop.select(threadId: 'A');
    final fixture = ConversationStopViewModelFixture(stop, initial);
    addTearDown(fixture.close);
    await fixture.container.read(conversationViewModelProvider('A').future);
    final metadata = await fixture.workspacePort.firstThreadOpen.future;
    final native = metadata.accept();
    await native.feed.listened.future;
    // Metadata deliberately remains Unknown. The native Execution baseline
    // declares an empty index (total=0), which the real domain owner can finish
    // without opening an identity read. It is not an unscripted read failure.
    await fixture.vm.loadInteractions();
    await fixture.waitFor(
      (state) => !state.indexLoading && state.interactions?.current != null,
    );
    expect(fixture.state.indexError, isNull);
    expect(fixture.state.interactions!.current!.items, isEmpty);
    return fixture;
  }

  Future<ConversationViewState> waitFor(
    bool Function(ConversationViewState) matches,
  ) {
    final current = state;
    if (matches(current)) return Future.value(current);
    final waiting = _StateWait(matches);
    _waiting.add(waiting);
    return waiting.done.future;
  }

  Future<
    ({Future<void> settled, StopInterrupt call, OperationObservation operation})
  >
  dispatch(ConversationStopPage page) async {
    final callback = vm.captureStop(page);
    expect(callback, isNotNull);
    final settled = callback!();
    await stop.reads.at(0);
    await stop.acceptRead(0);
    await Future.any<void>([
      stop.commands.interrupts.at(0).then<void>((_) {}),
      settled.then<void>(
        (_) => fail(
          'A current busy target must reach the real native command boundary',
        ),
      ),
    ]);
    final call = await stop.commands.interrupts.at(0);
    final operation = stop.owner.operations.observations.lookup(
      call.operationId,
    )!;
    return (settled: settled, call: call, operation: operation);
  }

  void disposePresentation() {
    if (_disposed) return;
    _disposed = true;
    subscription.close();
    container.dispose();
  }

  Future<void> close() async {
    disposePresentation();
    workspacePort.releasePending();
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final reports = await Future.wait([
      workspace.close(deadline: deadline),
      recovery.close(deadline: deadline),
    ]);
    expect([for (final report in reports) ...report.unresolved], isEmpty);
    // Native helpers contain no package:test dependency. Framework assertions
    // stay in this Flutter wrapper and check initial cleanup separately from
    // retry; neither a fake ticket nor manual permit release hides pending work.
    expect((await stop.close(deadline: deadline)).complete, isTrue);
    expect(
      (await stop.owner.repository.retryCleanup(deadline: deadline)).complete,
      isTrue,
    );
    expect(stop.budget.usage, isEmpty);
  }
}

void acceptStop(StopInterrupt call) {
  call.reply.complete(
    InterruptTurnReply(
      threadId: call.threadId,
      turnId: call.turnId,
      interrupted: true,
      receipt: stopReceipt(call.operationId),
    ),
  );
}
