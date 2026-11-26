import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

void main() {
  group('projectConversationActivity', () {
    test(
      'maps waitingApi to thinking and normalizes summary to single line',
      () {
        const activity = ThreadActivityView(
          threadId: 'thread-1',
          identity: 'act-1',
          revision: 2,
          turnId: 'turn-1',
          executionId: 'exec-1',
          kind: ThreadActivityKind.waitingApi,
          summary: '  first line \n  second   line  ',
          thinkingSummary: 'Inspecting state',
          thinkingSeconds: 12,
          tools: ThreadActivityTools.empty,
        );

        final projected = projectConversationActivity(activity: activity);

        expect(projected, isNotNull);
        expect(projected!.kind, ConversationActivityKind.thinking);
        expect(projected.summary, 'first line second line');
        expect(projected.thinkingSummary, 'Inspecting state');
        expect(projected.thinkingSeconds, 12);
        expect(projected.turnId, 'turn-1');
        expect(projected.executionId, 'exec-1');
      },
    );

    test('forwards typed wait metadata from latestStarted or active tools', () {
      final latestWait = ThreadWaitPresentationView(
        intent: ThreadWaitEventsIntentView(
          targets: const [
            ThreadWaitTargetView(
              taskId: 'task-1',
              toolName: 'exec',
              summary: 'cargo test',
            ),
          ],
          timeoutMs: 30000,
        ),
        state: ThreadWaitStateView.waiting,
      );
      const fallbackWait = ThreadWaitPresentationView(
        intent: ThreadWaitTimerIntentView(durationMs: 5000),
        state: ThreadWaitStateView.waiting,
      );

      final latestEntry = ThreadActivityToolEntry(
        callId: 'call-latest',
        name: 'wait',
        summary: '等待任务',
        arguments: ThreadActivityArgumentsKind.commandLine,
        state: ThreadActivityToolState.running,
        wait: latestWait,
      );
      const activeEntry = ThreadActivityToolEntry(
        callId: 'call-active',
        name: 'sleep',
        summary: '等待 5 秒',
        arguments: ThreadActivityArgumentsKind.commandLine,
        state: ThreadActivityToolState.running,
        wait: fallbackWait,
      );

      final withLatest = projectConversationActivity(
        activity: ThreadActivityView(
          threadId: 'thread-1',
          identity: 'act-wait-1',
          revision: 1,
          turnId: 'turn-1',
          kind: ThreadActivityKind.runningTool,
          summary: '',
          tools: ThreadActivityTools(
            count: 2,
            active: [activeEntry, latestEntry],
            latestStarted: latestEntry,
          ),
        ),
      );
      expect(withLatest?.wait, latestWait);

      final withFallback = projectConversationActivity(
        activity: ThreadActivityView(
          threadId: 'thread-1',
          identity: 'act-wait-2',
          revision: 1,
          turnId: 'turn-1',
          kind: ThreadActivityKind.runningTool,
          summary: '',
          tools: ThreadActivityTools(count: 1, active: const [activeEntry]),
        ),
      );
      expect(withFallback?.wait, fallbackWait);
    });

    test(
      'projects blocked storage and clears stale errorMessage when recovered',
      () {
        const blocked = ThreadStorageStateView(
          fault: ThreadHistoryFault.writeFailed,
          faultGeneration: 3,
          execution: ThreadStorageExecution.paused,
          resumeRequired: true,
          canResume: false,
          lastError: 'Disk full',
        );
        final blockedView = projectConversationActivity(
          activity: null,
          storage: blocked,
        );
        expect(blockedView?.kind, ConversationActivityKind.storageBlocked);
        expect(blockedView?.errorMessage, 'Disk full');
        expect(blockedView?.identity, 'storage:3:writeFailed');

        const recovered = ThreadStorageStateView(
          fault: ThreadHistoryFault.writeFailed,
          faultGeneration: 3,
          execution: ThreadStorageExecution.paused,
          resumeRequired: true,
          canResume: true,
          lastError: 'Disk full',
        );
        final recoveredView = projectConversationActivity(
          activity: null,
          storage: recovered,
        );
        expect(recoveredView?.kind, ConversationActivityKind.storageBlocked);
        expect(recoveredView?.errorMessage, isNull);
        expect(recoveredView?.storage?.canResume, isTrue);
      },
    );

    test('maps interaction fallback when no activity is active', () {
      const approval = PendingInteraction(
        id: 'req-1',
        threadId: 'thread-1',
        turnId: 'turn-1',
        kind: InteractionKind.toolApproval,
        title: 'Approve tool',
        body: 'Allow exec?',
        payload: ToolApprovalInteractionPayload(
          toolName: 'exec',
          arguments: {'cmd': 'cargo test'},
          workingDirectory: '/workspace',
        ),
      );

      final approvalView = projectConversationActivity(
        activity: null,
        interaction: approval,
      );
      expect(approvalView?.kind, ConversationActivityKind.awaitingApproval);
      expect(approvalView?.summary, 'exec');
      expect(approvalView?.expandable, isTrue);
      expect(approvalView?.details.single.body, contains('cargo test'));

      const input = PendingInteraction(
        id: 'req-2',
        threadId: 'thread-1',
        turnId: 'turn-1',
        kind: InteractionKind.userInput,
        title: 'Need decision',
        body: '',
        payload: UserInputInteractionPayload(
          questions: [
            UserQuestionView(
              id: 'q1',
              header: 'Target branch',
              question: 'Which branch should receive the PR?',
              isSecret: false,
              options: [],
            ),
          ],
        ),
      );

      final inputView = projectConversationActivity(
        activity: null,
        interaction: input,
      );
      expect(inputView?.kind, ConversationActivityKind.awaitingInput);
      expect(inputView?.summary, 'Target branch');
      expect(inputView?.details.single.title, 'Target branch');
    });

    test('isRunningExecTool matches running command tools only', () {
      for (final name in const ['exec', 'exec_command', 'builtin.exec@2']) {
        final running = ConversationActivityView(
          identity: 'run-$name',
          kind: ConversationActivityKind.runningTool,
          activeTools: [
            ThreadActivityToolEntry(
              callId: 'c1',
              name: name,
              summary: 'cargo test',
              arguments: ThreadActivityArgumentsKind.commandLine,
              state: ThreadActivityToolState.running,
            ),
          ],
        );
        expect(running.isRunningExecTool, isTrue, reason: name);

        final finished = ConversationActivityView(
          identity: 'done-$name',
          kind: ConversationActivityKind.runningTool,
          activeTools: [
            ThreadActivityToolEntry(
              callId: 'c1',
              name: name,
              summary: 'cargo test',
              arguments: ThreadActivityArgumentsKind.commandLine,
              state: ThreadActivityToolState.finished,
            ),
          ],
        );
        expect(finished.isRunningExecTool, isFalse, reason: '$name finished');
      }

      const writeFile = ConversationActivityView(
        identity: 'write-1',
        kind: ConversationActivityKind.runningTool,
        activeTools: [
          ThreadActivityToolEntry(
            callId: 'c2',
            name: 'write_file',
            summary: '写入 design/19-studio-ui.md',
            arguments: ThreadActivityArgumentsKind.opaque,
            state: ThreadActivityToolState.running,
          ),
        ],
      );
      expect(writeFile.isRunningExecTool, isFalse);

      const waitTool = ConversationActivityView(
        identity: 'wait-1',
        kind: ConversationActivityKind.runningTool,
        activeTools: [
          ThreadActivityToolEntry(
            callId: 'c3',
            name: 'wait',
            summary: '等待后台任务',
            arguments: ThreadActivityArgumentsKind.opaque,
            state: ThreadActivityToolState.running,
          ),
        ],
      );
      expect(waitTool.isRunningExecTool, isFalse);
    });
  });
}
