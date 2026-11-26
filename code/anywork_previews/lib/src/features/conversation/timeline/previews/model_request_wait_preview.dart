import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

class ModelRequestWaitPreview extends StatelessWidget {
  const ModelRequestWaitPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final projected = LiveStatusMachine.project(
      'preview-thread',
      LiveStatusSnapshot(
        revision: 7,
        phase: LiveStatusWorking(items: const [], startedAtMs: 100_000),
        attentions: const [],
        suppressedByInteraction: false,
      ),
      receivedAt: DateTime.fromMillisecondsSinceEpoch(117_000),
    );
    return LiveStatusSurfaceView(
      state: projected.state,
      now: () => DateTime.fromMillisecondsSinceEpoch(117_000),
    );
  }
}
