import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../view_models/timeline_view_model.dart';
import 'live_status_machine.dart';
import 'live_status_state.dart';

part 'live_status_view_model.g.dart';

/// Current state and business facts are projected directly through [LiveStatusMachine].
@riverpod
class LiveStatusViewModel extends _$LiveStatusViewModel {
  @override
  LiveStatusView? build(String threadId) {
    ref.watch(threadSessionStoreProvider(threadId));
    final conversations = ref.read(anyworkClientProvider).conversations;
    final visible = observeClient(ref, conversations.visibleThreadId, (_) {
      if (ref.mounted) ref.invalidateSelf();
    });
    if (visible != threadId) return null;
    ref.watch(timelineViewModelProvider(threadId));
    final lease = ref.read(timelineSessionOwnerProvider).lease(threadId);
    if (lease != null) {
      void changed() {
        if (ref.mounted) state = _project();
      }

      lease.live.addListener(changed);
      lease.liveOpenWork.addListener(changed);
      lease.retirement.addListener(changed);
      lease.currentCollectionError.addListener(changed);
      lease.renderedCurrentAtoms.addListener(changed);
      ref.onDispose(() {
        lease.live.removeListener(changed);
        lease.liveOpenWork.removeListener(changed);
        lease.retirement.removeListener(changed);
        lease.currentCollectionError.removeListener(changed);
        lease.renderedCurrentAtoms.removeListener(changed);
      });
    }
    return _project();
  }

  LiveStatusView? _project() {
    final conversations = ref.read(anyworkClientProvider).conversations;
    if (conversations.visibleThreadId.value != threadId) return null;
    final session = ref.read(threadSessionStoreProvider(threadId));
    final lease = ref.read(timelineSessionOwnerProvider).lease(threadId);
    final active = lease != null && !lease.retirement.value;
    final live = active ? lease.live.value : null;
    if (session.workspace == null && !session.hasSnapshot && live == null) {
      return null;
    }
    final connectionStatus = switch (session.sync.phase) {
      DomainSyncPhase.reconnecting => LiveConnectionStatus.reconnecting,
      DomainSyncPhase.failed => LiveConnectionStatus.disconnected,
      DomainSyncPhase.idle ||
      DomainSyncPhase.connecting ||
      DomainSyncPhase.ready => LiveConnectionStatus.connected,
    };
    final view = LiveStatusMachine.project(
      threadId: threadId,
      inputs: LiveStatusInputs(
        storage: session.storage,
        interactions: session.interactions,
        businessRefs: session.businessRefs,
        activeTurnId: session.activeTurn?.turnId,
        activity: session.activity,
        current: live,
        liveOpenWork: active ? lease.liveOpenWork.value : null,
        renderedCurrentAtomIds:
            lease?.renderedCurrentAtomIds ?? const <String>{},
        hasContentOwner: active,
        connectionStatus: connectionStatus,
        connectionDetail: session.sync.errorMessage,
      ),
      currentAtomsError: lease?.currentCollectionError.value,
    );
    // Diagnostics borrow the very object rendered by this component, not a second projection.
    if (active) lease.liveStatus = view;
    return view;
  }
}
