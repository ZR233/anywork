import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';

ThreadStatus shellAgentStatus(AgentState state) => switch (state) {
  IdleAgentState() => ThreadStatus.idle,
  QueuedAgentState() => ThreadStatus.queued,
  RunningAgentState() => ThreadStatus.running,
  WaitingToolAgentState() => ThreadStatus.waitingTool,
  WaitingInteractionAgentState() => ThreadStatus.waitingInteraction,
  CancellingAgentState() => ThreadStatus.cancelling,
  ClosingAgentState() => ThreadStatus.closing,
  ClosedAgentState() => ThreadStatus.closed,
  FaultedAgentState() => ThreadStatus.faulted,
};

SourceStateError? shellAgentError(AgentState state) => switch (state) {
  FaultedAgentState(:final error) => error,
  ClosingAgentState(:final error) => error,
  _ => null,
};

bool shellStatusWorking(ThreadStatus status) => switch (status) {
  ThreadStatus.queued ||
  ThreadStatus.running ||
  ThreadStatus.waitingTool ||
  ThreadStatus.cancelling ||
  ThreadStatus.closing => true,
  _ => false,
};
