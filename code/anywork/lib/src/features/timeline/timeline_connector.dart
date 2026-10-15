import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/observe_client.dart';
import 'timeline_session_view.dart';
import 'timeline_view.dart';

enum TimelineChatPhase { opening, ready, reconnecting, failed }

/// Only connection metadata is observed here. A Ready body patch belongs to its
/// row query and must not rebuild the Timeline list or the status wrapper.
final class TimelineChatStatus {
  const TimelineChatStatus(this.phase, {this.hasLastGood = false, this.error});

  final TimelineChatPhase phase;
  final bool hasLastGood;
  final Object? error;

  factory TimelineChatStatus.from(
    ChatUiState<StudioChatSnapshot> chat,
    DomainSyncStatus runtime,
  ) => switch (chat) {
    ChatOpening<StudioChatSnapshot>(:final lastGood) => TimelineChatStatus(
      TimelineChatPhase.opening,
      hasLastGood: lastGood != null,
    ),
    ChatReady<StudioChatSnapshot>() => const TimelineChatStatus(
      TimelineChatPhase.ready,
      hasLastGood: true,
    ),
    ChatReconnecting<StudioChatSnapshot>(:final lastGood, :final error) =>
      TimelineChatStatus(
        TimelineChatPhase.reconnecting,
        hasLastGood: lastGood != null,
        error: error,
      ),
    ChatFailed<StudioChatSnapshot>(:final lastGood, :final error) =>
      TimelineChatStatus(
        TimelineChatPhase.failed,
        hasLastGood: lastGood != null,
        error: error,
      ),
    ChatIdle<StudioChatSnapshot>() || ChatClosed<StudioChatSnapshot>() =>
      runtime.phase == DomainSyncPhase.failed
          ? TimelineChatStatus(
              TimelineChatPhase.failed,
              error: runtime.errorMessage,
            )
          : const TimelineChatStatus(TimelineChatPhase.opening),
  };

  @override
  bool operator ==(Object other) =>
      other is TimelineChatStatus &&
      phase == other.phase &&
      hasLastGood == other.hasLastGood &&
      error == other.error;

  @override
  int get hashCode => Object.hash(phase, hasLastGood, error);
}

final timelineChatStatusProvider = Provider.autoDispose
    .family<TimelineChatStatus, String>((ref, threadId) {
      final client = ref.read(anyworkClientProvider);
      try {
        final failure = observeClient(ref, client.resourceFailure, (_) {
          if (ref.mounted) ref.invalidateSelf();
        });
        final session = client.existingSession(threadId);
        if (session == null) {
          return TimelineChatStatus(
            TimelineChatPhase.failed,
            error:
                failure?.reason ??
                StateError('The selected ChatView owner is unavailable'),
          );
        }
        var chat = session.chat.state.value;
        var runtime = session.state.sync;
        var current = TimelineChatStatus.from(chat, runtime);
        void publishIfChanged() {
          final next = TimelineChatStatus.from(chat, runtime);
          if (next == current) return;
          current = next;
          if (ref.mounted) ref.invalidateSelf();
        }

        chat = observeClient(ref, session.chat.state, (next) {
          chat = next;
          publishIfChanged();
        });
        runtime = observeClient(ref, session.source, (next) {
          runtime = next.sync;
          publishIfChanged();
        }).sync;
        return TimelineChatStatus.from(chat, runtime);
      } catch (error) {
        return TimelineChatStatus(TimelineChatPhase.failed, error: error);
      }
    }, name: 'timelineChatStatusProvider');

/// List structure, connection state and stable actions meet in this Connector.
/// Disposing its providers releases observations; the Client retains demand.
class TimelineSessionConnector extends ConsumerWidget {
  const TimelineSessionConnector({
    super.key,
    required this.threadId,
    this.planConfirmation,
    this.planExpanded = true,
    this.onPlanToggle,
  });

  final String threadId;
  final PlanConfirmationView? planConfirmation;
  final bool planExpanded;
  final VoidCallback? onPlanToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var status = ref.watch(timelineChatStatusProvider(threadId));
    TimelineSessionWindow? window;
    try {
      window = ref.watch(timelineSessionWindowProvider);
    } catch (error) {
      status = TimelineChatStatus(TimelineChatPhase.failed, error: error);
    }
    final matched = window?.threadId == threadId ? window : null;
    final Widget? content;
    if (matched == null) {
      content = null;
    } else {
      final history = matched.history;
      content = TimelineView(
        threadId: threadId,
        viewId: matched.viewId,
        rows: matched.rows,
        body: history,
        turn: matched.turn,
        planConfirmation: planConfirmation,
        planExpanded: planExpanded,
        onPlanToggle: onPlanToggle,
        isLoadingOlder: matched.isLoadingOlder,
        isLoadingNewer: matched.isLoadingNewer,
        olderError: history.errorMessage,
        newerError: history.newerError,
        anchor: history.anchor,
        hasOlder: history.hasOlder,
        hasNewer: history.hasNewer,
        canExtendLatest: history.canExtendLatest,
        olderCursor: history.olderCursor,
        newerCursor: history.newerCursor,
        windowEpoch: history.epoch,
        onCommand: (command) {
          final owner = ref
              .read(timelineSessionOwnerProvider)
              .session(threadId);
          if (owner != null) unawaited(owner.dispatch(command));
        },
      );
    }
    return TimelineStateView(
      status: status,
      content: content,
      onRetry: () {
        ref.read(anyworkClientProvider).retrySession(threadId);
        ref.invalidate(timelineChatStatusProvider(threadId));
        ref.invalidate(timelineSessionWindowProvider);
      },
    );
  }
}

/// Loading and failure remain visible even before a window exists. A retained
/// window is a last-good display while a new attempt opens or reconnects.
class TimelineStateView extends StatelessWidget {
  const TimelineStateView({
    super.key,
    required this.status,
    required this.content,
    required this.onRetry,
  });

  final TimelineChatStatus status;
  final Widget? content;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (status.phase == TimelineChatPhase.ready && content != null) {
      return content!;
    }
    final failed = status.phase == TimelineChatPhase.failed;
    final error = status.error;
    final message = error?.toString() ?? context.l10n.workspaceLoading;
    final notice = Padding(
      key: ValueKey(('timeline-chat-state', status.phase)),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (failed)
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            )
          else
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          if (error != null)
            TextButton.icon(
              key: const ValueKey('timeline-chat-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.sidebarRetry),
            ),
        ],
      ),
    );
    if (content == null) return Center(child: notice);
    return Column(
      children: [
        notice,
        Expanded(child: content!),
      ],
    );
  }
}
