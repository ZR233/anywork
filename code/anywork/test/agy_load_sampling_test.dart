import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/agy_load_sampling.dart';

void main() {
  test(
    'slow captures coalesce, stay serial and join accepted pending work',
    () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final secondStarted = Completer<void>();
      var calls = 0;
      var active = 0;
      final samples = AgyLoadSampling(() async {
        expect(++active, 1);
        calls++;
        if (calls == 1) await first.future;
        if (calls == 2) {
          secondStarted.complete();
          await second.future;
        }
        active--;
      });
      samples.request();
      for (var i = 0; i < 20; i++) {
        samples.request();
      }
      expect(samples.diagnostics['started'], 1);
      expect(samples.diagnostics['pending'], isTrue);
      samples.closeAdmission();
      samples.request();
      var drained = false;
      final drain = samples.drain().then((_) => drained = true);
      first.complete();
      await secondStarted.future;
      expect(drained, isFalse);
      expect(calls, 2);
      second.complete();
      await drain;
      expect(samples.diagnostics['coalesced'], 20);
      expect(samples.diagnostics['rejectedAfterClose'], 1);
      expect(samples.diagnostics['completed'], 2);
      expect(samples.diagnostics['pending'], isFalse);
      expect(samples.diagnostics['inFlight'], isFalse);
      await samples.finalSample();
      expect(calls, 3);
      await expectLater(samples.finalSample(), throwsStateError);
    },
  );

  test(
    'errors remain visible after drain and the explicit final capture',
    () async {
      final error = StateError('synthetic capture failure');
      var calls = 0;
      final samples = AgyLoadSampling(() async {
        if (++calls == 1) throw error;
      });
      samples.request();
      samples.closeAdmission();
      await expectLater(samples.drain(), throwsA(same(error)));
      await expectLater(samples.finalSample(), throwsA(same(error)));
      expect(calls, 2);
      expect(samples.diagnostics['completed'], 2);
      expect(samples.diagnostics['inFlight'], isFalse);
    },
  );

  test(
    'empty admission drains without work and owns one final capture',
    () async {
      var calls = 0;
      final samples = AgyLoadSampling(() async => calls++);
      await expectLater(samples.finalSample(), throwsStateError);
      samples.closeAdmission();
      await samples.drain();
      expect(calls, 0);
      await samples.finalSample();
      expect(calls, 1);
    },
  );
}
