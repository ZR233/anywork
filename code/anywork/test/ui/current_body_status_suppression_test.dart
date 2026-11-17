import 'package:anywork/src/features/conversation/timeline/live_status/live_status_projection.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_models.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

CurrentAtom _activeText() => CurrentAtom(
  id: 'current-body',
  source: const ForegroundTurnChatSource(turnId: 'turn'),
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  turnId: 'turn',
  contents: const [],
);

const _responding = ExecutionLiveNotice(
  ConversationActivityView(
    identity: 'responding',
    kind: ConversationActivityKind.responding,
    turnId: 'turn',
  ),
);

void main() {
  test(
    'a mounted Current body suppresses only its matching responding notice',
    () {
      final current = CurrentAtomSnapshot(
        revision: 3,
        currentAtoms: [_activeText()],
      );

      expect(
        LiveStatusProjection.hasCurrentOutputRenderer(
          current: current,
          renderedCurrentAtomIds: const {'current-body'},
          activeTurnId: 'turn',
          notice: _responding,
        ),
        isTrue,
      );
      expect(
        LiveStatusProjection.projectSurface(
          current: current,
          renderedCurrentAtomIds: const {'current-body'},
          activeTurnId: 'turn',
          rawNotices: const [_responding],
        ),
        isNull,
      );
      expect(
        LiveStatusProjection.hasCurrentOutputRenderer(
          current: current,
          renderedCurrentAtomIds: const {},
          activeTurnId: 'turn',
          notice: _responding,
        ),
        isFalse,
        reason:
            'A Current atom that has not mounted a body must not hide status.',
      );
      expect(
        LiveStatusProjection.hasCurrentOutputRenderer(
          current: current,
          renderedCurrentAtomIds: const {'current-body'},
          activeTurnId: 'another-turn',
          notice: _responding,
        ),
        isFalse,
        reason:
            'Rendered content from another Turn cannot suppress this notice.',
      );
    },
  );
}
