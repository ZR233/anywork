import 'package:anywork/src/features/conversation/timeline/state/timeline_display_models.dart';
import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

class ModelRequestWaitPreview extends StatelessWidget {
  const ModelRequestWaitPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final projected = LiveStatusMachine.project(
      threadId: 'preview-thread',
      inputs: LiveStatusInputs(
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
    return LiveStatusSurfaceView(gate: projected.gate);
  }
}
