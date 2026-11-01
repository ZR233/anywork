import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';

import 'frame_timing_observation.dart';

void main() {
  test('batched frame samples retain each engine finish and wall finish', () {
    final frames = [
      FrameTiming(
        vsyncStart: 1000,
        buildStart: 2000,
        buildFinish: 4000,
        rasterStart: 5000,
        rasterFinish: 8000,
        rasterFinishWallTime: 1_700_000_000_008_000,
      ),
      FrameTiming(
        vsyncStart: 10000,
        buildStart: 12000,
        buildFinish: 15000,
        rasterStart: 16000,
        rasterFinish: 20000,
        rasterFinishWallTime: 1_700_000_000_020_000,
      ),
    ];
    final samples = [for (final frame in frames) frameTimingSample(frame)];
    expect(samples.first, {
      'rasterFinishMicros': 8000,
      'rasterFinishWallTimeMicros': 1_700_000_000_008_000,
      'totalMillis': 7.0,
      'vsyncOverheadMillis': 1.0,
      'buildMillis': 2.0,
      'rasterMillis': 3.0,
    });
    expect(samples.last, {
      'rasterFinishMicros': 20000,
      'rasterFinishWallTimeMicros': 1_700_000_000_020_000,
      'totalMillis': 10.0,
      'vsyncOverheadMillis': 2.0,
      'buildMillis': 3.0,
      'rasterMillis': 4.0,
    });
  });
}
