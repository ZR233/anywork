import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import 'timeline_transport.dart';
import 'business_metadata_inputs.dart';
export 'business_metadata_inputs.dart';

final Map<String, ScriptedConversationFeed> _feeds = {};
final Map<String, Completer<ScriptedConversationFeed>> _waiting = {};

Future<ScriptedConversationFeed> scriptedConversationFeed(String threadId) {
  final current = _feeds[threadId];
  return current != null &&
          current.controller.hasListener &&
          !current.requestCloseStarted.isCompleted
      ? Future.value(current)
      : (_waiting[threadId] ??= Completer()).future;
}

extension ConversationTestDelivery on ConversationSession {
  Future<void> deliverWorkspace(ThreadWorkspace workspace) async {
    final feed = await scriptedConversationFeed(threadId);
    await feed.deliver(
      ThreadSnapshotFrame(
        schemaVersion: threadSchemaVersion,
        workspace: workspace,
      ),
    );
    await source.waitFor((state) => state.meta?.revision == workspace.revision);
  }

  Future<void> deliverNotification(ThreadNotificationFrame frame) async {
    final feed = await scriptedConversationFeed(threadId);
    await feed.deliver(frame);
  }
}

ThreadStreamFrame testConversationEvent({required ThreadStreamFrame frame}) =>
    frame;

/// Business test inputs are converted here to complete metadata snapshots.
/// This environment has no production continuity, paging or grouping reducer.
class ScriptedConversationFeed extends TestConversationFeed {
  ScriptedConversationFeed({
    String threadId = 'thread',
    this.states,
    SessionMetaSnapshot? initialMeta,
  }) : super(threadId: threadId, initialMeta: initialMeta) {
    _feeds[threadId] = this;
    controller.onListen = () {
      _waiting.remove(threadId)?.complete(this);
    };
    final stream = states;
    if (stream != null) _states = stream.listen(sendFrame, onError: sendError);
  }
  final Stream<ThreadStreamFrame>? states;
  StreamSubscription<ThreadStreamFrame>? _states;
  ThreadWorkspace? _workspace;
  void sendFrame(ThreadStreamFrame frame) {
    if (requestCloseStarted.isCompleted) return;
    final workspace =
        _workspace ??
        emptyConversationWorkspace(threadId).copyWith(
          revision: sessionMetaSnapshot.revision,
          runtime: ThreadSessionState(
            threadId: threadId,
            meta: sessionMetaSnapshot,
          ).runtime,
          modelRoute: sessionMetaSnapshot.modelRoute,
          activeTurn: sessionMetaSnapshot.activeTurn,
          latestTurn: sessionMetaSnapshot.lastTurn,
          interactions: sessionMetaSnapshot.interactions,
          activity: sessionMetaSnapshot.activity,
          storage: sessionMetaSnapshot.storageState,
        );
    final next = switch (frame) {
      ThreadSnapshotFrame(:final workspace) => workspace,
      ThreadNotificationFrame(:final revision, :final update) =>
        switch (update) {
          ThreadTurnUpdate(:final turn) => workspace.copyWith(
            revision: revision,
            activeTurn: turn.state.isBusy ? turn : null,
            latestTurn: turn,
          ),
          ThreadRuntimeUpdate(:final runtime, :final todo, :final modelRoute) =>
            workspace.copyWith(
              revision: revision,
              runtime: runtime,
              todo: todo,
              modelRoute: modelRoute,
            ),
          ThreadStorageUpdate(:final storage) => workspace.copyWith(
            revision: revision,
            storage: storage,
          ),
          ThreadActivityUpdate(:final activity) => workspace.copyWith(
            revision: revision,
            activity: activity,
          ),
          ThreadInteractionUpdate(:final interaction, :final pending) =>
            workspace.copyWith(
              revision: revision,
              interactions: [
                for (final value in workspace.interactions)
                  if (value.id != interaction.id) value,
                if (pending) interaction,
              ],
            ),
        },
    };
    _workspace = next;
    send(ConversationSessionMeta(snapshot: sessionMetaForWorkspace(next)));
  }

  @override
  Future<void> deliver(Object event) async {
    if (event is ThreadStreamFrame) {
      sendFrame(event);
      await Future<void>.value();
      return;
    }
    await super.deliver(event as ConversationFeedEvent);
  }

  @override
  Future<void> close() async {
    await _states?.cancel();
    await super.close();
  }
}
