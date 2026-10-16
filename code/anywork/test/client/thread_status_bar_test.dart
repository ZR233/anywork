import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';

void main() {
  testWidgets(
    'throughput readout keeps the last value when runtime has no new sample',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          _readout(
            threadId: 'thread-1',
            runtime: _runtime(
              contextTokens: 100,
              liveUsage: _liveUsage(
                turnId: 'turn-1',
                attemptId: 'attempt-1',
                completionTokens: 25,
                decodeMillis: 1000,
              ),
            ),
          ),
        ),
      );
      expect(find.text('25 t/s'), findsOneWidget);

      await tester.pumpWidget(
        _harness(
          _readout(
            threadId: 'thread-1',
            runtime: _runtime(
              contextTokens: 200,
              turnCompletionTokens: 0,
              turnDecodeMillis: 0,
            ),
          ),
        ),
      );
      expect(
        find.text('25 t/s'),
        findsOneWidget,
        reason: 'an unrelated runtime update must not clear the readout',
      );
    },
  );

  testWidgets('throughput readout clears for a new partial sample and thread', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _readout(
          threadId: 'thread-1',
          runtime: _runtime(
            contextTokens: 100,
            liveUsage: _liveUsage(
              turnId: 'turn-1',
              attemptId: 'attempt-1',
              completionTokens: 25,
              decodeMillis: 1000,
            ),
          ),
        ),
      ),
    );
    expect(find.text('25 t/s'), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        _readout(
          threadId: 'thread-1',
          runtime: _runtime(
            contextTokens: 120,
            liveUsage: _liveUsage(
              turnId: 'turn-2',
              attemptId: 'attempt-2',
              completionTokens: 10,
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('- t/s'),
      findsOneWidget,
      reason: 'a new incomplete attempt must not borrow the old speed',
    );

    await tester.pumpWidget(
      _harness(
        _readout(
          threadId: 'thread-1',
          runtime: _runtime(
            contextTokens: 140,
            liveUsage: _liveUsage(
              turnId: 'turn-2',
              attemptId: 'attempt-2',
              completionTokens: 20,
              decodeMillis: 500,
              observationSequence: 2,
            ),
          ),
        ),
      ),
    );
    expect(find.text('40 t/s'), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        _readout(
          threadId: 'thread-2',
          runtime: _runtime(turnCompletionTokens: 0, turnDecodeMillis: 0),
        ),
      ),
    );
    expect(
      find.text('- t/s'),
      findsOneWidget,
      reason: 'a new thread must not inherit the previous thread speed',
    );
  });
}

Widget _harness(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

Widget _readout({
  required String threadId,
  required ThreadRuntimeView runtime,
}) {
  return ThreadThroughputReadout(
    key: StudioDriverKeys.threadThroughput,
    threadId: threadId,
    runtime: runtime,
  );
}

ThreadRuntimeView _runtime({
  int contextTokens = 0,
  int turnCompletionTokens = 25,
  int turnDecodeMillis = 1000,
  ThreadRuntimeLiveUsageView? liveUsage,
}) {
  return ThreadRuntimeView(
    model: 'fixture-model',
    contextTokens: contextTokens,
    contextWindow: 128000,
    totalTokens: 100,
    costLabel: '-',
    activeSkills: const [],
    activeMcpServers: const [],
    activeLspServers: const [],
    turnCompletionTokens: turnCompletionTokens,
    turnDecodeMillis: turnDecodeMillis,
    liveUsage: liveUsage,
  );
}

ThreadRuntimeLiveUsageView _liveUsage({
  required String turnId,
  required String attemptId,
  required int completionTokens,
  int? decodeMillis,
  int observationSequence = 1,
}) {
  return ThreadRuntimeLiveUsageView(
    turnId: turnId,
    attemptId: attemptId,
    completionTokens: completionTokens,
    decodeMillis: decodeMillis,
    state: ThreadRuntimeUsageState.live,
    observationSequence: observationSequence,
  );
}
