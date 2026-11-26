import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../presentation/providers/thread_session_store.dart';
import '../../interactions/state/interaction_payload.dart';
import '../connectors/interaction_details_connector.dart';
import 'live_status_state.dart';
import 'live_status_surface_view.dart';
import 'live_status_view_model.dart';

/// The footer observes the live snapshot independently of the timeline list.
class LiveStatusBar extends ConsumerWidget {
  const LiveStatusBar({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(liveStatusViewModelProvider(threadId));
    if (view == null) return const SizedBox.shrink();
    final interaction = ref.watch(
      threadSessionStoreProvider(threadId)
          .select((state) => activePendingInteraction(state.interactions)),
    );
    final work = switch (view.gate) {
      LiveStatusPresenting(
        presentation: LiveStatusPresentation(primary: final LiveWorkPhase work),
      ) =>
        work,
      _ => null,
    };
    return LiveStatusSurfaceView(
      viewportKey: ValueKey(threadId),
      gate: view.gate,
      liveWorkChildBuilder: work == null
          ? null
          : (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in work.items)
                  ListTile(
                    key: ValueKey(item.id),
                    dense: true,
                    title: Text(
                      item.summary.isEmpty ? item.toolName : item.summary,
                    ),
                    subtitle: Text(item.status),
                  ),
              ],
            ),
      interactionDetailsSlot:
          interaction == null || !view.gate.showInteractionDetails
          ? null
          : ReadOnlyInteractionDetails(
              key: ValueKey(interaction.id),
              id: interaction.id,
              payload: interaction.payload,
            ),
    );
  }
}
