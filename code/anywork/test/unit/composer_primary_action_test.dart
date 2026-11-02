import 'package:anywork/src/domain/models/composer_primary_action.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _execution = AgentExecutionView(
  id: 'exec-1',
  phase: AgentExecutionPhase.running,
  turnId: 'turn-1',
);

const _stopping = AgentExecutionView(
  id: 'exec-1',
  phase: AgentExecutionPhase.stopping,
  turnId: 'turn-1',
);

const _recoveryBlocker = ComposerRecoveryBlocker(
  StudioRecoveryIssue(
    id: 'thread-recovery',
    scope: RecoveryIssueScope.thread,
    category: RecoveryIssueCategory.repository,
    impact: RecoveryIssueImpact.executionBlocked,
    availableActions: [RecoveryIssueAction.retry],
    workspaceId: 'project',
    threadId: 'thread',
    detail: 'Workspace unavailable',
  ),
);

final _continuation = ContinuationView(
  id: 'continuation-1',
  sourceTurnId: 'turn-1',
  reason: ContinuationReason.userStop,
  createdAt: DateTime.utc(2026, 1, 1),
  claimed: false,
);

final _claimed = ContinuationView(
  id: 'continuation-1',
  sourceTurnId: 'turn-1',
  reason: ContinuationReason.userStop,
  createdAt: DateTime.utc(2026, 1, 1),
  claimed: true,
);

ComposerPrimaryAction _resolve({
  bool isChild = false,
  AgentExecutionView? execution,
  ContinuationView? continuation,
  bool hasContent = false,
  bool submissionPending = false,
  bool stopAccepted = false,
  bool continuationAccepted = false,
  bool continuationPending = false,
  ComposerBlocker? blocker,
}) {
  return ComposerPrimaryAction.resolve(
    isChild: isChild,
    execution: execution,
    continuation: continuation,
    hasContent: hasContent,
    submissionPending: submissionPending,
    stopAccepted: stopAccepted,
    continuationAccepted: continuationAccepted,
    continuationPending: continuationPending,
    blocker: blocker,
  );
}

void main() {
  group('running', () {
    test('空草稿是中性停止，且回车不提交', () {
      final action = _resolve(execution: _execution);
      expect(action.kind, ComposerPrimaryActionKind.stop);
      expect(action.enabled, isTrue);
      expect(action.enterSubmits, isFalse);
    });

    test('有草稿是发送并继续，回车与主按钮一致', () {
      final action = _resolve(execution: _execution, hasContent: true);
      expect(action.kind, ComposerPrimaryActionKind.sendAndContinue);
      expect(action.enabled, isTrue);
      expect(action.enterSubmits, isTrue);
    });

    test('准备与等待准入阶段同样只提供停止', () {
      for (final phase in const [
        AgentExecutionPhase.preparing,
        AgentExecutionPhase.awaitingStorage,
        AgentExecutionPhase.awaitingAdmission,
      ]) {
        final action = _resolve(
          execution: AgentExecutionView(id: 'exec-1', phase: phase),
        );
        expect(action.kind, ComposerPrimaryActionKind.stop, reason: '$phase');
        expect(action.enabled, isTrue, reason: '$phase');
      }
    });

    test('停止已受理且清理未结束时即使有草稿也不提交', () {
      final action = _resolve(execution: _stopping, hasContent: true);
      expect(action.kind, ComposerPrimaryActionKind.stopping);
      expect(action.enabled, isFalse);
      expect(action.enterSubmits, isFalse);
    });
  });

  group('stopping', () {
    test('执行已消失但停止仍在观察时显示正在停止', () {
      final action = _resolve(stopAccepted: true, hasContent: true);
      expect(action.kind, ComposerPrimaryActionKind.stopping);
      expect(action.enabled, isFalse);
    });

    test('即使同时存在继续点也不接受继续', () {
      final action = _resolve(
        stopAccepted: true,
        continuation: _continuation,
        hasContent: true,
      );
      expect(action.kind, ComposerPrimaryActionKind.stopping);
      expect(action.enabled, isFalse);
    });
  });

  group('continuation', () {
    test('未认领继续点的空输入必须显式点击，回车不提交', () {
      final action = _resolve(continuation: _continuation);
      expect(action.kind, ComposerPrimaryActionKind.continueConversation);
      expect(action.enabled, isTrue);
      expect(action.enterSubmits, isFalse);
    });

    test('未认领继续点有草稿时发送并继续', () {
      final action = _resolve(continuation: _continuation, hasContent: true);
      expect(action.kind, ComposerPrimaryActionKind.sendAndContinue);
      expect(action.enabled, isTrue);
      expect(action.enterSubmits, isTrue);
    });

    test('已认领的继续点显示正在继续且不可重复提交', () {
      for (final continuation in [_claimed, _continuation]) {
        final action = _resolve(
          continuation: continuation,
          continuationAccepted: true,
        );
        expect(action.kind, ComposerPrimaryActionKind.continuing);
        expect(action.enabled, isFalse);
      }
      expect(
        _resolve(continuation: _claimed).kind,
        ComposerPrimaryActionKind.continuing,
      );
    });

    test('继续已受理但执行尚未出现时也显示正在继续', () {
      final action = _resolve(continuationAccepted: true, hasContent: true);
      expect(action.kind, ComposerPrimaryActionKind.continuing);
      expect(action.enabled, isFalse);
    });

    test('继续请求在途但未受理时仍是继续入口，只临时禁用', () {
      final action = _resolve(
        continuation: _continuation,
        continuationPending: true,
      );
      expect(
        action.kind,
        ComposerPrimaryActionKind.continueConversation,
        reason: '回执未到就不算已受理，不能提前显示正在继续',
      );
      expect(action.enabled, isFalse, reason: '同一时刻不重复提交');
    });

    test('继续点已被执行取代时回到运行中按钮', () {
      final action = _resolve(
        execution: _execution,
        continuation: _claimed,
        continuationAccepted: true,
      );
      expect(action.kind, ComposerPrimaryActionKind.stop);
      expect(action.enabled, isTrue);
    });
  });

  group('completed', () {
    test('正常完成且没有中断工作时不出现继续', () {
      final empty = _resolve();
      expect(empty.kind, ComposerPrimaryActionKind.send);
      expect(empty.enabled, isFalse);
      expect(empty.enterSubmits, isFalse);

      final content = _resolve(hasContent: true);
      expect(content.kind, ComposerPrimaryActionKind.send);
      expect(content.enabled, isTrue);
      expect(content.enterSubmits, isTrue);
    });

    test('提交中禁用主按钮与回车', () {
      final action = _resolve(hasContent: true, submissionPending: true);
      expect(action.kind, ComposerPrimaryActionKind.send);
      expect(action.enabled, isFalse);
      expect(action.enterSubmits, isFalse);
    });
  });

  group('blocked', () {
    test('保存阻塞禁用继续但保留草稿与原因', () {
      final action = _resolve(
        continuation: _continuation,
        blocker: const ComposerStorageBlocker(),
      );
      expect(action.kind, ComposerPrimaryActionKind.continueConversation);
      expect(action.enabled, isFalse);
      expect(action.blocker, isA<ComposerStorageBlocker>());
    });

    test('模型阻塞禁用继续', () {
      const blocker = ComposerModelBlocker();
      final action = _resolve(continuation: _continuation, blocker: blocker);
      expect(action.enabled, isFalse);
      expect(action.blocker, blocker);
    });

    test('Recovery阻塞禁用继续但不隐藏运行中的停止入口', () {
      final continuing = _resolve(
        continuation: _continuation,
        blocker: _recoveryBlocker,
      );
      expect(continuing.enabled, isFalse);
      expect(continuing.blocker, _recoveryBlocker);

      final running = _resolve(
        execution: _execution,
        blocker: _recoveryBlocker,
      );
      expect(running.kind, ComposerPrimaryActionKind.stop);
      expect(running.enabled, isTrue);
      expect(running.blocker, _recoveryBlocker);
    });

    test('阻塞不隐藏运行中的停止入口', () {
      final action = _resolve(
        execution: _execution,
        blocker: const ComposerModelBlocker(),
      );
      expect(action.kind, ComposerPrimaryActionKind.stop);
      expect(action.enabled, isTrue);
      expect(action.blocker, isA<ComposerModelBlocker>());
    });

    test('被拒绝的原因照常显示，但不锁死重试入口', () {
      final blocker = const ComposerFailureBlocker(
        StudioFailureReason.staleExecution,
      );
      final withContent = _resolve(hasContent: true, blocker: blocker);
      expect(withContent.kind, ComposerPrimaryActionKind.send);
      expect(withContent.enabled, isTrue, reason: '上一次操作被拒绝不等于当前事实阻塞提交');
      expect(withContent.enterSubmits, isTrue);
      expect(
        (withContent.blocker as ComposerFailureBlocker).reason,
        StudioFailureReason.staleExecution,
      );

      final afterInterrupt = _resolve(
        continuation: _continuation,
        blocker: blocker,
      );
      expect(
        afterInterrupt.kind,
        ComposerPrimaryActionKind.continueConversation,
      );
      expect(afterInterrupt.enabled, isTrue, reason: '允许按当前事实重试继续');
    });
  });

  test('子会话没有输入区操作', () {
    for (final execution in const [null, _execution]) {
      final action = _resolve(
        isChild: true,
        execution: execution,
        continuation: _continuation,
        hasContent: true,
      );
      expect(action.kind, ComposerPrimaryActionKind.readOnly);
      expect(action.enabled, isFalse);
      expect(action.enterSubmits, isFalse);
    }
  });
}
