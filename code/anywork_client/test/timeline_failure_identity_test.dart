import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:test/test.dart';

import 'support/conversation_fixture.dart';
import 'support/timeline_transport.dart';

void main() {
  for (final consumerFailure in [false, true]) {
    test(
      '${consumerFailure ? 'consumer' : 'transport'} failure retains original object identity through typed diagnostics and a replacement attempt',
      () async {
        final fixture = ConversationFixture();
        final original = StateError('original failure with private detail');
        final different = StateError('original failure with private detail');
        final session = fixture.select('thread');
        session.timeline.attachConsumer((frame) {
          if (consumerFailure && frame is StudioTimelinePatchFrame)
            throw original;
        });
        final opening = await fixture.timeline.opened(0);
        final native = TestTimelineConnection(initial: baseline(1));
        opening.result.complete(native);
        await session.timeline.ready;
        await pumpEventQueue();
        final attempt = session.timeline.state.value.attemptId;
        final failed = session.timeline.state.waitFor(
          (state) => state.phase == TimelineConnectionPhase.failed,
        );
        if (consumerFailure) {
          native.emit(patch(1, 2));
        } else {
          native.emitOriginalStreamError(original);
        }
        final state = await failed;
        final diagnostic = session.timeline.failure;
        expect(diagnostic!.attemptId, attempt);
        expect(diagnostic.failure, same(state.error));
        expect(diagnostic.failure.code, StudioFailureCode.internal);
        expect(diagnostic.isOriginal(original), isTrue);
        expect(
          diagnostic.isOriginal(different),
          isFalse,
          reason: 'Equal messages cannot substitute another error object',
        );
        expect(diagnostic.toString(), isNot(contains('private detail')));
        expect(native.acks, [
          1,
        ], reason: 'The failed frame/consumer is never acknowledged');

        session.timeline.refresh();
        expect(
          session.timeline.failure,
          isNull,
          reason:
              'A replacement attempt cannot inherit another attempt\'s failure',
        );
        final replacement = await fixture.timeline.opened(1);
        replacement.result.complete(
          TestTimelineConnection(
            initial: baseline(1, subscriptionId: 'replacement'),
          ),
        );
        await session.timeline.ready;
        expect(session.timeline.failure, isNull);
        expect(
          diagnostic.isOriginal(original),
          isTrue,
          reason: 'A borrowed diagnostic retains its original identity after attempt retirement',
        );
        fixture.deselect();
        final report = await fixture.repository.close();
        expect(report.complete, !consumerFailure);
        if (consumerFailure) {
          expect(
            report.unresolved.any(
              (resource) => resource.issues.any(
                (issue) =>
                    issue.diagnostic.stage == 'timeline:consumer' &&
                    issue.recovery == CleanupRecovery.terminal,
              ),
            ),
            isTrue,
          );
        }
        expect(native.disposeCalls, 1);
      },
    );
  }
}
