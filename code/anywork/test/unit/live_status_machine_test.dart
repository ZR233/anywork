import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork_client/models.dart' as feed;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the reconnect snapshot uses the retry delay relative to receipt time',
    () {
      final receivedAt = DateTime.utc(2026);
      final view = LiveStatusMachine.project(
        'thread-main',
        feed.LiveStatusSnapshot(
          revision: 3,
          phase: const feed.LiveStatusReconnecting(
            attemptId: 'retry-1',
            message: 'Request failed',
            retryAfterMs: 2500,
            attempt: 2,
          ),
          attentions: const [],
          suppressedByInteraction: false,
        ),
        receivedAt: receivedAt,
      );
      final retry =
          (view.gate as LiveStatusPresenting).presentation.primary!
              as LiveReconnectingPhase;
      expect(retry.detail, 'Request failed');
      expect(retry.attempt, 2);
      expect(retry.retryAt, receivedAt.add(const Duration(milliseconds: 2500)));
    },
  );

  test('storage severity comes from typed flags', () {
    const paused = feed.ThreadStorageExecution.paused;
    for (final (storage, expected) in [
      (null, LiveStorageSeverity.fault),
      (
        const feed.ThreadStorageStateView(
          execution: paused,
          pressurePaused: true,
        ),
        LiveStorageSeverity.pressure,
      ),
      (
        const feed.ThreadStorageStateView(execution: paused),
        LiveStorageSeverity.paused,
      ),
      (
        const feed.ThreadStorageStateView(
          execution: paused,
          resumeRequired: true,
        ),
        LiveStorageSeverity.resumeRequired,
      ),
      (
        const feed.ThreadStorageStateView(
          execution: paused,
          resumeRequired: true,
          canResume: true,
        ),
        LiveStorageSeverity.resumeReady,
      ),
    ]) {
      expect(
        LiveStorageSeverity.fromStorage(storage),
        expected,
        reason: expected.name,
      );
    }
  });
}
