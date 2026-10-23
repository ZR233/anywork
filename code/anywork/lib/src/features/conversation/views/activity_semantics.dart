import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../state/thread_status_state.dart';

/// Conversation-only composition. No parallel shared Activity enum/model.
String conversationActivityLabel(BuildContext context, ThreadStatusViewState state) {
  final storage = state.execution?.value?.storage;
  if (storage?.fault != null) return context.l10n.conversationActivitySaveFailed;
  if (storage?.resumeRequired == true) return storage!.canResume
      ? context.l10n.conversationActivityResumeReady : context.l10n.conversationActivityResumeRequired;
  if (storage?.pressurePaused == true) return context.l10n.conversationActivityStoragePressure;
  if (storage != null && storage.execution != ThreadStorageExecution.running) return context.l10n.conversationActivitySavePaused;
  final wait = state.activityRead.header?.latestStarted?.wait;
  if (wait != null && wait.state == ThreadWaitState.waiting) return switch (wait.intent) {
    TimerWaitReadIntent() => context.l10n.conversationActivityWaitingTimer,
    EventsWaitReadIntent(:final targetCount) => targetCount == 0
        ? context.l10n.conversationActivityWaitingMessages : context.l10n.conversationActivityWaitingTools,
  };
  final activity = state.execution?.value?.activity;
  return switch (activity?.kind) {
    ThreadActivityKind.preparing => context.l10n.conversationActivityPreparing,
    ThreadActivityKind.waitingApi => context.l10n.workspaceLoading,
    ThreadActivityKind.thinking => context.l10n.timelineReasoningActive,
    ThreadActivityKind.responding => context.l10n.statusTurnResponding,
    ThreadActivityKind.planning => context.l10n.statusTurnPlanning,
    ThreadActivityKind.runningTool => context.l10n.conversationActivityRunningTool,
    ThreadActivityKind.awaitingApproval => context.l10n.statusTurnWaitingForApproval,
    ThreadActivityKind.awaitingInput => context.l10n.statusTurnWaitingForUserInput,
    ThreadActivityKind.stopping => context.l10n.conversationActivityStopping,
    null => state.execution?.value == null ? '—' : context.threadStatusLabel(state.execution!.value!.status),
  };
}

bool conversationActivityIsIssue(ThreadStatusViewState state) =>
    state.execution?.value?.storage?.fault != null ||
    state.execution?.value?.storage?.resumeRequired == true;

IconData conversationActivityIcon(ThreadStatusViewState state) {
  if (conversationActivityIsIssue(state)) return Icons.warning_amber;
  return switch (state.execution?.value?.activity?.kind) {
    ThreadActivityKind.runningTool => Icons.terminal,
    ThreadActivityKind.thinking => Icons.psychology_outlined,
    ThreadActivityKind.awaitingApproval => Icons.verified_user_outlined,
    ThreadActivityKind.awaitingInput => Icons.question_answer_outlined,
    ThreadActivityKind.stopping => Icons.stop_circle_outlined,
    _ => Icons.circle_outlined,
  };
}
