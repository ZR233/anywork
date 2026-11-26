import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

/// Supplies the page-side consumer used by command/draft integration tests.
/// Production SDK metadata is updated only by consuming the one feed stream.
final _pageClients = Expando<bool>();
void observeTestConversationPage(AnyworkClient client) {
  if (_pageClients[client] == true) return;
  _pageClients[client] = true;
  final observations = <Observation>[];
  final subscriptions = <StreamSubscription<ConversationFeedEvent>>[];
  final attached = <ConversationFeedHandle>{};
  final watched = <String>{};
  void watch(String? threadId) {
    if (threadId == null || !watched.add(threadId)) return;
    final session = client.conversations.session(threadId);
    void attach(ThreadSessionState state) {
      if (state.sync.phase != DomainSyncPhase.connecting) return;
      unawaited(
        client.conversations.openConversationFeed(threadId).then<void>((
          handle,
        ) {
          if (!attached.add(handle)) return;
          subscriptions.add(handle.events.listen((_) {}));
        }, onError: (Object _, StackTrace _) {}),
      );
    }

    observations.add(session.source.watch(attach, fireImmediately: true));
  }

  observations.add(
    client.conversations.visibleThreadId.watch(watch, fireImmediately: true),
  );
  addTearDown(() async {
    for (final observation in observations) observation.cancel();
    for (final subscription in subscriptions) await subscription.cancel();
  });
}
