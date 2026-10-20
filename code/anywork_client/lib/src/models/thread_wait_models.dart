import 'collection_equality.dart';

/// Typed wait/sleep presentation attached to the original tool call.
class ThreadWaitPresentationView {
  const ThreadWaitPresentationView({
    required this.intent,
    required this.state,
    this.messagesReady,
  });

  final ThreadWaitIntentView intent;
  final ThreadWaitStateView state;
  final bool? messagesReady;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ThreadWaitPresentationView &&
            intent == other.intent &&
            state == other.state &&
            messagesReady == other.messagesReady;
  }

  @override
  int get hashCode => Object.hash(intent, state, messagesReady);
}

sealed class ThreadWaitIntentView {
  const ThreadWaitIntentView();
}

final class ThreadWaitEventsIntentView extends ThreadWaitIntentView {
  const ThreadWaitEventsIntentView({
    required this.targets,
    required this.timeoutMs,
  });

  final List<ThreadWaitTargetView> targets;
  final int timeoutMs;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ThreadWaitEventsIntentView &&
            timeoutMs == other.timeoutMs &&
            listEquals(targets, other.targets);
  }

  @override
  int get hashCode => Object.hash(timeoutMs, Object.hashAll(targets));
}

final class ThreadWaitTimerIntentView extends ThreadWaitIntentView {
  const ThreadWaitTimerIntentView({required this.durationMs});

  final int durationMs;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ThreadWaitTimerIntentView && durationMs == other.durationMs;
  }

  @override
  int get hashCode => durationMs.hashCode;
}

class ThreadWaitTargetView {
  const ThreadWaitTargetView({
    required this.taskId,
    this.toolName,
    this.summary,
    this.summaryTruncated = false,
    this.status,
  });

  final String taskId;
  final String? toolName;
  final String? summary;
  final bool summaryTruncated;
  final ThreadWaitTargetStatusView? status;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ThreadWaitTargetView &&
            taskId == other.taskId &&
            toolName == other.toolName &&
            summary == other.summary &&
            summaryTruncated == other.summaryTruncated &&
            status == other.status;
  }

  @override
  int get hashCode =>
      Object.hash(taskId, toolName, summary, summaryTruncated, status);
}

enum ThreadWaitTargetStatusView {
  running,
  succeeded,
  failed,
  cancelled,
  interrupted,
}

enum ThreadWaitStateView {
  waiting,
  ready,
  timedOut,
  elapsed,
  cancelled,
  failed,
  interrupted,
}
