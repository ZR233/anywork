import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_permission_view_model.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_client_future.dart';
import 'acp_components_support.dart';

void main() {
  for (final scenario in [
    (fails: false, dispose: false, newerFailed: false),
    (fails: true, dispose: false, newerFailed: false),
    (fails: false, dispose: false, newerFailed: true),
    (fails: true, dispose: false, newerFailed: true),
    (fails: false, dispose: true, newerFailed: false),
    (fails: true, dispose: true, newerFailed: false),
  ]) {
    testWidgets('permission late ${scenario.fails ? 'failure' : 'success'} '
        '${scenario.dispose
            ? 'after disposal does not write'
            : scenario.newerFailed
            ? 'preserves a newer failure'
            : 'cannot settle a newer decision'}', (tester) async {
      final harness = await AcpComponentHarness.create();
      addTearDown(() => harness.close(tester));
      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(harness.graph)],
      );
      var disposed = false;
      void dispose() {
        if (disposed) return;
        disposed = true;
        container.dispose();
      }

      addTearDown(dispose);
      final firstResult = Completer<void>();
      final secondResult = Completer<void>();
      addTearDown(() {
        if (!firstResult.isCompleted) firstResult.complete();
        if (!secondResult.isCompleted) secondResult.complete();
      });
      final provider = acpPermissionViewModelProvider('thread');
      var notifications = 0;
      container.listen(provider, (_, _) => notifications++);
      final first = _permission(1);
      final second = _permission(2);
      harness.emit(first);
      await pumpClientUntil(
        tester,
        () => container.read(provider).activeRequest?.id == '19:1',
        'observe permission A',
      );
      final model = container.read(provider.notifier);
      harness.port.answerResult = firstResult;
      final firstDecision = model.answer('19:1', 'allow');
      await pumpClientUntil(
        tester,
        () =>
            harness.port.calls
                .where((c) => c.$1 == 'answerPermission')
                .length ==
            1,
        'submit permission A',
      );

      if (scenario.dispose) {
        dispose();
        final beforeCompletion = notifications;
        _complete(firstResult, fails: scenario.fails);
        await pumpClientFuture(
          tester,
          firstDecision,
          'settle disposed decision',
        );
        expect(notifications, beforeCompletion);
        expect(tester.takeException(), isNull);
        return;
      }

      // A real completion frame retires the old permission queue while A's
      // boundary call is still awaiting its independent reply.
      harness.emit(
        AcpCompletedEventView(
          AcpCompletedRunView(
            run: AcpRunIdView(instance: BigInt.from(19), sequence: BigInt.one),
            completionSequence: BigInt.one,
            result: const AcpSuccessView(
              AcpPromptResponseView(stopReason: AcpStopReasonView.endTurn),
            ),
            summary: '',
            truncated: false,
          ),
        ),
      );
      harness.emit(second);
      await pumpClientUntil(
        tester,
        () => container.read(provider).activeRequest?.id == '19:2',
        'replace permission A with B',
      );
      harness.port.answerResult = secondResult;
      final secondDecision = model.answer('19:2', 'allow');
      await pumpClientUntil(
        tester,
        () =>
            harness.port.calls
                .where((c) => c.$1 == 'answerPermission')
                .length ==
            2,
        'submit permission B',
      );
      expect(container.read(provider).activeRequest!.submitting, isTrue);

      if (scenario.newerFailed) {
        secondResult.completeError(StateError('permission B rejected'));
        await pumpClientFuture(
          tester,
          secondDecision,
          'fail current decision B',
        );
        expect(
          container.read(provider).errorMessage,
          contains('permission B rejected'),
        );
      }
      _complete(firstResult, fails: scenario.fails);
      await pumpClientFuture(
        tester,
        firstDecision,
        'settle retired decision A',
      );
      final current = container.read(provider);
      expect(current.activeRequest!.id, '19:2');
      expect(current.activeRequest!.submitting, !scenario.newerFailed);
      expect(
        current.errorMessage,
        scenario.newerFailed ? contains('permission B rejected') : isNull,
      );
      expect(
        harness.port.calls
            .where((c) => c.$1 == 'answerPermission')
            .map((c) => (c.$2 as AcpPermissionAnswerRequestView).permissionId),
        [first.id, second.id],
      );

      // The current operation still owns its failure and unlocks only B.
      if (!scenario.newerFailed) {
        secondResult.completeError(StateError('permission B rejected'));
        await pumpClientFuture(
          tester,
          secondDecision,
          'settle current decision B',
        );
      }
      final failed = container.read(provider);
      expect(failed.activeRequest!.id, '19:2');
      expect(failed.activeRequest!.submitting, isFalse);
      expect(failed.errorMessage, contains('permission B rejected'));
    });
  }
}

void _complete(Completer<void> result, {required bool fails}) {
  if (fails) {
    result.completeError(StateError('retired permission A failed'));
  } else {
    result.complete();
  }
}

AcpPermissionEventView _permission(int sequence) => AcpPermissionEventView(
  id: AcpPermissionIdView(
    instance: BigInt.from(19),
    sequence: BigInt.from(sequence),
  ),
  request: AcpPermissionRequestView(
    sessionId: acpRemoteFixture,
    toolCall: AcpToolCallUpdateView(
      toolCallId: const AcpToolCallId('read'),
      fields: AcpToolCallUpdateFieldsView(title: 'Read source'),
    ),
    options: const [
      AcpPermissionOptionView(
        optionId: AcpPermissionOptionId('allow'),
        name: 'Allow once',
        kind: AcpPermissionOptionKindView.allowOnce,
      ),
    ],
  ),
);
