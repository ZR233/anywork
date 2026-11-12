import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state_machine.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';

/// Typed execution/foreground-source facts pass through the production state
/// machine. In particular, the activity is never injected into a Work header:
/// a failed merge must remain visible as an extra standalone notice here.
class ModelRequestWaitPreview extends StatefulWidget {
  const ModelRequestWaitPreview({super.key});

  @override
  State<ModelRequestWaitPreview> createState() =>
      _ModelRequestWaitPreviewState();
}

class _ModelRequestWaitPreviewState extends State<ModelRequestWaitPreview> {
  final _expansion = TimelineExpansionIntent();
  static final _now = DateTime.fromMillisecondsSinceEpoch(1428000);
  static final _window = LiveDisplayWindow(
    revision: 7,
    historyThrough: 0,
    executionPresent: true,
    blocks: const [
      LiveDisplayBlock(
        id: 'model-request-wait',
        blockOrder: 1,
        state: DisplayBlockState.open,
        source: ForegroundTurnChatSource(turnId: 'preview-turn'),
        body: WorkDisplayBlock(
          summary: WorkSummary(
            total: 1,
            terminal: 1,
            running: 0,
            waiting: 0,
            failed: 0,
            cancelled: 0,
            transferred: 1,
            unavailable: 0,
            createdAt: 1000,
            elapsedMs: 428000,
          ),
          members: DisplayBlockRef(
            databaseId: 'preview',
            blockId: 'model-request-wait',
          ),
        ),
      ),
    ],
  );
  late final _aggregate = LiveStatusStateMachine.transition(
    LiveStatusAggregate.initial('preview-thread'),
    LiveStatusObserved(
      LiveStatusObservation(
        cut: LiveWindowCut(
          revision: _window.revision,
          historyThrough: _window.historyThrough,
          executionPresent: _window.executionPresent,
          attemptId: 1,
          isDisplayActive: true,
        ),
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
        latestLive: _window,
        hasContentOwner: true,
      ),
    ),
  ).state;

  @override
  void dispose() {
    _expansion.retire();
    _expansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presenting = _aggregate.barState as LiveStatusPresenting;
    final surface = presenting.surface;
    return ConversationActivityBar(
      children: [
        if (surface.standaloneNotices.isNotEmpty)
          ConversationRealtimeNotices(notices: surface.standaloneNotices),
        for (final block in surface.blocks)
          TimelineDisplayUnitView(
            key: ValueKey(block.id),
            unit: TimelineDisplayUnit.live(
              block: block,
              executionPresent: _window.executionPresent,
              expansion: _expansion,
            ),
            activity: surface.mergedActivityFor(block.id),
            now: () => _now,
            childBuilder: (_) => const TimelineToolDetails(
              item: TimelineToolPresentation(
                id: 'preview-transferred-command',
                toolCallId: 'preview-transferred-command',
                name: 'exec',
                presentationContract: 'builtin.exec@2',
                statusString: 'transferred',
                arguments: '{"command":"cargo flutter analyze"}',
                output: '执行已交接，当前轮次正在请求模型。',
              ),
            ),
          ),
      ],
    );
  }
}
