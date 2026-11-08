import 'package:flutter_test/flutter_test.dart';

import '../../tool/profile_timeline_probe.dart';

Map<String, Object?> _observed({
  String threadId = 'thread-a',
  int selectionId = 2,
  int generation = 4,
  int started = 100,
  int completed = 175,
  int elapsed = 75,
}) => {
  'schemaVersion': 1,
  'buildMode': 'profile',
  'status': 'observed',
  'threadId': threadId,
  'selectionId': selectionId,
  'generation': generation,
  'firstContentLayout': {
    'selectionId': selectionId,
    'generation': generation,
    'itemId': 'item-1',
    'selectionStartedMicros': started,
    'layoutCompletedMicros': completed,
    'elapsedMicros': elapsed,
  },
};

List<String> _coldArguments({
  String mode = 'cold',
  String samples = '1',
  String deadline = '30000',
}) => [
  '--vm-url',
  'ws://127.0.0.1:8181/auth-token',
  '--project-id',
  'project-a',
  '--thread-id',
  'thread-a',
  '--mode',
  mode,
  '--samples',
  samples,
  '--output',
  'probe.json',
  '--deadline-ms',
  deadline,
];

void main() {
  group('probe CLI arguments', () {
    test('accepts cold single sample and the bounded default deadline', () {
      final options = parseProbeOptions(_coldArguments());

      expect(options.mode, 'cold');
      expect(options.projectId, 'project-a');
      expect(options.samples, 1);
      expect(options.deadline, const Duration(seconds: 30));
      expect(options.otherThreadId, isNull);
    });

    test('accepts switch samples with a distinct second thread', () {
      final options = parseProbeOptions([
        ..._coldArguments(mode: 'switch', samples: '20'),
        '--other-thread-id',
        'thread-b',
      ]);

      expect(options.mode, 'switch');
      expect(options.samples, 20);
      expect(options.otherThreadId, 'thread-b');
    });

    test('rejects invalid sample count and cold counts other than one', () {
      expect(
        () => parseProbeOptions(_coldArguments(samples: '0')),
        throwsFormatException,
      );
      expect(
        () => parseProbeOptions(_coldArguments(samples: '2')),
        throwsFormatException,
      );
      expect(
        () => parseProbeOptions(_coldArguments(mode: 'switch', samples: '101')),
        throwsFormatException,
      );
    });

    test('requires distinct A and B for switch and rejects B for cold', () {
      expect(
        () => parseProbeOptions(_coldArguments(mode: 'switch', samples: '1')),
        throwsFormatException,
      );
      expect(
        () => parseProbeOptions([
          ..._coldArguments(mode: 'switch'),
          '--other-thread-id',
          'thread-a',
        ]),
        throwsFormatException,
      );
      expect(
        () => parseProbeOptions([
          ..._coldArguments(),
          '--other-thread-id',
          'thread-b',
        ]),
        throwsFormatException,
      );
    });

    test('validates deadline and native VM Service URI boundaries', () {
      expect(
        () => parseProbeOptions(_coldArguments(deadline: '0')),
        throwsFormatException,
      );
      expect(
        () => parseProbeOptions(_coldArguments(deadline: '120001')),
        throwsFormatException,
      );
      final badUri = _coldArguments()..[1] = 'https://127.0.0.1:8181/';
      expect(() => parseProbeOptions(badUri), throwsFormatException);
    });
  });

  group('timeline layout RPC schema', () {
    test('parses a matching profile observation and preserves owner span', () {
      final observation = TimelineObservation.parse(_observed());

      expect(observation.status, 'observed');
      expect(observation.threadId, 'thread-a');
      expect(observation.firstContentLayout!.elapsedMicros, 75);
    });

    test('accepts pending without treating it as an observed span', () {
      final observation = TimelineObservation.parse({
        'schemaVersion': 1,
        'buildMode': 'profile',
        'status': 'pending',
        'threadId': 'thread-a',
        'selectionId': 2,
        'generation': 4,
        'firstContentLayout': null,
      });

      expect(observation.isObserved, isFalse);
      expect(observation.firstContentLayout, isNull);
    });

    test('rejects schema, mode, status, and unexpected fields', () {
      final unsupported = _observed()..['schemaVersion'] = 2;
      final debug = _observed()..['buildMode'] = 'debug';
      final unknownStatus = _observed()..['status'] = 'complete';
      final extraField = _observed()..['authUri'] = 'must-not-be-returned';

      for (final response in [unsupported, debug, unknownStatus, extraField]) {
        expect(
          () => TimelineObservation.parse(response),
          throwsFormatException,
        );
      }
    });

    test('rejects incomplete identity and inconsistent selection identity', () {
      final missingIdentity = _observed()..['threadId'] = null;
      final mismatched = _observed();
      (mismatched['firstContentLayout']!
              as Map<String, Object?>)['generation'] =
          5;

      expect(
        () => TimelineObservation.parse(missingIdentity),
        throwsFormatException,
      );
      expect(
        () => TimelineObservation.parse(mismatched),
        throwsFormatException,
      );
    });

    test(
      'rejects negative, reversed, or arithmetically inconsistent timing',
      () {
        final negative = _observed(started: -1);
        final reversed = _observed(started: 200, completed: 100, elapsed: -100);
        final wrongElapsed = _observed(elapsed: 74);

        for (final response in [negative, reversed, wrongElapsed]) {
          expect(
            () => TimelineObservation.parse(response),
            throwsFormatException,
          );
        }
      },
    );
  });

  group('switch observation freshness', () {
    test('treats valid old thread or generation observations as not ready', () {
      final oldThread = TimelineObservation.parse(
        _observed(threadId: 'thread-a', selectionId: 7, generation: 9),
      );
      final oldGeneration = TimelineObservation.parse(
        _observed(threadId: 'thread-b', selectionId: 8, generation: 9),
      );
      final fresh = TimelineObservation.parse(
        _observed(threadId: 'thread-b', selectionId: 8, generation: 10),
      );

      bool isReady(TimelineObservation observation) => isFreshObservation(
        observation,
        threadId: 'thread-b',
        afterSelectionId: 7,
        afterGeneration: 9,
      );

      expect(isReady(oldThread), isFalse);
      expect(isReady(oldGeneration), isFalse);
      expect(isReady(fresh), isTrue);
    });

    test('requires requested thread and strictly advancing selection and generation', () {
      final previous = TimelineObservation.parse(
        _observed(threadId: 'thread-b', selectionId: 7, generation: 9),
      );
      final next = TimelineObservation.parse(
        _observed(threadId: 'thread-a', selectionId: 8, generation: 10),
      );

      expect(
        requireFreshObservation(
          next,
          threadId: 'thread-a',
          afterSelectionId: previous.selectionId!,
          afterGeneration: previous.generation!,
        ).itemId,
        'item-1',
      );
      for (final stale in [
        _observed(threadId: 'thread-a', selectionId: 7, generation: 10),
        _observed(threadId: 'thread-a', selectionId: 8, generation: 9),
        _observed(threadId: 'thread-b', selectionId: 8, generation: 10),
      ]) {
        expect(
          () => requireFreshObservation(
            TimelineObservation.parse(stale),
            threadId: 'thread-a',
            afterSelectionId: previous.selectionId!,
            afterGeneration: previous.generation!,
          ),
          throwsFormatException,
        );
      }
    });
  });
}
