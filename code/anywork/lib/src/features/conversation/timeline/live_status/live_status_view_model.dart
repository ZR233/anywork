import 'package:anywork_client/models.dart' as feed;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../interactions/state/interaction_payload.dart';
import 'live_status_machine.dart';
import '../view_models/timeline_view_model.dart';
import 'live_status_state.dart';

part 'live_status_view_model.g.dart';

@riverpod
class LiveStatusViewModel extends _$LiveStatusViewModel {
  @override
  LiveStatusView? build(String threadId) {
    final owner = ref.read(timelineSessionOwnerProvider);
    final interaction = ref.watch(
      threadSessionStoreProvider(threadId)
          .select((state) => activePendingInteraction(state.interactions)),
    );
    LiveStatusView? project(
      ({
        String threadId,
        feed.LiveStatusSnapshot snapshot,
        DateTime receivedAt,
      })?
      event,
    ) {
      if (event == null || event.threadId != threadId) return null;
      final view = LiveStatusMachine.project(
        threadId,
        event.snapshot,
        receivedAt: event.receivedAt,
        interaction: interaction,
      );
      // Driver diagnostics borrow the same presentation the footer renders.
      owner.lease(threadId)?.liveStatus = view;
      return view;
    }

    final initial = observeClient(ref, owner.liveStatus, (event) {
      if (ref.mounted) state = project(event);
    });
    return project(initial);
  }
}
