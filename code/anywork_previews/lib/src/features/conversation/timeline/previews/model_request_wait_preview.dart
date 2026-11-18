import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import 'package:anywork/src/features/conversation/timeline/live_status/live_status_projection.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';

class ModelRequestWaitPreview extends StatelessWidget {
  const ModelRequestWaitPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final projected = LiveStatusProjection.project(
      threadId: 'preview-thread',
      observation: LiveStatusInputs(
        activeTurnId: 'preview-turn',
        activity: const ThreadActivityView(
          threadId: 'preview-thread',
          identity: 'preview-model-request',
          revision: 7,
          turnId: 'preview-turn',
          kind: ThreadActivityKind.waitingApi,
          summary: '',
          thinkingSeconds: 17,
        ),
        current: CurrentAtomSnapshot(revision: 7),
        hasContentOwner: true,
      ),
    );
    final presenting = projected.barState as LiveStatusPresenting;
    return ConversationActivityBar(
      children: [
        ConversationRealtimeNotices(notices: presenting.surface.notices),
      ],
    );
  }
}
